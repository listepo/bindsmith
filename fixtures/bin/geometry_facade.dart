/// Calls the generated C facade for real.
///
/// Marshalling is the part of a binding that a compiler cannot check: an arena
/// copy freed too early, a `Pointer<Char>` read as UTF-16, an enum passed as
/// its index instead of its value, a struct laid out with the wrong field
/// offsets all compile and then return nonsense. So the facade is exercised
/// against a real `libgeometry`, built from `fixtures/c/geometry/geometry.c`.
///
/// Usage: `dart run fixtures/bin/geometry_facade.dart <path to libgeometry>`.
/// Run by `packages/bindsmith/test/emit/facade_c_test.dart`, which builds the
/// library first and skips where no C compiler is available.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:bindsmith_fixtures/generated/geometry/geometry_facade.g.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: geometry_facade.dart <path to libgeometry>');
    exit(64);
  }
  // `@Native` resolves through the asset id, then a registered resolver, then
  // the process — and opening the library puts its symbols in the process.
  DynamicLibrary.open(args.single);

  // A String argument: the facade allocates a UTF-8 copy in an arena, and the
  // library reports the length it actually received.
  _expect(geometry_log('héllo'), 6, 'geometry_log byte length');

  // A String result: a `const char *` the library owns, copied out.
  _expect(geometry_shape_name(Shape.SHAPE_CIRCLE), 'circle', 'circle name');
  _expect(geometry_shape_name(Shape.SHAPE_TRIANGLE), 'triangle', 'enum value');

  // A struct built in Dart, passed by value.
  final a = Point(x: 3, y: 4);
  final b = Point(x: 0, y: 0);
  _expect(geometry_distance(a, b), 5.0, 'a struct crosses by value');

  // The same struct passed by pointer, through an arena the facade opens and
  // closes around the call. The library writes through that pointer, so the
  // copy is read back into the caller's object before the arena frees it.
  geometry_scale(a, 2);
  _expect(a.x, 6.0, 'an out-parameter is written back into the caller');
  _expect(geometry_distance(a, b), 10.0, 'the whole struct came back');
  a
    ..x = 6
    ..y = 8;
  _expect(geometry_distance(a, b), 10.0, 'a field setter reaches the struct');

  // A nested struct: assignment copies in, reading gives a view out.
  final rect = Rect(origin: a, width: 2, height: 5);
  _expect(geometry_rect_area(rect), 10.0, 'a nested struct is laid out right');
  rect.origin.x = 1;
  _expect(rect.origin.x, 1.0, 'a struct field is a view into its container');
  _expect(a.x, 6.0, 'assigning a struct field copies it');

  // An opaque handle: created, used and released through `dispose`.
  final scene = geometry_scene_new();
  _expect(geometry_scene_count(scene), 0, 'a new scene is empty');
  _expect(geometry_scene_add(scene, Shape.SHAPE_SQUARE, a), 1, 'first id');
  _expect(geometry_scene_count(scene), 1, 'the shape was added');
  _expect(geometry_max_shapes, 8, 'the global reads back');
  scene.dispose();

  print('ok: strings, enums, structs and handles cross the C boundary');
}

void _expect(Object? actual, Object? expected, String what) {
  if (actual != expected) {
    throw StateError('$what: got $actual, expected $expected');
  }
}
