/// P8-4: ffigen's search for `dart` never ends in a native build. Pure.
library;

import 'package:bindsmith/bindsmith.dart';
import 'package:test/test.dart';

void main() {
  group('findDartLikeFfigen', () {
    test('a dart executable resolves to itself', () {
      expect(
        findDartLikeFfigen('/sdk/bin/dart', exists: (_) => false),
        '/sdk/bin/dart',
      );
    });

    test('finds a dart in a parent directory', () {
      // Windows spells the candidate with `\`; compare on `/`.
      String slash(String path) => path.replaceAll('\\', '/');
      final found = findDartLikeFfigen(
        '/sdk/out/bundle/bin/bindsmith',
        exists: (path) => slash(path) == '/sdk/dart',
      );
      expect(found, isNotNull);
      expect(slash(found!), '/sdk/dart');
    });

    test('stops at the filesystem root instead of looping forever', () {
      expect(
        findDartLikeFfigen('/tmp/bundle/bin/bindsmith', exists: (_) => false),
        isNull,
      );
    });
  });

  group('ensureFfigenCanFormat', () {
    test('passes when dart is found', () {
      ensureFfigenCanFormat(
        resolvedExecutable: '/sdk/bin/dart',
        exists: (_) => false,
      );
    });

    test('names the problem when it is not', () {
      expect(
        () => ensureFfigenCanFormat(
          resolvedExecutable: '/tmp/bundle/bin/bindsmith',
          exists: (_) => false,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('dart'),
          ),
        ),
      );
    });
  });
}
