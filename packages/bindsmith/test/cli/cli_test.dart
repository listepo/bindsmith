/// The command line (plan P1-4).
///
/// `runBindsmith` takes its sinks and its working directory, so every case
/// here runs in-process against a throwaway project directory: no `dart run`,
/// no `Directory.current` to restore, and the output is a string rather than a
/// pipe. The generate cases need libclang, the same as `drivers/c_test.dart`.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:bindsmith/bindsmith.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:bindsmith/src/cli/android_sdk.dart';

import '../jvm_toolchain.dart';

final _root = p.dirname(p.dirname(io.Directory.current.path));

const _header = '''
#include <stdint.h>

typedef enum { DEMO_RED = 0, DEMO_BLUE = 1 } DemoColor;

int32_t demo_add(int32_t a, int32_t b);
int32_t other_thing(int32_t a);
''';

const _config = '''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart

platforms:
  linux:
    driver: c
    headers: [demo.h]
    include:
      functions: ["demo_*"]
      enums: ["DemoColor"]
    build:
      sources: [demo.c]
''';

/// A throwaway project directory: a pubspec, a header, and whatever
/// [bindsmith] was passed as `bindsmith.yaml`.
String _project({String? bindsmith, String pubspec = 'name: demo\n'}) {
  final dir = io.Directory.systemTemp.createTempSync('bindsmith_cli_');
  addTearDown(() => dir.deleteSync(recursive: true));
  if (pubspec.isNotEmpty) {
    io.File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  }
  io.File(p.join(dir.path, 'demo.h')).writeAsStringSync(_header);
  if (bindsmith != null) {
    io.File(p.join(dir.path, 'bindsmith.yaml')).writeAsStringSync(bindsmith);
  }
  return dir.path;
}

typedef _Result = ({int code, String out, String err});

Future<_Result> _run(String directory, List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runBindsmith(
    args,
    out: out,
    err: err,
    workingDirectory: directory,
  );
  return (code: code, out: out.toString(), err: err.toString());
}

/// A two-artifact Maven repository on disk, `demo` depending on `core`.
///
/// `file:` repositories are a real feature — Gradle writes the same thing as
/// `maven { url = uri("file:///…") }` for a vendored or mirrored repository —
/// and they are also what lets these cases exercise the whole of `resolve`,
/// the real resolver included, with nothing injected and no network.
String _repository() {
  final dir = io.Directory.systemTemp.createTempSync('bindsmith_maven_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  void publish(String coordinate, {String dependency = ''}) {
    final parts = coordinate.split(':');
    final into = io.Directory(
      p.join(dir.path, 'com', 'example', parts[1], parts[2]),
    )..createSync(recursive: true);
    io.File(p.join(into.path, '${parts[1]}-${parts[2]}.pom')).writeAsStringSync(
      '<project xmlns="http://maven.apache.org/POM/4.0.0">'
      '<modelVersion>4.0.0</modelVersion>'
      '<groupId>${parts[0]}</groupId>'
      '<artifactId>${parts[1]}</artifactId>'
      '<version>${parts[2]}</version>'
      '$dependency'
      '</project>',
    );
    io.File(p.join(into.path, '${parts[1]}-${parts[2]}.jar'))
        .writeAsStringSync('jar of ${parts[1]}');
  }

  publish('com.example:core:2.0');
  publish(
    'com.example:demo:1.0',
    dependency:
        '<dependencies><dependency>'
        '<groupId>com.example</groupId>'
        '<artifactId>core</artifactId>'
        '<version>2.0</version>'
        '</dependency></dependencies>',
  );
  return dir.path;
}

/// A configuration whose one platform declares Maven dependencies and nothing
/// else, so `resolve` is exercised without a driver ever running.
String _mavenConfig(
  String repository, {
  List<String> coordinates = const ['com.example:demo:1.0'],
  String compileSdk = '35',
  List<String> include = const ['com.example.*'],
}) =>
    '''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart

platforms:
  android:
    driver: jvm
    compile_sdk: $compileSdk
    deps:
      maven: [${coordinates.map((c) => '"$c"').join(', ')}]
      repositories: ["${Uri.directory(repository)}"]
    include:
      classes: [${include.map((c) => '"$c"').join(', ')}]
''';

String _read(String directory, String path) =>
    io.File(p.join(directory, path)).readAsStringSync();

