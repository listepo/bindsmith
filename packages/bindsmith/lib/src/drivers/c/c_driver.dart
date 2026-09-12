/// C driver: runs ffigen 22 through its library API and lifts the result into
/// the IR.
///
/// ffigen's public AST exposes names and USRs but no types, so signatures are
/// read back from the Dart it generated (`package:analyzer`, syntax only). The
/// generated file *is* the platform binding; the IR describes what it holds so
/// passes, the facade and `bindsmith verify` can work on it.
///
/// Mapping (C → generated Dart → IR):
///
/// | C                       | IR                                                   |
/// |-------------------------|------------------------------------------------------|
/// | function                | `FunctionDecl`, `TypeRef.native` = dart:ffi type     |
/// | variadic function       | fixed arguments only + verify marker                 |
/// | struct / union          | `TypeDecl(struct)` with `field` members (union: verify) |
/// | forward-declared struct | `TypeDecl(opaque)`                                   |
/// | enum                    | `TypeDecl(enumeration)`, `constant` members with values |
/// | typedef                 | `TypeDecl(typedef)`, target in `supertypes`          |
/// | function-pointer typedef| as above + callback signature in docs + verify       |
/// | `#define` constant      | `VariableDecl(isConst: true, value:)`                |
/// | global                  | `VariableDecl`                                       |
///
/// Names stay as ffigen emits them (the C spelling); `id` is the C name.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ffigen/ffigen.dart' as ffigen;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../ir/ir.dart';
import '../../passes/glib_macros.dart';
import 'ffigen_adapter.dart';
import 'header_docs.dart';

export 'ffigen_adapter.dart' show CSymbol;

/// Generates a dart:ffi binding for C headers and returns its IR.
final class CDriver {
  CDriver({
    required this.platform,
    required this.headers,
    this.compilerOptions = const [],
    this.include,
    this.assetId,
    this.preamble = '',
  });

  final Platform platform;

  /// Entry headers, absolute or relative to the working directory of [load].
  /// Only declarations written in these files are bound; headers they include
  /// contribute types on demand.
  final List<String> headers;

  /// Extra clang arguments (`-I…`, `-DFOO=1`).
  final List<String> compilerOptions;

  /// Pull list by C name; `null` binds everything declared in [headers].
  /// Typedefs are not filtered: they appear when something bound uses them.
  final bool Function(String cName)? include;

  /// Asset id for `@DefaultAsset` (`package:foo/foo.dart`); `null` resolves
  /// symbols against the process.
  final String? assetId;

  /// Text placed above ffigen's own header (license, ignores).
  final String preamble;

  /// Writes the binding to [output] (relative to [workingDirectory]) and
  /// returns the IR of what it contains. ffigen warnings go to [logger]
  /// (default: stderr); libclang is found at the platform default locations
  /// unless [libclangDylib] is given.
  Future<List<Decl>> load({
    required String workingDirectory,
    required String output,
    Uri? libclangDylib,
    Logger? logger,
  }) async {
    final entries = [
      for (final h in headers) p.canonicalize(p.join(workingDirectory, h)),
    ];
    final out = File(p.join(workingDirectory, output));
    out.parent.createSync(recursive: true);
    final symbols = <String, CSymbol>{};
    await ffigen.FfiGenerator(
      input: ffigen.Input(
        entryPoints: [for (final e in entries) Uri.file(e)],
        include: (uri) => entries.contains(p.canonicalize(uri.toFilePath())),
        compilerOptions: compilerOptions,
      ),
      output: ffigen.Output(
        dart: ffigen.DartOutput(path: Uri.file(out.absolute.path)),
        style: ffigen.NativeExternalBindings(assetId: assetId),
        preamble: '$bindsmithHeader$preamble',
        commentType: sourceComments,
      ),
      visitors: [cRecorder(include ?? (_) => true, symbols)],
    ).generate(
      logger: logger ?? stderrFfigenLogger(),
      libclangDylib: libclangDylib,
    );
    final decls = cToIr(
      out.readAsStringSync(),
      platform: platform,
      symbols: symbols,
      loc: headers.length == 1 ? SourceLoc(headers.single) : null,
    );
    return glibMacroPass()(
      mergeHeaderDocs(
        decls,
        headerDocsFromTree(
          entryHeaders: headers,
          workingDirectory: workingDirectory,
        ),
      ),
    );
  }
}

