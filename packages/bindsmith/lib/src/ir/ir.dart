/// Unified intermediate representation.
///
/// Every driver reduces its platform's API to a `List<Decl>`. Passes are pure
/// functions over that list; emitters read it and nothing else. The model is
/// immutable: use `copyWith` to derive a changed declaration and never mutate
/// the lists in place.
///
/// JSON round-trips (`toJson` / `fromJson`) exist for snapshot tests,
/// `bindsmith dump` and `bindsmith diff`. Key order is fixed so serialized
/// output is deterministic.
library;

import 'dart:convert' show jsonEncode;

/// The six Flutter platforms.
enum Platform { android, ios, macos, windows, linux, web }

/// What kind of type a [TypeDecl] describes.
enum TypeKind {
  klass,
  interface,
  protocol,
  struct,
  enumeration,
  opaque,
  typedef,
  jsObject,
}

/// What kind of member a [Member] describes. A `setter` has exactly one
/// parameter and returns void; a writable property is a `property` plus a
/// `setter` of the same name.
enum MemberKind {
  method,
  constructor,
  property,
  setter,
  field,
  constant,
  event,
}

/// How a call completes on the Dart side.
enum Async { none, future, stream, callback }

/// Which thread the native side requires.
enum Threading { any, main }

/// Tri-state nullability; `unknown` becomes a verify marker.
enum Nullability { nonNull, nullable, unknown }

/// Why a symbol needs attention. `dropped` means the symbol is not emitted.
enum MarkerKind { verify, dropped, todo }

T _enumFromJson<T extends Enum>(List<T> values, Object? json) =>
    values.byName(json as String);

/// A note attached to a declaration or member that `bindsmith verify` and
/// `bindsmith dump` surface. Nothing is ever dropped without one.
final class Marker {
  const Marker(this.kind, this.reason);

  const Marker.verify(String reason) : this(MarkerKind.verify, reason);

  const Marker.dropped(String reason) : this(MarkerKind.dropped, reason);

  factory Marker.fromJson(Map<String, Object?> json) => Marker(
    _enumFromJson(MarkerKind.values, json['kind']),
    json['reason'] as String,
  );

  final MarkerKind kind;
  final String reason;

  Map<String, Object?> toJson() => {'kind': kind.name, 'reason': reason};

  @override
  String toString() => '${kind.name}: $reason';
}

/// Where a declaration came from in the native input.
final class SourceLoc {
  const SourceLoc(this.file, [this.line]);

  factory SourceLoc.fromJson(Map<String, Object?> json) =>
      SourceLoc(json['file'] as String, json['line'] as int?);

  final String file;
  final int? line;

  Map<String, Object?> toJson() => {
    'file': file,
    if (line != null) 'line': line,
  };
}

/// Platform availability carried into dartdoc and optional runtime guards.
final class Availability {
  const Availability({this.since, this.deprecated});

  factory Availability.fromJson(Map<String, Object?> json) => Availability(
    since: json['since'] as String?,
    deprecated: json['deprecated'] as String?,
  );

  /// Minimum OS/API level, in the platform's own notation (`iOS 15`, `26`).
  final String? since;

  /// Deprecation message, when the native API is deprecated.
  final String? deprecated;

  Map<String, Object?> toJson() => {
    if (since != null) 'since': since,
    if (deprecated != null) 'deprecated': deprecated,
  };
}

/// A reference to a type by Dart-facing name.
final class TypeRef {
  const TypeRef(
    this.name, {
    this.args = const [],
    this.nullability = Nullability.nonNull,
    this.native,
  });

  factory TypeRef.fromJson(Map<String, Object?> json) => TypeRef(
    json['name'] as String,
    args: _listFromJson(json['args'], TypeRef.fromJson),
    nullability: json.containsKey('nullability')
        ? _enumFromJson(Nullability.values, json['nullability'])
        : Nullability.nonNull,
    native: json['native'] as String?,
  );

  static const void_ = TypeRef('void');

  final String name;
  final List<TypeRef> args;
  final Nullability nullability;

  /// The platform's own spelling (`java.lang.String`, `NSString *`,
  /// `Promise<Response>`), kept for `explain` and for emitters that need it.
  final String? native;

  TypeRef copyWith({String? name, Nullability? nullability}) => TypeRef(
    name ?? this.name,
    args: args,
    nullability: nullability ?? this.nullability,
    native: native,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    if (args.isNotEmpty) 'args': [for (final a in args) a.toJson()],
    if (nullability != Nullability.nonNull) 'nullability': nullability.name,
    if (native != null) 'native': native,
  };

