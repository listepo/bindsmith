/// Facade synthesis (plan P6-4): one Dart API over the per-platform bindings.
///
/// Input: the IR of every configured platform after passes. Output: Dart
/// source for
///
/// * `<lib>.g.dart` — conditional export choosing the io or the web group;
/// * `<lib>_io.g.dart` — one class per type, dispatching on
///   `bindsmithPlatform` to the Android, iOS, macOS, Windows and Linux
///   bindings;
/// * `<lib>_web.g.dart` — the same classes delegating to the web binding.
///
/// Both group files declare the identical public API; that is what makes the
/// facade usable from platform-independent Dart code.
///
/// Types, functions and variables are matched across platforms by Dart-facing
/// name; members by name, kind and staticness. The first configured platform
/// gives the shape (facade signature). A shape that differs elsewhere gets a
/// `verify` marker, emitted as `@BindsmithVerify`. A symbol missing on a
/// platform follows [Unsupported]. Nothing disappears silently: every symbol
/// left out is listed in a trailer comment of the generated file.
///
/// Type conventions in the IR consumed here: [TypeRef.name] is the facade
/// (Dart core or facade type) name; [Member.returns] is the payload type and
/// [Member.async] says whether the facade wraps it in `Future`/`Stream`.
library;

import 'package:dart_style/dart_style.dart';

import '../ir/ir.dart';
import '../passes/passes.dart' show disposedBy, laidOutAs;

/// What the facade does for a symbol that a configured platform lacks.
enum Unsupported {
  /// Throws `BindsmithUnsupported` on that platform. Default.
  throw_,

  /// Returns `null` (nullable result), a completed future (`Future<void>`) or
  /// does nothing (`void`). Falls back to [throw_] for other results.
  stub,

  /// Leaves the symbol out of the facade on every platform and lists it in
  /// the trailer of the generated file.
  omit,
}

final class FacadeOptions {
  const FacadeOptions({
    required this.library,
    required this.bindings,
    this.unsupported = Unsupported.throw_,
  });

  /// Base name of the generated files: `my_sdk` → `my_sdk.g.dart`.
  final String library;

  /// Configured platforms and the import of each platform's generated binding
  /// library relative to the facade files, e.g.
  /// `{Platform.android: 'android.g.dart'}`.
  final Map<Platform, String> bindings;

  final Unsupported unsupported;
}

/// File name → formatted Dart source.
typedef FacadeFiles = Map<String, String>;

/// An enum's constants and the Dart type its values are written in.
typedef _EnumValues = ({String type, Map<String, String> values});

const _io = {
  Platform.android,
  Platform.ios,
  Platform.macos,
  Platform.windows,
  Platform.linux,
};

/// The names of the files a facade is written to; [io] and [web] are `null`
/// when no configured platform belongs to that group.
typedef FacadeNames = ({String entry, String? io, String? web});

/// What [emitFacade] calls its files for [platforms].
///
/// `bindsmith verify` reads the two group files back off disk to compare what
/// they declare, so it must not carry its own idea of what they are called —
/// and the emitter below keys its own output off this, so the two cannot
/// drift.
FacadeNames facadeFileNames(String library, Iterable<Platform> platforms) {
  final configured = platforms.toSet();
  return (
    entry: '$library.g.dart',
    io: configured.any(_io.contains) ? '${library}_io.g.dart' : null,
    web: configured.contains(Platform.web) ? '${library}_web.g.dart' : null,
  );
}

FacadeFiles emitFacade(Map<Platform, List<Decl>> ir, FacadeOptions options) {
  final platforms = [
    for (final p in Platform.values)
      if (options.bindings.containsKey(p)) p,
  ];
  if (platforms.isEmpty) {
    throw ArgumentError.value(
      options.bindings,
      'bindings',
      'at least one platform is required',
    );
  }
  final model = _merge(ir, platforms, options.unsupported);
  final io = [
    for (final p in platforms)
      if (_io.contains(p)) p,
  ];
  final names = facadeFileNames(options.library, platforms);
  return {
    names.entry: _format(
      _entry(options.library, io: names.io != null, web: names.web != null),
    ),
    ?names.io: _format(_group(model, io, options)),
    ?names.web: _format(_group(model, const [Platform.web], options)),
  };
}

// ---------------------------------------------------------------------------
// Unified model

final class _Unified<T extends Decl> {
  _Unified(this.shape);

  /// Declaration of the first platform that has the symbol.
  final T shape;
  final Map<Platform, T> impls = {};
  final List<Marker> markers = [];

  /// Members by key, for [TypeDecl] only.
  final Map<String, _Member> members = {};

  String get name => shape.name;
}

final class _Member {
  _Member(this.shape, this.shapePlatform);

  final Member shape;
  final Platform shapePlatform;
  final Map<Platform, Member> impls = {};
  final List<Marker> markers = [];
}

final class _Model {
  _Model(this.types, this.functions, this.variables, this.notEmitted);

  final List<_Unified<TypeDecl>> types;
  final List<_Unified<FunctionDecl>> functions;
  final List<_Unified<VariableDecl>> variables;
  final List<String> notEmitted;

  late final Map<String, _Unified<TypeDecl>> typeByName = {
    for (final t in types) t.name: t,
  };
}

String _sig(List<Param> params, TypeRef returns, Async async) {
  final ps = [
    for (final p in params)
      '${p.named ? '${p.name}: ' : ''}'
          '${_dartType(p.type)}${p.optional ? '?' : ''}',
  ];
  return '(${ps.join(', ')}) -> ${_facadeReturn(returns, async)}';
}

String _memberSig(Member m) => _sig(m.params, m.returns, m.async);

String _reason(List<Marker> markers) => markers
    .where((m) => m.kind == MarkerKind.dropped)
    .map((m) => m.reason)
    .join('; ');

List<Marker> _verifyOf(Platform p, List<Marker> markers) => [
  for (final m in markers)
    if (m.kind == MarkerKind.verify) Marker.verify('${p.name}: ${m.reason}'),
];

