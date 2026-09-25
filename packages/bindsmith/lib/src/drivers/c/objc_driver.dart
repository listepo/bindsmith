/// Objective-C driver: runs ffigen 22 in Objective-C mode and lifts the result
/// into the IR.
///
/// Same upstream generator as the C driver, so the same read-back applies (see
/// [FfigenReader]): ffigen's AST names declarations and their selectors but
/// carries no types, and the generated Dart has the types. An Objective-C
/// header also declares plain C, so [objcToIr] runs [cToIr] over the same
/// binding and returns both.
///
/// Mapping (Objective-C → generated Dart → IR):
///
/// | Objective-C           | IR                                                |
/// |-----------------------|---------------------------------------------------|
/// | `@interface`          | `TypeDecl(klass)`, `id` = the class name          |
/// | `@protocol`           | `TypeDecl(interface)` + implementable marker      |
/// | `@interface X (Cat)`  | merged into `X`; pulled as `X(Cat)`               |
/// | instance/class method | `Member(method, isStatic:)`, `native` = selector  |
/// | `@property`           | `property` (+ `setter` when writable)             |
/// | `@optional` method    | member + verify marker (throws when unimplemented)|
/// | block parameter       | `Async.callback` + marker naming the block class  |
/// | `NSError **` argument | dropped by ffigen; verify marker: it throws       |
///
/// ffigen writes an Objective-C glue file next to the Dart one; the Apple glue
/// emitter (P2-3) puts it into the podspec.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ffigen/ffigen.dart' as ffigen;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../ir/ir.dart';
import 'c_driver.dart';
import 'ffigen_adapter.dart';

/// Generates a `package:objective_c` binding for Objective-C headers and
/// returns its IR.
final class ObjcDriver {
  ObjcDriver({
    required this.platform,
    required this.headers,
    this.compilerOptions = const [],
    this.include,
    this.assetId,
    this.preamble = '',
  });

  final Platform platform;

  /// Entry headers, absolute or relative to the working directory of [load].
  /// Only declarations written in these files are bound; frameworks they
  /// import contribute types on demand.
  final List<String> headers;

  /// Extra clang arguments (`-F…`, `-fmodules`). `-x objective-c` and the
  /// active SDK's `-isysroot` are added by ffigen itself.
  final List<String> compilerOptions;

  /// Pull list by Objective-C name: a class or protocol by its own name, a
  /// category as `Interface(Category)`. `null` binds everything declared in
  /// [headers].
  final bool Function(String objcName)? include;

  /// Asset id for `@DefaultAsset` (`package:foo/foo.dart`); `null` resolves
  /// symbols against the process, which is what a linked framework needs.
  final String? assetId;

  /// Text placed above ffigen's own header (license, ignores).
  final String preamble;

