/// The `bindsmith` command line (plan P1-4, P6-6).
///
/// `init` writes a starter `bindsmith.yaml` and the schema an editor completes
/// it against; `doctor` says whether this machine has the toolchains the
/// configured platforms need; `resolve` pins every declared dependency in
/// `bindsmith.lock`; `generate` runs the drivers and writes every
/// generated file;
/// `generate --check` runs the same thing into a throwaway directory and
/// fails if what is committed is not what would be generated; `verify` reads
/// the generated code back and fails while anything in it still waits on a
/// human; `dump` prints
/// the IR; `diff` compares that IR against an earlier dump; `explain` says why
/// one symbol looks the way it does; `watch` regenerates while you edit;
/// `schema` prints the JSON Schema on its own.
///
/// Everything is written through injected [StringSink]s and [runBindsmith]
/// returns the exit code rather than calling `exit`, so the whole command line
/// is exercised in-process; `bin/bindsmith.dart` is the only place that
/// touches the real streams and the real process.
///
/// Exit codes follow `sysexits(3)`, so a script can tell a configuration it
/// must fix from a build that failed on it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show Platform;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:winmd/winmd.dart' as winmd;
import 'package:yaml/yaml.dart';

import '../config/config.dart';
import '../config/schema.dart';
import '../deps/lockfile.dart';
import '../deps/maven.dart';
import '../deps/npm.dart';
import '../deps/nuget.dart';
import '../deps/resolve.dart';
import '../drivers/c/c_driver.dart';
import '../drivers/c/objc_driver.dart';
import '../drivers/c/pkg_config.dart';
import '../drivers/dbus/dbus_driver.dart';
import '../drivers/dts/dts_driver.dart';
import '../drivers/jvm/jvm_driver.dart';
import '../drivers/swift/swift_driver.dart';
import '../drivers/winmd/winmd_driver.dart';
import '../emit/android_glue.dart';
import '../emit/apple_glue.dart';
import '../emit/build_hook.dart';
import '../emit/editable_regions.dart';
import '../emit/facade.dart';
import '../emit/js_interop.dart';
import '../emit/kotlin_bridge.dart';
import '../emit/layout.dart';
import '../emit/swift_bridge.dart';
import '../emit/win32.dart';
import '../ir/ir.dart';
import '../passes/fixups.dart';
import '../passes/passes.dart';
import '../verify/verify.dart';
import 'android_sdk.dart';
import 'doctor.dart';

/// The answer is no: `generate --check` found a stale file, `diff` found a
/// changed symbol, `doctor` found a toolchain missing. The convention of
/// `diff(1)` and `git diff --exit-code`.
const exitChanged = 1;

/// Bad arguments (`EX_USAGE`).
const exitUsage = 64;

/// `bindsmith.yaml` was read but cannot be used (`EX_DATAERR`).
const exitData = 65;

/// A file the command needs is not there (`EX_NOINPUT`).
const exitNoInput = 66;

/// Generation itself failed (`EX_SOFTWARE`).
const exitSoftware = 70;

/// Runs the command line and returns the process exit code.
Future<int> runBindsmith(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  String? workingDirectory,
}) async {
  final directory = workingDirectory ?? Directory.current.path;
  final runner =
      CommandRunner<int>('bindsmith', 'One config, six Flutter platforms.')
        ..addCommand(_Init(out, directory))
        ..addCommand(_Doctor(out, directory))
        ..addCommand(_Resolve(out, directory))
        ..addCommand(_Generate(out, err, directory))
        ..addCommand(_Verify(out, err, directory))
        ..addCommand(_Dump(out, directory))
        ..addCommand(_Diff(out, directory))
        ..addCommand(_Explain(out, directory))
        ..addCommand(_Watch(out, err, directory))
        ..addCommand(_Schema(out));
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    err.writeln(e);
    return exitUsage;
  } on ConfigException catch (e) {
    err.writeln(e);
    return exitData;
  } on LockException catch (e) {
    err.writeln(e);
    return exitData;
  } on MavenException catch (e) {
    err.writeln('bindsmith: ${e.message}');
    return exitSoftware;
  } on NpmException catch (e) {
    err.writeln('bindsmith: ${e.message}');
    return exitSoftware;
  } on NugetException catch (e) {
    err.writeln('bindsmith: ${e.message}');
    return exitSoftware;
  } on PkgConfigException catch (e) {
    err.writeln('bindsmith: ${e.message}');
    return exitSoftware;
  } on ProcessException catch (e) {
    err.writeln('bindsmith: ${e.message}');
    return exitSoftware;
  } on _Failure catch (e) {
    err.writeln('bindsmith: ${e.message}');
    return e.code;
  }
}

/// A command giving up with a message and an exit code.
final class _Failure implements Exception {
  _Failure(this.code, this.message);

  final int code;
  final String message;
}

// ---------------------------------------------------------------------------
// Commands

final class _Init extends Command<int> {
  _Init(this._out, this._directory) {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'bindsmith.yaml',
        help: 'Where to write the configuration.',
      )
      ..addOption(
        'template',
        allowed: ['c', 'jvm'],
        defaultsTo: 'c',
        help: 'Which starter configuration to write.',
      )
      ..addFlag(
        'force',
        help: 'Overwrite an existing configuration.',
        negatable: false,
      );
  }

  final StringSink _out;
  final String _directory;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Write a starter bindsmith.yaml and the schema an editor checks it '
      'against.';

  @override
  int run() {
    final config = File(p.join(_directory, argResults!.option('config')!));
    if (config.existsSync() && !argResults!.flag('force')) {
      throw _Failure(
        exitData,
        '${p.relative(config.path, from: _directory)} already exists; '
        'pass --force to overwrite it',
      );
    }
    final package = _packageName(config.parent.path);
    final schema = File(p.join(config.parent.path, 'bindsmith.schema.json'));
    config
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        _template(
          package,
          template: argResults!.option('template')!,
          schema: p.basename(schema.path),
        ),
      );
    schema.writeAsStringSync(bindsmithSchemaJson());
    for (final file in [config, schema]) {
      _out.writeln(p.relative(file.path, from: _directory));
    }
    return 0;
  }
}

final class _Generate extends Command<int> {
  _Generate(this._out, this._err, this._directory) {
    _addProjectOptions(argParser);
    argParser.addFlag(
      'check',
      help:
          'Generate into a throwaway directory and fail if what is committed '
          'differs. Writes nothing.',
      negatable: false,
    );
  }

  final StringSink _out;
  final StringSink _err;
  final String _directory;

  @override
  String get name => 'generate';

