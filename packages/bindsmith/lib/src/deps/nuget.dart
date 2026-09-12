/// NuGet dependency resolution: pinned packages in, `.winmd` files on disk.
///
/// Downloads the published `.nupkg` for an exact version, records its digest in
/// the lockfile, and extracts Windows metadata from the archive. Floating
/// versions are refused for the same reason Maven and npm refuse them.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'lockfile.dart';

/// The default NuGet v3 flat container.
final nugetFlatContainer = Uri.parse('https://api.nuget.org/v3-flatcontainer/');

/// Thrown when a package cannot be resolved or has no `.winmd` file.
final class NugetException implements Exception {
  const NugetException(this.message);

  final String message;

  @override
  String toString() => 'NugetException: $message';
}

/// Fetches the bytes at [url], or throws [NugetException].
typedef NugetFetch = Future<Uint8List> Function(Uri url);

/// A pinned `PackageId@version` coordinate.
final class NugetCoordinate {
  const NugetCoordinate(this.id, this.version);

  /// Parses `Microsoft.Windows.SDK.Win32Metadata@60.0.34-preview`.
  factory NugetCoordinate.parse(String text) {
    final at = text.lastIndexOf('@');
    if (at <= 0 || at == text.length - 1) {
      throw ArgumentError.value(
        text,
        'coordinate',
        'expected PackageId@version, for example '
            'Microsoft.Windows.SDK.Win32Metadata@60.0.34-preview',
      );
    }
    final id = text.substring(0, at);
    final version = text.substring(at + 1);
    if (id.isEmpty || version.isEmpty) {
      throw ArgumentError.value(
        text,
        'coordinate',
        'expected PackageId@version',
      );
    }
    return NugetCoordinate(id, version);
  }

  final String id;
  final String version;

  String get idLower => id.toLowerCase();
  String get versionLower => version.toLowerCase();

  String get fileName => '$idLower.$versionLower.nupkg';

  /// The absolute URL of this version's `.nupkg` in [repository].
  Uri packageUri(Uri repository) =>
      repository.resolve('$idLower/$versionLower/$fileName');

  @override
  String toString() => '$id@$version';

  @override
  bool operator ==(Object other) =>
      other is NugetCoordinate && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

/// One resolved NuGet package.
final class NugetArtifact {
  const NugetArtifact({
    required this.coordinate,
    required this.package,
    required this.sha256,
    required this.extracted,
    required this.winmd,
    required this.winmdFiles,
  });

  final NugetCoordinate coordinate;

  /// The downloaded `.nupkg`, laid out like the flat container serves it.
  final File package;

  /// Digest of [package] — the bytes a lockfile pins.
  final String sha256;

  /// The directory the `.nupkg` was extracted into.
  final Directory extracted;

  /// The primary `.winmd` file bindsmith should read.
  final File winmd;

  /// Every `.winmd` file extracted from the package.
  final List<File> winmdFiles;

  LockedArtifact get locked =>
      (coordinate: '$coordinate', extension: 'nupkg', sha256: sha256);
}

/// Resolves pinned NuGet packages into files on disk.
final class NugetResolver {
  NugetResolver({required this.cache, Uri? repository, this.fetch = nugetFetch})
    : repository = repository ?? nugetFlatContainer;

  /// Where downloads land, mirroring the flat container layout.
  final Directory cache;
  final Uri repository;
  final NugetFetch fetch;

  /// Resolves [coordinates] in the order given.
  Future<List<NugetArtifact>> resolve(Iterable<String> coordinates) async {
    final artifacts = <NugetArtifact>[];
    for (final text in coordinates) {
      final coordinate = NugetCoordinate.parse(text);
      _checkVersion(coordinate);
      artifacts.add(await _resolve(coordinate));
    }
    return artifacts;
  }

  Future<NugetArtifact> _resolve(NugetCoordinate coordinate) async {
    final bytes = await _packageBytes(coordinate);
    final sha256 = crypto.sha256.convert(bytes).toString();
    final extracted = _extracted(coordinate);
    if (!extracted.existsSync()) {
      _extractPackage(bytes, extracted);
    }
    final winmdFiles = _winmdFiles(extracted);
    if (winmdFiles.isEmpty) {
      throw NugetException(
        '$coordinate has no .winmd file after extraction. bindsmith needs '
        'Windows metadata to drive the winmd driver.',
      );
    }
    final winmd = _primaryWinmd(coordinate, winmdFiles);
    return NugetArtifact(
      coordinate: coordinate,
      package: _cachedPackage(coordinate),
      sha256: sha256,
      extracted: extracted,
      winmd: winmd,
      winmdFiles: winmdFiles,
    );
  }

