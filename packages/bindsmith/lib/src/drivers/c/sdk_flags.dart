/// Clang flags that make Apple SDK headers parse: `-isysroot` and `-F`.
///
/// ffigen's C path passes no sysroot, so `<CoreGraphics/CGBase.h>` is not
/// found unless the config says where the SDK is. This resolves it once, in
/// one place, and the C and Objective-C drivers both use the result.
library;

import 'dart:io';

/// Runs a host command and returns its trimmed stdout, or `null` on failure.
typedef SdkProbe = String? Function(String executable, List<String> args);

String? _hostProbe(String executable, List<String> args) {
  try {
    final r = Process.runSync(executable, args);
    if (r.exitCode != 0) return null;
    final out = (r.stdout as String).trim();
    return out.isEmpty ? null : out;
  } on ProcessException {
    return null;
  }
}

/// The macOS SDK root, from `xcrun --show-sdk-path`, or `null` off macOS or
/// when the command line tools are missing.
String? macosSdkPath({SdkProbe probe = _hostProbe, bool? isMacOS}) {
  if (!(isMacOS ?? Platform.isMacOS)) return null;
  return probe('xcrun', ['--show-sdk-path']);
}

/// Builds the clang argument list in a fixed order: `-isysroot`, `-F` for the
/// SDK's frameworks and for [frameworkPaths], then [compilerOptions] and
/// [extra] (for example pkg-config flags).
///
/// [sysroot] wins over auto-detection. `xcrun` is asked only when
/// [autoSysroot] is true and neither [sysroot] nor an explicit `-isysroot` in
/// [compilerOptions] is present.
List<String> clangFlags({
  String? sysroot,
  List<String> frameworkPaths = const [],
  List<String> compilerOptions = const [],
  List<String> extra = const [],
  bool autoSysroot = false,
  SdkProbe probe = _hostProbe,
  bool? isMacOS,
}) {
  final explicit = compilerOptions.any((o) => o.startsWith('-isysroot'));
  final root =
      sysroot ??
      (autoSysroot && !explicit
          ? macosSdkPath(probe: probe, isMacOS: isMacOS)
          : null);
  return [
    if (root != null && !explicit) ...['-isysroot', root],
    if (root != null) '-F$root/System/Library/Frameworks',
    for (final f in frameworkPaths) '-F$f',
    ...compilerOptions,
    ...extra,
  ];
}
