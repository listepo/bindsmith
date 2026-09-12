/// `.d.ts` driver (plan P4-2).
///
/// Runs the TypeScript sidecar (`tool/ts_sidecar/index.mjs`, TypeScript
/// Compiler API) and maps its JSON model of exported declarations to IR. The
/// mapping is a pure function, [dtsToIr], so it is unit-tested without node;
/// [DtsDriver.load] only adds the process boundary.
///
/// Mapping rules (facade types; `native` keeps the TypeScript spelling):
///
/// | TypeScript                    | IR                                       |
/// |-------------------------------|------------------------------------------|
/// | string, number, boolean       | String, num, bool                        |
/// | void, undefined, never        | void                                     |
/// | any, unknown                  | JSAny?                                   |
/// | object, inline `{...}`        | JSObject (inline types get a verify)     |
/// | `T[]`, `Array<T>`             | `List<T>`                                |
/// | `Promise<T>` (return position)| payload T with `Async.future`            |
/// | `'a' | 'b'`                   | String, values listed in the docs        |
/// | `X | null | undefined`        | `X?`                                     |
/// | `(x: T) => R`                 | JSFunction, signature in `args`          |
/// | enum E                        | E is dropped; references use its values  |
/// | type parameter T              | JSAny? with a verify marker              |
///
/// Overloads are bound as `name`, `name$2`, … that all point at the same JS
/// member through [Member.native]. Writable properties become a `property`
/// plus a `setter`. An interface without methods gets an object-literal
/// constructor with named parameters.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../ir/ir.dart';

final class DtsDriver {
  DtsDriver({required this.sidecarDir, this.node = 'node'});

  /// Directory holding `index.mjs` and its installed `node_modules`.
  final String sidecarDir;

  /// The node executable.
  final String node;

  /// The sidecar shipped inside the bindsmith package.
  static Future<String> bundledSidecarDir() async {
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:bindsmith/bindsmith.dart'),
    );
    if (lib == null) throw StateError('package:bindsmith cannot be located');
    final root = p.dirname(p.dirname(lib.toFilePath()));
    return p.join(root, 'tool', 'ts_sidecar');
  }

  /// Extracts [files] (paths relative to [workingDirectory]) and maps them to
  /// IR. Throws a [ProcessException] when the sidecar fails.
  Future<List<Decl>> load(
    List<String> files, {
    required String workingDirectory,
  }) async {
    final args = [p.join(sidecarDir, 'index.mjs'), ...files];
    final result = await Process.run(
      node,
      args,
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        node,
        args,
        (result.stderr as String).trim(),
        result.exitCode,
      );
    }
    return dtsToIr(jsonDecode(result.stdout as String) as Map<String, Object?>);
  }
}

/// Maps the sidecar's JSON model to IR. Pure.
List<Decl> dtsToIr(Map<String, Object?> model) {
  final version = model['version'];
  if (version != 1) {
    throw FormatException(
      'sidecar model version $version is not supported; expected 1. '
      'Update bindsmith or the sidecar together.',
    );
  }
  final raw = (model['decls'] as List<Object?>).cast<Map<String, Object?>>();
  final scope = _Scope(raw);
  return [for (final d in raw) _decl(d, scope)];
}

// ---------------------------------------------------------------------------
// Scope: what the other declarations of the file are

final class _Scope {
  _Scope(List<Map<String, Object?>> decls) {
    for (final d in decls) {
      final name = d['name'] as String;
      switch (d['kind']) {
        case 'class' || 'interface':
          types.add(name);
        case 'enum':
          enums[name] = _enumUnderlying(d);
        case 'typeAlias':
          final type = d['type'] as Map<String, Object?>;
          if (type['k'] == 'object') {
            types.add(name);
          } else {
            aliases[name] = type;
          }
      }
    }
  }

  /// TypeScript names of classes, interfaces and object-type aliases.
  final types = <String>{};

  /// Enum name → underlying primitive type.
  final enums = <String, TypeRef>{};

  /// Alias name → aliased type (non-object aliases only).
  final aliases = <String, Map<String, Object?>>{};

