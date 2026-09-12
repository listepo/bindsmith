/// End-to-end for the Windows pipeline: metadata → [WinmdDriver] → IR →
/// [emitWin32] → dart:ffi binding, committed under
/// `fixtures/lib/generated/win32/` where `dart analyze --fatal-infos fixtures`
/// proves it compiles.
///
/// The metadata is built in memory by `winmd_sample.dart` rather than read from
/// `Windows.Win32.winmd`, so nothing is downloaded and nothing binary is
/// committed. Everything here runs on any host: `package:winmd` is a pure-Dart
/// reader and the emitter writes text.
/// Every test here waits on an external toolchain, so the 30-second default
/// is not a timeout, it is a load test of the host: under a busy machine
/// `swiftc`, libclang, Gradle and a spawned `dart run` all exceed it and the
/// suite fails for a reason that has nothing to do with the code.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
// The IR has a `Platform` of its own, and a non-SDK import shadows `dart:io`.
import 'dart:io' as io show Platform;

import 'package:bindsmith/bindsmith.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../golden.dart';
import 'winmd_sample.dart';

const _generated = '../../fixtures/lib/generated/win32/sample.g.dart';
const _vtableCheck = 'fixtures/bin/win32_vtable.dart';

// packages/bindsmith → repository root.
final _root = p.dirname(p.dirname(Directory.current.path));

List<Decl> _load() => WinmdDriver(
  index: sampleIndex(),
  functions: {'MessageBoxW', 'SampleGreet', 'SampleGetVersion', 'SampleBox'},
  constants: {'SAMPLE_MAX_NAME'},
  types: {'ISampleGreeter'},
  covered: (name) => const {'MessageBoxW': 'MessageBox'}[name],
).load();

