/// Maven dependency resolution: coordinates in, jars on disk out.
///
/// Enough of Maven to build a classpath for jnigen and to pin it in a lockfile:
/// parent inheritance, properties, `dependencyManagement` including BOMs
/// imported with `<scope>import</scope>`, scope and `<optional>` filtering,
/// `<exclusions>`, and nearest-definition-wins when two paths disagree about a
/// version.
///
/// jnigen resolves Maven by writing a stub Gradle project and running
/// `gradlew`, which is both driving a tool through its console (rule 1) and
/// unpinnable, so bindsmith resolves coordinates itself instead.
///
/// Three inputs are refused rather than guessed at: version ranges,
/// `LATEST`/`RELEASE`, and `-SNAPSHOT`. Each makes the same coordinate mean
/// different bytes on different days, so there is nothing honest to write in a
/// lockfile (rule 3).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Maven Central, the default repository.
final mavenCentral = Uri.parse('https://repo1.maven.org/maven2/');

/// Google's Maven repository, which serves the AndroidX and Play libraries.
///
/// An Android build always lists it *and* [mavenCentral]: an `aar` published
/// here routinely depends on a Kotlin or JetBrains artifact that only Central
/// has, which is why [MavenResolver] takes a list rather than one repository.
final googleMaven = Uri.parse('https://dl.google.com/dl/android/maven2/');

/// Thrown when a coordinate cannot be resolved or an artifact cannot be read.
final class MavenException implements Exception {
  const MavenException(this.message);

  final String message;

  @override
  String toString() => 'MavenException: $message';
}

/// Fetches the bytes at [url], or throws [MavenException].
///
/// Injectable so that resolution can be tested against an in-memory repository
/// without a network.
typedef MavenFetch = Future<Uint8List> Function(Uri url);

/// A `group:artifact:version` coordinate, with the optional classifier that
/// selects a sibling file of the main artifact.
final class Coordinate {
  const Coordinate(this.group, this.artifact, this.version, {this.classifier});

  /// Parses `group:artifact:version` from `bindsmith.yaml`, or a four-part
  /// form with a classifier such as `sources` from a lockfile entry.
  factory Coordinate.parse(String text) {
    final parts = text.split(':').map((s) => s.trim()).toList();
    if (parts.length == 3 && parts.every((s) => s.isNotEmpty)) {
      return Coordinate(parts[0], parts[1], parts[2]);
    }
    if (parts.length == 4 && parts.every((s) => s.isNotEmpty)) {
      return Coordinate(parts[0], parts[1], parts[2], classifier: parts[3]);
    }
    throw ArgumentError.value(
      text,
      'coordinate',
      'expected group:artifact:version or group:artifact:version:classifier',
    );
  }

  final String group;
  final String artifact;
  final String version;
  final String? classifier;

  /// `group:artifact`, the key conflict resolution works on: a classpath holds
  /// one version of a module, not one per requester.
  String get module => '$group:$artifact';

  /// The repository-relative directory holding every file of this artifact.
  String get directory => '${group.replaceAll('.', '/')}/$artifact/$version';

  /// The published file name for [extension].
  String fileName(String extension) =>
      '$artifact-$version'
      '${classifier == null ? '' : '-$classifier'}.$extension';

  /// The absolute URL of this artifact's [extension] file in [repository].
  Uri uri(Uri repository, String extension) =>
      repository.resolve('$directory/${fileName(extension)}');

  @override
  String toString() => classifier == null
      ? '$group:$artifact:$version'
      : '$group:$artifact:$version:$classifier';

  @override
  bool operator ==(Object other) =>
      other is Coordinate &&
      other.group == group &&
      other.artifact == artifact &&
      other.version == version &&
      other.classifier == classifier;

  @override
  int get hashCode => Object.hash(group, artifact, version, classifier);
}

