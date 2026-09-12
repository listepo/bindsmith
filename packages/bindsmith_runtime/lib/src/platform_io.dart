import 'dart:io' as io;

import 'platform.dart';

/// The platform this program is running on, resolved through `dart:io`.
BindsmithPlatform get bindsmithPlatform {
  if (io.Platform.isAndroid) return BindsmithPlatform.android;
  if (io.Platform.isIOS) return BindsmithPlatform.ios;
  if (io.Platform.isMacOS) return BindsmithPlatform.macos;
  if (io.Platform.isWindows) return BindsmithPlatform.windows;
  if (io.Platform.isLinux) return BindsmithPlatform.linux;
  throw UnsupportedError(
    'bindsmith_runtime: unknown operating system '
    '"${io.Platform.operatingSystem}"',
  );
}
