/// Generation from real Apple SDK headers, end to end (macOS only).
///
/// These cases drive the same pipeline `bindsmith generate` runs against
/// headers that ship with Xcode, and check each stage of the *process*, not
/// only the output:
///
/// - sysroot resolution: `xcrun --show-sdk-path` gives an SDK that exists and
///   whose framework headers are the ones parsed;
/// - clang invocation: without `-isysroot`/`-F` a system header does not
///   parse, with them it does;
/// - include filtering: only the pulled symbols are bound, the rest of the
///   header is not;
/// - the pull list's blind spots: a type a bound signature mentions is
///   wrapped, an enum is converted, what the facade cannot spell is dropped
///   with a reason;
/// - facade assembly and verify markers: the facade analyzes clean and the
///   passthrough markers are present;
/// - a runtime smoke test: an `NSButton` made through the generated AppKit
///   binding keeps the title set from Dart and, clicked, fires an action
///   handler registered from Dart.
///
/// An `NSWindow` cannot be instantiated here: AppKit throws unless it is on the
/// process's main thread, and `dart test` runs Dart on another one. The window
/// types are generated, analyzed and compiled; the button is the part run.
///
/// Skipped everywhere but macOS with Xcode. The first run needs the network for
/// `dart pub get` and compiles ~40k lines of Objective-C glue (minutes).
@Timeout(Duration(minutes: 20))
@TestOn('mac-os')
library;

import 'dart:io' as io;

import 'package:bindsmith/bindsmith.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _runtime = p.join(
  p.dirname(io.Directory.current.path),
  'bindsmith_runtime',
);

String? _sdk() {
  final path = macosSdkPath();
  return path != null && io.Directory(path).existsSync() ? path : null;
}

String _frameworkHeader(String sdk, String framework, String header) => p.join(
  sdk,
  'System/Library/Frameworks/$framework.framework/Headers/$header',
);

/// A throwaway package named [name] with [yaml] as its `bindsmith.yaml`.
io.Directory _project(String name, String yaml, {bool hooks = false}) {
  final dir = io.Directory.systemTemp.createTempSync('bindsmith_sdk_');
  addTearDown(() => dir.deleteSync(recursive: true));
  io.File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
    '''
name: $name
publish_to: none
environment: {sdk: ^3.13.0}
dependencies:
  ffi: ^2.1.0
  objective_c: ^9.0.0
  bindsmith_runtime: {path: $_runtime}
${hooks ? '  hooks: ^2.0.0\n  code_assets: ^2.0.0\n  native_toolchain_c: ^0.19.0\n' : ''}''',
  );
  io.File(p.join(dir.path, 'bindsmith.yaml')).writeAsStringSync(yaml);
  return dir;
}

Future<String> _generate(io.Directory dir) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runBindsmith(
    ['generate'],
    out: out,
    err: err,
    workingDirectory: dir.path,
  );
  expect(code, 0, reason: '$err');
  return '$out';
}

String _read(io.Directory dir, String path) =>
    io.File(p.join(dir.path, path)).readAsStringSync();