  @override
  String get description => 'Generate the bindings and the facade.';

  @override
  Future<int> run() async {
    final project = _Project.open(_directory, argResults!);
    if (argResults!.flag('check')) return _check(project);

    final files = (await _emit(project, outputRoot: project.root)).files;
    for (final path in files.keys) {
      _write(project.root, path, files[path]!);
      _out.writeln(p.relative(p.join(project.root, path), from: _directory));
    }
    return 0;
  }

  /// Generation has to be reproducible (rule 6), so the check is the whole run
  /// again into a directory that is thrown away, compared against what is on
  /// disk. Nothing in the project is touched, which is what makes it safe to
  /// run in CI on a clean checkout.
  Future<int> _check(_Project project) async {
    final files = await _inScratch(
      (root) async => (await _emit(project, outputRoot: root)).files,
    );
    final stale = <String, String>{};
    for (final MapEntry(key: path, value: source) in files.entries) {
      final file = File(p.join(project.root, path));
      if (!file.existsSync()) {
        stale[path] = 'missing';
      } else if (_normalize(file.readAsStringSync()) != _normalize(source)) {
        stale[path] = 'out of date';
      }
    }
    if (stale.isEmpty) {
      _out.writeln('${files.length} generated files are up to date');
      return 0;
    }
    for (final MapEntry(key: path, value: why) in stale.entries) {
      _err.writeln('$path is $why');
    }
    _err.writeln('bindsmith: run "bindsmith generate" and commit the result');
    return exitChanged;
  }
}

final class _Verify extends Command<int> {
  _Verify(this._out, this._err, this._directory) {
    _addProjectOptions(argParser);
  }

  final StringSink _out;
  final StringSink _err;
  final String _directory;

  @override
  String get name => 'verify';

  @override
  String get description =>
      'Check the committed generated code: markers still waiting on a human, '
      'the size budget, and one public API across the io and web facades.';

  /// Reads what is on disk instead of generating again, which is the point of
  /// having both: `generate --check` says whether the output is *current*,
  /// this says whether it is *finished*, and it needs no toolchain to say so.
  @override
  int run() {
    final project = _Project.open(_directory, argResults!);
    final names = facadeFileNames(
      project.config.name,
      project.config.platforms.keys,
    );
    String? facadePath(String? name) =>
        name == null ? null : project.layout.facade(name);
    final (ioFacade, webFacade) = (facadePath(names.io), facadePath(names.web));
    final sources = <String, String>{};
    for (final path in [
      for (final platform in project.platforms)
        project.layout.binding(platform),
      project.layout.facade(names.entry),
      ?ioFacade,
      ?webFacade,
      if (project.layout.builds.isNotEmpty) Layout.hook,
    ]) {
      final file = File(p.join(project.root, path));
      if (!file.existsSync()) {
        throw _Failure(
          exitNoInput,
          '$path has not been generated; run "bindsmith generate"',
        );
      }
      sources[path] = _normalize(file.readAsStringSync());
    }

    final markers = [
      for (final MapEntry(key: path, value: source) in sources.entries)
        ...findMarkers(path, source),
    ];
    for (final finding in markers) {
      _err.writeln('${finding.file}:${finding.line}: ${finding.what}');
    }

    // Only a facade with both groups can disagree with itself.
    final drift = ioFacade == null || webFacade == null
        ? const <String>[]
        : facadeDrift(
            publicApi(sources[ioFacade]!),
            publicApi(sources[webFacade]!),
          );
    if (drift.isNotEmpty) {
      _err.writeln(
        'bindsmith: $ioFacade and $webFacade do not declare the same API:',
      );
      for (final difference in drift) {
        _err.writeln('  $difference');
      }
    }

    final lines = sources.values.map(countLines).reduce((a, b) => a + b);
    final budget = project.config.verify.lineBudget;
    final over = budget != null && lines > budget;
    if (over) {
      _err.writeln(
        'bindsmith: the generated output is $lines lines, over the '
        'size_budget of $budget',
      );
    }

    // `markers: warn` is the only thing that decides whether a marker blocks;
    // drift and the budget are not opinions the configuration can hold.
    final blocking =
        markers.isNotEmpty &&
        project.config.verify.markers == MarkerPolicy.error;
    if (blocking) {
      _err.writeln(
        'bindsmith: ${markers.length} marker(s) still need a human; '
        'acknowledge one by deleting its annotation or with a fixups entry '
        'carrying "ack: true", or set "verify: { markers: warn }"',
      );
    }
    if (blocking || over || drift.isNotEmpty) return exitChanged;
    _out.writeln(
      '${sources.length} generated files verified, $lines lines'
      '${markers.isEmpty ? '' : ', ${markers.length} marker(s) warned about'}',
    );
    return 0;
  }
}

final class _Dump extends Command<int> {
  _Dump(this._out, this._directory) {
    _addProjectOptions(argParser);
  }

  final StringSink _out;
  final String _directory;

  @override
  String get name => 'dump';

  @override
  String get description =>
      'Print the IR as JSON, including everything that was dropped.';

  @override
  Future<int> run() async {
    final project = _Project.open(_directory, argResults!);
    _out.writeln(
      _encode(
        await _inScratch(
          (root) async => (await _emit(project, outputRoot: root)).ir,
        ),
      ),
    );
    return 0;
  }
}

final class _Diff extends Command<int> {
  _Diff(this._out, this._directory) {
    _addProjectOptions(argParser);
  }

  final StringSink _out;
  final String _directory;

  @override
  String get name => 'diff';

  @override
  String get invocation => 'bindsmith diff <earlier-dump.json>';

  @override
  String get description =>
      'Compare the API against an earlier "bindsmith dump", symbol by symbol.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw _Failure(
        exitUsage,
        'diff takes exactly one earlier dump: run '
        '"bindsmith dump > before.json", then "bindsmith diff before.json"',
      );
    }
    final file = File(p.join(_directory, rest.single));
    if (!file.existsSync()) throw _Failure(exitNoInput, 'no ${rest.single}');
    final before = _symbols(_decode(file));
    final project = _Project.open(_directory, argResults!);
    final after = _symbols(
      await _inScratch(
        (root) async => (await _emit(project, outputRoot: root)).ir,
      ),
    );

    var changed = 0;
    for (final key in {...before.keys, ...after.keys}.toList()..sort()) {
      final (was, now) = (before[key], after[key]);
      if (was == now) continue;
      changed++;
      if (was == null) {
        _out.writeln('+ $key  $now');
      } else if (now == null) {
        _out.writeln('- $key  $was');
      } else {
        _out
          ..writeln('~ $key  $now')
          ..writeln('    was  $was');
      }
    }
    _out.writeln(
      changed == 0
          ? 'no change: ${after.length} symbols'
          : '$changed changed of ${after.length} symbols',
    );
    return changed == 0 ? 0 : exitChanged;
  }
}

