/// The toolchains the JVM suites shell out to: the Kotlin compiler with the
/// runtime jars of its own distribution, and a throwaway package that can run
/// jnigen and load `package:jni`.
library;

import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:io' as io show Platform;

import 'package:bindsmith/bindsmith.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

// packages/bindsmith → repository root.
final _root = p.dirname(p.dirname(Directory.current.path));

/// The Kotlin compiler and the jars that ship beside it.
typedef Kotlin = ({String exe, String stdlib, String coroutines});

/// The Kotlin compiler together with the stdlib and coroutines jars of the
/// same distribution, or `null` when neither `KOTLIN_HOME`, a mise install,
/// nor `PATH` leads to a complete one.
///
/// The jars have to come from the same root as the compiler: a mise shim on
/// `PATH` is a script in a directory with no `lib/` next to it.
Future<Kotlin?> findKotlin() async {
  final roots = <String>[];
  if (io.Platform.environment['KOTLIN_HOME'] case final home?) roots.add(home);
  final installs = Directory(
    p.join(
      io.Platform.environment['HOME'] ?? '',
      '.local',
      'share',
      'mise',
      'installs',
      'kotlin',
    ),
  );
  if (installs.existsSync()) {
    for (final entry in installs.listSync()) {
      roots.add(p.join(entry.path, 'kotlinc'));
    }
  }
  final onPath =
      await Process.run(io.Platform.isWindows ? 'where' : 'which', [
        'kotlinc',
      ]).then(
        (r) => r.exitCode == 0
            ? (r.stdout as String).trim().split('\n').first.trim()
            : null,
        onError: (_) => null,
      );
  if (onPath != null && onPath.isNotEmpty) {
    roots.add(p.dirname(p.dirname(onPath)));
  }

  for (final root in roots) {
    final stdlib = p.join(root, 'lib', 'kotlin-stdlib.jar');
    final coroutines = p.join(root, 'lib', 'kotlinx-coroutines-core-jvm.jar');
    if (!File(stdlib).existsSync() || !File(coroutines).existsSync()) continue;
    for (final name in ['kotlinc', 'kotlinc.bat']) {
      final exe = p.join(root, 'bin', name);
      if (File(exe).existsSync()) {
        return (exe: exe, stdlib: stdlib, coroutines: coroutines);
      }
    }
  }
  return null;
}

/// Whether `exe args` starts and exits with 0.
Future<bool> commandRuns(String exe, List<String> args) => Process.run(
  exe,
  args,
  runInShell: io.Platform.isWindows,
).then((r) => r.exitCode == 0, onError: (_) => false);

/// A package resolved by `flutter pub get`, which is the only way to have
/// `package:jni`: jni declares a Flutter SDK constraint, so this pure-Dart
/// workspace can never depend on it. jnigen runs against it in a separate
/// process — it calls `exit(1)` when something goes wrong — and so does
/// every program that calls a generated binding.
final class JniProject {
  JniProject._(this.root);

  final String root;

  String get _packages => p.join(root, '.dart_tool', 'package_config.json');

  /// Why no [JniProject] can be made on this host, or `null`.
  static Future<String?> blocker() async {
    if (!await commandRuns('flutter', ['--version'])) {
      return 'no Flutter SDK on PATH, and package:jni needs one; '
          'run `mise install`';
    }
    if (!await commandRuns('java', ['-version'])) {
      return 'no JDK on PATH; run `mise install`';
    }
    return null;
  }

  static Future<JniProject> create() async {
    final root = Directory.systemTemp.createTempSync('bindsmith_jni_').path;
    final bindsmith = p.join(_root, 'packages', 'bindsmith');
    File(p.join(root, 'pubspec.yaml')).writeAsStringSync('''
name: bindsmith_jni_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  bindsmith:
    path: ${bindsmith.replaceAll(r'\', '/')}
  jni: ^1.0.3
''');
    File(p.join(root, 'tool', 'generate.dart'))
      ..parent.createSync()
      ..writeAsStringSync(_generate);
    await _check('flutter', ['pub', 'get'], root);
    return JniProject._(root);
  }

