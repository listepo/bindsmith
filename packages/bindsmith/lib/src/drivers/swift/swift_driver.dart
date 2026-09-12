/// Swift driver: runs swiftgen 0.2 through its library API and lifts the
/// result into the IR.
///
/// Dart reaches Swift through Objective-C, so swiftgen is a pipeline:
/// swift2objc writes an `@objc` wrapper for the Swift API, `swiftc` emits the
/// Objective-C header for it, and ffigen binds that header. The last step is
/// the Objective-C driver's territory, so [swiftToIr] is [objcToIr] plus the
/// bookkeeping that only this pipeline can do.
///
/// Two things do not survive the trip, and neither may be lost quietly:
///
/// * A declaration swift2objc cannot parse (an array parameter, a generic
///   type) never reaches the wrapper. swift2objc reports these on the [Logger]
///   it is given — one `SEVERE` record per declaration, and only for the
///   caller's own sources, never for the SDK — so the driver keeps that
///   logger and turns each record into a `dropped` marker.
/// * A declaration that swift2objc did accept but that no longer appears in
///   the binding is found by diffing what `SwiftGenerator.include` was offered
///   against what came back, which needs no diagnostics at all.
///
/// Either way the diagnostic says only *that* something was lost. What it is
/// comes from the Swift symbol graph swift2objc parsed, which this driver
/// reads out of the temporary directory it hands to swiftgen (see
/// `symbolgraph.dart`). A dropped declaration therefore arrives in the IR with
/// its parameters, result and doc comment intact, which is what
/// `bindsmith verify` reports and what `emitSwiftBridge` turns back into an
/// `@objc` bridge.
library;

import 'dart:io';

import 'package:ffigen/ffigen.dart' as ffigen;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:swiftgen/swiftgen.dart' as swiftgen;

import '../../ir/ir.dart';
import '../c/ffigen_adapter.dart';
import '../c/objc_driver.dart';
import 'symbolgraph.dart';

export 'symbolgraph.dart' show SwiftSymbol, parseSymbolgraph;

/// Generates a `package:objective_c` binding for a Swift API and returns its
/// IR, together with the Swift and Objective-C glue that must be compiled with
/// the app.
final class SwiftDriver {
  SwiftDriver({
    required this.platform,
    required this.module,
    this.sources = const [],
    this.objcCompatibleSources = const [],
    this.objcCompatibleTypes = const {},
    this.include,
    this.assetId,
    this.preamble = '',
  }) : assert(
         sources.isNotEmpty || objcCompatibleSources.isNotEmpty,
         'nothing to bind',
       );

  final Platform platform;

  /// Swift sources that are not `@objc`, relative to the working directory of
  /// [load]. swift2objc reads these and writes the `@objc` wrapper.
  final List<String> sources;

  /// Swift sources that are already `@objc`, and so are compiled as written.
  /// A bridge from `emitSwiftBridge` belongs here.
  final List<String> objcCompatibleSources;

  /// The `@objc` classes to bind out of [objcCompatibleSources]. They have to
  /// be named: swift2objc never sees those files, so it never offers their
  /// declarations to [include], and the Objective-C header they land in also
  /// declares the whole of Foundation.
  final Set<String> objcCompatibleTypes;

  /// Name of the Swift module the sources and the generated wrapper are
  /// compiled into. The binding looks Swift symbols up under this name, so it
  /// has to match the plugin or framework that ships them.
  final String module;

  /// Pull list by Swift name (`Greeter`, `greet`); `null` binds everything in
  /// [sources]. It selects Swift declarations only: the Objective-C header
  /// `swiftc` emits imports Foundation, so the plain C declarations reachable
  /// from it are never bound on purpose, and the types a bound signature
  /// actually names come in transitively.
  final bool Function(String swiftName)? include;

  /// Asset id for `@DefaultAsset`; `null` resolves symbols against the
  /// process, which is what a linked Swift module needs.
  final String? assetId;

  /// Text placed above ffigen's own header (license, ignores).
  final String preamble;