_Model _merge(
  Map<Platform, List<Decl>> ir,
  List<Platform> platforms,
  Unsupported policy,
) {
  final types = <String, _Unified<TypeDecl>>{};
  final functions = <String, _Unified<FunctionDecl>>{};
  final variables = <String, _Unified<VariableDecl>>{};
  final owner = <String, String>{}; // name → kind that claimed it first
  final notEmitted = <String>[];

  for (final p in platforms) {
    for (final decl in ir[p] ?? const <Decl>[]) {
      if (decl.isDropped) {
        notEmitted.add('${p.name} ${decl.name} — ${_reason(decl.markers)}');
        continue;
      }
      final kind = switch (decl) {
        TypeDecl() => 'type',
        FunctionDecl() => 'function',
        VariableDecl() => 'variable',
      };
      final claimed = owner.putIfAbsent(decl.name, () => kind);
      if (claimed != kind) {
        notEmitted.add(
          '${p.name} ${decl.name} — declared as a $kind but ${decl.name} is '
          'already a $claimed on another platform; rename one with a fixup',
        );
        continue;
      }
      switch (decl) {
        case TypeDecl():
          final u = types.putIfAbsent(decl.name, () => _Unified(decl));
          if (!_claim(u, decl, p)) continue;
          if (u.shape.kind != decl.kind) {
            u.markers.add(
              Marker.verify(
                'declared as ${decl.kind.name} on ${p.name} but as '
                '${u.shape.kind.name} on ${u.shape.platform.name}',
              ),
            );
          }
          if (decl.typeParams.isNotEmpty) {
            u.markers.add(
              Marker.verify(
                'generic on ${p.name} <${decl.typeParams.join(', ')}>; '
                'the facade is not generic',
              ),
            );
          }
          _mergeMembers(u, decl, p, notEmitted);
        case FunctionDecl():
          final u = functions.putIfAbsent(decl.name, () => _Unified(decl));
          if (!_claim(u, decl, p)) continue;
          final a = _sig(u.shape.params, u.shape.returns, u.shape.async);
          final b = _sig(decl.params, decl.returns, decl.async);
          if (a != b) u.markers.add(_differs(p, b, u.shape.platform, a));
        case VariableDecl():
          final u = variables.putIfAbsent(decl.name, () => _Unified(decl));
          if (!_claim(u, decl, p)) continue;
          final a = _dartType(u.shape.type);
          final b = _dartType(decl.type);
          if (a != b) u.markers.add(_differs(p, b, u.shape.platform, a));
      }
    }
  }

  if (policy == Unsupported.omit) {
    _omitMissing(types, platforms, notEmitted);
    _omitMissing(functions, platforms, notEmitted);
    _omitMissing(variables, platforms, notEmitted);
    for (final t in types.values) {
      t.members.removeWhere((key, m) {
        final missing = [
          for (final p in t.impls.keys)
            if (!m.impls.containsKey(p)) p.name,
        ];
        if (missing.isEmpty) return false;
        notEmitted.add(
          '${t.name}.${m.shape.name} — omitted: missing on '
          '${missing.join(', ')}',
        );
        return true;
      });
    }
  }

  List<_Unified<T>> sorted<T extends Decl>(Map<String, _Unified<T>> m) =>
      m.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  return _Model(
    sorted(types),
    sorted(functions),
    sorted(variables),
    notEmitted..sort(),
  );
}

bool _claim<T extends Decl>(_Unified<T> u, T decl, Platform p) {
  if (u.impls.containsKey(p)) {
    u.markers.add(
      Marker.verify(
        '${decl.name} is declared twice on ${p.name}; ${decl.id} is ignored',
      ),
    );
    return false;
  }
  u.impls[p] = decl;
  u.markers.addAll(_verifyOf(p, decl.markers));
  return true;
}

Marker _differs(Platform p, String sig, Platform shapePlatform, String shape) =>
    Marker.verify(
      'signature differs: $sig on ${p.name} vs $shape on '
      '${shapePlatform.name} (facade uses ${shapePlatform.name})',
    );

void _mergeMembers(
  _Unified<TypeDecl> u,
  TypeDecl decl,
  Platform p,
  List<String> notEmitted,
) {
  for (final m in decl.members) {
    if (m.isDropped) {
      notEmitted.add(
        '${p.name} ${decl.name}.${m.name} — ${_reason(m.markers)}',
      );
      continue;
    }
    final key = '${m.kind.name}:${m.isStatic}:${m.name}';
    final um = u.members.putIfAbsent(key, () => _Member(m, p));
    if (um.impls.containsKey(p)) {
      um.markers.add(
        Marker.verify(
          '${decl.name}.${m.name} is overloaded on ${p.name}; only the first '
          'overload is bound, rename the others with a fixup',
        ),
      );
      continue;
    }
    um.impls[p] = m;
    um.markers.addAll(_verifyOf(p, m.markers));
    final a = _memberSig(um.shape);
    final b = _memberSig(m);
    if (a != b) um.markers.add(_differs(p, b, um.shapePlatform, a));
  }
}

void _omitMissing<T extends Decl>(
  Map<String, _Unified<T>> all,
  List<Platform> platforms,
  List<String> notEmitted,
) {
  all.removeWhere((name, u) {
    final missing = [
      for (final p in platforms)
        if (!u.impls.containsKey(p)) p.name,
    ];
    if (missing.isEmpty) return false;
    notEmitted.add('$name — omitted: missing on ${missing.join(', ')}');
    return true;
  });
}

// ---------------------------------------------------------------------------
// Emission

const _header =
    '// GENERATED BY bindsmith — do not edit.\n'
    '// ignore_for_file: type=lint, unused_element, unused_import, '
    'unnecessary_cast, unnecessary_non_null_assertion\n';

String _entry(String lib, {required bool io, required bool web}) {
  final b = StringBuffer(_header);
  if (io && web) {
    b.writeln(
      "export '${lib}_io.g.dart' if (dart.library.js_interop) "
      "'${lib}_web.g.dart';",
    );
  } else if (io) {
    b.writeln("export '${lib}_io.g.dart';");
  } else {
    b.writeln("export '${lib}_web.g.dart';");
  }
  return b.toString();
}

final class _Ctx {
  _Ctx(this.model, this.group, this.policy);

  final _Model model;
  final List<Platform> group;
  final Unsupported policy;

  /// Set by the C marshalling below; decides whether the generated file
  /// imports dart:ffi and package:ffi.
  bool needsFfi = false;

