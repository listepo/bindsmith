/// Pigeon contract (plan P0-4): the pinned `pigeon` library API we will drive
/// the channels-fallback driver through.
///
/// There is no driver yet — this pins the API surface only, so an upstream
/// rename breaks loudly here instead of silently later. `Pigeon.parseArgs`
/// builds `PigeonOptions` from CLI flags, and `PigeonOptions.swiftOutPaths`
/// normalizes the single-vs-multiple Swift outputs (pigeon 28.1+).
library;

import 'package:pigeon/pigeon.dart';
import 'package:test/test.dart';

void main() {
  test('parseArgs builds PigeonOptions for every generator output', () {
    final options = Pigeon.parseArgs([
      '--input',
      'lib/api.dart',
      '--dart_out',
      'lib/api.g.dart',
      '--java_out',
      'Api.java',
      '--swift_out',
      'Api.swift',
      '--kotlin_out',
      'Api.kt',
      '--cpp_header_out',
      'api.h',
      '--cpp_source_out',
      'api.cpp',
      '--gobject_header_out',
      'api.h',
      '--gobject_source_out',
      'api.c',
    ]);
    expect(options.input, 'lib/api.dart');
    expect(options.dartOut, 'lib/api.g.dart');
    expect(options.javaOut, 'Api.java');
    expect(options.swiftOut, 'Api.swift');
    expect(options.swiftOutPaths, ['Api.swift']);
    expect(options.kotlinOut, 'Api.kt');
    expect(options.cppHeaderOut, 'api.h');
    expect(options.cppSourceOut, 'api.cpp');
    expect(options.gobjectHeaderOut, 'api.h');
    expect(options.gobjectSourceOut, 'api.c');
  });

  test('swiftOutPaths accepts multiple outputs', () {
    final options = Pigeon.parseArgs([
      '--swift_out',
      'One.swift',
      '--swift_out',
      'Two.swift',
    ]);
    expect(options.swiftOutPaths, ['One.swift', 'Two.swift']);
  });

  test('per-language options objects exist with our flags', () {
    final options = Pigeon.parseArgs([
      '--kotlin_package',
      'com.example.sdk',
      '--java_package',
      'com.example.sdk',
      '--cpp_namespace',
      'sdk',
      '--gobject_module',
      'sdk',
    ]);
    expect(options.kotlinOptions?.package, 'com.example.sdk');
    expect(options.javaOptions?.package, 'com.example.sdk');
    expect(options.cppOptions?.namespace, 'sdk');
    expect(options.gobjectOptions?.module, 'sdk');
  });
}
