import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bindsmith/bindsmith.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

/// An in-memory NuGet flat container.
final class _Repository {
  _Repository([String base = 'https://example.invalid/nuget/'])
    : base = Uri.parse(base);

  final Uri base;
  final _files = <String, List<int>>{};

  final requested = <String>[];

  void package(String coordinate, List<int> bytes) {
    final c = NugetCoordinate.parse(coordinate);
    _files[c.packageUri(base).path] = bytes;
  }

  Future<Uint8List> fetch(Uri url) async {
    requested.add(url.path);
    final bytes = _files[url.path];
    if (bytes == null) throw NugetException('GET $url returned HTTP 404');
    return Uint8List.fromList(bytes);
  }
}

Uint8List _nupkg(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(key: path, value: contents) in files.entries) {
    archive.add(ArchiveFile.string(path, contents));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('bindsmith_nuget_'));
  tearDown(() => cache.deleteSync(recursive: true));

  NugetResolver resolver(_Repository repository) => NugetResolver(
    cache: cache,
    repository: repository.base,
    fetch: repository.fetch,
  );

  group('NugetCoordinate', () {
    test('parses id@version and builds a flat-container URL', () {
      const coordinate = NugetCoordinate(
        'Microsoft.Windows.SDK.Win32Metadata',
        '1.0.0',
      );
      expect(
        coordinate.toString(),
        'Microsoft.Windows.SDK.Win32Metadata@1.0.0',
      );
      expect(
        coordinate.packageUri(nugetFlatContainer).path,
        '/v3-flatcontainer/microsoft.windows.sdk.win32metadata/1.0.0/'
        'microsoft.windows.sdk.win32metadata.1.0.0.nupkg',
      );
      expect(
        NugetCoordinate.parse('Microsoft.Windows.SDK.Win32Metadata@1.0.0'),
        coordinate,
      );
    });

    test('rejects coordinates without a version', () {
      expect(
        () => NugetCoordinate.parse('Microsoft.Windows.SDK.Win32Metadata'),
        throwsArgumentError,
      );
    });
  });

  group('resolve', () {
    test('extracts the primary winmd file', () async {
      final repository = _Repository()
        ..package(
          'Microsoft.Windows.SDK.Win32Metadata@1.0.0',
          _nupkg({
            'Windows.Win32.winmd': 'winmd bytes',
            '_rels/.rels': '<Relationships/>',
          }),
        );

      final resolved = await resolver(repository)
          .resolve(['Microsoft.Windows.SDK.Win32Metadata@1.0.0']);
      expect(resolved, hasLength(1));
      final artifact = resolved.single;
      expect(artifact.winmd.path, endsWith('Windows.Win32.winmd'));
      expect(artifact.locked.extension, 'nupkg');
      expect(
        artifact.sha256,
        crypto.sha256.convert(repository._files.values.single).toString(),
      );
    });

    test('refuses a package with no winmd file', () async {
      final repository = _Repository()
        ..package(
          'Demo.Package@1.0.0',
          _nupkg({'README.md': 'no metadata here'}),
        );

      await expectLater(
        resolver(repository).resolve(['Demo.Package@1.0.0']),
        throwsA(
          isA<NugetException>().having(
            (e) => e.message,
            'message',
            contains('no .winmd file'),
          ),
        ),
      );
    });

    test('refuses a version that cannot be pinned', () async {
      final repository = _Repository();
      for (final version in ['latest', '*', '^1.0.0']) {
        await expectLater(
          resolver(repository).resolve(['Demo.Package@$version']),
          throwsA(isA<NugetException>()),
          reason: version,
        );
      }
    });

    test('resolveNuget returns lock entries', () async {
      final repository = _Repository()
        ..package(
          'Microsoft.Windows.SDK.Win32Metadata@1.0.0',
          _nupkg({'Windows.Win32.winmd': 'winmd bytes'}),
        );

      final locked = await resolveNuget(
        packages: ['Microsoft.Windows.SDK.Win32Metadata@1.0.0'],
        cache: cache,
        repository: repository.base,
        fetch: repository.fetch,
      );
      expect(
        locked.single.coordinate,
        'Microsoft.Windows.SDK.Win32Metadata@1.0.0',
      );
      expect(locked.single.extension, 'nupkg');
    });

    test(
      'a second run over the same cache asks the network for nothing',
      () async {
        final repository = _Repository()
          ..package(
            'Microsoft.Windows.SDK.Win32Metadata@1.0.0',
            _nupkg({'Windows.Win32.winmd': 'winmd bytes'}),
          );

        final first = await resolver(repository)
            .resolve(['Microsoft.Windows.SDK.Win32Metadata@1.0.0']);
        expect(repository.requested, isNotEmpty);

        final offline = NugetResolver(
          cache: cache,
          repository: repository.base,
          fetch: (url) async => throw const NugetException('offline'),
        );
        final second = await offline.resolve([
          'Microsoft.Windows.SDK.Win32Metadata@1.0.0',
        ]);
        expect(
          second.map((a) => (a.coordinate.toString(), a.sha256, a.winmd.path)),
          first.map((a) => (a.coordinate.toString(), a.sha256, a.winmd.path)),
        );
      },
    );
  });

  test('resolves Win32Metadata from nuget.org', () async {
    final resolved = await NugetResolver(cache: cache)
        .resolve(['Microsoft.Windows.SDK.Win32Metadata@60.0.34-preview'])
        .onError<NugetException>((e, _) {
          printOnFailure('$e');
          return const [];
        });
    if (resolved.isEmpty) {
      markTestSkipped('api.nuget.org is not reachable');
      return;
    }
    final artifact = resolved.single;
    expect(artifact.winmd.existsSync(), isTrue);
    expect(artifact.winmd.path, endsWith('Windows.Win32.winmd'));
    expect(
      crypto.sha256.convert(artifact.package.readAsBytesSync()).toString(),
      artifact.sha256,
    );
  }, tags: ['network']);
}
