import 'package:bindsmith/bindsmith.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../golden.dart';

/// The configuration published in the report and in `plan.md`, verbatim. If it
/// stops loading, either the loader or the documentation is wrong.
const documented = r'''
# yaml-language-server: $schema=…/bindsmith.schema.json
name: my_sdk
output: lib/src/generated
facade:
  library: lib/my_sdk.dart
  unsupported: throw          # throw | stub | omit

platforms:
  android:
    driver: jvm
    compile_sdk: 35
    deps: { maven: [com.example:sdk-android:2.3.1] }
    include: { classes: [com.example.sdk.Client] }
    kotlin: { suspend: future, flow: stream }
  ios:
    driver: swift
    module: ClientKit
    sources: [swift/Client.swift]
    deps: { swiftpm: [{ url: https://github.com/example/sdk-ios, from: 2.3.0 }] }
    include: { types: [Client, ClientDelegate] }
    wrapper: auto             # @objc wrapper for Swift-only members
  macos: { inherit: ios }
  windows:
    driver: c
    headers: [third_party/sdk/include/sdk.h]
    include: { functions: ["sdk_*"], structs: ["sdk_*"] }
    build: { hook: native_toolchain_c, sources: [src/shim.c] }
  linux: { inherit: windows }
  web:
    driver: dts
    deps: { npm: ["@example/sdk@2.3.1"] }
    include: { exports: [Client, ClientOptions] }

fixups:
  - match: { platform: android, symbol: "Client#connect$2" }
    rename: connectWithTimeout
  - match: { symbol: "Client.*Legacy*" }
    hide: true
  - match: { platform: ios, symbol: Client.onEvent }
    threading: main

verify:
  markers: error
  compile: [android, ios, macos, windows, linux, web]
  size_budget: { lines: 40000 }
''';

/// The smallest configuration that loads, for tests that change one thing.
const minimal = '''
name: my_sdk
output: lib/src/generated
platforms:
  linux:
    driver: c
    headers: [sdk.h]
''';

/// The problems [loadBindsmithConfig] reports for [yaml], or an empty list.
List<String> problems(String yaml) {
  try {
    loadBindsmithConfig(yaml, sourceUrl: Uri.parse('bindsmith.yaml'));
    return const [];
  } on ConfigException catch (e) {
    return e.problems;
  }
}

BindsmithConfig load(String yaml) =>
    loadBindsmithConfig(yaml, sourceUrl: Uri.parse('bindsmith.yaml'));