final class _Explain extends Command<int> {
  _Explain(this._out, this._directory) {
    _addProjectOptions(argParser);
  }

  final StringSink _out;
  final String _directory;

  @override
  String get name => 'explain';

  @override
  String get invocation => 'bindsmith explain <symbol pattern>';

  @override
  String get description =>
      'Say what one symbol became on each platform, and every marker on it.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw _Failure(
        exitUsage,
        'explain takes one symbol pattern, spelled the way an "include:" '
        'entry is: Type, Type.member or native.id#member',
      );
    }
    final pattern = SymbolPattern.parse(rest.single);
    final project = _Project.open(_directory, argResults!);
    final ir = await _inScratch(
      (root) async => (await _emit(project, outputRoot: root)).ir,
    );

    var found = 0;
    for (final MapEntry(key: platform, value: decls) in ir.entries) {
      for (final decl in decls) {
        final whole = pattern.matchesDecl(decl);
        final members = decl is TypeDecl
            ? [
                for (final member in decl.members)
                  if (whole || pattern.matchesMember(decl, member)) member,
              ]
            : const <Member>[];
        if (!whole && members.isEmpty) continue;
        found++;
        _out.writeln('${platform.name}  ${_shape(decl)}');
        if (decl.native case final native?) {
          _out.writeln('  native  $native');
        }
        if (decl.loc case final loc?) {
          _out.writeln(
            '  from    ${loc.file}${loc.line == null ? '' : ':${loc.line}'}',
          );
        }
        for (final marker in decl.markers) {
          _out.writeln('  ${marker.kind.name}  ${marker.reason}');
        }
        if (decl is FunctionDecl) {
          for (final p in decl.params) {
            if (p.docs != null) _out.writeln('  ${p.name}: ${p.docs}');
          }
        }
        for (final member in members) {
          _out.writeln('  .${_member(member)}');
          for (final marker in member.markers) {
            _out.writeln('    ${marker.kind.name}  ${marker.reason}');
          }
        }
      }
    }
    if (found == 0) {
      throw _Failure(
        exitUsage,
        'nothing matches "${rest.single}"; "bindsmith dump" lists every '
        'symbol that was generated',
      );
    }
    return 0;
  }
}

final class _Watch extends Command<int> {
  _Watch(this._out, this._err, this._directory) {
    _addProjectOptions(argParser);
    argParser.addOption(
      'interval',
      help: 'Milliseconds between checks.',
      defaultsTo: '500',
    );
  }

  final StringSink _out;
  final StringSink _err;
  final String _directory;

  @override
  String get name => 'watch';

  @override
  String get description =>
      'Regenerate whenever the configuration or one of its headers changes.';

  @override
  Future<int> run() async {
    final ms = int.tryParse(argResults!.option('interval')!);
    if (ms == null || ms <= 0) {
      throw _Failure(exitUsage, '--interval takes a positive number of ms');
    }
    final interval = Duration(milliseconds: ms);
    final config = File(p.join(_directory, argResults!.option('config')!));
    if (!config.existsSync()) {
      throw _Failure(
        exitNoInput,
        'no ${p.relative(config.path, from: _directory)} to watch',
      );
    }

    var seen = <String, DateTime?>{};
    while (config.existsSync()) {
      final now = _stamps(config);
      if (!_same(seen, now)) {
        // Taken before generating, not after: a header edited while the run is
        // in flight has to trigger the next one rather than be absorbed.
        seen = now;
        await _once();
      }
      await Future<void>.delayed(interval);
    }
    _err.writeln(
      'bindsmith: ${p.relative(config.path, from: _directory)} is gone; '
      'nothing left to watch',
    );
    return exitNoInput;
  }

  /// One pass. A configuration being edited is broken half the time, which is
  /// exactly when watching is worth having: report and keep going.
  Future<void> _once() async {
    try {
      final project = _Project.open(_directory, argResults!);
      final files = (await _emit(project, outputRoot: project.root)).files;
      for (final path in files.keys) {
        _write(project.root, path, files[path]!);
      }
      _out.writeln('generated ${files.length} files');
    } on ConfigException catch (e) {
      _err.writeln(e);
    } on _Failure catch (e) {
      _err.writeln('bindsmith: ${e.message}');
    }
  }

  /// The configuration and every header it names, each with its modification
  /// time; a file that is not there yet is watched for arriving.
  Map<String, DateTime?> _stamps(File config) {
    final paths = <String>{config.path};
    try {
      final loaded = loadBindsmithConfig(
        config.readAsStringSync(),
        sourceUrl: config.uri,
      );
      for (final spec in loaded.platforms.values) {
        for (final header in spec.headers) {
          paths.add(p.join(config.parent.path, header));
        }
        for (final xml in spec.xml) {
          paths.add(p.join(config.parent.path, xml));
        }
      }
    } on ConfigException {
      // Nothing but the configuration itself is known yet; watch that.
    }
    return {
      for (final path in paths)
        path: File(path).existsSync() ? File(path).lastModifiedSync() : null,
    };
  }

  static bool _same(Map<String, DateTime?> a, Map<String, DateTime?> b) =>
      a.length == b.length &&
      a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);
}

final class _Schema extends Command<int> {
  _Schema(this._out);

  final StringSink _out;

  @override
  String get name => 'schema';

  @override
  String get description =>
      'Print the JSON Schema for bindsmith.yaml, for an editor to check '
      'against.';

  @override
  int run() {
    _out.writeln(bindsmithSchemaJson());
    return 0;
  }
}

