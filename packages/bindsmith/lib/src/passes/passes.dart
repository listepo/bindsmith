/// Pure transformations over the IR.
///
/// A [Pass] never mutates its input; it returns a new list. Passes run in the
/// order given to [runPasses]. Nothing is removed silently: a declaration or
/// member that must not be emitted gets a `dropped` marker and stays in the
/// list so `dump`, `explain` and `verify` can show it.
library;

import '../ir/ir.dart';
import 'symbol_pattern.dart';

export 'symbol_pattern.dart';

typedef Pass = List<Decl> Function(List<Decl> decls);

List<Decl> runPasses(List<Decl> decls, Iterable<Pass> passes) =>
    passes.fold(decls, (current, pass) => pass(current));

/// Keeps only declarations named by [patterns] (pull model). Everything else
/// is marked dropped with the reason `not in include list`.
///
/// Member-level patterns (`Type.member`) keep the declaration and drop the
/// members the patterns do not name.
Pass includePass(List<String> patterns) {
  final parsed = [for (final p in patterns) SymbolPattern.parse(p)];
  return (decls) => [
    for (final decl in decls)
      if (parsed.any((p) => p.matchesDecl(decl)))
        decl
      else if (decl is TypeDecl && parsed.any((p) => p.touches(decl)))
        decl.copyWith(
          members: [
            for (final m in decl.members)
              if (parsed.any((p) => p.matchesMember(decl, m)))
                m
              else
                m.copyWith(
                  markers: [
                    ...m.markers,
                    const Marker.dropped('not in include list'),
                  ],
                ),
          ],
        )
      else
        decl.copyWith(
          markers: [
            ...decl.markers,
            const Marker.dropped('not in include list'),
          ],
        ),
  ];
}

/// Replaces `Nullability.unknown` with `nullable` and attaches a verify marker
/// naming the affected types, so a guess never ships unreviewed.
Pass nullabilityPass() =>
    (decls) => [
      for (final decl in decls)
        switch (decl) {
          TypeDecl() => decl.copyWith(
            members: [for (final m in decl.members) _fixMember(m)],
          ),
          FunctionDecl() => _fixFunction(decl),
          VariableDecl() when decl.type.nullability == Nullability.unknown =>
            VariableDecl(
              id: decl.id,
              name: decl.name,
              platform: decl.platform,
              type: decl.type.copyWith(nullability: Nullability.nullable),
              value: decl.value,
              isConst: decl.isConst,
              loc: decl.loc,
              docs: decl.docs,
              availability: decl.availability,
              markers: [
                ...decl.markers,
                _unknownMarker([decl.type.name]),
              ],
            ),
          VariableDecl() => decl,
        },
    ];

Marker _unknownMarker(List<String> names) => Marker.verify(
  'nullability unknown for ${names.join(', ')}; treated as nullable',
);

TypeRef _nullable(TypeRef t) => t.nullability == Nullability.unknown
    ? t.copyWith(nullability: Nullability.nullable)
    : t;

Member _fixMember(Member m) {
  final unknown = [
    for (final p in m.params)
      if (p.type.nullability == Nullability.unknown) p.name,
    if (m.returns.nullability == Nullability.unknown) 'return value',
  ];
  if (unknown.isEmpty) return m;
  return m.copyWith(
    params: [
      for (final p in m.params)
        Param(p.name, _nullable(p.type), optional: p.optional, docs: p.docs),
    ],
    returns: _nullable(m.returns),
    markers: [...m.markers, _unknownMarker(unknown)],
  );
}

FunctionDecl _fixFunction(FunctionDecl f) {
  final unknown = [
    for (final p in f.params)
      if (p.type.nullability == Nullability.unknown) p.name,
    if (f.returns.nullability == Nullability.unknown) 'return value',
  ];
  if (unknown.isEmpty) return f;
  return f.copyWith(
    params: [
      for (final p in f.params)
        Param(p.name, _nullable(p.type), optional: p.optional, docs: p.docs),
    ],
    returns: _nullable(f.returns),
    markers: [...f.markers, _unknownMarker(unknown)],
  );
}

