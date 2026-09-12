/// C++ shim emitter: writes the `extern "C"` surface that lets the C driver
/// bind a C++ library without anyone parsing C++.
///
/// bindsmith does not parse C++ and will not (`plan.md` §1): Clang's C++ AST
/// is not something ffigen exposes, and a binding generated from it would be
/// tied to one ABI. The supported path is the one every other toolkit ends up
/// at — a thin C surface over the C++ API — and this emitter writes it from
/// the IR, so the shim and the Dart binding cannot drift apart.
///
/// ```c
/// typedef struct greeter_Greeter greeter_Greeter;
///
/// greeter_Greeter* greeter_Greeter_new(const char* prefix);
/// void greeter_Greeter_delete(greeter_Greeter* self);
/// char* greeter_Greeter_Greet(greeter_Greeter* self, const char* name);
/// const char* greeter_last_error(void);
/// ```
///
/// Three things the boundary has to get right, all of them in the generated
/// source rather than left to the caller:
///
/// * **Exceptions.** A C++ exception unwinding through `extern "C"` is
///   undefined behaviour, so every body runs inside a guard that catches
///   everything, records the message, and returns a zero value. The caller
///   asks `<prefix>_last_error()`, which is `NULL` after a call that worked.
/// * **Ownership.** An `std::string` result is copied onto the C heap and
///   freed with `<prefix>_free_string`; a class result is copied onto the
///   heap and freed with that class's `_delete`. Nothing returns a pointer
///   into a temporary.
/// * **Null.** A `const char*` argument is never handed to `std::string`
///   unchecked, because `std::string(nullptr)` is undefined.
///
/// A type with no C spelling — `std::vector`, a template, anything not named
/// in the IR — is refused with the reason as a comment and keeps its marker,
/// so `bindsmith verify` still reports it. The header is plain C, which is
/// what [CDriver] binds; building it is `hook/build.dart`'s job (P5-5).
///
/// @docImport '../drivers/c/c_driver.dart';
library;

import '../ir/ir.dart';

/// The two generated files and the C functions they declare, which the C
/// driver takes as its pull list.
typedef CppShim = ({String header, String source, Set<String> symbols});

/// Emits an `extern "C"` shim for every class in [ir].
///
/// [prefix] is the C symbol prefix (`greeter` → `greeter_Greeter_new`), and
/// must be a C identifier. [includes] are the C++ headers the shim needs,
/// written as they appear after `#include` (`'"greeter.h"'`, `'<lib/api.h>'`).
/// [header] is the file name the source includes itself by. A declaration's
/// `id` is its qualified C++ name (`greeter::Greeter`) and its `name` the
/// short one.
CppShim emitCppShim(
  List<Decl> ir, {
  required String prefix,
  required List<String> includes,
  String header = 'shim.h',
  String preamble = '',
}) => _Shim(ir, prefix).run(includes, header, preamble);

/// C spellings that cross unchanged. Everything else is either a class in the
/// IR, a string, or refused.
const _arithmetic = {
  'void',
  'bool',
  'char',
  'signed char',
  'unsigned char',
  'short',
  'unsigned short',
  'int',
  'unsigned int',
  'unsigned',
  'long',
  'unsigned long',
  'long long',
  'unsigned long long',
  'float',
  'double',
  'long double',
  'size_t',
  'ptrdiff_t',
  'int8_t',
  'int16_t',
  'int32_t',
  'int64_t',
  'uint8_t',
  'uint16_t',
  'uint32_t',
  'uint64_t',
};

const _strings = {'std::string', 'std::string_view'};

final class _Shim {
  _Shim(this.ir, this.prefix) {
    for (final d in ir.whereType<TypeDecl>()) {
      if (d.kind == TypeKind.klass || d.kind == TypeKind.struct) {
        classes[d.name] = d;
        classes[d.id] = d;
      }
    }
  }

  final List<Decl> ir;
  final String prefix;

  /// Both the short and the qualified C++ name point at the declaration, so a
  /// signature can spell either.
  final classes = <String, TypeDecl>{};

  final refused = <String>[];
  final taken = <String>{};