  /// Writes the Dart binding to [output], the Objective-C glue to [objcOutput]
  /// (default: `<output>.m`) and, when [sources] is not empty, the generated
  /// `@objc` Swift wrapper to [wrapperOutput] (default: `<module>.g.swift`
  /// beside the binding). Paths are relative to [workingDirectory].
  Future<List<Decl>> load({
    required String workingDirectory,
    required String output,
    String? objcOutput,
    String? wrapperOutput,
    swiftgen.Target? target,
    Logger? logger,
  }) async {
    File file(String path) =>
        File(p.join(workingDirectory, path))
          ..parent.createSync(recursive: true);
    Uri uri(String path) => Uri.file(p.join(workingDirectory, path));
    final out = file(output);
    final glue = file(objcOutput ?? '$output.m');
    final wrapper = file(
      wrapperOutput ?? p.join(p.dirname(output), '$module.g.swift'),
    );

    // Every Swift declaration swiftgen offers, whether or not it is pulled.
    final offered = <String, String>{};
    final unparsed = <String>[];
    final log = logger ?? stderrFfigenLogger();
    final subscription = log.onRecord.listen((r) {
      if (r.level >= Level.SEVERE) unparsed.add(r.message);
    });

    final symbols = <String, CSymbol>{};
    final objc = <String, ObjcSymbol>{};
    // swiftgen deletes a directory it creates itself, and the symbol graph
    // that describes the dropped declarations is written into it.
    final temp = Directory.systemTemp.createTempSync('bindsmith_swiftgen_');
    const swift = swiftgen.SwiftFileInput(files: []);
    try {
      await swiftgen.SwiftGenerator(
        target: target ?? await _target(),
        inputs: [
          if (sources.isNotEmpty)
            swiftgen.SwiftFileInput(files: [for (final s in sources) uri(s)]),
          if (objcCompatibleSources.isNotEmpty)
            swiftgen.ObjCCompatibleSwiftFileInput(
              files: [for (final s in objcCompatibleSources) uri(s)],
            ),
        ],
        include: (d) {
          if (!(include?.call(d.name) ?? true)) return false;
          offered[d.name] = d.id;
          return true;
        },
        output: swiftgen.Output(
          module: module,
          dartFile: Uri.file(out.absolute.path),
          objectiveCFile: Uri.file(glue.absolute.path),
          swiftWrapperFile: sources.isEmpty
              ? null
              : swiftgen.SwiftWrapperFile(
                  path: Uri.file(wrapper.absolute.path),
                  // swift2objc puts its own line break after the preamble.
                  preamble: bindsmithHeader.trimRight(),
                ),
          preamble: '$bindsmithHeader$preamble',
          assetId: assetId,
        ),
        ffigen: swiftgen.FfiGeneratorOptions(
          visitors: [
            // The generated header imports Foundation, so binding C
            // declarations by name would bind the SDK. Nothing is pulled;
            // ffigen still brings in what a bound signature refers to.
            cRecorder((_) => false, symbols),
            _recorder(offered, objc),
          ],
        ),
      ).generate(logger: log, tempDirectory: temp.uri);

      // ffigen points the glue at the header `swiftc` emitted into the
      // temporary directory. What ships is the module's own generated header,
      // which Xcode writes as `<Module>-Swift.h`; rewriting the import makes
      // the output both shippable and independent of where the temporary
      // directory landed. ffigen's `preamble` reaches only the Dart file, so
      // the glue gets the header here.
      if (glue.existsSync()) {
        glue.writeAsStringSync(
          bindsmithHeader +
              glue.readAsStringSync().replaceAll(
                RegExp('#import "[^"]*${RegExp.escape(module)}\\.h"'),
                '#import "$module-Swift.h"',
              ),
        );
      }

      final graph = File(
        p.join(temp.path, '${swift.tempModuleName}.symbols.json'),
      );
      return swiftToIr(
        out.readAsStringSync(),
        platform: platform,
        symbols: symbols,
        objc: objc,
        offered: offered,
        graph: graph.existsSync()
            ? parseSymbolgraph(graph.readAsStringSync())
            : const {},
        unparsed: unparsed,
        loc: sources.length == 1 ? SourceLoc(sources.single) : null,
      );
    } finally {
      await subscription.cancel();
      temp.deleteSync(recursive: true);
    }
  }