// ---------------------------------------------------------------------------
// C bindings → facade types (plan P6-4b)

/// Marker reason on a synthesized `dispose`, naming the facade function that
/// releases the handle. [cFacadePass] writes it and the facade emitter reads
/// it, so the two agree without either one parsing the other's strings.
String disposedBy(String function) => 'released by calling $function';

/// Marker reason on a struct constructor [cFacadePass] synthesized, naming the
/// dart:ffi struct it lays out. Same contract as [disposedBy]: the name is
/// last, so the emitter reads it back without parsing prose.
String laidOutAs(String type) =>
    '$type is laid out by ffi.Struct.create on the Dart heap: it owns no '
    'native memory, so it is collected like any other Dart object and has no '
    'dispose';

/// Marker reason on a struct field that is itself a struct.
const viewIntoContainer =
    'reading a struct field gives a view into the memory of the struct that '
    'contains it, not a copy: writing through it writes into the container';

/// Suffixes a C library uses for the function that frees a handle.
const _freeSuffixes = ['_free', '_destroy', '_release', '_delete', '_close'];

/// Rewrites a C binding's types into the API the facade should offer, and
/// gives every opaque handle a `dispose`.
///
/// A dart:ffi binding is spelled in pointers; a Dart API is not. This pass
/// renames the type — `TypeRef.name` becomes the facade spelling — and keeps
/// the dart:ffi one in `TypeRef.native`, which is what tells the facade
/// emitter how to marshal the value back:
///
/// | C binding                | facade  | marshalling                        |
/// |--------------------------|---------|------------------------------------|
/// | `Pointer<Char>`          | `String`| arena-allocated UTF-8 copy         |
/// | `Pointer<X>`, X opaque   | `X`     | the wrapper's pointer              |
/// | `Pointer<X>`, X a struct | `X`     | arena copy through `Pointer.ref`   |
/// | `X` by value, X a struct | `X`     | unchanged: dart:ffi passes structs |
/// | `X`, X an enum           | `X`     | its `value`                        |
///
/// A one-argument `void` function whose name ends in `_free`, `_destroy`,
/// `_release`, `_delete` or `_close` and that takes exactly one handle is
/// recognised as that handle's deallocator: the opaque type gains a `dispose`
/// forwarding to it. The function itself stays in the facade — a C API may
/// hand a handle back to be freed elsewhere — so nothing is dropped.
///
/// Types this pass does not recognise keep their C spelling and reach the
/// emitter unchanged, where they become a `verify` marker rather than a
/// silently wrong signature.
Pass cFacadePass() => (decls) {
  final kinds = {
    for (final d in decls)
      if (d is TypeDecl) d.name: d.kind,
  };
  // A C typedef is replaced by what it aliases, so no signature is left
  // naming a declaration the facade drops.
  final aliases = {
    for (final d in decls)
      if (d is TypeDecl && d.kind == TypeKind.typedef && _isC(d))
        d.name: d.supertypes.single,
  };
  final disposers = _disposers(decls, kinds);
  final notes = <String>[];
  TypeRef map(TypeRef t) => _cFacadeType(t, kinds, aliases, notes);
  List<Param> params(List<Param> ps) => [
    for (final p in ps)
      Param(
        p.name,
        map(p.type),
        optional: p.optional,
        named: p.named,
        docs: p.docs,
      ),
  ];
  List<Marker> collect(List<Marker> existing) {
    final added = [for (final note in notes) Marker.verify(note)];
    notes.clear();
    return added.isEmpty ? existing : [...existing, ...added];
  }

  Member member(Member m) {
    final returns = map(m.returns);
    return m.copyWith(
      params: params(m.params),
      returns: returns,
      markers: collect([
        ...m.markers,
        // Reading it hands out the container's own memory; the surprise is on
        // the way out, not on the way in, where the assignment copies.
        if (m.kind == MemberKind.field &&
            kinds[returns.name] == TypeKind.struct)
          const Marker.verify(viewIntoContainer),
      ]),
    );
  }

  return [
    for (final decl in decls)
      switch (decl) {
        FunctionDecl() => decl.copyWith(
          params: params(decl.params),
          returns: map(decl.returns),
          markers: collect(decl.markers),
        ),
        VariableDecl() => decl.copyWith(type: map(decl.type)),
        // An alias is not an object: the facade would emit an empty class for
        // it while every signature already names what it aliases.
        TypeDecl(kind: TypeKind.typedef) when _isC(decl) => decl.copyWith(
          markers: [
            ...decl.markers,
            const Marker.dropped(
              'a typedef is an alias, not a type the facade can wrap; the '
              'declarations using it name its target directly',
            ),
          ],
        ),
        TypeDecl() => decl.copyWith(
          members: [
            for (final m in decl.members) member(m),
            if (disposers[decl.name] case final free?)
              Member(
                'dispose',
                kind: MemberKind.method,
                markers: [Marker.verify(disposedBy(free))],
              ),
            ..._structMembers(decl, map),
          ],
        ),
      },
  ];
};

