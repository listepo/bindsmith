/// The JSON Schema for `bindsmith.yaml`, and the validator that reads it.
///
/// One document does both jobs. `bindsmith schema` writes it to
/// `schema/bindsmith.schema.json` for an editor's YAML language server, and
/// [validateAgainstSchema] walks a parsed YAML tree against the same map, so
/// what an editor underlines and what the loader rejects cannot drift apart.
///
/// The validator is deliberately not a complete JSON Schema implementation: it
/// understands the keywords this document uses and nothing else, which a test
/// enforces from the other side by walking the schema for an unknown keyword.
/// Semantic rules that JSON Schema expresses badly — that `headers:` belongs to
/// a C driver, that `inherit:` names a platform that is configured — stay in
/// the loader, where the error can say what to do about it.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Keywords [validateAgainstSchema] acts on. Anything else in the schema is a
/// silent no-op, which is what the schema test exists to prevent.
const schemaKeywords = {
  r'$comment',
  r'$schema',
  r'$id',
  r'$ref',
  r'$defs',
  'title',
  'description',
  'type',
  'properties',
  'required',
  'additionalProperties',
  'items',
  'enum',
  'minimum',
  'oneOf',
};

final _string = {'type': 'string'};
final _strings = {
  'type': 'array',
  'items': {'type': 'string'},
};

/// Patterns selecting what a driver binds. Which kinds a driver understands is
/// the loader's business; the schema only says they are lists of patterns.
final _include = {
  'type': 'object',
  'description': 'Glob patterns for the symbols to bind, by kind.',
  'additionalProperties': false,
  'properties': {
    'classes': _strings,
    'types': _strings,
    'protocols': _strings,
    'functions': _strings,
    'structs': _strings,
    'enums': _strings,
    'globals': _strings,
    'typedefs': _strings,
    'exports': _strings,
  },
};

final _deps = {
  'type': 'object',
  'description': 'Packages to resolve and pin in bindsmith.lock.',
  'additionalProperties': false,
  'properties': {
    'maven': {
      'type': 'array',
      'description': 'group:artifact:version coordinates.',
      'items': _string,
    },
    'repositories': {
      'type': 'array',
      'description':
          'Maven repository URLs, searched in order, each https:// or a '
          'file:// directory. Defaults to Maven Central; an Android '
          "dependency usually needs Google's too.",
      'items': _string,
    },
    'swiftpm': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['url', 'from'],
        'properties': {'url': _string, 'from': _string},
      },
    },
    'npm': {'type': 'array', 'items': _string},
    'nuget': {'type': 'array', 'items': _string},
    'pkg_config': {'type': 'array', 'items': _string},
  },
};

final _platform = {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'driver': {
      'type': 'string',
      'description': 'Which generator reads the native API.',
      'enum': ['c', 'objc', 'swift', 'jvm', 'winmd', 'dts', 'dbus'],
    },
    'inherit': {
      'type': 'string',
      'description':
          'Take this platform\'s whole configuration from another one.',
      'enum': ['android', 'ios', 'macos', 'windows', 'linux', 'web'],
    },
    'headers': {
      'type': 'array',
      'description': 'Entry-point headers, for the c and objc drivers.',
      'items': _string,
    },
    'xml': {
      'type': 'array',
      'description': 'D-Bus introspection XML files, for the dbus driver.',
      'items': _string,
    },
    'deps': {r'$ref': r'#/$defs/deps'},
    'include': {r'$ref': r'#/$defs/include'},
    'compile_sdk': {
      'description':
          'Android API level whose android.jar jnigen binds against.',
      'oneOf': [
        {'type': 'integer', 'minimum': 1},
        {'type': 'string'},
      ],
    },
    'module': {
      'type': 'string',
      'description':
          'Swift module the sources and generated wrapper compile into.',
    },
    'sources': {
      'type': 'array',
      'description': 'Swift or Kotlin sources the driver reads.',
      'items': _string,
    },
    'kotlin': {
      'type': 'object',
      'description': 'How Kotlin constructs cross into Dart.',
      'additionalProperties': false,
      'properties': {
        'suspend': {
          'type': 'string',
          'enum': ['future', 'callback'],
        },
        'flow': {
          'type': 'string',
          'enum': ['stream', 'callback'],
        },
      },
    },
    'wrapper': {
      'type': 'string',
      'description':
          'Generate a native bridge for members the driver cannot carry across.',
      'enum': ['auto', 'off', 'only'],
    },
    'build': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'hook': {
          'type': 'string',
          'enum': ['native_toolchain_c', 'native_toolchain_cmake'],
        },
        'sources': {'type': 'array', 'items': _string},
      },
    },
  },
};