/// Runs `dart` with the mise shims and other tool managers off `PATH`:
/// native_toolchain_c would otherwise pick up a `clang` shim instead of
/// Xcode's.
Future<io.ProcessResult> _dart(io.Directory dir, List<String> args) {
  final dartDir = p.dirname(io.Platform.resolvedExecutable);
  return io.Process.run(
    io.Platform.resolvedExecutable,
    args,
    workingDirectory: dir.path,
    environment: {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin:$dartDir'},
  );
}

Future<void> _pubGet(io.Directory dir) async {
  final r = await _dart(dir, ['pub', 'get']);
  expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
}

Future<void> _analyzeClean(io.Directory dir) async {
  await _pubGet(dir);
  final r = await _dart(dir, ['analyze', '--fatal-warnings']);
  expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
}

void main() {
  final sdk = _sdk();
  final skip = sdk == null
      ? 'needs macOS with the Xcode command line tools'
      : null;

  group('sysroot and clang flags', () {
    test('xcrun resolves an SDK that holds the framework headers', () {
      expect(sdk, isNotNull);
      expect(
        io.File(_frameworkHeader(sdk!, 'CoreGraphics', 'CGGeometry.h'))
            .existsSync(),
        isTrue,
      );
    }, skip: skip);

    test('the macOS SDK is added by default, and only for macos', () {
      final flags = clangFlags(autoSysroot: true);
      expect(flags, containsAllInOrder(['-isysroot', sdk]));
      expect(flags, contains('-F$sdk/System/Library/Frameworks'));
      expect(clangFlags(), isEmpty);
    }, skip: skip);

    test('a system header does not parse without the SDK flags', () async {
      // This is what the C driver did before: no -isysroot, no -F.
      final dir = _project(
        'nosdk',
        _cgYaml(
          sdk!,
          extra: '''
    sysroot: /nonexistent
''',
        ),
      );
      // clang cannot find <CoreGraphics/CGBase.h>, so ffigen refuses to bind.
      await expectLater(
        runBindsmith(
          ['generate'],
          out: StringBuffer(),
          err: StringBuffer(),
          workingDirectory: dir.path,
        ),
        throwsA(anything),
      );
    }, skip: skip);
  });

  group('CoreGraphics CGGeometry.h through the C driver', () {
    late io.Directory dir;
    setUpAll(() async {
      if (sdk == null) return;
      dir = _project('cg_bind', _cgYaml(sdk));
      await _generate(dir);
    });

    test('binds exactly the pulled functions (include filtering)', () {
      final binding = _read(dir, 'lib/src/generated/macos/c.g.dart');
      for (final f in [
        'CGPointEqualToPoint',
        'CGRectContainsPoint',
        'CGRectGetWidth',
      ]) {
        expect(binding, contains('external '));
        expect(binding, contains(f));
      }
      expect(binding, isNot(contains('CGRectGetMidX')));
      expect(binding, isNot(contains('CGRectCreateDictionaryRepresentation')));
    }, skip: skip);

    test('the facade carries verify markers for what passes through', () {
      final facade = _read(dir, 'lib/cg_bind_io.g.dart');
      expect(facade, contains('CGRectContainsPoint'));
      expect(facade, contains('@BindsmithVerify'));
      expect(facade, contains('no marshalling for CGPoint'));
    }, skip: skip);

    test('the generated package analyzes clean', () async {
      await _analyzeClean(dir);
    }, skip: skip);
  });

  group('Foundation NSByteCountFormatter through the Objective-C driver', () {
    late io.Directory dir;
    setUpAll(() async {
      if (sdk == null) return;
      dir = _project('fnd_bind', '''
name: fnd_bind
output: lib/src/generated
facade: {library: lib/fnd_bind.dart}
platforms:
  macos:
    driver: objc
    headers: [${_frameworkHeader(sdk, 'Foundation', 'NSByteCountFormatter.h')}]
    include:
      types: [NSByteCountFormatter]
      enums: ["NSByteCountFormatter*", NSFormattingContext]
''');
      await _generate(dir);
    });

    test('a type only a signature mentions is wrapped, not left dangling', () {
      final facade = _read(dir, 'lib/fnd_bind_io.g.dart');
      expect(facade, contains('final class NSMeasurement'));
      expect(facade, contains('opaque handle'));
      expect(facade, isNot(contains('NSFormatter {')));
    }, skip: skip);

    test('facade enums are converted to the binding enums by value', () {
      final facade = _read(dir, 'lib/fnd_bind_io.g.dart');
      expect(facade, contains('macos.NSFormattingContext.fromValue('));
      expect(facade, contains('NSFormattingContext.fromValue('));
      expect(facade, isNot(contains('no marshalling for NSFormattingContext')));
    }, skip: skip);

    test('the generated package analyzes clean', () async {
      await _analyzeClean(dir);
    }, skip: skip);
  });

  group('AppKit window and button (minimal, selected types only)', () {
    late io.Directory dir;
    setUpAll(() async {
      if (sdk == null) return;
      final headers = [
        for (final h in ['NSApplication.h', 'NSWindow.h', 'NSButton.h'])
          _frameworkHeader(sdk, 'AppKit', h),
      ];
      dir = _project('appkit_bind', '''
name: appkit_bind
output: lib/src/generated
facade: {library: lib/appkit_bind.dart}
platforms:
  macos:
    driver: objc
    headers: [${headers.join(', ')}]
    include:
      types: [NSApplication, NSWindow, NSButton, NSWindowDelegate]
      enums: [NSWindowStyleMask, NSBackingStoreType, NSApplicationActivationPolicy, NSBezelStyle, NSButtonType]
    build:
      sources: [lib/src/generated/macos/objc.g.m]
''', hooks: true);
      await _generate(dir);
    });

    test('only the selected types are bound, not the framework', () {
      final binding = _read(dir, 'lib/src/generated/macos/objc.g.dart');
      for (final t in ['NSApplication', 'NSWindow', 'NSButton']) {
        expect(binding, contains('extension type $t._('));
      }
      expect(binding, isNot(contains('extension type NSTextField._(')));
      expect(binding, isNot(contains('extension type NSTableView._(')));
    }, skip: skip);

    test('the build hook compiles the glue with ARC against AppKit', () {
      final hook = _read(dir, 'hook/build.dart');
      expect(hook, contains("'-fobjc-arc'"));
      expect(hook, contains("'AppKit'"));
    }, skip: skip);

    test(
      'the facade wraps referenced types and drops what it cannot spell',
      () {
        final facade = _read(dir, 'lib/appkit_bind_io.g.dart');
        // NSWindow.contentView returns an NSView nobody pulled.
        expect(facade, contains('final class NSView'));
        // Private to the binding library; recorded, not emitted.
        expect(facade, isNot(contains('Pointer<_NSModalSession>')));
        expect(facade, contains('@BindsmithVerify'));
      },
      skip: skip,
    );

    test('the generated package analyzes clean', () async {
      await _analyzeClean(dir);
    }, skip: skip);

    test('a button keeps its title and a click runs a Dart handler', () async {
      io.Directory(p.join(dir.path, 'bin')).createSync();
      io.File(p.join(dir.path, 'bin/smoke.dart')).writeAsStringSync(_smoke);
      final r = await _dart(dir, ['run', 'bin/smoke.dart']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final out = '${r.stdout}';
      expect(out, contains('title=Click me'));
      expect(out, contains('fired=1'));
    }, skip: skip);
  });
}

String _cgYaml(String sdk, {String extra = ''}) =>
    '''
name: cg_bind
output: lib/src/generated
facade: {library: lib/cg_bind.dart}
platforms:
  macos:
    driver: c
    headers: [${_frameworkHeader(sdk, 'CoreGraphics', 'CGGeometry.h')}]
$extra    include:
      functions: [CGPointEqualToPoint, CGSizeEqualToSize, CGRectEqualToRect, CGRectContainsPoint, CGRectContainsRect, CGRectGetWidth, CGRectGetHeight]
''';

/// Runs on the isolate's own thread, so it never instantiates an NSWindow.
const _smoke = r'''
import 'dart:ffi';

import 'package:appkit_bind/src/generated/macos/objc.g.dart' as ak;
import 'package:objective_c/objective_c.dart' as objc;

void main() {
  DynamicLibrary.open('/System/Library/Frameworks/AppKit.framework/AppKit');
  // A click is routed through the shared application; without one it is
  // dropped.
  ak.NSApplication.getSharedApplication();
  final button = ak.NSButton.alloc().init();
  button.title = objc.NSString('Click me');
  print('title=${button.title.toDartString()}');

  var fired = 0;
  // A Dart object that answers `windowDidMove:`; the button's action takes the
  // same one-argument shape, so a click lands in this handler.
  final target = ak.NSWindowDelegate$Builder.implement(
    windowDidMove_: (_) => fired++,
  );
  button.target = target;
  button.action = objc.registerName('windowDidMove:');
  button.performClick(null);
  print('fired=$fired');
  // NSButton holds its target weakly: keep the Dart object reachable until
  // the click has been delivered, or it can be released first.
  print('target=${target.runtimeType}');
}
''';
