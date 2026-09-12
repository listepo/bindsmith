/// Facade over a C binding (plan P6-4b): `cFacadePass` turns dart:ffi types
/// into the API the facade offers, and `emitFacade` writes the marshalling.
///
/// The IR is read from the C driver's committed snapshot rather than produced
/// by running ffigen, so these tests need no libclang and run on any host. The
/// generated facade is committed under `fixtures/lib/generated/geometry/`,
/// where `dart analyze --fatal-infos fixtures` proves it compiles against the
/// real binding.
///
/// The last test is the one that matters: marshalling is what a compiler
/// cannot check. An arena freed too early, a `Pointer<Char>` read as UTF-16 or
/// an enum passed as its index all compile and then return nonsense, so
/// `fixtures/c/geometry/geometry.c` is built into a shared library and the
/// facade is called against it.
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:bindsmith/bindsmith.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../golden.dart';

const _snapshot = 'test/drivers/goldens/geometry.ir.json';
const _facade = '../../fixtures/lib/generated/geometry';
const _runner = 'fixtures/bin/geometry_facade.dart';

// packages/bindsmith → repository root.
final _root = p.dirname(p.dirname(io.Directory.current.path));

List<Decl> _ir() => runPasses(
  irFromJson(
    jsonDecode(io.File(_snapshot).readAsStringSync()) as List<Object?>,
  ),
  [cFacadePass()],
);

FacadeFiles _emit(List<Decl> ir) => emitFacade(
  {Platform.linux: ir},
  const FacadeOptions(
    library: 'geometry_facade',
    bindings: {Platform.linux: 'c.g.dart'},
  ),
);

