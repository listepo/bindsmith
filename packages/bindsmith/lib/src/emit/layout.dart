/// Where every generated file goes (plan P1-3).
///
/// Three things have to agree about one path and none of them can see the
/// others: the driver is handed an output path and an asset id before any
/// content exists, the facade imports each binding by a path relative to
/// itself, and `hook/build.dart` names the same asset the binding's
/// `@DefaultAsset` names. So the layout is computed once, here, and the CLI
/// hands the answers out rather than each caller joining paths again.
///
/// Every path is POSIX and relative to the directory holding `bindsmith.yaml`.
/// That is also a usable path on Windows — `dart:io` accepts forward slashes
/// there — so nothing has to convert before touching the filesystem, while
/// import strings, which must be POSIX, are correct as they are.
library;

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../ir/ir.dart';

final class Layout {
  Layout(this.config, {required this.package});

  final BindsmithConfig config;

  /// The enclosing Dart package, read from its `pubspec.yaml`. Asset ids are
  /// `package:<package>/…`, so bindings cannot be placed without it.
  final String package;

  /// `hook/build.dart`, which a Dart package may only have one of.
  static const hook = 'hook/build.dart';

  /// The Gradle script the package's Android library applies for a `jvm`
  /// binding: the Maven dependencies, and [androidRules] as consumer rules.
  static const androidGradle = 'android/bindsmith.gradle';

  /// The R8 keep rules for every class a `jvm` binding looks up by name.
  static const androidRules = 'android/bindsmith-rules.pro';

  /// The generated binding for [platform], e.g.
  /// `lib/src/generated/windows/c.g.dart`.
  String binding(Platform platform) => p.url.join(
    config.output,
    platform.name,
    '${_driver(platform).name}.g.dart',
  );

  /// The Objective-C glue ffigen writes beside a binding, for the drivers that
  /// produce one. Nothing else reads it, so it is never imported.
  String glue(Platform platform) => p.url.setExtension(binding(platform), '.m');

  /// The swift2objc wrapper beside a Swift binding.
  String swiftWrapper(Platform platform, String module) =>
      p.url.join(p.url.dirname(binding(platform)), '$module.g.swift');

  /// The bindsmith `@objc` bridge for Swift members swift2objc drops.
  String swiftBridge(Platform platform, String module) =>
      p.url.join(p.url.dirname(binding(platform)), '$module.bridge.g.swift');

  /// The bindsmith Kotlin bridge for shapes jnigen cannot carry across.
  String kotlinBridge(Platform platform, String package) {
    final simple = package.split('.').last;
    return p.url.join(p.url.dirname(binding(platform)), '$simple.bridge.g.kt');
  }

  /// The asset id the binding's `@DefaultAsset` carries and `hook/build.dart`
  /// declares. Naming it after the Dart file that uses it is the convention
  /// the SDK documents, and it makes the two sides agree by construction.
  String assetId(Platform platform) =>
      'package:$package/${_underLib(binding(platform))}';

  /// Where one file of [emitFacade]'s output goes: the entry point at the
  /// configured path, the group libraries beside it, because the entry point
  /// exports them by bare name.
  String facade(String emitted) => emitted == '${config.name}.g.dart'
      ? config.facade.library
      : p.url.join(p.url.dirname(config.facade.library), emitted);

  /// [FacadeOptions.bindings]: each binding as the facade files import it.
  Map<Platform, String> get bindingImports => {
    for (final platform in Platform.values)
      if (config.platforms.containsKey(platform))
        platform: p.url.relative(
          binding(platform),
          from: p.url.dirname(config.facade.library),
        ),
  };

  /// The platforms that asked for native code to be built, in the order the
  /// hook should test for them. Empty means no `hook/build.dart` is written.
  Map<Platform, BuildConfig> get builds => {
    for (final platform in Platform.values)
      platform: ?config.platforms[platform]?.build,
  };

  Driver _driver(Platform platform) => config.platforms[platform]!.driver;

  /// The part of a path under `lib/`, which is what a `package:` URI names.
  ///
  /// The loader already refuses an output directory anywhere else, so this
  /// only has to strip the prefix.
  String _underLib(String path) => p.url.relative(path, from: 'lib');
}