final class _Doctor extends Command<int> {
  _Doctor(this._out, this._directory) {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'bindsmith.yaml',
        help: 'The configuration whose platforms decide what is needed.',
      )
      ..addFlag('json', help: 'Print the report as JSON.', negatable: false);
  }

  final StringSink _out;
  final String _directory;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check that this machine has the toolchains the configured platforms '
      'need, and say how to install the ones it does not.';

  /// Without a `bindsmith.yaml` every check is advisory, so a fresh machine
  /// can be looked over before there is anything to configure.
  @override
  int run() {
    final file = File(p.join(_directory, argResults!.option('config')!));
    final checks = doctor(
      config: file.existsSync()
          ? loadBindsmithConfig(file.readAsStringSync(), sourceUrl: file.uri)
          : null,
    );
    final missing = checks.where((c) => c.required && !isOk(c)).length;
    if (argResults!.flag('json')) {
      _out.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'os': hostPlatform().name,
          'ok': missing == 0,
          'checks': [
            for (final check in checks)
              {
                'tool': check.tool.name,
                'required': check.required,
                'found': check.found,
                'problem': check.problem,
                'fix': check.fix,
              },
          ],
        }),
      );
    } else {
      for (final check in checks) {
        _out.writeln(
          '${_state(check).padRight(8)}${check.tool.name.padRight(12)}'
          '${check.problem ?? check.found ?? 'not found — ${check.tool.purpose}'}',
        );
        if (!isOk(check)) _out.writeln('${' ' * 20}fix: ${check.fix}');
      }
      _out.writeln(
        missing == 0
            ? 'ready: ${checks.length} checks'
            : '$missing of ${checks.length} checks missing something bindsmith '
                  'needs',
      );
    }
    return missing == 0 ? 0 : exitChanged;
  }

  /// `warn` rather than `fail` for a toolchain nothing configured asks for.
  static String _state(Check check) =>
      isOk(check) ? 'ok' : (check.required ? 'FAIL' : 'warn');
}

final class _Resolve extends Command<int> {
  _Resolve(this._out, this._directory) {
    _addProjectOptions(argParser);
    argParser
      ..addFlag(
        'check',
        help:
            'Fail instead of writing when the lock is not what resolution '
            'produces. Exit 1 if it differs.',
        negatable: false,
      )
      ..addFlag(
        'offline',
        help:
            'Resolve from the download cache only, never over the network. '
            'Exit 70 if something is missing from it.',
        negatable: false,
      );
  }

  final StringSink _out;
  final String _directory;

  @override
  String get name => 'resolve';

  @override
  String get description =>
      'Resolve every declared dependency and pin what it turned out to be in '
      '${Lockfile.fileName}. Commit that file.';

  @override
  Future<int> run() async {
    final project = _Project.open(_directory, argResults!);
    final check = argResults!.flag('check');
    final file = File(p.join(project.root, Lockfile.fileName));
    final existing = file.existsSync()
        ? parseLockfile(file.readAsStringSync(), sourceUrl: file.uri)
        : null;

    final lock = await _resolve(
      project,
      offline: argResults!.flag('offline'),
      cache: Directory(
        p.join(project.root, '.dart_tool', 'bindsmith', 'maven'),
      ),
    );
    final before = existing?.digests ?? const <String, String>{};
    final after = lock.digests;

    // A published coordinate is immutable, so the same one arriving with a
    // different digest is never a routine update: either the lock was edited
    // or something is serving other bytes under that name. Refuse rather than
    // rewrite the line that would have recorded it (rule 3).
    final changed = [
      for (final MapEntry(key: key, value: digest) in after.entries)
        if (before[key] case final was? when was != digest) key,
    ];
    if (changed.isNotEmpty) {
      throw _Failure(
        exitData,
        'the bytes behind ${changed.join(', ')} are not the ones '
        '${Lockfile.fileName} records, and a released artifact does not '
        'change. Check where it was served from; delete the entry to accept '
        'the new bytes deliberately.',
      );
    }

    if (after.isEmpty && existing == null) {
      _out.writeln('nothing to resolve: no platform declares dependencies');
      return 0;
    }

    final text = writeLockfile(lock);
    final differences = [
      for (final key in ({...before.keys, ...after.keys}).toList()..sort())
        if (!after.containsKey(key))
          '- $key'
        else if (!before.containsKey(key))
          '+ $key',
    ];
    for (final line in differences) {
      _out.writeln(line);
    }

    if (check) {
      // Re-serialising the parsed lock rather than comparing the file's text,
      // so that whitespace someone tidied is not a failure while a missing
      // artifact is.
      if (existing != null && writeLockfile(existing) == text) {
        _out.writeln('${Lockfile.fileName} is up to date');
        return 0;
      }
      _out.writeln(
        '${Lockfile.fileName} is not what resolving produces; '
        'run "bindsmith resolve"',
      );
      return exitChanged;
    }

    file.writeAsStringSync(text);
    _out.writeln('${Lockfile.fileName}: ${after.length} pinned');
    return 0;
  }
}

/// Resolves every kind of dependency the configuration declares.
///
/// Platforms are merged into one lock rather than kept apart: a coordinate
/// names the same bytes whoever asked for it, and a build that needs a
/// dependency for two platforms should not download or record it twice.
Future<Lockfile> _resolve(
  _Project project, {
  required bool offline,
  required Directory cache,
}) async {
  final maven = <String, LockedArtifact>{};
  for (final platform in project.platforms) {
    final deps = project.config.platforms[platform]!.deps;
    if (deps.maven.isEmpty) continue;
    final resolver = MavenResolver(
      cache: cache,
      repositories: deps.repositories.isEmpty ? null : deps.repositories,
      // The cache mirrors a repository's own layout, so a second resolve reads
      // it and never calls this; one that does call it is one the cache could
      // not answer, which is exactly what `--offline` is asking about.
      fetch: offline
          ? (url) => throw MavenException(
              '$url is not in the download cache, and --offline forbids '
              'fetching it. Resolve once with a network first.',
            )
          : mavenFetch,
    );
    for (final artifact in await resolver.resolve([
      for (final coordinate in deps.maven) coordinate.toString(),
    ])) {
      maven['${artifact.coordinate}'] = (
        coordinate: '${artifact.coordinate}',
        extension: artifact.extension,
        sha256: artifact.sha256,
      );
    }
    // Sources jars of direct coordinates only. Missing is normal — many
    // artifacts publish none — and the lock then omits them, so an
    // offline run never looks for a file it did not pin. The coordinate
    // is `g:a:v:sources` (`Coordinate.toString`); a YAML `classifier:`
    // field would be an unknown key and force lock version 2.
    for (final artifact in await resolver.fetchSources([
      for (final coordinate in deps.maven) coordinate.toString(),
    ])) {
      maven['${artifact.coordinate}'] = (
        coordinate: '${artifact.coordinate}',
        extension: artifact.extension,
        sha256: artifact.sha256,
      );
    }
  }
  final extra = await resolveNpmAndNuget(
    npmPackages: {
      for (final platform in project.platforms)
        ...project.config.platforms[platform]!.deps.npm,
    },
    nugetPackages: {
      for (final platform in project.platforms)
        ...project.config.platforms[platform]!.deps.nuget,
    },
    npmCache: Directory(p.join(project.root, '.dart_tool', 'bindsmith', 'npm')),
    nugetCache: Directory(
      p.join(project.root, '.dart_tool', 'bindsmith', 'nuget'),
    ),
    offline: offline,
  );
  return Lockfile({
    if (maven.isNotEmpty) 'maven': maven.values.toList(),
    ...extra,
  });
}

