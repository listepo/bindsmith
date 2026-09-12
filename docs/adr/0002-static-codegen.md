# ADR-0002: Static code generation, no runtime bridge

Status: accepted (2026-09-08)

Bindings are generated ahead of time into `.g.dart` files that call dart:ffi, package:jni, package:objective_c or dart:js_interop directly. A NativeScript-style dynamic bridge (metadata + reflective dispatch at runtime) is rejected: it needs its own runtime and interpreter (impossible under iOS AOT), disables tree-shaking, and costs about 3.5x per call. From the dynamic world we keep two ideas: the pull model (an explicit list of the APIs in use) and type generation from metadata.
