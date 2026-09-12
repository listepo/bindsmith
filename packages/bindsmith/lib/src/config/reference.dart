/// The configuration reference in `docs/config.md`, written from the same
/// JSON Schema the loader validates against (plan P8-2).
///
/// Hand-written reference documentation drifts the moment a key is added, and
/// nothing fails when it does. This walks [bindsmithSchema] instead, so the
/// page, the editor's completions and what the loader rejects are three views
/// of one document; a golden test in `test/config/reference_test.dart` fails
/// when the committed page no longer matches.
///
/// What the schema cannot say — which keys a given driver reads, why a path
/// has to be under `lib/` — stays in the prose pages beside it, where it can
/// explain itself.
library;

import 'schema.dart';

/// The Markdown of `docs/config.md`, newline included.
String bindsmithConfigReference() {
  final defs = bindsmithSchema[r'$defs']! as Map<String, Object?>;
  final queue = <(String, Map<String, Object?>)>[(_root, bindsmithSchema)];
  final queued = <String>{_root};
  final body = StringBuffer();

  void enqueue(String title, Map<String, Object?> schema) {
    if (queued.add(title)) queue.add((title, schema));
  }

  // Breadth-first over the schema's own key order, so the page is stable
  // (rule 6): a section appears where the key that reaches it appears.
  while (queue.isNotEmpty) {
    final (title, schema) = queue.removeAt(0);
    final properties = schema['properties']! as Map<String, Object?>;
    final required = {...?schema['required'] as List<Object?>?};
    body
      ..writeln('## $title')
      ..writeln();
    if (schema['description'] case final String description) {
      body
        ..writeln(description)
        ..writeln();
    }
    body
      ..writeln('| Key | Type | Notes |')
      ..writeln('| --- | --- | --- |');
    for (final MapEntry(key: key, value: value) in properties.entries) {
      final node = value! as Map<String, Object?>;
      final path = title == _root ? key : '$title.$key';
      body.writeln(
        '| `$key` | ${_type(node, path, defs, enqueue)} '
        '| ${_notes(node, required: required.contains(key))} |',
      );
    }
    body.writeln();
  }
  return '$_preamble$body';
}

const _root = 'Top level';

const _preamble = '''
<!-- GENERATED from packages/bindsmith/lib/src/config/schema.dart — do not
     edit. Run `dart test` with UPDATE_GOLDENS=1 to rewrite it. -->

# Configuration reference

Every key `bindsmith.yaml` accepts, written from the JSON Schema the loader
validates against — so this page cannot drift away from what bindsmith
enforces. `bindsmith init` writes that same schema next to your configuration
and points the file at it, so an editor completes and checks these keys as you
type them.

The schema settles shape: spelling, types, which keys exist. It cannot say
which keys a *particular* driver reads — `headers:` means nothing to the JVM
driver, `include: {classes:}` means nothing to the C driver — and the loader
refuses those with a line and a column rather than ignoring them. See
[platforms.md](platforms.md) for what each driver takes.

''';

/// The type column, queueing a section for anything with keys of its own.
String _type(
  Map<String, Object?> node,
  String path,
  Map<String, Object?> defs,
  void Function(String, Map<String, Object?>) enqueue,
) {
  if (node[r'$ref'] case final String ref) {
    final name = ref.split('/').last;
    enqueue(name, defs[name]! as Map<String, Object?>);
    return '[$name](#${_slug(name)})';
  }
  return switch (node['type']) {
    'array' =>
      'list of '
          '${_type(node['items']! as Map<String, Object?>, path, defs, enqueue)}',
    'object' when node.containsKey('properties') => () {
      enqueue(path, node);
      return '[object](#${_slug(path)})';
    }(),
    final String type => type,
    _ => 'any',
  };
}

String _notes(Map<String, Object?> node, {required bool required}) {
  final notes = [
    if (required) '**Required.**',
    if (node['description'] case final String description) description,
    if (node['enum'] case final List<Object?> values)
      'One of ${values.map((v) => '`$v`').join(', ')}.',
    if (node['minimum'] case final Object minimum) 'At least $minimum.',
  ];
  return notes.isEmpty ? '—' : notes.join(' ');
}

/// The anchor GitHub derives from a heading: lowercased, punctuation dropped,
/// spaces hyphenated.
String _slug(String title) => title
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9 _-]'), '')
    .replaceAll(' ', '-');
