/// End-to-end for Kotlin: `fixtures/jvm/ktgreeter` compiled by `kotlinc` →
/// jnigen 1.0 → `package:jni` binding + IR, and then that binding called on
/// a desktop JVM through `Jni.spawn`.
///
/// jnigen and the runner both run against a throwaway project resolved by
/// `flutter pub get` ([JniProject]), because package:jni needs the Flutter
/// SDK. Without `kotlinc`, Flutter or a JDK the committed binding is read
/// instead and every IR expectation still runs, since `jvmToIr` is pure; the
/// default arguments only the class files know then come from [_defaults],
/// which the IR snapshot keeps honest whenever the real toolchain runs.
///
/// The runtime test also builds `libdartjni` with CMake and `jni.jar` with
/// Gradle, once per jni version, so this suite gets ten minutes rather than
/// the five every other toolchain suite has.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:typed_data';

import 'package:bindsmith/bindsmith.dart';
import 'package:bindsmith/src/drivers/jvm/kdoc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../golden.dart';
import '../jvm_toolchain.dart';

const _package = 'com.example.ktgreeter';
const _fixture = 'fixtures/jvm/ktgreeter/com/example/ktgreeter/KtGreeter.kt';
const _binding = 'test/drivers/goldens/ktgreeter_jvm.g.dart';

// packages/bindsmith → repository root.
final _root = p.dirname(p.dirname(Directory.current.path));

/// What [classFileMethods] finds in the compiled fixture: `greet` and each
/// data class's `copy` have a default argument.
const _defaults = {
  'com.example.ktgreeter.KtGreeter': ['greet'],
  r'com.example.ktgreeter.Reply$Failed': ['copy'],
  r'com.example.ktgreeter.Reply$Ok': ['copy'],
};