  CppShim run(List<String> includes, String header, String preamble) {
    final declarations = <String>[];
    final definitions = <String>[];
    final symbols = <String>{};

    for (final decl in ir.whereType<TypeDecl>()) {
      if (decl.isDropped) continue;
      if (decl.kind != TypeKind.klass && decl.kind != TypeKind.struct) {
        refused.add('${decl.name}: only a class or struct becomes a handle');
        continue;
      }
      if (decl.typeParams.isNotEmpty) {
        refused.add(
          '${decl.name}: template over <${decl.typeParams.join(', ')}>, which '
          'has no C spelling until it is instantiated',
        );
        continue;
      }
      _type(decl, declarations, definitions, symbols);
    }

    return (
      header: _header(declarations, symbols, preamble),
      source: _source(definitions, includes, header, preamble),
      symbols: symbols,
    );
  }

  String _header(List<String> declarations, Set<String> symbols, String pre) {
    final guard = 'BINDSMITH_${prefix.toUpperCase()}_SHIM_H_';
    final out = StringBuffer()
      ..writeln('// GENERATED BY bindsmith — do not edit.')
      ..write(pre)
      ..writeln('#ifndef $guard')
      ..writeln('#define $guard')
      ..writeln()
      ..writeln('#include <stdbool.h>')
      ..writeln('#include <stddef.h>')
      ..writeln('#include <stdint.h>')
      ..writeln()
      ..writeln('#ifdef __cplusplus')
      ..writeln('extern "C" {')
      ..writeln('#endif')
      ..writeln()
      ..write(
        _doc(0, [
          'The message of the last call that failed, or NULL when the last '
              'call on this thread succeeded. Owned by the shim, and valid '
              'until the next call on this thread.',
        ]),
      )
      ..writeln('const char* ${prefix}_last_error(void);')
      ..writeln()
      ..write(_doc(0, ['Frees a string this shim returned.']))
      ..writeln('void ${prefix}_free_string(char* value);')
      ..write(declarations.join());
    symbols
      ..add('${prefix}_last_error')
      ..add('${prefix}_free_string');
    return (out
          ..writeln()
          ..writeln('#ifdef __cplusplus')
          ..writeln('}')
          ..writeln('#endif')
          ..writeln()
          ..write(_notBridged())
          ..writeln('#endif  // $guard'))
        .toString();
  }

  String _source(
    List<String> definitions,
    List<String> includes,
    String header,
    String pre,
  ) {
    final out = StringBuffer()
      ..writeln('// GENERATED BY bindsmith — do not edit.')
      ..write(pre)
      ..writeln('#include "$header"')
      ..writeln()
      ..writeln('#include <cstdlib>')
      ..writeln('#include <cstring>')
      ..writeln('#include <exception>')
      ..writeln('#include <string>')
      ..writeln();
    for (final include in includes) {
      out.writeln('#include $include');
    }
    return (out
          ..writeln()
          ..write(_runtime())
          ..writeln('extern "C" {')
          ..writeln()
          ..writeln('const char* ${prefix}_last_error(void) {')
          ..writeln(
            '  return bindsmith_failed ? bindsmith_error.c_str() : NULL;',
          )
          ..writeln('}')
          ..writeln()
          ..writeln('void ${prefix}_free_string(char* value) {')
          ..writeln('  std::free(value);')
          ..writeln('}')
          ..write(definitions.join())
          ..writeln()
          ..writeln('}  // extern "C"'))
        .toString();
  }

  /// The two helpers every generated body uses. In an anonymous namespace, so
  /// linking two shims into one binary cannot collide.
  String _runtime() =>
      '''
namespace {

/// An exception unwinding out of `extern "C"` is undefined behaviour, so the
/// message is recorded here instead and the call returns a zero value.
thread_local std::string bindsmith_error;
thread_local bool bindsmith_failed = false;

template <typename Body>
auto bindsmith_guard(Body body) -> decltype(body()) {
  bindsmith_failed = false;
  try {
    return body();
  } catch (const std::exception& error) {
    bindsmith_error = error.what();
  } catch (...) {
    bindsmith_error = "unknown C++ exception";
  }
  bindsmith_failed = true;
  return decltype(body())();
}

/// Copies onto the C heap, so the result outlives the temporary it came from
/// and `${prefix}_free_string` can release it.
char* bindsmith_copy(const std::string& value) {
  char* out = static_cast<char*>(std::malloc(value.size() + 1));
  if (out != NULL) {
    std::memcpy(out, value.c_str(), value.size() + 1);
  }
  return out;
}

}  // namespace

''';

