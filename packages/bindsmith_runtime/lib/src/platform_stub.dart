import 'platform.dart';

/// Fallback when neither `dart:io` nor `dart:js_interop` is available.
BindsmithPlatform get bindsmithPlatform => throw UnsupportedError(
  'bindsmith_runtime: neither dart:io nor dart:js_interop is available',
);