Future<List<MavenArtifact>> _mavenArtifacts({
  required String root,
  required DepsConfig deps,
  required Lockfile lock,
}) async {
  if (deps.maven.isEmpty) return const [];
  final resolver = MavenResolver(
    cache: Directory(p.join(root, '.dart_tool', 'bindsmith', 'maven')),
    repositories: deps.repositories.isEmpty ? null : deps.repositories,
    fetch: (url) => throw MavenException(
      '$url is not in the download cache; run "bindsmith resolve" with a '
      'network first',
    ),
  );
  final artifacts = await resolver.resolve([
    for (final coordinate in deps.maven) coordinate.toString(),
  ]);
  for (final artifact in artifacts) {
    final key = 'maven ${artifact.coordinate}';
    final expected = lock.digests[key];
    if (expected != null && expected != artifact.sha256) {
      throw _Failure(
        exitData,
        'the bytes behind ${artifact.coordinate} are not the ones '
        '${Lockfile.fileName} records; run "bindsmith resolve"',
      );
    }
  }
  return artifacts;
}

// ---------------------------------------------------------------------------
// The pipeline

void _addProjectOptions(ArgParser parser) {
  parser
    ..addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'bindsmith.yaml',
      help: 'The configuration to read.',
    )
    ..addMultiOption(
      'platform',
      abbr: 'p',
      allowed: [for (final platform in Platform.values) platform.name],
      help: 'Limit the run to these platforms. Default: every configured one.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: "Show the generators' own diagnostics.",
      negatable: false,
    );
}

/// A loaded `bindsmith.yaml` and everything derived from it.
final class _Project {
  _Project({
    required this.root,
    required this.config,
    required this.layout,
    required this.platforms,
    required this.logger,
  });

  factory _Project.open(String directory, ArgResults args) {
    final file = File(p.join(directory, args.option('config')!));
    if (!file.existsSync()) {
      throw _Failure(
        exitNoInput,
        'no ${p.relative(file.path, from: directory)}; '
        'run "bindsmith init" to write one',
      );
    }
    final root = file.parent.path;
    final config = loadBindsmithConfig(
      file.readAsStringSync(),
      sourceUrl: file.uri,
    );
    final asked = args.multiOption('platform');
    final platforms = [
      for (final platform in Platform.values)
        if (config.platforms.containsKey(platform) &&
            (asked.isEmpty || asked.contains(platform.name)))
          platform,
    ];
    if (platforms.isEmpty) {
      throw _Failure(
        exitUsage,
        'none of the platforms asked for are configured; '
        '${p.relative(file.path, from: directory)} has '
        '${config.platforms.keys.map((q) => q.name).join(', ')}',
      );
    }
    final logger = Logger.detached('bindsmith')
      ..level = args.flag('verbose') ? Level.ALL : Level.OFF
      ..onRecord.listen((record) => stderr.writeln(record.message));
    return _Project(
      root: root,
      config: config,
      layout: Layout(config, package: _packageName(root)),
      platforms: platforms,
      logger: logger,
    );
  }

  /// The directory holding `bindsmith.yaml`; every configured path is relative
  /// to it.
  final String root;
  final BindsmithConfig config;
  final Layout layout;
  final List<Platform> platforms;
  final Logger logger;

  /// Runs each platform's driver and its passes, with the drivers writing
  /// their binding under [outputRoot].
  Future<Map<Platform, List<Decl>>> load(String outputRoot) async {
    final ir = <Platform, List<Decl>>{};
    for (final platform in platforms) {
      final spec = config.platforms[platform]!;
      final decls = await _driver(platform, spec, outputRoot);
      ir[platform] = runPasses(decls, [
        // Member-level `include:` patterns, which a driver's pull list cannot
        // apply: it is given a name and there is no IR yet.
        if (_patterns(spec).isNotEmpty) includePass(_patterns(spec)),
        nullabilityPass(),
        if (spec.driver == Driver.c) cFacadePass(),
        if (spec.driver == Driver.dts) dtsFacadePass(),
        if (config.fixups.isNotEmpty) fixupsPass(config.fixups),
      ]);
    }
    return ir;
  }

  Future<List<Decl>> _driver(
    Platform platform,
    PlatformConfig spec,
    String outputRoot,
  ) async {
    // An absolute output path wins over the driver's working directory, so
    // headers still resolve against the project while the binding lands
    // wherever the command wanted it.
    final output = p.join(outputRoot, layout.binding(platform));
    // A linked Apple framework lives in the process. A C hook has to name
    // the asset the binding's `@DefaultAsset` looks up, so only then is an id
    // handed down. Swift still receives one: swiftgen's lookup needs a value
    // even when the module is linked rather than loaded as a code asset.
    final assetId = spec.build == null && spec.driver == Driver.objc
        ? null
        : layout.assetId(platform);
    final include = _include(spec);
    return switch (spec.driver) {
      Driver.c => CDriver(
        platform: platform,
        headers: spec.headers,
        include: include,
        assetId: layout.assetId(platform),
        compilerOptions: pkgConfigCflags(spec.deps.pkgConfig),
      ).load(workingDirectory: root, output: output, logger: logger),
      Driver.objc =>
        ObjcDriver(
          platform: platform,
          headers: spec.headers,
          include: include,
          assetId: assetId,
        ).load(
          workingDirectory: root,
          output: output,
          objcOutput: p.join(outputRoot, layout.glue(platform)),
          logger: logger,
        ),
      Driver.jvm => _jvm(
        platform: platform,
        spec: spec,
        output: output,
        include: include,
      ),
      Driver.dbus => DbusDriver(
        xmlFiles: spec.xml,
      ).load(workingDirectory: root, output: output),
      Driver.swift => _swift(
        platform: platform,
        spec: spec,
        output: output,
        outputRoot: outputRoot,
        assetId: layout.assetId(platform),
        include: include,
      ),
      Driver.dts => _dts(spec: spec, output: output),
      Driver.winmd => _winmd(spec: spec, output: output),
    };
  }