/// The constructor and field setters a C struct gets, on top of the getters its
/// fields already have.
///
/// A dart:ffi struct has no Dart constructor — `ffi.Struct.create` lays one out
/// on the Dart heap — so the facade cannot make one without the emitter's help;
/// the marker [laidOutAs] is what asks for it, and it doubles as the answer to
/// the question a reader has here, which is who frees the memory. Nobody: the
/// struct is garbage-collected like any other Dart object, unlike the handles
/// on this same page.
///
/// A struct with a pointer field gets neither the constructor nor a setter for
/// that field; see [_byValue].
List<Member> _structMembers(TypeDecl decl, TypeRef Function(TypeRef) map) {
  if (decl.kind != TypeKind.struct || !_isC(decl)) return const [];
  final fields = [
    for (final m in decl.members)
      if (m.kind == MemberKind.field) (name: m.name, type: map(m.returns)),
  ];
  if (fields.isEmpty) return const [];
  return [
    if (fields.every((f) => _byValue(f.type)))
      Member(
        '',
        kind: MemberKind.constructor,
        params: [for (final f in fields) Param(f.name, f.type, named: true)],
        markers: [Marker.verify(laidOutAs(decl.name))],
      ),
    for (final f in fields)
      if (_byValue(f.type))
        Member(
          f.name,
          kind: MemberKind.setter,
          params: [Param('value', f.type)],
        ),
  ];
}