  /// Structural equality, so passes and `verify` can compare signatures.
  @override
  bool operator ==(Object other) =>
      other is TypeRef &&
      other.name == name &&
      other.nullability == nullability &&
      other.native == native &&
      other.args.length == args.length &&
      args.indexed.every((a) => other.args[a.$1] == a.$2);

  @override
  int get hashCode => Object.hash(name, nullability, native, args.length);

  @override
  String toString() => jsonEncode(toJson());
}

/// A function or method parameter.
final class Param {
  const Param(
    this.name,
    this.type, {
    this.optional = false,
    this.named = false,
    this.docs,
  });

  factory Param.fromJson(Map<String, Object?> json) => Param(
    json['name'] as String,
    TypeRef.fromJson(json['type'] as Map<String, Object?>),
    optional: json['optional'] as bool? ?? false,
    named: json['named'] as bool? ?? false,
    docs: json['docs'] as String?,
  );

  final String name;
  final TypeRef type;
  final bool optional;

  /// Passed by name (`{String? prefix}`); named parameters follow the
  /// positional ones. A named parameter that is not [optional] is `required`.
  final bool named;

  /// Parameter documentation, as Markdown.
  final String? docs;

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.toJson(),
    if (optional) 'optional': true,
    if (named) 'named': true,
    if (docs != null) 'docs': docs,
  };
}

/// A member of a [TypeDecl].
final class Member {
  const Member(
    this.name, {
    required this.kind,
    this.params = const [],
    this.returns = TypeRef.void_,
    this.async = Async.none,
    this.threading = Threading.any,
    this.isStatic = false,
    this.binding,
    this.native,
    this.value,
    this.docs,
    this.availability,
    this.markers = const [],
  });

  factory Member.fromJson(Map<String, Object?> json) => Member(
    json['name'] as String,
    kind: _enumFromJson(MemberKind.values, json['kind']),
    binding: json['binding'] as String?,
    native: json['native'] as String?,
    value: json['value'] as String?,
    params: _listFromJson(json['params'], Param.fromJson),
    returns: json.containsKey('returns')
        ? TypeRef.fromJson(json['returns'] as Map<String, Object?>)
        : TypeRef.void_,
    async: json.containsKey('async')
        ? _enumFromJson(Async.values, json['async'])
        : Async.none,
    threading: json.containsKey('threading')
        ? _enumFromJson(Threading.values, json['threading'])
        : Threading.any,
    isStatic: json['isStatic'] as bool? ?? false,
    docs: json['docs'] as String?,
    availability: _availabilityFromJson(json['availability']),
    markers: _listFromJson(json['markers'], Marker.fromJson),
  );

  final String name;
  final MemberKind kind;
  final List<Param> params;
  final TypeRef returns;
  final Async async;
  final Threading threading;
  final bool isStatic;

  /// The member's identifier in the platform binding library, when it differs
  /// from [name] (`greetWithName_` for an ObjC selector, `new$1` for a jnigen
  /// constructor overload, `alloc().initWithName_` for an ObjC initializer).
  /// Passes rename [name] only; the facade calls [binding].
  final String? binding;

  /// The member's name in the native API when it differs from [name]
  /// (`greet` for the overload bound as `greet$2`, an ObjC selector, a JVM
  /// descriptor). Emitters that produce the binding themselves use it.
  final String? native;

  /// Literal value of a [MemberKind.constant] as written in the source
  /// (`0`, `'formal'`), when known.
  final String? value;
  final String? docs;
  final Availability? availability;
  final List<Marker> markers;

  bool get isDropped => markers.any((m) => m.kind == MarkerKind.dropped);

  /// Renaming keeps the binding identifier: the facade keeps calling the
  /// binding by its old name.
  Member copyWith({
    String? name,
    List<Param>? params,
    TypeRef? returns,
    Async? async,
    Threading? threading,
    String? docs,
    List<Marker>? markers,
  }) => Member(
    name ?? this.name,
    kind: kind,
    params: params ?? this.params,
    returns: returns ?? this.returns,
    async: async ?? this.async,
    threading: threading ?? this.threading,
    isStatic: isStatic,
    binding: _rebind(binding, this.name, name),
    native: native,
    value: value,
    docs: docs ?? this.docs,
    availability: availability,
    markers: markers ?? this.markers,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    if (binding != null) 'binding': binding,
    if (native != null) 'native': native,
    if (value != null) 'value': value,
    if (params.isNotEmpty) 'params': [for (final p in params) p.toJson()],
    if (returns.name != 'void') 'returns': returns.toJson(),
    if (async != Async.none) 'async': async.name,
    if (threading != Threading.any) 'threading': threading.name,
    if (isStatic) 'isStatic': true,
    if (docs != null) 'docs': docs,
    if (availability != null) 'availability': availability!.toJson(),
    if (markers.isNotEmpty) 'markers': [for (final m in markers) m.toJson()],
  };
}

