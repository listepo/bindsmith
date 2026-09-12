/// A miniature Win32 metadata assembly, written with `package:winmd`'s own
/// [MetadataWriter].
///
/// The real input for the winmd driver is `Windows.Win32.winmd`, a ~10 MB NuGet
/// asset that cannot be committed and cannot be downloaded in CI. Writing the
/// fixture instead of shipping a binary keeps the input readable, keeps it in
/// the language the driver is tested in, and costs a few milliseconds.
///
/// The shape mirrors what `win32metadata` actually emits, because the driver
/// depends on every one of these conventions:
///
/// * free functions and constants live as static members of a class named
///   `Apis`, one per namespace (this is how `MetadataLookup` finds them);
/// * each function carries an `ImplMap` naming the DLL that exports it;
/// * a handle is a one-field struct tagged `NativeTypedefAttribute`;
/// * a COM interface is an `interface` TypeDef tagged `GuidAttribute` whose
///   `InterfaceImpl` names its base, and whose methods are in vtable order.
library;

import 'dart:typed_data';

// The reader and the writer spell the coded indexes with the same class
// names; the builder wants the writer's.
import 'package:winmd/winmd.dart'
    hide
        CustomAttributeType,
        HasConstant,
        HasCustomAttribute,
        MemberRefParent,
        TypeDefOrRef;
import 'package:winmd/writer.dart';

/// The namespace every fixture declaration lives in.
const sampleNamespace = 'Bindsmith.Sample';

/// `{6f9b1a2c-3d4e-4f50-8a61-b2c3d4e5f607}` — the fixture interface's IID.
const sampleGuid = [
  0x6f9b1a2c,
  0x3d4e,
  0x4f50,
  0x8a,
  0x61,
  0xb2,
  0xc3,
  0xd4,
  0xe5,
  0xf6,
  0x07,
];

/// Builds the fixture assembly and returns it as a `.winmd` byte string.
///
/// Deterministic: the same bytes on every run and every host.
Uint8List sampleWinmd() => _write().toBytes();

/// The fixture assembly, indexed and ready for [MetadataIndex] consumers.
MetadataIndex sampleIndex() =>
    MetadataIndex.fromReader(MetadataReader.read(sampleWinmd()));

final _publicStaticLiteral =
    FieldAttributes.public |
    FieldAttributes.static |
    FieldAttributes.literal |
    FieldAttributes.hasDefault;

final _publicStaticMethod =
    MethodAttributes.public |
    MethodAttributes.static |
    MethodAttributes.hideBySig |
    MethodAttributes.pinvokeImpl;

final _comMethod =
    MethodAttributes.public |
    MethodAttributes.hideBySig |
    MethodAttributes.newSlot |
    MethodAttributes.virtual |
    MethodAttributes.abstract;

MetadataWriter _write() {
  final writer = MetadataWriter(
    name: 'Bindsmith.Sample.winmd',
    flags: const AssemblyFlags(0),
    // Rule 6: an omitted module version id is randomly generated, which would
    // make the assembly differ byte for byte between runs.
    mvid: Guid(
      sampleGuid[0],
      sampleGuid[1],
      sampleGuid[2],
      Uint8List.fromList(sampleGuid.sublist(3)),
    ),
  );

  final valueType = TypeDefOrRef.typeRef(
    writer.writeTypeRef(namespace: 'System', name: 'ValueType'),
  );
  final enumType = TypeDefOrRef.typeRef(
    writer.writeTypeRef(namespace: 'System', name: 'Enum'),
  );
  final objectType = TypeDefOrRef.typeRef(
    writer.writeTypeRef(namespace: 'System', name: 'Object'),
  );

  _apis(writer, objectType);
  _flags(writer, enumType);
  _handle(writer, valueType);
  _options(writer, valueType);
  _greeter(writer);

  return writer;
}