  Future<List<Decl>> _dts({
    required PlatformConfig spec,
    required String output,
  }) async {
    if (spec.deps.npm.isEmpty && spec.sources.isEmpty) {
      throw _Failure(
        exitData,
        'the dts driver needs deps.npm or sources with a .d.ts file',
      );
    }
    final files = [...spec.sources];
    if (spec.deps.npm.isNotEmpty) {
      final lockFile = File(p.join(root, Lockfile.fileName));
      if (!lockFile.existsSync()) {
        throw _Failure(
          exitData,
          'no ${Lockfile.fileName}; run "bindsmith resolve" before generating',
        );
      }
      final lock = parseLockfile(
        lockFile.readAsStringSync(),
        sourceUrl: lockFile.uri,
      );
      for (final coordinate in spec.deps.npm) {
        if (!lock.digests.containsKey('npm $coordinate')) {
          throw _Failure(
            exitData,
            '${Lockfile.fileName} does not pin $coordinate; '
            'run "bindsmith resolve"',
          );
        }
      }
      final artifacts = await NpmResolver(
        cache: Directory(p.join(root, '.dart_tool', 'bindsmith', 'npm')),
        fetch: (url) => throw NpmException(
          '$url is not in the download cache; run "bindsmith resolve" with a '
          'network first',
        ),
      ).resolve(spec.deps.npm);
      for (final artifact in artifacts) {
        final expected = lock.digests['npm ${artifact.coordinate}'];
        if (expected != null && expected != artifact.sha256) {
          throw _Failure(
            exitData,
            'the bytes behind ${artifact.coordinate} are not the ones '
            '${Lockfile.fileName} records; run "bindsmith resolve"',
          );
        }
      }
      files.addAll([
        for (final artifact in artifacts)
          p.relative(artifact.entrypoint.path, from: root),
      ]);
    }
    final sidecar = await DtsDriver.bundledSidecarDir();
    var ir = await DtsDriver(sidecarDir: sidecar)
        .load(files, workingDirectory: root);
    final patterns = _patterns(spec);
    if (patterns.isNotEmpty) {
      ir = includePass(patterns)(ir);
    }
    File(output)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(emitJsInterop(ir));
    return ir;
  }

  Future<List<Decl>> _winmd({
    required PlatformConfig spec,
    required String output,
  }) async {
    if (spec.deps.nuget.isEmpty) {
      throw _Failure(
        exitData,
        'the winmd driver needs deps.nuget with a PackageId@version, for '
        'example Microsoft.Windows.SDK.Win32Metadata@60.0.34-preview',
      );
    }
    final functions = {...?spec.include[IncludeKind.functions]};
    final types = {
      ...?spec.include[IncludeKind.types],
      ...?spec.include[IncludeKind.structs],
      ...?spec.include[IncludeKind.enums],
    };
    if (functions.isEmpty && types.isEmpty) {
      throw _Failure(
        exitData,
        'the winmd driver needs include.functions, include.types, '
        'include.structs or include.enums',
      );
    }
    final lockFile = File(p.join(root, Lockfile.fileName));
    if (!lockFile.existsSync()) {
      throw _Failure(
        exitData,
        'no ${Lockfile.fileName}; run "bindsmith resolve" before generating',
      );
    }
    final lock = parseLockfile(
      lockFile.readAsStringSync(),
      sourceUrl: lockFile.uri,
    );
    for (final coordinate in spec.deps.nuget) {
      if (!lock.digests.containsKey('nuget $coordinate')) {
        throw _Failure(
          exitData,
          '${Lockfile.fileName} does not pin $coordinate; '
          'run "bindsmith resolve"',
        );
      }
    }
    final artifacts = await NugetResolver(
      cache: Directory(p.join(root, '.dart_tool', 'bindsmith', 'nuget')),
      fetch: (url) => throw NugetException(
        '$url is not in the download cache; run "bindsmith resolve" with a '
        'network first',
      ),
    ).resolve(spec.deps.nuget);
    for (final artifact in artifacts) {
      final expected = lock.digests['nuget ${artifact.coordinate}'];
      if (expected != null && expected != artifact.sha256) {
        throw _Failure(
          exitData,
          'the bytes behind ${artifact.coordinate} are not the ones '
          '${Lockfile.fileName} records; run "bindsmith resolve"',
        );
      }
    }
    final readers = [
      for (final artifact in artifacts)
        winmd.MetadataReader.read(artifact.winmd.readAsBytesSync()),
    ];
    final index = readers.length == 1
        ? winmd.MetadataIndex.fromReader(readers.single)
        : winmd.MetadataIndex.fromReaders(readers);
    final List<Decl> ir;
    try {
      ir = WinmdDriver(index: index, functions: functions, types: types).load();
    } on ArgumentError catch (e) {
      throw _Failure(exitData, e.message?.toString() ?? '$e');
    }
    File(output)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(emitWin32(ir).source);
    return ir;
  }

  Future<List<Decl>> _jvm({
    required Platform platform,
    required PlatformConfig spec,
    required String output,
    required bool Function(String)? include,
  }) async {
    final classPath = await _jvmClassPath(platform, spec);
    final docs = await _jvmSourceDocs(spec);
    try {
      return await JvmDriver(
        platform: platform,
        classes: spec.include[IncludeKind.classes] ?? const <String>[],
        classPath: classPath,
        sourcePath: docs.javaDirs,
        kotlinSources: docs.kotlinFiles,
        include: include,
      ).load(workingDirectory: root, output: output, logger: logger);
    } on StateError catch (e) {
      if (e.message.contains('package:jni')) {
        throw _Failure(
          exitData,
          'package:jni does not resolve from this project; add jni to the '
          'pubspec dependencies and run flutter pub get',
        );
      }
      rethrow;
    }
  }

  Future<List<Decl>> _swift({
    required Platform platform,
    required PlatformConfig spec,
    required String output,
    required String outputRoot,
    required String assetId,
    required bool Function(String)? include,
  }) async {
    final module = spec.module!;
    final bridgePath = layout.swiftBridge(platform, module);
    final wrapperPath = layout.swiftWrapper(platform, module);

    Future<List<Decl>> run({
      List<String> objcCompatibleSources = const [],
      Set<String> objcCompatibleTypes = const {},
    }) =>
        SwiftDriver(
          platform: platform,
          module: module,
          sources: spec.sources,
          objcCompatibleSources: objcCompatibleSources,
          objcCompatibleTypes: objcCompatibleTypes,
          include: include,
          assetId: assetId,
        ).load(
          workingDirectory: root,
          output: output,
          objcOutput: p.join(outputRoot, layout.glue(platform)),
          wrapperOutput: p.join(outputRoot, wrapperPath),
          logger: logger,
        );

    switch (spec.wrapper) {
      case WrapperMode.off:
        return run();
      case WrapperMode.only:
        final binding = File(output);
        if (!binding.existsSync()) {
          throw _Failure(
            exitData,
            'wrapper: only needs an existing binding at '
            '${layout.binding(platform)}; run generate with wrapper: auto '
            'first',
          );
        }
        return swiftToIr(
          binding.readAsStringSync(),
          platform: platform,
          loc: spec.sources.length == 1 ? SourceLoc(spec.sources.single) : null,
        );
      case WrapperMode.auto:
        final first = await run();
        final bridge = emitSwiftBridge(first);
        if (bridge.classes.isEmpty) return first;
        final bridgeFile = File(p.join(outputRoot, bridgePath));
        final merged = mergeEditableRegion(
          body: unwrapGenerated(bridge.source),
          existing: bridgeFile.existsSync()
              ? bridgeFile.readAsStringSync()
              : null,
        );
        bridgeFile.parent.createSync(recursive: true);
        bridgeFile.writeAsStringSync(merged);
        return run(
          objcCompatibleSources: [bridgePath],
          objcCompatibleTypes: bridge.classes,
        );
    }
  }

