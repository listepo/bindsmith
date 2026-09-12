/// win32 emitter: writes the dart:ffi binding for Windows metadata.
///
/// Every other platform has an upstream generator that writes the binding and
/// leaves bindsmith to describe it. Windows does not — `package:winmd` reads
/// metadata and stops — so this emitter is the binding writer, and the IR it
/// reads comes from [WinmdDriver].
///
/// Three shapes, all of them chosen to match `package:win32` rather than to
/// invent a second dialect for the same platform:
///
/// * **Functions** become `@ffi.Native` externals carrying the exported symbol
///   and the DLL as the asset id, so a call resolves through a build hook's
///   code asset when there is one and through the loaded process otherwise —
///   which is how a system DLL like `user32.dll` already resolves.
/// * **COM interfaces** become a class over `package:win32`'s [IUnknown],
///   holding a `VTablePointer`, reading its vtable through a `base$` chained
///   `Struct`, and calling each slot with `asFunction`. `package:win32` spells
///   it exactly this way, so the two interoperate: an interface from either
///   side can be handed to the other.
/// * **Anything `package:win32` already binds** is not generated at all. The
///   driver marks it, and this emitter turns it into one `export … show`, so
///   a consumer gets the well-tested binding rather than a second one.
///
/// A Win32 enum is emitted as a Dart enum with a `value`, the way ffigen
/// writes a C enum, but the binding still passes and stores the integer: an
/// FFI struct field cannot hold a Dart enum, and lifting it is the facade's
/// job. A handle (`NativeTypedefAttribute`) becomes a typedef pair, again
/// following ffigen, so `Pointer<SampleHandle>` keeps reading as a handle.
///
/// @docImport '../drivers/winmd/winmd_driver.dart';
library;

import 'package:dart_style/dart_style.dart';

import '../drivers/c/ffigen_adapter.dart' show bindsmithHeader;
import '../drivers/winmd/winmd_driver.dart' show reexportedFrom, win32Package;
import '../ir/ir.dart';

/// The generated library and the identifiers it re-exports from
/// `package:win32` rather than generating.
typedef Win32Binding = ({String source, Set<String> reexports});

/// Emits the dart:ffi binding for [ir].
///
/// [library] is where a covered symbol is re-exported from; it must be the
/// same value the driver was given, because the driver writes the marker this
/// emitter reads. [preamble] is placed under the generated-file header.
Win32Binding emitWin32(
  List<Decl> ir, {
  String library = win32Package,
  String preamble = '',
}) => _Emitter(ir, library).run(preamble);

const _indent = '  ';

final class _Emitter {
  _Emitter(this.ir, this.library) {
    for (final decl in ir) {
      if (decl case TypeDecl(:final name, :final kind)) kinds[name] = kind;
    }
  }

  final List<Decl> ir;
  final String library;

  /// Type name → kind, so a field can tell a struct from an enum from a
  /// handle without looking the declaration up again.
  final kinds = <String, TypeKind>{};
  final reexports = <String>{};
  final refused = <String>[];
  var needsCom = false;

  Win32Binding run(String preamble) {
    final body = [
      ..._constants(),
      ..._functions(),
      ..._types(),
    ].where((part) => part.isNotEmpty);
    // The body is built first: it decides which imports the file needs.
    final source = StringBuffer()
      ..write(bindsmithHeader)
      ..write(preamble.isEmpty ? '' : '$preamble\n')
      ..writeln()
      ..writeln(
        '// ignore_for_file: camel_case_types, '
        'constant_identifier_names',
      )
      ..writeln('// ignore_for_file: non_constant_identifier_names')
      ..writeln()
      ..writeln("import 'dart:ffi' as ffi;");
    if (needsCom) source.writeln("import 'dart:typed_data';");
    if (needsCom || reexports.isNotEmpty) {
      source
        ..writeln()
        ..writeln("import '$library';");
    }
    if (reexports.isNotEmpty) {
      source
        ..writeln()
        ..writeln(
          "export '$library' show ${(reexports.toList()..sort()).join(', ')};",
        );
    }
    for (final part in body) {
      source
        ..writeln()
        ..writeln(part);
    }
    if (refused.isNotEmpty) {
      source
        ..writeln()
        ..writeln('// Not bound, and still reported by `bindsmith verify`:');
      for (final reason in refused..sort()) {
        source.writeln(_comment(reason));
      }
    }
    return (
      // Rule 5: golden output is formatted, so the emitter writes readable
      // code and dart_style decides where the lines break.
      source: DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format(source.toString()),
      reexports: reexports,
    );
  }

  // ---------------------------------------------------------------- constants

