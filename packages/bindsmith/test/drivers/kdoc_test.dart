import 'package:bindsmith/src/drivers/jvm/kdoc.dart';
import 'package:test/test.dart';

void main() {
  group('splitKDoc', () {
    test('@param lands in paramDocs when the name exists', () {
      final split = splitKDoc(
        '@param name The name.\nBody.',
        paramNames: {'name'},
      );
      expect(split.paramDocs, {'name': 'The name.'});
      expect(split.memberDocs, 'Body.');
    });

    test('@param for a missing name stays in member prose', () {
      final split = splitKDoc(
        '@param ghost Nowhere.\nBody.',
        paramNames: {'name'},
      );
      expect(split.paramDocs, isEmpty);
      expect(split.memberDocs, contains('`ghost`: Nowhere.'));
      expect(split.memberDocs, contains('Body.'));
    });

    test('@return becomes Returns prose', () {
      final split = splitKDoc('Greets.\n@return the greeting');
      expect(split.memberDocs, contains('Returns the greeting'));
    });

    test('@property on a class documents a primary-constructor property', () {
      final split = splitKDoc(
        'Class doc.\n@property bar Bar docs.',
        propertyNames: {'bar'},
      );
      expect(split.memberDocs, 'Class doc.');
      expect(split.propertyDocs, {'bar': 'Bar docs.'});
    });

    test('@constructor is separated from class prose', () {
      final split = splitKDoc('Class doc.\n@constructor Ctor docs.');
      expect(split.memberDocs, 'Class doc.');
      expect(split.constructorDocs, 'Ctor docs.');
    });
  });

  group('kdocs', () {
    test('skips nested block comments', () {
      final map = kdocs('''
package example

/* /* still a comment */ */
/** real */
fun ok(): Int = 1
''');
      expect(map.keys, contains('example.FileKt.ok()'));
      expect(map['example.FileKt.ok()']!.memberDocs, 'real');
    });

    test('ignores /** and } inside a raw string', () {
      final map = kdocs(r'''
package example

val raw = """
  /** not kdoc */
  }
"""
/** attached */
fun ok(): Int = 1
''');
      expect(map['example.FileKt.ok()']!.memberDocs, 'attached');
    });

    test('attaches through annotations between doc and declaration', () {
      final map = kdocs('''
package example

/** greets */
@JvmStatic
fun greet(name: String): String = name
''');
      expect(map['example.FileKt.greet(name)']!.memberDocs, 'greets');
    });

    test('companion const val is keyed on the outer class', () {
      final map = kdocs('''
package example

class Greeter {
  companion object {
    /** the default */
    const val PREFIX = "Hi"
  }
}
''');
      expect(map['example.Greeter.PREFIX']!.memberDocs, 'the default');
    });

    test('overload keys include parameter names', () {
      final map = kdocs('''
package example

class Greeter {
  /** one */
  fun shout(name: String): String = name

  /** two */
  fun shout(name: String, times: Int): String = name
}
''');
      expect(map['example.Greeter.shout(name)']!.memberDocs, 'one');
      expect(map['example.Greeter.shout(name,times)']!.memberDocs, 'two');
    });

    test('@Suppress drops the doc but not the declaration', () {
      final map = kdocs('''
package example

/** hidden */
@Suppress("unused")
fun secret(): Int = 0

/** visible */
fun open(): Int = 1
''');
      expect(map.containsKey('example.FileKt.secret()'), isFalse);
      expect(map['example.FileKt.open()']!.memberDocs, 'visible');
    });
  });
}