  Future<({List<String> javaDirs, List<String> kotlinFiles})> _jvmSourceDocs(
    PlatformConfig spec,
  ) async {
    if (spec.deps.maven.isEmpty) {
      return (javaDirs: const <String>[], kotlinFiles: const <String>[]);
    }
    final resolver = MavenResolver(
      cache: Directory(p.join(root, '.dart_tool', 'bindsmith', 'maven')),
      repositories: spec.deps.repositories.isEmpty
          ? null
          : spec.deps.repositories,
      fetch: (url) => throw MavenException(
        '$url is not in the download cache; run "bindsmith resolve" first',
      ),
    );
    final sourceArtifacts = await resolver.fetchSources([
      for (final coordinate in spec.deps.maven) coordinate.toString(),
    ]);
    return mavenSourceDocs(sourceArtifacts, root: root);
  }

  Future<List<String>> _jvmClassPath(
    Platform platform,
    PlatformConfig spec,
  ) async {
    final maven = <String>[];
    if (spec.deps.maven.isNotEmpty) {
      final lockFile = File(p.join(root, Lockfile.fileName));
      if (!lockFile.existsSync()) {
        throw _Failure(
          exitData,
          'no ${Lockfile.fileName}; run "bindsmith resolve" before generating',
        );
      }
      final lock = parseLockfile(
        lockFile.readAsStringSync(),
        sourceUrl: lockFile.uri,
      );
      for (final coordinate in spec.deps.maven) {
        final key = 'maven $coordinate';
        if (!lock.digests.containsKey(key)) {
          throw _Failure(
            exitData,
            '${Lockfile.fileName} does not pin $coordinate; run "bindsmith resolve"',
          );
        }
      }

      final artifacts = await _mavenArtifacts(
        root: root,
        deps: spec.deps,
        lock: lock,
      );
      maven.addAll([
        for (final artifact in artifacts)
          p.relative(artifact.file.path, from: root),
      ]);
    }

    if (platform != Platform.android) return maven;

    final compileSdk = spec.compileSdk!;
    final (jar, problem) = findAndroidJar(
      io.Platform.environment,
      compileSdk: compileSdk,
    );
    if (jar == null) {
      throw _Failure(
        exitData,
        problem ??
            'ANDROID_HOME or ANDROID_SDK_ROOT is not set; export one and '
                'install platforms;android-$compileSdk',
      );
    }
    return [p.relative(jar, from: root), ...maven];
  }

  /// The `include:` patterns of one platform, flattened: which kind a symbol
  /// was listed under matters to the reader, not to the matcher.
  static List<String> _patterns(PlatformConfig spec) => [
    for (final patterns in spec.include.values) ...patterns,
  ];

  /// The pull list a driver is given, `null` when nothing was listed.
  static bool Function(String)? _include(PlatformConfig spec) {
    final patterns = [
      for (final source in _patterns(spec)) SymbolPattern.parse(source),
    ];
    if (patterns.isEmpty) return null;
    return (name) => patterns.any((q) => q.touchesName(name));
  }
}

String? _kotlinPackage(PlatformConfig spec) {
  for (final name in spec.include[IncludeKind.classes] ?? const <String>[]) {
    if (name.contains('*')) continue;
    final last = name.lastIndexOf('.');
    if (last > 0) return name.substring(0, last);
  }
  return null;
}

/// One whole run: the IR, and every generated file keyed by its path relative
/// to the project root.
///
/// The drivers write their own binding, so [outputRoot] is where they are
/// pointed — the project itself for `generate` and `watch`, a throwaway
/// directory for every command that only reads.
Future<({Map<Platform, List<Decl>> ir, Map<String, String> files})> _emit(
  _Project project, {
  required String outputRoot,
}) async {
  final ir = await project.load(outputRoot);
  final files = <String, String>{};
  for (final platform in ir.keys) {
    final spec = project.config.platforms[platform]!;
    final kotlinPackage = spec.driver == Driver.jvm
        ? _kotlinPackage(spec)
        : null;
    for (final path in [
      project.layout.binding(platform),
      project.layout.glue(platform),
      if (spec.driver == Driver.swift && spec.module != null) ...[
        project.layout.swiftWrapper(platform, spec.module!),
        if (spec.wrapper != WrapperMode.off)
          project.layout.swiftBridge(platform, spec.module!),
      ],
      if (kotlinPackage != null)
        project.layout.kotlinBridge(platform, kotlinPackage),
    ]) {
      final file = File(p.join(outputRoot, path));
      if (file.existsSync()) files[path] = file.readAsStringSync();
    }
    if (spec.wrapper == WrapperMode.only) {
      files.remove(project.layout.binding(platform));
      files.remove(project.layout.glue(platform));
      if (spec.driver == Driver.swift && spec.module != null) {
        files.remove(project.layout.swiftWrapper(platform, spec.module!));
      }
    }
    if (spec.wrapper != WrapperMode.off && spec.driver == Driver.jvm) {
      final package = _kotlinPackage(spec);
      final decls = ir[platform];
      if (package != null && decls != null) {
        final path = project.layout.kotlinBridge(platform, package);
        final bridge = emitKotlinBridge(decls, package: package);
        if (bridge.classes.isNotEmpty) {
          files[path] = mergeEditableRegion(
            body: unwrapGenerated(bridge.source),
            existing: files[path],
          );
        }
      }
    }
  }
  final facade = emitFacade(
    ir,
    FacadeOptions(
      library: project.config.name,
      bindings: {
        for (final platform in ir.keys)
          platform: project.layout.bindingImports[platform]!,
      },
      unsupported: project.config.facade.unsupported,
    ),
  );
  for (final MapEntry(key: name, value: source) in facade.entries) {
    files[project.layout.facade(name)] = source;
  }
  if (emitBuildHook(project.layout) case final hook?) files[Layout.hook] = hook;
  if (ir[Platform.android] case final decls?
      when project.config.platforms[Platform.android]!.driver == Driver.jvm) {
    files.addAll(emitAndroidGlue(project.layout, decls));
  }
  for (final platform in [Platform.ios, Platform.macos]) {
    if (ir[platform] case final decls?) {
      final driver = project.config.platforms[platform]!.driver;
      if (driver == Driver.objc || driver == Driver.swift) {
        files.addAll(emitAppleGlue(project.layout, decls, platform: platform));
      }
    }
  }
  return (ir: ir, files: files);
}