  /// Arena locals the call being built needs, with the write-back each one
  /// runs afterwards. A C function taking a struct by pointer may write
  /// through it, so the copy has to be read back into the facade object; the
  /// pointer has to be named for that, which an argument expression cannot do.
  /// Filled by `_toC` and drained by [_withArena].
  final pending = <({String local, String back})>[];

  bool get single => group.length == 1;

  /// The literals of an enum every platform agrees on, with the Dart type
  /// they are written in; null when a value is missing, two platforms
  /// disagree, or the values are not all of one type. Only a valued enum can
  /// be marshalled as its underlying value.
  final _values = <String, _EnumValues?>{};

  _EnumValues? enumValues(String facadeName) =>
      _values.putIfAbsent(facadeName, () {
        final t = model.typeByName[facadeName];
        if (t == null || t.shape.kind != TypeKind.enumeration) return null;
        final values = <String, String>{};
        final types = <String>{};
        for (final impl in t.impls.values) {
          for (final m in impl.members) {
            if (m.kind != MemberKind.constant) continue;
            final value = m.value;
            if (value == null ||
                (values.containsKey(m.name) && values[m.name] != value)) {
              return null;
            }
            values[m.name] = value;
            types.add(m.returns.name);
          }
        }
        if (values.isEmpty || types.length != 1) return null;
        return (type: types.single, values: values);
      });

  /// The binding library's class name for a facade type on [p], or null when
  /// the type has no binding on that platform.
  String? bindingType(Platform p, String facadeName) {
    final decl = model.typeByName[facadeName]?.impls[p];
    return decl == null ? null : (decl.binding ?? decl.name);
  }
}

String _group(_Model model, List<Platform> group, FacadeOptions options) {
  final ctx = _Ctx(model, group, options.unsupported);
  // The body is written first: whether it marshals a C type decides whether
  // the file needs dart:ffi.
  final body = StringBuffer();
  for (final t in model.types) {
    body.writeln(_type(t, ctx));
  }
  for (final f in model.functions) {
    body.writeln(_function(f, ctx));
  }
  for (final v in model.variables) {
    body.writeln(_variable(v, ctx));
  }
  final b = StringBuffer(_header);
  // Marshalling helpers used by the call expressions below. A C type the
  // marshalling did not claim still reaches a signature spelled `ffi.…`, so
  // the prefix in the body is what decides the dart:ffi import.
  final bodyText = body.toString();
  if (bodyText.contains('ffi.')) {
    b.writeln("import 'dart:ffi' as ffi;");
  } else if (bodyText.contains('Pointer<')) {
    b.writeln("import 'dart:ffi';");
  }

  if (group.contains(Platform.web)) b.writeln("import 'dart:js_interop';");
  b.writeln("import 'package:bindsmith_runtime/bindsmith_runtime.dart';");
  if (ctx.needsFfi) b.writeln("import 'package:ffi/ffi.dart';");
  if (group.contains(Platform.android)) {
    b.writeln("import 'package:jni/jni.dart';");
  }
  if (group.contains(Platform.ios) || group.contains(Platform.macos)) {
    b.writeln("import 'package:objective_c/objective_c.dart';");
  }
  for (final p in group) {
    b.writeln("import '${options.bindings[p]}' as ${p.name};");
  }
  b
    ..writeln()
    ..write(body)
    ..writeln('T? _n<S, T>(S? v, T Function(S) f) => v == null ? null : f(v);')
    ..writeln();
  if (model.notEmitted.isNotEmpty) {
    b.writeln('// Not emitted by the facade (see `bindsmith verify`):');
    for (final line in model.notEmitted) {
      b.writeln('//   $line');
    }
  }
  return b.toString();
}

String _type(_Unified<TypeDecl> t, _Ctx ctx) {
  final b = StringBuffer();
  _docs(b, t.shape.docs, t.shape.availability, t.markers);
  if (t.shape.kind == TypeKind.enumeration) return _enum(b, t, ctx);
  final constructible = t.members.values.any(
    (m) => m.shape.kind == MemberKind.constructor,
  );
  if ((t.shape.kind == TypeKind.interface ||
          t.shape.kind == TypeKind.protocol) &&
      !constructible) {
    b.writeln(
      "@BindsmithVerify('implementing ${t.name} from Dart is not generated; "
      "only calls into existing instances')",
    );
  }
  b
    ..writeln('final class ${t.name} {')
    ..writeln('${t.name}._(this._impl);')
    ..writeln()
    ..writeln('/// The platform binding object this facade wraps.')
    ..writeln('final Object _impl;')
    ..writeln();
  final members = t.members.values.toList()
    ..sort((a, b) {
      int rank(Member m) => switch (m.kind) {
        MemberKind.constructor => 0,
        _ when m.isStatic => 1,
        _ => 2,
      };
      final r = rank(a.shape).compareTo(rank(b.shape));
      if (r != 0) return r;
      final n = a.shape.name.compareTo(b.shape.name);
      if (n != 0) return n;
      // Getter before setter of the same name; sort is not stable, and the
      // two carry different kinds (`property` on web, `field` over C).
      int slot(Member m) => m.kind == MemberKind.setter ? 1 : 0;
      return slot(a.shape).compareTo(slot(b.shape));
    });
  for (final m in members) {
    b.writeln(_member(t, m, ctx));
  }
  b.writeln('}');
  return b.toString();
}