/// One `<dependency>` entry, whose version may still be unknown: a POM is
/// allowed to leave it to `<dependencyManagement>`.
final class MavenDependency {
  const MavenDependency({
    required this.group,
    required this.artifact,
    this.version,
    this.scope = 'compile',
    this.type = 'jar',
    this.classifier,
    this.optional = false,
    this.exclusions = const {},
  });

  final String group;
  final String artifact;
  final String? version;
  final String scope;
  final String type;
  final String? classifier;
  final bool optional;

  /// `group:artifact` pairs this dependency's subtree must not reach; either
  /// half may be `*`.
  final Set<String> exclusions;

  /// `group:artifact`, matching [Coordinate.module].
  String get module => '$group:$artifact';
}

/// A parsed POM, exactly as written: nothing inherited, nothing interpolated.
///
/// Kept separate from [MavenResolver] for the same reason passes are kept
/// separate from emitters — it is a pure function of one string and has its own
/// unit tests.
final class Pom {
  const Pom({
    required this.artifact,
    this.group,
    this.version,
    this.parent,
    this.packaging = 'jar',
    this.properties = const {},
    this.managed = const [],
    this.dependencies = const [],
  });

  /// Reads a `pom.xml`.
  ///
  /// Every lookup is by direct child. A POM also carries `<dependencies>` deep
  /// inside `<build><plugins><plugin>`, and those belong to the build that
  /// produced the artifact, not to anyone who consumes it.
  factory Pom.parse(String xml) {
    final project = XmlDocument.parse(xml).rootElement;
    if (project.name.local != 'project') {
      throw const MavenException(
        'not a POM: the root element should be <project>',
      );
    }
    final parent = project.getElement('parent');
    final artifact = _text(project, 'artifactId');
    if (artifact == null) {
      throw const MavenException('POM has no <artifactId>');
    }
    return Pom(
      artifact: artifact,
      group: _text(project, 'groupId'),
      version: _text(project, 'version'),
      parent: parent == null ? null : _parent(parent),
      packaging: _text(project, 'packaging') ?? 'jar',
      properties: {
        for (final e
            in project
                    .getElement('properties')
                    ?.children
                    .whereType<XmlElement>() ??
                const <XmlElement>[])
          e.name.local: e.innerText.trim(),
      },
      managed: _dependencies(project.getElement('dependencyManagement')),
      dependencies: _dependencies(project),
    );
  }

  /// The parent POM to inherit from, if any.
  final Coordinate? parent;

  /// Absent when the POM inherits its group from [parent].
  final String? group;
  final String artifact;

  /// Absent when the POM inherits its version from [parent].
  final String? version;

  /// `jar` unless the POM says otherwise; `pom` for a BOM or an aggregator and
  /// `aar` for an Android library. Packaging is not inherited.
  final String packaging;
  final Map<String, String> properties;

  /// `<dependencyManagement>` entries: versions and exclusions for modules this
  /// POM or its children may depend on, not dependencies themselves.
  final List<MavenDependency> managed;
  final List<MavenDependency> dependencies;
}

Coordinate _parent(XmlElement parent) {
  final group = _text(parent, 'groupId');
  final artifact = _text(parent, 'artifactId');
  final version = _text(parent, 'version');
  if (group == null || artifact == null || version == null) {
    throw const MavenException(
      '<parent> needs a groupId, an artifactId and a version; this POM names '
      'fewer, so there is no coordinate to fetch it by',
    );
  }
  return Coordinate(group, artifact, version);
}

String? _text(XmlElement element, String name) {
  final text = element.getElement(name)?.innerText.trim();
  return (text == null || text.isEmpty) ? null : text;
}

