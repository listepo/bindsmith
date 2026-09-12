/// Calls the generated Objective-C binding for real.
///
/// The parts of an Objective-C binding a compiler cannot check are the ones
/// that cross the runtime: a selector that does not exist fails at the call, an
/// `NSString` handed over without a copy is freed under the callee, a block
/// invoked from the wrong isolate deadlocks, an `NSError**` filled by the
/// callee is invisible in the Dart signature, and a protocol implemented in
/// Dart is only really implemented once Objective-C dispatches to it. So the
/// binding is exercised against a real `libcounter`, built from
/// `fixtures/objc/counter/counter.m` together with the generated `objc.g.m`.
///
/// Usage: `dart run fixtures/bin/counter_objc.dart <path to libcounter>`.
/// Run by `packages/bindsmith/test/drivers/objc_test.dart`, which builds the
/// library first and skips off macOS.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:bindsmith_fixtures/generated/counter/objc.g.dart';
import 'package:objective_c/objective_c.dart' as objc;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: counter_objc.dart <path to libcounter>');
    exit(64);
  }
  // `@Native` resolves through the asset id, then a registered resolver, then
  // the process — and opening the library both puts its symbols in the process
  // and registers its classes with the Objective-C runtime.
  DynamicLibrary.open(args.single);

  // A class method returning `instancetype`, and a property read back.
  final counter = BSMCounter.counterWithLabel('ticks'.toNSString());
  _expect(counter.label.toDartString(), 'ticks', 'a copied NSString property');
  _expect(counter.value, 0, 'a readonly property');

  // A designated initializer reached through alloc.
  final other = BSMCounter.alloc().initWithLabel('other'.toNSString());
  _expect(other.label.toDartString(), 'other', 'the designated initializer');

  // A writable property: the setter copies, so the Dart string may go.
  counter.label = 'clicks'.toNSString();
  _expect(counter.label.toDartString(), 'clicks', 'a property setter');

  // An ordinary method with a scalar argument and result.
  _expect(counter.increment(3), 3, 'increment returns the new value');
  _expect(counter.value, 3, 'and the property agrees');

  // A protocol implemented in Dart, dispatched to from Objective-C. The
  // optional member is implemented too, so `respondsToSelector:` is true.
  final ticks = <int>[];
  var finished = 0;
  counter.delegate = BSMCounterDelegate$Builder.implement(
    counterDidTick_: ticks.add,
    counterDidFinish: () => finished++,
  );
  _expect(counter.increment(1), 4, 'increment through a delegate');
  _expect(ticks, [4], 'Objective-C called back into Dart');

  // A block built from a Dart closure, invoked synchronously by the callee.
  var total = -1;
  objc.NSError? failure;
  counter.countTo(
    7,
    completion: ObjCBlock_ffiVoid_NSInteger_NSError.fromFunction((t, e) {
      total = t;
      failure = e;
    }),
  );
  _expect(total, 7, 'the completion handler ran with the final count');
  _expect(failure, null, 'and reported no error');
  _expect(ticks, [4, 5, 6, 7], 'every tick reached the delegate');
  _expect(finished, 1, 'the optional delegate member was called once');

  // The same block, this time given the `NSError` the callee constructs.
  counter.countTo(
    -1,
    completion: ObjCBlock_ffiVoid_NSInteger_NSError.fromFunction((t, e) {
      total = t;
      failure = e;
    }),
  );
  _expect(
    failure?.domain.toDartString(),
    'BSMCounterError',
    'the error domain',
  );
  _expect(total, 7, 'a failed count does not move the value');

  // An `NSError**` out-parameter, which ffigen turns into a thrown exception:
  // the Dart signature says nothing about it, so only a call can prove it.
  _expect(counter.validate(1), true, 'a valid target returns true');
  var threw = false;
  try {
    counter.validate(-1);
  } on objc.NSErrorException catch (e) {
    threw = true;
    _expect(
      e.error.domain.toDartString(),
      'BSMCounterError',
      'the thrown domain',
    );
  }
  _expect(threw, true, 'an NSError** out-parameter throws');

  // A category method, and an NS_ENUM passed by its value rather than its
  // index — here they are the same, which is exactly why the enum is checked
  // against the string the library builds.
  _expect(
    counter.describeWithVolume(BSMVolume.BSMVolumeLoud).toDartString(),
    'CLICKS 7!',
    'a category method with an enum argument',
  );
  _expect(
    counter.describeWithVolume(BSMVolume.BSMVolumeQuiet).toDartString(),
    'clicks 7',
    'the other enum constant',
  );

  print('ok: properties, blocks, delegates, errors and categories cross');
}

void _expect(Object? actual, Object? expected, String what) {
  final same = actual is List && expected is List
      ? actual.length == expected.length &&
            List.generate(
              actual.length,
              (i) => actual[i] == expected[i],
            ).every((e) => e)
      : actual == expected;
  if (!same) {
    throw StateError('$what: got $actual, expected $expected');
  }
}