String _enum(StringBuffer b, _Unified<TypeDecl> t, _Ctx ctx) {
  final values = <String>[];
  // A value's documentation comes from the first platform that has any.
  final docs = <String, String>{};
  for (final impl in t.impls.values) {
    for (final m in impl.members) {
      if (m.kind != MemberKind.constant) continue;
      if (!values.contains(m.name)) values.add(m.name);
      if (m.docs case final text?) docs.putIfAbsent(m.name, () => text);
    }
  }
  for (final MapEntry(key: p, value: impl) in t.impls.entries) {
    final own = {
      for (final m in impl.members)
        if (m.kind == MemberKind.constant) m.name,
    };
    if (own.length != values.length) {
      b.writeln(
        "@BindsmithVerify('${p.name} lacks enum values "
        "${values.where((v) => !own.contains(v)).join(', ')}')",
      );
    }
  }
  // The values are what the native API passes, so they are part of the API.
  final known = ctx.enumValues(t.name);
  b.writeln('enum ${t.name} {');
  for (final v in values) {
    _docs(b, docs[v], null, const []);
    b.writeln(known == null ? '$v,' : '$v(${known.values[v]}),');
  }
  if (known == null) {
    b.writeln('}');
    return b.toString();
  }
  final type = known.type;
  b
    ..writeln(';')
    ..writeln()
    ..writeln('const ${t.name}(this.value);')
    ..writeln()
    ..writeln('/// The value the native API uses for this constant.')
    ..writeln('final $type value;')
    ..writeln()
    ..writeln('/// The constant [value] stands for.')
    ..writeln('///')
    ..writeln('/// Throws [ArgumentError] for a value no constant covers: a')
    ..writeln('/// native API is free to return one, and guessing would hide')
    ..writeln('/// it.')
    ..writeln('static ${t.name} fromValue($type value) => values.firstWhere(')
    ..writeln('(v) => v.value == value,')
    ..writeln(
      "orElse: () => throw ArgumentError.value(value, 'value', "
      "'not a ${t.name}'),",
    )
    ..writeln(');')
    ..writeln('}');
  return b.toString();
}

String _member(_Unified<TypeDecl> t, _Member m, _Ctx ctx) {
  final shape = m.shape;
  final b = StringBuffer();
  final markers = [...m.markers];
  final symbol = '${t.name}.${shape.name.isEmpty ? 'new' : shape.name}';

  // `cFacadePass` synthesized this one; the deallocator is a facade function
  // in the same file, so the forward needs no binding of its own.
  if (_disposer(shape) case final free?) {
    b
      ..writeln('/// Releases the native handle. Calling it twice is a bug,')
      ..writeln('/// and so is using this object afterwards.')
      ..writeln('void dispose() => $free(this);');
    return b.toString();
  }

  if (shape.kind == MemberKind.event) {
    markers.add(
      const Marker.verify('events are not mapped yet; use a wrapper (P7)'),
    );
    _docs(b, shape.docs, shape.availability, markers);
    b.writeln(
      'Stream<${_dartType(shape.returns)}> get ${shape.name} => '
      "throw UnimplementedError('bindsmith: $symbol');",
    );
    return b.toString();
  }

  // Build one call expression per platform of the group, collecting
  // marshalling markers as we go.
  final calls = <Platform, String>{};
  for (final p in ctx.group) {
    final impl = m.impls[p];
    final typeBinding = ctx.bindingType(p, t.name);
    if (impl == null || typeBinding == null) continue;
    calls[p] = _call(p, typeBinding, impl, shape, ctx, markers);
  }
  final missing = [
    for (final p in ctx.group)
      if (!calls.containsKey(p)) p,
  ];
  _docs(b, shape.docs, shape.availability, markers);
  _paramDocs(b, shape.params);
  if (shape.threading == Threading.main) {
    b.writeln('/// Must be called on the main thread.');
  }

  final params = _params(shape.params);
  final ret = _facadeReturn(shape.returns, shape.async);
  final isConstructor = shape.kind == MemberKind.constructor;
  // Constructors return the wrapped object even though the IR says `void`.
  final isVoid =
      !isConstructor &&
      shape.async == Async.none &&
      shape.returns.name == 'void';
  final missingExpr = _missing(
    symbol,
    shape.returns,
    shape.async,
    ctx.policy,
    statement: isVoid,
  );

  String dispatch({required bool wrap}) {
    String arm(Platform p) => wrap ? '${t.name}._(${calls[p]})' : calls[p]!;
    if (ctx.single) {
      final p = ctx.group.single;
      return calls.containsKey(p) ? arm(p) : missingExpr;
    }
    if (calls.isEmpty) return missingExpr;
    if (isVoid) {
      final sb = StringBuffer('switch (bindsmithPlatform) {');
      for (final p in calls.keys) {
        sb.writeln('case BindsmithPlatform.${p.name}: ${arm(p)};');
      }
      sb
        ..writeln('default: $missingExpr;')
        ..write('}');
      return sb.toString();
    }
    final sb = StringBuffer('switch (bindsmithPlatform) {');
    for (final p in calls.keys) {
      sb.writeln('BindsmithPlatform.${p.name} => ${arm(p)},');
    }
    sb
      ..writeln('_ => $missingExpr,')
      ..write('}');
    return sb.toString();
  }

  if (isConstructor) {
    final name = shape.name.isEmpty ? '' : '.${shape.name}';
    if (ctx.single && missing.isNotEmpty) {
      b.writeln('factory ${t.name}$name($params) => $missingExpr;');
    } else if (ctx.single) {
      b.writeln(
        'factory ${t.name}$name($params) => '
        '${t.name}._(${calls[ctx.group.single]});',
      );
    } else {
      b.writeln('factory ${t.name}$name($params) => ${dispatch(wrap: true)};');
    }
    return b.toString();
  }

  final static = shape.isStatic ? 'static ' : '';
  final head = shape.kind == MemberKind.setter
      ? '${static}set ${shape.name}($params)'
      : '$static$ret ${shape.name}($params)';
  switch (shape.kind) {
    case MemberKind.property || MemberKind.field || MemberKind.constant:
      b.writeln('$static$ret get ${shape.name} => ${dispatch(wrap: false)};');
    case MemberKind.method || MemberKind.setter when isVoid && !ctx.single:
      b.writeln('$head {${dispatch(wrap: false)}}');
    case MemberKind.method || MemberKind.setter when isVoid:
      b.writeln('$head { ${dispatch(wrap: false)}; }');
    case MemberKind.method || MemberKind.setter:
      b.writeln('$head => ${dispatch(wrap: false)};');
    case MemberKind.constructor || MemberKind.event:
      throw StateError('unreachable');
  }
  return b.toString();
}

/// True when `cFacadePass` synthesized this constructor for a dart:ffi struct,
/// which has no Dart constructor of its own.
bool _laidOut(Member m) =>
    m.kind == MemberKind.constructor &&
    m.markers.any((k) => k.reason.endsWith(laidOutAs('')));

/// The facade function a synthesized `dispose` forwards to, from the marker
/// `cFacadePass` left on it.
String? _disposer(Member m) {
  if (m.name != 'dispose') return null;
  for (final marker in m.markers) {
    final free = marker.reason.replaceFirst(disposedBy(''), '');
    if (free != marker.reason) return free;
  }
  return null;
}