List<MavenDependency> _dependencies(XmlElement? holder) {
  final list = holder?.getElement('dependencies');
  if (list == null) return const [];
  return [
    for (final d in list.findElements('dependency'))
      MavenDependency(
        group: _text(d, 'groupId') ?? '',
        artifact: _text(d, 'artifactId') ?? '',
        version: _text(d, 'version'),
        scope: _text(d, 'scope') ?? 'compile',
        type: _text(d, 'type') ?? 'jar',
        classifier: _text(d, 'classifier'),
        optional: _text(d, 'optional') == 'true',
        exclusions: {
          for (final x
              in d.getElement('exclusions')?.findElements('exclusion') ??
                  const <XmlElement>[])
            '${_text(x, 'groupId') ?? '*'}:${_text(x, 'artifactId') ?? '*'}',
        },
      ),
  ];
}

/// One resolved artifact.
final class MavenArtifact {
  const MavenArtifact({
    required this.coordinate,
    required this.extension,
    required this.file,
    required this.sha256,
  });

  final Coordinate coordinate;

  /// The published file's extension, `jar` or `aar`.
  final String extension;

  /// The classpath entry: the downloaded jar, or the `classes.jar` unpacked out
  /// of an `aar`.
  final File file;

  /// Digest of the published file — of the `aar` rather than of what came out
  /// of it, because those are the bytes a later run can re-check. Together with
  /// [coordinate] it is everything a lockfile needs: which repository served
  /// the bytes does not matter once the digest matches.
  final String sha256;
}

/// Everything about a POM after its ancestors have been folded in.
typedef _Effective = ({
  String packaging,
  Map<String, String> properties,
  Map<String, MavenDependency> managed,
  List<MavenDependency> dependencies,
});

/// One node of the resolution frontier: a coordinate plus the exclusions its
/// whole subtree inherits.
typedef _Node = ({Coordinate coordinate, Set<String> exclusions});

/// Resolves Maven coordinates into files on disk.
final class MavenResolver {
  MavenResolver({
    required this.cache,
    List<Uri>? repositories,
    this.fetch = mavenFetch,
  }) : repositories = [
         for (final r in repositories ?? [mavenCentral]) _withSlash(r),
       ];

  /// Where downloads land, laid out exactly like a Maven repository — so the
  /// cache is one, and a second run with the same lockfile needs no network.
  final Directory cache;

  /// Searched in order, the way a Maven or Gradle build searches the
  /// repositories it declares: the first one that has a file serves it.
  final List<Uri> repositories;

  /// How bytes are read from [repository]; replaced in tests.
  final MavenFetch fetch;

  final _effectives = <Coordinate, _Effective>{};
  final _visiting = <Coordinate>{};

  /// Resolves [coordinates] and everything they need, in breadth-first order.
  ///
  /// The result starts with the requested coordinates and is deterministic:
  /// same inputs, same order, same files (rule 6).
  Future<List<MavenArtifact>> resolve(Iterable<String> coordinates) async {
    final picked = <String, Coordinate>{};
    final order = <Coordinate>[];
    var frontier = [
      for (final text in coordinates)
        (coordinate: Coordinate.parse(text), exclusions: const <String>{}),
    ];
    // A directly requested coordinate keeps its `provided` dependencies, the
    // way a Maven compile classpath does; `provided` is not inherited further.
    var scopes = const {'compile', 'runtime', 'provided'};

    while (frontier.isNotEmpty) {
      final next = <_Node>[];
      for (final node in frontier) {
        // Nearest definition wins: the first path to reach a module, at the
        // shallowest depth, fixes its version for the whole classpath.
        if (picked.containsKey(node.coordinate.module)) continue;
        _checkVersion(node.coordinate);
        picked[node.coordinate.module] = node.coordinate;
        order.add(node.coordinate);

        final pom = await _effective(node.coordinate);
        for (final d in pom.dependencies) {
          if (d.optional || !scopes.contains(d.scope)) continue;
          if (_excluded(node.exclusions, d)) continue;
          if (picked.containsKey(d.module)) continue;
          final version = d.version ?? pom.managed[d.module]?.version;
          if (version == null) {
            throw MavenException(
              'no version for ${d.module}, required by ${node.coordinate}: '
              'nothing in the <dependencyManagement> it inherits pins one. '
              'Request ${d.module}:<version> directly.',
            );
          }
          next.add((
            coordinate: Coordinate(
              d.group,
              d.artifact,
              version,
              classifier: d.classifier,
            ),
            exclusions: {...node.exclusions, ...d.exclusions},
          ));
        }
      }
      frontier = next;
      scopes = const {'compile', 'runtime'};
    }

    final artifacts = <MavenArtifact>[];
    for (final coordinate in order) {
      final packaging = _effectives[coordinate]!.packaging;
      // A `pom` packaging is a BOM or an aggregator: it has no file to put on a
      // classpath, only the metadata already read out of it.
      if (packaging == 'pom') continue;
      // Anything else ships a jar; `aar` wraps one, `bundle` and `maven-plugin`
      // are jars with extra manifest entries.
      final extension = packaging == 'aar' ? 'aar' : 'jar';
      final bytes = await _bytes(coordinate, extension);
      artifacts.add(
        MavenArtifact(
          coordinate: coordinate,
          extension: extension,
          file: extension == 'aar'
              ? _classesJar(coordinate, bytes)
              : _cached(coordinate, extension),
          sha256: crypto.sha256.convert(bytes).toString(),
        ),
      );
    }
    return artifacts;
  }

