/// `bindsmith.yaml` read into a typed model.
///
/// Loading happens in two passes and both report every problem they find, not
/// the first. [validateAgainstSchema] settles the shape — spelling, types,
/// which keys exist — against the same JSON Schema an editor uses; then this
/// file settles meaning: that a driver is named, that `headers:` belongs to the
/// driver it was written under, that a Maven coordinate parses, that a platform
/// inheriting from another inherits from one that exists. Every message carries
/// the line and column it is about.
library;

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../deps/maven.dart';
import '../emit/facade.dart' show Unsupported;
import '../ir/ir.dart';
import '../passes/fixups.dart';
import '../passes/symbol_pattern.dart';
import 'schema.dart';

/// Which generator reads the native API for a platform.
enum Driver { c, objc, swift, jvm, winmd, dts, dbus }

/// The kinds of symbol an `include:` list can name.
enum IncludeKind {
  classes,
  types,
  protocols,
  functions,
  structs,
  enums,
  globals,
  typedefs,
  exports,
}

/// The build hook template emitted next to a generated C binding.
enum BuildHook { c, cmake }

/// What an unacknowledged `verify` marker does to `bindsmith verify`.
enum MarkerPolicy { error, warn }

/// Whether bindsmith generates a native bridge for shapes the driver drops.
enum WrapperMode {
  /// Generate the bridge and feed it back through the driver.
  auto,

  /// Do not generate a bridge.
  off,

  /// Regenerate the bridge file only; leave the binding on disk.
  only,
}

/// Thrown when `bindsmith.yaml` cannot be used, carrying every problem found.
final class ConfigException implements Exception {
  const ConfigException(this.problems);

  /// One entry per problem, each already formatted with its line and column.
  final List<String> problems;

  @override
  String toString() =>
      'the configuration is not usable:\n\n${problems.join('\n\n')}';
}

final class BindsmithConfig {
  const BindsmithConfig({
    required this.name,
    required this.output,
    required this.facade,
    required this.platforms,
    this.fixups = const [],
    this.verify = const VerifyConfig(),
  });

  /// Base name of the generated library: `my_sdk` → `my_sdk.g.dart`.
  final String name;

  /// Directory for the generated bindings, relative to the config file.
  final String output;
  final FacadeConfig facade;
  final Map<Platform, PlatformConfig> platforms;
  final List<Fixup> fixups;
  final VerifyConfig verify;
}

final class FacadeConfig {
  const FacadeConfig({
    required this.library,
    this.unsupported = Unsupported.throw_,
  });

  /// Path of the facade library to write.
  final String library;
  final Unsupported unsupported;
}

final class PlatformConfig {
  const PlatformConfig({
    required this.driver,
    this.headers = const [],
    this.deps = const DepsConfig(),
    this.include = const {},
    this.compileSdk,
    this.xml = const [],
    this.suspend = Async.future,
    this.flow = Async.stream,
    this.wrapper = WrapperMode.auto,
    this.module,
    this.sources = const [],
    this.build,
  });

  final Driver driver;

  /// Entry-point headers, for the C and Objective-C drivers.
  final List<String> headers;
  final DepsConfig deps;
  final Map<IncludeKind, List<String>> include;

  /// Android API level whose `android.jar` jnigen binds against.
  final String? compileSdk;

  /// D-Bus introspection XML files, for the dbus driver.
  final List<String> xml;

  /// What a Kotlin `suspend fun` becomes: [Async.future] or [Async.callback].
  final Async suspend;

  /// What a Kotlin `Flow` becomes: [Async.stream] or [Async.callback].
  final Async flow;

  /// Generate a native bridge for members the driver cannot carry across.
  final WrapperMode wrapper;

  /// Swift module name, for the swift driver.
  final String? module;

  /// Swift sources the swift driver reads.
  final List<String> sources;
  final BuildConfig? build;
}

final class DepsConfig {
  const DepsConfig({
    this.maven = const [],
    this.repositories = const [],
    this.swiftpm = const [],
    this.npm = const [],
    this.nuget = const [],
    this.pkgConfig = const [],
  });