/// `name: value` for named parameters, `value` otherwise.
String _args(Platform p, List<Param> params, _Ctx ctx, List<Marker> markers) =>
    [
      for (final param in params)
        '${param.named ? '${param.name}: ' : ''}'
            '${_toNative(p, param.type, param.name, ctx, markers)}',
    ].join(', ');

/// The expression calling [impl] on platform [p] and converting the result to
/// the facade type. Constructors return the raw binding object; the caller
/// wraps it.
String _call(
  Platform p,
  String typeBinding,
  Member impl,
  Member shape,
  _Ctx ctx,
  List<Marker> markers,
) {
  final ns = p.name;
  final bname = impl.binding ?? impl.name;
  if (_laidOut(shape)) {
    // A dart:ffi struct has no constructor: `Struct.create` lays one out on
    // the Dart heap, and the fields are then assigned in declaration order.
    // Nothing here allocates, so there is no arena and nothing to release.
    final fields = [
      for (final param in shape.params)
        '..${param.name} = '
            '${_toNative(p, param.type, param.name, ctx, markers)}',
    ].join();
    return '(ffi.Struct.create<$ns.$typeBinding>()$fields)';
  }
  final args = _args(p, shape.params, ctx, markers);
  final receiver = impl.isStatic
      ? '$ns.$typeBinding'
      : '(_impl as $ns.$typeBinding)';
  final target = switch (impl.kind) {
    MemberKind.constructor =>
      '$ns.$typeBinding${bname.isEmpty ? '' : '.$bname'}($args)',
    MemberKind.method => '$receiver.$bname($args)',
    MemberKind.setter => '$receiver.$bname = $args',
    _ => '$receiver.$bname',
  };
  final discard = shape.async == Async.none && shape.returns.name == 'void';
  if (impl.kind == MemberKind.constructor || impl.kind == MemberKind.setter) {
    return _allocates(ctx, args)
        ? _withArena(ctx, target, discard: impl.kind == MemberKind.setter)
        : target;
  }
  final call = _toDart(p, shape.returns, shape.async, target, ctx, markers);
  return _allocates(ctx, args) ? _withArena(ctx, call, discard: discard) : call;
}

String _function(_Unified<FunctionDecl> f, _Ctx ctx) {
  final b = StringBuffer();
  final markers = [...f.markers];
  final shape = f.shape;
  final calls = <Platform, String>{};
  final isVoid = shape.async == Async.none && shape.returns.name == 'void';
  for (final p in ctx.group) {
    final impl = f.impls[p];
    if (impl == null) continue;
    final args = _args(p, shape.params, ctx, markers);
    final call = _toDart(
      p,
      shape.returns,
      shape.async,
      '${p.name}.${impl.binding ?? impl.name}($args)',
      ctx,
      markers,
    );
    calls[p] = _allocates(ctx, args)
        ? _withArena(ctx, call, discard: isVoid)
        : call;
  }
  _docs(b, shape.docs, shape.availability, markers);
  final ret = _facadeReturn(shape.returns, shape.async);
  final missingExpr = _missing(
    shape.name,
    shape.returns,
    shape.async,
    ctx.policy,
    statement: isVoid,
  );
  final params = _params(shape.params);
  if (ctx.single) {
    final call = calls[ctx.group.single] ?? missingExpr;
    b.writeln(
      isVoid
          ? '$ret ${shape.name}($params) { $call; }'
          : '$ret ${shape.name}($params) => $call;',
    );
    return b.toString();
  }
  if (isVoid) {
    b.writeln('$ret ${shape.name}($params) { switch (bindsmithPlatform) {');
    for (final p in calls.keys) {
      b.writeln('case BindsmithPlatform.${p.name}: ${calls[p]};');
    }
    b.writeln('default: $missingExpr; } }');
    return b.toString();
  }
  b.writeln('$ret ${shape.name}($params) => switch (bindsmithPlatform) {');
  for (final p in calls.keys) {
    b.writeln('BindsmithPlatform.${p.name} => ${calls[p]},');
  }
  b.writeln('_ => $missingExpr, };');
  return b.toString();
}

String _variable(_Unified<VariableDecl> v, _Ctx ctx) {
  final b = StringBuffer();
  final shape = v.shape;
  final markers = [...v.markers];
  final values = {for (final d in v.impls.values) d.value};
  if (shape.isConst && shape.value != null && values.length == 1) {
    _docs(b, shape.docs, shape.availability, markers);
    b.writeln('const ${_dartType(shape.type)} ${shape.name} = ${shape.value};');
    return b.toString();
  }
  final calls = <Platform, String>{};
  for (final p in ctx.group) {
    final impl = v.impls[p];
    if (impl == null) continue;
    calls[p] = _toDart(
      p,
      shape.type,
      Async.none,
      '${p.name}.${impl.binding ?? impl.name}',
      ctx,
      markers,
    );
  }
  _docs(b, shape.docs, shape.availability, markers);
  final missingExpr = _missing(
    shape.name,
    shape.type,
    Async.none,
    ctx.policy,
    statement: false,
  );
  final type = _dartType(shape.type);
  if (ctx.single) {
    b.writeln(
      '$type get ${shape.name} => ${calls[ctx.group.single] ?? missingExpr};',
    );
    return b.toString();
  }
  b.writeln('$type get ${shape.name} => switch (bindsmithPlatform) {');
  for (final p in calls.keys) {
    b.writeln('BindsmithPlatform.${p.name} => ${calls[p]},');
  }
  b.writeln('_ => $missingExpr, };');
  return b.toString();
}

String _missing(
  String symbol,
  TypeRef returns,
  Async async,
  Unsupported policy, {
  required bool statement,
}) {
  final throwExpr =
      'throw BindsmithUnsupported(${_str(symbol)}, bindsmithPlatform)';
  if (policy != Unsupported.stub) return throwExpr;
  if (statement) return 'return';
  if (async == Async.future && returns.name == 'void') {
    return 'Future<void>.value()';
  }
  if (async == Async.future && returns.nullability == Nullability.nullable) {
    return 'Future<${_dartType(returns)}>.value()';
  }
  if (async == Async.none && returns.nullability == Nullability.nullable) {
    return 'null';
  }
  return throwExpr;
}