  Future<swiftgen.Target> _target() => platform == Platform.ios
      ? swiftgen.Target.iOSArm64Latest()
      : swiftgen.Target.host();

  /// Binds exactly the Objective-C classes the Swift API turned into: the
  /// wrapper swift2objc generated, the `@objc` declaration itself, or a named
  /// bridge.
  ffigen.Visitor _recorder(
    Map<String, String> offered,
    Map<String, ObjcSymbol> into,
  ) {
    bool wanted(String objcName) =>
        offered.containsKey(objcName) ||
        offered.containsKey(_swiftName(objcName)) ||
        objcCompatibleTypes.contains(objcName);
    ObjcSymbol record(ObjcSymbol s, List<ffigen.ObjCMethod> methods) {
      for (final m in methods) {
        s.selectors[m.isPropertySetter ? '${m.name}=' : m.name] = m.selector;
      }
      return s;
    }

    return ffigen.Visitor(
      objCInterface: (i) {
        i.isIncluded = wanted(i.originalName);
        into[i.name] = record(ObjcSymbol(i.originalName), i.methods);
      },
      objCProtocol: (q) {
        q.isIncluded = wanted(q.originalName);
        into[q.name] = record(ObjcSymbol(q.originalName), q.methods);
      },
    );
  }
}

/// Lifts a generated Swift binding into IR: everything [objcToIr] finds, plus
/// the Swift declarations that did not make it, described by [graph] and
/// carrying a `dropped` marker. Pure: no I/O, no swiftgen.
List<Decl> swiftToIr(
  String binding, {
  required Platform platform,
  Map<String, CSymbol> symbols = const {},
  Map<String, ObjcSymbol> objc = const {},
  Map<String, String> offered = const {},
  Map<String, SwiftSymbol> graph = const {},
  List<String> unparsed = const [],
  SourceLoc? loc,
}) {
  // swift2objc writes no comments into its wrapper, so the header ffigen
  // reads has none; the Swift ones are still in the symbol graph.
  final symbolsByObjc = {
    for (final s in graph.values)
      if (s.owner case final owner?) '$owner.${_objcName(s)}': s,
  };
  final swiftDocs = <String, String>{
    for (final s in graph.values)
      if (s.docs case final docs?)
        if (s.isType)
          if (splitSwiftDocs(docs, paramNames: const {}).memberDocs
              case final member?)
            s.name: member
          else if (s.owner case final owner?)
            if (splitSwiftDocs(
                  docs,
                  paramNames: {for (final p in s.params) p.name},
                ).memberDocs
                case final member?)
              '$owner.${_objcName(s)}': member,
  };
  final decls = [
    for (final d in objcToIr(
      binding,
      platform: platform,
      symbols: symbols,
      objc: objc,
      loc: loc,
    ))
      d is TypeDecl ? _withDocs(d, swiftDocs, symbolsByObjc) : d,
  ];
  final types = {
    for (final d in decls) ...[d.name, _swiftName(d.name)],
  };
  // A Swift type can arrive as more than one Objective-C class: swift2objc's
  // wrapper and a generated bridge both stand for `Greeter`.
  final members = <String, Set<String>>{};
  for (final d in decls) {
    if (d is TypeDecl) {
      (members[_swiftName(d.name)] ??= {}).addAll(d.members.map((m) => m.name));
    }
  }
  // A Swift argument label becomes part of the selector, so `greet(name:)`
  // arrives as `greetWithName`; `init(prefix:)` as `initWithPrefix`.
  bool matches(Set<String> names, String swiftName) =>
      names.contains(swiftName) ||
      names.any((n) => n.startsWith('${swiftName}With'));
  // A member is looked for on its own type: every class has an `init`, so an
  // unscoped search would call every dropped initializer bound.
  bool isBound(SwiftSymbol? symbol, String name) => switch (symbol) {
    null => matches(types, name) || members.values.any((m) => matches(m, name)),
    SwiftSymbol(isType: true) => matches(types, symbol.name),
    SwiftSymbol(owner: final owner?) => matches(
      members[owner] ?? const {},
      symbol.baseName,
    ),
    _ => matches(types, symbol.baseName),
  };

  // Reasons per Swift symbol: swift2objc walks the symbol graph more than
  // once, so one declaration can be reported several times.
  final lost = <SwiftSymbol, List<String>>{};
  final unattributed = <String>[];
  for (final MapEntry(key: name, value: usr) in offered.entries) {
    final symbol = graph[usr];
    if (isBound(symbol, name)) continue;
    final reason =
        'swift2objc accepted `$name` but nothing reached the binding; an '
        '@objc wrapper has to expose it';
    if (symbol == null) {
      unattributed.add(reason);
    } else {
      (lost[symbol] ??= []).add(reason);
    }
  }
  for (final message in {...unparsed}) {
    final symbol = _blame(message, graph);
    if (symbol == null) {
      unattributed.add(message);
      continue;
    }
    if (isBound(symbol, symbol.baseName)) continue;
    (lost[symbol] ??= []).add(
      'swift2objc could not parse this declaration, so it is absent from the '
      '@objc wrapper: $message',
    );
  }

  return [
    ...decls,
    ..._dropped(lost, graph, platform, loc),
    if (unattributed.isNotEmpty)
      TypeDecl(
        id: 'swift2objc',
        name: 'unparsed',
        platform: platform,
        kind: TypeKind.klass,
        loc: loc,
        markers: [
          Marker.dropped(
            'swift2objc reported a declaration that is in none of the '
            'symbols it parsed: ${unattributed.join('; ')}',
          ),
        ],
      ),
  ];
}