final _fixup = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['match'],
  'properties': {
    'match': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['symbol'],
      'properties': {
        'symbol': _string,
        'platform': {
          'type': 'string',
          'enum': ['android', 'ios', 'macos', 'windows', 'linux', 'web'],
        },
      },
    },
    'rename': _string,
    'hide': {'type': 'boolean'},
    'threading': {
      'type': 'string',
      'enum': ['any', 'main'],
    },
    'nullability': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'returns': {
          'type': 'string',
          'enum': ['nonnull', 'nullable', 'unknown'],
        },
      },
    },
    'ack': {
      'type': 'boolean',
      'description': 'A human reviewed this symbol: drop its verify markers.',
    },
  },
};

/// The schema `bindsmith schema` writes and [validateAgainstSchema] reads.
final bindsmithSchema = <String, Object?>{
  // JSON has no comments; `$comment` is JSON Schema's own place for a note.
  r'$comment': 'GENERATED BY bindsmith — do not edit.',
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  r'$id':
      'https://raw.githubusercontent.com/listepo/bindsmith/main/'
      'schema/bindsmith.schema.json',
  'title': 'bindsmith configuration',
  'description': 'One config, six Flutter platforms.',
  'type': 'object',
  'additionalProperties': false,
  'required': ['name', 'output', 'platforms'],
  'properties': {
    'name': {
      'type': 'string',
      'description': 'Base name of the generated library: my_sdk.dart.',
    },
    'output': {
      'type': 'string',
      'description':
          'Directory for the generated bindings, relative to this file. '
          'Under lib/, because a binding is reached by a package: URI.',
    },
    'facade': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'library': {
          'type': 'string',
          'description':
              'Path of the facade library to write. Under lib/, because it '
              'is what callers import.',
        },
        'unsupported': {
          'type': 'string',
          'description': 'What the facade does where a platform has no symbol.',
          'enum': ['throw', 'stub', 'omit'],
        },
      },
    },
    'platforms': {
      'type': 'object',
      'description': 'One entry per Flutter platform to generate for.',
      'additionalProperties': false,
      'properties': {
        'android': {r'$ref': r'#/$defs/platform'},
        'ios': {r'$ref': r'#/$defs/platform'},
        'macos': {r'$ref': r'#/$defs/platform'},
        'windows': {r'$ref': r'#/$defs/platform'},
        'linux': {r'$ref': r'#/$defs/platform'},
        'web': {r'$ref': r'#/$defs/platform'},
      },
    },
    'fixups': {
      'type': 'array',
      'description': 'Declarative edits applied to the IR after the drivers.',
      'items': {r'$ref': r'#/$defs/fixup'},
    },
    'verify': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'markers': {
          'type': 'string',
          'description': 'Whether an unacknowledged verify marker fails.',
          'enum': ['error', 'warn'],
        },
        'compile': {
          'type': 'array',
          'description': 'Platforms whose generated code must compile.',
          'items': {
            'type': 'string',
            'enum': ['android', 'ios', 'macos', 'windows', 'linux', 'web'],
          },
        },
        'size_budget': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'lines': {'type': 'integer', 'minimum': 1},
          },
        },
      },
    },
  },
  r'$defs': {
    'platform': _platform,
    'include': _include,
    'deps': _deps,
    'fixup': _fixup,
  },
};