  /// Writes the Dart binding to [output] and the Objective-C glue to
  /// [objcOutput] (default: `<output>.m`), both relative to
  /// [workingDirectory], and returns the IR of what they contain.
  Future<List<Decl>> load({
    required String workingDirectory,
    required String output,
    String? objcOutput,
    Uri? libclangDylib,
    Logger? logger,
  }) async {
    final entries = [
      for (final h in headers) p.canonicalize(p.join(workingDirectory, h)),
    ];
    final out = File(p.join(workingDirectory, output));
    out.parent.createSync(recursive: true);
    final glue = File(p.join(workingDirectory, objcOutput ?? '$output.m'));
    glue.parent.createSync(recursive: true);
    final symbols = <String, CSymbol>{};
    final objc = <String, ObjcSymbol>{};
    await ffigen.FfiGenerator(
      input: ffigen.Input(
        entryPoints: [for (final e in entries) Uri.file(e)],
        include: (uri) => entries.contains(p.canonicalize(uri.toFilePath())),
        compilerOptions: compilerOptions,
      ),
      objectiveC: const ffigen.ObjectiveC(),
      output: ffigen.Output(
        dart: ffigen.DartOutput(path: Uri.file(out.absolute.path)),
        objectiveCFile: Uri.file(glue.absolute.path),
        style: ffigen.NativeExternalBindings(assetId: assetId),
        preamble: '$bindsmithHeader$preamble',
        commentType: sourceComments,
      ),
      visitors: [cRecorder(include ?? (_) => true, symbols), _recorder(objc)],
    ).generate(
      logger: logger ?? stderrFfigenLogger(),
      libclangDylib: libclangDylib,
    );
    // ffigen writes the glue's `#import` as a path from the generated file to
    // the header it parsed, which for an absolute entry point is a walk up to
    // the filesystem root and back down — the machine it ran on, baked into a
    // committed file (rule 6), and unbuildable anywhere else. What ships is the
    // header's own name, found through the include path a podspec or a build
    // hook sets, the same way the Swift driver ships `<Module>-Swift.h`.
    // ffigen's `preamble` reaches only the Dart file, so the glue gets the
    // header here.
    if (glue.existsSync()) {
      var text = glue.readAsStringSync();
      for (final entry in entries) {
        final name = p.basename(entry);
        text = text.replaceAll(
          RegExp('#import "(?:[^"]*[/\\\\])?${RegExp.escape(name)}"'),
          '#import "$name"',
        );
      }
      glue.writeAsStringSync('$bindsmithHeader$text');
    }

    return objcToIr(
      out.readAsStringSync(),
      platform: platform,
      symbols: symbols,
      objc: objc,
      loc: headers.length == 1 ? SourceLoc(headers.single) : null,
    );
  }

  /// Applies the pull list to the Objective-C declarations and records each
  /// one's selectors, which the generated Dart does not spell out.
  ffigen.Visitor _recorder(Map<String, ObjcSymbol> into) {
    ObjcSymbol record(ObjcSymbol s, List<ffigen.ObjCMethod> methods) {
      for (final m in methods) {
        s.selectors[m.isPropertySetter ? '${m.name}=' : m.name] = m.selector;
      }
      return s;
    }

    bool pull(String objcName) => include?.call(objcName) ?? true;
    return ffigen.Visitor(
      objCInterface: (i) {
        i.isIncluded = pull(i.originalName);
        // With a pull list, categories are named explicitly instead of being
        // dragged in by the interface they extend.
        if (include != null) i.includeCategories = false;
        into[i.name] = record(ObjcSymbol(i.originalName), i.methods);
      },
      objCProtocol: (q) {
        q.isIncluded = pull(q.originalName);
        into[q.name] = record(ObjcSymbol(q.originalName), q.methods);
      },
      objCCategory: (c) {
        c.isIncluded = pull('${c.interface.originalName}(${c.originalName})');
        into[c.name] = record(
          ObjcSymbol(c.originalName, owner: c.interface.name),
          c.methods,
        );
      },
    );
  }
}

/// What ffigen knows about an Objective-C declaration beyond the Dart it
/// generates, keyed by the Dart name in [objcToIr].
final class ObjcSymbol {
  ObjcSymbol(this.objcName, {this.owner});

  /// The Objective-C interface, protocol or category name.
  final String objcName;

  /// For a category, the Dart name of the interface it extends.
  final String? owner;

  /// Dart member name (a setter as `name=`) → Objective-C selector.
  final selectors = <String, String>{};
}

/// Lifts a generated `package:objective_c` [binding] into IR: the
/// Objective-C types first, then the C declarations of the same header.
/// Pure: no I/O, no ffigen.
List<Decl> objcToIr(
  String binding, {
  required Platform platform,
  Map<String, CSymbol> symbols = const {},
  Map<String, ObjcSymbol> objc = const {},
  SourceLoc? loc,
}) => [
  ..._Reader(
    parseString(content: binding, path: 'binding.g.dart').unit,
    platform,
    objc,
    loc,
  ).read(),
  ...cToIr(binding, platform: platform, symbols: symbols, loc: loc),
];

