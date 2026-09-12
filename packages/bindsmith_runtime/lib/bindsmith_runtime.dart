/// Tiny runtime shared by code that `bindsmith` generates.
///
/// Generated code depends on this package only; it never depends on the
/// generator itself.
library;

export 'src/platform.dart';
export 'src/platform_stub.dart'
    if (dart.library.js_interop) 'src/platform_web.dart'
    if (dart.library.io) 'src/platform_io.dart';
export 'src/unsupported.dart';
export 'src/verify.dart';