  String dartName(String tsName) => _dartName(tsName);
}

TypeRef _enumUnderlying(Map<String, Object?> d) {
  final values = [
    for (final m
        in (d['members'] as List<Object?>).cast<Map<String, Object?>>())
      m['value'],
  ];
  return values.any((v) => v is String)
      ? const TypeRef('String')
      : const TypeRef('num');
}

/// `utils.shout` → `utilsShout`, `ns.Type` → `NsType`, `default` → `default$`.
String _dartName(String tsName) {
  final parts = tsName.split('.').where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return r'$';
  final last = parts.last;
  final buffer = StringBuffer(parts.first);
  for (final part in parts.skip(1)) {
    buffer.write(_capitalize(part));
  }
  var name = buffer.toString();
  if (parts.length > 1 && last[0].toUpperCase() == last[0]) {
    name = _capitalize(name);
  }
  name = name.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), r'$');
  if (RegExp(r'^[0-9]').hasMatch(name)) name = '\$$name';
  return _reserved.contains(name) ? '$name\$' : name;
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

const _reserved = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default',
  'do', 'else', 'enum', 'extends', 'false', 'final', 'finally', 'for', 'if',
  'in', 'is', 'new', 'null', 'rethrow', 'return', 'super', 'switch', 'this',
  'throw', 'true', 'try', 'var', 'void', 'while', 'with', 'async', 'await',
  'yield', 'dynamic', 'Function', 'Object', 'Null', 'Never', //
};

// ---------------------------------------------------------------------------
// Declarations

/// Markers and doc notes collected while mapping one declaration or member.
final class _Notes {
  final markers = <Marker>[];
  final docs = <String>[];

  void verify(String reason) => markers.add(Marker.verify(reason));
}

SourceLoc? _loc(Map<String, Object?> d) => d['file'] == null
    ? null
    : SourceLoc(d['file'] as String, d['line'] as int?);

String? _docs(String? docs, List<String> notes) {
  if (docs == null && notes.isEmpty) return null;
  return [?docs, ...notes].join('\n');
}

/// A sidecar node's JSDoc as Dart documentation: `{@link X}` becomes a
/// dartdoc reference, `@param` and `@returns` become prose, an `@example` a
/// fenced block, and any other tag with text stays as written. `@deprecated`
/// and `@since` are [_availability] instead.
String? _jsdoc(Map<String, Object?> node, {Set<String> paramNames = const {}}) {
  final parts = [
    if (node['docs'] case final String docs) docs,
    for (final t in _tags(node)) ?_tag(t, paramNames: paramNames),
  ];
  if (parts.isEmpty) return null;
  return parts.join('\n\n').replaceAllMapped(_link, _dartLink);
}

List<Map<String, Object?>> _tags(Map<String, Object?> node) =>
    ((node['tags'] as List<Object?>?) ?? const []).cast<Map<String, Object?>>();

String? _tag(Map<String, Object?> t, {Set<String> paramNames = const {}}) {
  final text = t['text'] as String? ?? '';
  final name = t['name'] as String?;
  if (t['tag'] == 'param' &&
      name != null &&
      !name.contains('.') &&
      paramNames.contains(_dartName(name))) {
    return null;
  }
  return switch (t['tag']) {
    'deprecated' || 'since' => null,
    'param' => '`${t['name']}`: $text'.trimRight(),
    'returns' || 'return' => 'Returns $text',
    'example' => '```ts\n$text\n```',
    _ when text.isEmpty => null,
    final tag => '@$tag $text',
  };
}

Map<String, String> _paramDocsFromTags(
  List<Map<String, Object?>> tags,
  Set<String> paramNames,
) {
  final out = <String, String>{};
  for (final t in tags) {
    if (t['tag'] != 'param') continue;
    final raw = t['name'] as String?;
    if (raw == null || raw.contains('.')) continue;
    final name = _dartName(raw);
    if (!paramNames.contains(name)) continue;
    var text = (t['text'] as String? ?? '').trim();
    if (text.startsWith('- ')) text = text.substring(2);
    out[name] = text;
  }
  return out;
}