void main() {
  late List<Decl> ir;
  late String source;

  setUpAll(() {
    ir = _ir();
    source = _emit(ir)['geometry_facade_io.g.dart']!;
  });

  FunctionDecl function(String name) =>
      ir.whereType<FunctionDecl>().singleWhere((d) => d.name == name);
  TypeDecl type(String name) =>
      ir.whereType<TypeDecl>().singleWhere((d) => d.name == name);

  test('goldens', () {
    for (final e in _emit(ir).entries) {
      expectGolden('$_facade/${e.key}', e.value);
    }
  });

  test('a C string becomes a String, and the pointer stays in native', () {
    final log = function('geometry_log').params.single;
    expect(log.type.name, 'String');
    expect(log.type.native, 'ffi.Pointer<ffi.Char>');
    expect(function('geometry_shape_name').returns.name, 'String');
  });

  test('a String argument is copied into an arena around the call', () {
    expect(
      source,
      containsCode(
        'int geometry_log(String format) => using((_arena) => '
        'linux.geometry_log('
        'format.toNativeUtf8(allocator: _arena).cast<ffi.Char>()))',
      ),
    );
  });

  test('a returned C string is copied out, and says who owns it', () {
    expect(
      source,
      containsCode(
        'linux.geometry_shape_name(...).cast<Utf8>().toDartString()'
            .replaceFirst('...', 'linux.Shape.values.byName(shape.name)'),
      ),
    );
    expect(
      source,
      contains('the returned string is copied out of memory the library owns'),
    );
  });

  test('an opaque handle keeps its pointer and gains dispose', () {
    final scene = function('geometry_scene_new').returns;
    expect(scene.name, 'GeometryScene');
    expect(scene.native, 'ffi.Pointer<GeometryScene>');
    final dispose = type('GeometryScene').members.single;
    expect(dispose.name, 'dispose');
    expect(dispose.markers.single.reason, disposedBy('geometry_scene_free'));
    expect(source, containsCode('void dispose() => geometry_scene_free(this)'));
    // The deallocator is still callable on its own: a C API may hand a handle
    // somewhere else to be freed.
    expect(source, containsCode('void geometry_scene_free(GeometryScene'));
  });

  test('an ambiguous deallocator is left alone', () {
    const handle = TypeDecl(
      id: 'H',
      name: 'H',
      platform: Platform.linux,
      kind: TypeKind.opaque,
    );
    FunctionDecl free(String name) => FunctionDecl(
      id: name,
      name: name,
      platform: Platform.linux,
      params: const [
        Param(
          'h',
          TypeRef('Pointer', args: [TypeRef('H')], native: 'ffi.Pointer<H>'),
        ),
      ],
    );
    List<Member> members(List<Decl> decls) =>
        decls.whereType<TypeDecl>().single.members;
    expect(
      members(cFacadePass()([handle, free('h_free')])).map((m) => m.name),
      ['dispose'],
    );
    // Two candidates and no way to choose: the caller frees it explicitly.
    expect(
      members(cFacadePass()([handle, free('h_free'), free('h_release')])),
      isEmpty,
    );
  });

  test('a struct is passed by value, or copied into the arena by pointer', () {
    // dart:ffi passes a struct by value on its own; nothing to marshal.
    expect(
      source,
      containsCode(
        'double geometry_distance(Point a, Point b) => '
        'linux.geometry_distance('
        '(a._impl as linux.Point), (b._impl as linux.Point))',
      ),
    );
    // P6-4d: the copy is what the callee writes through, so it is read back
    // field by field before the arena frees it.
    expect(
      source,
      containsCode(
        'double geometry_rect_area(Rect rect) => using((_arena) { '
        'final _p0 = (_arena<linux.Rect>()..ref = (rect._impl as linux.Rect)); '
        'final _result = linux.geometry_rect_area(_p0); '
        '(rect._impl as linux.Rect)'
        '..origin = _p0.ref.origin..width = _p0.ref.width'
        '..height = _p0.ref.height; '
        'return _result; });',
      ),
    );
    // A void call has no result to hold, and still has the write-back to run.
    expect(
      source,
      containsCode(
        'void geometry_scale(Point point, double factor) { using((_arena) { '
        'final _p0 = (_arena<linux.Point>()..ref = (point._impl as linux.Point)); '
        'linux.geometry_scale(_p0, factor); '
        '(point._impl as linux.Point)..x = _p0.ref.x..y = _p0.ref.y; }); }',
      ),
    );
    expect(source, contains('a callee that keeps the pointer outlives it'));
  });

  test('a struct gains a constructor and field setters (P6-4c)', () {
    final point = type('Point');
    final ctor = point.members.singleWhere(
      (m) => m.kind == MemberKind.constructor,
    );
    expect(ctor.params.map((p) => (p.name, p.named)), [
      ('x', true),
      ('y', true),
    ]);
    // `ffi.Struct.create` lays the struct out on the Dart heap, so unlike the
    // opaque handle above it owns nothing and gets no `dispose`.
    expect(ctor.markers.single.reason, laidOutAs('Point'));
    expect(point.members.map((m) => m.name), isNot(contains('dispose')));
    expect(
      source,
      containsCode(
        'factory Point({required double x, required double y}) => '
        'Point._((ffi.Struct.create<linux.Point>()..x = x..y = y));',
      ),
    );
    expect(
      source,
      containsCode('set x(double value) { (_impl as linux.Point).x = value; }'),
    );
    // A nested struct is copied in by assignment, and read back as a view.
    expect(
      source,
      containsCode(
        'factory Rect({required Point origin, required double width, '
        'required double height}) => Rect._((ffi.Struct.create<linux.Rect>()'
        '..origin = (origin._impl as linux.Point)..width = width'
        '..height = height));',
      ),
    );
    expect(
      type('Rect').members
          .singleWhere((m) => m.name == 'origin' && m.kind == MemberKind.field)
          .markers
          .map((m) => m.reason),
      contains(viewIntoContainer),
    );
  });

  test('a struct the facade cannot fill by value gets no constructor', () {
    // A `char *` field would be an arena copy freed before the struct is used,
    // so the field keeps its getter and the struct keeps its private
    // constructor: nothing offers a way to build one that already dangles.
    const named = TypeDecl(
      id: 'Named',
      name: 'Named',
      platform: Platform.linux,
      kind: TypeKind.struct,
      members: [
        Member(
          'label',
          kind: MemberKind.field,
          returns: TypeRef(
            'Pointer',
            args: [TypeRef('Char')],
            native: 'ffi.Pointer<ffi.Char>',
          ),
        ),
        Member(
          'size',
          kind: MemberKind.field,
          returns: TypeRef('int', native: 'ffi.Int32'),
        ),
      ],
    );
    final members = cFacadePass()([named]).whereType<TypeDecl>().single.members;
    expect(members.where((m) => m.kind == MemberKind.constructor), isEmpty);
    // The int field is still settable; only the pointer one is not.
    expect(
      members.where((m) => m.kind == MemberKind.setter).map((m) => m.name),
      ['size'],
    );
  });

  test('a C enum crosses by constant name', () {
    expect(function('geometry_shape_name').params.single.type.name, 'Shape');
    expect(source, containsCode('linux.Shape.values.byName(shape.name)'));
    // The facade enum carries the values the C API uses.
    expect(source, containsCode('SHAPE_TRIANGLE(2)'));
    expect(source, containsCode('static Shape fromValue(int value)'));
  });

  test('a typedef is replaced by what it aliases, not wrapped', () {
    // `geometry_id` is `uint32_t`, so the facade says `int`.
    expect(function('geometry_scene_add').returns.name, 'int');
    expect(type('geometry_id').isDropped, isTrue);
    expect(source, isNot(contains('class geometry_id')));
    expect(source, contains('geometry_id — a typedef is an alias'));
  });

  test('a pointer the facade cannot spell degrades to Pointer<Void>', () {
    // `geometry_visitor` is a `Pointer<NativeFunction<…>>` whose type argument
    // lives in the binding library and cannot be named in a facade signature.
    final visitor = function('geometry_scene_each').params[1];
    expect(visitor.type.name, 'ffi.Pointer<ffi.Void>');
    expect(source, containsCode('ffi.Pointer<ffi.Void> visitor'));
    // Cast back at the boundary rather than passed to the wrong parameter.
    expect(source, containsCode('visitor.cast()'));
    expect(
      function('geometry_scene_each').markers.map((m) => m.reason),
      contains(contains('has no facade type')),
    );
  });

  test('the facade imports dart:ffi only where it marshals C types', () {
    expect(source, contains("import 'dart:ffi' as ffi;"));
    expect(source, contains("import 'package:ffi/ffi.dart';"));
    // A facade over a binding with no C types keeps both imports out.
    final plain = emitFacade(
      {
        Platform.android: const [
          FunctionDecl(
            id: 'ping',
            name: 'ping',
            platform: Platform.android,
            returns: TypeRef('int'),
          ),
        ],
      },
      const FacadeOptions(
        library: 'plain',
        bindings: {Platform.android: 'a.g.dart'},
      ),
    )['plain_io.g.dart']!;
    expect(plain, isNot(contains('ffi')));
  });

  test(
    'the generated facade marshals correctly against a real library',
    () async {
      final compiler = await _compiler();
      if (compiler == null || io.Platform.isWindows) {
        markTestSkipped('no C compiler for a shared library on this host');
        return;
      }
      final tmp = io.Directory.systemTemp.createTempSync('bindsmith_facade_c_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final dylib = p.join(
        tmp.path,
        io.Platform.isMacOS ? 'libgeometry.dylib' : 'libgeometry.so',
      );
      final built = await io.Process.run(compiler, [
        '-shared',
        '-fPIC',
        '-I',
        p.join(_root, 'fixtures/c/geometry'),
        p.join(_root, 'fixtures/c/geometry/geometry.c'),
        '-o',
        dylib,
      ]);
      expect(
        built.exitCode,
        0,
        reason: 'the C compiler rejected the fixture:\n${built.stderr}',
      );
      final run = await io.Process.run(io.Platform.executable, [
        'run',
        _runner,
        dylib,
      ], workingDirectory: _root);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect(
        run.stdout,
        contains(
          'ok: strings, enums, structs and handles cross the C boundary',
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// The system C compiler, or `null`.
Future<String?> _compiler() async {
  for (final candidate in ['cc', 'clang', 'gcc']) {
    final ok = await io.Process.run(candidate, [
      '--version',
    ]).then((r) => r.exitCode == 0, onError: (_) => false);
    if (ok) return candidate;
  }
  return null;
}