  void _type(
    TypeDecl decl,
    List<String> declarations,
    List<String> definitions,
    Set<String> symbols,
  ) {
    final handle = '${prefix}_${decl.name}';
    final cpp = decl.id;
    declarations
      ..add('\n')
      ..add(_doc(0, [...?decl.docs?.split('\n'), 'Opaque handle for `$cpp`.']))
      ..add('typedef struct $handle $handle;\n');

    for (final member in decl.members) {
      final piece = switch (member.kind) {
        MemberKind.constructor => _constructor(decl, member, handle, cpp),
        MemberKind.method => _method(decl, member, handle, cpp),
        MemberKind.property => _method(decl, member, handle, cpp),
        MemberKind.setter => _method(decl, member, handle, cpp),
        _ => null,
      };
      if (piece == null) continue;
      declarations.add(piece.declaration);
      definitions.add(piece.definition);
      symbols.add(piece.symbol);
    }

    final destructor = _name('${handle}_delete');
    symbols.add(destructor);
    declarations
      ..add('\n')
      ..add(_doc(0, ['Destroys a `$cpp`. Safe on NULL.']))
      ..add('void $destructor($handle* self);\n');
    definitions
      ..add('\n')
      ..add('void $destructor($handle* self) {\n')
      ..add('  delete reinterpret_cast<$cpp*>(self);\n')
      ..add('}\n');
  }

