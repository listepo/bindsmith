/// The Swift symbol graph, read as the record of what the Swift source says.
///
/// `swiftc -emit-symbol-graph` writes it, swift2objc parses it, and its
/// diagnostics point back into it by index (`symbols/5/declarationFragments`).
/// swift2objc's own AST is not public beyond a declaration's name and id, so
/// this is where bindsmith recovers how a dropped declaration is written: the
/// diagnostic says *that* something was lost, the symbol graph says *what*.
///
/// Only the fields a bridge needs are read. The format is Apple's, documented
/// with the SymbolKit package, and stable across the Swift releases this
/// project pins.
library;

import 'dart:convert';

/// One declaration in a Swift symbol graph.
final class SwiftSymbol {
  const SwiftSymbol({
    required this.usr,
    required this.path,
    required this.kind,
    required this.declaration,
    this.params = const [],
    this.returns,
    this.typeParams = const [],
    this.docs,
  });

  /// `identifier.precise`: the mangled Swift name, which is also the id
  /// swift2objc reports for a declaration it accepted.
  final String usr;

  /// `pathComponents`: `['Greeter', 'greetAll(names:)']`.
  final List<String> path;

  /// `kind.identifier`: `swift.class`, `swift.struct`, `swift.enum`,
  /// `swift.protocol`, `swift.method`, `swift.type.method`, `swift.init`,
  /// `swift.property`, `swift.type.property`.
  final String kind;

  /// The declaration as written: `func greetAll(names: [String]) -> [String]`.
  final String declaration;

  /// Argument label (`null` for `_`), parameter name and written type.
  final List<({String? label, String name, String type})> params;

  /// Written return type; `null` for `Void` and for anything that is not a
  /// function.
  final String? returns;

  /// Names of the generic parameters this declaration introduces.
  final List<String> typeParams;

  /// The `///` comment, joined with newlines.
  final String? docs;

  /// `greetAll(names:)` — the spelling swift2objc and the symbol graph use.
  String get name => path.last;

  /// `greetAll` — the spelling that appears in a diagnostic and in a call.
  String get baseName => name.split('(').first;

  /// The type this declaration belongs to, or `null` at file scope.
  String? get owner => path.length > 1 ? path[path.length - 2] : null;

  bool get isType => const {
    'swift.class',
    'swift.struct',
    'swift.enum',
    'swift.protocol',
    'swift.typealias',
  }.contains(kind);

  bool get isStatic =>
      kind == 'swift.type.method' || kind == 'swift.type.property';

  /// A `var` without a `{ get }` clause round-trips.
  bool get isSettable =>
      kind.endsWith('property') &&
      declaration.startsWith('var ') &&
      !declaration.contains('{ get }');
}

/// Parses a `*.symbols.json` file, keyed by USR. Insertion order is the order
/// swift2objc indexes by, so `symbols/5/…` in a diagnostic is the fifth entry.
Map<String, SwiftSymbol> parseSymbolgraph(String json) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  final out = <String, SwiftSymbol>{};
  for (final entry in root['symbols'] as List? ?? const []) {
    final s = entry as Map<String, dynamic>;
    final usr = (s['identifier'] as Map)['precise'] as String;
    final path = [for (final c in s['pathComponents'] as List) c as String];
    final signature = s['functionSignature'] as Map<String, dynamic>?;
    out[usr] = SwiftSymbol(
      usr: usr,
      path: path,
      kind: (s['kind'] as Map)['identifier'] as String,
      declaration: _spell(s['declarationFragments']),
      params: _params(signature, path.last),
      returns: switch (_spell(signature?['returns'])) {
        '' || '()' || 'Void' => null,
        final r => r,
      },
      typeParams: [
        for (final p
            in (s['swiftGenerics'] as Map?)?['parameters'] as List? ?? const [])
          (p as Map)['name'] as String,
      ],
      docs: _docs(s['docComment']),
    );
  }
  return out;
}

/// Declaration fragments concatenate to the source spelling.
String _spell(Object? fragments) =>
    [for (final f in fragments as List? ?? const []) (f as Map)['spelling']]
        .join();

List<({String? label, String name, String type})> _params(
  Map<String, dynamic>? signature,
  String name,
) {
  final parameters = signature?['parameters'] as List? ?? const [];
  // `greetAll(names:)` carries the argument labels; `_` means the call site
  // passes the value positionally.
  final labels = RegExp(r'\(([^)]*)\)').firstMatch(name)?.group(1) ?? '';
  final split = labels.split(':').where((l) => l.isNotEmpty).toList();
  return [
    for (final (i, p) in parameters.indexed)
      (
        label: split.elementAtOrNull(i) == '_'
            ? null
            : split.elementAtOrNull(i),
        name: (p as Map)['name'] as String,
        // `names: [String]` — the label is everything up to the first colon.
        type: _spell(p['declarationFragments'])
            .split(':')
            .skip(1)
            .join(':')
            .trim(),
      ),
  ];
}

/// Splits Swift doc-comment lines into member prose and per-parameter docs.
///
/// `- Parameter name: …` and `- Parameters:` list items go to [paramDocs],
/// keyed by the Swift parameter's internal name. `- Returns:` and `- Throws:`
/// stay in [memberDocs] as `Returns …` / `Throws …`.
({String? memberDocs, Map<String, String> paramDocs}) splitSwiftDocs(
  String? docs, {
  required Set<String> paramNames,
}) {
  if (docs == null || docs.isEmpty) {
    return (memberDocs: docs, paramDocs: const {});
  }
  final paramDocs = <String, String>{};
  final kept = <String>[];
  var inParameters = false;
  final parameterLine = RegExp(r'^- Parameter (\w+):\s*(.*)$');
  final listParam = RegExp(r'^\s*-\s*(\w+):\s*(.*)$');
  final returnsLine = RegExp(r'^- Returns:\s*(.*)$');
  final throwsLine = RegExp(r'^- Throws:\s*(.*)$');
  for (final line in docs.split('\n')) {
    final trimmed = line.trimRight();
    if (parameterLine.matchAsPrefix(trimmed) case final m?) {
      inParameters = false;
      final name = m.group(1)!;
      if (paramNames.contains(name)) {
        paramDocs[name] = m.group(2)!.trim();
        continue;
      }
    } else if (trimmed == '- Parameters:') {
      inParameters = true;
      continue;
    } else if (inParameters) {
      if (listParam.matchAsPrefix(trimmed) case final m?) {
        final name = m.group(1)!;
        if (paramNames.contains(name)) {
          paramDocs[name] = m.group(2)!.trim();
          continue;
        }
      }
      inParameters = false;
    } else {
      inParameters = false;
    }
    if (returnsLine.matchAsPrefix(trimmed) case final m?) {
      kept.add('Returns ${m.group(1)!.trim()}');
      continue;
    }
    if (throwsLine.matchAsPrefix(trimmed) case final m?) {
      kept.add('Throws ${m.group(1)!.trim()}');
      continue;
    }
    kept.add(trimmed);
  }
  final member = kept.join('\n').trim();
  return (memberDocs: member.isEmpty ? null : member, paramDocs: paramDocs);
}

String? _docs(Object? comment) {
  final lines = (comment as Map?)?['lines'] as List?;
  if (lines == null || lines.isEmpty) return null;
  return [for (final l in lines) (l as Map)['text'] as String].join('\n');
}