void main() {
  late List<Decl> ir;
  late Win32Binding binding;

  setUpAll(() {
    ir = _load();
    binding = emitWin32(ir);
  });

  TypeDecl type(String name) =>
      ir.whereType<TypeDecl>().singleWhere((d) => d.name == name);
  FunctionDecl function(String name) =>
      ir.whereType<FunctionDecl>().singleWhere((d) => d.name == name);

  test('the sample assembly is byte-identical between builds', () {
    expect(sampleWinmd(), sampleWinmd());
  });

  test('an unknown name in a pull list is an error, not an empty result', () {
    final index = sampleIndex();
    expect(
      () => WinmdDriver(index: index, functions: {'NoSuchApi'}).load(),
      throwsA(
        isA<ArgumentError>()
            .having((e) => e.name, 'name', 'functions')
            .having((e) => e.message, 'message', contains('not declared')),
      ),
    );
    expect(
      () => WinmdDriver(index: index, constants: {'NO_SUCH_CONSTANT'}).load(),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'constants')),
    );
    expect(
      () => WinmdDriver(index: index, types: {'NoSuchStruct'}).load(),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'types')),
    );
  });

  test('a function records its exported symbol and its DLL', () {
    final greet = function('SampleGreet');
    expect(greet.id, '$sampleNamespace.SampleGreet');
    expect(greet.platform, Platform.windows);
    // The metadata calls it `SampleGreet`; `sample.dll` exports `SampleGreetW`.
    expect(greet.native, 'SampleGreetW');
    expect(greet.loc?.file, 'sample.dll');
    expect(greet.returns, const TypeRef('int', native: 'ffi.Uint32'));
    expect(greet.params.map((q) => q.name), ['options', 'buffer', 'cch']);
    expect(
      greet.params.first.type,
      const TypeRef(
        'ffi.Pointer<SampleOptions>',
        native: 'ffi.Pointer<SampleOptions>',
      ),
    );
    expect(greet.docs, contains('learn.microsoft.com/sample/nf-samplegreet'));
    expect(greet.markers, isEmpty);
  });

  test('a symbol package:win32 already binds is dropped, not regenerated', () {
    final box = function('MessageBoxW');
    expect(box.binding, 'MessageBox');
    expect(box.markers.single.kind, MarkerKind.dropped);
    expect(box.markers.single.reason, reexportedFrom(win32Package));
    // Still described: `bindsmith verify` reports what the re-export covers.
    expect(box.params.map((q) => q.name), [
      'hWnd',
      'lpText',
      'lpCaption',
      'uType',
    ]);
  });

  test('a type with no dart:ffi spelling is dropped with its reason', () {
    final refused = function('SampleBox').markers.single;
    expect(refused.kind, MarkerKind.dropped);
    expect(refused.reason, contains('has no dart:ffi spelling'));
  });

  test('a constant keeps its value and its type', () {
    final max = ir.whereType<VariableDecl>().single;
    expect(max.name, 'SAMPLE_MAX_NAME');
    expect(max.isConst, isTrue);
    expect(max.value, '64');
    expect(max.type, const TypeRef('int', native: 'ffi.Uint32'));
  });

  test('types reached from a signature are pulled in transitively', () {
    // Only `ISampleGreeter` was requested; the rest arrive through
    // `SampleGreet`'s parameter and then through `SampleOptions`' fields.
    expect(
      ir.whereType<TypeDecl>().map((d) => d.name),
      containsAll(['SampleOptions', 'SampleHandle', 'SampleFlags']),
    );
  });

  test('a NativeTypedef handle flattens to the type it really is', () {
    final handle = type('SampleHandle');
    expect(handle.kind, TypeKind.typedef);
    expect(handle.supertypes.single.native, 'ffi.IntPtr');
    // A struct field typed by the handle is an `int`, not a wrapper struct.
    final caller = type('SampleOptions').members
        .singleWhere((m) => m.name == 'Caller');
    expect(caller.returns, const TypeRef('int', native: 'SampleHandle'));
  });

  test('an enum carries its storage type and stays int at the boundary', () {
    final flags = type('SampleFlags');
    expect(flags.kind, TypeKind.enumeration);
    expect(flags.supertypes.single, const TypeRef('int', native: 'ffi.Uint32'));
    expect(flags.members.map((m) => (m.name, m.value)), [
      ('SAMPLE_QUIET', '0'),
      ('SAMPLE_NORMAL', '1'),
      ('SAMPLE_LOUD', '2'),
    ]);
    expect(flags.markers.single.kind, MarkerKind.verify);
    final field = type('SampleOptions').members
        .singleWhere((m) => m.name == 'Flags');
    expect(field.returns, const TypeRef('int', native: 'ffi.Uint32'));
  });

  test('a COM interface keeps its base, its IID and its vtable order', () {
    final greeter = type('ISampleGreeter');
    expect(greeter.kind, TypeKind.interface);
    expect(greeter.supertypes.single.name, 'IUnknown');
    final iid = greeter.members.first;
    expect(iid.name, 'IID');
    expect(iid.isStatic, isTrue);
    expect(iid.value, "'{6f9b1a2c-3d4e-4f50-8a61-b2c3d4e5f607}'");
    expect(
      greeter.members
          .where((m) => m.kind == MemberKind.method)
          .map((m) => m.name),
      // Declaration order is vtable order; `win32_vtable.dart` proves it holds
      // through to the generated struct.
      ['Greet', 'GetVersion'],
    );
    expect(
      greeter.markers.map((m) => m.reason),
      contains(startsWith('COM: methods are called through the vtable')),
    );
  });

  test('output is ordered, not hash-ordered', () {
    final ids = ir.map((d) => d.id).toList();
    expect(ids, orderedEquals([...ids]..sort()));
    // A second read of a second index produces the same IR.
    expect(_load().map((d) => d.id), ids);
  });

  test('generated dart:ffi binding matches the committed fixture', () {
    expect(binding.source, startsWith('// GENERATED BY bindsmith'));
    expectGolden(_generated, binding.source);
  });

  test('a covered symbol becomes one export, not a second binding', () {
    expect(binding.reexports, {'MessageBox'});
    expect(
      binding.source,
      contains("export 'package:win32/win32.dart' show MessageBox;"),
    );
    expect(binding.source, isNot(contains('MessageBoxW')));
  });

  test('what could not be bound is still reported in the binding', () {
    expect(
      binding.source,
      contains('// Not bound, and still reported by `bindsmith verify`:'),
    );
    expect(binding.source, contains('SampleBox: ObjectType'));
  });

  test('the generated COM vtable has the layout COM requires', () async {
    final result = await Process.run(io.Platform.executable, [
      'run',
      _vtableCheck,
    ], workingDirectory: _root);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('ok: 5 vtable slots in COM order'));
  });
}
