/// Formatting for ffigen's output without ffigen's own `dart format` call.
///
/// ffigen formats a binding by running `dart format` with the executable it
/// finds in `_findDart`: `Platform.resolvedExecutable` when that is called
/// `dart`, otherwise a `dart` file in the nearest parent directory that has
/// one. A natively built CLI (`dart build cli`) resolves to the `bindsmith`
/// binary itself, no parent holds a `dart`, and the walk is
/// `while (path.isNotEmpty) path = dirname(path)` — which never ends, because
/// `dirname('/')` is `'/'`. The result is a process at 100% CPU that never
/// reaches the formatter (P8-4). So the drivers ask ffigen not to format and
/// format in-process with `package:dart_style`, which is also one process
/// fewer and needs no SDK on the machine that runs the CLI.
library;

import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

/// Formats the Dart file at [file] in place, the way `dart format` would.
///
/// A file ffigen wrote is valid Dart, so a formatter failure is a bug worth
/// surfacing rather than swallowing.
void formatDartFile(File file) {
  final formatted = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  ).format(file.readAsStringSync());
  file.writeAsStringSync(formatted);
}

/// The `dart` executable ffigen would find for [resolvedExecutable], or `null`
/// where ffigen's own search would loop forever.
///
/// Same search as ffigen's, but bounded: it stops at the filesystem root.
String? findDartLikeFfigen(
  String resolvedExecutable, {
  bool Function(String path)? exists,
}) {
  final fileExists = exists ?? (String path) => File(path).existsSync();
  var path = resolvedExecutable;
  if (p.basenameWithoutExtension(path) == 'dart') return path;
  final name = 'dart${p.extension(path)}';
  while (true) {
    final parent = p.dirname(path);
    if (parent == path) return null;
    path = parent;
    final candidate = p.normalize(p.join(path, name));
    if (fileExists(candidate)) return candidate;
  }
}

/// Throws when a generator that runs `dart format` itself (swiftgen offers no
/// way to turn that off) would hang in this process.
void ensureFfigenCanFormat({
  String? resolvedExecutable,
  bool Function(String path)? exists,
}) {
  final exe = resolvedExecutable ?? Platform.resolvedExecutable;
  if (findDartLikeFfigen(exe, exists: exists) != null) return;
  throw StateError(
    'ffigen formats its output with `dart format` and looks for a `dart` '
    'executable next to $exe or in one of its parent directories; there is '
    'none, and ffigen would spin forever looking. Run this command with '
    '`dart run bindsmith` or from a `dart pub global activate` install, or '
    'put a `dart` next to the binary.',
  );
}
