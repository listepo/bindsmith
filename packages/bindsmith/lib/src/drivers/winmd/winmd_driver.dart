/// winmd driver: reads Windows metadata through `package:winmd` 7 and lifts it
/// into the IR.
///
/// Unlike every other platform, Windows has no upstream generator to drive:
/// `package:winmd` is a reader, not a code generator, so bindsmith writes the
/// dart:ffi binding itself (`emit/win32.dart`). This file is the half that
/// turns metadata into IR; it does no I/O and knows nothing about Dart syntax.
///
/// What the metadata looks like, and what the driver depends on:
///
/// * free functions and constants are static members of a class named `Apis`,
///   one per namespace — `MetadataLookup` is what finds them;
/// * a function's `ImplMap` names the DLL that exports it and the exported
///   symbol, which is often the `W` suffixed twin of the metadata name;
/// * a handle (`HWND`, `HANDLE`) is a one-field struct tagged
///   `NativeTypedefAttribute`, and is flattened to that field's type;
/// * a COM interface is an `interface` TypeDef tagged `GuidAttribute` whose
///   single `InterfaceImpl` names the interface it extends, and whose methods
///   are declared in vtable order.
///
/// Mapping (metadata → IR):
///
/// | metadata                  | IR                                            |
/// |---------------------------|-----------------------------------------------|
/// | `Apis` method             | `FunctionDecl`, `native` = exported symbol,   |
/// |                           | `loc` = the DLL                               |
/// | `Apis` field              | `VariableDecl(isConst: true, value:)`         |
/// | struct                    | `TypeDecl(struct)` with `field` members       |
/// | native typedef struct     | `TypeDecl(typedef)`, target in `supertypes`   |
/// | enum                      | `TypeDecl(enumeration)`, `constant` members   |
/// | COM interface             | `TypeDecl(interface)`, `method` members in    |
/// |                           | vtable order, `IID` constant, base in         |
/// |                           | `supertypes`                                  |
///
/// `TypeRef.name` is the Dart-facing spelling and `TypeRef.native` the dart:ffi
/// one, exactly as the C driver records them.
library;

// `winmd` spells a metadata type reference `TypeRef` too; the IR's wins.
import 'package:winmd/winmd.dart' hide TypeRef;

import '../../ir/ir.dart' hide Param;
import '../../ir/ir.dart' as ir show Param;

/// The default library a covered symbol is re-exported from.
const win32Package = 'package:win32/win32.dart';

/// The `dropped` reason a symbol carries when [WinmdDriver.covered] said the
/// binding already exists in [library]. The emitter re-exports these instead of
/// generating them, and `bindsmith verify` lists them.
String reexportedFrom(String library) =>
    'already bound by $library; re-exported from there, not generated';

/// Reads Windows metadata and returns the IR of the requested symbols.
final class WinmdDriver {
  WinmdDriver({
    required this.index,
    this.functions = const {},
    this.constants = const {},
    this.types = const {},
    this.covered,
    this.library = win32Package,
    this.platform = Platform.windows,
  });

  /// The metadata to read. `WindowsMetadataLoader().loadWin32Metadata()`
  /// downloads and caches `Windows.Win32.winmd` from NuGet and returns one.
  final MetadataIndex index;

  /// Pull list of free functions, by their metadata name (`MessageBoxW`).
  final Set<String> functions;

  /// Pull list of constants, by their metadata name (`SAMPLE_MAX_NAME`).
  final Set<String> constants;

  /// Pull list of structs, enums and COM interfaces, by name. Types reached
  /// from an included signature are pulled in whether or not they are listed.
  final Set<String> types;

  /// Maps a metadata name to the identifier [library] already exports for it,
  /// or `null` when it does not. A covered symbol is described in the IR and
  /// marked `dropped`: the binding re-exports it rather than regenerating it.
  final String? Function(String name)? covered;

  /// Where a covered symbol is re-exported from.
  final String library;

  final Platform platform;

  /// Lifts the pull list, and everything it references, into IR.
  ///
  /// Throws [ArgumentError] naming any requested symbol the metadata does not
  /// declare — a typo in a pull list is a configuration error, not an empty
  /// result.
  List<Decl> load() => _Reader(this).read();
}

/// dart:ffi spellings of one metadata type: [native] goes in an `@Native<>` or
/// `Pointer<>` position, [dart] is the Dart-side type.
typedef _Ffi = ({String native, String dart});