/// The schema as the JSON document `bindsmith schema` writes, newline included.
String bindsmithSchemaJson() =>
    '${const JsonEncoder.withIndent('  ').convert(bindsmithSchema)}\n';

/// Checks [node] against [schema], appending one message per problem.
///
/// Every message carries the line and column of the node it is about, because
/// a configuration error the reader cannot locate is barely an error report.
void validateAgainstSchema(
  YamlNode node,
  Map<String, Object?> schema,
  List<String> problems,
) => _check(node, schema, problems);

Map<String, Object?> _resolve(Map<String, Object?> schema) {
  final ref = schema[r'$ref'];
  if (ref is! String) return schema;
  final name = ref.split('/').last;
  final defs = bindsmithSchema[r'$defs']! as Map<String, Object?>;
  return defs[name]! as Map<String, Object?>;
}

void _check(YamlNode node, Map<String, Object?> raw, List<String> problems) {
  final schema = _resolve(raw);
  final oneOf = schema['oneOf'] as List<Object?>?;
  if (oneOf != null) {
    for (final option in oneOf) {
      final branch = <String>[];
      _check(node, option! as Map<String, Object?>, branch);
      if (branch.isEmpty) return;
    }
    problems.add(
      node.span.message('expected an integer or a string such as "36.1" here'),
    );
    return;
  }
  final type = schema['type'] as String?;
  switch (type) {
    case 'object':
      if (node is! YamlMap) {
        problems.add(node.span.message('expected a mapping here'));
        return;
      }
      _object(node, schema, problems);
    case 'array':
      if (node is! YamlList) {
        problems.add(node.span.message('expected a list here'));
        return;
      }
      final items = schema['items'] as Map<String, Object?>?;
      if (items == null) return;
      for (final item in node.nodes) {
        _check(item, items, problems);
      }
    case 'string':
      if (node.value is! String) {
        problems.add(node.span.message('expected a string here'));
        return;
      }
      _enum(node, schema, problems);
    case 'boolean':
      if (node.value is! bool) {
        problems.add(node.span.message('expected true or false here'));
      }
    case 'integer':
      final value = node.value;
      if (value is! int) {
        problems.add(node.span.message('expected a whole number here'));
        return;
      }
      final minimum = schema['minimum'];
      if (minimum is int && value < minimum) {
        problems.add(node.span.message('must be at least $minimum'));
      }
  }
}

void _object(YamlMap node, Map<String, Object?> schema, List<String> problems) {
  final properties =
      (schema['properties'] as Map<String, Object?>?) ?? const {};
  for (final key in (schema['required'] as List<Object?>?) ?? const []) {
    if (node.containsKey(key)) continue;
    // A missing key has no node of its own, so the message points at the first
    // key of the mapping rather than underlining the whole mapping.
    final keys = node.nodes.keys;
    final where = keys.isEmpty ? node.span : (keys.first as YamlNode).span;
    problems.add(where.message('missing "$key"'));
  }
  for (final entry in node.nodes.entries) {
    final key = (entry.key as YamlNode).value;
    final property = properties[key];
    if (property == null) {
      if (schema['additionalProperties'] == false) {
        problems.add(
          (entry.key as YamlNode).span.message(
            'unknown key "$key"; this mapping takes '
            '${_list(properties.keys.cast<String>())}',
          ),
        );
      }
      continue;
    }
    _check(entry.value, property as Map<String, Object?>, problems);
  }
}

void _enum(YamlNode node, Map<String, Object?> schema, List<String> problems) {
  final allowed = schema['enum'] as List<Object?>?;
  if (allowed == null || allowed.contains(node.value)) return;
  problems.add(
    node.span.message(
      '"${node.value}" is not one of ${_list(allowed.cast<String>())}',
    ),
  );
}

String _list(Iterable<String> values) {
  final all = values.toList();
  if (all.length < 2) return all.join();
  return '${all.take(all.length - 1).join(', ')} and ${all.last}';
}
