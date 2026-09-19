/// `bindsmith verify` (plan P6-5).
///
/// The pure half is tested on source text, the way a pass is tested on IR; the
/// command is tested against the two committed facade goldens, which are a
/// real pair of group files carrying real markers.
library;

import 'dart:io';

import 'package:bindsmith/bindsmith.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _golden(String name) =>
    File(p.join('test', 'emit', 'goldens', name)).readAsStringSync();

/// A project whose "generated" files are written by the test, so verify reads
/// exactly what each case is about. The two bindings are stubs: verify never
/// runs a driver, it only reads.
String _project({required String verify, String? io, String? web}) {
  final dir = Directory.systemTemp.createTempSync('bindsmith_verify_');
  addTearDown(() => dir.deleteSync(recursive: true));
  void write(String path, String source) => File(p.join(dir.path, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(source);

  write('pubspec.yaml', 'name: demo\nenvironment: { sdk: ^3.13.0 }\n');
  write('bindsmith.yaml', '''
name: sdk
output: lib/src/generated
facade:
  library: lib/sdk.dart
$verify
platforms:
  android:
    driver: jvm
    compile_sdk: 35
  web:
    driver: dts
    deps: { npm: ["demo@1.0.0"] }
''');
  write('lib/src/generated/android/jvm.g.dart', '// binding\n');
  write('lib/src/generated/web/dts.g.dart', '// binding\n');
  // The entry point goes where `facade: library:` says; the group files go
  // beside it under the emitter's own names.
  write('lib/sdk.dart', '// entry\n');
  write('lib/sdk_io.g.dart', io ?? _golden('sdk_io.g.dart'));
  write('lib/sdk_web.g.dart', web ?? _golden('sdk_web.g.dart'));
  return dir.path;
}

Future<({int code, String out, String err})> _run(
  String directory, [
  List<String> args = const ['verify'],
]) async {
  final (out, err) = (StringBuffer(), StringBuffer());
  final code = await runBindsmith(
    args,
    out: out,
    err: err,
    workingDirectory: directory,
  );
  return (code: code, out: out.toString(), err: err.toString());
}

void main() {
  group('markers', () {
    test('every annotation left in the file is one finding, with its '
        'reason', () {
      final found = findMarkers('sdk_io.g.dart', _golden('sdk_io.g.dart'));
      expect(found, hasLength(2));
      expect(found.first.line, 11);
      expect(
        found.first.what,
        'declared as jsObject on web but as klass on android',
      );
      expect(found.last.what, startsWith('signature differs:'));
    });

    test('an annotation without a reason still reports where it is', () {
      expect(findMarkers('a.dart', '@BindsmithVerify\nvoid f() {}\n'), [
        (file: 'a.dart', line: 1, what: '@BindsmithVerify'),
      ]);
    });

    test('another annotation is not one', () {
      expect(findMarkers('a.dart', "@Deprecated('x')\nvoid f() {}\n"), isEmpty);
    });

    test('a file a hand-edit broke is a finding rather than a crash', () {
      final found = findMarkers('a.dart', 'class {{{\n');
      expect(found, hasLength(1));
      expect(found.single.what, startsWith('does not parse:'));
    });
  });

  group('the public API of a facade group', () {
    test('is what a caller can name, and nothing private', () {
      final api = publicApi(_golden('sdk_io.g.dart'));
      expect(api['Client'], 'final class Client');
      expect(api['Client.new'], 'factory Client(String name)');
      expect(api['Client.version'], 'static String get version');
      expect(api['Client.greet'], 'String greet(String? who)');
      expect(api['createClient'], 'Client createClient(String name)');
      // The value is left off: a const may legitimately differ per platform.
      expect(api['VERSION'], 'const String VERSION');
      expect(api.keys, isNot(contains('Client._')));
      expect(api.keys, isNot(contains('_n')));
    });

    test('leaves out the doc comment and the marker above a declaration', () {
      expect(
        publicApi(_golden('sdk_web.g.dart'))['Client.count'],
        'int '
        'count(int n)',
      );
    });

    test('names enum constants and members', () {
      final api = publicApi('''
enum Mode {
  fast,
  slow;

  bool get quick => this == Mode.fast;
}
''');
      expect(api['Mode'], 'enum Mode');
      expect(api['Mode.fast'], 'fast');
      expect(api['Mode.quick'], 'bool get quick');
    });

    test('the two committed facade groups agree, which is the point of '
        'them', () {
      expect(
        facadeDrift(
          publicApi(_golden('sdk_io.g.dart')),
          publicApi(_golden('sdk_web.g.dart')),
        ),
        isEmpty,
      );
    });

    test('a missing or differing declaration is reported from both sides', () {
      expect(
        facadeDrift(
          publicApi('class A { int f() => 0; }\nvoid g() {}\n'),
          publicApi('class A { double f() => 0; }\nvoid h() {}\n'),
        ),
        [
          'A.f is "int f()" on io and "double f()" on web',
          'g is declared on io only',
          'h is declared on web only',
        ],
      );
    });
  });

  test('a size budget counts lines the same on either kind of checkout', () {
    expect(countLines('a\nb\n'), countLines('a\r\nb\r\n'));
  });

  group('the command', () {
    test('markers block it, and say how to acknowledge one', () async {
      final run = await _run(_project(verify: ''));
      expect(run.code, exitChanged);
      expect(run.err, contains('lib/sdk_io.g.dart:11: declared as jsObject'));
      expect(run.err, contains('4 marker(s) still need a human'));
      expect(run.err, contains('ack: true'));
    });

    test('markers: warn reports the same markers and passes', () async {
      final run = await _run(_project(verify: 'verify:\n  markers: warn\n'));
      expect(run.code, 0);
      expect(run.err, contains('lib/sdk_web.g.dart:10:'));
      expect(run.out, contains('4 marker(s) warned about'));
    });

    test('a clean tree passes and says how much was read', () async {
      final directory = _project(verify: '', io: '// a\n', web: '// a\n');
      final run = await _run(directory);
      expect(run.code, 0);
      expect(run.out, contains('5 generated files verified'));
    });

    test('the io and web facades declaring different APIs is a failure no '
        'configuration can wave through', () async {
      final run = await _run(
        _project(
          verify: 'verify:\n  markers: warn\n',
          io: 'class Client {\n  int count(int n) => n;\n}\n',
          web: 'class Client {\n  double count(double n) => n;\n}\n',
        ),
      );
      expect(run.code, exitChanged);
      expect(
        run.err,
        contains('lib/sdk_io.g.dart and lib/sdk_web.g.dart do not declare'),
      );
      expect(run.err, contains('Client.count is "int count(int n)" on io'));
    });

    test('a size budget is over when the whole output is', () async {
      final run = await _run(
        _project(
          verify: 'verify:\n  size_budget: { lines: 3 }\n',
          io: '// a\n// b\n',
          web: '// a\n// b\n',
        ),
      );
      expect(run.code, exitChanged);
      expect(run.err, contains('over the size_budget of 3'));
    });

    test('output that was never generated is a missing file, not an empty '
        'pass', () async {
      final directory = _project(verify: '');
      File(p.join(directory, 'lib', 'sdk_web.g.dart')).deleteSync();
      final run = await _run(directory);
      expect(run.code, exitNoInput);
      expect(run.err, contains('lib/sdk_web.g.dart has not been generated'));
    });
  });
}