  /// Parsed at load, so a malformed coordinate is reported with its line and
  /// column rather than when a download fails.
  final List<Coordinate> maven;

  /// Maven repositories, searched in order. Empty means Maven Central.
  final List<Uri> repositories;
  final List<SwiftPackage> swiftpm;
  final List<String> npm;
  final List<String> nuget;
  final List<String> pkgConfig;
}

final class SwiftPackage {
  const SwiftPackage(this.url, this.from);

  final Uri url;

  /// The lowest version accepted, as SwiftPM's `from:` means it.
  final String from;
}

final class BuildConfig {
  const BuildConfig(this.hook, this.sources);

  final BuildHook hook;
  final List<String> sources;
}

final class VerifyConfig {
  const VerifyConfig({
    this.markers = MarkerPolicy.error,
    this.compile = const {},
    this.lineBudget,
  });

  final MarkerPolicy markers;

  /// Platforms whose generated code must compile.
  final Set<Platform> compile;

  /// Fail if the generated output grows past this many lines.
  final int? lineBudget;
}

/// What a driver's platform entry may carry.
///
/// A key written under the wrong driver would otherwise do nothing at all,
/// which is the config-file version of a silent drop.
typedef _Accepts = ({
  Set<String> keys,
  Set<IncludeKind> include,
  Set<String> deps,
});

const _accepts = <Driver, _Accepts>{
  Driver.c: (
    keys: {'headers', 'build'},
    include: {
      IncludeKind.functions,
      IncludeKind.structs,
      IncludeKind.enums,
      IncludeKind.globals,
      IncludeKind.typedefs,
    },
    deps: {'pkg_config'},
  ),
  Driver.objc: (
    keys: {'headers', 'build'},
    include: {
      IncludeKind.types,
      IncludeKind.protocols,
      IncludeKind.functions,
      IncludeKind.structs,
      IncludeKind.enums,
    },
    deps: {},
  ),
  Driver.swift: (
    keys: {'wrapper', 'module', 'sources'},
    include: {IncludeKind.types, IncludeKind.protocols},
    deps: {'swiftpm'},
  ),
  Driver.jvm: (
    keys: {'compile_sdk', 'kotlin', 'wrapper'},
    include: {IncludeKind.classes},
    deps: {'maven', 'repositories'},
  ),
  Driver.winmd: (
    keys: {},
    include: {
      IncludeKind.types,
      IncludeKind.functions,
      IncludeKind.structs,
      IncludeKind.enums,
    },
    deps: {'nuget'},
  ),
  Driver.dts: (
    keys: {},
    include: {IncludeKind.exports, IncludeKind.types},
    deps: {'npm'},
  ),
  Driver.dbus: (keys: {'xml'}, include: {}, deps: {}),
};

/// Reads [source] as `bindsmith.yaml`.
///
/// [sourceUrl] is the file the text came from; it appears in every message, so
/// pass it whenever the text was read from disk. Throws [ConfigException] with
/// every problem found, never only the first.
BindsmithConfig loadBindsmithConfig(String source, {Uri? sourceUrl}) {
  final YamlNode root;
  try {
    root = loadYamlNode(source, sourceUrl: sourceUrl);
  } on YamlException catch (e) {
    throw ConfigException([e.span?.message(e.message) ?? e.message]);
  }

  final problems = <String>[];
  validateAgainstSchema(root, bindsmithSchema, problems);
  // The rest reads the tree as the schema describes it, so nothing continues
  // past a shape that did not hold.
  if (problems.isNotEmpty) throw ConfigException(problems);

  final map = root as YamlMap;
  final name = map._string('name')!;
  final platforms = _platforms(map._map('platforms')!, problems);
  _underLib(map.nodes['output'], problems);
  _underLib(map._map('facade')?.nodes['library'], problems);
  final config = BindsmithConfig(
    name: name,
    output: map._string('output')!,
    facade: _facade(map._map('facade'), name),
    platforms: platforms,
    fixups: _fixups(map._list('fixups'), problems),
    verify: _verify(map._map('verify'), platforms.keys.toSet(), problems),
  );
  if (problems.isNotEmpty) throw ConfigException(problems);
  return config;
}