  /// Fetches the `sources` classifier for each *direct* [coordinates] entry.
  ///
  /// A missing sources jar is normal and is omitted from the result. Only
  /// coordinates the caller names are tried — transitives are never fetched
  /// here.
  ///
  /// Lock entries use [Coordinate.toString] with classifier `sources` (for
  /// example `g:a:1.0:sources`) rather than a `classifier:` YAML field:
  /// [parseLockfile] refuses unknown fields, so adding one would force lock
  /// format version 2 for no extra information.
  Future<List<MavenArtifact>> fetchSources(Iterable<String> coordinates) async {
    final artifacts = <MavenArtifact>[];
    for (final text in coordinates) {
      final base = Coordinate.parse(text);
      final coordinate = Coordinate(
        base.group,
        base.artifact,
        base.version,
        classifier: 'sources',
      );
      final bytes = await _bytesOptional(coordinate, 'jar');
      if (bytes == null) continue;
      final file = _cached(coordinate, 'jar');
      _unpackSourcesJar(coordinate, bytes);
      artifacts.add(
        MavenArtifact(
          coordinate: coordinate,
          extension: 'jar',
          file: file,
          sha256: crypto.sha256.convert(bytes).toString(),
        ),
      );
    }
    return artifacts;
  }

  Future<_Effective> _effective(Coordinate coordinate) async {
    final done = _effectives[coordinate];
    if (done != null) return done;
    if (!_visiting.add(coordinate)) {
      throw MavenException(
        '$coordinate is its own ancestor: the POM chain '
        'loops through <parent> or an imported BOM',
      );
    }
    try {
      final pom = Pom.parse(utf8.decode(await _bytes(coordinate, 'pom')));
      final parent = pom.parent == null ? null : await _effective(pom.parent!);

      final properties = <String, String>{
        ...?parent?.properties,
        ...pom.properties,
        'project.groupId': coordinate.group,
        'project.artifactId': coordinate.artifact,
        'project.version': coordinate.version,
        'pom.groupId': coordinate.group,
        'pom.artifactId': coordinate.artifact,
        'pom.version': coordinate.version,
        if (pom.parent case final up?) ...{
          'project.parent.groupId': up.group,
          'project.parent.version': up.version,
        },
      };

      // Inherited entries first, then imported BOMs, then this POM's own: a
      // version written here beats one a BOM suggests.
      final managed = <String, MavenDependency>{...?parent?.managed};
      for (final d in pom.managed) {
        final filled = _fill(d, properties);
        if (filled.scope == 'import' && filled.type == 'pom') {
          final version = filled.version;
          if (version == null) {
            throw MavenException(
              '$coordinate imports the ${filled.module} BOM without a version',
            );
          }
          final bom = await _effective(
            Coordinate(filled.group, filled.artifact, version),
          );
          managed.addAll(bom.managed);
        }
      }
      for (final d in pom.managed) {
        final filled = _fill(d, properties);
        if (filled.scope == 'import' && filled.type == 'pom') continue;
        managed[filled.module] = filled;
      }

      final dependencies = <String, MavenDependency>{
        for (final d in parent?.dependencies ?? const <MavenDependency>[])
          d.module: d,
        for (final d in pom.dependencies) d.module: _fill(d, properties),
      };

      final result = (
        packaging: pom.packaging,
        properties: properties,
        managed: managed,
        dependencies: dependencies.values.toList(),
      );
      _effectives[coordinate] = result;
      return result;
    } finally {
      _visiting.remove(coordinate);
    }
  }