/// `Bindsmith.Sample.Apis` — where the free functions and constants live.
void _apis(MetadataWriter writer, TypeDefOrRef objectType) {
  // Rows written after this one belong to it: the writer appends fields and
  // methods to the type definition it is currently building.
  writer.writeTypeDef(
    namespace: sampleNamespace,
    name: 'Apis',
    flags:
        TypeAttributes.public | TypeAttributes.abstract | TypeAttributes.sealed,
    extends$: objectType,
  );

  final maxName = writer.writeField(
    name: 'SAMPLE_MAX_NAME',
    signature: const Uint32Type(),
    flags: _publicStaticLiteral,
  );
  writer.writeConstant(
    parent: HasConstant.field(maxName),
    value: const Uint32Value(64),
  );

  // Covered by `package:win32`, which exports it as `MessageBox`.
  final messageBox = writer.writeMethodDef(
    name: 'MessageBoxW',
    flags: _publicStaticMethod,
    signature: const MethodSignature(
      returnType: Int32Type(),
      types: [
        IntPtrType(),
        MutablePointerType(Uint16Type(), 1),
        MutablePointerType(Uint16Type(), 1),
        Uint32Type(),
      ],
    ),
  );
  writer
    ..writeParam(sequence: 1, name: 'hWnd', flags: ParamAttributes.in$)
    ..writeParam(sequence: 2, name: 'lpText', flags: ParamAttributes.in$)
    ..writeParam(sequence: 3, name: 'lpCaption', flags: ParamAttributes.in$)
    ..writeParam(sequence: 4, name: 'uType', flags: ParamAttributes.in$)
    ..writeImplMap(
      method: messageBox,
      importName: 'MessageBoxW',
      importScope: 'user32.dll',
    );

  final greet = writer.writeMethodDef(
    name: 'SampleGreet',
    flags: _publicStaticMethod,
    signature: const MethodSignature(
      returnType: Uint32Type(),
      types: [
        MutablePointerType(
          NamedValueType(TypeName(sampleNamespace, 'SampleOptions')),
          1,
        ),
        MutablePointerType(Uint16Type(), 1),
        Uint32Type(),
      ],
    ),
  );
  writer
    ..writeParam(sequence: 1, name: 'options', flags: ParamAttributes.in$)
    ..writeParam(sequence: 2, name: 'buffer', flags: ParamAttributes.out)
    ..writeParam(sequence: 3, name: 'cch', flags: ParamAttributes.in$)
    ..writeImplMap(
      method: greet,
      importName: 'SampleGreetW',
      importScope: 'sample.dll',
    );
  _document(
    writer,
    HasCustomAttribute.methodDef(greet),
    'sample/nf-samplegreet',
  );

  final version = writer.writeMethodDef(
    name: 'SampleGetVersion',
    flags: _publicStaticMethod,
    signature: const MethodSignature(returnType: Uint32Type()),
  );
  writer.writeImplMap(
    method: version,
    importName: 'SampleGetVersion',
    importScope: 'sample.dll',
  );

  // No dart:ffi spelling: the driver must refuse it rather than lose it.
  final box = writer.writeMethodDef(
    name: 'SampleBox',
    flags: _publicStaticMethod,
    signature: const MethodSignature(
      returnType: Int32Type(),
      types: [ObjectType()],
    ),
  );
  writer
    ..writeParam(sequence: 1, name: 'value', flags: ParamAttributes.in$)
    ..writeImplMap(
      method: box,
      importName: 'SampleBox',
      importScope: 'sample.dll',
    );
}

/// `Bindsmith.Sample.SampleFlags` — a Win32 enum over `Uint32`.
void _flags(MetadataWriter writer, TypeDefOrRef enumType) {
  final flags = writer.writeTypeDef(
    namespace: sampleNamespace,
    name: 'SampleFlags',
    flags: TypeAttributes.public | TypeAttributes.sealed,
    extends$: enumType,
  );
  _document(
    writer,
    HasCustomAttribute.typeDef(flags),
    'sample/ne-sample-sampleflags',
  );
  // The first field of an enum carries its underlying integral type.
  writer.writeField(
    name: 'value__',
    signature: const Uint32Type(),
    flags:
        FieldAttributes.private |
        FieldAttributes.specialName |
        FieldAttributes.rtSpecialName,
  );
  for (final (name, value) in const [
    ('SAMPLE_QUIET', 0),
    ('SAMPLE_NORMAL', 1),
    ('SAMPLE_LOUD', 2),
  ]) {
    final field = writer.writeField(
      name: name,
      signature: const NamedValueType(TypeName(sampleNamespace, 'SampleFlags')),
      flags: _publicStaticLiteral,
    );
    writer.writeConstant(
      parent: HasConstant.field(field),
      value: Uint32Value(value),
    );
  }
}

/// `Bindsmith.Sample.SampleHandle` — a handle, i.e. a tagged one-field struct.
void _handle(MetadataWriter writer, TypeDefOrRef valueType) {
  final handle = writer.writeTypeDef(
    namespace: sampleNamespace,
    name: 'SampleHandle',
    flags:
        TypeAttributes.public |
        TypeAttributes.sealed |
        TypeAttributes.sequentialLayout,
    extends$: valueType,
  );
  writer
    ..writeField(
      name: 'Value',
      signature: const IntPtrType(),
      flags: FieldAttributes.public,
    )
    ..writeCustomAttribute(
      parent: HasCustomAttribute.typeDef(handle),
      type: _attributeCtor(writer, 'NativeTypedefAttribute'),
    );
}