const _primitives = <Type, _Ffi>{
  VoidType: (native: 'ffi.Void', dart: 'void'),
  BoolType: (native: 'ffi.Bool', dart: 'bool'),
  CharType: (native: 'ffi.Uint16', dart: 'int'),
  Int8Type: (native: 'ffi.Int8', dart: 'int'),
  Uint8Type: (native: 'ffi.Uint8', dart: 'int'),
  Int16Type: (native: 'ffi.Int16', dart: 'int'),
  Uint16Type: (native: 'ffi.Uint16', dart: 'int'),
  Int32Type: (native: 'ffi.Int32', dart: 'int'),
  Uint32Type: (native: 'ffi.Uint32', dart: 'int'),
  Int64Type: (native: 'ffi.Int64', dart: 'int'),
  Uint64Type: (native: 'ffi.Uint64', dart: 'int'),
  Float32Type: (native: 'ffi.Float', dart: 'double'),
  Float64Type: (native: 'ffi.Double', dart: 'double'),
  IntPtrType: (native: 'ffi.IntPtr', dart: 'int'),
  UintPtrType: (native: 'ffi.UintPtr', dart: 'int'),
};

final class _Reader {
  _Reader(this.driver) : lookup = MetadataLookup(driver.index);

  final WinmdDriver driver;
  final MetadataLookup lookup;

  /// Types reached from an included signature, keyed by metadata name.
  final pending = <String, TypeDef>{};
  final seen = <String>{};

  List<Decl> read() {
    final decls = <Decl>[
      for (final name in driver.functions) _function(name, _find(name)),
      for (final name in driver.constants) _constant(name, _findConstant(name)),
    ];
    for (final name in driver.types) {
      pending.putIfAbsent(name, () => _findType(name));
    }
    // Each type can reference further types, so drain rather than iterate.
    while (pending.isNotEmpty) {
      final name = pending.keys.first;
      final type = pending.remove(name)!;
      if (!seen.add(name)) continue;
      if (_type(type) case final decl?) decls.add(decl);
    }
    // `MetadataIndex` is hash-ordered; the output must not be.
    return decls..sort((a, b) => a.id.compareTo(b.id));
  }

  MethodDef _find(String name) =>
      lookup.tryFindFunctionByName(name) ??
      (throw ArgumentError.value(
        name,
        'functions',
        'not declared in the metadata',
      ));

  Field _findConstant(String name) =>
      lookup.tryFindConstantByName(name) ??
      (throw ArgumentError.value(
        name,
        'constants',
        'not declared in the metadata',
      ));

  TypeDef _findType(String name) =>
      switch (lookup.findTypesByName(name).toList()) {
        [final only] => only,
        [] => throw ArgumentError.value(
          name,
          'types',
          'not declared in the metadata',
        ),
        final many => throw ArgumentError.value(
          name,
          'types',
          'declared in ${many.length} namespaces '
              '(${many.map((t) => t.namespace).join(', ')}); '
              'bindsmith needs one',
        ),
      };

  // ---------------------------------------------------------------- functions

  /// Signature types paired with the `Param` rows that name them. Sequence 0 is
  /// the return value, and a parameter row can be missing entirely.
  List<ir.Param> _params(MethodDef method, List<String> refused) => [
    for (final (i, type) in method.signature.types.indexed)
      ir.Param(
        method.params
                .where((p) => p.sequence == i + 1)
                .map((p) => p.name)
                .firstOrNull
                ?.ifEmpty('arg$i') ??
            'arg$i',
        _ref(type, refused),
      ),
  ];

  FunctionDecl _function(String name, MethodDef method) {
    final id = '${method.parent.namespace}.$name';
    final export = driver.covered?.call(name);
    final refused = <String>[];
    return FunctionDecl(
      id: id,
      name: name,
      platform: driver.platform,
      binding: export,
      native: method.implMap?.importName,
      params: _params(method, refused),
      returns: _ref(method.signature.returnType, refused),
      loc: SourceLoc(method.implMap?.importScope.name ?? id),
      docs: _docs(method),
      markers: [
        if (export != null) Marker.dropped(reexportedFrom(driver.library)),
        for (final reason in refused) Marker.dropped(reason),
      ],
    );
  }

  VariableDecl _constant(String name, Field field) {
    final refused = <String>[];
    return VariableDecl(
      id: '${field.parent.namespace}.$name',
      name: name,
      platform: driver.platform,
      type: _ref(field.signature, refused),
      value: _literal(field.constant?.value),
      isConst: true,
      loc: SourceLoc(field.parent.namespace),
      docs: _docs(field),
      markers: [for (final reason in refused) Marker.dropped(reason)],
    );
  }

