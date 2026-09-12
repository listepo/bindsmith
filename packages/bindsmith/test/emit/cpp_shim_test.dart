/// End-to-end for the C++ path: hand-written IR → `extern "C"` shim → clang++
/// → a loaded library that Dart calls, and the same header through the C
/// driver into a dart:ffi binding.
///
/// The IR is hand-written because bindsmith does not parse C++ and will not
/// (`plan.md` §1): the shim is the supported way across, so its description
/// comes from configuration, not from a driver. Everything downstream of it
/// is real — the shim is compiled by the system C++ compiler, called through
/// `dart:ffi`, and bound by ffigen.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:bindsmith/bindsmith.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../golden.dart';

const _header = '../../fixtures/cpp/greeter/shim.g.h';
const _source = '../../fixtures/cpp/greeter/shim.g.cc';
const _binding = '../../fixtures/lib/generated/greeter_cpp/shim.g.dart';

// packages/bindsmith → repository root.
final _root = p.dirname(p.dirname(io.Directory.current.path));
final _quiet = Logger.detached('quiet')..level = Level.OFF;

TypeRef _string({bool owned = false}) =>
    TypeRef('String', native: owned ? 'std::string' : 'const std::string&');

const _int = TypeRef('int', native: 'int');

Member _method(
  String name, {
  List<Param> params = const [],
  TypeRef returns = const TypeRef('void', native: 'void'),
  bool isStatic = false,
  String? docs,
}) => Member(
  name,
  kind: MemberKind.method,
  params: params,
  returns: returns,
  isStatic: isStatic,
  docs: docs,
);

/// `fixtures/cpp/greeter/greeter.h`, as configuration would describe it.
List<Decl> get _greeter => [
  TypeDecl(
    id: 'greeter::Greeter',
    name: 'Greeter',
    platform: Platform.macos,
    kind: TypeKind.klass,
    docs: 'Greets people.',
    members: [
      Member(
        '',
        kind: MemberKind.constructor,
        params: [Param('prefix', _string())],
        docs: 'Greets with `prefix` in front of every name.',
      ),
      _method(
        'Greet',
        params: [Param('name', _string())],
        returns: _string(owned: true),
        docs:
            'Greets `name`.\n\nThrows `std::invalid_argument` when `name` is '
            'empty, which is what an `extern "C"` boundary must not let '
            'escape.',
      ),
      _method(
        'SetPrefix',
        params: [Param('prefix', _string())],
        docs: 'Changes the prefix.',
      ),
      _method(
        'Count',
        returns: _int,
        docs: 'How many greetings this instance has produced.',
      ),
      _method(
        'Version',
        isStatic: true,
        returns: _int,
        docs: 'The library version.',
      ),
      _method(
        'GreetAll',
        params: [
          Param(
            'names',
            const TypeRef('List', native: 'const std::vector<std::string>&'),
          ),
        ],
        returns: const TypeRef('List', native: 'std::vector<std::string>'),
        docs: 'Greets everyone. `std::vector` has no C spelling at all.',
      ),
    ],
  ),
];

CppShim _emit(List<Decl> ir) => emitCppShim(
  ir,
  prefix: 'greeter',
  includes: ['"greeter.h"'],
  header: 'shim.g.h',
);

