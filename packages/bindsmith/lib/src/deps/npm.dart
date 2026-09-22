/// npm dependency resolution: pinned packages in, declaration files on disk.
///
/// Fetches the published tarball for an exact version, records its digest in the
/// lockfile, and extracts every `.d.ts` file the package carries. bindsmith
/// refuses version ranges and moving tags for the same reason Maven does: there
/// is nothing honest to pin when the bytes can change without the coordinate
/// changing.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'lockfile.dart';

/// The default npm registry.
final npmRegistry = Uri.parse('https://registry.npmjs.org/');

/// Thrown when a package cannot be resolved or has no declaration files.
final class NpmException implements Exception {
  const NpmException(this.message);

  final String message;

  @override
  String toString() => 'NpmException: $message';
}

/// Fetches the bytes at [url], or throws [NpmException].
typedef NpmFetch = Future<Uint8List> Function(Uri url);

/// A pinned `name@version` coordinate.
final class NpmCoordinate {
  const NpmCoordinate(this.name, this.version);

  /// Parses `chart.js@4.4.7` and `@example/sdk@2.3.1`.
  factory NpmCoordinate.parse(String text) {
    final at = text.lastIndexOf('@');
    if (at <= 0 || at == text.length - 1) {
      throw ArgumentError.value(
        text,
        'coordinate',
        'expected name@version, for example chart.js@4.4.7 or '
            '@example/sdk@2.3.1',
      );
    }
    final name = text.substring(0, at);
    final version = text.substring(at + 1);
    if (name.isEmpty || version.isEmpty) {
      throw ArgumentError.value(text, 'coordinate', 'expected name@version');
    }
    return NpmCoordinate(name, version);
  }

  final String name;
  final String version;

  /// The registry path segment for [name].
  String get encodedName => name.split('/').map(Uri.encodeComponent).join('/');

  /// The published tarball file name.
  String get tarballName => '$name-$version.tgz';

  /// The absolute URL of this version's tarball in [registry].
  Uri tarballUri(Uri registry) =>
      registry.resolve('$encodedName/-/${Uri.encodeComponent(tarballName)}');

  @override
  String toString() => '$name@$version';

  @override
  bool operator ==(Object other) =>
      other is NpmCoordinate && other.name == name && other.version == version;

  @override
  int get hashCode => Object.hash(name, version);
}

/// One resolved npm package.
final class NpmArtifact {
  const NpmArtifact({
    required this.coordinate,
    required this.tarball,
    required this.sha256,
    required this.packageRoot,
    required this.entrypoint,
    required this.declarations,
  });

  final NpmCoordinate coordinate;

  /// The downloaded tarball, laid out like the registry serves it.
  final File tarball;

  /// Digest of [tarball] — the bytes a lockfile pins.
  final String sha256;

  /// The extracted `package/` directory from the tarball.
  final Directory packageRoot;

  /// The main declaration file (`types`, `typings`, or `index.d.ts`).
  final File entrypoint;

  /// Every `.d.ts` file extracted from the package.
  final List<File> declarations;

  LockedArtifact get locked =>
      (coordinate: '$coordinate', extension: 'tgz', sha256: sha256);
}

/// Resolves pinned npm packages into files on disk.
final class NpmResolver {
  NpmResolver({required this.cache, Uri? registry, this.fetch = npmFetch})
    : registry = registry ?? npmRegistry;

  /// Where downloads land, mirroring the registry layout.
  final Directory cache;
  final Uri registry;
  final NpmFetch fetch;

  /// Resolves [coordinates] in the order given.
  Future<List<NpmArtifact>> resolve(Iterable<String> coordinates) async {
    final artifacts = <NpmArtifact>[];
    for (final text in coordinates) {
      final coordinate = NpmCoordinate.parse(text);
      _checkVersion(coordinate);
      artifacts.add(await _resolve(coordinate));
    }
    return artifacts;
  }

  Future<NpmArtifact> _resolve(NpmCoordinate coordinate) async {
    final bytes = await _tarballBytes(coordinate);
    final sha256 = crypto.sha256.convert(bytes).toString();
    final packageRoot = _packageRoot(coordinate);
    if (!packageRoot.existsSync()) {
      _extractPackage(coordinate, bytes, packageRoot);
    }
    final manifest = _readManifest(packageRoot, coordinate);
    final declarations = _declarationFiles(packageRoot);
    if (declarations.isEmpty) {
      throw NpmException(
        '$coordinate has no .d.ts files after extraction. '
        'bindsmith needs TypeScript declarations to drive the dts driver.',
      );
    }
    final entrypoint = _entrypoint(packageRoot, manifest, coordinate);
    return NpmArtifact(
      coordinate: coordinate,
      tarball: _cachedTarball(coordinate),
      sha256: sha256,
      packageRoot: packageRoot,
      entrypoint: entrypoint,
      declarations: declarations,
    );
  }