  ({String declaration, String definition, String symbol})? _constructor(
    TypeDecl decl,
    Member member,
    String handle,
    String cpp,
  ) {
    final params = _params(decl, member, self: null);
    if (params == null) return null;
    final name = _name('${handle}_new${member.binding ?? ''}');
    return (
      symbol: name,
      declaration:
          '\n'
          '${_doc(0, [...?member.docs?.split('\n'), 'The caller owns the result; release it with `${handle}_delete`. '
              'NULL means the call threw: ask `${prefix}_last_error`.'])}'
          '$handle* $name(${_signature(params)});\n',
      definition:
          '\n'
          '$handle* $name(${_signature(params)}) {\n'
          '  return bindsmith_guard([&]() -> $handle* {\n'
          '    return reinterpret_cast<$handle*>('
          'new $cpp(${_arguments(params)}));\n'
          '  });\n'
          '}\n',
    );
  }

  ({String declaration, String definition, String symbol})? _method(
    TypeDecl decl,
    Member member,
    String handle,
    String cpp,
  ) {
    final returns = _return(decl, member);
    if (returns == null) return null;
    final params = _params(
      decl,
      member,
      self: member.isStatic ? null : '$handle* self',
    );
    if (params == null) return null;

    final call = member.isStatic
        ? '$cpp::${member.native ?? member.name}'
        : 'reinterpret_cast<$cpp*>(self)->${member.native ?? member.name}';
    final invocation = member.kind == MemberKind.property
        ? call
        : '$call(${_arguments(params)})';
    final name = _name('${handle}_${member.name}');

    return (
      symbol: name,
      declaration:
          '\n'
          '${_doc(0, [...?member.docs?.split('\n'), ...returns.note, 'Check `${prefix}_last_error` afterwards: this call can throw.'])}'
          '${returns.type} $name(${_signature(params)});\n',
      definition:
          '\n'
          '${returns.type} $name(${_signature(params)}) {\n'
          '  return bindsmith_guard([&]() -> ${returns.type} {\n'
          '    ${returns.wrap(invocation)};\n'
          '  });\n'
          '}\n',
    );
  }

  /// The C return type, how to produce it, and what to say about ownership.
  ({String type, String Function(String) wrap, List<String> note})? _return(
    TypeDecl decl,
    Member member,
  ) {
    final cpp = _bare(member.returns.native ?? member.returns.name);
    if (cpp == 'void') {
      return (type: 'void', wrap: (call) => call, note: const []);
    }
    if (_strings.contains(cpp)) {
      return (
        type: 'char*',
        wrap: (call) => 'return bindsmith_copy($call)',
        note: [
          'The caller owns the result; release it with '
              '`${prefix}_free_string`. NULL means the call threw.',
        ],
      );
    }
    if (_arithmetic.contains(cpp)) {
      return (type: cpp, wrap: (call) => 'return $call', note: const []);
    }
    if (classes[cpp] case final target?) {
      final handle = '${prefix}_${target.name}';
      return (
        type: '$handle*',
        wrap: (call) =>
            'return reinterpret_cast<$handle*>(new ${target.id}($call))',
        note: [
          'The caller owns the result, which is a copy; release it with '
              '`${handle}_delete`. NULL means the call threw.',
        ],
      );
    }
    refused.add(
      '${decl.name}.${member.name}: `$cpp` has no C spelling; '
      'return a handle or a string instead',
    );
    return null;
  }

  /// Each parameter as its C declaration and the C++ expression that reads it.
  List<({String declaration, String argument})>? _params(
    TypeDecl decl,
    Member member, {
    required String? self,
  }) {
    final out = <({String declaration, String argument})>[
      if (self != null) (declaration: self, argument: ''),
    ];
    for (final q in member.params) {
      final native = q.type.native ?? q.type.name;
      final cpp = _bare(native);
      if (_strings.contains(cpp)) {
        out.add((
          declaration: 'const char* ${q.name}',
          // `std::string(nullptr)` is undefined; an empty string is not.
          argument: 'std::string(${q.name} ? ${q.name} : "")',
        ));
        continue;
      }
      if (_arithmetic.contains(cpp) && cpp != 'void') {
        out.add((declaration: '$cpp ${q.name}', argument: q.name));
        continue;
      }
      if (classes[cpp] case final target?) {
        final handle = '${prefix}_${target.name}';
        final pointer = 'reinterpret_cast<${target.id}*>(${q.name})';
        out.add((
          declaration: '$handle* ${q.name}',
          // The C++ side takes a pointer or a reference; only a pointer
          // crosses, so a reference parameter is dereferenced here.
          argument: native.trimRight().endsWith('*') ? pointer : '*$pointer',
        ));
        continue;
      }
      refused.add(
        '${decl.name}.${member.name}: `$cpp` has no C spelling; '
        'take a handle or a string instead',
      );
      return null;
    }
    return out;
  }

  String _signature(List<({String declaration, String argument})> params) =>
      params.isEmpty
      ? 'void'
      : [for (final q in params) q.declaration].join(', ');

  String _arguments(List<({String declaration, String argument})> params) => [
    for (final q in params)
      if (q.argument.isNotEmpty) q.argument,
  ].join(', ');

  /// `const std::string&` → `std::string`; `Greeter*` → `Greeter`.
  String _bare(String cpp) {
    var out = cpp.trim();
    if (out.startsWith('const ')) out = out.substring(6).trim();
    while (out.endsWith('&') || out.endsWith('*')) {
      out = out.substring(0, out.length - 1).trimRight();
      if (out.startsWith('const ')) out = out.substring(6).trim();
    }
    return out;
  }

  /// A C identifier nothing else claimed. Overloads share a spelling in C++
  /// and cannot in C.
  String _name(String wanted) {
    if (taken.add(wanted)) return wanted;
    for (var i = 2; ; i++) {
      if (taken.add('${wanted}_$i')) return '${wanted}_$i';
    }
  }

  String _notBridged() {
    if (refused.isEmpty) return '';
    final out = StringBuffer(
      '// Not bridged, and still reported by `bindsmith verify`:\n',
    );
    for (final line in refused) {
      for (final (i, wrapped) in _wrap(line, 74).indexed) {
        out.writeln(i == 0 ? '//   $wrapped' : '//     $wrapped');
      }
    }
    return (out..writeln()).toString();
  }
}

/// A `///` comment block, which is what ffigen carries into the Dart binding.
String _doc(int indent, List<String> paragraphs) {
  final pad = ' ' * indent;
  final kept = [
    for (final p in paragraphs)
      for (final line in p.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
  ];
  final out = StringBuffer();
  for (final (i, paragraph) in kept.indexed) {
    if (i > 0) out.writeln('$pad///');
    for (final line in _wrap(paragraph, 77 - indent)) {
      out.writeln('$pad/// $line');
    }
  }
  return out.toString();
}

/// Greedy word wrap; a word longer than [width] keeps its own line, because
/// it is a type or an identifier.
List<String> _wrap(String text, int width) {
  final lines = <String>[];
  final line = StringBuffer();
  for (final word in text.split(' ')) {
    if (line.isNotEmpty && line.length + 1 + word.length > width) {
      lines.add(line.toString());
      line.clear();
    }
    line.write(line.isEmpty ? word : ' $word');
  }
  if (line.isNotEmpty) lines.add(line.toString());
  return lines;
}
