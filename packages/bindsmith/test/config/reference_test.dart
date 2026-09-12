/// The configuration reference is generated from the schema (plan P8-2), so
/// the committed page is a golden: adding a key to `schema.dart` without
/// regenerating fails here rather than leaving the docs quietly wrong.
library;

import 'package:bindsmith/bindsmith.dart';
import 'package:test/test.dart';

import '../golden.dart';

void main() {
  final reference = bindsmithConfigReference();

  test('matches docs/config.md', () {
    expectGolden('../../docs/config.md', reference);
  });

  test('documents every key in the schema', () {
    // Walks the schema from the other side: a key the generator skipped —
    // because its shape is one the walker does not handle — would be an
    // undocumented key, which is the whole failure mode this page has.
    final missing = <String>[];
    void walk(Map<String, Object?> schema) {
      for (final MapEntry(key: key, value: value)
          in (schema['properties'] as Map<String, Object?>? ?? {}).entries) {
        if (!reference.contains('| `$key` |')) missing.add(key);
        final node = value! as Map<String, Object?>;
        walk(node);
        if (node['items'] case final Map<String, Object?> items) walk(items);
      }
    }

    walk(bindsmithSchema);
    for (final def
        in (bindsmithSchema[r'$defs']! as Map<String, Object?>).values) {
      walk(def! as Map<String, Object?>);
    }
    expect(missing, isEmpty);
  });

  test('every link points at a heading on the page', () {
    final headings = {
      for (final line in reference.split('\n'))
        if (line.startsWith('## '))
          line
              .substring(3)
              .toLowerCase()
              .replaceAll(RegExp('[^a-z0-9 _-]'), '')
              .replaceAll(' ', '-'),
    };
    final links = RegExp(r'\]\(#([^)]+)\)').allMatches(reference);
    expect(links, isNotEmpty);
    for (final link in links) {
      expect(headings, contains(link.group(1)), reason: link.group(0));
    }
  });
}
