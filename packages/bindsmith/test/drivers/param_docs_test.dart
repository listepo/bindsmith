import 'package:bindsmith/src/drivers/c/ffigen_adapter.dart';
import 'package:bindsmith/src/drivers/dts/dts_driver.dart';
import 'package:bindsmith/src/drivers/swift/symbolgraph.dart';
import 'package:bindsmith/src/ir/ir.dart';
import 'package:test/test.dart';

void main() {
  group('splitCommentDocs', () {
    test('Doxygen @param and @returns', () {
      const docs = '''
Adds a shape.
@param scene The scene to add to.
@param shape The shape to add.
@param options.tone Not a real parameter.
@returns The new id.
''';
      final split = splitCommentDocs(docs, paramNames: {'scene', 'shape'});
      expect(split.memberDocs, contains('Adds a shape.'));
      expect(split.memberDocs, contains('options.tone'));
      expect(split.memberDocs, contains('Returns The new id.'));
      expect(split.paramDocs['scene'], 'The scene to add to.');
      expect(split.paramDocs['shape'], 'The shape to add.');
    });

    test('direction prefixes', () {
      final split = splitCommentDocs(
        r'@param [out] rect The buffer.',
        paramNames: {'rect'},
      );
      expect(split.paramDocs['rect'], '(out) The buffer.');
    });
  });

  group('dts @param', () {
    test('matched param leaves member docs', () {
      final decls = dtsToIr({
        'version': 1,
        'decls': [
          {
            'kind': 'function',
            'name': 'wait',
            'params': [
              {
                'name': 'delayMs',
                'type': {'k': 'keyword', 'name': 'number'},
              },
            ],
            'returns': {'k': 'keyword', 'name': 'void'},
            'tags': [
              {
                'tag': 'param',
                'name': 'delayMs',
                'text': 'How long to wait, in milliseconds.',
              },
              {'tag': 'param', 'name': 'options.tone', 'text': 'ignored'},
            ],
          },
        ],
      });
      final fn = decls.single as FunctionDecl;
      expect(fn.params.single.docs, 'How long to wait, in milliseconds.');
      expect(fn.docs, contains('options.tone'));
      expect(fn.docs, isNot(contains('delayMs')));
    });
  });

  group('splitSwiftDocs', () {
    test('Parameter and Returns lines', () {
      const docs = '''
Greets someone.
- Parameter name: The person to greet.
- Returns: A greeting.
''';
      final split = splitSwiftDocs(docs, paramNames: {'name'});
      expect(split.memberDocs, 'Greets someone.\nReturns A greeting.');
      expect(split.paramDocs['name'], 'The person to greet.');
    });
  });
}