/// Runs [body] against a directory that is deleted afterwards, so a command
/// that only reads never writes into the project.
Future<T> _inScratch<T>(Future<T> Function(String outputRoot) body) async {
  final tmp = Directory.systemTemp.createTempSync('bindsmith_run_');
  try {
    return await body(tmp.path);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// Writes [source] to [path] under [root], leaving a file that already says
/// exactly that alone so its modification time does not move.
void _write(String root, String path, String source) {
  final file = File(p.join(root, path));
  if (file.existsSync() && file.readAsStringSync() == source) return;
  file
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(source);
}

/// Line endings are the one difference a checkout can introduce on its own
/// (rule 8), so `--check` compares text rather than bytes.
String _normalize(String source) => source.replaceAll('\r\n', '\n');

// ---------------------------------------------------------------------------
// Rendering

String _encode(Map<Platform, List<Decl>> ir) =>
    const JsonEncoder.withIndent('  ').convert({
      for (final MapEntry(key: platform, value: decls) in ir.entries)
        platform.name: irToJson(decls),
    });

Map<Platform, List<Decl>> _decode(File file) {
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    throw _Failure(
      exitData,
      '${p.basename(file.path)} is not JSON: ${e.message}',
    );
  }
  if (json is! Map<String, Object?>) {
    throw _Failure(
      exitData,
      '${p.basename(file.path)} is not a "bindsmith dump": it should be an '
      'object keyed by platform',
    );
  }
  return {
    for (final MapEntry(key: name, value: decls) in json.entries)
      Platform.values.byName(name): irFromJson(decls! as List<Object?>),
  };
}

/// Every symbol in [ir] as `platform name` → its shape. That is what a diff
/// compares: markers and documentation move around constantly, a signature
/// changing is what breaks a caller.
Map<String, String> _symbols(Map<Platform, List<Decl>> ir) {
  final symbols = <String, String>{};
  for (final MapEntry(key: platform, value: decls) in ir.entries) {
    for (final decl in decls) {
      symbols['${platform.name} ${decl.name}'] = _shape(decl);
      if (decl is! TypeDecl) continue;
      for (final member in decl.members) {
        symbols['${platform.name} ${decl.name}.${member.name}'] = _member(
          member,
        );
      }
    }
  }
  return symbols;
}

String _shape(Decl decl) => switch (decl) {
  TypeDecl() =>
    '${decl.kind.name} ${decl.name}'
        '${decl.typeParams.isEmpty ? '' : '<${decl.typeParams.join(', ')}>'}',
  FunctionDecl() =>
    '${decl.name}(${_params(decl.params)}) -> '
        '${_returns(decl.returns, decl.async)}',
  VariableDecl() =>
    '${decl.isConst ? 'const ' : ''}${decl.name}: ${_type(decl.type)}',
};

String _member(Member member) {
  final head = switch (member.kind) {
    MemberKind.field || MemberKind.constant =>
      '${member.isStatic ? 'static ' : ''}${member.name}: '
          '${_type(member.returns)}',
    _ =>
      '${member.isStatic ? 'static ' : ''}${member.name}'
          '(${_params(member.params)}) -> '
          '${_returns(member.returns, member.async)}',
  };
  final paramDocs = [
    for (final p in member.params)
      if (p.docs != null) '    ${p.name}: ${p.docs}',
  ];
  if (paramDocs.isEmpty) return head;
  return '$head\n${paramDocs.join('\n')}';
}

String _params(List<Param> params) => [
  for (final param in params)
    '${param.named ? '{' : ''}${_type(param.type)} ${param.name}'
        '${param.named ? '}' : ''}',
].join(', ');

String _returns(TypeRef type, Async async) => switch (async) {
  Async.none => _type(type),
  Async.future => 'Future<${_type(type)}>',
  Async.stream => 'Stream<${_type(type)}>',
  Async.callback => 'callback<${_type(type)}>',
};

String _type(TypeRef type) =>
    '${type.name}'
    '${type.args.isEmpty ? '' : '<${type.args.map(_type).join(', ')}>'}'
    '${type.nullability == Nullability.nullable ? '?' : ''}';

// ---------------------------------------------------------------------------
// The project on disk

/// The name of the Dart package at [directory], which asset ids are built from.
String _packageName(String directory) {
  final pubspec = File(p.join(directory, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw _Failure(
      exitNoInput,
      'no pubspec.yaml beside the configuration: the generated bindings need '
      'the package name for their asset ids',
    );
  }
  final name = (loadYaml(pubspec.readAsStringSync()) as YamlMap?)?['name'];
  if (name is! String || name.isEmpty) {
    throw _Failure(exitData, 'pubspec.yaml has no "name"');
  }
  return name;
}

String _template(
  String package, {
  required String template,
  required String schema,
}) => switch (template) {
  'jvm' => _jvmTemplate(package, schema: schema),
  _ => _cTemplate(package, schema: schema),
};

String _cTemplate(String package, {required String schema}) =>
    '''
# yaml-language-server: \$schema=$schema
name: $package
output: lib/src/generated
facade:
  library: lib/$package.dart

platforms:
  # One entry per platform, each naming the driver that reads its native API.
  # `inherit:` copies another platform's entry rather than repeating it.
  linux:
    driver: c
    headers: [third_party/example/include/example.h]
    include: { functions: ["example_*"], structs: ["example_*"] }
''';

String _jvmTemplate(String package, {required String schema}) =>
    '''
# yaml-language-server: \$schema=$schema
name: $package
output: lib/src/generated
facade:
  library: lib/$package.dart

platforms:
  android:
    driver: jvm
    compile_sdk: 35
    deps:
      maven: [com.example:library:1.0.0]
    include:
      classes: [com.example.*]
''';