/// Polls until [done], so a `watch` case waits on the file system rather than
/// on a guessed sleep.
Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

const _emptyZip = <int>[
  0x50,
  0x4b,
  0x05,
  0x06,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
];

String _fakeAndroidSdk({String compileSdk = '35'}) {
  final sdk = io.Directory.systemTemp.createTempSync('bindsmith_android_sdk_');
  addTearDown(() => sdk.deleteSync(recursive: true));
  io.File(p.join(sdk.path, 'platforms', 'android-$compileSdk', 'android.jar'))
    ..createSync(recursive: true)
    ..writeAsBytesSync(_emptyZip);
  return sdk.path;
}

Future<_Result> _runWithPackages(
  String directory,
  String packages,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final bindsmith = p.join(
    _root,
    'packages',
    'bindsmith',
    'bin',
    'bindsmith.dart',
  );
  final result = await io.Process.run(
    io.Platform.resolvedExecutable,
    ['--packages=$packages', bindsmith, ...args],
    workingDirectory: directory,
    environment: environment,
  );
  return (
    code: result.exitCode,
    out: '${result.stdout}',
    err: '${result.stderr}',
  );
}

Future<String> _greeterRepository() async {
  final dir = io.Directory.systemTemp.createTempSync(
    'bindsmith_greeter_maven_',
  );
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final classes = io.Directory(p.join(dir.path, 'classes'))..createSync();
  final source = p.join(
    _root,
    'fixtures',
    'jvm',
    'greeter',
    'com',
    'example',
    'greeter',
    'Greeter.java',
  );
  final javac = await io.Process.run('javac', ['-d', classes.path, source]);
  if (javac.exitCode != 0) {
    throw StateError('javac failed: ${javac.stderr}');
  }
  final jar = p.join(dir.path, 'greeter.jar');
  final pack = await io.Process.run('jar', [
    'cf',
    jar,
    '-C',
    classes.path,
    '.',
  ]);
  if (pack.exitCode != 0) {
    throw StateError('jar failed: ${pack.stderr}');
  }
  final bytes = io.File(jar).readAsBytesSync();
  final repo = io.Directory(p.join(dir.path, 'repo'))..createSync();
  final into = io.Directory(
    p.join(repo.path, 'com', 'example', 'greeter', '1.0'),
  )..createSync(recursive: true);
  io.File(p.join(into.path, 'greeter-1.0.jar')).writeAsBytesSync(bytes);
  io.File(p.join(into.path, 'greeter-1.0.pom')).writeAsStringSync(
    '<project xmlns="http://maven.apache.org/POM/4.0.0">'
    '<modelVersion>4.0.0</modelVersion>'
    '<groupId>com.example</groupId>'
    '<artifactId>greeter</artifactId>'
    '<version>1.0</version>'
    '</project>',
  );
  return repo.path;
}

String _jvmGenerateConfig(String repository) =>
    '''
name: bindsmith_jni_probe
output: lib/src/generated
facade:
  library: lib/bindsmith_jni_probe.dart

platforms:
  android:
    driver: jvm
    compile_sdk: 35
    deps:
      maven: [com.example:greeter:1.0]
      repositories: ["${Uri.directory(repository)}"]
    include:
      classes: [com.example.greeter.Greeter]
''';

