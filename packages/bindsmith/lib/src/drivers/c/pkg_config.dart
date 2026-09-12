/// Resolves `deps.pkg_config` entries into clang compiler flags.
library;

import 'dart:io';

/// Thrown when `pkg-config` is missing or cannot resolve a package.
final class PkgConfigException implements Exception {
  const PkgConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs `pkg-config --cflags` for each [packages] entry and returns the merged
/// argument list (`-I…`, `-D…`, `-pthread`, …).
///
/// [run] defaults to invoking `pkg-config` on the host; tests inject a fake.
List<String> pkgConfigCflags(
  List<String> packages, {
  List<String> Function(List<String> args)? run,
}) {
  if (packages.isEmpty) return const [];
  final exec = run ?? _runPkgConfig;
  final flags = <String>[];
  for (final package in packages) {
    try {
      final lines = exec(['--cflags', package]);
      for (final line in lines) {
        flags.addAll(_splitFlags(line));
      }
    } on PkgConfigException {
      rethrow;
    } on Object catch (e) {
      throw PkgConfigException(
        'pkg-config failed for $package: $e\n'
        'Install the development package that provides it '
        '(for example: apt install libgtk-3-dev).',
      );
    }
  }
  return flags;
}

List<String> _runPkgConfig(List<String> args) {
  ProcessResult result;
  try {
    result = Process.runSync('pkg-config', args);
  } on ProcessException catch (e) {
    throw PkgConfigException(
      'pkg-config is not installed or not on PATH: ${e.message}\n'
      'Install pkg-config and the development package for the library.',
    );
  }
  final stderr = (result.stderr as String).trim();
  if (result.exitCode != 0) {
    final package = args.last;
    if (stderr.contains('not found') || stderr.contains('No package')) {
      throw PkgConfigException(
        'pkg-config does not know package $package.\n'
        'Install the development package that provides it '
        '(for example: apt install libgtk-3-dev).',
      );
    }
    throw PkgConfigException('pkg-config --cflags $package failed: $stderr');
  }
  final stdout = (result.stdout as String).trim();
  return stdout.isEmpty ? const [] : [stdout];
}

List<String> _splitFlags(String output) {
  if (output.trim().isEmpty) return const [];
  final flags = <String>[];
  final buffer = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  for (final char in output.trim().split('')) {
    if (char == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (char == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (!inSingle && !inDouble && char == ' ') {
      if (buffer.isNotEmpty) {
        flags.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) flags.add(buffer.toString());
  return flags;
}
