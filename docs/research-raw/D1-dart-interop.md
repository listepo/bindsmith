# Dart/Flutter Native Interop Toolchain — 2025–2026 Research Report

**Research Date:** September 8, 2026  
**Focus:** Official Dart-Lang native-interop generators and runtime libraries for mobile + desktop binding generation

---

## Executive Summary

- **FFIgen 22.0.0** (Sep 2026): Primary C/ObjC/Swift binding generator; YAML config deprecated → Dart API with `FfiGenerator` class; public library API stable via `package:ffigen`.
- **JNIgen 1.0.0** (Sep 2026): Java/Kotlin bindings generator; just reached stable "1.0" status after 75+ days of active development; Kotlin suspend/nullability supported; YAML config replaced by Dart API.
- **Pigeon 28.0.0** (Aug 2026): Cross-platform RPC code generator (Dart→Kotlin/Swift/C++/GObject); ProxyApi (native object proxies from Dart) now generating `suspend`/`async throws` by default; experimental status still applies to ProxyApi across platforms.
- **objective_c 9.6.0** (Aug 2026): Runtime library for ObjC interop (ARC, memory management, blocks); not explicitly marked "stable" but production-grade with verified publisher.
- **swift2objc**: Experimental tool in dart-lang/native monorepo; generates `@objc` wrappers for Swift APIs to make them ObjC-accessible; actively developed (Swift borrowing features in progress, Mar 2025).
- **package:jni 1.0.0** (Sep 2026): Runtime support for Java/Kotlin calling via JNI; stable.
- **Native assets (build hooks)**: Stable in Flutter 3.38+ (Sep 2024); `hook/build.dart` + `hook/link.dart` for bundling native code; tree-shaking via link hooks (Dart 3.13+).
- **Interop roadmap 2025–2026**: Direct native interop priority; thread merge complete (Android/iOS); FFIgen+JNIgen endorsed as primary strategy vs. method channels. Dart macros cancelled Jan 2025; augmentations (codegen support) shipping separately. Early access program closed Jun 2025.

---

## 1. package:ffigen — C/ObjC/Swift FFI Binding Generator

### What It Is
FFIgen parses C headers, Objective-C interfaces/protocols/categories, and (indirectly via `@objc` wrapper headers) Swift code using **libclang via FFI**. It generates Dart `dart:ffi` FFI bindings.

### How It Works

**Parser/Front-End:**
- Uses libclang (via FFI, not subprocess) to parse C/ObjC headers
- Requires LLVM 9+ on the host system (locates libclang dynamically)
- Does **not** parse C++ or raw Swift; Swift APIs must be wrapped in `@objc` annotations and exposed via generated ObjC header from `swiftc`

**IR / AST Processing:**
- Visitor pattern for filtering and transforming AST nodes (as of v22.0.0)
- Callback-based config (v20–21) replaced by setter-based visitor approach in v22

**Emitter:**
- Generates Dart code for structs/unions/typedefs/enums/functions/globals
- Supports multiple binding styles: `NativeExternalBindings` (external C functions), `DynamicLibraryBindings` (runtime lookup via `DynamicLibrary`)
- Optional `@Native` decorator for asset-based native code

**Runtime Library:**
- `package:objective_c` (v9.6.0) provides ObjCBase, ObjCBlock, ObjCProtocol runtime support

### Configuration & CLI

**Config Formats:**
- **YAML** (deprecated, will be removed in future version): `ffigen.yaml` or `pubspec.yaml` `ffigen:` section
- **Dart API** (recommended, stable): `tool/ffigen.dart` script creating `FfiGenerator` instance, then calling `generate()`
  ```dart
  final generator = FfiGenerator(
    input: Input(/* header paths, includes, etc */),
    output: DartOutput(/* dart file path */),
    visitio
r: CustomVisitor(),
  );
  await generator.generate();
  ```

**CLI UX:**
- `dart run ffigen` (if using pubspec.yaml config)
- `dart run ffigen --config custom.yaml` (custom YAML path)
- Dart API script execution via `dart run tool/ffigen.dart` (convention)

**Public Library API:**
- **`package:ffigen`** exports (v22.0.0):
  - `FfiGenerator` (main entry point)
  - `Input`, `DartOutput` (config builders)
  - `Visitor` base class
  - `Func`, `Global`, `Struct`, `Union`, `EnumClass`, `Typealias`, `ObjCInterface`, `ObjCMethod`, `ObjCProtocol`, `ObjCCategory`
  - `importFromSymbolFile()`, `importFromSymbolFiles()` (symbol import utilities)
  - Binding style options: `NativeExternalBindings`, `DynamicLibraryBindings`, `BindingStyle`