/// A top-level declaration produced by a driver for one platform.
sealed class Decl {
  const Decl({
    required this.id,
    required this.name,
    required this.platform,
    this.binding,
    this.native,
    this.loc,
    this.docs,
    this.availability,
    this.markers = const [],
  });

  factory Decl.fromJson(Map<String, Object?> json) =>
      switch (json['decl'] as String) {
        'type' => TypeDecl.fromJson(json),
        'function' => FunctionDecl.fromJson(json),
        'variable' => VariableDecl.fromJson(json),
        final other => throw FormatException('unknown decl kind "$other"'),
      };

  /// Stable identity within a platform, in the native spelling
  /// (`com.example.sdk.Client`, `SDKClient`, `sdk_connect`). Never renamed.
  final String id;

  /// Dart-facing name. Passes may change it.
  final String name;
  final Platform platform;

  /// Identifier in the platform binding library when it differs from [name]
  /// (`Outer$Inner` for a nested Java class). Never changed by passes.
  final String? binding;

  /// The declaration's name in the native API when it differs from [name]
  /// (`SampleGreetW` for the Win32 function metadata calls `SampleGreet`).
  /// Emitters that produce the binding themselves use it.
  final String? native;
  final SourceLoc? loc;
  final String? docs;
  final Availability? availability;
  final List<Marker> markers;

  bool get isDropped => markers.any((m) => m.kind == MarkerKind.dropped);

  Decl copyWith({String? name, String? docs, List<Marker>? markers});

  Map<String, Object?> toJson();

  Map<String, Object?> _baseJson(String decl) => {
    'decl': decl,
    'id': id,
    'name': name,
    'platform': platform.name,
    if (binding != null) 'binding': binding,
    if (native != null) 'native': native,
    if (loc != null) 'loc': loc!.toJson(),
    if (docs != null) 'docs': docs,
    if (availability != null) 'availability': availability!.toJson(),
    if (markers.isNotEmpty) 'markers': [for (final m in markers) m.toJson()],
  };

  @override
  String toString() => jsonEncode(toJson());
}

/// A class, interface, protocol, struct, enum, opaque handle, typedef or
/// JS object type.
final class TypeDecl extends Decl {
  const TypeDecl({
    required super.id,
    required super.name,
    required super.platform,
    super.binding,
    super.native,
    required this.kind,
    this.members = const [],
    this.supertypes = const [],
    this.typeParams = const [],
    super.loc,
    super.docs,
    super.availability,
    super.markers,
  });

  factory TypeDecl.fromJson(Map<String, Object?> json) => TypeDecl(
    id: json['id'] as String,
    name: json['name'] as String,
    platform: _enumFromJson(Platform.values, json['platform']),
    binding: json['binding'] as String?,
    native: json['native'] as String?,
    kind: _enumFromJson(TypeKind.values, json['kind']),
    members: _listFromJson(json['members'], Member.fromJson),
    supertypes: _listFromJson(json['supertypes'], TypeRef.fromJson),
    typeParams: [...?(json['typeParams'] as List<Object?>?)?.cast<String>()],
    loc: _locFromJson(json['loc']),
    docs: json['docs'] as String?,
    availability: _availabilityFromJson(json['availability']),
    markers: _listFromJson(json['markers'], Marker.fromJson),
  );

  final TypeKind kind;
  final List<Member> members;
  final List<TypeRef> supertypes;
  final List<String> typeParams;

  @override
  TypeDecl copyWith({
    String? name,
    String? docs,
    List<Marker>? markers,
    List<Member>? members,
  }) => TypeDecl(
    id: id,
    name: name ?? this.name,
    platform: platform,
    binding: _rebind(binding, this.name, name),
    native: native,
    kind: kind,
    members: members ?? this.members,
    supertypes: supertypes,
    typeParams: typeParams,
    loc: loc,
    docs: docs ?? this.docs,
    availability: availability,
    markers: markers ?? this.markers,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson('type'),
    'kind': kind.name,
    if (typeParams.isNotEmpty) 'typeParams': typeParams,
    if (supertypes.isNotEmpty)
      'supertypes': [for (final s in supertypes) s.toJson()],
    if (members.isNotEmpty) 'members': [for (final m in members) m.toJson()],
  };
}

/// A free function (C, JavaScript module export, Kotlin top-level).
final class FunctionDecl extends Decl {
  const FunctionDecl({
    required super.id,
    required super.name,
    required super.platform,
    super.binding,
    super.native,
    this.params = const [],
    this.returns = TypeRef.void_,
    this.async = Async.none,
    super.loc,
    super.docs,
    super.availability,
    super.markers,
  });