  File _cachedPackage(NugetCoordinate coordinate) => File(
    p.join(
      cache.path,
      coordinate.idLower,
      coordinate.versionLower,
      coordinate.fileName,
    ),
  );

  Directory _extracted(NugetCoordinate coordinate) => Directory(
    p.join(
      cache.path,
      coordinate.idLower,
      coordinate.versionLower,
      'extracted',
    ),
  );

  Future<Uint8List> _packageBytes(NugetCoordinate coordinate) async {
    final file = _cachedPackage(coordinate);
    if (file.existsSync()) return file.readAsBytesSync();
    final bytes = await fetch(coordinate.packageUri(repository));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return bytes;
  }

  void _extractPackage(Uint8List bytes, Directory extracted) {
    final archive = ZipDecoder().decodeBytes(bytes);
    extracted.createSync(recursive: true);
    for (final file in archive) {
      if (!file.isFile) continue;
      final target = File(p.join(extracted.path, file.name));
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(file.readBytes()!);
    }
  }

  List<File> _winmdFiles(Directory extracted) {
    final files = <File>[];
    if (!extracted.existsSync()) return files;
    for (final entity in extracted.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.winmd')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  File _primaryWinmd(NugetCoordinate coordinate, List<File> winmdFiles) {
    final preferred = p.basename(switch (coordinate.id.toLowerCase()) {
      'microsoft.windows.sdk.win32metadata' => 'Windows.Win32.winmd',
      'microsoft.windows.wdk.win32metadata' => 'Windows.Wdk.winmd',
      'microsoft.windows.sdk.contracts' => 'Windows.winmd',
      _ => '',
    });
    if (preferred.isNotEmpty) {
      for (final file in winmdFiles) {
        if (p.basename(file.path) == preferred) return file;
      }
    }
    if (winmdFiles.length == 1) return winmdFiles.single;
    throw NugetException(
      '$coordinate holds ${winmdFiles.length} .winmd files and bindsmith '
      'cannot tell which one to read: '
      '${winmdFiles.map((f) => p.basename(f.path)).join(', ')}.',
    );
  }
}

/// Resolves [packages] and returns what belongs in `bindsmith.lock`.
Future<List<LockedArtifact>> resolveNuget({
  required Iterable<String> packages,
  required Directory cache,
  NugetFetch? fetch,
}) async {
  final resolver = NugetResolver(cache: cache, fetch: fetch ?? nugetFetch);
  return [
    for (final artifact in await resolver.resolve(packages)) artifact.locked,
  ];
}

void _checkVersion(NugetCoordinate coordinate) {
  final version = coordinate.version;
  final problem = switch (version) {
    'latest' || '*' => 'a tag that moves with the repository',
    _ when version.startsWith('[') || version.startsWith('(') =>
      'a version range',
    _
        when version.startsWith('^') ||
            version.startsWith('~') ||
            version.startsWith('>') ||
            version.startsWith('<') =>
      'a version range',
    _ when version.contains(' ') => 'not a concrete version',
    _ => null,
  };
  if (problem != null) {
    throw NugetException(
      '$coordinate asks for $problem. bindsmith pins every artifact in the '
      'lockfile, which a version like this cannot be. Name a released '
      'version instead.',
    );
  }
}

/// Downloads [url] over HTTP, or reads it when it is a `file:` URL.
Future<Uint8List> nugetFetch(Uri url) async {
  if (url.isScheme('file')) {
    final file = File.fromUri(url);
    if (!file.existsSync()) {
      throw NugetException('${file.path} is not in this repository');
    }
    return file.readAsBytesSync();
  }
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw NugetException('GET $url returned HTTP ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await response.forEach(bytes.add);
    return bytes.takeBytes();
  } on SocketException catch (e) {
    throw NugetException('GET $url failed: ${e.message}');
  } finally {
    client.close();
  }
}
