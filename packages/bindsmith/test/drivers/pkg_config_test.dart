import 'dart:io';

import 'package:bindsmith/src/drivers/c/pkg_config.dart';
import 'package:test/test.dart';

void main() {
  group('pkgConfigCflags', () {
    test('merges flags from each package', () {
      final flags = pkgConfigCflags(
        ['gtk+-3.0', 'glib-2.0'],
        run: (args) {
          expect(args.first, '--cflags');
          return switch (args.last) {
            'gtk+-3.0' => ['-I/usr/include/gtk-3.0 -DGTK'],
            'glib-2.0' => ['-I/usr/include/glib-2.0 -pthread'],
            _ => throw StateError('unexpected package'),
          };
        },
      );
      expect(flags, [
        '-I/usr/include/gtk-3.0',
        '-DGTK',
        '-I/usr/include/glib-2.0',
        '-pthread',
      ]);
    });

    test('missing package names the package and the fix', () {
      expect(
        () => pkgConfigCflags(
          ['missing-dev'],
          run: (_) => throw const PkgConfigException(
            'pkg-config does not know package missing-dev.\n'
            'Install the development package that provides it '
            '(for example: apt install libgtk-3-dev).',
          ),
        ),
        throwsA(
          isA<PkgConfigException>().having(
            (e) => e.message,
            'message',
            allOf(contains('missing-dev'), contains('development package')),
          ),
        ),
      );
    });

    test('empty package list returns no flags', () {
      expect(pkgConfigCflags([]), isEmpty);
    });

    test('calls host pkg-config when a common package exists', () {
      if (Process.runSync('which', ['pkg-config']).exitCode != 0) return;
      for (final package in ['zlib', 'glib-2.0', 'libpng']) {
        try {
          pkgConfigCflags([package]);
          return;
        } on PkgConfigException {
          continue;
        }
      }
    });
  });
}