  Iterable<String> _constants() sync* {
    for (final decl in ir) {
      if (decl is! VariableDecl) continue;
      if (_skip(decl)) continue;
      final value = decl.value;
      if (value == null) {
        refused.add('${decl.name}: no value in the metadata');
        continue;
      }
      yield '${_docs(decl.docs, '')}'
          'const ${decl.type.name} ${decl.name} = $value;';
    }
  }

  // ---------------------------------------------------------------- functions

  Iterable<String> _functions() sync* {
    for (final decl in ir) {
      if (decl is! FunctionDecl) continue;
      if (_skip(decl)) continue;
      final signature = [
        decl.returns.native ?? decl.returns.name,
        ' Function(',
        [for (final p in decl.params) p.type.native ?? p.type.name].join(', '),
        ')',
      ].join();
      final args = [for (final p in decl.params) '${p.type.name} ${p.name}']
          .join(', ');
      yield '${_docs(decl.docs, '')}'
          '@ffi.Native<$signature>('
          "symbol: '${decl.native ?? decl.name}'"
          "${decl.loc == null ? '' : ", assetId: '${decl.loc!.file}'"})\n"
          'external ${decl.returns.name} ${decl.name}($args);';
    }
  }

  // -------------------------------------------------------------------- types

  Iterable<String> _types() sync* {
    for (final decl in ir) {
      if (decl is! TypeDecl) continue;
      if (_skip(decl)) continue;
      switch (decl.kind) {
        case TypeKind.typedef:
          yield _typedef(decl);
        case TypeKind.enumeration:
          yield _enum(decl);
        case TypeKind.struct:
          yield _struct(decl);
        case TypeKind.interface:
          needsCom = true;
          yield _interface(decl);
        case _:
          refused.add('${decl.name}: ${decl.kind.name} has no Windows binding');
      }
    }
  }

  /// A handle: the native type plus the Dart twin, the way ffigen writes one.
  String _typedef(TypeDecl decl) {
    final target = decl.supertypes.single;
    return '${_docs(decl.docs, '')}'
        'typedef ${decl.name} = ${target.native ?? target.name};\n'
        'typedef Dart${decl.name} = ${target.name};';
  }

  String _enum(TypeDecl decl) {
    final values = [
      for (final m in decl.members)
        if (m.value != null) (name: m.name, value: m.value!, docs: m.docs),
    ];
    if (values.isEmpty) {
      refused.add('${decl.name}: enum with no values');
      return '';
    }
    final storage = decl.supertypes.singleOrNull?.native ?? 'ffi.Int32';
    final docs = _docs(decl.docs, '');
    final body = StringBuffer()
      ..write(docs)
      ..write(docs.isEmpty ? '' : '///\n')
      ..writeln('/// Stored and passed as `$storage`.')
      ..writeln('enum ${decl.name} {');
    for (final (i, value) in values.indexed) {
      body
        ..write(_docs(value.docs, _indent))
        ..writeln(
          '$_indent${value.name}(${value.value})'
          '${i == values.length - 1 ? ';' : ','}',
        );
    }
    body
      ..writeln()
      ..writeln('${_indent}final int value;')
      ..writeln('${_indent}const ${decl.name}(this.value);')
      ..writeln()
      ..writeln(
        '${_indent}static ${decl.name} fromValue(int value) => '
        'switch (value) {',
      );
    for (final value in values) {
      body.writeln('$_indent$_indent${value.value} => ${value.name},');
    }
    body
      ..writeln(
        '$_indent$_indent'
        '_ => throw ArgumentError('
        "'Unknown value for ${decl.name}: \$value'),",
      )
      ..writeln('$_indent};')
      ..write('}');
    return body.toString();
  }

  String _struct(TypeDecl decl) {
    final body = StringBuffer()
      ..write(_docs(decl.docs, ''))
      ..writeln('final class ${decl.name} extends ffi.Struct {');
    for (final (i, member) in decl.members.indexed) {
      if (i > 0) body.writeln();
      final native = member.returns.native;
      body.write(_docs(member.docs, _indent));
      // A struct field of a compound type carries no annotation; every other
      // field is annotated with the native type it is stored as.
      if (native != null && kinds[member.returns.name] != TypeKind.struct) {
        body.writeln('$_indent@${_annotation(native)}');
      }
      body.writeln('${_indent}external ${member.returns.name} ${member.name};');
    }
    body.write('}');
    return body.toString();
  }

  /// `ffi.Uint32` → `@ffi.Uint32()`; `ffi.Array<ffi.Uint16>(16)` is already a
  /// call and passes through.
  String _annotation(String native) =>
      native.endsWith(')') ? native : '$native()';

  // ---------------------------------------------------------------------- COM

