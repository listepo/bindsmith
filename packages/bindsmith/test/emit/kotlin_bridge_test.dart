/// Kotlin bridge emitter: hand-built IR in, Kotlin out, and the output is
/// compiled against the real fixture.
///
/// The IR here is written by hand, so that every shape is pinned down without
/// a JDK or a Flutter SDK; `test/drivers/kotlin_test.dart` runs the same
/// emitter on the IR [JvmDriver] really produces. Every `native` string below
/// is the signature `javap` prints for the compiled `fixtures/jvm/ktgreeter`,
/// so the shapes are the real ones.
///
/// The last test closes that gap from the other side: it writes the emitted
/// bridge next to the fixture and compiles both with `kotlinc`, which is what
/// proves the generated Kotlin is valid and type-checks against the API it
/// wraps. It skips where the Kotlin compiler is not installed.
///
/// @docImport 'package:bindsmith/bindsmith.dart';
library;

import 'dart:io' hide Platform;

import 'package:bindsmith/bindsmith.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../golden.dart';
import '../jvm_toolchain.dart';

const _package = 'com.example.ktgreeter';
const _fixture = 'fixtures/jvm/ktgreeter/com/example/ktgreeter/KtGreeter.kt';
const _golden =
    'fixtures/jvm/ktgreeter/com/example/ktgreeter/KtGreeter.bridge.g.kt';

// packages/bindsmith → repository root.
final _root = p.dirname(p.dirname(Directory.current.path));

TypeRef _string({bool nullable = false}) => TypeRef(
  'JString',
  native: 'java.lang.String',
  nullability: nullable ? Nullability.nullable : Nullability.nonNull,
);

Member _method(
  String name, {
  List<Param> params = const [],
  TypeRef returns = const TypeRef('void', native: 'void'),
  bool isStatic = false,
  String? docs,
}) => Member(
  name,
  kind: MemberKind.method,
  params: params,
  returns: returns,
  isStatic: isStatic,
  docs: docs,
);

TypeDecl _type(
  String name, {
  List<Member> members = const [],
  List<TypeRef> supertypes = const [],
  List<String> typeParams = const [],
  TypeKind kind = TypeKind.klass,
  List<Marker> markers = const [],
}) => TypeDecl(
  id: '$_package.$name',
  name: name,
  platform: Platform.android,
  kind: kind,
  members: members,
  supertypes: supertypes,
  typeParams: typeParams,
  markers: markers,
);

/// `public final String greet(String, Volume)` plus the synthetic
/// `greet$default(KtGreeter, String, Volume, int, Object)`.
List<Member> get _greet => [
  _method(
    'greet',
    docs: 'Greets [name], at [volume].',
    params: [
      Param('name', _string()),
      Param('volume', const TypeRef('Volume', native: '$_package.Volume')),
    ],
    returns: _string(),
  ),
  _method(
    r'greet$default',
    isStatic: true,
    params: [
      Param(
        'receiver',
        const TypeRef('KtGreeter', native: '$_package.KtGreeter'),
      ),
      Param('name', _string()),
      Param('volume', const TypeRef('Volume', native: '$_package.Volume')),
      Param('mask', const TypeRef('int', native: 'int')),
      Param('marker', const TypeRef('JObject', native: 'java.lang.Object')),
    ],
    returns: _string(),
  ),
];

/// `public final Flow<String> greetAll(List<String>)`.
Member get _greetAll => _method(
  'greetAll',
  docs: 'One greeting per name, emitted as a cold flow.',
  params: [
    Param(
      'names',
      const TypeRef(
        'JList',
        args: [TypeRef('JString')],
        native: 'java.util.List<java.lang.String>',
      ),
    ),
  ],
  returns: const TypeRef(
    'Flow',
    native: 'kotlinx.coroutines.flow.Flow<java.lang.String>',
  ),
);

/// The whole fixture, as jnigen would describe it.
List<Decl> get _ktGreeter => [
  _type(
    'KtGreeter',
    members: [
      ..._greet,
      _greetAll,
      // `suspend` is the shape jnigen already lowers itself.
      Member(
        'greetSlowly',
        kind: MemberKind.method,
        async: Async.future,
        params: [Param('name', _string())],
        returns: _string(),
      ),
      _method(
        'tryGreet',
        params: [Param('name', _string())],
        returns: const TypeRef('Reply', native: '$_package.Reply'),
      ),
    ],
  ),
  _type('Reply'),
  _type(
    r'Reply$Ok',
    supertypes: [const TypeRef('Reply', native: '$_package.Reply')],
  ),
  _type(
    r'Reply$Failed',
    supertypes: [const TypeRef('Reply', native: '$_package.Reply')],
  ),
  _type(
    'Volume',
    kind: TypeKind.enumeration,
    members: [Member('QUIET', kind: MemberKind.property, isStatic: true)],
  ),
];

KotlinBridge _emit(List<Decl> ir) => emitKotlinBridge(ir, package: _package);