  /// The cache path of one file of [coordinate], mirroring the repository.
  File _cached(Coordinate coordinate, String extension) => File(
    p.join(
      cache.path,
      p.joinAll(coordinate.directory.split('/')),
      coordinate.fileName(extension),
    ),
  );

  Future<Uint8List> _bytes(Coordinate coordinate, String extension) async {
    final file = _cached(coordinate, extension);
    if (file.existsSync()) return file.readAsBytesSync();
    final failures = <String>[];
    for (final repository in repositories) {
      try {
        final bytes = await fetch(coordinate.uri(repository, extension));
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        return bytes;
      } on MavenException catch (e) {
        failures.add(e.message);
        continue;
      }
    }
    throw MavenException(
      'no repository has ${coordinate.fileName(extension)}:\n'
      '${failures.map((f) => '  $f').join('\n')}',
    );
  }

  /// Like [_bytes], but returns `null` when no repository has the file.
  ///
  /// Used for optional `sources` jars. A missing POM still goes through
  /// [_bytes] and throws.
  Future<Uint8List?> _bytesOptional(
    Coordinate coordinate,
    String extension,
  ) async {
    final file = _cached(coordinate, extension);
    if (file.existsSync()) return file.readAsBytesSync();
    for (final repository in repositories) {
      try {
        final bytes = await fetch(coordinate.uri(repository, extension));
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        return bytes;
      } on MavenException {
        continue;
      }
    }
    return null;
  }

  /// The directory a sources jar is unpacked into, beside the jar in the cache.
  Directory _sourcesTree(Coordinate coordinate) {
    final jar = _cached(coordinate, 'jar');
    return Directory(
      p.join(jar.parent.path, p.basenameWithoutExtension(jar.path)),
    );
  }

  /// Expands a sources jar into [_sourcesTree] for jnigen and [mavenSourceDocs].
  void _unpackSourcesJar(Coordinate coordinate, Uint8List jar) {
    final tree = _sourcesTree(coordinate);
    if (tree.existsSync()) return;
    tree.createSync(recursive: true);
    for (final entry in ZipDecoder().decodeBytes(jar)) {
      if (entry.isFile) {
        final out = File(p.join(tree.path, entry.name));
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.readBytes()!);
      }
    }
  }

  /// An `aar` is a zip whose `classes.jar` is the part a classpath wants; the
  /// rest is Android resources, a manifest and native libraries.
  File _classesJar(Coordinate coordinate, Uint8List aar) {
    final target = _cached(coordinate, 'classes.jar');
    if (target.existsSync()) return target;
    final classes = ZipDecoder()
        .decodeBytes(aar)
        .findFile('classes.jar')
        ?.readBytes();
    if (classes == null) {
      throw MavenException(
        '$coordinate is packaged as an aar but holds no '
        'classes.jar, so there is nothing to compile against',
      );
    }
    target.writeAsBytesSync(classes);
    return target;
  }
}