/// Generated Dart has to live under `lib/`, and not only by convention: a
/// binding is reached by a `package:` URI and its `@DefaultAsset` is named
/// after that URI, neither of which exists for a file outside `lib/`.
void _underLib(YamlNode? node, List<String> problems) {
  if (node == null) return;
  final path = p.url.normalize((node.value as String).replaceAll(r'\', '/'));
  if (path == 'lib' || p.url.isWithin('lib', path)) return;
  problems.add(
    node.span.message('"$path" is outside lib/, so it has no package: URI'),
  );
}

FacadeConfig _facade(YamlMap? node, String name) => FacadeConfig(
  library: node?._string('library') ?? 'lib/$name.dart',
  unsupported: switch (node?._string('unsupported')) {
    'stub' => Unsupported.stub,
    'omit' => Unsupported.omit,
    _ => Unsupported.throw_,
  },
);

Map<Platform, PlatformConfig> _platforms(YamlMap node, List<String> problems) {
  final own = <Platform, PlatformConfig>{};
  final inherited = <Platform, ({String from, YamlNode at})>{};

  for (final entry in node.nodes.entries) {
    final platform = Platform.values.byName(
      (entry.key as YamlNode).value as String,
    );
    final spec = entry.value as YamlMap;
    final from = spec._string('inherit');
    if (from != null) {
      if (spec.length > 1) {
        problems.add(
          spec.nodes['inherit']!.span.message(
            'a platform that inherits takes nothing else; move these keys to '
            '"$from" or drop the inherit',
          ),
        );
      }
      inherited[platform] = (from: from, at: spec.nodes['inherit']!);
      continue;
    }
    final config = _platform(platform, spec, problems);
    if (config != null) own[platform] = config;
  }

  final all = {...own};
  for (final entry in inherited.entries) {
    final from = Platform.values.byName(entry.value.from);
    final source = own[from];
    if (source == null) {
      problems.add(
        entry.value.at.span.message(
          inherited.containsKey(from)
              ? '"${entry.value.from}" inherits as well; inherit from a '
                    'platform that is configured directly'
              : '"${entry.value.from}" is not configured, so there is nothing '
                    'to inherit',
        ),
      );
      continue;
    }
    all[entry.key] = source;
  }
  return all;
}

PlatformConfig? _platform(
  Platform platform,
  YamlMap spec,
  List<String> problems,
) {
  final driverNode = spec.nodes['driver'];
  if (driverNode == null) {
    problems.add(
      spec.span.message(
        'needs a "driver", or an "inherit" naming a platform '
        'that has one',
      ),
    );
    return null;
  }
  final driver = Driver.values.byName(driverNode.value as String);
  final accepts = _accepts[driver]!;

  for (final key in spec.keys.cast<String>()) {
    const shared = {'driver', 'inherit', 'deps', 'include'};
    if (shared.contains(key) || accepts.keys.contains(key)) continue;
    problems.add(
      spec.nodes[key]!.span.message(
        '"$key" is not something the ${driver.name} driver reads',
      ),
    );
  }

  final include = <IncludeKind, List<String>>{};
  for (final entry in (spec._map('include')?.nodes ?? const {}).entries) {
    final kind = IncludeKind.values.byName(
      (entry.key as YamlNode).value as String,
    );
    if (!accepts.include.contains(kind)) {
      problems.add(
        (entry.key as YamlNode).span.message(
          'the ${driver.name} driver has no ${kind.name}; it selects '
          '${_names(accepts.include.map((k) => k.name))}',
        ),
      );
      continue;
    }
    include[kind] = [
      for (final p in (entry.value as YamlList).nodes) p.value as String,
    ];
  }

  final compileSdk = _compileSdk(spec, problems);
  if (platform == Platform.android &&
      driver == Driver.jvm &&
      compileSdk == null &&
      spec.nodes['compile_sdk'] == null) {
    final where = spec.nodes.isEmpty
        ? spec.span
        : (spec.nodes.keys.first as YamlNode).span;
    problems.add(
      where.message(
        'android on the jvm driver needs "compile_sdk", the API level whose '
        'android.jar jnigen binds against — for example compile_sdk: 35 or '
        'compile_sdk: "36.1"',
      ),
    );
  }

  final xml = spec._strings('xml');
  if (driver == Driver.dbus && xml.isEmpty) {
    final where =
        spec.nodes['xml']?.span ??
        (spec.nodes.isEmpty
            ? spec.span
            : (spec.nodes.keys.first as YamlNode).span);
    problems.add(
      where.message(
        'the dbus driver needs "xml", the introspection files — for example '
        'xml: [third_party/com.example.Greeter.xml]',
      ),
    );
  }

  final module = spec._string('module');
  if (driver == Driver.swift &&
      module == null &&
      spec.nodes['module'] == null) {
    final where = spec.nodes.isEmpty
        ? spec.span
        : (spec.nodes.keys.first as YamlNode).span;
    problems.add(
      where.message(
        'the swift driver needs "module", the name the sources compile into — '
        'for example module: GreeterKit',
      ),
    );
  }

  final sources = spec._strings('sources');
  if (driver == Driver.swift &&
      sources.isEmpty &&
      _wrapper(spec, problems) != WrapperMode.only) {
    final where =
        spec.nodes['sources']?.span ??
        spec.nodes['module']?.span ??
        (spec.nodes.isEmpty
            ? spec.span
            : (spec.nodes.keys.first as YamlNode).span);
    problems.add(
      where.message(
        'the swift driver needs "sources", the Swift files to bind — '
        'for example sources: [swift/Greeter.swift]',
      ),
    );
  }

  return PlatformConfig(
    driver: driver,
    headers: spec._strings('headers'),
    deps: _deps(spec._map('deps'), driver, accepts.deps, problems),
    include: include,
    compileSdk: compileSdk,
    xml: xml,
    suspend: spec._map('kotlin')?._string('suspend') == 'callback'
        ? Async.callback
        : Async.future,
    flow: spec._map('kotlin')?._string('flow') == 'callback'
        ? Async.callback
        : Async.stream,
    wrapper: _wrapper(spec, problems),
    module: module,
    sources: sources,
    build: switch (spec._map('build')) {
      null => null,
      final build => BuildConfig(
        build._string('hook') == 'native_toolchain_cmake'
            ? BuildHook.cmake
            : BuildHook.c,
        build._strings('sources'),
      ),
    },
  );
}

DepsConfig _deps(
  YamlMap? node,
  Driver driver,
  Set<String> accepted,
  List<String> problems,
) {
  if (node == null) return const DepsConfig();
  for (final key in node.keys.cast<String>()) {
    if (accepted.contains(key)) continue;
    problems.add(
      node.nodes[key]!.span.message(
        'the ${driver.name} driver does not resolve $key packages'
        '${accepted.isEmpty ? '' : '; it takes ${_names(accepted)}'}',
      ),
    );
  }

  final maven = <Coordinate>[];
  for (final item in node._list('maven')?.nodes ?? const <YamlNode>[]) {
    try {
      maven.add(Coordinate.parse(item.value as String));
    } on ArgumentError {
      problems.add(
        item.span.message('expected a group:artifact:version coordinate'),
      );
    }
  }

  final repositories = <Uri>[];
  for (final item in node._list('repositories')?.nodes ?? const <YamlNode>[]) {
    final url = Uri.tryParse(item.value as String);
    // `file:` is a vendored or mirrored repository on disk, which Gradle
    // writes the same way (`maven { url = uri("file:///…") }`). Everything
    // that crosses a network has to be `https:`, because an artifact fetched
    // over plain http is an artifact whoever is between you and the mirror
    // chose — and it is then pinned in the lockfile as if it were yours.
    if (url == null || !(url.isScheme('https') || url.isScheme('file'))) {
      problems.add(
        item.span.message('expected an https:// or file:// repository URL'),
      );
      continue;
    }
    repositories.add(url);
  }

  final packages = <SwiftPackage>[];
  for (final item in node._list('swiftpm')?.nodes ?? const <YamlNode>[]) {
    final package = item as YamlMap;
    final url = Uri.tryParse(package._string('url')!);
    if (url == null || !url.hasScheme) {
      problems.add(
        package.nodes['url']!.span.message('expected a package URL'),
      );
      continue;
    }
    packages.add(SwiftPackage(url, package._string('from')!));
  }

  return DepsConfig(
    maven: maven,
    repositories: repositories,
    swiftpm: packages,
    npm: node._strings('npm'),
    nuget: node._strings('nuget'),
    pkgConfig: node._strings('pkg_config'),
  );
}

List<Fixup> _fixups(YamlList? node, List<String> problems) {
  final fixups = <Fixup>[];
  for (final item in node?.nodes ?? const <YamlNode>[]) {
    final fixup = item as YamlMap;
    final match = fixup._map('match')!;
    final SymbolPattern pattern;
    try {
      pattern = SymbolPattern.parse(match._string('symbol')!);
    } on FormatException catch (e) {
      problems.add(match.nodes['symbol']!.span.message(e.message));
      continue;
    }
    fixups.add(
      Fixup(
        match: pattern,
        platform: switch (match._string('platform')) {
          null => null,
          final name => Platform.values.byName(name),
        },
        rename: fixup._string('rename'),
        hide: fixup.nodes['hide']?.value as bool? ?? false,
        threading: switch (fixup._string('threading')) {
          'main' => Threading.main,
          'any' => Threading.any,
          _ => null,
        },
        returns: switch (fixup._map('nullability')?._string('returns')) {
          'nonnull' => Nullability.nonNull,
          'nullable' => Nullability.nullable,
          'unknown' => Nullability.unknown,
          _ => null,
        },
        ack: fixup.nodes['ack']?.value as bool? ?? false,
      ),
    );
  }
  return fixups;
}

VerifyConfig _verify(
  YamlMap? node,
  Set<Platform> configured,
  List<String> problems,
) {
  if (node == null) return const VerifyConfig();
  final compile = <Platform>{};
  for (final item in node._list('compile')?.nodes ?? const <YamlNode>[]) {
    final platform = Platform.values.byName(item.value as String);
    if (!configured.contains(platform)) {
      problems.add(
        item.span.message(
          'nothing is generated for ${platform.name}, so there is nothing to '
          'compile; add it under platforms: or drop it here',
        ),
      );
      continue;
    }
    compile.add(platform);
  }
  return VerifyConfig(
    markers: node._string('markers') == 'warn'
        ? MarkerPolicy.warn
        : MarkerPolicy.error,
    compile: compile,
    lineBudget: node._map('size_budget')?.nodes['lines']?.value as int?,
  );
}

WrapperMode _wrapper(YamlMap spec, List<String> problems) {
  final node = spec.nodes['wrapper'];
  final value = node?.value as String?;
  if (value == null) return WrapperMode.auto;
  return switch (value) {
    'auto' => WrapperMode.auto,
    'off' => WrapperMode.off,
    'only' => WrapperMode.only,
    'none' => () {
      problems.add(
        node!.span.message(
          '"none" is not valid; use off (one of auto, off, only)',
        ),
      );
      return WrapperMode.off;
    }(),
    _ => () {
      problems.add(
        node!.span.message('"wrapper" must be one of auto, off, only'),
      );
      return WrapperMode.auto;
    }(),
  };
}

String? _compileSdk(YamlMap spec, List<String> problems) {
  final node = spec.nodes['compile_sdk'];
  if (node == null) return null;
  final value = node.value;
  if (value is int) return value.toString();
  if (value is String && RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
    return value;
  }
  problems.add(
    node.span.message(
      'expected an integer or a string such as "36.1" for compile_sdk',
    ),
  );
  return null;
}

String _names(Iterable<String> values) {
  final all = values.toList();
  if (all.length < 2) return all.join();
  return '${all.take(all.length - 1).join(', ')} and ${all.last}';
}

/// Typed reads of a mapping the schema has already checked, so the casts here
/// cannot fail.
extension on YamlMap {
  YamlMap? _map(String key) => nodes[key] as YamlMap?;
  YamlList? _list(String key) => nodes[key] as YamlList?;
  String? _string(String key) => nodes[key]?.value as String?;
  List<String> _strings(String key) => [
    for (final item in _list(key)?.nodes ?? const <YamlNode>[])
      item.value as String,
  ];
}