final _link = RegExp(r'\{@link(?:code|plain)?\s+([^\s|}]+)\s*\|?\s*([^}]*)\}');

/// `{@link Greeter}` → `[Greeter]`, `{@link Greeter.greet the greeting}` →
/// `the greeting ([Greeter.greet])`, and a URL → a markdown link.
String _dartLink(Match m) {
  final target = m[1]!;
  final label = m[2]!.trim();
  if (target.contains('://')) {
    return '[${label.isEmpty ? target : label}]($target)';
  }
  final ref = '[${target.replaceAll('#', '.')}]';
  return label.isEmpty ? ref : '$label ($ref)';
}

/// `@deprecated` and `@since`, which Dart writes as an annotation and an
/// "Available since" line rather than as prose.
Availability? _availability(Map<String, Object?> node) {
  final tags = {
    for (final t in _tags(node)) t['tag']: t['text'] as String? ?? '',
  };
  final deprecated = tags['deprecated'];
  final since = tags['since'] ?? '';
  if (deprecated == null && since.isEmpty) return null;
  return Availability(
    since: since.isEmpty ? null : since,
    // `@Deprecated` needs a message, and a bare `@deprecated` has none.
    deprecated: deprecated == null || deprecated.isNotEmpty
        ? deprecated
        : 'deprecated',
  );
}