void main() {
  late List<Decl> ir;
  late String binding;
  String? blocker;
  Kotlin? kotlin;
  JniProject? project;
  final tmp = Directory.systemTemp.createTempSync('bindsmith_kotlin_');
  final classes = p.join(tmp.path, 'classes');

  setUpAll(() async {
    kotlin = await findKotlin();
    if (kotlin case final k?) {
      await _kotlinc(k, [p.join(_root, _fixture)], classes);
      blocker = await JniProject.blocker();
    } else {
      blocker = 'no Kotlin compiler found; run `mise install`';
    }
    if (blocker == null) {
      project = await JniProject.create();
      (ir, binding) = await project!.generate(
        classes: [_package],
        classPath: [classes],
        kotlinSources: [_fixture],
      );
    } else {
      binding = File(_binding).readAsStringSync().replaceAll('\r\n', '\n');
      ir = jvmToIr(
        binding,
        platform: Platform.android,
        defaults: _defaults,
        kdocs: kdocs(
          File(p.join(_root, _fixture)).readAsStringSync(),
          fileName: p.basename(_fixture),
        ),
      );
    }
  });
  tearDownAll(() {
    project?.delete();
    tmp.deleteSync(recursive: true);
  });

  TypeDecl type(String name) =>
      ir.whereType<TypeDecl>().singleWhere((d) => d.name == name);
  Member member(TypeDecl t, String name, [MemberKind kind = .method]) =>
      t.members.singleWhere((m) => m.name == name && m.kind == kind);

  test('IR snapshot', () {
    final json = const JsonEncoder.withIndent('  ').convert(irToJson(ir));
    expectGolden('test/drivers/goldens/ktgreeter_jvm.ir.json', '$json\n');
  });

  test('generated jni binding matches the committed golden', () {
    if (blocker case final why?) {
      markTestSkipped('jnigen did not run: $why');
      return;
    }
    expectGolden(_binding, binding);
  });

  test('KDoc from the Kotlin source reaches the IR', () {
    final greeter = type('KtGreeter');
    expect(greeter.docs, contains('Greets people'));
    expect(greeter.docs, contains('[greet]'));

    final greet = member(greeter, 'greet');
    expect(greet.docs, 'Greets [name], at [volume].');

    final shout = member(greeter, 'shout');
    final shoutTwice = member(greeter, r'shout$1');
    expect(shout.docs, 'Greets [name] loudly.');
    expect(shoutTwice.docs, 'Greets [name] loudly, [times] times over.');

    final prefix = member(greeter, 'DEFAULT_PREFIX', MemberKind.property);
    expect(prefix.docs, 'The prefix a greeter uses when none is given.');
  });

  test('members take Kotlin parameter names and Kotlin types', () {
    final greet = member(type('KtGreeter'), 'greet');
    // The Dart binding names them after the bytecode: `string`, `volume`.
    expect(greet.params.map((q) => q.name), ['name', 'volume']);
    expect(greet.params.map((q) => q.type.native), [
      'kotlin.String',
      'com.example.ktgreeter.Volume',
    ]);
    expect(greet.params.first.type.name, 'JString');
    expect(greet.returns, const TypeRef('JString', native: 'kotlin.String'));
  });

  test('nullability comes from Kotlin, not from the bytecode', () {
    final greeter = type('KtGreeter');
    final nickname = member(greeter, 'nickname');
    expect(nickname.returns.nullability, Nullability.nullable);
    expect(
      nickname.returns.native,
      'kotlin.String',
      reason: 'the `?` is carried by the nullability',
    );
    expect(member(greeter, 'greet').returns.nullability, Nullability.nonNull);
  });

  test('a suspend fun is a Future of its Kotlin return type', () {
    final slowly = member(type('KtGreeter'), 'greetSlowly');
    expect(slowly.async, Async.future);
    expect(slowly.returns, const TypeRef('JString', native: 'kotlin.String'));
    expect(slowly.params.single.name, 'name');
  });

  test('overloads are numbered by jnigen and keep the Kotlin name', () {
    final greeter = type('KtGreeter');
    final one = member(greeter, 'shout');
    final two = member(greeter, r'shout$1');
    expect(one.native, isNull);
    expect(two.native, 'shout');
    expect(one.params.map((q) => q.name), ['name']);
    expect(two.params.map((q) => q.name), ['name', 'times']);
    expect(two.params.last.type, const TypeRef('int', native: 'kotlin.Int'));
  });

  test('a Flow return is flagged for the bridge', () {
    final greeter = type('KtGreeter');
    final all = member(greeter, 'greetAll');
    expect(all.returns.name, 'Flow');
    expect(all.returns.native, 'kotlinx.coroutines.flow.Flow<kotlin.String>');
    expect(all.markers.single.kind, MarkerKind.verify);
    expect(all.markers.single.reason, contains('emitKotlinBridge'));
    expect(member(greeter, 'greet').markers, isEmpty);
  });

  test('default arguments surface as dropped members', () {
    final greeter = type('KtGreeter');
    final carrier = member(greeter, r'greet$default');
    expect(carrier.isDropped, isTrue);
    expect(carrier.isStatic, isTrue);
    expect(carrier.markers.single.reason, contains('@JvmOverloads'));

    // A constructor's default argument is a synthetic constructor instead,
    // which jnigen keeps and numbers like any other.
    final ctors = greeter.members
        .where((m) => m.kind == MemberKind.constructor)
        .toList();
    expect(ctors.map((c) => c.binding), [null, r'new$1', r'new$2']);
    expect(ctors.map((c) => c.isDropped), [false, true, false]);
    expect(ctors[1].params.last.type.name, 'DefaultConstructorMarker');
    expect(ctors[1].markers.single.reason, contains('@JvmOverloads'));

    // The companion's synthetic constructor is Kotlin's way into a private
    // one, which no annotation turns into API.
    final private = type(r'KtGreeter$Companion').members
        .singleWhere((m) => m.kind == MemberKind.constructor);
    expect(private.isDropped, isTrue);
    expect(private.markers.single.reason, contains('private constructor'));
  });

  test('a companion object is a static getter with instance members', () {
    final greeter = type('KtGreeter');
    final companion = member(greeter, 'Companion', MemberKind.property);
    expect(companion.isStatic, isTrue);
    expect(companion.returns.name, r'KtGreeter$Companion');
    final version = member(type(r'KtGreeter$Companion'), 'version');
    expect(version.isStatic, isFalse);
    expect(version.returns, const TypeRef('int', native: 'kotlin.Int'));
    final prefix = member(greeter, 'DEFAULT_PREFIX', MemberKind.property);
    expect(prefix.isStatic, isTrue);
    expect(prefix.returns.nullability, Nullability.nonNull);
  });

  test('a fun interface is implementable from Dart', () {
    final listener = type('Listener');
    expect(listener.kind, TypeKind.interface);
    expect(
      listener.markers.single.reason,
      contains(r'Listener.implement($Listener(...))'),
    );
    expect(member(listener, 'onGreeting').params.single.name, 'greeting');
  });

  test('classFileMethods finds the default-argument carrier', () {
    if (kotlin == null) {
      markTestSkipped('no Kotlin compiler found; run `mise install`');
      return;
    }
    final methods = classFileMethods(
      File(p.join(classes, 'com', 'example', 'ktgreeter', 'KtGreeter.class'))
          .readAsBytesSync(),
    );
    final carrier = methods.singleWhere((m) => m.name == r'greet$default');
    expect(carrier.access & 0x1008, 0x1008, reason: 'static synthetic');
    expect(
      carrier.descriptor,
      '(Lcom/example/ktgreeter/KtGreeter;Ljava/lang/String;'
      'Lcom/example/ktgreeter/Volume;ILjava/lang/Object;)Ljava/lang/String;',
    );
    expect(
      methods.map((m) => m.name),
      containsAll(['<init>', 'greet', 'shout', 'greetSlowly']),
    );
  });

  test('classFileMethods walks every constant and attribute shape', () {
    expect(classFileMethods(_classFile()), [
      (access: 0x0001, name: 'size', descriptor: '()I'),
      (access: 0x1009, name: r'size$default', descriptor: '()I'),
    ]);
  });

  test('classFileMethods refuses what is not a class file', () {
    final bytes = _classFile();
    Matcher refused(String why) => throwsA(
      isA<FormatException>().having((e) => e.message, 'message', contains(why)),
    );
    expect(
      () => classFileMethods(Uint8List.fromList([0, ...bytes.skip(1)])),
      refused('bad magic'),
    );
    expect(
      () => classFileMethods(Uint8List.sublistView(bytes, 0, bytes.length - 1)),
      refused('truncated'),
    );
  });

  test(
    'the bridge emitted from driver IR compiles against the fixture',
    () async {
      final bridge = emitKotlinBridge(ir, package: _package);
      expect(
        bridge.source,
        contains(
          '  fun greet(name: String): String =\n'
          '    wrapped.greet(name = name)\n',
        ),
      );
      final k = kotlin;
      if (k == null) {
        markTestSkipped('no Kotlin compiler found; run `mise install`');
        return;
      }
      final source = File(p.join(tmp.path, 'KtGreeterBridge.kt'))
        ..writeAsStringSync(bridge.source);
      await _kotlinc(k, [
        p.join(_root, _fixture),
        source.path,
      ], p.join(tmp.path, 'bridge'));
    },
  );

  test('the binding runs on a desktop JVM', () async {
    if (blocker case final why?) {
      markTestSkipped('jnigen did not run: $why');
      return;
    }
    if (!await commandRuns('cmake', ['--version'])) {
      markTestSkipped('no CMake to build libdartjni; run `mise install`');
      return;
    }
    final jni = await project!.buildJni();
    final result = await project!.run(
      _runner,
      binding: binding,
      args: [
        jni,
        p.join(jni, 'jni.jar'),
        classes,
        kotlin!.stdlib,
        kotlin!.coroutines,
      ],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(const LineSplitter().convert(result.stdout as String), [
      'Hi, Ada!!!',
      'Hi, Ada!!!',
      'Hi, Ada!!! Hi, Ada!!!',
      'null',
      'Gra',
      'Hi, Ada!',
      'heard Hi, Ada!',
      'empty name',
      '3',
      'Hello',
      'Hello, Ada!',
    ]);
  });
}

Future<void> _kotlinc(Kotlin k, List<String> sources, String out) async {
  final result = await Process.run(k.exe, [
    '-cp',
    k.coroutines,
    '-nowarn',
    ...sources,
    '-d',
    out,
  ]);
  if (result.exitCode != 0) {
    throw StateError('kotlinc failed:\n${result.stdout}${result.stderr}');
  }
}

/// Calls one member per shape the fixture exists for. `greetSlowly` resumes
/// on a coroutine thread and `greetTo` calls back into Dart, which are the two
/// things only a running JVM can check.
const _runner = r'''
import 'dart:io';

import 'package:bindsmith_jni_probe/binding.g.dart';
import 'package:jni/jni.dart';

Future<void> main(List<String> args) async {
  Jni.spawn(dylibDir: args.first, classPath: args.skip(1).toList());
  final hi = KtGreeter('Hi'.toJString());
  final ada = 'Ada'.toJString();
  print(hi.greet(ada, Volume.LOUD).toDartString());
  print(hi.shout(ada).toDartString());
  print(hi.shout$1(ada, 2).toDartString());
  print(hi.nickname(ada)?.toDartString());
  print(hi.nickname('Grace'.toJString())?.toDartString());
  print((await hi.greetSlowly(ada)).toDartString());
  hi.greetTo(
    ada,
    Listener.implement(
      $Listener(onGreeting: (g) => print('heard ${g.toDartString()}')),
    ),
  );
  final reply = hi.tryGreet(''.toJString());
  print(
    reply.isA(Reply$Failed.type)
        ? reply.as(Reply$Failed.type).reason.toDartString()
        : 'not a failure',
  );
  print(KtGreeter.Companion.version());
  print(KtGreeter.DEFAULT_PREFIX.toDartString());
  print(KtGreeter.new$2().greet(ada, Volume.NORMAL).toDartString());
  // The listener's port keeps the isolate alive.
  exit(0);
}
''';

/// A class file written byte by byte (JVMS §4): a `Long` constant, which
/// takes two pool slots, a `MethodHandle`, a field with a `ConstantValue`
/// attribute and a method with a `Code` attribute, so that every skip in
/// [classFileMethods] is taken.
Uint8List _classFile() {
  final out = BytesBuilder();
  void u1(int v) => out.addByte(v);
  void u2(int v) => out.add([v >> 8 & 0xff, v & 0xff]);
  void u4(int v) {
    u2(v >> 16 & 0xffff);
    u2(v & 0xffff);
  }

  void utf8(String s) {
    u1(1);
    u2(s.length);
    out.add(s.codeUnits);
  }

  u4(0xCAFEBABE);
  u2(0); // minor_version
  u2(65); // major_version: Java 21
  u2(15); // constant_pool_count
  utf8('Box'); // #1
  u1(7); // #2 Class #1
  u2(1);
  utf8('java/lang/Object'); // #3
  u1(7); // #4 Class #3
  u2(3);
  u1(5); // #5 and #6: Long 42
  u4(0);
  u4(42);
  utf8('size'); // #7
  utf8('()I'); // #8
  utf8('Code'); // #9
  utf8('COUNT'); // #10
  utf8('J'); // #11
  utf8('ConstantValue'); // #12
  utf8(r'size$default'); // #13
  u1(15); // #14 MethodHandle
  u1(6);
  u2(2);
  u2(0x0021); // ACC_PUBLIC | ACC_SUPER
  u2(2); // this_class
  u2(4); // super_class
  u2(0); // interfaces_count
  u2(1); // fields_count
  u2(0x0019); // public static final long COUNT = 42
  u2(10);
  u2(11);
  u2(1);
  u2(12); // ConstantValue
  u4(2);
  u2(5);
  u2(2); // methods_count
  u2(0x0001); // public int size() { return 1; }
  u2(7);
  u2(8);
  u2(1);
  u2(9); // Code
  u4(14);
  u2(1); // max_stack
  u2(1); // max_locals
  u4(2); // code_length
  u1(0x04); // iconst_1
  u1(0xac); // ireturn
  u2(0); // exception_table_length
  u2(0); // attributes_count
  u2(0x1009); // public static synthetic int size$default()
  u2(13);
  u2(8);
  u2(0);
  u2(0); // the class's own attributes_count
  return out.takeBytes();
}