/// [d] with the Swift documentation of what it stands for, wherever ffigen
/// had none.
TypeDecl _withDocs(
  TypeDecl d,
  Map<String, String> docs,
  Map<String, SwiftSymbol> symbols,
) {
  final owner = _swiftName(d.name);
  return d.copyWith(
    docs: d.docs ?? docs[owner],
    members: [
      for (final m in d.members)
        _enrichMember(m, docs['$owner.${m.name}'], symbols['$owner.${m.name}']),
    ],
  );
}

Member _enrichMember(Member m, String? swiftDocs, SwiftSymbol? symbol) {
  final split = symbol?.docs == null
      ? null
      : splitSwiftDocs(
          symbol!.docs,
          paramNames: {for (final q in symbol.params) q.name},
        );
  return m.copyWith(
    docs: m.docs ?? swiftDocs ?? split?.memberDocs,
    params: [
      for (final (i, p) in m.params.indexed)
        Param(
          p.name,
          p.type,
          optional: p.optional,
          named: p.named,
          docs:
              p.docs ??
              (symbol != null && i < symbol.params.length
                  ? split?.paramDocs[symbol.params[i].name]
                  : null),
        ),
    ],
  );
}

/// The name ffigen gives the member swift2objc writes for [s]: the first
/// argument label joins the base name, so `greet(name:)` is `greetWithName`.
String _objcName(SwiftSymbol s) => switch (s.params.firstOrNull?.label) {
  null => s.baseName,
  final label =>
    '${s.baseName}With${label[0].toUpperCase()}${label.substring(1)}',
};

/// Groups the lost declarations under the Swift type that owns them, so that a
/// bridge emitter sees `class Greeter` together with the members it has to
/// re-expose.
List<Decl> _dropped(
  Map<SwiftSymbol, List<String>> lost,
  Map<String, SwiftSymbol> graph,
  Platform platform,
  SourceLoc? loc,
) {
  final owners = <String, SwiftSymbol>{
    for (final s in graph.values)
      if (s.isType) s.name: s,
  };
  final members = <String, List<Member>>{};
  final types = <String, List<String>>{};
  final free = <Decl>[];
  for (final MapEntry(key: symbol, value: reasons) in lost.entries) {
    final markers = [Marker.dropped(reasons.join('; '))];
    if (symbol.isType) {
      (types[symbol.name] ??= []).addAll(reasons);
    } else if (symbol.owner case final owner?) {
      (members[owner] ??= []).addAll(_members(symbol, markers));
    } else {
      free.add(
        FunctionDecl(
          id: symbol.usr,
          name: symbol.baseName,
          platform: platform,
          params: _params(symbol),
          returns: TypeRef(symbol.returns ?? 'Void'),
          loc: loc,
          docs: symbol.docs,
          markers: markers,
        ),
      );
    }
  }
  return [
    for (final name in {...types.keys, ...members.keys})
      TypeDecl(
        id: owners[name]?.usr ?? name,
        name: name,
        platform: platform,
        kind: _kind(owners[name]?.kind),
        typeParams: owners[name]?.typeParams ?? const [],
        members: members[name] ?? const [],
        loc: loc,
        docs: owners[name]?.docs,
        markers: [
          if (types[name] case final reasons?)
            Marker.dropped(reasons.join('; ')),
        ],
      ),
    ...free,
  ];
}