void main() {
  group('compile_sdk', () {
    test('is required for android on jvm', () {
      final found = problems('''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart
platforms:
  android:
    driver: jvm
''');
      expect(found.any((p) => p.contains('compile_sdk')), isTrue);
      expect(
        found.any((p) => p.contains('android on the jvm driver needs')),
        isTrue,
      );
    });

    test('accepts an integer', () {
      final config = load('''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart
platforms:
  android:
    driver: jvm
    compile_sdk: 36
''');
      expect(config.platforms[Platform.android]!.compileSdk, '36');
    });

    test('accepts a minor release string', () {
      final config = load('''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart
platforms:
  android:
    driver: jvm
    compile_sdk: "36.1"
''');
      expect(config.platforms[Platform.android]!.compileSdk, '36.1');
    });

    test('rejects the wrong type', () {
      final found = problems('''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart
platforms:
  android:
    driver: jvm
    compile_sdk: [35]
''');
      expect(found.any((p) => p.contains('compile_sdk')), isTrue);
      expect(found.any((p) => p.contains('integer or a string')), isTrue);
    });
  });

  group('dbus xml', () {
    test('is required', () {
      final found = problems('''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart
platforms:
  linux:
    driver: dbus
''');
      expect(found.single, contains('the dbus driver needs "xml"'));
    });

    test('is loaded', () {
      final config = load('''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart
platforms:
  linux:
    driver: dbus
    xml: [com.example.Greeter.xml]
''');
      expect(config.platforms[Platform.linux]!.xml, [
        'com.example.Greeter.xml',
      ]);
    });
  });

  group('the documented configuration', () {
    test('loads', () {
      final config = load(documented);
      expect(config.name, 'my_sdk');
      expect(config.output, 'lib/src/generated');
      expect(config.facade.library, 'lib/my_sdk.dart');
      expect(config.facade.unsupported, Unsupported.throw_);
      expect(config.platforms.keys, Platform.values.toSet());
      expect(config.verify.markers, MarkerPolicy.error);
      expect(config.verify.compile, Platform.values.toSet());
      expect(config.verify.lineBudget, 40000);
    });

    test('reads each driver and its own keys', () {
      final config = load(documented);
      final android = config.platforms[Platform.android]!;
      expect(android.driver, Driver.jvm);
      expect(
        android.deps.maven.single.toString(),
        'com.example:sdk-android:2.3.1',
      );
      expect(android.include[IncludeKind.classes], ['com.example.sdk.Client']);
      expect(android.suspend, Async.future);
      expect(android.flow, Async.stream);

      final ios = config.platforms[Platform.ios]!;
      expect(ios.driver, Driver.swift);
      expect(ios.wrapper, WrapperMode.auto);
      expect(ios.deps.swiftpm.single.url.host, 'github.com');
      expect(ios.deps.swiftpm.single.from, '2.3.0');

      final windows = config.platforms[Platform.windows]!;
      expect(windows.driver, Driver.c);
      expect(windows.headers, ['third_party/sdk/include/sdk.h']);
      expect(windows.build!.hook, BuildHook.c);
      expect(windows.build!.sources, ['src/shim.c']);

      expect(config.platforms[Platform.web]!.deps.npm, ['@example/sdk@2.3.1']);
    });

    test('an inheriting platform gets the whole configuration it names', () {
      final config = load(documented);
      expect(
        config.platforms[Platform.macos],
        same(config.platforms[Platform.ios]),
      );
      expect(config.platforms[Platform.linux]!.headers, [
        'third_party/sdk/include/sdk.h',
      ]);
    });

    test('the fixups reach the pass that applies them', () {
      final fixups = load(documented).fixups;
      expect(fixups, hasLength(3));
      expect(fixups[0].platform, Platform.android);
      expect(fixups[0].rename, 'connectWithTimeout');
      expect(fixups[0].match.source, r'Client#connect$2');
      expect(fixups[1].hide, isTrue);
      expect(fixups[1].platform, isNull);
      expect(fixups[2].threading, Threading.main);
    });
  });

  group('defaults', () {
    test('the facade is named after the library and throws where a platform '
        'has nothing', () {
      final config = load(minimal);
      expect(config.facade.library, 'lib/my_sdk.dart');
      expect(config.facade.unsupported, Unsupported.throw_);
      expect(config.fixups, isEmpty);
      expect(config.verify.markers, MarkerPolicy.error);
      expect(config.verify.compile, isEmpty);
      expect(config.verify.lineBudget, isNull);
    });

    test('Kotlin async and the Swift wrapper are on', () {
      final config = load('''
name: my_sdk
output: lib/gen
platforms:
  android: { driver: jvm, compile_sdk: 35 }
  ios: { driver: swift, module: Kit, sources: [a.swift] }
''');
      expect(config.platforms[Platform.android]!.suspend, Async.future);
      expect(config.platforms[Platform.android]!.flow, Async.stream);
      expect(config.platforms[Platform.ios]!.wrapper, WrapperMode.auto);
    });

    test('wrapper accepts auto, off, and only', () {
      for (final mode in WrapperMode.values) {
        final config = load(
          'name: s\noutput: lib/gen\nplatforms:\n'
          '  ios:\n    driver: swift\n    module: Kit\n'
          '    sources: [a.swift]\n    wrapper: ${mode.name}\n',
        );
        expect(config.platforms[Platform.ios]!.wrapper, mode);
      }
    });

    test('wrapper: none is rejected', () {
      final found = problems(
        'name: s\noutput: lib/gen\nplatforms:\n'
        '  ios:\n    driver: swift\n    module: Kit\n'
        '    sources: [a.swift]\n    wrapper: none\n',
      );
      expect(found.single, contains('auto, off and only'));
    });

    test('wrapper garbage is rejected', () {
      final found = problems(
        'name: s\noutput: lib/gen\nplatforms:\n'
        '  ios:\n    driver: swift\n    module: Kit\n'
        '    sources: [a.swift]\n    wrapper: maybe\n',
      );
      expect(found.single, contains('auto, off and only'));
    });

    test('kotlin: and wrapper: can turn them off', () {
      final config = load('''
name: my_sdk
output: lib/gen
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    kotlin: { suspend: callback, flow: callback }
  ios:
    driver: swift
    module: Kit
    sources: [a.swift]
    wrapper: off
''');
      expect(config.platforms[Platform.android]!.suspend, Async.callback);
      expect(config.platforms[Platform.android]!.flow, Async.callback);
      expect(config.platforms[Platform.ios]!.wrapper, WrapperMode.off);
    });
  });

  group('shape errors carry a place', () {
    test('an unknown key names the alternatives', () {
      final found = problems('''
name: my_sdk
outupt: gen
platforms:
  linux: { driver: c }
''');
      // A typo in a required key is two problems, and saying both is the
      // point: the key that is missing and the key that is not a key.
      expect(found, hasLength(2));
      expect(found.first, contains('missing "output"'));
      expect(found.last, contains('unknown key "outupt"'));
      expect(found.last, contains('line 2, column 1'));
      expect(found.last, contains('name, output, facade'));
    });

    test('a missing required key is reported', () {
      expect(
        problems('output: lib/gen\nplatforms: { linux: { driver: c } }\n')
            .single,
        contains('missing "name"'),
      );
    });

    test('a value of the wrong type is reported where it is written', () {
      final found = problems('''
name: my_sdk
output: lib/gen
platforms:
  linux:
    driver: c
    headers: sdk.h
''');
      expect(found.single, contains('expected a list here'));
      expect(found.single, contains('line 6, column 14'));
    });

    test('a value outside an enum lists what is allowed', () {
      final found = problems('''
name: my_sdk
output: lib/gen
platforms:
  linux: { driver: rust }
''');
      expect(found.single, contains('"rust" is not one of'));
      expect(found.single, contains('dts and dbus'));
    });

    test('a platform that is not a Flutter platform is unknown', () {
      expect(
        problems(
          'name: s\noutput: lib/gen\nplatforms: { fuchsia: { driver: c } }\n',
        ).single,
        contains('unknown key "fuchsia"'),
      );
    });

    test('YAML that does not parse is reported, not thrown raw', () {
      expect(problems('name: [\n'), hasLength(1));
    });

    test('an empty file is a mapping that is missing', () {
      expect(problems('').single, contains('expected a mapping here'));
    });
  });

  group('swift driver', () {
    test('needs module and sources', () {
      final found = problems(
        'name: s\noutput: lib/gen\nplatforms:\n  ios: { driver: swift }\n',
      );
      expect(found, hasLength(2));
      expect(found.any((p) => p.contains('"module"')), isTrue);
      expect(found.any((p) => p.contains('"sources"')), isTrue);
    });

    test('wrapper: only does not require sources', () {
      final config = load(
        'name: s\noutput: lib/gen\nplatforms:\n'
        '  ios:\n    driver: swift\n    module: Kit\n    wrapper: only\n',
      );
      expect(config.platforms[Platform.ios]!.wrapper, WrapperMode.only);
      expect(config.platforms[Platform.ios]!.sources, isEmpty);
    });
  });

  group('meaning errors', () {
    test('a key belonging to another driver is not silently ignored', () {
      final found = problems('''
name: my_sdk
output: lib/gen
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    headers: [sdk.h]
''');
      expect(
        found.single,
        contains(
          '"headers" is not something the jvm '
          'driver reads',
        ),
      );
      expect(found.single, contains('line 7, column 14'));
    });

    test('an include kind the driver has no notion of is reported', () {
      final found = problems('''
name: my_sdk
output: lib/gen
platforms:
  linux:
    driver: c
    include: { classes: [Client] }
''');
      expect(found.single, contains('the c driver has no classes'));
      expect(found.single, contains('functions, structs'));
    });

    test('a package kind the driver cannot resolve is reported', () {
      final found = problems('''
name: my_sdk
output: lib/gen
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    deps: { npm: ["@example/sdk"] }
''');
      expect(found.single, contains('does not resolve npm packages'));
      expect(found.single, contains('maven and repositories'));
    });

    test('a Maven coordinate is parsed at load, not at download', () {
      final found = problems('''
name: my_sdk
output: lib/gen
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    deps: { maven: [com.example:sdk] }
''');
      expect(found.single, contains('group:artifact:version'));
      expect(found.single, contains('line 7, column 21'));
    });

    test('a repository that is not https or file is refused', () {
      // Not pedantry: an artifact fetched over plain http is one whoever is
      // between you and the mirror chose, and it is then pinned in the lock
      // as if it were yours.
      expect(
        problems('''
name: my_sdk
output: lib/gen
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    deps: { repositories: ["http://insecure.example"] }
''').single,
        contains('expected an https:// or file:// repository URL'),
      );
    });

    test('a file: repository is a repository, as it is to Gradle', () {
      final config = loadBindsmithConfig('''
name: my_sdk
output: lib/gen
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    deps: { repositories: ["file:///opt/mirror/maven2/"] }
''');
      expect(
        config.platforms[Platform.android]!.deps.repositories.single.path,
        '/opt/mirror/maven2/',
      );
    });

    test('a platform with neither driver nor inherit says so', () {
      expect(
        problems('name: s\noutput: lib/gen\nplatforms: { linux: {} }\n').single,
        contains('needs a "driver"'),
      );
    });

    test('inheriting from a platform that is not configured is reported', () {
      expect(
        problems('''
name: my_sdk
output: lib/gen
platforms:
  linux: { driver: c }
  macos: { inherit: ios }
''').single,
        contains('"ios" is not configured'),
      );
    });

    test('a chain of inherits is refused, not followed', () {
      expect(
        problems('''
name: my_sdk
output: lib/gen
platforms:
  ios: { driver: swift, module: Kit, sources: [a.swift] }
  macos: { inherit: ios }
  linux: { inherit: macos }
''').single,
        contains('"macos" inherits as well'),
      );
    });

    test('inherit alongside other keys is a mistake', () {
      expect(
        problems('''
name: my_sdk
output: lib/gen
platforms:
  ios: { driver: swift, module: Kit, sources: [a.swift] }
  macos: { inherit: ios, wrapper: off }
''').single,
        contains('a platform that inherits takes nothing else'),
      );
    });

    test('compiling a platform nothing is generated for is reported', () {
      expect(
        problems('''
$minimal
verify:
  compile: [web]
''').single,
        contains('nothing is generated for web'),
      );
    });

    test('an empty symbol pattern is reported at the pattern', () {
      expect(
        problems('''
$minimal
fixups:
  - match: { symbol: "" }
    hide: true
''').single,
        contains('symbol pattern must not be empty'),
      );
    });

    test('every problem is reported, not the first', () {
      final found = problems('''
name: my_sdk
output: lib/gen
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    headers: [sdk.h]
    deps: { maven: [nope] }
  macos: { inherit: ios }
''');
      expect(found, hasLength(3));
      expect(found.join('\n'), contains('"headers" is not something'));
      expect(found.join('\n'), contains('group:artifact:version'));
      expect(found.join('\n'), contains('"ios" is not configured'));
    });
  });

  group('the exported schema', () {
    test('matches schema/bindsmith.schema.json', () {
      expectGolden(
        p.join('..', '..', 'schema', 'bindsmith.schema.json'),
        bindsmithSchemaJson(),
      );
    });

    test('uses only the keywords the validator acts on', () {
      // A keyword the schema uses and the validator ignores would be a rule an
      // editor enforces and bindsmith quietly does not.
      final unknown = <String>{};
      void walk(Map<String, Object?> schema) {
        for (final entry in schema.entries) {
          if (!schemaKeywords.contains(entry.key)) {
            unknown.add(entry.key);
            continue;
          }
          switch (entry.key) {
            // Nested schemas, keyed by name.
            case 'properties':
            case r'$defs':
              for (final sub in (entry.value! as Map<String, Object?>).values) {
                walk(sub! as Map<String, Object?>);
              }
            // One nested schema.
            case 'items':
              walk(entry.value! as Map<String, Object?>);
          }
        }
      }

      walk(bindsmithSchema);
      expect(unknown, isEmpty);
    });
  });
}