  factory FunctionDecl.fromJson(Map<String, Object?> json) => FunctionDecl(
    id: json['id'] as String,
    name: json['name'] as String,
    platform: _enumFromJson(Platform.values, json['platform']),
    binding: json['binding'] as String?,
    native: json['native'] as String?,
    params: _listFromJson(json['params'], Param.fromJson),
    returns: json.containsKey('returns')
        ? TypeRef.fromJson(json['returns'] as Map<String, Object?>)
        : TypeRef.void_,
    async: json.containsKey('async')
        ? _enumFromJson(Async.values, json['async'])
        : Async.none,
    loc: _locFromJson(json['loc']),
    docs: json['docs'] as String?,
    availability: _availabilityFromJson(json['availability']),
    markers: _listFromJson(json['markers'], Marker.fromJson),
  );

  final List<Param> params;
  final TypeRef returns;
  final Async async;

  @override
  FunctionDecl copyWith({
    String? name,
    String? docs,
    List<Marker>? markers,
    List<Param>? params,
    TypeRef? returns,
    Async? async,
  }) => FunctionDecl(
    id: id,
    name: name ?? this.name,
    platform: platform,
    binding: _rebind(binding, this.name, name),
    native: native,
    params: params ?? this.params,
    returns: returns ?? this.returns,
    async: async ?? this.async,
    loc: loc,
    docs: docs ?? this.docs,
    availability: availability,
    markers: markers ?? this.markers,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson('function'),
    if (params.isNotEmpty) 'params': [for (final p in params) p.toJson()],
    if (returns.name != 'void') 'returns': returns.toJson(),
    if (async != Async.none) 'async': async.name,
  };
}

/// A global variable or constant.
final class VariableDecl extends Decl {
  const VariableDecl({
    required super.id,
    required super.name,
    required super.platform,
    super.binding,
    super.native,
    required this.type,
    this.value,
    this.isConst = false,
    super.loc,
    super.docs,
    super.availability,
    super.markers,
  });

  factory VariableDecl.fromJson(Map<String, Object?> json) => VariableDecl(
    id: json['id'] as String,
    name: json['name'] as String,
    platform: _enumFromJson(Platform.values, json['platform']),
    binding: json['binding'] as String?,
    native: json['native'] as String?,
    type: TypeRef.fromJson(json['type'] as Map<String, Object?>),
    value: json['value'] as String?,
    isConst: json['isConst'] as bool? ?? false,
    loc: _locFromJson(json['loc']),
    docs: json['docs'] as String?,
    availability: _availabilityFromJson(json['availability']),
    markers: _listFromJson(json['markers'], Marker.fromJson),
  );

  final TypeRef type;

  /// Literal value as written in the source, when known.
  final String? value;
  final bool isConst;

  @override
  VariableDecl copyWith({
    String? name,
    TypeRef? type,
    String? docs,
    List<Marker>? markers,
  }) => VariableDecl(
    id: id,
    name: name ?? this.name,
    platform: platform,
    binding: _rebind(binding, this.name, name),
    native: native,
    type: type ?? this.type,
    value: value,
    isConst: isConst,
    loc: loc,
    docs: docs ?? this.docs,
    availability: availability,
    markers: markers ?? this.markers,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson('variable'),
    'type': type.toJson(),
    if (value != null) 'value': value,
    if (isConst) 'isConst': true,
  };
}

/// The binding identifier after a rename from [oldName] to [newName]: the
/// existing [binding], else the old name once it no longer equals the name.
String? _rebind(String? binding, String oldName, String? newName) =>
    binding ?? (newName == null || newName == oldName ? null : oldName);

List<T> _listFromJson<T>(
  Object? json,
  T Function(Map<String, Object?>) fromJson,
) => [
  for (final item in (json as List<Object?>?) ?? const [])
    fromJson(item as Map<String, Object?>),
];

SourceLoc? _locFromJson(Object? json) =>
    json == null ? null : SourceLoc.fromJson(json as Map<String, Object?>);

Availability? _availabilityFromJson(Object? json) =>
    json == null ? null : Availability.fromJson(json as Map<String, Object?>);

/// Serializes a whole IR list the way `dump` and snapshot tests expect.
List<Map<String, Object?>> irToJson(List<Decl> decls) => [
  for (final d in decls) d.toJson(),
];

/// Inverse of [irToJson].
List<Decl> irFromJson(List<Object?> json) => [
  for (final item in json) Decl.fromJson(item as Map<String, Object?>),
];