  // -------------------------------------------------------------------- types

  TypeDecl? _type(TypeDef type) => switch (type.category) {
    TypeCategory.enum$ => _enum(type),
    TypeCategory.struct when _nativeTypedef(type) != null => _typedef(type),
    TypeCategory.struct => _struct(type),
    TypeCategory.interface => _interface(type),
    // A metadata class that is not `Apis` is a WinRT runtime class, and a
    // delegate or attribute is not part of any binding surface.
    _ => null,
  };

  /// The single field of a `NativeTypedefAttribute` struct — the type a handle
  /// really is.
  Field? _nativeTypedef(TypeDef type) =>
      type.hasAttribute('NativeTypedefAttribute') && type.fields.length == 1
      ? type.fields.single
      : null;

  TypeDecl _typedef(TypeDef type) {
    final refused = <String>[];
    return TypeDecl(
      id: '${type.namespace}.${type.name}',
      name: type.name,
      platform: driver.platform,
      kind: TypeKind.typedef,
      supertypes: [_ref(_nativeTypedef(type)!.signature, refused)],
      loc: SourceLoc(type.namespace),
      docs: _docs(type),
      markers: [for (final reason in refused) Marker.dropped(reason)],
    );
  }

  TypeDecl _struct(TypeDef type) {
    final refused = <String>[];
    return TypeDecl(
      id: '${type.namespace}.${type.name}',
      name: type.name,
      platform: driver.platform,
      kind: TypeKind.struct,
      members: [
        for (final field in type.fields)
          Member(
            field.name,
            kind: MemberKind.field,
            returns: _ref(field.signature, refused),
            docs: _docs(field),
          ),
      ],
      loc: SourceLoc(type.namespace),
      docs: _docs(type),
      markers: [for (final reason in refused) Marker.dropped(reason)],
    );
  }

  TypeDecl _enum(TypeDef type) {
    // The first field of an enum carries its underlying integral type; the
    // rest are the values.
    final storage = _spell(type.fields.first.signature);
    return TypeDecl(
      id: '${type.namespace}.${type.name}',
      name: type.name,
      platform: driver.platform,
      kind: TypeKind.enumeration,
      members: [
        for (final field in type.fields.skip(1))
          Member(
            field.name,
            kind: MemberKind.constant,
            returns: const TypeRef('int'),
            value: _literal(field.constant?.value),
            docs: _docs(field),
          ),
      ],
      supertypes: [TypeRef('int', native: storage?.native)],
      loc: SourceLoc(type.namespace),
      docs: _docs(type),
      markers: const [
        Marker(
          MarkerKind.verify,
          'Win32 enum: the binding passes and stores it as its underlying '
          'integer, and the facade lifts it',
        ),
      ],
    );
  }

  TypeDecl _interface(TypeDef type) {
    final refused = <String>[];
    final base = type.interfaceImpls.firstOrNull?.interface.name ?? 'IUnknown';
    final iid = _guid(type);
    return TypeDecl(
      id: '${type.namespace}.${type.name}',
      name: type.name,
      platform: driver.platform,
      kind: TypeKind.interface,
      supertypes: [TypeRef(base)],
      members: [
        if (iid != null)
          Member(
            'IID',
            kind: MemberKind.constant,
            returns: const TypeRef('String'),
            value: "'$iid'",
            isStatic: true,
          ),
        for (final method in type.methods)
          Member(
            method.name,
            kind: MemberKind.method,
            params: _params(method, refused),
            returns: _ref(method.signature.returnType, refused),
            docs: _docs(method),
          ),
      ],
      loc: SourceLoc(type.namespace),
      docs: _docs(type),
      markers: [
        if (iid == null)
          const Marker.verify('no GuidAttribute: the IID has to be supplied'),
        for (final reason in refused) Marker.dropped(reason),
        const Marker(
          MarkerKind.verify,
          'COM: methods are called through the vtable in declaration order, '
          'and an HRESULT return is not checked by the binding',
        ),
      ],
    );
  }