// ---------------------------------------------------------------------------
// Marshalling between facade types and platform binding types

const _primitives = {'int', 'double', 'bool', 'num', 'void'};

/// dart:js_interop types that cross the web boundary unchanged.
const _jsTypes = {
  'JSAny',
  'JSObject',
  'JSFunction',
  'JSArray',
  'JSPromise',
  'JSString',
  'JSNumber',
  'JSBoolean',
  'JSBigInt',
  'JSSymbol',
  'JSArrayBuffer',
  'JSDataView',
  'JSTypedArray',
  'JSUint8Array',
  'JSExportedDartFunction',
  'JSBoxedDartObject',
};

/// `(x._impl as web.T)` for a facade type, null for anything else. Enums have
/// no binding object.
String? _unwrapFacade(Platform p, TypeRef t, String expr, _Ctx ctx) {
  final unified = ctx.model.typeByName[t.name];
  if (unified == null || unified.shape.kind == TypeKind.enumeration) {
    return null;
  }
  final binding = ctx.bindingType(p, t.name);
  if (binding == null) return null;
  final q = t.nullability == Nullability.nullable ? '?' : '';
  return '($expr$q._impl as ${p.name}.$binding$q)';
}

/// Converts the facade value [expr] of type [t] to what the binding on [p]
/// expects.
String _toNative(
  Platform p,
  TypeRef t,
  String expr,
  _Ctx ctx,
  List<Marker> markers,
) {
  final q = t.nullability == Nullability.nullable ? '?' : '';
  // The C check runs first: a facade type backed by a C binding is spelled in
  // pointers there, and `_unwrapFacade` would hand the binding the object.
  if (_toC(p, t, expr, ctx, markers) case final c?) return c;
  // `_toJs` handles facade types itself, so it comes before the lookup below.
  if (p == Platform.web) return _toJs(t, expr, ctx, markers, boxed: false);
  if (ctx.model.typeByName.containsKey(t.name)) {
    return _unwrapFacade(p, t, expr, ctx) ?? _unmarshalled(p, t, expr, markers);
  }
  if (_primitives.contains(t.name)) return expr;
  if (t.name == 'String') {
    return switch (p) {
      Platform.android => '$expr$q.toJString()',
      Platform.ios || Platform.macos =>
        q.isEmpty ? 'NSString($expr)' : '_n($expr, NSString.new)',
      Platform.web || Platform.windows || Platform.linux => expr,
    };
  }
  return _unmarshalled(p, t, expr, markers);
}

/// Converts the binding result [expr] on [p] to the facade type, honouring
/// [async].
String _toDart(
  Platform p,
  TypeRef t,
  Async async,
  String expr,
  _Ctx ctx,
  List<Marker> markers,
) {
  switch (async) {
    case Async.none:
      return _fromNative(p, t, expr, ctx, markers, js: false);
    case Async.future:
      switch (p) {
        case Platform.android:
          final inner = _fromNative(p, t, 'v', ctx, markers, js: false);
          return inner == 'v' ? expr : '$expr.then((v) => $inner)';
        case Platform.web:
          if (t.name == 'void') return '$expr.toDart';
          final inner = _fromNative(p, t, 'v', ctx, markers, js: true);
          return inner == 'v'
              ? '$expr.toDart'
              : '$expr.toDart.then((v) => $inner)';
        case Platform.ios ||
            Platform.macos ||
            Platform.windows ||
            Platform.linux:
          markers.add(
            Marker.verify(
              '${p.name}: async result needs a completion-handler wrapper; '
              'the raw binding value is returned',
            ),
          );
          return expr;
      }
    case Async.stream || Async.callback:
      markers.add(
        Marker.verify(
          '${p.name}: ${async.name} results are not mapped yet; the raw '
          'binding value is returned',
        ),
      );
      return expr;
  }
}

String _fromNative(
  Platform p,
  TypeRef t,
  String expr,
  _Ctx ctx,
  List<Marker> markers, {
  required bool js,
}) {
  final nullable = t.nullability == Nullability.nullable;
  final q = nullable ? '?' : '';
  if (t.name == 'void') return expr;
  if (p == Platform.web) return _fromJs(p, t, expr, ctx, markers, boxed: js);
  if (_fromC(p, t, expr, ctx, markers) case final c?) return c;
  if (ctx.model.typeByName.containsKey(t.name)) {
    if (ctx.model.typeByName[t.name]!.shape.kind == TypeKind.enumeration) {
      return _unmarshalled(p, t, expr, markers);
    }
    return nullable ? '_n($expr, ${t.name}._)' : '${t.name}._($expr)';
  }
  if (_primitives.contains(t.name)) return expr;
  if (t.name == 'String') {
    return switch (p) {
      Platform.android => '$expr$q.toDartString(releaseOriginal: true)',
      Platform.ios || Platform.macos => '$expr$q.toDartString()',
      Platform.web || Platform.windows || Platform.linux => expr,
    };
  }
  return _unmarshalled(p, t, expr, markers);
}

/// Facade value → dart:js_interop value. At the top level of an `external`
/// signature primitives convert implicitly; inside `JSArray`/`JSPromise` type
/// arguments ([boxed]) they need `.toJS`. [depth] keeps loop variables of
/// nested lists apart.
String _toJs(
  TypeRef t,
  String expr,
  _Ctx ctx,
  List<Marker> markers, {
  required bool boxed,
  int depth = 0,
}) {
  const p = Platform.web;
  final nullable = t.nullability == Nullability.nullable;
  final q = nullable ? '?' : '';
  if (ctx.model.typeByName[t.name] case final unified?) {
    if (unified.shape.kind == TypeKind.enumeration) {
      // JavaScript has no enums: the binding takes the literal.
      return ctx.enumValues(t.name) == null
          ? _unmarshalled(p, t, expr, markers)
          : '$expr$q.value';
    }
    return _unwrapFacade(p, t, expr, ctx) ?? _unmarshalled(p, t, expr, markers);
  }
  if (t.name == 'JSFunction' && t.args.isNotEmpty) {
    // `.toJS` makes a new JSFunction every time, so a caller that has to
    // remove the callback later needs the converted value, not the closure.
    markers.add(
      const Marker.verify(
        'a callback is converted with `.toJS`, which returns a new JSFunction '
        'each time; keep the converted value to pass the same one twice',
      ),
    );
    return '$expr$q.toJS';
  }
  if (_jsTypes.contains(t.name)) return expr;
  if (_primitives.contains(t.name) || t.name == 'String') {
    return boxed ? '$expr$q.toJS' : expr;
  }
  if (t.name == 'List' && t.args.length == 1) {
    final e = 'e$depth';
    final inner = _toJs(
      t.args.single,
      e,
      ctx,
      markers,
      boxed: true,
      depth: depth + 1,
    );
    if (!nullable) return '[for (final $e in $expr) $inner].toJS';
    final v = 'v$depth';
    return '_n($expr, ($v) => [for (final $e in $v) $inner].toJS)';
  }
  return _unmarshalled(p, t, expr, markers);
}

