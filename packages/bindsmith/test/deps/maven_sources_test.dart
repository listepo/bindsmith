import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bindsmith/src/deps/lockfile.dart';
import 'package:bindsmith/src/deps/maven.dart';
import 'package:bindsmith/src/drivers/jvm/kdoc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _project(String body) =>
    '<project xmlns="http://maven.apache.org/POM/4.0.0">\n'
    '  <modelVersion>4.0.0</modelVersion>\n'
    '$body\n'
    '</project>';

String _self(String coordinate) {
  final parts = coordinate.split(':');
  return '  <groupId>${parts[0]}</groupId>\n'
      '  <artifactId>${parts[1]}</artifactId>\n'
      '  <version>${parts[2]}</version>';
}

final class _Repo {
  _Repo([String base = 'https://example.invalid/maven2/'])
    : base = Uri.parse(base);

  final Uri base;
  final _files = <String, List<int>>{};
  final requested = <String>[];

  void add(String coordinate, String extension, List<int> bytes) =>
      _files[Coordinate.parse(coordinate).uri(base, extension).path] = bytes;

  void pom(String coordinate, [String body = '']) => add(
    coordinate,
    'pom',
    utf8.encode(_project('${_self(coordinate)}\n$body')),
  );

  void jar(String coordinate) =>
      add(coordinate, 'jar', utf8.encode('jar of $coordinate'));

  void sourcesJar(String coordinate, List<int> bytes) =>
      add('$coordinate:sources', 'jar', bytes);

  Future<Uint8List> fetch(Uri url) async {
    requested.add(url.path);
    final bytes = _files[url.path];
    if (bytes == null) throw MavenException('GET $url returned HTTP 404');
    return Uint8List.fromList(bytes);
  }
}

Uint8List _sourcesZip({String? java, String? kotlin}) {
  final archive = Archive();
  if (java != null) {
    archive.add(ArchiveFile.string('com/example/Demo.java', java));
  }
  if (kotlin != null) {
    archive.add(ArchiveFile.string('com/example/Demo.kt', kotlin));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late Directory cache;
  late Directory root;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('bindsmith_maven_src_');
    root = Directory.systemTemp.createTempSync('bindsmith_maven_root_');
  });
  tearDown(() {
    cache.deleteSync(recursive: true);
    root.deleteSync(recursive: true);
  });

  MavenResolver resolver(_Repo repo) =>
      MavenResolver(cache: cache, repositories: [repo.base], fetch: repo.fetch);

  group('fetchSources', () {
    test(
      'fetches sources for directs that publish them and skips the rest',
      () async {
        final repo = _Repo()
          ..pom('g:with:1.0')
          ..jar('g:with:1.0')
          ..sourcesJar(
            'g:with:1.0',
            _sourcesZip(java: '/** Greeter. */\npackage com.example;\n'),
          )
          ..pom('g:without:1.0')
          ..jar('g:without:1.0');

        final r = resolver(repo);
        final resolved = await r.resolve(['g:with:1.0', 'g:without:1.0']);
        expect(resolved.map((a) => a.coordinate.toString()), [
          'g:with:1.0',
          'g:without:1.0',
        ]);

        final sources = await r.fetchSources(['g:with:1.0', 'g:without:1.0']);
        expect(sources.map((a) => a.coordinate.toString()), [
          'g:with:1.0:sources',
        ]);
      },
    );

    test('does not fetch sources for transitive dependencies', () async {
      final repo = _Repo()
        ..pom('g:root:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>leaf</artifactId><version>1.0</version>
    </dependency>
  </dependencies>''')
        ..pom('g:leaf:1.0')
        ..jar('g:root:1.0')
        ..jar('g:leaf:1.0')
        ..sourcesJar('g:leaf:1.0', _sourcesZip(kotlin: '/** leaf */\n'));

      final r = resolver(repo);
      await r.resolve(['g:root:1.0']);
      repo.requested.clear();
      final sources = await r.fetchSources(['g:root:1.0']);
      expect(sources, isEmpty);
      expect(
        repo.requested.where((path) => path.contains('leaf-1.0-sources.jar')),
        isEmpty,
        reason: 'transitive coordinates never get a sources fetch',
      );
    });

    test('round-trips sources through the lockfile as g:a:v:sources', () {
      final lock = Lockfile({
        'maven': [
          (coordinate: 'g:with:1.0', extension: 'jar', sha256: 'a' * 64),
          (
            coordinate: 'g:with:1.0:sources',
            extension: 'jar',
            sha256: 'b' * 64,
          ),
        ],
      });
      final parsed = parseLockfile(writeLockfile(lock));
      expect(parsed.artifacts['maven']!.map((a) => a.coordinate), [
        'g:with:1.0',
        'g:with:1.0:sources',
      ]);
    });

    test(
      'offline run serves cached sources and never asks the network',
      () async {
        final repo = _Repo()
          ..pom('g:with:1.0')
          ..jar('g:with:1.0')
          ..sourcesJar('g:with:1.0', _sourcesZip(kotlin: '/** cached */\n'))
          ..pom('g:plain:1.0')
          ..jar('g:plain:1.0');

        final online = resolver(repo);
        final sources = await online.fetchSources([
          'g:with:1.0',
          'g:plain:1.0',
        ]);
        expect(sources.single.coordinate.toString(), 'g:with:1.0:sources');
        expect(repo.requested, isNotEmpty);

        repo.requested.clear();
        final offline = MavenResolver(
          cache: cache,
          repositories: [repo.base],
          fetch: (url) async => throw const MavenException('offline'),
        );
        final second = await offline.fetchSources(['g:with:1.0']);
        expect(second.single.sha256, sources.single.sha256);
        expect(repo.requested, isEmpty);

        await expectLater(
          offline.fetchSources(['g:missing:1.0']),
          completion(isEmpty),
        );
      },
    );

    test(
      'mavenSourceDocs unpacks kotlin for kdocs and java trees for jnigen',
      () async {
        final repo = _Repo()
          ..pom('g:demo:1.0')
          ..jar('g:demo:1.0')
          ..sourcesJar(
            'g:demo:1.0',
            _sourcesZip(
              java: '/** Java doc. */\npackage com.example;\nclass Demo {}\n',
              kotlin: '''
package example

/** Greets [name]. */
class Greeter {
  /** Says hello. */
  fun greet(name: String) {}
}
''',
            ),
          );

        final projectCache = Directory(
          p.join(root.path, '.dart_tool', 'maven'),
        );
        final projectResolver = MavenResolver(
          cache: projectCache,
          repositories: [repo.base],
          fetch: repo.fetch,
        );
        await projectResolver.resolve(['g:demo:1.0']);
        final projectSources = await projectResolver.fetchSources([
          'g:demo:1.0',
        ]);
        final projectDocs = mavenSourceDocs(projectSources, root: root.path);

        expect(projectDocs.javaDirs, hasLength(1));
        expect(projectDocs.kotlinFiles, hasLength(1));
        expect(projectDocs.javaDirs.single, startsWith('.dart_tool/maven/'));

        final map = kdocs(
          File(p.join(root.path, projectDocs.kotlinFiles.single))
              .readAsStringSync(),
          fileName: p.basename(projectDocs.kotlinFiles.single),
        );
        expect(
          map['example.Greeter.greet(name)']?.memberDocs,
          contains('Says hello'),
        );
        expect(map['example.Greeter']?.memberDocs, contains('Greets'));
      },
    );
  });
}
