import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bindsmith/bindsmith.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

/// Wraps [body] in the POM envelope, namespace included, so the tests exercise
/// the same document shape Maven Central serves.
String _project(String body) =>
    '<project xmlns="http://maven.apache.org/POM/4.0.0">\n'
    '  <modelVersion>4.0.0</modelVersion>\n'
    '$body\n'
    '</project>';

/// The three coordinate elements, for a POM that declares its own.
String _self(String coordinate) {
  final parts = coordinate.split(':');
  return '  <groupId>${parts[0]}</groupId>\n'
      '  <artifactId>${parts[1]}</artifactId>\n'
      '  <version>${parts[2]}</version>';
}

/// An in-memory Maven repository, so resolution is tested without a network.
final class _Repo {
  _Repo([String base = 'https://example.invalid/maven2/'])
    : base = Uri.parse(base);

  final Uri base;
  final _files = <String, List<int>>{};

  /// Every path fetched, in order — what proves the second run stays offline.
  final requested = <String>[];

  void add(String coordinate, String extension, List<int> bytes) =>
      _files[Coordinate.parse(coordinate).uri(base, extension).path] = bytes;

  /// Registers a POM that declares its own coordinates, plus [body].
  void pom(String coordinate, [String body = '']) => add(
    coordinate,
    'pom',
    utf8.encode(_project('${_self(coordinate)}\n$body')),
  );

  /// Registers a POM exactly as given: for parents, BOMs and inheritance.
  void raw(String coordinate, String body) =>
      add(coordinate, 'pom', utf8.encode(_project(body)));

  void jar(String coordinate) =>
      add(coordinate, 'jar', utf8.encode('jar of $coordinate'));

  Future<Uint8List> fetch(Uri url) async {
    requested.add(url.path);
    final bytes = _files[url.path];
    if (bytes == null) throw MavenException('GET $url returned HTTP 404');
    return Uint8List.fromList(bytes);
  }
}