### Filters & Fixup Mechanisms
- **Member-level rename:** ObjC interface/protocol method renaming via visitor
- **Include/exclude regex:** Per-type filtering (interfaces, categories, protocols)
- **Type mapping:** Custom type overrides for C types → Dart equivalents
- **Symbol file export/import:** Share synthesized symbols across ffigen runs
- **Preamble/comments:** Preserve doc comments from C/ObjC headers
- **C++ support:** **None** (C++ bindings not supported; C++ code must be wrapped in C API first)
- **Varargs:** Supported for C variadic functions via `dart:ffi`
- **Macros/inline functions:** Limitations — macros not parsed; inline functions can be called if wrapped

### ObjC-Specific Features
- `language: objc` config key
- Filtering: `objc-interfaces`, `objc-protocols`, `objc-categories`
- Member-level filtering: `exclude-objc-methods`, etc.
- `external-versions`: ObjC framework versioning constraints
- `include-transitive-objc-*`: Include transitive ObjC dependencies

### Status & Version
- **Latest stable:** 22.0.0 (published ~15 hours before page snapshot, Sep 2026)
- **Prerelease:** 21.0.0-dev.0 (Aug 2026)
- **Min Dart:** Not explicitly locked in search results; historically 3.0+, likely 3.8+ for 22.0
- **License:** BSD-3-Clause
- **Publisher:** tools.dart.dev (verified)
- **Downloads:** 1.09M+
- **Status:** Stable (not experimental)

### Key Limitations
- No C++ support; no varargs tuple unpacking
- Swift requires `@objc` wrapper generation first
- Thread safety: callbacks via `FooBlock.fromFunction` must run on owner isolate's thread; use `FooBlock.listener` or `FooBlock.blocking` for cross-thread callbacks
- libclang requirement (must be installed on developer machine)