Decl _decl(Map<String, Object?> d, _Scope s) {
  final ts = d['name'] as String;
  final name = s.dartName(ts);
  final loc = _loc(d);
  final docs = _jsdoc(d);
  final availability = _availability(d);
  switch (d['kind']) {
    case 'class':
      return _typeDecl(d, s, ts: ts, name: name, kind: TypeKind.jsObject);
    case 'interface':
      return _typeDecl(d, s, kind: TypeKind.interface, ts: ts, name: name);
    case 'function':
      final notes = _Notes();
      final typeParams = _typeParamNames(d['typeParams']);
      if (typeParams.isNotEmpty) {
        notes.verify(
          'generic function <${typeParams.join(', ')}>; type parameters are '
          'bound as JSAny?',
        );
      }
      final sig = _signature(d, s, notes, typeParams, self: null);
      return FunctionDecl(
        id: ts,
        name: name,
        platform: Platform.web,
        params: sig.params,
        returns: sig.returns,
        async: sig.async,
        loc: loc,
        docs: _docs(
          _jsdoc(d, paramNames: {for (final q in sig.params) q.name}),
          notes.docs,
        ),
        availability: availability,
        markers: notes.markers,
      );
    case 'variable':
      final notes = _Notes();
      final type = _type(d['type'], s, notes, const {}, self: null);
      return VariableDecl(
        id: ts,
        name: name,
        platform: Platform.web,
        type: type,
        isConst: d['isConst'] as bool? ?? false,
        loc: loc,
        docs: _docs(docs, notes.docs),
        availability: availability,
        markers: notes.markers,
      );
    case 'enum':
      final underlying = s.enums[ts]!;
      final members = (d['members'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final values = [
        for (final m in members)
          m['value'] == null ? m['name'] as String : _literal(m['value']),
      ];
      return TypeDecl(
        id: ts,
        name: name,
        platform: Platform.web,
        kind: TypeKind.enumeration,
        members: [
          for (final m in members)
            Member(
              _dartName(m['name'] as String),
              kind: MemberKind.constant,
              returns: underlying,
              native: m['name'] as String,
              value: m['value'] == null ? null : _literal(m['value']),
              docs: _jsdoc(m),
              availability: _availability(m),
            ),
        ],
        loc: loc,
        docs: docs,
        availability: availability,
        markers: [
          Marker.dropped(
            'TypeScript enum; parameters of this type are bound as '
            '${underlying.name} and accept ${values.join(', ')}',
          ),
        ],
      );
    case 'typeAlias':
      final type = d['type'] as Map<String, Object?>;
      if (type['k'] == 'object') {
        return _typeDecl(
          {...d, 'members': type['members']},
          s,
          ts: ts,
          name: name,
          kind: TypeKind.interface,
        );
      }
      final notes = _Notes();
      final target = _type(
        type,
        s,
        notes,
        _typeParamNames(d['typeParams']),
        self: null,
      );
      return TypeDecl(
        id: ts,
        name: name,
        platform: Platform.web,
        kind: TypeKind.typedef,
        loc: loc,
        docs: docs,
        availability: availability,
        markers: [
          Marker.dropped(
            'type alias for ${_describe(type)}; references are bound as '
            '${_show(target)}',
          ),
        ],
      );
    case 'unsupported':
      return TypeDecl(
        id: ts,
        name: name,
        platform: Platform.web,
        kind: TypeKind.opaque,
        loc: loc,
        markers: [
          Marker.dropped('unsupported TypeScript construct: ${d['text']}'),
        ],
      );
    case final other:
      throw FormatException('unknown sidecar declaration kind "$other"');
  }
}

Set<String> _typeParamNames(Object? json) => {
  for (final tp in (json as List<Object?>?) ?? const [])
    (tp as Map<String, Object?>)['name'] as String,
};

TypeDecl _typeDecl(
  Map<String, Object?> d,
  _Scope s, {
  required String ts,
  required String name,
  required TypeKind kind,
}) {
  final notes = _Notes();
  final typeParams = _typeParamNames(d['typeParams']);
  if (typeParams.isNotEmpty) {
    notes.verify(
      'generic <${typeParams.join(', ')}>; type parameters are bound as JSAny?',
    );
  }
  final supertypes = <TypeRef>[];
  for (final key in ['extends', 'implements']) {
    for (final ref in (d[key] as List<Object?>?) ?? const []) {
      final r = ref as Map<String, Object?>;
      if (r['k'] == 'ref' && s.types.contains(r['name'])) {
        supertypes.add(
          TypeRef(s.dartName(r['name'] as String), native: r['name'] as String),
        );
      }
    }
  }

  final members = <Member>[];
  final overloads = <String, int>{};
  var hasCallable = false;
  final rawMembers = ((d['members'] as List<Object?>?) ?? const [])
      .cast<Map<String, Object?>>();
  for (final m in rawMembers) {
    final mn = _Notes();
    final mKind = m['kind'] as String;
    final tsName = m['name'] as String;
    final isStatic = m['static'] as bool? ?? false;
    final docs = _jsdoc(m);
    final availability = _availability(m);
    switch (mKind) {
      case 'constructor':
        hasCallable = true;
        final n = (overloads['new'] = (overloads['new'] ?? 0) + 1);
        final sig = _signature(m, s, mn, typeParams, self: name);
        members.add(
          Member(
            n == 1 ? '' : 'new\$$n',
            kind: MemberKind.constructor,
            params: sig.params,
            docs: _docs(docs, mn.docs),
            availability: availability,
            markers: mn.markers,
          ),
        );
      case 'method':
        hasCallable = true;
        final methodParams = _typeParamNames(m['typeParams']);
        if (methodParams.isNotEmpty) {
          mn.verify(
            'generic method <${methodParams.join(', ')}>; type parameters '
            'are bound as JSAny?',
          );
        }
        if (m['optional'] == true) mn.verify('optional method; may be absent');
        final key = '${isStatic ? 'static ' : ''}$tsName';
        final n = (overloads[key] = (overloads[key] ?? 0) + 1);
        final dartName = _dartName(tsName);
        final sig = _signature(m, s, mn, {
          ...typeParams,
          ...methodParams,
        }, self: name);
        members.add(
          Member(
            n == 1 ? dartName : '$dartName\$$n',
            kind: MemberKind.method,
            params: sig.params,
            returns: sig.returns,
            async: sig.async,
            isStatic: isStatic,
            native: n == 1 && dartName == tsName ? null : tsName,
            docs: _docs(docs, mn.docs),
            availability: availability,
            markers: mn.markers,
          ),
        );
      case 'property' || 'getter':
        var type = _type(m['type'], s, mn, typeParams, self: name);
        if (m['optional'] == true) type = _nullable(type);
        final dartName = _dartName(tsName);
        final native = dartName == tsName ? null : tsName;
        members.add(
          Member(
            dartName,
            kind: MemberKind.property,
            returns: type,
            isStatic: isStatic,
            native: native,
            docs: _docs(docs, mn.docs),
            availability: availability,
            markers: mn.markers,
          ),
        );
        final writable = mKind == 'property' && m['readonly'] != true;
        if (writable) {
          members.add(
            Member(
              dartName,
              kind: MemberKind.setter,
              params: [Param('value', type)],
              isStatic: isStatic,
              native: native,
            ),
          );
        }
      case 'setter':
        final type = _type(m['type'], s, mn, typeParams, self: name);
        final dartName = _dartName(tsName);
        members.add(
          Member(
            dartName,
            kind: MemberKind.setter,
            params: [Param('value', type)],
            isStatic: isStatic,
            native: dartName == tsName ? null : tsName,
            docs: _docs(docs, mn.docs),
            availability: availability,
            markers: mn.markers,
          ),
        );
      case 'index':
        notes.verify(
          'index signature [${_describe(m['keyType'])}]: '
          '${_describe(m['type'])} is not bound',
        );
      case 'call':
        hasCallable = true;
        notes.verify(
          'call signature is not bound; the object is not callable '
          'from Dart',
        );
      default:
        notes.verify('unsupported member $tsName: ${m['text']}');
    }
  }

  if (kind == TypeKind.interface && !hasCallable) {
    // Option-bag interface: an object-literal constructor with named
    // parameters, the dart:js_interop way to build `{ prefix: 'x' }`.
    final props = [
      for (final m in members)
        if (m.kind == MemberKind.property && !m.isStatic) m,
    ];
    if (props.isNotEmpty) {
      members.insert(
        0,
        Member(
          '',
          kind: MemberKind.constructor,
          params: [
            for (final m in props)
              Param(
                m.name,
                m.returns,
                optional: m.returns.nullability == Nullability.nullable,
                named: true,
              ),
          ],
          docs: 'Creates a JavaScript object literal with these properties.',
        ),
      );
    }
  }

  return TypeDecl(
    id: ts,
    name: name,
    platform: Platform.web,
    kind: kind,
    members: members,
    supertypes: supertypes,
    typeParams: typeParams.toList(),
    loc: _loc(d),
    docs: _docs(_jsdoc(d), notes.docs),
    availability: _availability(d),
    markers: notes.markers,
  );
}

// ---------------------------------------------------------------------------
// Signatures and types

typedef _Signature = ({List<Param> params, TypeRef returns, Async async});

_Signature _signature(
  Map<String, Object?> node,
  _Scope s,
  _Notes notes,
  Set<String> typeParams, {
  required String? self,
}) {
  var params = <Param>[];
  final used = <String>{};
  for (final raw
      in ((node['params'] as List<Object?>?) ?? const [])
          .cast<Map<String, Object?>>()) {
    var name = _dartName(raw['name'] as String);
    while (!used.add(name)) {
      name = '$name\$';
    }
    var type = _type(raw['type'], s, notes, typeParams, self: self);
    final optional = raw['optional'] as bool? ?? false;
    if (optional) type = _nullable(type);
    if (raw['rest'] == true) {
      notes.verify(
        'rest parameter ...$name is bound as a single ${_show(type)} argument',
      );
    }
    params.add(Param(name, type, optional: optional));
  }
  final paramDocs = _paramDocsFromTags(
    _tags(node),
    params.map((q) => q.name).toSet(),
  );
  if (paramDocs.isNotEmpty) {
    params = [
      for (final q in params)
        if (paramDocs[q.name] case final docs?)
          Param(
            q.name,
            q.type,
            optional: q.optional,
            named: q.named,
            docs: docs,
          )
        else
          q,
    ];
  }
  final returnsJson = node['returns'] as Map<String, Object?>?;
  if (returnsJson != null &&
      returnsJson['k'] == 'ref' &&
      returnsJson['name'] == 'Promise') {
    final args = (returnsJson['args'] as List<Object?>?) ?? const [];
    final payload = args.isEmpty
        ? TypeRef.void_
        : _type(args.first, s, notes, typeParams, self: self);
    return (params: params, returns: payload, async: Async.future);
  }
  return (
    params: params,
    returns: _type(returnsJson, s, notes, typeParams, self: self),
    async: Async.none,
  );
}

TypeRef _nullable(TypeRef t) =>
    t.name == 'void' ? t : t.copyWith(nullability: Nullability.nullable);

const _jsAny = TypeRef('JSAny', nullability: Nullability.nullable);

TypeRef _type(
  Object? json,
  _Scope s,
  _Notes notes,
  Set<String> typeParams, {
  required String? self,
}) {
  if (json == null) return _jsAny;
  final t = json as Map<String, Object?>;
  switch (t['k']) {
    case 'keyword':
      return switch (t['name'] as String) {
        'string' => const TypeRef('String'),
        'number' => const TypeRef('num'),
        'boolean' => const TypeRef('bool'),
        'void' || 'undefined' || 'never' => TypeRef.void_,
        'object' => const TypeRef('JSObject', native: 'object'),
        'bigint' => const TypeRef('JSBigInt', native: 'bigint'),
        'symbol' => const TypeRef('JSSymbol', native: 'symbol'),
        'this' when self != null => TypeRef(self, native: 'this'),
        final other => TypeRef(
          'JSAny',
          nullability: Nullability.nullable,
          native: other,
        ),
      };
    case 'ref':
      final name = t['name'] as String;
      final args = (t['args'] as List<Object?>?) ?? const [];
      TypeRef arg(int i) => i < args.length
          ? _type(args[i], s, notes, typeParams, self: self)
          : _jsAny;
      if (typeParams.contains(name)) {
        return TypeRef(
          'JSAny',
          nullability: Nullability.nullable,
          native: name,
        );
      }
      switch (name) {
        case 'Array' || 'ReadonlyArray':
          return TypeRef('List', args: [arg(0)], native: _describe(t));
        case 'Promise':
          return TypeRef('JSPromise', args: [arg(0)], native: _describe(t));
        case 'Function':
          return const TypeRef('JSFunction', native: 'Function');
      }
      final underlying = s.enums[name];
      if (underlying != null) {
        return TypeRef(underlying.name, native: name);
      }
      final alias = s.aliases[name];
      if (alias != null) {
        final resolved = _type(alias, s, notes, typeParams, self: self);
        return TypeRef(
          resolved.name,
          args: resolved.args,
          nullability: resolved.nullability,
          native: name,
        );
      }
      if (s.types.contains(name)) {
        if (args.isNotEmpty) {
          notes.verify(
            'type arguments of ${_describe(t)} are dropped; the facade is '
            'not generic',
          );
        }
        return TypeRef(s.dartName(name), native: name);
      }
      notes.verify('unknown type ${_describe(t)} is bound as JSAny?');
      return TypeRef('JSAny', nullability: Nullability.nullable, native: name);
    case 'array':
      return TypeRef(
        'List',
        args: [_type(t['elem'], s, notes, typeParams, self: self)],
        native: _describe(t),
      );
    case 'tuple':
      notes.verify('tuple ${_describe(t)} is bound as List<JSAny?>');
      return TypeRef('List', args: const [_jsAny], native: _describe(t));
    case 'union':
      final parts = (t['types'] as List<Object?>).cast<Map<String, Object?>>();
      var nullable = false;
      final rest = <Map<String, Object?>>[];
      for (final part in parts) {
        final isNull =
            (part['k'] == 'keyword' &&
                (part['name'] == 'null' || part['name'] == 'undefined')) ||
            (part['k'] == 'literal' && part['value'] == null);
        if (isNull) {
          nullable = true;
        } else {
          rest.add(part);
        }
      }
      TypeRef done(TypeRef r) => nullable ? _nullable(r) : r;
      if (rest.isEmpty) return _jsAny;
      if (rest.length == 1) {
        return done(_type(rest.single, s, notes, typeParams, self: self));
      }
      if (rest.every((r) => r['k'] == 'literal')) {
        final values = [for (final r in rest) r['value']];
        final shown = values.map(_literal).join(', ');
        if (values.every((v) => v is String)) {
          notes.docs.add('One of: $shown.');
          return done(TypeRef('String', native: _describe(t)));
        }
        if (values.every((v) => v is num)) {
          notes.docs.add('One of: $shown.');
          return done(TypeRef('num', native: _describe(t)));
        }
        if (values.every((v) => v is bool)) {
          return done(TypeRef('bool', native: _describe(t)));
        }
      }
      notes.verify('union ${_describe(t)} is bound as JSAny?');
      return TypeRef(
        'JSAny',
        nullability: Nullability.nullable,
        native: _describe(t),
      );
    case 'intersection':
      notes.verify('intersection ${_describe(t)} is bound as JSObject');
      return TypeRef('JSObject', native: _describe(t));
    case 'literal':
      return switch (t['value']) {
        String() => TypeRef('String', native: _describe(t)),
        num() => TypeRef('num', native: _describe(t)),
        bool() => TypeRef('bool', native: _describe(t)),
        _ => _jsAny,
      };
    case 'fn':
      // `args` carries the signature: the return type first, then the
      // parameters. `JSFunction` is what the binding declares — a Dart
      // function cannot cross an `external` — and the facade reads the
      // signature back to accept a typed callback and convert it with `.toJS`.
      final params = (t['params'] as List<Object?>? ?? const [])
          .cast<Map<String, Object?>>();
      return TypeRef(
        'JSFunction',
        args: [
          _type(t['returns'], s, notes, typeParams, self: self),
          for (final param in params)
            _type(param['type'], s, notes, typeParams, self: self),
        ],
        native: _describe(t),
      );
    case 'object':
      notes.verify(
        'inline object type ${_describe(t)} is bound as JSObject; declare an '
        'interface to get typed access',
      );
      return TypeRef('JSObject', native: _describe(t));
    case 'unsupported':
      notes.verify('unsupported type ${t['text']} is bound as JSAny?');
      return TypeRef(
        'JSAny',
        nullability: Nullability.nullable,
        native: t['text'] as String?,
      );
    case final other:
      throw FormatException('unknown sidecar type kind "$other"');
  }
}

String _literal(Object? value) => value is String ? "'$value'" : '$value';

/// A TypeScript-looking rendering for messages and `native`.
String _describe(Object? json) {
  if (json == null) return 'any';
  final t = json as Map<String, Object?>;
  switch (t['k']) {
    case 'keyword':
      return t['name'] as String;
    case 'ref':
      final args = (t['args'] as List<Object?>?) ?? const [];
      final name = t['name'] as String;
      return args.isEmpty ? name : '$name<${args.map(_describe).join(', ')}>';
    case 'array':
      return '${_describe(t['elem'])}[]';
    case 'tuple':
      return '[${(t['elems'] as List<Object?>).map(_describe).join(', ')}]';
    case 'union':
      return (t['types'] as List<Object?>).map(_describe).join(' | ');
    case 'intersection':
      return (t['types'] as List<Object?>).map(_describe).join(' & ');
    case 'literal':
      return _literal(t['value']);
    case 'fn':
      final params = ((t['params'] as List<Object?>?) ?? const [])
          .cast<Map<String, Object?>>()
          .map((p) => '${p['name']}: ${_describe(p['type'])}')
          .join(', ');
      return '($params) => ${_describe(t['returns'])}';
    case 'object':
      return '{ ... }';
    default:
      return (t['text'] as String?) ?? '?';
  }
}

String _show(TypeRef t) {
  final args = t.args.isEmpty ? '' : '<${t.args.map(_show).join(', ')}>';
  return '${t.name}$args${t.nullability == Nullability.nullable ? '?' : ''}';
}