/// A minimal Android library archive: a zip carrying a `classes.jar`.
Uint8List _aar(String classes) {
  final archive = Archive()
    ..add(ArchiveFile.string('AndroidManifest.xml', '<manifest/>'))
    ..add(ArchiveFile.string('classes.jar', classes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('bindsmith_maven_'));
  tearDown(() => cache.deleteSync(recursive: true));

  MavenResolver resolver(_Repo repo) =>
      MavenResolver(cache: cache, repositories: [repo.base], fetch: repo.fetch);

  group('coordinates', () {
    test('parse the three-part form and lay out a repository path', () {
      final c = Coordinate.parse('com.google.code.gson:gson:2.11.0');
      expect(c.group, 'com.google.code.gson');
      expect(c.artifact, 'gson');
      expect(c.version, '2.11.0');
      expect(c.module, 'com.google.code.gson:gson');
      expect(
        c.uri(mavenCentral, 'jar').toString(),
        'https://repo1.maven.org/maven2/com/google/code/gson/gson/2.11.0/'
        'gson-2.11.0.jar',
      );
    });

    test('a repository without a trailing slash still resolves under it', () {
      final r = MavenResolver(
        cache: Directory.systemTemp,
        repositories: [Uri.parse('https://example.invalid/m2')],
      );
      expect(r.repositories.single.toString(), 'https://example.invalid/m2/');
      expect(
        Coordinate.parse('g:a:1.0').uri(r.repositories.single, 'jar').path,
        '/m2/g/a/1.0/a-1.0.jar',
      );
    });

    test('rejects coordinates that are not three or four parts', () {
      for (final bad in ['gson', 'a:b', 'a:b:c:d:e', 'a::1.0']) {
        expect(() => Coordinate.parse(bad), throwsArgumentError, reason: bad);
      }
      expect(Coordinate.parse('g:a:1.0:sources').toString(), 'g:a:1.0:sources');
    });

    test('a classifier picks a sibling file of the main artifact', () {
      const c = Coordinate('g', 'a', '1.0', classifier: 'linux-x86_64');
      expect(c.fileName('jar'), 'a-1.0-linux-x86_64.jar');
      expect(c.module, 'g:a');
    });
  });

  group('Pom.parse', () {
    test('reads coordinates, parent, packaging and properties', () {
      final pom = Pom.parse(
        _project('''
  <parent>
    <groupId>com.google.code.gson</groupId>
    <artifactId>gson-parent</artifactId>
    <version>2.11.0</version>
  </parent>
  <artifactId>gson</artifactId>
  <packaging>bundle</packaging>
  <properties>
    <junit.version>4.13.2</junit.version>
  </properties>'''),
      );
      expect(pom.artifact, 'gson');
      expect(pom.group, isNull, reason: 'inherited from the parent');
      expect(pom.version, isNull, reason: 'inherited from the parent');
      expect(pom.parent.toString(), 'com.google.code.gson:gson-parent:2.11.0');
      expect(pom.packaging, 'bundle');
      expect(pom.properties, {'junit.version': '4.13.2'});
    });

    test('defaults packaging to jar and keeps dependencies empty', () {
      final pom = Pom.parse(_project(_self('g:a:1.0')));
      expect(pom.packaging, 'jar');
      expect(pom.dependencies, isEmpty);
      expect(pom.managed, isEmpty);
      expect(pom.properties, isEmpty);
    });

    test('reads scope, optional, type, classifier and exclusions', () {
      final pom = Pom.parse(
        _project('''
${_self('g:a:1.0')}
  <dependencies>
    <dependency>
      <groupId>g</groupId>
      <artifactId>plain</artifactId>
      <version>1.0</version>
    </dependency>
    <dependency>
      <groupId>g</groupId>
      <artifactId>testing</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>g</groupId>
      <artifactId>extra</artifactId>
      <version>2.0</version>
      <optional>true</optional>
      <classifier>linux-x86_64</classifier>
      <type>so</type>
      <exclusions>
        <exclusion>
          <groupId>junk</groupId>
          <artifactId>*</artifactId>
        </exclusion>
      </exclusions>
    </dependency>
  </dependencies>'''),
      );
      expect(pom.dependencies.map((d) => d.module), [
        'g:plain',
        'g:testing',
        'g:extra',
      ]);
      final plain = pom.dependencies[0];
      expect(plain.scope, 'compile', reason: 'the default scope');
      expect(plain.type, 'jar');
      expect(plain.optional, isFalse);
      expect(pom.dependencies[1].scope, 'test');
      expect(pom.dependencies[1].version, isNull);
      final extra = pom.dependencies[2];
      expect(extra.optional, isTrue);
      expect(extra.classifier, 'linux-x86_64');
      expect(extra.type, 'so');
      expect(extra.exclusions, {'junk:*'});
    });

    test('separates dependencyManagement from dependencies', () {
      final pom = Pom.parse(
        _project('''
${_self('g:a:1.0')}
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>g</groupId>
        <artifactId>pinned</artifactId>
        <version>3.0</version>
      </dependency>
    </dependencies>
  </dependencyManagement>'''),
      );
      expect(pom.managed.single.module, 'g:pinned');
      expect(pom.managed.single.version, '3.0');
      expect(pom.dependencies, isEmpty);
    });

    test('ignores the dependencies a build plugin declares', () {
      // The real gson POM carries a proguard plugin with its own
      // <dependencies>; those belong to the build, not to the classpath, and a
      // lookup that is not by direct child picks them up.
      final pom = Pom.parse(
        _project('''
${_self('g:a:1.0')}
  <build>
    <plugins>
      <plugin>
        <groupId>com.github.wvengen</groupId>
        <artifactId>proguard-maven-plugin</artifactId>
        <dependencies>
          <dependency>
            <groupId>com.guardsquare</groupId>
            <artifactId>proguard-base</artifactId>
            <version>7.4.2</version>
          </dependency>
        </dependencies>
      </plugin>
    </plugins>
  </build>'''),
      );
      expect(pom.dependencies, isEmpty);
    });

    test('a comment around an element is not read as its text', () {
      final pom = Pom.parse(
        _project('''
${_self('g:a:1.0')}
  <!-- Apache-2.0, see the root pom -->
  <packaging><!-- OSGi -->bundle</packaging>'''),
      );
      expect(pom.packaging, 'bundle');
    });

    test('a document that is not a POM is rejected', () {
      expect(
        () => Pom.parse('<manifest><application/></manifest>'),
        throwsA(isA<MavenException>()),
      );
    });
  });

  group('resolve', () {
    test('walks the transitive graph and skips test scope', () async {
      final repo = _Repo()
        ..pom('g:root:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>mid</artifactId><version>1.0</version>
    </dependency>
    <dependency>
      <groupId>g</groupId><artifactId>junit</artifactId>
      <version>4.13.2</version><scope>test</scope>
    </dependency>
  </dependencies>''')
        ..pom('g:mid:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>leaf</artifactId><version>1.0</version>
    </dependency>
  </dependencies>''')
        ..pom('g:leaf:1.0')
        ..jar('g:root:1.0')
        ..jar('g:mid:1.0')
        ..jar('g:leaf:1.0');

      final resolved = await resolver(repo).resolve(['g:root:1.0']);
      expect(resolved.map((a) => a.coordinate.toString()), [
        'g:root:1.0',
        'g:mid:1.0',
        'g:leaf:1.0',
      ], reason: 'breadth first, requested coordinates first');
      expect(
        repo.requested.where((path) => path.contains('junit')),
        isEmpty,
        reason: 'a test-scope dependency is never even fetched',
      );
    });

    test('an optional dependency is not inherited', () async {
      final repo = _Repo()
        ..pom('g:root:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>extra</artifactId>
      <version>1.0</version><optional>true</optional>
    </dependency>
  </dependencies>''')
        ..jar('g:root:1.0');
      final resolved = await resolver(repo).resolve(['g:root:1.0']);
      expect(resolved.map((a) => a.coordinate.artifact), ['root']);
    });

    test(
      'a direct provided dependency is kept, a transitive one is not',
      () async {
        // Maven puts a directly declared `provided` dependency on the compile
        // classpath and stops there; jnigen needs the same, or a supertype the
        // API mentions goes missing.
        final repo = _Repo()
          ..pom('g:root:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>api</artifactId>
      <version>1.0</version><scope>provided</scope>
    </dependency>
  </dependencies>''')
          ..pom('g:api:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>deep</artifactId>
      <version>1.0</version><scope>provided</scope>
    </dependency>
  </dependencies>''')
          ..jar('g:root:1.0')
          ..jar('g:api:1.0');
        final resolved = await resolver(repo).resolve(['g:root:1.0']);
        expect(resolved.map((a) => a.coordinate.artifact), ['root', 'api']);
      },
    );

    test('a version comes from the parent dependencyManagement', () async {
      final repo = _Repo()
        ..raw('g:parent:1.0', '''
${_self('g:parent:1.0')}
  <packaging>pom</packaging>
  <properties>
    <leaf.version>2.5</leaf.version>
  </properties>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>g</groupId><artifactId>leaf</artifactId>
        <version>\${leaf.version}</version>
      </dependency>
    </dependencies>
  </dependencyManagement>''')
        ..raw('g:root:1.0', '''
  <parent>
    <groupId>g</groupId><artifactId>parent</artifactId><version>1.0</version>
  </parent>
  <artifactId>root</artifactId>
  <dependencies>
    <dependency><groupId>g</groupId><artifactId>leaf</artifactId></dependency>
  </dependencies>''')
        ..pom('g:leaf:2.5')
        ..jar('g:root:1.0')
        ..jar('g:leaf:2.5');

      final resolved = await resolver(repo).resolve(['g:root:1.0']);
      expect(resolved.map((a) => a.coordinate.toString()), [
        'g:root:1.0',
        'g:leaf:2.5',
      ]);
    });

    test(
      'an imported BOM supplies versions, a local pin overrides it',
      () async {
        final repo = _Repo()
          ..raw('g:bom:1.0', '''
${_self('g:bom:1.0')}
  <packaging>pom</packaging>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>g</groupId><artifactId>a</artifactId><version>1.0</version>
      </dependency>
      <dependency>
        <groupId>g</groupId><artifactId>b</artifactId><version>1.0</version>
      </dependency>
    </dependencies>
  </dependencyManagement>''')
          ..pom('g:root:1.0', '''
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>g</groupId><artifactId>bom</artifactId><version>1.0</version>
        <type>pom</type><scope>import</scope>
      </dependency>
      <dependency>
        <groupId>g</groupId><artifactId>b</artifactId><version>2.0</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
  <dependencies>
    <dependency><groupId>g</groupId><artifactId>a</artifactId></dependency>
    <dependency><groupId>g</groupId><artifactId>b</artifactId></dependency>
  </dependencies>''')
          ..pom('g:a:1.0')
          ..pom('g:b:2.0')
          ..jar('g:root:1.0')
          ..jar('g:a:1.0')
          ..jar('g:b:2.0');

        final resolved = await resolver(repo).resolve(['g:root:1.0']);
        expect(resolved.map((a) => a.coordinate.toString()), [
          'g:root:1.0',
          'g:a:1.0',
          'g:b:2.0',
        ]);
      },
    );

    test('an exclusion applies to the whole subtree below it', () async {
      final repo = _Repo()
        ..pom('g:root:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>mid</artifactId><version>1.0</version>
      <exclusions>
        <exclusion><groupId>g</groupId><artifactId>junk</artifactId></exclusion>
      </exclusions>
    </dependency>
  </dependencies>''')
        ..pom('g:mid:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>leaf</artifactId><version>1.0</version>
    </dependency>
  </dependencies>''')
        ..pom('g:leaf:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>junk</artifactId><version>1.0</version>
    </dependency>
  </dependencies>''')
        ..jar('g:root:1.0')
        ..jar('g:mid:1.0')
        ..jar('g:leaf:1.0');

      final resolved = await resolver(repo).resolve(['g:root:1.0']);
      expect(resolved.map((a) => a.coordinate.artifact), [
        'root',
        'mid',
        'leaf',
      ]);
    });

    test('the nearest definition of a module wins', () async {
      final repo = _Repo()
        ..pom('g:root:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>mid</artifactId><version>1.0</version>
    </dependency>
    <dependency>
      <groupId>g</groupId><artifactId>leaf</artifactId><version>2.0</version>
    </dependency>
  </dependencies>''')
        ..pom('g:mid:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>leaf</artifactId><version>1.0</version>
    </dependency>
  </dependencies>''')
        ..pom('g:leaf:2.0')
        ..jar('g:root:1.0')
        ..jar('g:mid:1.0')
        ..jar('g:leaf:2.0');

      final resolved = await resolver(repo).resolve(['g:root:1.0']);
      expect(resolved.map((a) => a.coordinate.toString()), [
        'g:root:1.0',
        'g:mid:1.0',
        'g:leaf:2.0',
      ]);
      expect(
        repo.requested.where((path) => path.contains('leaf/1.0')),
        isEmpty,
        reason: 'the losing version is never fetched',
      );
    });

    test(
      'a pom packaging contributes metadata but no classpath entry',
      () async {
        final repo = _Repo()
          ..pom('g:root:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>agg</artifactId><version>1.0</version>
      <type>pom</type>
    </dependency>
  </dependencies>''')
          ..raw('g:agg:1.0', '''
${_self('g:agg:1.0')}
  <packaging>pom</packaging>''')
          ..jar('g:root:1.0');

        final resolved = await resolver(repo).resolve(['g:root:1.0']);
        expect(resolved.map((a) => a.coordinate.artifact), ['root']);
      },
    );

    test('an aar is unpacked to the classes.jar inside it', () async {
      final repo = _Repo()
        ..raw('g:widget:1.0', '''
${_self('g:widget:1.0')}
  <packaging>aar</packaging>''')
        ..add('g:widget:1.0', 'aar', _aar('the compiled classes'));

      final resolved = await resolver(repo).resolve(['g:widget:1.0']);
      final artifact = resolved.single;
      expect(artifact.file.path, endsWith('widget-1.0.classes.jar'));
      expect(artifact.file.readAsStringSync(), 'the compiled classes');
      expect(
        artifact.extension,
        'aar',
        reason: 'the lock pins the published file, not what came out of it',
      );
    });

    test(
      'a dependency the first repository lacks comes from the next',
      () async {
        // The case this exists for: an AndroidX `aar` is served by Google's
        // repository, and the Kotlin artifact it depends on only Central has.
        final google = _Repo('https://google.invalid/maven2/')
          ..raw('g:widget:1.0', '''
${_self('g:widget:1.0')}
  <packaging>aar</packaging>
  <dependencies>
    <dependency>
      <groupId>k</groupId><artifactId>stdlib</artifactId><version>2.0</version>
    </dependency>
  </dependencies>''')
          ..add('g:widget:1.0', 'aar', _aar('widget classes'));
        final central = _Repo('https://central.invalid/maven2/')
          ..pom('k:stdlib:2.0')
          ..jar('k:stdlib:2.0');

        final resolved = await MavenResolver(
          cache: cache,
          repositories: [google.base, central.base],
          fetch: (url) => url.host == google.base.host
              ? google.fetch(url)
              : central.fetch(url),
        ).resolve(['g:widget:1.0']);

        expect(resolved.map((a) => a.coordinate.toString()), [
          'g:widget:1.0',
          'k:stdlib:2.0',
        ]);
        expect(resolved.first.file.readAsStringSync(), 'widget classes');
      },
    );

    test(
      'a coordinate no repository has names every one that was tried',
      () async {
        final a = _Repo('https://a.invalid/m2/');
        final b = _Repo('https://b.invalid/m2/');
        await expectLater(
          MavenResolver(
            cache: cache,
            repositories: [a.base, b.base],
            fetch: (url) =>
                url.host == a.base.host ? a.fetch(url) : b.fetch(url),
          ).resolve(['g:missing:1.0']),
          throwsA(
            isA<MavenException>().having(
              (e) => e.message,
              'message',
              allOf(contains('a.invalid'), contains('b.invalid')),
            ),
          ),
        );
      },
    );

    test('an aar with no classes.jar is reported, not skipped', () async {
      final empty = Archive()
        ..add(ArchiveFile.string('AndroidManifest.xml', '<manifest/>'));
      final repo = _Repo()
        ..raw('g:widget:1.0', '''
${_self('g:widget:1.0')}
  <packaging>aar</packaging>''')
        ..add('g:widget:1.0', 'aar', ZipEncoder().encode(empty));

      await expectLater(
        resolver(repo).resolve(['g:widget:1.0']),
        throwsA(
          isA<MavenException>().having(
            (e) => e.message,
            'message',
            contains('classes.jar'),
          ),
        ),
      );
    });

    test('the digest is of the published bytes', () async {
      final repo = _Repo()
        ..pom('g:root:1.0')
        ..jar('g:root:1.0');
      final artifact = (await resolver(repo).resolve(['g:root:1.0'])).single;
      expect(artifact.extension, 'jar');
      expect(
        artifact.sha256,
        crypto.sha256.convert(utf8.encode('jar of g:root:1.0')).toString(),
      );
      expect(artifact.file.readAsStringSync(), 'jar of g:root:1.0');
    });

    test(
      'a second run over the same cache asks the network for nothing',
      () async {
        final repo = _Repo()
          ..pom('g:root:1.0', '''
  <dependencies>
    <dependency>
      <groupId>g</groupId><artifactId>leaf</artifactId><version>1.0</version>
    </dependency>
  </dependencies>''')
          ..pom('g:leaf:1.0')
          ..jar('g:root:1.0')
          ..jar('g:leaf:1.0');

        final first = await resolver(repo).resolve(['g:root:1.0']);
        expect(repo.requested, isNotEmpty);

        final offline = MavenResolver(
          cache: cache,
          repositories: [repo.base],
          fetch: (url) async => throw const MavenException('offline'),
        );
        final second = await offline.resolve(['g:root:1.0']);
        expect(
          second.map((a) => (a.coordinate.toString(), a.sha256, a.file.path)),
          first.map((a) => (a.coordinate.toString(), a.sha256, a.file.path)),
        );
      },
    );

    test('a version that cannot be pinned is refused by name', () async {
      final repo = _Repo();
      for (final version in [
        '1.0-SNAPSHOT',
        'LATEST',
        'RELEASE',
        '[1.0,2.0)',
      ]) {
        await expectLater(
          resolver(repo).resolve(['g:a:$version']),
          throwsA(isA<MavenException>()),
          reason: version,
        );
      }
    });

    test('a dependency nothing pins names itself in the error', () async {
      final repo = _Repo()
        ..pom('g:root:1.0', '''
  <dependencies>
    <dependency><groupId>g</groupId><artifactId>leaf</artifactId></dependency>
  </dependencies>''');
      await expectLater(
        resolver(repo).resolve(['g:root:1.0']),
        throwsA(
          isA<MavenException>().having(
            (e) => e.message,
            'message',
            allOf(contains('g:leaf'), contains('g:root:1.0')),
          ),
        ),
      );
    });

    test(
      'a parent chain that loops is reported instead of overflowing',
      () async {
        final repo = _Repo()
          ..raw('g:a:1.0', '''
  <parent><groupId>g</groupId><artifactId>b</artifactId><version>1.0</version>
  </parent>
  <artifactId>a</artifactId>''')
          ..raw('g:b:1.0', '''
  <parent><groupId>g</groupId><artifactId>a</artifactId><version>1.0</version>
  </parent>
  <artifactId>b</artifactId>''');
        await expectLater(
          resolver(repo).resolve(['g:a:1.0']),
          throwsA(
            isA<MavenException>().having(
              (e) => e.message,
              'message',
              contains('loops'),
            ),
          ),
        );
      },
    );
  });

  test(
    'resolves a real coordinate from Maven Central',
    () async {
      // gson is the smallest real exercise of the whole machinery: two levels of
      // <parent>, a version left to the parent's <dependencyManagement>, three
      // test-scope dependencies to drop, and a proguard plugin whose own
      // <dependencies> must not reach the classpath.
      final resolved = await MavenResolver(cache: cache)
          .resolve(['com.google.code.gson:gson:2.11.0'])
          .onError<MavenException>((e, _) {
            printOnFailure('$e');
            return const [];
          });
      if (resolved.isEmpty) {
        markTestSkipped('Maven Central is not reachable');
        return;
      }
      expect(resolved.map((a) => a.coordinate.toString()), [
        'com.google.code.gson:gson:2.11.0',
        'com.google.errorprone:error_prone_annotations:2.27.0',
      ]);
      for (final artifact in resolved) {
        expect(artifact.file.existsSync(), isTrue);
        expect(
          crypto.sha256.convert(artifact.file.readAsBytesSync()).toString(),
          artifact.sha256,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    tags: ['network'],
  );
}
