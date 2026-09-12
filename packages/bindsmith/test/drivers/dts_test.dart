/// End-to-end for the web pipeline: `fixtures/dts/greeter.d.ts` → sidecar →
/// IR → js_interop emitter + facade. The IR is snapshotted under
/// `test/drivers/goldens/`; the generated Dart is committed under
/// `fixtures/lib/generated/greeter/` where `dart analyze --fatal-infos
/// fixtures` proves it compiles. Needs node and the sidecar's `node_modules`
/// (`mise run setup`).
library;

import 'dart:convert';
import 'dart:io' as io show Directory, Platform, Process;

import 'package:bindsmith/bindsmith.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../golden.dart';

const _fixture = 'fixtures/dts/greeter.d.ts';
const _generated = '../../fixtures/lib/generated/greeter';

/// The binding is written from the driver's IR and the facade from the IR
/// [dtsFacadePass] rewrote: JavaScript has no enums and cannot take a Dart
/// function, so those types exist on the facade side only.
FacadeFiles _facade(List<Decl> ir) => emitFacade(
  {
    Platform.web: runPasses(ir, [dtsFacadePass()]),
  },
  const FacadeOptions(
    library: 'greeter',
    bindings: {Platform.web: 'web.g.dart'},
  ),
);

void main() {
  late List<Decl> ir;

  setUpAll(() async {
    final sidecar = await DtsDriver.bundledSidecarDir();
    // <root>/packages/bindsmith/tool/ts_sidecar → <root>
    final root = p.dirname(p.dirname(p.dirname(p.dirname(sidecar))));
    ir = await DtsDriver(sidecarDir: sidecar)
        .load([_fixture], workingDirectory: root);
  });

  TypeDecl type(String name) =>
      ir.whereType<TypeDecl>().singleWhere((d) => d.name == name);
  Member member(TypeDecl t, String name, MemberKind kind) =>
      t.members.singleWhere((m) => m.name == name && m.kind == kind);

  test('IR snapshot', () {
    final json = const JsonEncoder.withIndent('  ').convert(irToJson(ir));
    expectGolden('test/drivers/goldens/greeter.ir.json', '$json\n');
  });

  test('classes become JS object types with overloads bound apart', () {
    final greeter = type('Greeter');
    expect(greeter.kind, TypeKind.jsObject);
    expect(greeter.loc?.file, _fixture);
    expect(member(greeter, '', MemberKind.constructor).params, hasLength(2));
    expect(member(greeter, 'greet', MemberKind.method).native, isNull);
    final overload = member(greeter, r'greet$2', MemberKind.method);
    expect(overload.native, 'greet');
    expect(overload.returns.name, 'List');
    expect(overload.returns.args.single.name, 'String');
    final later = member(greeter, 'greetLater', MemberKind.method);
    expect(later.async, Async.future);
    expect(later.returns.name, 'String');
    expect(member(greeter, 'version', MemberKind.property).isStatic, isTrue);
    expect(
      member(greeter, 'uppercase', MemberKind.property).returns.name,
      'bool',
    );
    expect(
      member(greeter, 'uppercase', MemberKind.setter).params.single.name,
      'value',
    );
    // readonly `name` has no setter.
    expect(
      greeter.members.where((m) => m.name == 'name'),
      everyElement(predicate<Member>((m) => m.kind == MemberKind.property)),
    );
  });

  test('option-bag interfaces get an object-literal constructor', () {
    final options = type('GreeterOptions');
    expect(options.kind, TypeKind.interface);
    final ctor = member(options, '', MemberKind.constructor);
    expect(ctor.params.every((p) => p.named), isTrue);
    expect(
      {for (final p in ctor.params) p.name: p.optional},
      {'prefix': true, 'loud': false, 'tone': false, 'onGreet': true},
    );
    final tone = member(options, 'tone', MemberKind.property);
    expect(tone.returns.name, 'String');
    expect(tone.docs, contains("One of: 'formal', 'casual'."));
    expect(
      member(options, 'onGreet', MemberKind.property).returns.name,
      'JSFunction',
    );
    expect(
      options.markers.map((m) => m.reason),
      contains(startsWith('index signature')),
    );
  });

  test('enums and aliases are dropped with a reason, never silently', () {
    expect(type('Tone').isDropped, isTrue);
    expect(type('Tone').markers.single.reason, contains("'formal', 'casual'"));
    expect(type('GreetCallback').kind, TypeKind.typedef);
    expect(type('GreetCallback').isDropped, isTrue);
  });

  test('namespaces flatten to camelCase with the JS path kept as id', () {
    final shout = ir.whereType<FunctionDecl>().singleWhere(
      (d) => d.id == 'utils.shout',
    );
    expect(shout.name, 'utilsShout');
  });

  test('generics are bound as JSAny? with a verify marker', () {
    final box = type('Box');
    expect(box.typeParams, ['T']);
    expect(box.markers.map((m) => m.kind), contains(MarkerKind.verify));
    expect(member(box, 'value', MemberKind.property).returns.name, 'JSAny');
    expect(member(box, 'map', MemberKind.method).returns.name, 'Box');
  });

  test('generated web binding and facade match the committed fixtures', () {
    expectGolden('$_generated/web.g.dart', emitJsInterop(ir));
    final facade = _facade(ir);
    expect(facade.keys, ['greeter.g.dart', 'greeter_web.g.dart']);
    for (final MapEntry(key: name, value: source) in facade.entries) {
      expectGolden('$_generated/$name', source);
    }
  });

  test('facade delegates to the binding with JS marshalling', () {
    final web = _facade(ir)['greeter_web.g.dart']!;
    expect(
      web,
      containsCode(
        'factory Greeter(String name, [GreeterOptions? options]) => '
        'Greeter._(web.Greeter(name, (options?._impl as web.GreeterOptions?)));',
      ),
    );
    expect(
      web,
      containsCode(
        r'List<String> greet$2(num times) => '
        r'[for (final e0 in (_impl as web.Greeter).greet$2(times).toDart) e0.toDart];',
      ),
    );
    expect(
      web,
      containsCode(
        'Future<String> greetLater(num delayMs) => '
        '(_impl as web.Greeter).greetLater(delayMs).toDart.then((v) => v.toDart);',
      ),
    );
    expect(
      web,
      containsCode(
        'set uppercase(bool value) { (_impl as web.Greeter).uppercase = value; }',
      ),
    );
    expect(
      web,
      containsCode('String utilsShout(String text) => web.utilsShout(text);'),
    );
    expect(
      web,
      containsCode(
        'prefix: prefix, loud: loud, tone: tone.value, onGreet: onGreet?.toJS',
      ),
    );
  });

  test('an inline literal union becomes a named enum on the facade', () {
    final facade = runPasses(ir, [dtsFacadePass()]);
    final tone = facade.whereType<TypeDecl>().singleWhere(
      (d) => d.name == 'GreeterOptionsTone',
    );
    expect(tone.kind, TypeKind.enumeration);
    expect(tone.platform, Platform.web);
    // The enum is bindsmith's, not the library's: say where the name came from.
    expect(
      tone.markers.single.reason,
      synthesizedFrom("'formal' | 'casual'", 'GreeterOptions.tone'),
    );
    expect(tone.members.map((m) => (m.name, m.value)), [
      ('formal', "'formal'"),
      ('casual', "'casual'"),
    ]);
    // The property is retyped; the binding still sees the string it declared.
    final property = member(
      facade.whereType<TypeDecl>().singleWhere(
        (d) => d.name == 'GreeterOptions',
      ),
      'tone',
      MemberKind.property,
    );
    expect(property.returns.name, 'GreeterOptionsTone');
    expect(property.returns.native, "'formal' | 'casual'");

    final web = _facade(ir)['greeter_web.g.dart']!;
    expect(web, containsCode("formal('formal'), casual('casual');"));
    expect(
      web,
      containsCode(
        'GreeterOptionsTone get tone => '
        'GreeterOptionsTone.fromValue((_impl as web.GreeterOptions).tone);',
      ),
    );
    expect(
      web,
      containsCode(
        'set tone(GreeterOptionsTone value) { '
        '(_impl as web.GreeterOptions).tone = value.value; }',
      ),
    );
  });

  test('a callback parameter takes a Dart function, a getter stays JSFunction', () {
    // `.toJS` goes one way only, so a value coming *out* of JavaScript keeps
    // the type the binding declares.
    final web = _facade(ir)['greeter_web.g.dart']!;
    expect(
      web,
      containsCode(
        'JSFunction? get onGreet => (_impl as web.GreeterOptions).onGreet;',
      ),
    );
    expect(
      web,
      containsCode(
        'set onGreet(void Function(String)? value) { '
        '(_impl as web.GreeterOptions).onGreet = value?.toJS; }',
      ),
    );
    expect(
      web,
      containsCode(
        'Box map(JSAny? Function(JSAny?) transform) => '
        'Box._((_impl as web.Box).map(transform.toJS));',
      ),
    );
    // Each `.toJS` makes a new JSFunction, so `removeListener` style APIs need
    // the caller to keep the converted value. Say so rather than hide it.
    expect(
      web,
      contains('keep the converted value to pass the same one twice'),
    );
  });

  test('the generated web code compiles with dart2js and dart2wasm', () async {
    final root = p.dirname(p.dirname(io.Directory.current.path));
    final tmp = io.Directory.systemTemp.createTempSync('bindsmith_dts_web_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // js_interop is checked by the compilers, not by the analyzer: an
    // `external` member with a type dart2wasm cannot lower is an error only
    // here. Both back ends run because they disagree about what is legal.
    for (final target in ['js', 'wasm']) {
      final result = await io.Process.run(io.Platform.executable, [
        'compile',
        target,
        '-o',
        p.join(tmp.path, 'greeter.$target'),
        'bin/greeter_web.dart',
      ], workingDirectory: p.join(root, 'fixtures'));
      expect(
        result.exitCode,
        0,
        reason: 'dart compile $target:\n${result.stdout}\n${result.stderr}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('JSDoc: a link becomes a reference, a tag prose or an annotation', () {
    final decls = dtsToIr({
      'version': 1,
      'decls': [
        {
          'kind': 'function',
          'name': 'shout',
          'params': [
            {
              'name': 'text',
              'type': {'k': 'keyword', 'name': 'string'},
            },
          ],
          'returns': {'k': 'keyword', 'name': 'string'},
          'docs':
              'Shouts, as {@link Greeter.greet} does; see '
              '{@link https://example.com the spec}.',
          'tags': [
            {'tag': 'param', 'name': 'text', 'text': 'What to shout.'},
            {'tag': 'param', 'name': 'extra', 'text': 'Not a parameter.'},
            {'tag': 'returns', 'text': 'the text, louder.'},
            {'tag': 'deprecated', 'text': 'Use greet.'},
            {'tag': 'template'},
          ],
        },
      ],
    });
    final shout = decls.single;
    final fn = shout as FunctionDecl;
    expect(fn.params.single.docs, 'What to shout.');
    expect(
      fn.docs,
      'Shouts, as [Greeter.greet] does; see [the spec](https://example.com).'
      '\n\n`extra`: Not a parameter.'
      '\n\nReturns the text, louder.',
    );
    expect(shout.availability?.deprecated, 'Use greet.');
    expect(emitJsInterop(decls), contains("@Deprecated('Use greet.')"));
  });

  test('rejects a sidecar model of another version', () {
    expect(
      () => dtsToIr({'version': 2, 'decls': <Object?>[]}),
      throwsFormatException,
    );
  });
}