void main() {
  group('schema', () {
    test('prints the schema the loader itself validates against', () async {
      final run = await _run(_project(), ['schema']);
      expect(run.code, 0);
      expect(jsonDecode(run.out), jsonDecode(bindsmithSchemaJson()));
    });
  });

  group('init', () {
    test('writes a jvm template that loads', () async {
      final dir = _project(pubspec: 'name: my_sdk\n');
      expect((await _run(dir, ['init', '--template', 'jvm'])).code, 0);
      final config = loadBindsmithConfig(_read(dir, 'bindsmith.yaml'));
      expect(config.platforms[Platform.android]!.compileSdk, '35');
      expect(config.platforms[Platform.android]!.driver, Driver.jvm);
    });

    test('writes a config that loads and a schema that describes it', () async {
      final dir = _project(pubspec: 'name: my_sdk\n');
      final run = await _run(dir, ['init']);
      expect(run.code, 0);
      expect(run.out, 'bindsmith.yaml\nbindsmith.schema.json\n');

      // The point of the template is that it is a working starting state, so
      // the check is that the loader accepts it rather than that it matches
      // some text.
      final config = loadBindsmithConfig(_read(dir, 'bindsmith.yaml'));
      expect(config.name, 'my_sdk', reason: 'the name comes from pubspec.yaml');
      expect(config.facade.library, 'lib/my_sdk.dart');
      expect(config.platforms.keys, [Platform.linux]);
      expect(
        _read(dir, 'bindsmith.yaml'),
        contains(r'$schema=bindsmith.schema.json'),
        reason: "an editor finds the schema through the file's own header",
      );
      expect(
        jsonDecode(_read(dir, 'bindsmith.schema.json')),
        isA<Map<String, Object?>>(),
      );
    });

    test('refuses to overwrite a config unless asked', () async {
      final dir = _project(bindsmith: _config);
      final run = await _run(dir, ['init']);
      expect(run.code, exitData);
      expect(run.err, contains('--force'));
      expect(_read(dir, 'bindsmith.yaml'), _config, reason: 'left alone');

      final forced = await _run(dir, ['init', '--force']);
      expect(forced.code, 0);
      expect(_read(dir, 'bindsmith.yaml'), isNot(_config));
    });

    test('says what is missing when there is no pubspec', () async {
      final run = await _run(_project(pubspec: ''), ['init']);
      expect(run.code, exitNoInput);
      expect(run.err, contains('pubspec.yaml'));
    });
  });

  group('generate', () {
    test('writes the binding, the facade and the build hook', () async {
      final dir = _project(bindsmith: _config);
      final run = await _run(dir, ['generate']);
      expect(run.code, 0, reason: run.err);
      expect(run.out.trim().split('\n'), [
        p.join('lib', 'src', 'generated', 'linux', 'c.g.dart'),
        p.join('lib', 'demo.dart'),
        p.join('lib', 'demo_io.g.dart'),
        p.join('hook', 'build.dart'),
      ]);

      final binding = _read(dir, 'lib/src/generated/linux/c.g.dart');
      expect(binding, contains('demo_add'));
      expect(
        binding,
        isNot(contains('other_thing')),
        reason: 'the include list is the pull list ffigen is given',
      );
      expect(
        binding,
        contains(
          "@ffi.DefaultAsset('package:demo/src/generated/linux/c.g.dart"
          "')",
        ),
        reason: 'the asset id follows from the output path',
      );

      expect(
        _read(dir, 'lib/demo.dart'),
        contains('demo_io.g.dart'),
        reason: 'the entry point exports its siblings',
      );

      final hook = _read(dir, 'hook/build.dart');
      expect(hook, contains('CBuilder.library'));
      expect(
        hook,
        contains("assetName: 'src/generated/linux/c.g.dart'"),
        reason: 'the hook has to declare the asset the binding names',
      );
      expect(hook, contains("sources: ['demo.c']"));
    });

    test('dispatches the dbus driver', () async {
      final dir = _project(
        bindsmith: '''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart

platforms:
  linux:
    driver: dbus
    xml: [com.example.Greeter.xml]
''',
      );
      io.File(p.join(dir, 'com.example.Greeter.xml')).writeAsStringSync(
        io.File(p.join(_root, 'fixtures', 'dbus', 'com.example.Greeter.xml'))
            .readAsStringSync(),
      );
      final run = await _run(dir, ['generate']);
      expect(run.code, 0, reason: run.err);
      expect(
        _read(dir, 'lib/src/generated/linux/dbus.g.dart'),
        contains('callGreet'),
      );
    });

    test('is byte-identical on a second run', () async {
      final dir = _project(bindsmith: _config);
      expect((await _run(dir, ['generate'])).code, 0);
      final first = {
        for (final path in [
          'lib/src/generated/linux/c.g.dart',
          'lib/demo.dart',
          'lib/demo_io.g.dart',
          'hook/build.dart',
        ])
          path: _read(dir, path),
      };
      expect((await _run(dir, ['generate'])).code, 0);
      for (final MapEntry(key: path, value: before) in first.entries) {
        expect(_read(dir, path), before, reason: '$path changed on a rerun');
      }
    });

    test('names the driver it cannot run yet instead of skipping it', () async {
      final dir = _project(
        bindsmith: '''
name: demo
output: lib/src/generated
facade:
  library: lib/demo.dart

platforms:
  macos:
    driver: swift
    include:
      types: [Greeter]
''',
      );
      final run = await _run(dir, ['generate']);
      expect(run.code, exitSoftware);
      expect(run.err, contains('swift'));
      expect(run.err, contains('macos'));
    });

    test('rejects a platform the config does not configure', () async {
      final dir = _project(bindsmith: _config);
      final run = await _run(dir, ['generate', '--platform', 'windows']);
      expect(run.code, exitUsage);
      expect(run.err, contains('linux'), reason: 'says what is configured');
    });

    test('reports every configuration problem at once', () async {
      final dir = _project(
        bindsmith: '''
name: demo
output: gen
facade:
  library: lib/demo.dart

platforms:
  linux:
    driver: c
    headers: [demo.h]
    wrapper: off
''',
      );
      final run = await _run(dir, ['generate']);
      expect(run.code, exitData);
      expect(run.err, contains('outside lib/'));
      expect(run.err, contains('"wrapper" is not something the c driver'));
    });

    test('points at init when there is no config', () async {
      final run = await _run(_project(), ['generate']);
      expect(run.code, exitNoInput);
      expect(run.err, contains('bindsmith init'));
    });

    test('reports a broken YAML file rather than throwing', () async {
      final dir = _project(bindsmith: 'name: [demo\n');
      final run = await _run(dir, ['generate']);
      expect(run.code, exitData);
    });
  });

  group('dump', () {
    test('prints the IR of every platform as JSON', () async {
      final dir = _project(bindsmith: _config);
      final run = await _run(dir, ['dump']);
      expect(run.code, 0, reason: run.err);
      final ir = jsonDecode(run.out) as Map<String, Object?>;
      expect(ir.keys, ['linux']);
      final names = [
        for (final decl in ir['linux']! as List)
          (decl as Map<String, Object?>)['name'],
      ];
      expect(names, contains('demo_add'));
    });
  });

  test('a command that only reads leaves the project alone', () async {
    final dir = _project(bindsmith: _config);
    for (final args in [
      ['dump'],
      ['explain', 'demo_add'],
    ]) {
      expect((await _run(dir, args)).code, 0, reason: args.join(' '));
    }
    expect(
      io.Directory(dir).listSync().map((e) => p.basename(e.path)).toSet(),
      {'pubspec.yaml', 'demo.h', 'bindsmith.yaml'},
      reason:
          'the drivers write their binding somewhere, and for a read-only '
          'command that somewhere is a directory that gets deleted',
    );
  });

  group('generate --check', () {
    test('passes on a freshly generated project and writes nothing', () async {
      final dir = _project(bindsmith: _config);
      expect((await _run(dir, ['generate'])).code, 0);
      final before = _read(dir, 'lib/src/generated/linux/c.g.dart');

      final run = await _run(dir, ['generate', '--check']);
      expect(run.code, 0, reason: run.err);
      expect(run.out, contains('up to date'));
      expect(
        _read(dir, 'lib/src/generated/linux/c.g.dart'),
        before,
        reason:
            'the check generates into a throwaway directory, and the '
            'output must not depend on where that is',
      );
    });

    test('names an edited file and leaves it alone', () async {
      final dir = _project(bindsmith: _config);
      expect((await _run(dir, ['generate'])).code, 0);
      io.File(p.join(dir, 'lib', 'demo_io.g.dart'))
          .writeAsStringSync('// hand-edited\n');

      final run = await _run(dir, ['generate', '--check']);
      expect(run.code, exitChanged);
      expect(run.err, contains('demo_io.g.dart is out of date'));
      expect(run.err, contains('bindsmith generate'));
      expect(_read(dir, 'lib/demo_io.g.dart'), '// hand-edited\n');
    });

    test('names a file that was never generated', () async {
      final dir = _project(bindsmith: _config);
      final run = await _run(dir, ['generate', '--check']);
      expect(run.code, exitChanged);
      expect(run.err, contains('is missing'));
    });
  });

  group('diff', () {
    test('reports no change against a dump of the same sources', () async {
      final dir = _project(bindsmith: _config);
      final dump = await _run(dir, ['dump']);
      io.File(p.join(dir, 'before.json')).writeAsStringSync(dump.out);

      final run = await _run(dir, ['diff', 'before.json']);
      expect(run.code, 0, reason: run.err);
      expect(run.out, startsWith('no change:'));
    });

    test('reports what a changed header did to the API', () async {
      final dir = _project(bindsmith: _config);
      final dump = await _run(dir, ['dump']);
      io.File(p.join(dir, 'before.json')).writeAsStringSync(dump.out);
      io.File(p.join(dir, 'demo.h')).writeAsStringSync(
        _header.replaceFirst(
          'int32_t demo_add(int32_t a, int32_t b);',
          'int32_t demo_add(int32_t a, int32_t b, int32_t c);\n'
              'int32_t demo_mul(int32_t a, int32_t b);',
        ),
      );

      final run = await _run(dir, ['diff', 'before.json']);
      expect(run.code, exitChanged);
      expect(run.out, contains('+ linux demo_mul'));
      expect(run.out, contains('~ linux demo_add'));
      expect(run.out, contains('    was  demo_add(int a, int b) -> int'));
    });

    test('says so when the dump is missing or is not one', () async {
      final dir = _project(bindsmith: _config);
      expect((await _run(dir, ['diff', 'nope.json'])).code, exitNoInput);
      io.File(p.join(dir, 'not.json')).writeAsStringSync('[]');
      final run = await _run(dir, ['diff', 'not.json']);
      expect(run.code, exitData);
      expect(run.err, contains('keyed by platform'));
      expect((await _run(dir, ['diff'])).code, exitUsage);
    });
  });

  group('explain', () {
    test('says what a symbol became and why', () async {
      final dir = _project(bindsmith: _config);
      final run = await _run(dir, ['explain', 'DemoColor']);
      expect(run.code, 0, reason: run.err);
      expect(run.out, contains('linux  enumeration DemoColor'));
      expect(
        run.out,
        contains('verify'),
        reason:
            'a C enum has an implementation-defined width, which is '
            'exactly the kind of thing explain exists to surface',
      );
      expect(run.out, contains('.DEMO_RED'));
    });

    test('a pattern that matches nothing is a usage error', () async {
      final dir = _project(bindsmith: _config);
      final run = await _run(dir, ['explain', 'Nothing*']);
      expect(run.code, exitUsage);
      expect(run.err, contains('bindsmith dump'));
      expect((await _run(dir, ['explain'])).code, exitUsage);
    });
  });

  group('watch', () {
    test('regenerates on a change and stops when the config goes', () async {
      final dir = _project(bindsmith: _config);
      final binding = io.File(p.join(dir, 'lib/src/generated/linux/c.g.dart'));
      final watching = _run(dir, ['watch', '--interval', '20']);

      await _until(binding.existsSync, 'the first generation');
      io.File(p.join(dir, 'demo.h')).writeAsStringSync(
        '$_header\nint32_t demo_mul(int32_t a, int32_t b);\n',
      );
      await _until(
        () => binding.readAsStringSync().contains('demo_mul'),
        'the regeneration after the header changed',
      );

      io.File(p.join(dir, 'bindsmith.yaml')).deleteSync();
      final run = await watching;
      expect(run.code, exitNoInput);
      expect(run.err, contains('nothing left to watch'));
      expect(RegExp('generated').allMatches(run.out).length, 2);
    });

    test('keeps watching a configuration that is broken right now', () async {
      final dir = _project(bindsmith: 'name: [demo\n');
      final watching = _run(dir, ['watch', '--interval', '20']);
      final config = io.File(p.join(dir, 'bindsmith.yaml'));

      config.writeAsStringSync(_config);
      await _until(
        () => io.File(p.join(dir, 'lib/demo.dart')).existsSync(),
        'the generation once the config parses',
      );
      config.deleteSync();
      expect((await watching).code, exitNoInput);
    });

    test('refuses a nonsense interval', () async {
      final dir = _project(bindsmith: _config);
      final run = await _run(dir, ['watch', '--interval', '0']);
      expect(run.code, exitUsage);
    });
  });

  group('resolve', () {
    test('pins what a coordinate turned out to be, transitives included', () {
      final dir = _project(bindsmith: _mavenConfig(_repository()));
      return _run(dir, ['resolve']).then((run) {
        expect(run.code, 0, reason: run.err);
        expect(run.out, contains('+ maven com.example:demo:1.0'));
        expect(run.out, contains('+ maven com.example:core:2.0'));

        final lock = parseLockfile(_read(dir, 'bindsmith.lock'));
        expect(lock.digests.keys, hasLength(2));
        // The digest is of the published file, so it is checkable against the
        // repository without rebuilding anything.
        expect(
          lock.digests['maven com.example:demo:1.0'],
          crypto.sha256.convert(utf8.encode('jar of demo')).toString(),
        );
      });
    });

    test('a second resolve needs no repository at all', () async {
      final repository = _repository();
      final dir = _project(bindsmith: _mavenConfig(repository));
      expect((await _run(dir, ['resolve'])).code, 0);
      final first = _read(dir, 'bindsmith.lock');

      // The download cache mirrors a repository's layout, so it is one: take
      // the original away entirely and the second run still resolves.
      io.Directory(repository).deleteSync(recursive: true);
      final run = await _run(dir, ['resolve', '--offline']);
      expect(run.code, 0, reason: run.err);
      expect(_read(dir, 'bindsmith.lock'), first);
    });

    test('--offline says what it would have had to fetch', () async {
      final dir = _project(bindsmith: _mavenConfig(_repository()));
      final run = await _run(dir, ['resolve', '--offline']);
      expect(run.code, exitSoftware);
      expect(run.err, contains('--offline'));
      expect(run.err, contains('demo-1.0.pom'));
      expect(io.File(p.join(dir, 'bindsmith.lock')).existsSync(), isFalse);
    });

    test('--check passes on a lock that matches and writes nothing', () async {
      final dir = _project(bindsmith: _mavenConfig(_repository()));
      expect((await _run(dir, ['resolve'])).code, 0);
      final before = io.File(p.join(dir, 'bindsmith.lock'));
      final stamp = before.lastModifiedSync();

      final run = await _run(dir, ['resolve', '--check']);
      expect(run.code, 0);
      expect(run.out, contains('up to date'));
      expect(before.lastModifiedSync(), stamp);
    });

    test('--check fails on a dependency the lock does not have', () async {
      final repository = _repository();
      final dir = _project(bindsmith: _mavenConfig(repository));
      expect((await _run(dir, ['resolve'])).code, 0);
      final lock = io.File(p.join(dir, 'bindsmith.lock'));
      final before = lock.readAsStringSync();

      io.File(p.join(dir, 'bindsmith.yaml')).writeAsStringSync(
        _mavenConfig(repository, coordinates: ['com.example:core:2.0']),
      );
      final run = await _run(dir, ['resolve', '--check']);
      expect(run.code, exitChanged);
      expect(run.out, contains('- maven com.example:demo:1.0'));
      expect(run.out, contains('run "bindsmith resolve"'));
      expect(lock.readAsStringSync(), before);
    });

    test('refuses a coordinate whose bytes are not the locked ones', () async {
      final dir = _project(bindsmith: _mavenConfig(_repository()));
      expect((await _run(dir, ['resolve'])).code, 0);
      final lock = io.File(p.join(dir, 'bindsmith.lock'));
      lock.writeAsStringSync(
        lock.readAsStringSync().replaceFirst(
          RegExp('sha256: .*'),
          "sha256: '${'ab' * 32}'",
        ),
      );

      final run = await _run(dir, ['resolve']);
      expect(run.code, exitData);
      expect(run.err, contains('com.example:'));
      expect(run.err, contains('does not change'));
    });

    test('refuses a lock it cannot read rather than overwriting it', () async {
      final dir = _project(bindsmith: _mavenConfig(_repository()));
      io.File(p.join(dir, 'bindsmith.lock'))
          .writeAsStringSync('version: 1\ncargo:\n  - name: serde\n');
      final run = await _run(dir, ['resolve']);
      expect(run.code, exitData);
      expect(run.err, contains('cargo'));
    });

    test('says so when no platform declares a dependency', () async {
      final run = await _run(_project(bindsmith: _config), ['resolve']);
      expect(run.code, 0);
      expect(run.out, contains('nothing to resolve'));
    });
  });

  group('generate jvm', () {
    test('needs bindsmith.lock before it touches Maven', () async {
      final repository = _repository();
      final dir = _project(bindsmith: _mavenConfig(repository));
      final run = await _run(dir, ['generate', '--platform', 'android']);
      expect(run.code, exitData);
      expect(run.err, contains('bindsmith.lock'));
      expect(run.err, contains('resolve'));
    });

    test('needs every declared coordinate in the lock', () async {
      final repository = _repository();
      final dir = _project(bindsmith: _mavenConfig(repository));
      expect((await _run(dir, ['resolve'])).code, 0);
      final orphan = io.Directory(
        p.join(repository, 'com', 'example', 'orphan', '1.0'),
      )..createSync(recursive: true);
      io.File(p.join(orphan.path, 'orphan-1.0.jar'))
          .writeAsStringSync('jar of orphan');
      io.File(p.join(orphan.path, 'orphan-1.0.pom')).writeAsStringSync(
        '<project xmlns="http://maven.apache.org/POM/4.0.0">'
        '<modelVersion>4.0.0</modelVersion>'
        '<groupId>com.example</groupId>'
        '<artifactId>orphan</artifactId>'
        '<version>1.0</version>'
        '</project>',
      );
      io.File(p.join(dir, 'bindsmith.yaml')).writeAsStringSync(
        _mavenConfig(
          repository,
          coordinates: ['com.example:demo:1.0', 'com.example:orphan:1.0'],
        ),
      );
      final run = await _run(dir, ['generate', '--platform', 'android']);
      expect(run.code, exitData);
      expect(run.err, contains('com.example:orphan:1.0'));
      expect(run.err, contains('resolve'));
    });

    test('findAndroidJar reads a fake SDK directory', () {
      final sdk = _fakeAndroidSdk(compileSdk: '36.1');
      final (jar, problem) = findAndroidJar({
        'ANDROID_HOME': sdk,
      }, compileSdk: '36.1');
      expect(problem, isNull);
      expect(jar, p.join(sdk, 'platforms', 'android-36.1', 'android.jar'));
    });

    test(
      'refuses to run jnigen without package:jni',
      () async {
        final repository = _repository();
        final dir = _project(bindsmith: _mavenConfig(repository));
        expect((await _run(dir, ['resolve'])).code, 0);
        final sdk = _fakeAndroidSdk();
        final run = await _runWithPackages(
          dir,
          p.join(dir, '.dart_tool', 'package_config.json'),
          ['generate', '--platform', 'android'],
          environment: {...io.Platform.environment, 'ANDROID_HOME': sdk},
        );
        expect(run.code, exitData);
        expect(run.err, contains('package:jni'));
      },
      skip: 'needs a host where package:jni does not resolve from the project',
    );

    test('writes the binding and Android glue from a lock, offline', () async {
      final blocker = await JniProject.blocker();
      if (blocker != null) {
        markTestSkipped('jnigen needs Flutter and a JDK: $blocker');
        return;
      }
      final project = await JniProject.create();
      addTearDown(project.delete);
      final repository = await _greeterRepository();
      final sdk = _fakeAndroidSdk();
      io.File(p.join(project.root, 'bindsmith.yaml'))
          .writeAsStringSync(_jvmGenerateConfig(repository));
      final packages = p.join(
        project.root,
        '.dart_tool',
        'package_config.json',
      );
      final env = {...io.Platform.environment, 'ANDROID_HOME': sdk};

      expect(
        (await _runWithPackages(project.root, packages, [
          'resolve',
        ], environment: env)).code,
        0,
      );
      final first = await _runWithPackages(project.root, packages, [
        'generate',
        '--platform',
        'android',
      ], environment: env);
      expect(first.code, 0, reason: first.err);
      expect(
        io.File(p.join(project.root, 'android', 'bindsmith.gradle'))
            .existsSync(),
        isTrue,
      );
      expect(
        io.File(p.join(project.root, 'android', 'bindsmith-rules.pro'))
            .existsSync(),
        isTrue,
      );

      final binding = _read(
        project.root,
        'lib/src/generated/android/jvm.g.dart',
      );
      final second = await _runWithPackages(project.root, packages, [
        'generate',
        '--platform',
        'android',
      ], environment: env);
      expect(second.code, 0, reason: second.err);
      expect(
        _read(project.root, 'lib/src/generated/android/jvm.g.dart'),
        binding,
      );
      expect(
        (await _runWithPackages(project.root, packages, [
          'generate',
          '--platform',
          'android',
          '--check',
        ], environment: env)).code,
        0,
      );
    }, timeout: Timeout(Duration(minutes: 10)));
  });

  test('a bad flag is a usage error, not a crash', () async {
    final run = await _run(_project(), ['generate', '--nonsense']);
    expect(run.code, exitUsage);
    expect(run.err, contains('nonsense'));
  });
}
