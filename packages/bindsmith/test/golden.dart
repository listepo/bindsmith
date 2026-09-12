/// Shared helpers for emitter tests: golden files and whitespace-insensitive
/// code matching. Not a test file itself.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Drops whitespace and trailing commas so expectations survive dart_style
/// line wrapping.
String _flat(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',(?=[)\]}])'), '');

Matcher containsCode(String snippet) => predicate<String>(
  (source) => _flat(source).contains(_flat(snippet)),
  'contains (ignoring whitespace) "$snippet"',
);

/// Compares [actual] with the file at [path], relative to the package root
/// where `dart test` runs. `UPDATE_GOLDENS=1` rewrites the file instead.
void expectGolden(String path, String actual) {
  final file = File(path);
  final normalized = actual.replaceAll('\r\n', '\n');
  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(normalized);
    return;
  }
  if (!file.existsSync()) {
    fail('golden $path is missing; run with UPDATE_GOLDENS=1 to create it');
  }
  expect(
    normalized,
    file.readAsStringSync().replaceAll('\r\n', '\n'),
    reason: 'golden $path differs; rerun with UPDATE_GOLDENS=1 to accept',
  );
}
