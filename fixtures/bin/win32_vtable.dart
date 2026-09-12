/// Checks that the generated COM vtable has the layout COM requires.
///
/// A COM call is an index into a function-pointer table: `QueryInterface` is
/// slot 0, `AddRef` slot 1, `Release` slot 2, and an interface's own methods
/// follow in declaration order. Get that wrong and the call jumps to the wrong
/// function, which is a memory-corruption bug rather than a compile error — so
/// the generated struct is filled with known addresses here and read back.
///
/// Run by `packages/bindsmith/test/drivers/winmd_test.dart`; it exits non-zero
/// with a message when a slot moves. Nothing here is Windows-specific: the
/// layout is dart:ffi struct arithmetic, so it runs on any host.
library;

import 'dart:ffi';

import 'package:bindsmith_fixtures/generated/win32/sample.g.dart';
import 'package:ffi/ffi.dart';

void main() {
  const slots = 5;
  const base = 0x1000;
  final table = calloc<IntPtr>(slots);
  try {
    for (var i = 0; i < slots; i++) {
      table[i] = base + i;
    }
    final vtable = table.cast<ISampleGreeterVtbl>().ref;
    final actual = {
      'QueryInterface': vtable.base$.QueryInterface.address,
      'AddRef': vtable.base$.AddRef.address,
      'Release': vtable.base$.Release.address,
      'Greet': vtable.Greet.address,
      'GetVersion': vtable.GetVersion.address,
    };
    final expected = {
      'QueryInterface': base,
      'AddRef': base + 1,
      'Release': base + 2,
      'Greet': base + 3,
      'GetVersion': base + 4,
    };
    for (final MapEntry(key: name, value: want) in expected.entries) {
      final got = actual[name];
      if (got != want) {
        throw StateError(
          '$name is at vtable slot ${(got! - base)}, expected ${want - base}',
        );
      }
    }
    final size = sizeOf<ISampleGreeterVtbl>();
    final want = slots * sizeOf<Pointer<Void>>();
    if (size != want) {
      throw StateError('ISampleGreeterVtbl is $size bytes, expected $want');
    }
    print('ok: $slots vtable slots in COM order');
  } finally {
    calloc.free(table);
  }
}