  String _interface(TypeDecl decl) {
    final base = decl.supertypes.singleOrNull?.name ?? 'IUnknown';
    final methods = [
      for (final m in decl.members)
        if (m.kind == MemberKind.method) m,
    ];
    final iid = decl.members
        .where((m) => m.name == 'IID')
        .map((m) => m.value)
        .firstOrNull;

    final body = StringBuffer()
      ..write(_docs(decl.docs, ''))
      ..writeln('class ${decl.name} extends $base {')
      ..writeln(
        '$_indent${decl.name}(super.ptr)'
        ' : _vtable = ptr.value.cast<${decl.name}Vtbl>().ref;',
      );
    if (iid != null) {
      body
        ..writeln()
        ..writeln(
          "$_indent/// `${iid.replaceAll("'", '')}`, this interface's IID.",
        )
        ..writeln('${_indent}static final iid = ${_guid(iid)};');
    }
    body
      ..writeln()
      ..writeln('${_indent}final ${decl.name}Vtbl _vtable;');
    for (final method in methods) {
      body.writeln(
        '${_indent}late final _${method.name}Fn = _vtable.${method.name}'
        '.asFunction<${_dartFn(method)}>();',
      );
    }
    for (final method in methods) {
      final args = [for (final p in method.params) '${p.type.name} ${p.name}']
          .join(', ');
      final call = ['ptr', for (final p in method.params) p.name].join(', ');
      body
        ..writeln()
        ..write(_docs(method.docs, _indent))
        ..writeln(
          '$_indent${method.returns.name} ${method.name}($args) => '
          '_${method.name}Fn($call);',
        );
    }
    body
      ..writeln('}')
      ..writeln()
      ..writeln('/// The vtable of [${decl.name}], laid out over its base.')
      ..writeln('base class ${decl.name}Vtbl extends ffi.Struct {')
      ..writeln('${_indent}external ${base}Vtbl base\$;');
    for (final method in methods) {
      body
        ..writeln()
        ..writeln(
          '${_indent}external ffi.Pointer<ffi.NativeFunction<'
          '${_nativeFn(method)}>>\n$_indent${method.name};',
        );
    }
    body.write('}');
    return body.toString();
  }

  /// `int Function(VTablePointer, ffi.Pointer<ffi.Uint16>)` — the Dart
  /// signature `asFunction` produces, with the `this` pointer first.
  String _dartFn(Member member) => [
    member.returns.name,
    ' Function(VTablePointer',
    for (final p in member.params) ', ${p.type.name}',
    ')',
  ].join();

  /// The same slot as dart:ffi types, for the vtable struct.
  String _nativeFn(Member member) => [
    member.returns.native ?? member.returns.name,
    ' Function(VTablePointer this\$',
    for (final p in member.params)
      ', ${p.type.native ?? p.type.name} ${p.name}',
    ')',
  ].join();

  /// `'{6f9b1a2c-3d4e-4f50-8a61-b2c3d4e5f607}'` as a `package:win32` GUID.
  String _guid(String literal) {
    final hex = literal.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    if (hex.length != 32) return 'GUID.parse($literal)';
    final bytes = [
      for (var i = 16; i < 32; i += 2) '0x${hex.substring(i, i + 2)}',
    ];
    final pad = '$_indent$_indent';
    return 'GUID.fromComponents(\n'
        '${pad}0x${hex.substring(0, 8)},\n'
        '${pad}0x${hex.substring(8, 12)},\n'
        '${pad}0x${hex.substring(12, 16)},\n'
        '${pad}Uint8List.fromList(const [${bytes.join(', ')}]),\n'
        '$_indent)';
  }

  // ------------------------------------------------------------------ helpers

  /// Whether [decl] is left out of the binding, recording why.
  bool _skip(Decl decl) {
    for (final marker in decl.markers) {
      if (marker.kind != MarkerKind.dropped) continue;
      if (marker.reason == reexportedFrom(library)) {
        reexports.add(decl.binding ?? decl.name);
      } else {
        refused.add('${decl.name}: ${marker.reason}');
      }
      return true;
    }
    return false;
  }

  String _docs(String? docs, String indent) {
    if (docs == null || docs.isEmpty) return '';
    final lines = [for (final line in docs.split('\n')) '$indent/// $line'];
    return '${lines.join('\n')}\n';
  }

  String _comment(String text) =>
      [for (final line in _wrap(text, 74)) '//   $line'].join('\n');

  /// Wraps at [width] columns, indenting continuations, so a long refusal
  /// stays readable in the generated file.
  List<String> _wrap(String text, int width) {
    final lines = <String>[];
    var current = StringBuffer();
    for (final word in text.split(' ')) {
      if (current.isEmpty) {
        current.write(word);
      } else if (current.length + 1 + word.length <= width) {
        current.write(' $word');
      } else {
        lines.add(current.toString());
        current = StringBuffer('  $word');
      }
    }
    if (current.isNotEmpty) lines.add(current.toString());
    return lines;
  }
}