/// dart:js_interop value → facade value; the inverse of [_toJs].
String _fromJs(
  Platform p,
  TypeRef t,
  String expr,
  _Ctx ctx,
  List<Marker> markers, {
  required bool boxed,
  int depth = 0,
}) {
  final nullable = t.nullability == Nullability.nullable;
  final q = nullable ? '?' : '';
  if (t.name == 'void') return expr;
  if (ctx.model.typeByName[t.name] case final unified?) {
    if (unified.shape.kind == TypeKind.enumeration) {
      final values = ctx.enumValues(t.name);
      if (values == null) return _unmarshalled(p, t, expr, markers);
      final lifted = '${t.name}.fromValue(${boxed ? '$expr.toDart' : expr})';
      return nullable ? '_n($expr, (v) => $lifted)' : lifted;
    }
    return nullable ? '_n($expr, ${t.name}._)' : '${t.name}._($expr)';
  }
  if (_jsTypes.contains(t.name)) return expr;
  if (_primitives.contains(t.name) || t.name == 'String') {
    if (!boxed) return expr;
    return switch (t.name) {
      'int' => '$expr$q.toDartInt',
      'double' || 'num' => '$expr$q.toDartDouble',
      _ => '$expr$q.toDart',
    };
  }
  if (t.name == 'List' && t.args.length == 1) {
    final e = 'e$depth';
    final inner = _fromJs(
      p,
      t.args.single,
      e,
      ctx,
      markers,
      boxed: true,
      depth: depth + 1,
    );
    if (!nullable) return '[for (final $e in $expr.toDart) $inner]';
    final v = 'v$depth';
    return '_n($expr, ($v) => [for (final $e in $v.toDart) $inner])';
  }
  return _unmarshalled(p, t, expr, markers);
}

// ---------------------------------------------------------------------------
// C bindings (plan P6-4b)
//
// `cFacadePass` has already renamed the C types to their facade spelling and
// left the dart:ffi one in `TypeRef.native`, so `native` is what says how a
// value crosses: `ffi.Pointer<ffi.Char>` on a `String` is a C string,
// `ffi.Pointer<Rect>` on a `Rect` is a struct passed by reference, and a plain
// `Rect` is one passed by value, which dart:ffi does on its own.

/// The allocator a C argument conversion allocates from. A call whose argument
/// list mentions it is wrapped in `using`, which frees the arena when the call
/// returns.
const _arena = '_arena';

/// True when the arguments allocated, so the call has to run inside an arena.
bool _allocates(_Ctx ctx, String args) =>
    ctx.pending.isNotEmpty || args.contains(_arena);

/// Wraps [call] in the arena its arguments allocated from, declaring the
/// locals they hoisted and running their write-backs after the call returns.
///
/// [discard] says the call has no value to return, which is not the same as
/// having nothing to do afterwards: `void f(Point *out)` is exactly the case
/// this exists for.
String _withArena(_Ctx ctx, String call, {required bool discard}) {
  if (ctx.pending.isEmpty) return 'using(($_arena) => $call)';
  final b = StringBuffer('using(($_arena) {');
  for (final e in ctx.pending) {
    b.writeln(e.local);
  }
  b.writeln(discard ? '$call;' : 'final _result = $call;');
  for (final e in ctx.pending) {
    b.writeln(e.back);
  }
  if (!discard) b.writeln('return _result;');
  ctx.pending.clear();
  b.write('})');
  return b.toString();
}

/// The `X` of a `Pointer<X>` in a dart:ffi spelling, or null when [native] is
/// not a pointer to one named type.
String? _pointee(String native) {
  const prefix = 'ffi.Pointer<';
  if (!native.startsWith(prefix) || !native.endsWith('>')) return null;
  final inner = native.substring(prefix.length, native.length - 1);
  return inner.contains('<') ? null : inner;
}

