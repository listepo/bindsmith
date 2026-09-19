/// Where generated files go, and the `hook/build.dart` that builds the native
/// code beside them (plan P1-3, P5-5).
///
/// The layout is the one place that knows a path, so the tests are mostly
/// about agreement rather than about strings: the asset id in the binding, the
/// asset name in the hook and the import in the facade all have to describe the
/// same file, and they are derived from each other here so they cannot drift.
/// The emitted hooks are committed under `fixtures/tool/build_hook/`, so
/// `dart analyze --fatal-infos fixtures` type-checks them against the real
/// `hooks`, `code_assets` and `native_toolchain_*` APIs — the check that
/// catches an upstream rename, where a golden would only notice our own edits.
/// Not under `lib/`, because a file there may not import a dev dependency, and
/// not at `hook/build.dart`, where it would run during every fixture build and
/// try to compile sources that do not exist.
library;

import 'package:bindsmith/bindsmith.dart';
import 'package:test/test.dart';

import '../golden.dart';

const _yaml = '''
name: my_sdk
output: lib/src/generated
facade:
  library: lib/my_sdk.dart
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    include: { classes: [com.example.sdk.Client] }
  ios:
    driver: swift
    module: ClientKit
    sources: [swift/Client.swift]
    include: { types: [Client] }
  macos: { inherit: ios }
  windows:
    driver: c
    headers: [third_party/sdk/include/sdk.h]
    build: { hook: native_toolchain_c, sources: [src/shim.c, src/util.c] }
  linux: { inherit: windows }
  web:
    driver: dts
    include: { exports: [Client] }
''';

Layout _layout([String yaml = _yaml]) =>
    Layout(loadBindsmithConfig(yaml), package: 'my_sdk');

/// [_yaml] with `platforms:` replaced, for the cases that need one platform.
String _one(String platform) =>
    '''
name: my_sdk
output: lib/src/generated
platforms:
  $platform
''';