  /// `GuidAttribute(a, b, c, d0…d7)` as `{aaaaaaaa-bbbb-cccc-d0d1-d2…d7}`.
  String? _guid(TypeDef type) {
    final args = type.tryFindAttribute('GuidAttribute')?.fixedArgs;
    if (args == null || args.length != 11) return null;
    final parts = [for (final arg in args) arg.valueAsInt ?? 0];
    String hex(int value, int digits) =>
        value.toRadixString(16).padLeft(digits, '0');
    return '{${hex(parts[0], 8)}-${hex(parts[1], 4)}-${hex(parts[2], 4)}-'
        '${parts.sublist(3, 5).map((b) => hex(b, 2)).join()}-'
        '${parts.sublist(5).map((b) => hex(b, 2)).join()}}';
  }

  // -------------------------------------------------------------------- types

  /// A metadata type as an IR reference, recording anything it reaches.
  ///
  /// A type with no dart:ffi spelling is not silently replaced: its reason is
  /// appended to [refused] and becomes a `dropped` marker on the declaration.
  TypeRef _ref(MetadataType type, List<String> refused) {
    final ffi = _spell(type);
    if (ffi == null) {
      refused.add('$type has no dart:ffi spelling');
      return TypeRef('void', native: 'ffi.Void');
    }
    return TypeRef(ffi.dart, native: ffi.native);
  }

  /// The dart:ffi spelling of [type], or `null` when it has none.
  _Ffi? _spell(MetadataType type) {
    if (_primitives[type.runtimeType] case final primitive?) return primitive;
    return switch (type) {
      MutablePointerType(:final pointee, :final depth) ||
      ConstPointerType(
        :final pointee,
        :final depth,
      ) => _pointer(pointee, depth),
      ArrayReferenceType(:final element) => _pointer(element, 1),
      FixedArrayType(:final element, :final length) => switch (_spell(
        element,
      )) {
        final e? => (
          native: 'ffi.Array<${e.native}>($length)',
          dart: 'ffi.Array<${e.native}>',
        ),
        null => null,
      },
      // A COM interface is passed as a pointer to its vtable, the way
      // `package:win32` spells it.
      NamedClassType() =>
        _use(type.name) == null
            ? null
            : (native: 'VTablePointer', dart: 'VTablePointer'),
      NamedValueType() => _named(type.name),
      _ => null,
    };
  }

  _Ffi? _pointer(MetadataType pointee, int depth) {
    // `void*` is `Pointer<Void>`, and every extra level of indirection wraps.
    final inner = _spell(pointee);
    if (inner == null) return null;
    var spelling = inner.native;
    for (var i = 0; i < depth; i++) {
      spelling = 'ffi.Pointer<$spelling>';
    }
    return (native: spelling, dart: spelling);
  }

  /// A struct, enum or handle by name, pulling its declaration in.
  _Ffi? _named(String name) {
    final type = _use(name);
    if (type == null) return null;
    return switch (type.category) {
      // A handle is its underlying type; nothing in the binding wants a
      // one-field wrapper struct.
      TypeCategory.struct when _nativeTypedef(type) != null => (
        native: name,
        dart: _spell(_nativeTypedef(type)!.signature)?.dart ?? 'int',
      ),
      TypeCategory.struct => (native: name, dart: name),
      // The binding is int-typed at the boundary; see the enum's marker.
      TypeCategory.enum$ => (
        native: _spell(type.fields.first.signature)?.native ?? 'ffi.Int32',
        dart: 'int',
      ),
      _ => null,
    };
  }

  /// Records that [name] is reachable, and returns its declaration.
  TypeDef? _use(String name) {
    final types = driver.index.readers.isEmpty
        ? const <TypeDef>[]
        : lookup.findTypesByName(name).toList();
    if (types.length != 1) return null;
    if (!seen.contains(name)) pending.putIfAbsent(name, () => types.single);
    return types.single;
  }
}

/// `DocumentationAttribute` holds the learn.microsoft.com URL for the
/// declaration, which is the only prose Windows metadata carries.
String? _docs(HasCustomAttributes row) =>
    switch (row.attributeAsString('DocumentationAttribute')) {
      null || '' => null,
      final url => 'To learn more, see <$url>.',
    };

String? _literal(MetadataValue? value) => switch (value) {
  null => null,
  Utf8StringValue(:final value) || Utf16StringValue(:final value) => "'$value'",
  BoolValue(:final value) => '$value',
  Float32Value(:final value) || Float64Value(:final value) => '$value',
  CharValue(:final value) ||
  Int8Value(:final value) ||
  Uint8Value(:final value) ||
  Int16Value(:final value) ||
  Uint16Value(:final value) ||
  Int32Value(:final value) ||
  Uint32Value(:final value) ||
  Int64Value(:final value) ||
  Uint64Value(:final value) => '$value',
  _ => null,
};

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
