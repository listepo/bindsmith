import 'dart:io' show Platform;

import 'package:bindsmith_runtime/bindsmith_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('bindsmithPlatform matches the host OS', () {
    final expected = Platform.isMacOS
        ? BindsmithPlatform.macos
        : Platform.isLinux
        ? BindsmithPlatform.linux
        : BindsmithPlatform.windows;
    expect(bindsmithPlatform, expected);
  });

  test('BindsmithUnsupported names the symbol and the platform', () {
    final error = BindsmithUnsupported('Client.connect', BindsmithPlatform.web);
    expect(error, isA<UnsupportedError>());
    expect(error.message, 'Client.connect is not available on web');
    expect(error.symbol, 'Client.connect');
    expect(error.platform, BindsmithPlatform.web);
  });

  test('BindsmithVerify is a const annotation carrying a reason', () {
    const marker = BindsmithVerify('shape differs on ios vs android');
    expect(marker.reason, 'shape differs on ios vs android');
  });
}