/// Opaque type name → the facade function that frees it.
Map<String, String> _disposers(List<Decl> decls, Map<String, TypeKind> kinds) {
  final found = <String, String>{};
  for (final decl in decls) {
    if (decl is! FunctionDecl) continue;
    if (decl.returns.name != 'void' || decl.params.length != 1) continue;
    if (!_freeSuffixes.any(decl.name.endsWith)) continue;
    final handle = _pointee(decl.params.single.type);
    if (handle == null || kinds[handle] != TypeKind.opaque) continue;
    // Two candidates and the convention is not decisive: leave both alone and
    // let the caller free the handle explicitly.
    found[handle] = found.containsKey(handle) ? '' : decl.name;
  }
  return {
    for (final e in found.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };
}

/// The `X` of a `Pointer<X>`, or null when [t] is not a pointer to one named
/// type — `Pointer<Pointer<…>>` and a bare `Pointer` have no facade shape.
String? _pointee(TypeRef t) => switch (t) {
  TypeRef(name: 'Pointer', args: [TypeRef(:final name, args: [])]) => name,
  _ => null,
};

/// Identifiers in a dart:ffi spelling that the facade cannot resolve: anything
/// not qualified with the `ffi.` prefix lives in the binding library.
final _bindingName = RegExp(r'ffi\.[A-Za-z0-9_]+|[<>, ]');

TypeRef _cFacadeType(
  TypeRef t,
  Map<String, TypeKind> kinds,
  Map<String, TypeRef> aliases,
  List<String> notes, {
  int depth = 0,
}) {
  // An alias chain is finite in valid metadata; the guard is for IR a fixup
  // made circular.
  if (aliases[t.name] case final target? when depth < 8) {
    return _cFacadeType(
      TypeRef(
        target.name,
        args: target.args,
        nullability: t.nullability,
        native: target.native,
      ),
      kinds,
      aliases,
      notes,
      depth: depth + 1,
    );
  }
  final native = t.native;
  // Only a dart:ffi spelling is a C binding type; every other driver records
  // its own language here.
  if (native == null || !native.startsWith('ffi.')) return t;
  final facade = switch (_pointee(t)) {
    // `char *` is the only C string this pass claims; a wide or explicitly
    // encoded one keeps its pointer and its marker.
    'Char' => 'String',
    final name? when kinds[name] == TypeKind.opaque => name,
    final name? when kinds[name] == TypeKind.struct => name,
    // Nothing claimed it, so it stays a pointer — spelled the way the facade
    // file imports dart:ffi, or it would not resolve there.
    _ when t.name == 'Pointer' => _opaque(native, notes),
    _ => null,
  };
  if (facade == null) return t;
  return TypeRef(facade, nullability: t.nullability, native: native);
}

/// The facade spelling of a pointer nothing claimed.
///
/// The dart:ffi spelling is used as it stands when every name in it is a
/// dart:ffi one. A spelling that names a type from the binding library cannot
/// be written in a facade signature — the facade is one API over several
/// bindings — so it degrades to `Pointer<Void>` and says so.
String _opaque(String native, List<String> notes) {
  if (native.replaceAll(_bindingName, '').isEmpty) return native;
  notes.add(
    '$native is spelled in the binding library and has no facade type; '
    'passed as ffi.Pointer<ffi.Void>, cast it back before use',
  );
  return 'ffi.Pointer<ffi.Void>';
}

/// True when [decl] came from a dart:ffi binding: either the type it aliases
/// or one of its fields is spelled in dart:ffi.
bool _isC(TypeDecl decl) =>
    decl.supertypes.any((t) => t.native?.startsWith('ffi.') ?? false) ||
    decl.members.any((m) => m.returns.native?.startsWith('ffi.') ?? false);

/// True when a value of [t] can be written into a struct field and stay valid
/// after the call that wrote it.
///
/// A pointer cannot: the facade marshals one through an arena that is released
/// when the expression ends, so a struct holding it would be left pointing at
/// freed memory. Such a field keeps its getter and loses its setter, and the
/// struct loses its constructor, rather than offering a way to build one that
/// is already dangling.
bool _byValue(TypeRef t) => !(t.native ?? '').contains('Pointer');

// ---------------------------------------------------------------------------
// TypeScript bindings → facade types (plan P4-3)

/// Marker reason on an enum this pass invented, naming where it came from.
String synthesizedFrom(String union, String site) =>
    'named after $site; TypeScript spells this union $union inline, and a '
    'Dart enum needs a name';

/// A union of string or number literals: `'formal' | 'casual'`.
final _literalUnion = RegExp(
  r"^'[^']*'( \| '[^']*')+$|^-?[\d.]+( \| -?[\d.]+)+$",
);

/// Turns a TypeScript binding into the API the facade should offer.
///
/// Two rewrites, both of which need a name the TypeScript does not give:
///
/// * a union of literals (`tone: 'formal' | 'casual'`) becomes an enum named
///   after the declaration and member it was found on, so `String` stops being
///   the only thing the type system knows about it. Two members with the same
///   literals share one enum, and the enum carries a marker saying its name
///   was invented.
/// * a callback keeps its signature only where a Dart function can be passed.
///   [DtsDriver] records the signature in `TypeRef.args` (the return type
///   first, then the parameters); the facade turns a parameter into a typed
///   Dart function and converts it with `.toJS`, while a result or a property
///   stays a `JSFunction`, because converting one back needs a closure that
///   calls through it.
///
/// @docImport '../drivers/dts/dts_driver.dart';
Pass dtsFacadePass() => (decls) {
  final unions = _Unions({
    for (final d in decls)
      if (d is TypeDecl) d.name,
  });
  for (final decl in decls) {
    switch (decl) {
      case FunctionDecl():
        for (final p in decl.params) {
          unions.record(p.type, decl.name, p.name);
        }
      case TypeDecl():
        for (final m in decl.members) {
          unions.record(m.returns, decl.name, m.name);
          for (final p in m.params) {
            unions.record(p.type, decl.name, m.name.isEmpty ? p.name : m.name);
          }
        }
      case VariableDecl():
        unions.record(decl.type, decl.name, decl.name);
    }
  }
  Param param(Param p) => Param(
    p.name,
    unions.map(p.type),
    optional: p.optional,
    named: p.named,
    docs: p.docs,
  );
  // A result keeps `JSFunction`: `.toJS` goes one way only.
  TypeRef out(TypeRef t) => t.name == 'JSFunction' && t.args.isNotEmpty
      ? TypeRef(t.name, nullability: t.nullability, native: t.native)
      : unions.map(t);
  return [
    ...unions.declarations,
    for (final decl in decls)
      switch (decl) {
        FunctionDecl() => decl.copyWith(
          params: [for (final p in decl.params) param(p)],
          returns: out(decl.returns),
        ),
        VariableDecl() => decl.copyWith(type: out(decl.type)),
        TypeDecl() => decl.copyWith(
          members: [
            for (final m in decl.members)
              m.copyWith(
                params: [for (final p in m.params) param(p)],
                returns: out(m.returns),
              ),
          ],
        ),
      },
  ];
};

/// Collects the literal unions in a binding and gives each one an enum.
final class _Unions {
  _Unions(this.taken);

  /// Declaration names already in use, so an invented one does not collide.
  final Set<String> taken;

  /// Literal list → the enum standing for it.
  final byLiterals = <String, TypeDecl>{};

  List<TypeDecl> get declarations =>
      byLiterals.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  void record(TypeRef t, String owner, String member) {
    final native = t.native;
    if (native == null || !_literalUnion.hasMatch(native)) return;
    if (byLiterals.containsKey(native)) return;
    final site = '$owner.$member';
    var name = '${_capitalize(owner)}${_capitalize(member)}';
    for (var i = 2; taken.contains(name); i++) {
      name = '${_capitalize(owner)}${_capitalize(member)}$i';
    }
    taken.add(name);
    byLiterals[native] = TypeDecl(
      id: name,
      name: name,
      platform: Platform.web,
      kind: TypeKind.enumeration,
      members: [
        for (final literal in native.split(' | '))
          Member(
            _identifier(literal),
            kind: MemberKind.constant,
            returns: TypeRef(t.name),
            value: literal,
          ),
      ],
      markers: [Marker.verify(synthesizedFrom(native, site))],
    );
  }

  TypeRef map(TypeRef t) {
    final decl = t.native == null ? null : byLiterals[t.native];
    if (decl == null) return t;
    return TypeRef(decl.name, nullability: t.nullability, native: t.native);
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// A Dart identifier for a literal: `'two-parts'` → `twoParts`, `2` → `$2`.
String _identifier(String literal) {
  final text = literal.startsWith("'")
      ? literal.substring(1, literal.length - 1)
      : literal;
  final words = text.split(RegExp(r'[^A-Za-z0-9]+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return r'$';
  final joined = [
    words.first,
    for (final w in words.skip(1)) _capitalize(w),
  ].join();
  return RegExp(r'^[0-9]').hasMatch(joined) ? '\$$joined' : joined;
}
