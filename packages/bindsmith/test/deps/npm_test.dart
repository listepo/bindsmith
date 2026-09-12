import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bindsmith/bindsmith.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

/// An in-memory npm registry.
final class _Registry {
  _Registry([String base = 'https://example.invalid/npm/'])
    : base = Uri.parse(base);

  final Uri base;
  final _files = <String, List<int>>{};

  final requested = <String>[];

  void tarball(String coordinate, List<int> bytes) {
    final c = NpmCoordinate.parse(coordinate);
    _files[c.tarballUri(base).path] = bytes;
  }

  Future<Uint8List> fetch(Uri url) async {
    requested.add(url.path);
    final bytes = _files[url.path];
    if (bytes == null) throw NpmException('GET $url returned HTTP 404');
    return Uint8List.fromList(bytes);
  }
}

Uint8List _tarball({
  required String name,
  required String version,
  required Map<String, String> files,
  Map<String, Object?>? manifest,
}) {
  final archive = Archive();
  final packageJson =
      manifest ??
      {
        'name': name,
        'version': version,
        'types': files.keys.firstWhere(
          (path) => path.endsWith('.d.ts'),
          orElse: () => 'index.d.ts',
        ),
      };
  archive.add(
    ArchiveFile.string('package/package.json', jsonEncode(packageJson)),
  );
  for (final MapEntry(key: path, value: contents) in files.entries) {
    archive.add(ArchiveFile.string('package/$path', contents));
  }
  final tar = TarEncoder().encode(archive);
  return Uint8List.fromList(GZipEncoder().encode(tar)!);
}

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('bindsmith_npm_'));
  tearDown(() => cache.deleteSync(recursive: true));

  NpmResolver resolver(_Registry registry) =>
      NpmResolver(cache: cache, registry: registry.base, fetch: registry.fetch);

  group('NpmCoordinate', () {
    test('parses unscoped and scoped coordinates', () {
      expect(
        NpmCoordinate.parse('chart.js@4.4.7').toString(),
        'chart.js@4.4.7',
      );
      expect(
        NpmCoordinate.parse('@example/sdk@2.3.1').toString(),
        '@example/sdk@2.3.1',
      );
      expect(
        NpmCoordinate.parse('chart.js@4.4.7').tarballUri(npmRegistry).path,
        '/chart.js/-/chart.js-4.4.7.tgz',
      );
    });

    test('rejects coordinates without a version', () {
      expect(() => NpmCoordinate.parse('chart.js'), throwsArgumentError);
      expect(() => NpmCoordinate.parse('@scope/pkg'), throwsArgumentError);
    });
  });

  group('resolve', () {
    test('extracts declaration files and discovers the entrypoint', () async {
      final registry = _Registry()
        ..tarball(
          'demo@1.0.0',
          _tarball(
            name: 'demo',
            version: '1.0.0',
            files: {
              'index.d.ts': 'export declare const value: number;',
              'extra.d.ts': 'export declare const other: string;',
            },
          ),
        );

      final resolved = await resolver(registry).resolve(['demo@1.0.0']);
      expect(resolved, hasLength(1));
      final artifact = resolved.single;
      expect(artifact.entrypoint.path, endsWith('index.d.ts'));
      expect(artifact.declarations, hasLength(2));
      expect(artifact.locked.extension, 'tgz');
      expect(
        artifact.sha256,
        crypto.sha256.convert(registry._files.values.single).toString(),
      );
    });

    test('follows types in package.json', () async {
      final registry = _Registry()
        ..tarball(
          'demo@1.0.0',
          _tarball(
            name: 'demo',
            version: '1.0.0',
            manifest: {
              'name': 'demo',
              'version': '1.0.0',
              'types': 'lib/main.d.ts',
            },
            files: {'lib/main.d.ts': 'export declare const value: number;'},
          ),
        );

      final artifact = (await resolver(registry).resolve(['demo@1.0.0']))
          .single;
      expect(artifact.entrypoint.path, endsWith('lib/main.d.ts'));
    });

    test('refuses a package with no declaration files', () async {
      final registry = _Registry()
        ..tarball(
          'demo@1.0.0',
          _tarball(
            name: 'demo',
            version: '1.0.0',
            manifest: {'name': 'demo', 'version': '1.0.0'},
            files: {'index.js': 'module.exports = {};'},
          ),
        );

      await expectLater(
        resolver(registry).resolve(['demo@1.0.0']),
        throwsA(
          isA<NpmException>().having(
            (e) => e.message,
            'message',
            contains('no .d.ts files'),
          ),
        ),
      );
    });

    test('refuses a version that cannot be pinned', () async {
      final registry = _Registry();
      for (final version in ['latest', '^1.0.0', '*']) {
        await expectLater(
          resolver(registry).resolve(['demo@$version']),
          throwsA(isA<NpmException>()),
          reason: version,
        );
      }
    });

    test('resolveNpm returns lock entries', () async {
      final registry = _Registry()
        ..tarball(
          'demo@1.0.0',
          _tarball(
            name: 'demo',
            version: '1.0.0',
            files: {'index.d.ts': 'export declare const value: number;'},
          ),
        );

      final locked = await resolveNpm(
        packages: ['demo@1.0.0'],
        cache: cache,
        fetch: registry.fetch,
      );
      expect(locked.single.coordinate, 'demo@1.0.0');
      expect(locked.single.extension, 'tgz');
    });

    test(
      'a second run over the same cache asks the network for nothing',
      () async {
        final registry = _Registry()
          ..tarball(
            'demo@1.0.0',
            _tarball(
              name: 'demo',
              version: '1.0.0',
              files: {'index.d.ts': 'export declare const value: number;'},
            ),
          );

        final first = await resolver(registry).resolve(['demo@1.0.0']);
        expect(registry.requested, isNotEmpty);

        final offline = NpmResolver(
          cache: cache,
          registry: registry.base,
          fetch: (url) async => throw const NpmException('offline'),
        );
        final second = await offline.resolve(['demo@1.0.0']);
        expect(
          second.map(
            (a) => (a.coordinate.toString(), a.sha256, a.entrypoint.path),
          ),
          first.map(
            (a) => (a.coordinate.toString(), a.sha256, a.entrypoint.path),
          ),
        );
      },
    );
  });

  test('resolves a real package from the npm registry', () async {
    final resolved = await NpmResolver(cache: cache)
        .resolve(['nanoid@3.3.7'])
        .onError<NpmException>((e, _) {
          printOnFailure('$e');
          return const [];
        });
    if (resolved.isEmpty) {
      markTestSkipped('registry.npmjs.org is not reachable');
      return;
    }
    final artifact = resolved.single;
    expect(artifact.declarations, isNotEmpty);
    expect(artifact.entrypoint.existsSync(), isTrue);
    expect(
      crypto.sha256.convert(artifact.tarball.readAsBytesSync()).toString(),
      artifact.sha256,
    );
  }, tags: ['network']);
}