/// `Bindsmith.Sample.SampleOptions` — a struct with an enum field, a pointer
/// field, a handle field and an inline array.
void _options(MetadataWriter writer, TypeDefOrRef valueType) {
  final options = writer.writeTypeDef(
    namespace: sampleNamespace,
    name: 'SampleOptions',
    flags:
        TypeAttributes.public |
        TypeAttributes.sealed |
        TypeAttributes.sequentialLayout,
    extends$: valueType,
  );
  _document(
    writer,
    HasCustomAttribute.typeDef(options),
    'sample/ns-sample-sampleoptions',
  );
  for (final (name, type) in const <(String, MetadataType)>[
    ('Flags', NamedValueType(TypeName(sampleNamespace, 'SampleFlags'))),
    ('Length', Uint32Type()),
    ('Caller', NamedValueType(TypeName(sampleNamespace, 'SampleHandle'))),
    ('Prefix', FixedArrayType(Uint16Type(), 16)),
  ]) {
    writer.writeField(
      name: name,
      signature: type,
      flags: FieldAttributes.public,
    );
  }
}

/// `Bindsmith.Sample.ISampleGreeter` — a COM interface over `IUnknown`.
void _greeter(MetadataWriter writer) {
  final greeter = writer.writeTypeDef(
    namespace: sampleNamespace,
    name: 'ISampleGreeter',
    flags:
        TypeAttributes.public |
        TypeAttributes.interface |
        TypeAttributes.abstract,
  );
  writer
    ..writeInterfaceImpl(
      class$: greeter,
      interface: const NamedClassType(
        TypeName('Windows.Win32.System.Com', 'IUnknown'),
      ),
    )
    ..writeCustomAttribute(
      parent: HasCustomAttribute.typeDef(greeter),
      type: _attributeCtor(
        writer,
        'GuidAttribute',
        types: const [
          Uint32Type(),
          Uint16Type(),
          Uint16Type(),
          Uint8Type(),
          Uint8Type(),
          Uint8Type(),
          Uint8Type(),
          Uint8Type(),
          Uint8Type(),
          Uint8Type(),
          Uint8Type(),
        ],
      ),
      fixedArgs: [
        FixedArg(Uint32Value(sampleGuid[0])),
        FixedArg(Uint16Value(sampleGuid[1])),
        FixedArg(Uint16Value(sampleGuid[2])),
        for (final byte in sampleGuid.skip(3)) FixedArg(Uint8Value(byte)),
      ],
    )
    ..writeMethodDef(
      name: 'Greet',
      flags: _comMethod,
      signature: const MethodSignature(
        returnType: Int32Type(),
        types: [
          MutablePointerType(Uint16Type(), 1),
          MutablePointerType(Int32Type(), 1),
        ],
      ),
    )
    ..writeParam(sequence: 1, name: 'name', flags: ParamAttributes.in$)
    ..writeParam(sequence: 2, name: 'written', flags: ParamAttributes.out)
    ..writeMethodDef(
      name: 'GetVersion',
      flags: _comMethod,
      signature: const MethodSignature(
        returnType: Int32Type(),
        types: [MutablePointerType(Uint32Type(), 1)],
      ),
    )
    ..writeParam(sequence: 1, name: 'value', flags: ParamAttributes.out);
  _document(
    writer,
    HasCustomAttribute.typeDef(greeter),
    'sample/nn-sample-isamplegreeter',
  );
}

/// Tags [parent] with the learn.microsoft.com URL Windows metadata carries
/// instead of prose.
void _document(MetadataWriter writer, HasCustomAttribute parent, String page) =>
    writer.writeCustomAttribute(
      parent: parent,
      type: _attributeCtor(
        writer,
        'DocumentationAttribute',
        types: const [StringType()],
      ),
      fixedArgs: [
        FixedArg(Utf8StringValue('https://learn.microsoft.com/$page')),
      ],
    );

/// A `MemberRef` to `<name>..ctor`, which is how an attribute is identified.
///
/// The reader decodes an attribute's arguments against this constructor's
/// signature, so [types] has to list them: get it wrong and the blob is parsed
/// as garbage rather than rejected.
CustomAttributeType _attributeCtor(
  MetadataWriter writer,
  String name, {
  List<MetadataType> types = const [],
}) => CustomAttributeType.memberRef(
  writer.writeMemberRef(
    parent: MemberRefParent.typeRef(
      writer.writeTypeRef(
        namespace: 'Windows.Win32.Foundation.Metadata',
        name: name,
      ),
    ),
    name: '.ctor',
    signature: MemberRefSignature.method(types: types),
  ),
);