### URLs
- [pub.dev/packages/ffigen](https://pub.dev/packages/ffigen)
- [GitHub dart-lang/native/pkgs/ffigen](https://github.com/dart-lang/native/tree/main/pkgs/ffigen)
- [Official Dart interop guide](https://dart.dev/interop/objective-c-interop)

---

## 2. package:objective_c — ObjC Runtime Support Library

### What It Is
A Dart library providing runtime support for FFIgen-generated Objective-C bindings. Bridges Dart's garbage-collected world with ObjC's reference-counted world.

### How It Works
- **NSObject wrappers:** `ObjCObjectBase` wraps native ObjC object pointers; automatically manages reference count
- **ARC/memory management:** Auto-retains when Dart wrapper created; auto-releases when GC'd via `NativeFinalizer`
- **ObjC blocks:** `ObjCBlockBase` for callable Objective-C blocks; supports thread-safe variants via listeners
- **Protocols:** `ObjCProtocolBuilder` + `ObjCProtocolMethod` for implementing protocols from Dart
- **NSString conversion:** Utilities for Dart String ↔ NSString bridging
- **Thread safety:** Isolate-aware; blocks can use `FooBlock.listener()` for cross-isolate calls

### Configuration & CLI
- No configuration; used as a direct dependency in `pubspec.yaml`
- No CLI; purely a library import

### Public Library API
- `ObjCObjectBase` (base class for ObjC object wrappers)
- `ObjCBlockBase` (callable block wrapper)
- `ObjCProtocolBuilder` (runtime protocol implementation builder)
- `ObjCProtocolMethod` (method metadata for protocols)
- String conversion utilities

### Status & Version
- **Latest:** 9.6.0 (published ~19 days before page snapshot, Aug 2026)
- **License:** BSD-3-Clause
- **Publisher:** tools.dart.dev (verified)
- **Downloads:** 5.72M+
- **Pub points:** 150 (quality score)
- **Status:** Not explicitly labeled "experimental" or "stable" in pub.dev; production-grade based on publisher status and adoption (used by cupertino_http, etc.)

### Key Limitations
- Manual memory management edge cases (must call `release()` on retained pointers if not using automatic finalizers)
- Thread pinning for callbacks; cross-thread calls require listener pattern or blocking wrapper
- Does not handle C++ at all (C++ Objective-C++ wrappers must be pre-made)

### URLs
- [pub.dev/packages/objective_c](https://pub.dev/packages/objective_c)
- [GitHub dart-lang/native/pkgs/objective_c](https://github.com/dart-lang/native/tree/main/pkgs/objective_c)

---

## 3. package:swift2objc — Swift → ObjC Wrapper Generator

### What It Is
An experimental code generator that creates `@objc`-annotated Objective-C wrapper code for Swift libraries. Enables FFIgen to subsequently parse and bind Swift APIs (since FFIgen cannot directly parse Swift).

### How It Works

**Parser/Front-End:**
- Uses Swift compiler toolchain to extract API metadata (likely via `swift symbolgraph-extract` JSON output or `swift-syntax` AST)
- Mechanism not fully documented in official sources; appears to read Swift module symbol graphs or AST

**IR / Processing:**
- Analyzes Swift types, protocols, classes, enums, structs, functions
- Determines what can be bridged to ObjC (subset of Swift features)

**Emitter:**
- Generates Objective-C header + implementation with `@objc` annotations
- Makes Swift API callable from C/FFIgen pipeline

### Configuration & CLI
- **No pub.dev package yet** — lives as a tool in `dart-lang/native` monorepo
- CLI/invocation mechanism not standardized; likely `dart run` on tool script

### Supported Constructs (as of Mar 2025)
- Classes, structs, enums, protocols
- Properties, methods
- Generics (limited; ObjC generics are weak)
- Nullability annotations (maps to ObjC nullability)
- **In development:** Swift borrowing features (moveonly, consuming, borrowing) — tracked in Issue #2086, Mar 2025

### Status & Version
- **Status:** Experimental
- **Repository:** github.com/dart-lang/native
- **Recent activity:** Active development on Swift borrowing features (Mar 2025); part of GSoC 2024 results (created as new tool)
- **License:** BSD-3-Clause (inherited from dart-lang/native)
- **Stability:** Not production-ready; expect breaking changes

### Integration with FFIgen
- No explicit `input: swift` config key in FFIgen (as of v22.0.0)
- Workflow: Run swift2objc first → feeds generated ObjC header to ffigen.yaml
- **Not yet integrated into ffigen's config** (separate tool invocation required)

### Key Limitations
- Limited Swift feature coverage (generics weak, async/throws partially supported)
- No C++ support (Swift-C++ interop not addressed)
- Compiler version dependencies (requires Swift toolchain on dev machine)
- Experimental; API and output may change

### URLs
- [GitHub dart-lang/native/pkgs/swift2objc](https://github.com/dart-lang/native/tree/main/pkgs/swift2objc)
- [Issue: Swift borrowing features](https://github.com/dart-lang/native/issues/2086)

---

## 4. package:jnigen & package:jni — Java/Kotlin FFI Binding Generator & Runtime

### What It Is
**jnigen:** Parses Java/Kotlin code and generates Dart FFI bindings via JNI.  
**jni:** Runtime library providing JVM access from Dart (spawns JVM on desktop; uses app's ART on Android).

### How It Works

**Parser/Front-End (jnigen):**
- **ApiSummarizer backend:** Two modes:
  1. **Doclet mode** (javac plugin): Parses Java source files, extracts docs, parameter names, annotations
  2. **ASM mode** (bytecode analysis): Reads compiled `.class` files in JARs, extracts metadata (no source needed)
- **Auto mode:** Tries doclet first, falls back to ASM
- **Kotlin support:** Reads Kotlin metadata embedded in `.class` files → synthesizes suspend function signatures, nullability (platform vs. nullable)

**IR / Processing:**
- Scans class hierarchy, methods, fields, types
- Generates method signatures with nullability info (Kotlin-aware)
- Suspending functions → Dart `Future` (Kotlin suspend → async)

**Emitter:**
- Generates Dart FFI bindings + glue C code (via JNI binding layer)
- Output modes: single file or package-structured

**Runtime Library (jni):**
- `Jni.spawn()` (desktop): Spawns JVM in separate process or thread
- Android: Uses app's built-in ART VM (no spawn needed)
- JNI frame management, GC interaction, exception handling

### Configuration & CLI

**Config Formats:**
- **YAML (legacy):** `jnigen.yaml` with keys like:
  - `source_path`, `class_path`, `output.dart.path`, `output.dart.structure`
  - Command-line: `-D` flag overrides
- **Dart API (recommended, v0.14+):** `tool/jnigen.dart` script creating `JniGenerator` with `Input` + `Output`

**CLI UX:**
- `dart run jnigen --config jnigen.yaml`
- `dart run jnigen -D source_path=src -D output.dart.path=lib/generated`
- Dart API script via `dart run tool/jnigen.dart`

**Public Library API:**
- **`package:jnigen`** exports:
  - `JniGenerator` (main entry point)
  - `Input` (source/class paths, includes/excludes)
  - `Output` (Dart output config)
  - Configuration builders
- **`package:jni`** exports:
  - `Jni` class (JVM spawn, frame management)
  - JNI primitive bindings

### Filters & Fixup Mechanisms
- **Include/exclude:** Class name regex patterns
- **Rename:** Method/class renaming rules
- **Interface implementation:** Generate `$` proxy classes for implementing Java interfaces from Dart
- **Type mapping:** Custom type overrides
- **Generics:** Supported (erased at runtime, but signature preservation)
- **Exceptions:** Java exceptions → Dart exceptions via `try`/`catch`

### Kotlin-Specific Features
- **Suspend functions:** Auto-detected via Kotlin metadata; generate as `Future<T>` in Dart
- **Nullability:** Platform vs. nullable types from Kotlin annotations → Dart nullable/non-nullable type hints
- **Extension functions:** Not supported (Kotlin-only feature)
- **Coroutines:** Only direct suspend functions; no structured concurrency API yet

### Status & Version
- **jnigen:** 1.0.0 (published Sep 2026, ~4 days before page snapshot) — **JUST REACHED STABLE STATUS**
- **jni:** 1.0.0 (published Sep 2026) — **STABLE**
- **Min Dart:** 3.0+ (historically; 3.8+ for 1.0.0 likely)
- **License:** BSD-3-Clause (both packages)
- **Publisher:** tools.dart.dev (verified)
- **Status:** Moved from "experimental" → **stable (1.0.0 release)**
- **Downloads:** jnigen 100k+, jni 50k+

### Key Limitations
- **Toolchain complexity:** Requires JDK, Android SDK (if building for Android), Java/Kotlin source or compiled JARs
- **Build fragmentation:** Gradle/Maven projects + custom javac invocations = build configuration burden
- **Kotlin-only APIs:** Extension functions, suspend lambdas, sealed classes not directly supported
- **Java 8 bytecode features:** Limited lambda/method reference support
- **Generated code size:** Can be substantial for large APIs (per-method C stub overhead)
- **Android SDK API levels:** Must match or higher than app's minSdk

### URLs
- [pub.dev/packages/jnigen](https://pub.dev/packages/jnigen)
- [pub.dev/packages/jni](https://pub.dev/packages/jni)
- [GitHub dart-lang/native/pkgs/jnigen](https://github.com/dart-lang/native/tree/main/pkgs/jnigen)
- [Official Dart Java interop guide](https://dart.dev/interop/java-interop)

---

## 5. package:pigeon — Cross-Platform RPC Code Generator

### What It Is
Pigeon is a **code generator** (not a library) that eliminates method-channel boilerplate by generating type-safe communication interfaces. Produces platform-specific code (Dart, Kotlin, Java, Swift, ObjC, C++, GObject).

### How It Works

**Parser/Front-End:**
- Input: A Dart `.dart` file containing interface definitions with `@ConfigurePigeon(PigeonOptions(...))`
- Parses Dart class/method/field annotations
- No true AST parsing; uses Dart's own analyzer via the language server

**IR / Processing:**
- Builds interface metadata (methods, return types, parameters)
- Resolves types to target-language representations

**Emitter:**
- **Dart:** Codegen client/server stub classes
- **Kotlin:** Suspend functions + coroutine wrappers (as of v28.0.0)
- **Swift:** async/throws signatures (as of v28.0.0)
- **Objective-C:** Traditional callback-based APIs
- **C++ (Windows):** Native C++ host API
- **GObject (Linux):** D-Bus bindings (experimental)

**Runtime:** None (code-generated, no runtime library needed for basic RPC)

### Configuration & CLI

**Config Format:**
- **Input:** A Dart file with `@ConfigurePigeon()` annotation
  ```dart
  @ConfigurePigeon(PigeonOptions(
    dartOut: 'lib/generated/messages.dart',
    kotlinOut: 'android/app/src/main/kotlin/Messages.kt',
    kotlinPackage: 'com.example.app',
    swiftOut: 'ios/Runner/Messages.swift',
  ))
  class MyHostApi { ... }
  ```

**CLI UX:**
- `dart run pigeon --input pigeons/messages.dart`
- Or rely on build_runner integration via `@GeneratePigeon` (automatic during `flutter pub get`)

**Public Library API:**
- **`package:pigeon` exports:**
  - Configuration classes: `PigeonOptions`, `DartOptions`, `KotlinOptions`, `SwiftOptions`, `ObjCOptions`, `CppOptions`, `GObjectOptions`
  - Annotations: `@ConfigurePigeon`, `@HostApi`, `@FlutterApi`, `@EventChannelApi`, `@ProxyApi`
  - `Pigeon.runWithOptions(options)` — programmatic entry point for external tools
- **Not designed for import in app code** (generated code only)

### ProxyApi Feature

**What:** `@ProxyApi` annotation generates Dart proxy classes that wrap native object instances. Each Dart proxy holds a reference to a native object (managed by an `InstanceManager`).

**Status:** Experimental (though actively developed 2025–2026)

**Language Support:**
- **Dart:** Yes (proxy generation stable)
- **Kotlin:** Experimental (working; recent fixes for constructor field sharing, parallel instance crashes being fixed)
- **Swift:** Experimental (working; recent fix for null pointer crashes from premature finalization)
- **Objective-C:** Unknown (likely not supported; ObjC++ wrappers would be required)
- **C++:** Unknown (not mentioned in search results)
- **GObject:** Unknown

**Recent Updates (2025):**
- v28.0.0: Default to `suspend`/`async throws` for Kotlin/Swift methods
- Fixes: Null pointer crashes from premature Dart instance finalization (Aug 2026)
- Fixes: Parallel instance creation crashes on iOS (tracked but not yet released)

### Status & Version
- **Latest:** 28.0.0 (published Aug 2026, ~17 days before page snapshot)
- **Min Flutter:** 3.29+, Min Dart: 3.7+
- **License:** BSD-3-Clause
- **Publisher:** flutter.dev (verified)
- **Downloads:** 561k+
- **Status:** Production stable (not marked experimental, but experimental features like ProxyApi noted)
- **Caveat:** "Generated code should not be used in public APIs" (internal implementation detail intended)
- **Breaking changes:** Common in generated code; must re-generate with same Pigeon version on all platforms

### Key Limitations
- **Experimental language stability:** ProxyApi breaking changes possible
- **Version coupling:** All platforms must use same Pigeon version (mixing causes undefined behavior, crashes)
- **Async-only for modern targets:** C++ and GObject still callback-based; Swift/Kotlin get async by default now (v28+)
- **Limited generics:** No support for `<T>` style generics across platform boundary
- **No built-in serialization:** Must write custom serializers for complex types

### URLs
- [pub.dev/packages/pigeon](https://pub.dev/packages/pigeon)
- [GitHub flutter/packages/tree/main/packages/pigeon](https://github.com/flutter/packages/tree/main/packages/pigeon)
- [ProxyApi class docs](https://pub.dev/documentation/pigeon/latest/pigeon/ProxyApi-class.html)
- [Flutter issue tracker (ProxyApi issues)](https://github.com/flutter/flutter/issues?q=ProxyApi)

---

## 6. Native Assets & Build Hooks (`hook/build.dart`, `hook/link.dart`)

### What It Is
A Flutter/Dart system for bundling compiled native code (C, C++, Rust, Go) with Dart packages. Replaces manual platform-specific build configuration (CMake files, build.gradle, Xcode settings, etc.) with Dart-based hooks.

### How It Works

**Build Hook (`hook/build.dart`):**
- Dart script invoked automatically during `flutter build` / `dart pub get`
- Compiles native source code (via `native_toolchain_c`, `native_toolchain_cmake`, custom compilers, etc.)
- Produces dynamic libraries (`.so`, `.dylib`, `.dll`, `.framework` on macOS/iOS)
- Registers assets (native code) with the build system

**Link Hook (`hook/link.dart`, Dart 3.13+):**
- Runs at app-level linking phase
- Inspects which native symbols the app actually uses (tree-shaking context)
- Can filter/remove unused native code before final link
- Reduces binary size for plugins that export multiple libraries

**Asset Types:**
- **CodeAsset:** Compiled dynamic library (primary type)
- **DataAsset:** Bundled data files (supplementary)

### Configuration & CLI

**Config Format:**
- Dart code in `hook/build.dart` and `hook/link.dart`
- No YAML or CLI flags; purely programmatic
- Uses `BuildInput`, `BuildOutputBuilder`, `LinkInput`, `LinkOutputBuilder` APIs from `hooks` package

**Example:**
```dart
// hook/build.dart
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  final buildInput = BuildInput.fromArgs(args);
  final output = buildInput.buildDir;
  
  await CBuilder(
    source: 'src',
    install: true,
  ).run(
    buildInput: buildInput,
    outputDir: output,
  );
}
```

**CLI UX:**
- Automatic via `flutter pub get`, `flutter build apk`, etc.
- No manual invocation (unless testing/debugging)

**Public Library API:**
- **`package:hooks`:** `BuildInput`, `BuildOutputBuilder`, `LinkInput`, `LinkOutputBuilder`
- **`package:code_assets`:** Asset registration APIs
- **`package:native_toolchain_c`:** C compilation helpers
- **`package:native_toolchain_cmake`:** CMake-based compilation

### Filter/Asset Registration Mechanisms
- **CodeAsset registration:** Name, type, target OS/architecture
- **Target filtering:** `buildInput.targetOS`, `buildInput.targetOSVersion`, `buildInput.targetArchitecture` → conditional compilation
- **Link-time filtering:** LinkInput exposes symbol usage → can conditionally skip asset bundling

### Status & Version
- **Stable since:** Flutter 3.38 (September 2024) + Dart 3.10
- **Link hooks:** Added Dart 3.13 (August 2025)
- **License:** BSD-3-Clause (dart-lang/native)
- **Publisher:** dart.dev (verified)
- **Status:** Stable (production-ready)

### Integration with `@Native` Annotation
- Dart code uses `@Native(assetId: 'package:my_pkg/my_lib')` to reference bundled native code
- `@DefaultAsset` annotation for default asset selection
- No manual `DynamicLibrary.open()` needed; asset resolver handles platform differences

### Key Limitations
- **Platform-specific logic:** Dart code in hooks must handle OS/architecture conditionals
- **Build performance:** Hooks run in parallel per package; no cross-package optimization
- **CocoaPods/Gradle integration:** iOS/macOS frameworks and Android SDK configuration still partially manual (pubspec `ffiPlugin: true`, gradle build config)
- **Code signing (iOS/macOS):** Framework signing must be configured in Xcode project
- **Windows/Linux maturity:** Less tested than Android/iOS paths

### flutter create Template
- `flutter create --template=plugin_ffi my_plugin` scaffolds:
  - `hook/build.dart` with CMake integration
  - `pubspec.yaml` with `ffiPlugin: true`
  - C source files (`src/my_plugin.c`)
  - CMakeLists.txt for cross-platform compilation

### URLs
- [dart.dev/tools/hooks](https://dart.dev/tools/hooks)
- [flutter.dev interop: Bind to native code using FFI](https://docs.flutter.dev/platform-integration/bind-native-code)
- [GitHub dart-lang/native/tree/main/pkgs/hooks](https://github.com/dart-lang/native/tree/main/pkgs/hooks)
- [GitHub dart-lang/native/tree/main/pkgs/native_toolchain_c](https://github.com/dart-lang/native/tree/main/pkgs/native_toolchain_c)

---

## 7. Dart/Flutter Interop Roadmap 2025–2026 & Macros Status

### Official Roadmap Statements

**Direct Native Interop Initiative (Flutter blog, 2025–2026):**
- **Goal:** Make native API access as easy as calling Dart code
- **Strategy:** FFIgen (for iOS/macOS Objective-C/Swift) + JNIgen (for Android Java/Kotlin)
- **Advantages over method channels:** Synchronous calls, tree-shaking, type safety, platform-layer data access
- **Thread merge:** Platform thread + UI thread unified on Android & iOS (completed stable); Windows/macOS in beta (3.33)
- **Early access program:** Closed Jun 20, 2025; selected experienced plugin developers participated in rewriting reference plugins

**Timeline:**
- Flutter 3.38 (Sep 2024): Native assets stable
- Flutter 3.29+ (2025): Current baseline for new interop features
- Flutter 3.33 (beta): Thread merge on Windows/macOS
- Google I/O 2025 (announced momentum)
- 2026 roadmap continues focus: seamless interop via FFIgen + JNIgen, "direct native interop" as pillar

### Dart Macros & Augmentations

**Macros Cancellation (Jan 2025):**
- Official announcement: Dart team will **not ship macros in the foreseeable future**
- Reason: Complexity, limited use cases, maintenance burden
- Alternative approach: Simpler `augmentations` language feature

**Augmentations (Separate, Planned for Shipping 2025–2026):**
- Simpler than macros; just code generation hooks
- Enables build_runner codegen without compile-time execution
- Reduces macro API surface
- Official status: Planned to ship separately (post-cancellation)

**Build_runner & Codegen:**
- Continued investment in build_runner performance improvements
- Incremental generation enhancements
- No breaking changes expected; codegen workflows unaffected by macro cancellation

### Interop Status Summary
- **ffigen:** Stable (v22.0.0)
- **jnigen:** Stable (v1.0.0, just reached 1.0 status)
- **jni:** Stable (v1.0.0)
- **objective_c:** Production-ready (v9.6.0, not labeled experimental)
- **pigeon:** Stable for basic RPC; ProxyApi experimental
- **swift2objc:** Experimental
- **native assets:** Stable (Flutter 3.38+)

### URLs
- [Flutter blog: Flutter & Dart 2026 roadmap](https://flutter.dev/blog/flutter-darts-2026-roadmap)
- [Flutter blog: Path towards seamless interop](https://flutter.dev/blog/flutters-path-towards-seamless-interop)
- [Dart blog: Update on macros & data serialization](https://dart.dev/blog/an-update-on-dart-macros-data-serialization)
- [Dart blog: Announcing Dart 3.7](https://dart.dev/blog/announcing-dart-3-7)

---

## 8. Flagship Production Users & Real-World Examples

### cupertino_http (FFIgen User)

**What:** Flutter plugin providing HTTP client for macOS/iOS using Apple's Foundation URL Loading System (NSURLSession).

**Uses:** **FFIgen** (parses Foundation framework headers)

**Rationale:** Direct access to platform HTTP implementation; automatic VPN/proxy support, HTTP/3, advanced TLS config.

**Status:** Published in Dart HTTP monorepo (dart-lang/http); production-ready

**Links:**
- [pub.dev/packages/cupertino_http](https://pub.dev/packages/cupertino_http)
- [GitHub dart-lang/http/pkgs/cupertino_http](https://github.com/dart-lang/http/tree/master/pkgs/cupertino_http)

### ok_http (JNIgen User)

**What:** Flutter plugin wrapping OkHttp (Java HTTP client library) for Android.

**Uses:** **JNIgen** (parses OkHttp Java API)

**Rationale:** High-performance HTTP on Android; modern HTTP/2 & HTTP/3 support; interceptor chain for request/response customization.

**Timeline:** Published pub.dev Aug 5, 2024 after ~75 days development

**Status:** Production-ready; demonstrates jnigen's capability at scale

**Links:**
- [pub.dev/packages/ok_http](https://pub.dev/packages/ok_http) (implied; direct link in search results not captured)
- [GitHub dart-lang/http](https://github.com/dart-lang/http) (ok_http in packages/)

### MediaPipe (JNI/JNIgen User)

**What:** Google's on-device ML solution; Flutter integration via MediaPipe Dart bindings.

**Uses:** **JNI + JNIgen** (bridges to Java/Kotlin MediaPipe APIs on Android)

**Example:** Hand landmark detection with Flutter UI

**Links:**
- [pub.dev/packages/mediapipe_genai](https://pub.dev/packages/mediapipe_genai)
- [GitHub flutter_mediapipe_hand_tracking example](https://github.com/IoT-gamer/flutter_mediapipe_hand_tracking)

### Lessons from Real Users

1. **FFIgen @ scale (cupertino_http):**
   - Large framework headers (Foundation) manageable
   - Naming conflicts require careful config (rename filters)
   - ObjC runtime integration straightforward with package:objective_c

2. **JNIgen @ scale (ok_http, MediaPipe):**
   - Java library with many classes → jnigen config complexity (include/exclude rules critical)
   - Kotlin interop (suspend functions, nullability) now reliable (1.0.0 release)
   - Build system integration (gradle + jnigen) mature

3. **No Pigeon flagship yet:**
   - ProxyApi still experimental; no major public adoption for object proxies
   - Method channels still dominant for plugin communication

---

## Surprises & Corrections to Common Beliefs

1. **JNIgen reached 1.0.0 in Sep 2026** — moved from "experimental" to officially stable. This is *very* recent and signals Dart team confidence.

2. **Macros were completely cancelled (Jan 2025)** — not delayed or phased. Augmentations (subset) planned separately. This was a significant pivot.

3. **swift2objc is NOT a pub.dev package** — lives in dart-lang/native monorepo as experimental tool. Not ready for external consumption. No published version yet.

4. **FFIgen v22.0.0 released ~15 hours before research snapshot** — extremely fresh; API restructuring (Visitor pattern) just shipped. YAML deprecation in progress (not yet removed).

5. **Native assets stable since Flutter 3.38 (Sep 2024), not 3.35 or 3.41** — the "exact version" was 3.38.

6. **pigeon ProxyApi remains experimental** even though widely discussed; no general availability declaration. Recent crashes fixes show it's being hardened but not yet production-guaranteed.

7. **Objective_c package (v9.6.0) is production-grade but not explicitly marked "stable"** in pub.dev UI. Relies on verified publisher status and adoption metrics to signal maturity.

8. **No C++ interop** in the official Dart toolchain (ffigen, jnigen). Pigeon generates C++ code for Windows, but that's platform-specific RPC, not direct C++ binding. External tools (flutter_rust_bridge, gluecodium) fill this gap.

---

## Open Questions (Could Not Verify)

1. **swift2objc's exact parsing mechanism** — Is it symbolgraph JSON (`swift symbolgraph-extract`), swift-syntax AST, or another method? Documentation incomplete.

2. **Pigeon's ProxyApi C++ support** — Can you use ProxyApi with C++ backends on Windows? Docs don't explicitly cover this.

3. **Augmentations shipping timeline** — When exactly will Dart augmentations ship? "2025–2026 roadmap" mentioned but no ETA given.

4. **objective_c thread-safety guarantees** — What happens if you call an ObjC method from two Dart isolates simultaneously? Docs mention isolate restrictions but not runtime behavior.

5. **FFIgen C++ parsing plans** — Is C++ support planned for ffigen in the medium term? Only "not supported" confirmed; no forward roadmap.

6. **swift2objc integration with ffigen** — Will ffigen gain built-in swift2objc invocation (e.g., `input: swift`)? Or will swift2objc remain a separate tool? No official statement found.

7. **GObject backend maturity** — Pigeon's GObject/Linux support is mentioned but barely documented. How production-ready is it?

8. **JNIgen's support for Kotlin suspend lambdas (SAM)** — Suspend function support confirmed; what about suspend-returning higher-order functions? Edge case not clarified.

---

## References

### Official Documentation
- [Dart interop: Objective-C and Swift](https://dart.dev/interop/objective-c-interop)
- [Dart interop: Java](https://dart.dev/interop/java-interop)
- [Dart tools: Hooks](https://dart.dev/tools/hooks)
- [Flutter bind to native code](https://docs.flutter.dev/platform-integration/bind-native-code)

### Pub.dev Package Pages
- [ffigen](https://pub.dev/packages/ffigen)
- [jnigen](https://pub.dev/packages/jnigen)
- [jni](https://pub.dev/packages/jni)
- [pigeon](https://pub.dev/packages/pigeon)
- [objective_c](https://pub.dev/packages/objective_c)
- [cupertino_http](https://pub.dev/packages/cupertino_http)
- [ok_http](https://pub.dev/packages/ok_http)

### GitHub Repositories
- [dart-lang/native](https://github.com/dart-lang/native) (monorepo: ffigen, jnigen, swift2objc, objective_c, hooks, native_toolchain_c, native_toolchain_cmake)
- [flutter/packages](https://github.com/flutter/packages) (pigeon, cupertino_http)
- [dart-lang/http](https://github.com/dart-lang/http) (cupertino_http, ok_http)

### Blog Posts & Announcements
- [Flutter blog: Flutter & Dart 2026 roadmap](https://flutter.dev/blog/flutter-darts-2026-roadmap)
- [Flutter blog: Path towards seamless interop](https://flutter.dev/blog/flutters-path-towards-seamless-interop)
- [Dart blog: Update on macros & data serialization (Jan 2025)](https://dart.dev/blog/an-update-on-dart-macros-data-serialization)
- [Flutter 3.38 announcement (Sep 2024)](https://blog.flutter.dev/announcing-flutter-3-38-dart-3-10-building-the-future-of-apps-503429eeb685)
- [Google Summer of Code 2024 results (swift2objc)](https://blog.dart.dev/google-summer-of-code-2024-results-ae925357d2d7)

### Issue Trackers
- [dart-lang/native issues](https://github.com/dart-lang/native/issues) (jnigen build complexity, swift2objc borrowing features)
- [flutter/flutter issues](https://github.com/flutter/flutter/issues) (ProxyApi crashes, native assets)
- [dart-lang/sdk issues](https://github.com/dart-lang/sdk/issues) (interop roadmap tracking)

