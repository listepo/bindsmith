/// `bindsmith doctor` (plan P1-5).
///
/// The probe is injected, so every case here decides what the machine has
/// rather than asking the machine it runs on — the exception being the two
/// checks that look at the file system (libclang, the Android SDK), which are
/// given real directories.
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:bindsmith/bindsmith.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A probe answering from a table, so a tool is present exactly when it is
/// listed.
Probe _probe(Map<String, String> answers) =>
    (executable, args) => answers[executable];

const _versions = {
  'dart': 'Dart SDK version: 3.13.0 (stable)',
  'javac': 'javac 21.0.5',
  'node': 'v24.1.0',
  'swiftc': 'Apple Swift version 6.1',
  'xcrun': '/Applications/Xcode.app/Contents/Developer/SDKs/MacOSX.sdk',
  'pkg-config': '2.3.0',
};

BindsmithConfig _config(String platforms) => loadBindsmithConfig('''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart

platforms:
$platforms
''');

Check _find(List<Check> checks, Tool tool) =>
    checks.singleWhere((c) => c.tool == tool);

String _directory() {
  final dir = io.Directory.systemTemp.createTempSync('bindsmith_doctor_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.path;
}

Future<({int code, String out})> _run(
  String directory,
  List<String> args,
) async {
  final out = StringBuffer();
  final code = await runBindsmith(
    args,
    out: out,
    err: StringBuffer(),
    workingDirectory: directory,
  );
  return (code: code, out: out.toString());
}

void main() {
  group('what a configuration needs', () {
    test('a driver decides most of it, the platform adds the rest', () {
      expect(
        requiredTools(
          _config('''
  linux:
    driver: c
    headers: [demo.h]
  android:
    driver: jvm
    compile_sdk: 35
    deps: { maven: ["com.example:demo:1.0"] }
  web:
    driver: dts
    deps: { npm: ["demo@1.0.0"] }
'''),
          Platform.linux,
        ),
        {Tool.dart, Tool.libclang, Tool.jdk, Tool.androidSdk, Tool.node},
      );
    });

    test('the winmd driver needs nothing beyond Dart', () {
      expect(
        requiredTools(
          _config('  windows:\n    driver: winmd\n'),
          Platform.windows,
        ),
        {Tool.dart},
      );
    });

    test('a Windows build needs a compiler, reading metadata does not', () {
      expect(
        requiredTools(
          _config('''
  windows:
    driver: c
    headers: [demo.h]
    build: { sources: [demo.c] }
'''),
          Platform.windows,
        ),
        contains(Tool.msvc),
      );
    });

    test('a toolchain the host cannot have is not asked for', () {
      final swift = _config(
        '  ios:\n'
        '    driver: swift\n'
        '    module: GreeterKit\n'
        '    sources: [swift/Greeter.swift]\n',
      );
      expect(requiredTools(swift, Platform.macos), {
        Tool.dart,
        Tool.libclang,
        Tool.swiftc,
        Tool.xcode,
      });
      // The same configuration on Linux: Xcode is not a thing to install.
      expect(requiredTools(swift, Platform.linux), {Tool.dart, Tool.libclang});
    });

    test('pkg-config is needed when a dependency names it', () {
      expect(
        requiredTools(
          _config('''
  linux:
    driver: c
    headers: [demo.h]
    deps: { pkg_config: [gtk+-3.0] }
'''),
          Platform.linux,
        ),
        contains(Tool.pkgConfig),
      );
    });
  });

  group('checks', () {
    test('a tool that answers is ok, one that does not says how to get it', () {
      final checks = doctor(
        config: _config('  android:\n    driver: jvm\n    compile_sdk: 35\n'),
        probe: _probe(_versions),
        host: Platform.linux,
        environment: const {},
      );
      expect(_find(checks, Tool.jdk).found, 'javac 21.0.5');
      expect(isOk(_find(checks, Tool.jdk)), isTrue);

      final sdk = _find(checks, Tool.androidSdk);
      expect(isOk(sdk), isFalse);
      expect(sdk.required, isTrue);
      expect(sdk.fix, contains('ANDROID_HOME'));
    });

    test('a version outside the range a generator accepts is a problem', () {
      final checks = doctor(
        config: _config('  android:\n    driver: jvm\n    compile_sdk: 35\n'),
        probe: _probe({..._versions, 'javac': 'javac 24.0.1'}),
        host: Platform.linux,
        environment: const {},
      );
      final jdk = _find(checks, Tool.jdk);
      expect(jdk.found, 'javac 24.0.1');
      expect(jdk.problem, 'jnigen needs 17–21, this is 24');
      expect(isOk(jdk), isFalse);
    });

    test('node 18 is too old for the sidecar', () {
      final checks = doctor(
        config: _config('  web:\n    driver: dts\n'),
        probe: _probe({..._versions, 'node': 'v18.20.4'}),
        host: Platform.linux,
        environment: const {},
      );
      expect(_find(checks, Tool.node).problem, contains('20 or newer'));
    });

    test('the Android SDK is a directory named by the environment, and its '
        'configured platform jar is what jnigen binds against', () {
      final sdk = _directory();
      Check check(String compileSdk) => _find(
        doctor(
          config: _config(
            compileSdk.contains('.')
                ? '  android:\n    driver: jvm\n    compile_sdk: "$compileSdk"\n'
                : '  android:\n    driver: jvm\n    compile_sdk: $compileSdk\n',
          ),
          probe: _probe(_versions),
          host: Platform.linux,
          environment: {'ANDROID_SDK_ROOT': sdk},
        ),
        Tool.androidSdk,
      );
      final bare = check('35');
      expect(bare.found, sdk);
      expect(bare.problem, contains('no android.jar for API 35'));
      expect(bare.fix, contains('sdkmanager "platforms;android-35"'));

      for (final api in ['android-34', 'android-36.1', 'android-35']) {
        io.File(p.join(sdk, 'platforms', api, 'android.jar'))
            .createSync(recursive: true);
      }
      expect(
        check('36.1').found,
        p.join(sdk, 'platforms', 'android-36.1', 'android.jar'),
      );
      expect(isOk(check('35')), isTrue);
    });

    test('libclang is taken from the compiler when no default location has '
        'it', () {
      final dylib = p.join(_directory(), 'libclang.dll');
      io.File(dylib).writeAsStringSync('');
      final checks = doctor(
        config: _config('  windows:\n    driver: c\n    headers: [demo.h]\n'),
        probe: _probe({..._versions, 'clang': dylib}),
        // Windows: a Linux or macOS test machine has none of the locations
        // ffigen looks in first, so the fallback is what answers.
        host: Platform.windows,
        environment: const {},
      );
      expect(_find(checks, Tool.libclang).found, isNotNull);
      expect(_find(checks, Tool.libclang).fix, contains('LLVM'));
    });

    test('nothing is required without a configuration, but everything the '
        'host supports is looked at', () {
      final checks = doctor(
        probe: _probe(const {}),
        host: Platform.linux,
        environment: const {},
      );
      expect(checks.every((c) => !c.required), isTrue);
      expect(
        checks.map((c) => c.tool),
        isNot(contains(Tool.xcode)),
        reason: 'Xcode cannot be installed on Linux',
      );
      expect(checks.map((c) => c.tool), contains(Tool.pkgConfig));
    });
  });

  group('the command', () {
    test('a fresh machine gets a report and exit 0', () async {
      final run = await _run(_directory(), ['doctor']);
      expect(run.code, 0);
      expect(run.out, contains('dart'));
      expect(run.out, contains('ready:'));
    });

    test('--json is the same report for a script', () async {
      final run = await _run(_directory(), ['doctor', '--json']);
      expect(run.code, 0);
      final report = jsonDecode(run.out) as Map<String, Object?>;
      expect(report['ok'], isTrue);
      expect(report['os'], hostPlatform().name);
      final checks = report['checks']! as List<Object?>;
      expect({
        for (final c in checks) (c! as Map<String, Object?>)['tool'],
      }, contains('dart'));
      expect((checks.first as Map<String, Object?>).keys, [
        'tool',
        'required',
        'found',
        'problem',
        'fix',
      ]);
    });

    test('a configuration that cannot be loaded is reported as one', () async {
      final directory = _directory();
      io.File(p.join(directory, 'bindsmith.yaml')).writeAsStringSync(
        'name: demo\noutput: lib\nfacade: { library: lib/demo.dart }\n'
        'platforms: { linux: { driver: nonsense } }\n',
      );
      expect((await _run(directory, ['doctor'])).code, 65);
    });
  });
}