void main() {
  late CppShim shim;

  setUpAll(() => shim = _emit(_greeter));

  test('a class becomes an opaque handle with a factory and a destructor', () {
    expect(
      shim.header,
      containsCode('typedef struct greeter_Greeter greeter_Greeter;'),
    );
    expect(
      shim.header,
      containsCode('greeter_Greeter* greeter_Greeter_new(const char* prefix);'),
    );
    expect(
      shim.header,
      containsCode('void greeter_Greeter_delete(greeter_Greeter* self);'),
    );
    expect(
      shim.source,
      containsCode('delete reinterpret_cast<greeter::Greeter*>(self);'),
    );
    expect(shim.symbols, contains('greeter_Greeter_new'));
    expect(shim.symbols, contains('greeter_Greeter_delete'));
  });

  test('every body runs inside a guard, because C++ may throw', () {
    expect(shim.header, containsCode('const char* greeter_last_error(void);'));
    expect(shim.source, contains('catch (const std::exception& error)'));
    expect(shim.source, contains('catch (...)'));
    expect(
      shim.source,
      containsCode(
        'char* greeter_Greeter_Greet(greeter_Greeter* self, const char* name) '
        '{ return bindsmith_guard([&]() -> char* {',
      ),
    );
  });

  test('a std::string result is copied onto the C heap', () {
    expect(shim.header, contains('greeter_free_string'));
    expect(
      shim.source,
      containsCode(
        'return bindsmith_copy(reinterpret_cast<greeter::Greeter*>(self)'
        '->Greet(std::string(name ? name : "")));',
      ),
    );
    expect(shim.header, contains('release it with `greeter_free_string`'));
  });

  test('a const char* argument is never handed to std::string unchecked', () {
    expect(shim.source, contains('std::string(prefix ? prefix : "")'));
  });

  test('a static member takes no handle', () {
    expect(shim.header, containsCode('int greeter_Greeter_Version(void);'));
    expect(shim.source, containsCode('return greeter::Greeter::Version();'));
  });

  test('std::vector is refused, with the reason, in the header', () {
    expect(shim.header, contains('// Not bridged'));
    expect(shim.header, contains('Greeter.GreetAll'));
    expect(shim.header, contains('has no C spelling'));
    expect(shim.symbols, isNot(contains('greeter_Greeter_GreetAll')));
    expect(shim.source, isNot(contains('GreetAll')));
  });

  test('a template is refused rather than erased', () {
    final box = _emit([
      TypeDecl(
        id: 'greeter::Box',
        name: 'Box',
        platform: Platform.macos,
        kind: TypeKind.klass,
        typeParams: const ['T'],
        members: [_method('Value', returns: _int)],
      ),
    ]);
    expect(box.symbols, {'greeter_last_error', 'greeter_free_string'});
    expect(box.header, contains('template over <T>'));
  });

  test('a class result is a copy the caller owns', () {
    final cloned = _emit([
      TypeDecl(
        id: 'greeter::Greeter',
        name: 'Greeter',
        platform: Platform.macos,
        kind: TypeKind.klass,
        members: [
          _method(
            'Clone',
            returns: const TypeRef('Greeter', native: 'greeter::Greeter'),
          ),
          _method(
            'Merge',
            params: [
              Param(
                'other',
                const TypeRef('Greeter', native: 'const greeter::Greeter&'),
              ),
            ],
          ),
        ],
      ),
    ]);
    expect(
      cloned.source,
      containsCode(
        'return reinterpret_cast<greeter_Greeter*>('
        'new greeter::Greeter(reinterpret_cast<greeter::Greeter*>(self)'
        '->Clone()));',
      ),
    );
    // A reference parameter crosses as a pointer and is dereferenced here.
    expect(
      cloned.source,
      contains('->Merge(*reinterpret_cast<greeter::Greeter*>(other))'),
    );
    expect(
      cloned.header,
      contains('The caller owns the result, which is a copy'),
    );
  });

  test('an overload cannot share a C name', () {
    final twice = _emit([
      TypeDecl(
        id: 'greeter::Greeter',
        name: 'Greeter',
        platform: Platform.macos,
        kind: TypeKind.klass,
        members: [
          _method('Greet', returns: _int),
          _method('Greet', params: [Param('name', _string())], returns: _int),
        ],
      ),
    ]);
    expect(twice.symbols, contains('greeter_Greeter_Greet'));
    expect(twice.symbols, contains('greeter_Greeter_Greet_2'));
  });

  test('the generated shim matches the committed fixtures', () {
    expect(shim.header, startsWith('// GENERATED BY bindsmith — do not edit.'));
    expectGolden(_header, shim.header);
    expectGolden(_source, shim.source);
  });

  test('the shim compiles, and the exception never crosses', () async {
    final compiler = await _compiler();
    if (compiler == null || io.Platform.isWindows) {
      markTestSkipped('no C++ compiler for a shared library on this host');
      return;
    }
    final tmp = io.Directory.systemTemp.createTempSync('bindsmith_cpp_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final dylib = p.join(
      tmp.path,
      io.Platform.isMacOS ? 'libgreeter.dylib' : 'libgreeter.so',
    );
    final built = await io.Process.run(compiler, [
      '-std=c++17',
      '-shared',
      '-fPIC',
      '-I',
      p.join(_root, 'fixtures/cpp/greeter'),
      p.join(_root, 'fixtures/cpp/greeter/greeter.cc'),
      p.join(_root, 'fixtures/cpp/greeter/shim.g.cc'),
      '-o',
      dylib,
    ]);
    expect(
      built.exitCode,
      0,
      reason: 'the C++ compiler rejected the shim:\n${built.stderr}',
    );

    final lib = DynamicLibrary.open(dylib);
    final greeter = lib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Uint8>),
          Pointer<Void> Function(Pointer<Uint8>)
        >('greeter_Greeter_new')(_cString('Hello'));
    expect(greeter, isNot(nullptr));
    addTearDown(
      () =>
          lib.lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('greeter_Greeter_delete')(greeter),
    );

    final greet = lib
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint8>),
          Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint8>)
        >('greeter_Greeter_Greet');
    final lastError = lib
        .lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
          'greeter_last_error',
        );

    expect(_dart(greet(greeter, _cString('world'))), 'Hello, world!');
    expect(lastError(), nullptr, reason: 'a call that worked clears the error');

    // The C++ side throws std::invalid_argument here. Unwinding through
    // `extern "C"` would be undefined behaviour; the guard is what stops it.
    expect(greet(greeter, _cString('')), nullptr);
    expect(_dart(lastError()), 'name must not be empty');

    final count = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('greeter_Greeter_Count');
    expect(count(greeter), 1, reason: 'the throwing call counted nothing');
    expect(
      lib.lookupFunction<Int32 Function(), int Function()>(
        'greeter_Greeter_Version',
      )(),
      3,
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('the C driver binds the shim header like any other C', () async {
    final tmp = io.Directory.systemTemp.createTempSync('bindsmith_cpp_c_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = p.join(tmp.path, 'shim.g.dart');
    final ir = await CDriver(
      platform: Platform.macos,
      headers: ['fixtures/cpp/greeter/shim.g.h'],
      assetId: 'package:greeter/greeter.dart',
    ).load(workingDirectory: _root, output: out, logger: _quiet);

    final names = ir.whereType<FunctionDecl>().map((d) => d.name).toSet();
    expect(names, containsAll(shim.symbols));
    final greet = ir.whereType<FunctionDecl>().singleWhere(
      (d) => d.name == 'greeter_Greeter_Greet',
    );
    expect(greet.returns.native, 'ffi.Pointer<ffi.Char>');
    expect(greet.params.map((q) => q.name), ['self', 'name']);
    expect(greet.docs, contains('Greets `name`'));
    // The handle is an opaque struct, which is exactly what it should be.
    final handle = ir.whereType<TypeDecl>().singleWhere(
      (d) => d.name == 'greeter_Greeter',
    );
    expect(handle.kind, TypeKind.opaque);

    expectGolden(_binding, io.File(out).readAsStringSync());
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// The system C++ compiler, or `null`.
Future<String?> _compiler() async {
  for (final candidate in ['clang++', 'g++']) {
    final ok = await io.Process.run(candidate, [
      '--version',
    ]).then((r) => r.exitCode == 0, onError: (_) => false);
    if (ok) return candidate;
  }
  return null;
}

/// libc's allocator, so the test needs no package to build a C string.
final _malloc = DynamicLibrary.process()
    .lookupFunction<
      Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)
    >('malloc');

Pointer<Uint8> _cString(String value) {
  final bytes = utf8.encode(value);
  final out = _malloc(bytes.length + 1);
  out.asTypedList(bytes.length + 1)
    ..setAll(0, bytes)
    ..[bytes.length] = 0;
  return out;
}

String _dart(Pointer<Uint8> value) {
  var length = 0;
  while (value[length] != 0) {
    length++;
  }
  return utf8.decode(Uint8List.sublistView(value.asTypedList(length)));
}