void main() {
  test('a type with none of the three shapes gets no bridge', () {
    final bridge = _emit([
      _type(
        'Plain',
        members: [
          _method(
            'greet',
            params: [Param('name', _string())],
            returns: _string(),
          ),
        ],
      ),
    ]);
    expect(bridge.classes, isEmpty);
    expect(bridge.source, isNot(contains('class')));
    expect(bridge.source, isNot(contains('import kotlinx')));
  });

  test('a default argument becomes an overload without the last one', () {
    final source = _emit([_type('KtGreeter', members: _greet)]).source;
    expect(
      source,
      containsCode(
        'fun greet(name: String): String =\n'
        '    wrapped.greet(name = name)',
      ),
    );
    // Named arguments are what make the assumption safe.
    expect(source, contains('name = name'));
    expect(source, contains('@JvmOverloads'));
    // The synthetic itself is never re-declared.
    expect(source, isNot(contains(r'greet$default(')));
    // The original KDoc is carried on so jnigen hands it to Dart.
    expect(source, contains('Greets [name], at [volume].'));
  });

  test('an explicitly optional parameter beats the trailing assumption', () {
    final source = _emit([
      _type(
        'KtGreeter',
        members: [
          _method(
            'greet',
            params: [
              Param('name', _string(), optional: true),
              Param(
                'volume',
                const TypeRef('Volume', native: '$_package.Volume'),
              ),
            ],
            returns: _string(),
          ),
          _method(r'greet$default', params: const []),
        ],
      ),
    ]).source;
    expect(source, containsCode('fun greet(volume: Volume): String'));
    expect(source, containsCode('wrapped.greet(volume = volume)'));
  });

  test('a Flow becomes a listener and a handle that cancels', () {
    final bridge = _emit([
      _type('KtGreeter', members: [_greetAll]),
    ]);
    expect(bridge.classes, {'$_package.KtGreeterBridge'});
    expect(bridge.source, contains('import kotlinx.coroutines.launch'));
    expect(
      bridge.source,
      containsCode(
        'interface GreetAllSink {\n'
        '    fun onValue(value: String)\n\n'
        '    fun onError(error: Throwable)\n\n'
        '    fun onDone()\n'
        '  }',
      ),
    );
    expect(
      bridge.source,
      containsCode(
        'fun greetAll(names: List<String>, sink: GreetAllSink): AutoCloseable {',
      ),
    );
    expect(
      bridge.source,
      containsCode(
        'wrapped.greetAll(names = names).collect { sink.onValue(it) }',
      ),
    );
    expect(
      bridge.source,
      containsCode('return AutoCloseable { job.cancel() }'),
    );
    expect(bridge.source, containsCode('fun close() = scope.cancel()'));
  });

  test('a sealed base gets a discriminator and one checked cast each', () {
    final source = _emit(_ktGreeter).source;
    expect(source, contains('class ReplyBridge(val wrapped: Reply) {'));
    expect(
      source,
      containsCode(
        'val kind: String\n'
        '    get() = wrapped.javaClass.simpleName',
      ),
    );
    expect(
      source,
      containsCode('fun asOk(): Reply.Ok? =\n    wrapped as? Reply.Ok'),
    );
    expect(
      source,
      containsCode(
        'fun asFailed(): Reply.Failed? =\n    wrapped as? Reply.Failed',
      ),
    );
    // The subclasses themselves have nothing to bridge.
    expect(source, isNot(contains('Reply_OkBridge')));
  });

  test('an enum and a suspend function are left alone', () {
    final source = _emit(_ktGreeter).source;
    expect(source, isNot(contains('VolumeBridge')));
    expect(source, isNot(contains('greetSlowly')));
  });

  test('comments are KDoc, which is what jnigen reads', () {
    final source = _emit(_ktGreeter).source;
    expect(source, contains('/**'));
    expect(source, isNot(contains('/// ')));
  });

  test('a generic is refused, not mis-erased', () {
    final bridge = _emit([
      _type(
        'Box',
        typeParams: ['T'],
        members: [
          _method('value', returns: const TypeRef('Object', native: 'T')),
          _method(r'value$default'),
        ],
      ),
    ]);
    expect(bridge.classes, isEmpty);
    expect(bridge.source, contains('// Not bridged'));
    expect(bridge.source, contains('generic over <T>'));
  });

  test('a type with no Kotlin spelling is refused with the reason', () {
    final bridge = _emit([
      _type(
        'KtGreeter',
        members: [
          _method(
            'pick',
            params: [Param('choice', const TypeRef('JObject', native: 'T'))],
            returns: const TypeRef(
              'Flow',
              native: 'kotlinx.coroutines.flow.Flow<java.lang.String>',
            ),
          ),
        ],
      ),
    ]);
    expect(bridge.classes, isEmpty);
    expect(bridge.source, contains('has no Kotlin spelling here'));
  });

  test('a dropped declaration is not bridged', () {
    final bridge = _emit([
      _type(
        'Missing',
        markers: const [Marker.dropped('not in the pull list')],
        members: [_greetAll],
      ),
    ]);
    expect(bridge.classes, isEmpty);
  });

  test('the generated bridge matches the committed fixture', () {
    expectGolden(p.join(_root, _golden), _emit(_ktGreeter).source);
  });

  test('the generated bridge compiles against the fixture', () async {
    final kotlin = await findKotlin();
    if (kotlin == null) {
      markTestSkipped('no Kotlin compiler found; run `mise install`');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('bindsmith_kotlin_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final result = await Process.run(kotlin.exe, [
      '-cp',
      kotlin.coroutines,
      '-nowarn',
      p.join(_root, _fixture),
      p.join(_root, _golden),
      '-d',
      tmp.path,
    ]);
    expect(
      result.exitCode,
      0,
      reason: 'kotlinc rejected the generated bridge:\n${result.stderr}',
    );
    expect(
      File(
        p.join(
          tmp.path,
          'com',
          'example',
          'ktgreeter',
          'KtGreeterBridge.class',
        ),
      ).existsSync(),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