List<Member> _members(SwiftSymbol s, List<Marker> markers) {
  final kind = switch (s.kind) {
    'swift.init' => MemberKind.constructor,
    'swift.property' || 'swift.type.property' => MemberKind.property,
    _ => MemberKind.method,
  };
  return [
    Member(
      kind == MemberKind.constructor ? '' : s.baseName,
      kind: kind,
      params: _params(s),
      returns: TypeRef(
        s.returns ?? (kind == MemberKind.property ? _propertyType(s) : 'Void'),
      ),
      // Objective-C has no `await`; a bridge has to hand the result back on
      // a completion block.
      async: s.declaration.contains(' async ') ? Async.future : Async.none,
      isStatic: s.isStatic,
      native: s.declaration,
      docs: splitSwiftDocs(
        s.docs,
        paramNames: {for (final q in s.params) q.name},
      ).memberDocs,
      markers: markers,
    ),
    if (s.isSettable)
      Member(
        s.baseName,
        kind: MemberKind.setter,
        params: [Param('value', TypeRef(_propertyType(s)))],
        returns: const TypeRef('Void'),
        isStatic: s.isStatic,
        native: s.declaration,
        markers: markers,
      ),
  ];
}

/// The argument label is what a call site writes, so it is the parameter
/// name the IR keeps; `_` leaves the parameter positional.
List<Param> _params(SwiftSymbol s) {
  final split = splitSwiftDocs(
    s.docs,
    paramNames: {for (final q in s.params) q.name},
  );
  return [
    for (final q in s.params)
      Param(
        q.label ?? q.name,
        TypeRef(q.type),
        named: q.label != null,
        docs: split.paramDocs[q.name],
      ),
  ];
}

/// `var level: Int` / `var count: Int { get }` → `Int`.
String _propertyType(SwiftSymbol s) {
  final text = s.declaration.split(':').skip(1).join(':');
  return text.split('{').first.trim();
}

TypeKind _kind(String? swiftKind) => switch (swiftKind) {
  'swift.struct' => TypeKind.struct,
  'swift.enum' => TypeKind.enumeration,
  'swift.protocol' => TypeKind.interface,
  _ => TypeKind.klass,
};

/// swift2objc points at the symbol graph it was reading: `symbols/5/…` is the
/// fifth declaration in it. Failing that, the fragments name the declaration.
SwiftSymbol? _blame(String message, Map<String, SwiftSymbol> graph) {
  final index = RegExp(r'symbols/(\d+)/').firstMatch(message)?.group(1);
  if (index != null) {
    final at = graph.values.elementAtOrNull(int.parse(index));
    if (at != null) return at;
  }
  final name = RegExp(r'"kind":"identifier","spelling":"([^"]+)"')
      .firstMatch(message)
      ?.group(1);
  if (name == null) return null;
  for (final s in graph.values) {
    if (s.baseName == name) return s;
  }
  return null;
}

/// The Swift name behind a generated Objective-C class: `GreeterWrapper` is
/// what swift2objc calls its wrapper, `GreeterBridge` what `emitSwiftBridge`
/// calls the class that carries the members swift2objc left out.
String _swiftName(String name) {
  for (final suffix in const ['Wrapper', 'Bridge']) {
    if (name.length > suffix.length && name.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}