/// Facade value → C binding value, or null when [t] is not a C type.
String? _toC(
  Platform p,
  TypeRef t,
  String expr,
  _Ctx ctx,
  List<Marker> markers,
) {
  final native = t.native;
  if (native == null || !native.startsWith('ffi.')) return null;
  final unified = ctx.model.typeByName[t.name];
  if (t.name == 'String' && _pointee(native) == 'ffi.Char') {
    ctx.needsFfi = true;
    if (t.nullability == Nullability.nullable) {
      return '_n($expr, (v) => '
          'v.toNativeUtf8(allocator: $_arena).cast<ffi.Char>()) '
          '?? ffi.nullptr';
    }
    return '$expr.toNativeUtf8(allocator: $_arena).cast<ffi.Char>()';
  }
  if (unified == null) {
    // `cFacadePass` degraded a pointer it could not spell; the binding still
    // wants the real pointee type.
    if (t.name.startsWith('ffi.Pointer') && t.name != native) {
      ctx.needsFfi = true;
      return '$expr.cast()';
    }
    return null;
  }
  final binding = ctx.bindingType(p, t.name);
  if (binding == null) return null;
  if (unified.shape.kind == TypeKind.enumeration) {
    // ffigen types an enum parameter with its own Dart enum, so the two are
    // matched by constant name; a name the binding lacks already carries a
    // `@BindsmithVerify` on the facade enum.
    return '${p.name}.$binding.values.byName($expr.name)';
  }
  final q = t.nullability == Nullability.nullable ? '?' : '';
  if (_pointee(native) == null) return null;
  ctx.needsFfi = true;
  if (unified.shape.kind == TypeKind.opaque) {
    // An opaque handle is nothing but its pointer, and the facade object is
    // holding it.
    return '($expr$q._impl as ffi.Pointer<${p.name}.$binding>$q)';
  }
  // A struct argument the binding takes by reference is copied into the arena,
  // so the callee sees the facade object's current field values, and the copy
  // is freed with the arena when the call returns.
  final copy =
      '($_arena<${p.name}.$binding>()..ref = '
      '($expr$q._impl as ${p.name}.$binding))';
  final fields = [
    for (final m in unified.impls[p]?.members ?? const <Member>[])
      if (m.kind == MemberKind.field) m.name,
  ];
  if (q.isNotEmpty || fields.isEmpty) {
    // A null argument has nothing to write back into, and a struct whose
    // fields the IR does not carry cannot be copied field by field.
    markers.add(
      Marker.verify(
        '${p.name}: ${t.name} is copied into an arena for the call and the '
        'copy is freed with it, so a callee that writes through the pointer '
        'writes into the copy, not into ${t.name}',
      ),
    );
    return q.isEmpty ? copy : '_n($expr, (v) => $copy) ?? ffi.nullptr';
  }
  // The copy is what the callee writes through, so it is read back field by
  // field afterwards: dart:ffi copies a struct into a pointer but has no way
  // to copy one out. A callee that *keeps* the pointer still outlives it.
  markers.add(
    Marker.verify(
      '${p.name}: ${t.name} crosses as an arena copy that is read back into it '
      'when the call returns; a callee that keeps the pointer outlives it',
    ),
  );
  final name = '_p${ctx.pending.length}';
  ctx.pending.add((
    local: 'final $name = $copy;',
    back:
        '($expr._impl as ${p.name}.$binding)'
        '${fields.map((f) => '..$f = $name.ref.$f').join()};',
  ));
  return name;
}

/// C binding value → facade value, or null when [t] is not a C type.
String? _fromC(
  Platform p,
  TypeRef t,
  String expr,
  _Ctx ctx,
  List<Marker> markers,
) {
  final native = t.native;
  if (native == null || !native.startsWith('ffi.')) return null;
  final unified = ctx.model.typeByName[t.name];
  if (unified?.shape.kind == TypeKind.enumeration) {
    return '${t.name}.values.byName($expr.name)';
  }
  if (t.name == 'String' && _pointee(native) == 'ffi.Char') {
    ctx.needsFfi = true;
    markers.add(
      Marker.verify(
        '${p.name}: the returned string is copied out of memory the library '
        'owns; it is not freed here',
      ),
    );
    return '$expr.cast<Utf8>().toDartString()';
  }
  if (unified == null) {
    if (t.name.startsWith('ffi.Pointer') && t.name != native) {
      ctx.needsFfi = true;
      return '$expr.cast()';
    }
    return null;
  }
  if (_pointee(native) == null) return null;
  ctx.needsFfi = true;
  if (unified.shape.kind == TypeKind.opaque) {
    return '${t.name}._($expr)';
  }
  markers.add(
    Marker.verify(
      '${p.name}: ${t.name} is a view on memory the library owns; it stays '
      'valid only as long as the library keeps it',
    ),
  );
  return '${t.name}._($expr.ref)';
}

String _unmarshalled(
  Platform p,
  TypeRef t,
  String expr,
  List<Marker> markers, {
  String? hint,
}) {
  markers.add(
    Marker.verify(
      '${p.name}: no marshalling for ${_dartType(t)}'
      '${hint == null ? '' : ' ($hint)'}; passed through unchanged',
    ),
  );
  return expr;
}

// ---------------------------------------------------------------------------
// Rendering helpers

String _dartType(TypeRef t) {
  final q = t.nullability == Nullability.nullable ? '?' : '';
  // `dtsFacadePass` leaves a callback's signature in `args` — the return type
  // first, then the parameters — where a Dart function can be passed.
  if (t.name == 'JSFunction' && t.args.isNotEmpty) {
    final params = t.args.skip(1).map(_dartType).join(', ');
    return '${_dartType(t.args.first)} Function($params)$q';
  }
  final args = t.args.isEmpty ? '' : '<${t.args.map(_dartType).join(', ')}>';
  return '${t.name}$args$q';
}

String _facadeReturn(TypeRef returns, Async async) => switch (async) {
  Async.none => _dartType(returns),
  Async.future => 'Future<${_dartType(returns)}>',
  Async.stream => 'Stream<${_dartType(returns)}>',
  Async.callback => _dartType(returns),
};

String _params(List<Param> params) {
  final required = <String>[];
  final optional = <String>[];
  final named = <String>[];
  // Dart allows optional positional or named parameters, not both; when a
  // driver mixes them the optional ones become named too.
  final hasNamed = params.any((p) => p.named);
  for (final p in params) {
    final type = _dartType(p.type);
    final orNull = p.type.nullability == Nullability.nullable ? type : '$type?';
    if (p.named || (p.optional && hasNamed)) {
      named.add(p.optional ? '$orNull ${p.name}' : 'required $type ${p.name}');
    } else if (p.optional) {
      optional.add('$orNull ${p.name}');
    } else {
      required.add('$type ${p.name}');
    }
  }
  return [
    ...required,
    if (optional.isNotEmpty) '[${optional.join(', ')}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ].join(', ');
}

void _paramDocs(StringBuffer b, List<Param> params) {
  for (final p in params) {
    if (p.docs case final docs?) {
      b.writeln('/// - [${p.name}]: $docs');
    }
  }
}

void _docs(
  StringBuffer b,
  String? docs,
  Availability? availability,
  List<Marker> markers,
) {
  if (docs != null) {
    for (final line in docs.trim().split('\n')) {
      b.writeln('/// ${line.trimRight()}'.trimRight());
    }
  }
  if (availability?.since != null) {
    b.writeln('///');
    b.writeln('/// Available since ${availability!.since}.');
  }
  if (availability?.deprecated != null) {
    b.writeln('@Deprecated(${_str(availability!.deprecated!)})');
  }
  final seen = <String>{};
  for (final m in markers) {
    if (m.kind == MarkerKind.verify && seen.add(m.reason)) {
      b.writeln('@BindsmithVerify(${_str(m.reason)})');
    }
  }
}

String _str(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', ' ')}'";

String _format(String source) =>
    DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
        .format(source);