final class _Reader extends FfigenReader {
  _Reader(super.unit, super.platform, this.symbols, super.loc) {
    for (final d in unit.declarations) {
      switch (d) {
        case ExtensionTypeDeclaration():
          types[d.namePart.typeName.lexeme] = d;
        // `extension X$Methods on X` and one extension per category.
        case ExtensionDeclaration(
          onClause: ExtensionOnClause(
            extendedType: NamedType(:final name, importPrefix: null),
          ),
        ):
          extensions.putIfAbsent(name.lexeme, () => []).add(d);
        case ClassDeclaration():
          classes.add(d.namePart.typeName.lexeme);
          // `/// Construction methods for `objc.ObjCBlock<…>`.`
          final docs = this.docs(d) ?? '';
          final open = docs.indexOf('`');
          if (docs.startsWith('Construction methods for ') && open >= 0) {
            blocks[_key(docs.substring(open + 1, docs.lastIndexOf('`')))] =
                d.namePart.typeName.lexeme;
          }
        default:
      }
    }
  }

  final Map<String, ObjcSymbol> symbols;

  /// Dart name → the `extension type` generated for an interface or protocol.
  final types = <String, ExtensionTypeDeclaration>{};

  /// Dart type name → every extension declared on it.
  final extensions = <String, List<ExtensionDeclaration>>{};

  /// Names of the plain classes ffigen generates (protocol builders, block
  /// construction helpers).
  final classes = <String>{};

  /// `objc.ObjCBlock<…>` → the class holding that block's constructors.
  final blocks = <String, String>{};

  List<Decl> read() => [
    for (final MapEntry(key: name, value: d) in types.entries)
      // `_BlockArgs_…` are ffigen's own argument carriers.
      if (!name.startsWith('_')) _type(name, d),
  ];

  TypeDecl _type(String name, ExtensionTypeDeclaration d) {
    final symbol = symbols[name];
    // A protocol's representation is `objc.ObjCProtocol`; an interface wraps
    // `objc.ObjCObject`.
    final isProtocol = d.namePart.toSource().contains('ObjCProtocol');
    final interfaceId = symbol?.objcName ?? name;
    final docParts = <String>[?_ownDocs(docs(d), interfaceId)];
    for (final e in extensions[name] ?? const <ExtensionDeclaration>[]) {
      final cat = e.name?.lexeme;
      if (cat == null || cat.endsWith(r'$Methods')) continue;
      final catDoc = _ownDocs(docs(e), cat);
      if (catDoc != null) {
        docParts.add('`$interfaceId($cat)`: $catDoc');
      }
    }
    return TypeDecl(
      id: interfaceId,
      name: name,
      platform: platform,
      kind: isProtocol ? TypeKind.interface : TypeKind.klass,
      members: [
        for (final m in d.body.members) ?_member(m, symbol),
        for (final e in extensions[name] ?? const <ExtensionDeclaration>[])
          // A category's selectors were recorded under the category's name.
          for (final m in e.body.members)
            ?_member(m, symbols[e.name?.lexeme] ?? symbol),
      ],
      supertypes: [
        for (final t in d.implementsClause?.interfaces ?? const <NamedType>[])
          // The representation type repeats in `implements`.
          if (t.name.lexeme != 'ObjCObject' && t.name.lexeme != 'ObjCProtocol')
            type(t),
      ],
      loc: loc,
      docs: docParts.isEmpty ? null : docParts.join('\n\n'),
      markers: [
        if (isProtocol && classes.contains('$name\$Builder'))
          Marker.verify(
            'Objective-C protocol: implement it from Dart with '
            '$name\$Builder.implement(...)',
          ),
      ],
    );
  }

