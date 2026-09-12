import 'package:bindsmith/src/ir/ir.dart';
import 'package:bindsmith/src/passes/glib_macros.dart';
import 'package:test/test.dart';

const _platform = Platform.linux;

List<String> verifyReasons(Iterable<Marker> markers) => [
  for (final m in markers)
    if (m.kind == MarkerKind.verify) m.reason,
];

void main() {
  group('glibMacroPass', () {
    test('marks GObject cast macros', () {
      final out = glibMacroPass()([
        const FunctionDecl(
          id: 'G_OBJECT',
          name: 'G_OBJECT',
          platform: _platform,
        ),
      ]);
      expect(verifyReasons(out.single.markers), [
        contains('GObject cast macro'),
      ]);
    });

    test('marks g_object_new varargs', () {
      final out = glibMacroPass()([
        const FunctionDecl(
          id: 'g_object_new',
          name: 'g_object_new',
          platform: _platform,
        ),
      ]);
      expect(verifyReasons(out.single.markers), [contains('variadic')]);
    });

    test('leaves ordinary functions alone', () {
      final out = glibMacroPass()([
        const FunctionDecl(
          id: 'geometry_point_distance',
          name: 'geometry_point_distance',
          platform: _platform,
        ),
      ]);
      expect(out.single.markers, isEmpty);
    });

    test('does not add a second marker when one is already present', () {
      final fn = FunctionDecl(
        id: 'G_OBJECT',
        name: 'G_OBJECT',
        platform: _platform,
        markers: const [Marker.verify('already reviewed')],
      );
      final out = glibMacroPass()([fn]);
      expect(out.single.markers, hasLength(2));
    });
  });
}