/// Lifts a generated dart:ffi [binding] into IR. Pure: no I/O, no ffigen.
List<Decl> cToIr(
  String binding, {
  required Platform platform,
  Map<String, CSymbol> symbols = const {},
  SourceLoc? loc,
}) => _Reader(
  parseString(content: binding, path: 'binding.g.dart').unit,
  platform,
  symbols,
  loc,
).read();

final class _Reader extends FfigenReader {
  _Reader(super.unit, super.platform, this.symbols, super.loc) {
    for (final d in unit.declarations) {
      if (d is FunctionDeclaration) functions[d.name.lexeme] = d;
    }
  }

  final Map<String, CSymbol> symbols;
  final functions = <String, FunctionDeclaration>{};

  List<Decl> read() => [
    for (final d in unit.declarations)
      ...switch (d) {
        // `_name` externals back the wrappers ffigen writes for enum-taking
        // functions; the wrapper is the API.
        FunctionDeclaration() when !d.name.lexeme.startsWith('_') => [
          _function(d),
        ],
        TopLevelVariableDeclaration() => _variables(d),
        ClassDeclaration() => [?_compound(d)],
        EnumDeclaration() => [_enum(d)],
        GenericTypeAlias() when symbols.containsKey(d.name.lexeme) => [
          _typedef(d),
        ],
        _ => const <Decl>[],
      },
  ];

  String _id(String dartName) => symbols[dartName]?.cName ?? dartName;

  FunctionDecl _function(FunctionDeclaration d) {
    final name = d.name.lexeme;
    final native =
        nativeType(d.metadata) ??
        nativeType(functions['_$name']?.metadata ?? []);
    final (String? nativeReturn, List<String?> nativeParams) = switch (native) {
      GenericFunctionType(:final returnType, :final parameters) => (
        returnType?.toSource(),
        [for (final q in parameters.parameters) q.type?.toSource()],
      ),
      _ => (null, const []),
    };
    final List<FormalParameter> params =
        d.functionExpression.parameters?.parameters ?? const [];
    final irParams = [
      for (final (i, q) in params.indexed)
        Param(
          q.name?.lexeme ?? 'arg$i',
          _returns(q.type, nativeParams.elementAtOrNull(i)),
        ),
    ];
    final upstream =
        docs(d) ??
        switch (functions['_$name']) {
          final upstream? => docs(upstream),
          null => null,
        };
    final split = splitCommentDocs(
      upstream,
      paramNames: {for (final q in irParams) q.name},
    );
    return FunctionDecl(
      id: _id(name),
      name: name,
      platform: platform,
      params: withParamDocs(irParams, split.paramDocs),
      // A function written without a return type is `dynamic` in Dart, which
      // only happens in hand-written bindings; ffigen always writes one.
      returns: _returns(d.returnType, nativeReturn),
      loc: loc,
      docs: split.memberDocs,
      markers: [
        if (symbols[name]?.variadic ?? false)
          const Marker(
            MarkerKind.verify,
            'variadic: bound with its fixed arguments only; other argument '
            'lists need an ffigen varArgs entry',
          ),
      ],
    );
  }

  TypeRef _returns(TypeAnnotation? t, String? native) =>
      t == null ? TypeRef('dynamic', native: native) : type(t, native: native);

