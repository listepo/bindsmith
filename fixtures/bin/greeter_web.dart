/// Compile target for the web pipeline (plan P4-3).
///
/// `dart analyze` accepts js_interop code the web compilers reject: whether an
/// `external` member can be lowered at all is decided by dart2js and dart2wasm,
/// and the two disagree about what is legal. So `test/drivers/dts_test.dart`
/// compiles this file with both back ends. Nothing here runs — the JavaScript
/// library is never loaded — and every generated member is touched on purpose,
/// because a tree-shaken member is never lowered and so is never checked.
library;

import 'dart:js_interop';

import 'package:bindsmith_fixtures/generated/greeter/greeter.g.dart';
// `Box` is declared without a constructor, so the facade offers none and the
// only way to reach its members from Dart is the binding's extension type.
import 'package:bindsmith_fixtures/generated/greeter/web.g.dart' as web;

void main() {
  final options = GreeterOptions(
    prefix: 'Dr',
    loud: true,
    tone: GreeterOptionsTone.formal,
    onGreet: print,
  );
  options
    ..prefix = options.prefix
    ..loud = !options.loud
    ..tone = GreeterOptionsTone.fromValue(options.tone.value)
    ..onGreet = print;
  print(options.onGreet);

  final greeter = Greeter('Ada', options);
  print([Greeter.version, greeter.name, greeter.greet(), VERSION]);
  print(greeter.greet$2(2));
  greeter.uppercase = !greeter.uppercase;
  greeter.greetLater(1).then(print);

  print(createGreeter('Ada').greet());
  print(utilsShout('hey'));

  final box = JSObject() as web.Box;
  box.value = box.value;
  print(box.map(((JSAny? v) => v).toJS).value);
}