void main() {
  test('a binding is named after its driver, under the platform', () {
    final layout = _layout();
    expect(
      layout.binding(Platform.windows),
      'lib/src/generated/windows/c.g.dart',
    );
    expect(layout.binding(Platform.linux), 'lib/src/generated/linux/c.g.dart');
    expect(layout.binding(Platform.ios), 'lib/src/generated/ios/swift.g.dart');
    expect(
      layout.binding(Platform.android),
      'lib/src/generated/android/jvm.g.dart',
    );
    expect(layout.binding(Platform.web), 'lib/src/generated/web/dts.g.dart');
    // An inheriting platform still gets its own file: the driver is the same,
    // the target is not, and one file cannot carry two `@DefaultAsset`s.
    expect(layout.binding(Platform.macos), isNot(layout.binding(Platform.ios)));
  });

  test('the Objective-C glue sits beside the binding it belongs to', () {
    expect(_layout().glue(Platform.ios), 'lib/src/generated/ios/swift.g.m');
  });

  test('an asset id names the Dart file that declares it', () {
    expect(
      _layout().assetId(Platform.windows),
      'package:my_sdk/src/generated/windows/c.g.dart',
    );
  });

  test('the facade entry goes where configured, its groups beside it', () {
    final layout = _layout();
    expect(layout.facade('my_sdk.g.dart'), 'lib/my_sdk.dart');
    expect(layout.facade('my_sdk_io.g.dart'), 'lib/my_sdk_io.g.dart');
    expect(layout.facade('my_sdk_web.g.dart'), 'lib/my_sdk_web.g.dart');
  });

  test('bindings are imported relative to the facade, in platform order', () {
    final imports = _layout().bindingImports;
    expect(imports.keys, Platform.values);
    expect(imports[Platform.windows], 'src/generated/windows/c.g.dart');
    // The same map is what emitFacade is handed, so the two cannot disagree
    // about where a binding is.
    final facade = emitFacade(
      {
        Platform.windows: const [
          FunctionDecl(
            id: 'ping',
            name: 'ping',
            platform: Platform.windows,
            returns: TypeRef('int'),
          ),
        ],
      },
      FacadeOptions(
        library: 'my_sdk',
        bindings: {Platform.windows: imports[Platform.windows]!},
      ),
    );
    expect(
      facade['my_sdk_io.g.dart'],
      contains("import 'src/generated/windows/c.g.dart'"),
    );
  });

  test('a facade under a subdirectory walks back up to the bindings', () {
    final layout = Layout(
      loadBindsmithConfig('''
name: my_sdk
output: lib/src/generated
facade: { library: lib/src/my_sdk.dart }
platforms: { linux: { driver: c, headers: [sdk.h] } }
'''),
      package: 'my_sdk',
    );
    expect(layout.bindingImports[Platform.linux], 'generated/linux/c.g.dart');
    expect(layout.facade('my_sdk_io.g.dart'), 'lib/src/my_sdk_io.g.dart');
  });

  test('platforms that build native code are listed in a fixed order', () {
    // Written windows-then-linux in the YAML, and inherited in that direction,
    // but the order comes from the platform enum so a reordered config file
    // cannot change the generated hook (rule 6).
    expect(_layout().builds.keys, [Platform.windows, Platform.linux]);
    expect(_layout().builds[Platform.linux]!.sources, [
      'src/shim.c',
      'src/util.c',
    ]);
  });

  test('the build hook is one guard per platform, and analyzes', () {
    final hook = emitBuildHook(_layout())!;
    expect(hook, startsWith('// GENERATED BY bindsmith — do not edit.\n'));
    // Every platform that configured a build is guarded by its own target OS:
    // one hook file runs for all of them, once per target.
    expect(hook, containsCode('if (input.config.code.targetOS == OS.windows)'));
    expect(hook, containsCode('if (input.config.code.targetOS == OS.linux)'));
    // The asset the hook declares is the one the binding will ask for.
    expect(hook, containsCode("assetName: 'src/generated/windows/c.g.dart'"));
    expect(hook, containsCode("sources: ['src/shim.c', 'src/util.c']"));
    expect(hook, isNot(contains('native_toolchain_cmake')));
    expectGolden('../../fixtures/tool/build_hook/build.dart', hook);
  });

  test('a cmake build runs CMakeLists.txt and collects what it installed', () {
    final hook = emitBuildHook(
      _layout(
        _one(
          'linux: { driver: c, headers: [sdk.h], '
          'build: { hook: native_toolchain_cmake, sources: [src/native] } }',
        ),
      ),
    )!;
    expect(
      hook,
      containsCode(
        "import 'package:native_toolchain_cmake"
        "/native_toolchain_cmake.dart';",
      ),
    );
    expect(hook, isNot(contains('native_toolchain_c/')));
    expect(
      hook,
      containsCode("sourceDir: input.packageRoot.resolve('src/native')"),
    );
    // CMake decides the built file's name, so the library is installed into
    // the hook's output directory and found there.
    expect(
      hook,
      containsCode("names: {'my_sdk': 'src/generated/linux/c.g.dart'}"),
    );
    expect(
      hook,
      containsCode("outDir: input.outputDirectory.resolve('install')"),
    );
    expectGolden('../../fixtures/tool/build_hook/build_cmake.dart', hook);
  });

  test('no build hook is written when nothing asked for one', () {
    expect(emitBuildHook(_layout(_one('web: { driver: dts }'))), isNull);
  });

  test('a build that cannot be carried out is refused, not written', () {
    // The web has no native build to configure.
    expect(
      () => emitBuildHook(
        _layout(
          _one(
            'web: { driver: c, headers: [a.h], '
            'build: { hook: native_toolchain_c, sources: [a.c] } }',
          ),
        ),
      ),
      throwsA(
        isArgumentError
            .having((e) => e.invalidValue, 'invalidValue', 'web')
            .having((e) => e.message, 'message', contains('remove "build:"')),
      ),
    );
    // native_toolchain_c compiles sources, so it needs some.
    expect(
      () => emitBuildHook(
        _layout(
          _one(
            'linux: { driver: c, headers: [a.h], '
            'build: { hook: native_toolchain_c, sources: [] } }',
          ),
        ),
      ),
      throwsArgumentError,
    );
    // native_toolchain_cmake runs one CMakeLists.txt, so two directories are
    // ambiguous rather than a build of both.
    expect(
      () => emitBuildHook(
        _layout(
          _one(
            'linux: { driver: c, headers: [a.h], build: '
            '{ hook: native_toolchain_cmake, sources: [one, two] } }',
          ),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('a source path that cannot be quoted is refused', () {
    expect(
      () => emitBuildHook(
        _layout(
          _one(
            r'linux: { driver: c, headers: [a.h], build: '
            r"{ hook: native_toolchain_c, sources: ['src/$(rm -rf).c'] } }",
          ),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('a Windows source path is written with forward slashes', () {
    final hook = emitBuildHook(
      _layout(
        _one(
          r'linux: { driver: c, headers: [a.h], build: '
          r"{ hook: native_toolchain_c, sources: ['src\shim.c'] } }",
        ),
      ),
    )!;
    expect(hook, containsCode("sources: ['src/shim.c']"));
  });

  test('generated Dart outside lib/ is refused with its line and column', () {
    final problems = () {
      try {
        loadBindsmithConfig('''
name: my_sdk
output: build/generated
facade: { library: out/my_sdk.dart }
platforms: { linux: { driver: c, headers: [a.h] } }
''');
        return const <String>[];
      } on ConfigException catch (e) {
        return e.problems;
      }
    }();
    expect(problems, hasLength(2));
    expect(problems.first, contains('"build/generated" is outside lib/'));
    expect(problems.first, contains('line 2, column 9'));
    expect(problems.last, contains('"out/my_sdk.dart" is outside lib/'));
  });
}