  /// Runs [JvmDriver.load] with the repository root as both its working
  /// directory and the current one, so jnigen's summarizer is built into
  /// and reused from the repository's `.dart_tool/jnigen/`. The packages come
  /// from this project, which is where jnigen falls back to for `jni`.
  Future<(List<Decl>, String)> generate({
    required List<String> classes,
    List<String> sourcePath = const [],
    List<String> kotlinSources = const [],
    List<String> classPath = const [],
    List<String>? include,
  }) async {
    final out = Directory(p.join(root, 'out'))..createSync(recursive: true);
    final binding = p.join(out.path, 'binding.g.dart');
    final ir = p.join(out.path, 'ir.json');
    final job = File(p.join(out.path, 'job.json'))
      ..writeAsStringSync(
        jsonEncode({
          'root': _root,
          'classes': classes,
          'sourcePath': sourcePath,
          'kotlinSources': kotlinSources,
          'classPath': classPath,
          'include': include,
          'output': binding,
          'ir': ir,
        }),
      );
    await _check(io.Platform.resolvedExecutable, [
      '--packages=$_packages',
      p.join(root, 'tool', 'generate.dart'),
      job.path,
    ], _root);
    return (
      irFromJson(jsonDecode(File(ir).readAsStringSync()) as List<Object?>),
      File(binding).readAsStringSync(),
    );
  }

  /// Builds `libdartjni` (CMake) and `jni.jar` (Gradle) into the repository's
  /// `.dart_tool/bindsmith/<jni-version>/`, once: both take minutes, and a
  /// later run reuses them. Returns that directory, which is `Jni.spawn`'s
  /// `dylibDir`.
  Future<String> buildJni() async {
    final config = await findPackageConfig(Directory(root));
    final jni = p.basename(p.fromUri(config!['jni']!.root));
    final out = p.join(_root, '.dart_tool', 'bindsmith', jni);
    const libraries = ['libdartjni.dylib', 'libdartjni.so', 'dartjni.dll'];
    if (!File(p.join(out, 'jni.jar')).existsSync() ||
        !libraries.any((l) => File(p.join(out, l)).existsSync())) {
      await _check(io.Platform.resolvedExecutable, [
        'run',
        'jni:setup',
        '--build-path',
        out,
      ], root);
    }
    return out;
  }

  /// Runs [runner], a program that imports [binding] as
  /// `package:bindsmith_jni_probe/binding.g.dart`.
  Future<ProcessResult> run(
    String runner, {
    required String binding,
    List<String> args = const [],
  }) {
    File(p.join(root, 'lib', 'binding.g.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(binding);
    File(p.join(root, 'bin', 'runner.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(runner);
    return Process.run(io.Platform.resolvedExecutable, [
      '--packages=$_packages',
      p.join(root, 'bin', 'runner.dart'),
      ...args,
    ], workingDirectory: root);
  }

  void delete() => Directory(root).deleteSync(recursive: true);
}

Future<void> _check(String exe, List<String> args, String directory) async {
  final r = await Process.run(
    exe,
    args,
    workingDirectory: directory,
    runInShell: io.Platform.isWindows,
  );
  if (r.exitCode != 0) {
    throw StateError(
      '`${p.basename(exe)} ${args.join(' ')}` failed in $directory:\n'
      '${r.stdout}${r.stderr}',
    );
  }
}

/// `tool/generate.dart` in a [JniProject]: [JvmDriver.load] as a JSON job
/// file describes it, with the IR written beside the binding.
const _generate = r'''
import 'dart:convert';
import 'dart:io' hide Platform;

import 'package:bindsmith/bindsmith.dart';

Future<void> main(List<String> args) async {
  final job =
      jsonDecode(File(args.single).readAsStringSync()) as Map<String, Object?>;
  List<String> list(String key) => [
    for (final s in (job[key] as List<Object?>? ?? const [])) s as String,
  ];
  final include = job['include'] == null ? null : list('include').toSet();
  final ir = await JvmDriver(
    platform: Platform.android,
    classes: list('classes'),
    sourcePath: list('sourcePath'),
    kotlinSources: list('kotlinSources'),
    classPath: list('classPath'),
    include: include?.contains,
  ).load(
    workingDirectory: job['root'] as String,
    output: job['output'] as String,
  );
  File(job['ir'] as String).writeAsStringSync(jsonEncode(irToJson(ir)));
}
''';