  List<Decl> _variables(TopLevelVariableDeclaration d) {
    final type_ = d.variables.type;
    // ffigen's own plumbing (`_class_Foo`, `_sel_bar`, `_objc_msgSend_…`) is
    // private and untyped; only declared globals and macros reach the IR.
    if (type_ == null) return const [];
    final native = nativeType(d.metadata)?.toSource();
    return [
      for (final v in d.variables.variables)
        if (!v.name.lexeme.startsWith('_'))
          VariableDecl(
            id: _id(v.name.lexeme),
            name: v.name.lexeme,
            platform: platform,
            type: type(type_, native: native),
            value: v.initializer?.toSource(),
            isConst: d.variables.isConst,
            loc: loc,
            docs: docs(d),
          ),
    ];
  }

  TypeDecl? _compound(ClassDeclaration d) {
    final base = d.extendsClause?.superclass.name.lexeme;
    if (base != 'Struct' && base != 'Union' && base != 'Opaque') return null;
    final name = d.namePart.typeName.lexeme;
    final children = symbols[name]?.children ?? const {};
    return TypeDecl(
      id: _id(name),
      name: name,
      platform: platform,
      kind: base == 'Opaque' ? TypeKind.opaque : TypeKind.struct,
      members: [
        for (final m in d.body.members)
          if (m is FieldDeclaration && !m.isStatic)
            for (final f in m.fields.variables)
              Member(
                f.name.lexeme,
                kind: MemberKind.field,
                returns: type(
                  m.fields.type!,
                  native: m.metadata.isEmpty
                      ? null
                      : _annotationType(m.metadata.first),
                ),
                native: _cName(children, f.name.lexeme),
                docs: docs(m),
              ),
      ],
      loc: loc,
      docs: docs(d),
      markers: [
        if (base == 'Union')
          const Marker(
            MarkerKind.verify,
            'C union: all fields share the same storage',
          ),
      ],
    );
  }

  TypeDecl _enum(EnumDeclaration d) {
    final name = d.namePart.typeName.lexeme;
    final children = symbols[name]?.children ?? const {};
    return TypeDecl(
      id: _id(name),
      name: name,
      platform: platform,
      kind: TypeKind.enumeration,
      members: [
        for (final c in d.body.constants)
          Member(
            c.name.lexeme,
            kind: MemberKind.constant,
            returns: const TypeRef('int'),
            value: c.arguments?.argumentList.arguments.firstOrNull?.toSource(),
            native: _cName(children, c.name.lexeme),
            docs: docs(c),
          ),
      ],
      loc: loc,
      docs: docs(d),
      markers: const [
        Marker(
          MarkerKind.verify,
          'enum storage size is implementation-defined; ffigen mimics the '
          'platform compiler',
        ),
      ],
    );
  }

  TypeDecl _typedef(GenericTypeAlias d) {
    final name = d.name.lexeme;
    // ffigen pairs a native typedef with a Dart-side twin (`Dartfoo = int`)
    // and a function-pointer typedef with `Dart<name>Function`.
    final twin = aliases['Dart$name'];
    final callback = aliases['Dart${name}Function'];
    return TypeDecl(
      id: _id(name),
      name: name,
      platform: platform,
      kind: TypeKind.typedef,
      supertypes: [type((twin ?? d).type, native: d.type.toSource())],
      loc: loc,
      docs: join([
        docs(d),
        if (callback != null) 'Callback signature: ${callback.type.toSource()}',
      ]),
      markers: [
        if (callback != null)
          const Marker(
            MarkerKind.verify,
            'C function pointer: pass Pointer.fromFunction or a '
            'NativeCallable; Dart closures are not marshalled',
          ),
      ],
    );
  }

  /// `@ffi.Double()` → `ffi.Double`; `@ffi.Array(3)` → `ffi.Array(3)`.
  String _annotationType(Annotation a) {
    final args = a.arguments;
    return args == null || args.arguments.isEmpty
        ? a.name.name
        : '${a.name.name}${args.toSource()}';
  }

  String? _cName(Map<String, String> children, String dartName) {
    final c = children[dartName];
    return c == null || c == dartName ? null : c;
  }
}
