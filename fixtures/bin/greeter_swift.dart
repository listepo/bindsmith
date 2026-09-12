/// Calls the generated Swift binding for real.
///
/// A Swift binding is three translations deep — Swift, the Objective-C wrapper
/// swift2objc writes, then the Dart ffigen reads out of it — and each hop drops
/// something a compiler cannot check back: the mangled class name
/// (`_TtC10GreeterKit14GreeterWrapper`) only resolves once the module is really
/// named `GreeterKit`, a Swift `String` property only round-trips if the
/// wrapper bridges it, a Swift struct only survives as its wrapper class, and
/// an `async` method reaches Dart as a completion handler invoked from Swift's
/// own executor thread, so it needs a listener block or it deadlocks.
///
/// Usage: `dart run fixtures/bin/greeter_swift.dart <path to libgreeter_swift>`.
/// Run by `packages/bindsmith/test/drivers/swift_test.dart`, which builds the
/// library first and skips off macOS.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:bindsmith_fixtures/generated/greeter_swift/swift.g.dart';
import 'package:objective_c/objective_c.dart' as objc;

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: greeter_swift.dart <path to libgreeter_swift>');
    exit(64);
  }
  // `@Native` resolves through the asset id, then a registered resolver, then
  // the process — and opening the library both puts its symbols in the process
  // and registers its Swift classes with the Objective-C runtime.
  DynamicLibrary.open(args.single);

  // The Swift initializer, reached through the wrapper's `alloc`.
  final greeter = GreeterWrapper.alloc().initWithPrefix('Hello'.toNSString());
  _expect(greeter.prefix.toDartString(), 'Hello', 'a Swift String property');
  _expect(greeter.count, 0, 'a private(set) property is readable');

  // A Swift method: the argument bridges in, the result bridges out.
  _expect(
    greeter.greetWithName('world'.toNSString()).toDartString(),
    'Hello, world!',
    'a Swift method returning a String',
  );
  _expect(greeter.count, 1, 'the Swift side kept the mutation');

  // A settable Swift property.
  greeter.prefix = 'Hei'.toNSString();
  _expect(
    greeter.greetWithName('verden'.toNSString()).toDartString(),
    'Hei, verden!',
    'the setter reached the Swift instance',
  );

  // A Swift struct: no Objective-C representation of its own, so it only
  // arrives as the wrapper class swift2objc writes around it.
  final volume = VolumeWrapper.alloc().initWithLevel(3);
  _expect(volume.level, 3, 'a Swift struct crosses as its wrapper');
  _expect(volume.louder().level, 6, 'a method on the struct wrapper');
  _expect(volume.level, 3, 'and the value type was copied, not mutated');

  // `async` becomes a completion handler that Swift calls from its own
  // executor thread, so the block has to be a listener: an ordinary block
  // invoked off the isolate's thread crashes.
  final greeted = Completer<String>();
  greeter.greetSlowlyWithName(
    'later'.toNSString(),
    completionHandler: ObjCBlock_ffiVoid_NSString.listener(
      (s) => greeted.complete(s.toDartString()),
    ),
  );
  _expect(await greeted.future, 'Hei, later!', 'an async method completed');
  _expect(greeter.count, 3, 'the async call counted too');

  print('ok: Swift properties, structs and async completions cross');
}

void _expect(Object? actual, Object? expected, String what) {
  if (actual != expected) {
    throw StateError('$what: got $actual, expected $expected');
  }
}
