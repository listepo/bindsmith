/// The clang flags that make Apple SDK headers parse. Pure: the host is
/// injected, so the cases run on every OS.
library;

import 'package:bindsmith/bindsmith.dart';
import 'package:test/test.dart';

String? _xcrun(String exe, List<String> args) =>
    exe == 'xcrun' && args.join(' ') == '--show-sdk-path'
    ? '/SDK/MacOSX.sdk'
    : null;

void main() {
  group('clangFlags', () {
    test('auto-detects the macOS SDK from xcrun', () {
      expect(clangFlags(autoSysroot: true, probe: _xcrun, isMacOS: true), [
        '-isysroot',
        '/SDK/MacOSX.sdk',
        '-F/SDK/MacOSX.sdk/System/Library/Frameworks',
      ]);
    });

    test('does not ask xcrun off macOS or when auto-detection is off', () {
      var asked = false;
      String? probe(String e, List<String> a) {
        asked = true;
        return '/x';
      }

      expect(
        clangFlags(autoSysroot: true, probe: probe, isMacOS: false),
        isEmpty,
      );
      expect(clangFlags(probe: probe, isMacOS: true), isEmpty);
      expect(asked, isFalse);
    });

    test('a missing xcrun leaves the flags alone instead of failing', () {
      expect(
        clangFlags(autoSysroot: true, probe: (_, _) => null, isMacOS: true),
        isEmpty,
      );
    });

    test('an explicit sysroot wins over xcrun', () {
      final flags = clangFlags(
        sysroot: '/mine',
        autoSysroot: true,
        probe: _xcrun,
        isMacOS: true,
      );
      expect(flags, [
        '-isysroot',
        '/mine',
        '-F/mine/System/Library/Frameworks',
      ]);
    });

    test('an -isysroot in compiler_options is not doubled', () {
      final flags = clangFlags(
        compilerOptions: ['-isysroot/own', '-DX=1'],
        autoSysroot: true,
        probe: _xcrun,
        isMacOS: true,
      );
      expect(flags.where((f) => f.startsWith('-isysroot')), ['-isysroot/own']);
      expect(flags, contains('-DX=1'));
    });

    test('order is sysroot, framework paths, compiler options, extras', () {
      expect(
        clangFlags(
          sysroot: '/s',
          frameworkPaths: ['/fw'],
          compilerOptions: ['-DA'],
          extra: ['-I/pc'],
        ),
        [
          '-isysroot',
          '/s',
          '-F/s/System/Library/Frameworks',
          '-F/fw',
          '-DA',
          '-I/pc',
        ],
      );
    });
  });

  group('config keys', () {
    const yaml = '''
name: demo
output: lib/src/generated
facade: {library: lib/demo.dart}
platforms:
  macos:
    driver: c
    headers: [a.h]
    sysroot: /sdk
    framework_paths: [/fw1, /fw2]
    compiler_options: ['-DX=1']
    include: {functions: [f]}
''';

    test('c and objc accept sysroot, framework_paths, compiler_options', () {
      final spec = loadBindsmithConfig(yaml).platforms[Platform.macos]!;
      expect(spec.sysroot, '/sdk');
      expect(spec.frameworkPaths, ['/fw1', '/fw2']);
      expect(spec.compilerOptions, ['-DX=1']);
      expect(
        () => loadBindsmithConfig(
          yaml
              .replaceFirst('driver: c', 'driver: objc')
              .replaceFirst('functions', 'types'),
        ),
        returnsNormally,
      );
    });

    test('other drivers reject them rather than ignoring them', () {
      expect(
        () => loadBindsmithConfig('''
name: demo
output: lib/src/generated
facade: {library: lib/demo.dart}
platforms:
  android: {driver: jvm, compile_sdk: 35, sysroot: /x, include: {classes: [a.B]}}
'''),
        throwsA(anything),
      );
    });
  });
}
