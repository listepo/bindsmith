import 'package:bindsmith/src/ir/ir.dart';
import 'package:bindsmith/src/passes/passes.dart';
import 'package:test/test.dart';

const _p = Platform.macos;
const _dropped = [Marker.dropped('not in include list')];

TypeDecl _type(
  String name, {
  TypeKind kind = TypeKind.klass,
  List<Member> members = const [],
  List<TypeRef> supertypes = const [],
  bool dropped = false,
}) => TypeDecl(
  id: name,
  name: name,
  platform: _p,
  kind: kind,
  members: members,
  supertypes: supertypes,
  markers: dropped ? _dropped : const [],
);

Member _method(String name, TypeRef returns, [List<Param> params = const []]) =>
    Member(name, kind: MemberKind.method, params: params, returns: returns);

TypeDecl _byName(List<Decl> decls, String name) =>
    decls.whereType<TypeDecl>().firstWhere((d) => d.name == name);

void main() {
  group('referencedTypesPass', () {
    final decls = <Decl>[
      _type(
        'Window',
        members: [
          _method('contentView', const TypeRef('View')),
          _method('style', const TypeRef('Style')),
          _method('frame', const TypeRef('Rect')),
          _method('measure', const TypeRef('void'), [
            const Param(
              'm',
              TypeRef('Measurement', nullability: Nullability.nullable),
            ),
          ]),
        ],
      ),
      _type(
        'View',
        dropped: true,
        members: [_method('draw', const TypeRef('void'))],
      ),
      _type('Measurement', dropped: true),
      _type('Style', kind: TypeKind.enumeration, dropped: true),
      _type('Unrelated', dropped: true),
      _type(
        'Rect',
        kind: TypeKind.typedef,
        dropped: true,
        supertypes: [const TypeRef('CGRect')],
      ),
    ];
    final out = referencedTypesPass()(decls);

    test('restores a referenced class as a shell without members', () {
      final view = _byName(out, 'View');
      expect(view.isDropped, isFalse);
      expect(view.members, isEmpty);
      expect(
        view.markers.map((m) => m.reason),
        contains(contains('opaque handle')),
      );
    });

    test('restores a referenced stub reached through a nullable parameter', () {
      expect(_byName(out, 'Measurement').isDropped, isFalse);
    });

    test('restores a referenced enumeration whole', () {
      expect(_byName(out, 'Style').isDropped, isFalse);
    });

    test('leaves unreferenced types dropped', () {
      expect(_byName(out, 'Unrelated').isDropped, isTrue);
    });

    test('rewrites a typedef reference to its target', () {
      final frame = _byName(
        out,
        'Window',
      ).members.firstWhere((m) => m.name == 'frame');
      expect(frame.returns.name, 'CGRect');
      expect(_byName(out, 'Rect').isDropped, isTrue);
    });

    test('keeps the order and count of declarations', () {
      expect(out.map((d) => d.name), decls.map((d) => d.name));
    });
  });

  group('facadeSpellablePass', () {
    Member dropped(List<Decl> out, String name) =>
        _byName(out, 'Window').members.firstWhere((m) => m.name == name);

    final out = facadeSpellablePass()([
      _type(
        'Window',
        members: [
          _method('ok', const TypeRef('int')),
          _method(
            'session',
            const TypeRef('Pointer', args: [TypeRef('_Session')]),
          ),
          _method('each', const TypeRef('void'), [
            const Param(
              'block',
              TypeRef(
                'ObjCBlock',
                args: [TypeRef('ffi.Void Function(Window)')],
              ),
            ),
          ]),
          _method('plain', const TypeRef('void'), [
            const Param(
              'block',
              TypeRef(
                'ObjCBlock',
                args: [TypeRef('ffi.Void Function(NSError?)')],
              ),
            ),
          ]),
        ],
      ),
    ]);

    test('drops a type private to the binding library, with a reason', () {
      final m = dropped(out, 'session');
      expect(m.markers.single.kind, MarkerKind.dropped);
      expect(m.markers.single.reason, contains('_Session'));
    });

    test('drops a callback that mentions a facade-wrapped type', () {
      expect(dropped(out, 'each').markers.single.reason, contains('Window'));
    });

    test('keeps members the facade can spell', () {
      expect(dropped(out, 'ok').markers, isEmpty);
      expect(dropped(out, 'plain').markers, isEmpty);
    });
  });
}
