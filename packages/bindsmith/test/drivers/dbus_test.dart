/// End-to-end for the D-Bus pipeline: `fixtures/dbus/com.example.Greeter.xml`
/// → [DbusDriver] → IR → dart-dbus remote-object client, committed under
/// `fixtures/lib/generated/dbus/` where `dart analyze --fatal-infos fixtures`
/// proves it compiles. Pure Dart: no extra toolchain.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bindsmith/src/drivers/dbus/dbus_driver.dart';
import 'package:bindsmith/src/ir/ir.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../golden.dart';

const _fixture = 'fixtures/dbus/com.example.Greeter.xml';
const _generated = '../../fixtures/lib/generated/dbus/greeter.g.dart';

// packages/bindsmith → repository root.
final _root = p.dirname(p.dirname(Directory.current.path));

void main() {
  late List<Decl> ir;
  late String binding;

  setUpAll(() async {
    final driver = DbusDriver(xmlFiles: [_fixture]);
    ir = await driver.load(workingDirectory: _root, output: _generated);
    binding = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    ).format(File(p.join(_root, _generated)).readAsStringSync());
  });

  TypeDecl type(String name) =>
      ir.whereType<TypeDecl>().singleWhere((d) => d.name == name);
  Member member(TypeDecl t, String name, MemberKind kind) =>
      t.members.singleWhere((m) => m.name == name && m.kind == kind);

  test('IR snapshot', () {
    final json = const JsonEncoder.withIndent('  ').convert(irToJson(ir));
    expectGolden('test/drivers/goldens/greeter_dbus.ir.json', '$json\n');
  });

  test('the remote object class carries the greet method', () {
    final greeter = type('ComExampleGreeter');
    expect(greeter.id, 'com.example.Greeter');
    expect(greeter.platform, Platform.linux);
    expect(greeter.kind, TypeKind.klass);
    expect(greeter.loc?.file, _fixture);
    expect(greeter.supertypes.single.name, 'DBusRemoteObject');

    final greet = member(greeter, 'callGreet', MemberKind.method);
    expect(greet.native, 'Greet');
    expect(greet.async, Async.future);
    expect(greet.params.single.name, 'name');
    expect(greet.params.single.type, const TypeRef('String', native: 's'));
    expect(greet.returns, const TypeRef('String', native: 's'));

    final version = member(greeter, 'getVersion', MemberKind.method);
    expect(version.returns, const TypeRef('String', native: 's'));

    final greeted = member(greeter, 'greeted', MemberKind.event);
    expect(greeted.native, 'Greeted');
    expect(greeted.async, Async.stream);
    expect(greeted.params.map((p) => p.name), ['name', 'greeting']);
    expect(greeted.markers.single.kind, MarkerKind.verify);
  });

  test('unknown signatures get a verify marker', () {
    const xml = '''
<node>
  <interface name="com.example.Weird">
    <method name="Echo">
      <arg name="value" type="(is)" direction="in"/>
    </method>
  </interface>
</node>
''';
    final weird = dbusToIr(xml).single as TypeDecl;
    final echo = member(weird, 'callEcho', MemberKind.method);
    expect(echo.params.single.type.name, 'List');
    expect(echo.params.single.type.args.single.name, 'DBusValue');
    expect(echo.markers, isNotEmpty);
  });

  test('generated binding golden', () {
    expectGolden(_generated, '$binding\n');
  });

  test('generation is deterministic', () async {
    final first = await DbusDriver(xmlFiles: [_fixture])
        .load(workingDirectory: _root, output: 'tool/scratch/dbus_once.g.dart');
    final second = await DbusDriver(
      xmlFiles: [_fixture],
    ).load(workingDirectory: _root, output: 'tool/scratch/dbus_twice.g.dart');
    expect(irToJson(first), irToJson(second));
    expect(
      File(p.join(_root, 'tool/scratch/dbus_once.g.dart')).readAsStringSync(),
      File(p.join(_root, 'tool/scratch/dbus_twice.g.dart')).readAsStringSync(),
    );
    Directory(p.join(_root, 'tool/scratch')).deleteSync(recursive: true);
  });
}