  Member? _member(ClassMember m, ObjcSymbol? symbol) {
    final selectors = symbol?.selectors ?? const <String, String>{};
    switch (m) {
      // `BSMCounter()` forwards to the class's `new`; `.as` and `.fromPointer`
      // only rewrap a pointer that already exists.
      case ConstructorDeclaration(name: null):
        return Member('', kind: MemberKind.constructor, native: 'new');
      case ConstructorDeclaration():
        return null;
      case MethodDeclaration():
        final name = m.name.lexeme;
        final key = m.isSetter ? '$name=' : name;
        final selector = selectors[key] ?? selectors[_unescape(key)];
        // No selector means ffigen invented the member (`isA`, `conformsTo`).
        if (selector == null) return null;
        final block = _block(m.parameters);
        final params = _params(m.parameters);
        final split = splitCommentDocs(
          _ownDocs(docs(m), selector),
          paramNames: {for (final q in params) q.name},
        );
        return Member(
          name,
          kind: m.isGetter
              ? MemberKind.property
              : m.isSetter
              ? MemberKind.setter
              : MemberKind.method,
          params: withParamDocs(params, split.paramDocs),
          returns: m.returnType == null
              ? const TypeRef('void')
              : type(m.returnType!),
          async: block == null ? Async.none : Async.callback,
          isStatic: m.isStatic,
          native: selector == name ? null : selector,
          docs: split.memberDocs,
          markers: _markers(m, block),
        );
      default:
        return null;
    }
  }

  /// ffigen documents an undocumented Objective-C declaration with its own
  /// name (`/// alloc`, `/// initWithLabel:`), ahead of any availability
  /// note. That tells a reader nothing the declaration does not.
  String? _ownDocs(String? docs, String name) {
    if (docs == name) return null;
    if (docs != null && docs.startsWith('$name\n\n')) {
      return docs.substring(name.length + 2);
    }
    return docs;
  }

  List<Marker> _markers(MethodDeclaration m, String? block) {
    final body = m.body.toSource();
    return [
      if (body.contains('NSErrorException'))
        const Marker.verify(
          'the Objective-C `error:` out-parameter is dropped; a failure '
          'throws NSErrorException instead',
        ),
      if (body.contains('UnimplementedOptionalMethodException'))
        const Marker.verify(
          '@optional protocol method: throws '
          'UnimplementedOptionalMethodException when the receiver does not '
          'implement it',
        ),
      if (block != null)
        Marker.verify(
          'takes an Objective-C block: build it with $block.listener (any '
          'thread, void return only), $block.blocking (blocks the caller) or '
          '$block.fromFunction (owner isolate only). A completion handler '
          'becomes a Future in the facade',
        ),
    ];
  }

  /// The class holding the constructors of the block a parameter takes, if
  /// any: the parameter is written as ffigen's Dart-side typedef, which
  /// aliases the `objc.ObjCBlock<…>` the block class is documented with.
  String? _block(FormalParameterList? list) {
    for (final q in list?.parameters ?? const <FormalParameter>[]) {
      final t = q.type;
      if (t is! NamedType) continue;
      final alias = aliases[t.name.lexeme];
      final block = blocks[_key((alias?.type ?? t).toSource())];
      if (block != null) return block;
    }
    return null;
  }

  List<Param> _params(FormalParameterList? list) => [
    for (final q in list?.parameters ?? const <FormalParameter>[])
      Param(
        q.name!.lexeme,
        q.type == null ? const TypeRef('dynamic') : type(q.type!),
        named: q.isNamed,
        optional: q.isOptional,
      ),
  ];

  /// ffigen appends `$` to a Dart keyword (`new` → `new$`); the selector was
  /// recorded under the unescaped name.
  String _unescape(String name) =>
      name.endsWith(r'$') ? name.substring(0, name.length - 1) : name;

  /// Written Dart types are compared without whitespace: `toSource()` and the
  /// doc comment ffigen writes disagree about where the line breaks go.
  String _key(String type) => type.replaceAll(RegExp(r'\s+'), '');
}
