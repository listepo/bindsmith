/// Where the Android SDK lives and which `android.jar` jnigen binds against.
library;

import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// Matches `platforms/android-N` directory names, including minor releases.
final compileSdkPattern = RegExp(r'^\d+(\.\d+)?$');

/// The SDK root from [env], or `null` when neither variable points at one.
String? findAndroidSdkRoot(Map<String, String> env) {
  for (final name in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final sdk = env[name];
    if (sdk != null && sdk.isNotEmpty && io.Directory(sdk).existsSync()) {
      return sdk;
    }
  }
  return null;
}

/// The `android.jar` for [compileSdk], and why it is missing when it is.
///
/// Lookup order: `ANDROID_HOME`, then `ANDROID_SDK_ROOT`, then
/// `platforms/android-<compileSdk>/android.jar`.
(String? jar, String? problem) findAndroidJar(
  Map<String, String> env, {
  required String compileSdk,
}) {
  if (!compileSdkPattern.hasMatch(compileSdk)) {
    return (
      null,
      'compile_sdk "$compileSdk" is not an API level such as 35 or "36.1"',
    );
  }
  final sdk = findAndroidSdkRoot(env);
  if (sdk == null) {
    return (null, null);
  }
  final jar = io.File(
    p.join(sdk, 'platforms', 'android-$compileSdk', 'android.jar'),
  );
  if (jar.existsSync()) return (jar.path, null);
  return (
    null,
    'no android.jar for API $compileSdk under ${p.join(sdk, 'platforms')}: '
        'jnigen binds Android classes against that platform jar',
  );
}