  File _cachedTarball(NpmCoordinate coordinate) => File(
    p.join(
      cache.path,
      coordinate.encodedName,
      coordinate.version,
      coordinate.tarballName,
    ),
  );

  Directory _packageRoot(NpmCoordinate coordinate) => Directory(
    p.join(cache.path, coordinate.encodedName, coordinate.version, 'package'),
  );

  Future<Uint8List> _tarballBytes(NpmCoordinate coordinate) async {
    final file = _cachedTarball(coordinate);
    if (file.existsSync()) return file.readAsBytesSync();
    final bytes = await fetch(coordinate.tarballUri(registry));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return bytes;
  }

  void _extractPackage(
    NpmCoordinate coordinate,
    Uint8List tarball,
    Directory packageRoot,
  ) {
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(tarball),
    );
    final prefix = 'package/';
    packageRoot.createSync(recursive: true);
    for (final file in archive) {
      if (!file.isFile || !file.name.startsWith(prefix)) continue;
      final relative = file.name.substring(prefix.length);
      if (relative.isEmpty) continue;
      final target = File(p.join(packageRoot.path, relative));
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(file.readBytes()!);
    }
  }

  Map<String, Object?> _readManifest(
    Directory packageRoot,
    NpmCoordinate coordinate,
  ) {
    final file = File(p.join(packageRoot.path, 'package.json'));
    if (!file.existsSync()) {
      throw NpmException('$coordinate has no package.json in its tarball.');
    }
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    } on FormatException catch (e) {
      throw NpmException('$coordinate has a package.json that is not JSON: $e');
    }
  }

  File _entrypoint(
    Directory packageRoot,
    Map<String, Object?> manifest,
    NpmCoordinate coordinate,
  ) {
    final types = manifest['types'] ?? manifest['typings'];
    if (types is String && types.isNotEmpty) {
      final file = File(p.join(packageRoot.path, types));
      if (!file.existsSync()) {
        throw NpmException(
          '$coordinate points "types" at $types but that file is not in the '
          'tarball.',
        );
      }
      return file;
    }
    final index = File(p.join(packageRoot.path, 'index.d.ts'));
    if (index.existsSync()) return index;
    throw NpmException(
      '$coordinate does not declare where its types live: package.json has '
      'no "types" or "typings", and there is no index.d.ts.',
    );
  }

  List<File> _declarationFiles(Directory packageRoot) {
    final files = <File>[];
    if (!packageRoot.existsSync()) return files;
    for (final entity in packageRoot.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.d.ts')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }
}

/// Resolves [packages] and returns what belongs in `bindsmith.lock`.
Future<List<LockedArtifact>> resolveNpm({
  required Iterable<String> packages,
  required Directory cache,
  Uri? registry,
  NpmFetch? fetch,
}) async {
  final resolver = NpmResolver(
    cache: cache,
    registry: registry,
    fetch: fetch ?? npmFetch,
  );
  return [
    for (final artifact in await resolver.resolve(packages)) artifact.locked,
  ];
}

void _checkVersion(NpmCoordinate coordinate) {
  final version = coordinate.version;
  final problem = switch (version) {
    'latest' ||
    'next' ||
    'beta' ||
    'rc' ||
    '*' => 'a tag that moves with the registry',
    _
        when version.startsWith('^') ||
            version.startsWith('~') ||
            version.startsWith('>') ||
            version.startsWith('<') ||
            version.startsWith('=') =>
      'a version range',
    _ when version.contains(' ') => 'not a concrete version',
    _ => null,
  };
  if (problem != null) {
    throw NpmException(
      '$coordinate asks for $problem. bindsmith pins every artifact in the '
      'lockfile, which a version like this cannot be. Name a released '
      'version instead.',
    );
  }
}

/// Downloads [url] over HTTP, or reads it when it is a `file:` URL.
Future<Uint8List> npmFetch(Uri url) async {
  if (url.isScheme('file')) {
    final file = File.fromUri(url);
    if (!file.existsSync()) {
      throw NpmException('${file.path} is not in this registry');
    }
    return file.readAsBytesSync();
  }
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw NpmException('GET $url returned HTTP ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await response.forEach(bytes.add);
    return bytes.takeBytes();
  } on SocketException catch (e) {
    throw NpmException('GET $url failed: ${e.message}');
  } finally {
    client.close();
  }
}