MavenDependency _fill(MavenDependency d, Map<String, String> properties) =>
    MavenDependency(
      group: _expand(d.group, properties),
      artifact: _expand(d.artifact, properties),
      version: d.version == null ? null : _expand(d.version!, properties),
      scope: d.scope,
      type: d.type,
      classifier: d.classifier == null
          ? null
          : _expand(d.classifier!, properties),
      optional: d.optional,
      exclusions: d.exclusions,
    );

/// Substitutes `${...}` references, repeatedly, since a property may name
/// another. Stops when nothing changes, so an undefined property is left in
/// place for [_checkVersion] to report by name.
String _expand(String value, Map<String, String> properties) {
  var out = value;
  for (var i = 0; i < 8 && out.contains(r'${'); i++) {
    final next = out.replaceAllMapped(
      RegExp(r'\$\{([^}]+)\}'),
      (m) => properties[m[1]!] ?? m[0]!,
    );
    if (next == out) break;
    out = next;
  }
  return out;
}

bool _excluded(Set<String> exclusions, MavenDependency d) => exclusions.any(
  (e) => switch (e.split(':')) {
    [final g, final a] =>
      (g == '*' || g == d.group) && (a == '*' || a == d.artifact),
    _ => false,
  },
);

void _checkVersion(Coordinate coordinate) {
  final version = coordinate.version;
  final problem = switch (version) {
    _ when version.startsWith('[') || version.startsWith('(') =>
      'a version range',
    'LATEST' || 'RELEASE' => 'a version that moves with the repository',
    _ when version.endsWith('-SNAPSHOT') => 'a snapshot',
    _ when version.contains(r'${') =>
      'a version naming a property no POM in its chain defines',
    _ => null,
  };
  if (problem != null) {
    throw MavenException(
      '$coordinate asks for $problem. bindsmith pins every artifact in the '
      'lockfile, which a version like this cannot be. Name a released '
      'version instead.',
    );
  }
}

Uri _withSlash(Uri repository) => repository.path.endsWith('/')
    ? repository
    : repository.replace(path: '${repository.path}/');

/// Downloads [url] over HTTP, or reads it when it is a `file:` repository.
///
/// The default [MavenFetch]. One client per call: a resolve fetches a few dozen
/// small files, and a client that outlived the call would keep the isolate
/// alive after the CLI had finished.
Future<Uint8List> mavenFetch(Uri url) async {
  if (url.isScheme('file')) {
    final file = File.fromUri(url);
    if (!file.existsSync()) {
      throw MavenException('${file.path} is not in this repository');
    }
    return file.readAsBytesSync();
  }
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw MavenException('GET $url returned HTTP ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await response.forEach(bytes.add);
    return bytes.takeBytes();
  } on SocketException catch (e) {
    throw MavenException('GET $url failed: ${e.message}');
  } finally {
    client.close();
  }
}

/// Java directories for jnigen `sourcePath`, and `.kt` files for
/// `JvmDriver.kotlinSources`, derived from unpacked Maven `sources` jars.
///
/// [root] is the project working directory. Returned paths are relative to it
/// so `JvmDriver.load` can open them with `p.join(workingDirectory, rel)`.
({List<String> javaDirs, List<String> kotlinFiles}) mavenSourceDocs(
  Iterable<MavenArtifact> sources, {
  required String root,
}) {
  final javaDirs = <String>{};
  final kotlinFiles = <String>[];
  for (final artifact in sources) {
    if (artifact.coordinate.classifier != 'sources') continue;
    final tree = Directory(
      p.join(
        artifact.file.parent.path,
        p.basenameWithoutExtension(artifact.file.path),
      ),
    );
    if (!tree.existsSync()) continue;
    var hasJava = false;
    for (final entity in tree.listSync(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: root);
      switch (p.extension(entity.path)) {
        case '.java':
          hasJava = true;
        case '.kt':
          kotlinFiles.add(rel);
      }
    }
    if (hasJava) {
      javaDirs.add(p.relative(tree.path, from: root));
    }
  }
  return (javaDirs: [...javaDirs]..sort(), kotlinFiles: kotlinFiles..sort());
}
