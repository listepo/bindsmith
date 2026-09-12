import 'dart:io';

import 'package:bindsmith/src/drivers/c/header_docs.dart';
import 'package:bindsmith/src/ir/ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final geometryHeader = File(
    p.join('..', '..', 'fixtures', 'c', 'geometry', 'geometry.h'),
  ).readAsStringSync();

  group('commentAbove', () {
    test('collects contiguous comment lines directly above the declaration', () {
      const source = '''
/// kept
/// still kept
#define FOO 1
''';
      expect(
        commentAbove(source, RegExp(r'#\s*define\s+FOO\b')),
        'kept\nstill kept',
      );
    });

    test('returns null when a blank line sits above the declaration', () {
      const source = '''
/// lost

#define FOO 1
''';
      expect(
        commentAbove(source, RegExp(r'#\s*define\s+FOO\b')),
        isNull,
      );
    });

    test('reads a trailing // comment on the same line', () {
      const source = '#define BAR 2 // inline docs';
      expect(
        commentAbove(source, RegExp(r'#\s*define\s+BAR\b')),
        'inline docs',
      );
    });

    test('reads a multi-line /* */ block above the declaration', () {
      const source = '''
/*
 * First line
 * Second line
 */
#define BAZ 3
''';
      expect(
        commentAbove(source, RegExp(r'#\s*define\s+BAZ\b')),
        'First line\nSecond line',
      );
    });

    test('finds a #define inside #if', () {
      const source = '''
#if 1
/// inside if
#define IFDEFED 1
#endif
''';
      expect(
        commentAbove(source, RegExp(r'#\s*define\s+IFDEFED\b')),
        'inside if',
      );
    });
  });

  group('headerDocs', () {
    test('GEOMETRY_VERSION docs from the geometry fixture header', () {
      final docs = headerDocs(geometryHeader);
      expect(
        docs['GEOMETRY_VERSION'],
        'Library version as MAJOR * 100 + MINOR.',
      );
    });

    test('GeometryScene docs from the geometry fixture header', () {
      final docs = headerDocs(geometryHeader);
      expect(docs['GeometryScene'], startsWith('Opaque scene handle'));
    });
  });

  group('quotedIncludes', () {
    test('collects quoted includes relative to the header directory', () {
      const source = '''
#include "child.h"
#include <system.h>
#include "nested/leaf.h"
''';
      expect(quotedIncludes(source, '/tmp/include'), [
        '/tmp/include/child.h',
        '/tmp/include/nested/leaf.h',
      ]);
    });
  });

  group('macroLocationFromUsr', () {
    test('parses clang macro USR', () {
      expect(macroLocationFromUsr('c:geometry.h@128@macro@GEOMETRY_VERSION'), (
        'geometry.h',
        128,
      ));
      expect(macroLocationFromUsr('c:foo@bar'), isNull);
    });
  });

  group('mergeHeaderDocs', () {
    test('fills docs only where the IR has none', () {
      final out = mergeHeaderDocs(
        [
          VariableDecl(
            id: 'KEPT',
            name: 'KEPT',
            platform: Platform.linux,
            type: const TypeRef('int'),
            docs: 'upstream',
          ),
          VariableDecl(
            id: 'FILLED',
            name: 'FILLED',
            platform: Platform.linux,
            type: const TypeRef('int'),
          ),
        ],
        {'KEPT': 'scanner', 'FILLED': 'from header'},
      );
      expect(out[0].docs, 'upstream');
      expect(out[1].docs, 'from header');
    });
  });
}
