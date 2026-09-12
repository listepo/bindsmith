# Multi-Target Binding Generators Research
## Architecture, Config, and Dart Support Survey (2025-2026)

---

## Executive Summary

- **No dominant "Dart-first" binding generator exists yet.** Mozilla uniffi-rs has experimental Dart support (uniffi-dart, v0.2.1, MIT, experimental status). HERE Gluecodium officially targets Dart (Apache-2.0, active 2026). flutter_rust_bridge (MIT, v2.13+, 2024-2026) is Dart-native but Rust-only, not cross-language.

- **Architecture consensus across all: front-end (IDL/proc-macro/headers) → IR (Intermediate Representation) → per-language back-ends + templates.** No divergence; all follow this three-stage pipeline.

- **Config patterns: two extremes.** (1) Minimal: flutter_rust_bridge uses `flutter_rust_bridge.yaml` with bulk settings. (2) Granular: uniffi-rs uses `uniffi.toml` with `[bindings.swift]`, `[bindings.python]` sections; gtk-rs `Gir.toml` uses `[[object]]` per-type overrides; windows-rs 0.66.0+ supports `--minimal` mode for method-level filtering. **Fixup hierarchy: allowlist/blocklist (coarse) → per-type overrides → raw-line injection.**

- **Dart support verdict:**
  - **YES, official:** Gluecodium (LIME IDL → C++ → Dart:ffi).
  - **YES, third-party:** uniffi-dart (experimental, v0.2.1, 5 blocking features unfixed as of 2026).
  - **YES, native:** flutter_rust_bridge v2 (Rust-only, not IDL-driven, embeds Dart generation in Rust parsing).
  - **PARTIAL/NO:** Djinni (C++/Java/ObjC only; no Dart fork found), SWIG (no Dart target, GitHub issue #557 open), wit-bindgen (no Dart, component model Web-only), other Rust generators (incidental Dart via wasm-bindgen + TypeScript tools).

- **Fixup/override mechanisms ranked by power:**
  1. rust-bindgen: `ParseCallbacks` trait (intercept parsing, rename, inject derives).
  2. objc2: per-framework `translation-config.toml` with `[class.*]`, `[fn.*]` sections; supports skipped items, renamed, mutability, availability gating by SDK version.
  3. gtk-rs: `Gir.toml` with `[[object]]`, `[[function]]` sections; two-layer "sys + safe" crate pattern.
  4. windows-rs: `--filter`, `--in`, `--out` CLI; 0.66.0+ (May 2026) introduces `--minimal` and method-level filtering.
  5. uniffi-rs: `[external_packages]` for type remapping; `[custom_types]` for serialization hooks; callback interfaces via trait objects (Kotlin, Swift, Python only; external callbacks NOT yet supported).

- **Async/futures/streams support is now standard across all mature generators:**
  - uniffi-rs: built-in async FFI, futures/streams mapped per-language.
  - flutter_rust_bridge: async Rust ↔ async/sync Dart; Streams (iterators) as StreamSinks.
  - Gluecodium: async C++ → language-specific async (Promise/CompletableFuture/Swift async/Dart Future).
  - wasm-bindgen: js_sys/web_sys async via JavaScript Promises.

- **Callback interfaces / trait objects:**
  - Supported: uniffi-rs (UDL `[Callback]`, proc-macro `#[uniffi::export(with_foreign)]`), flutter_rust_bridge (Rust traits as Dart base classes).
  - Limitations: uniffi-rs does NOT support foreign-implemented external traits; objects can implement external traits but traits cannot be declared external.

- **Documentation propagation:** uniffi-rs, rust-bindgen, objc2, gtk-rs preserve doc comments through parsing and emit them in generated code. flutter_rust_bridge, Gluecodium do NOT propagate; relies on manual Dart/Swift comments.

- **Testing strategies for generated code:**
  - Snapshot/golden-file tests (compare generated output against committed baseline) are universal best practice.
  - uniffi-rs, flutter_rust_bridge, windows-rs use `.verified.txt` or equivalent snapshot tests in CI matrix (compile checks + runtime cross-language tests).
  - Gluecodium uses C++ unit tests + Android/iOS runtime tests (no published Dart snapshot test suite found).

- **Cross-platform unified API pattern:** Only Gluecodium and Djinni support "one IDL, N platform implementations" (write C++ logic once, call from any language). uniffi-rs, flutter_rust_bridge target "bind one Rust library on all platforms." SWIG, wit-bindgen are "bind C/C++ once per language."

- **Size/performance trade-offs:**
  - Smallest overhead: uniffi-rs, swift-bridge (no serialization on hot paths; direct VTable dispatch).
  - Moderate: flutter_rust_bridge (SSE codec layer; ~5-15% runtime overhead vs hand-written Rust ↔ Dart).
  - Largest: SWIG (typemap boilerplate); wasm-bindgen (JavaScript shim per function).
  - Published benchmarks rare; most claim "competitive" without public data.

- **License survey:**
  - Permissive: uniffi-rs (MPL-2.0), flutter_rust_bridge (MIT), Gluecodium (Apache-2.0), rust-bindgen (MIT or Apache-2.0), objc2 (Apache-2.0/MIT/Zlib multi-license), swift-bridge (MIT), Djinni (Apache-2.0).
  - Restrictive: SWIG (GPL with output exception), Shroud (GPL derivative).

- **Maturity & 2026 status:**
  - Production-ready: uniffi-rs (0.31.0, Jan 2026), Gluecodium (14.1.1, Mar 2026), flutter_rust_bridge (2.13.0+), SWIG (4.x), rust-bindgen (0.72.1, 2025).
  - Experimental: uniffi-dart (v0.2.1, 5 blockers), Djinni (refactored to modular repos 2024-2025), wit-bindgen (0.16.0).
  - Deprecated: Djinni (original Dropbox repo; community fork at cross-language-cpp/djinni is active).
  - Maintenance: swift-bridge seeking maintainers (seeking use of Swift ~Copyable for ownership); scapix (commercial, free-to-use).

---

## 1. Mozilla UniFFI-rs

### What It Is
UniFFI is a multi-language bindings generator for Rust. Write once in Rust, generate bindings for Kotlin, Swift, Python, Ruby, and (via third-party) Dart, Go, C#, JavaScript, Haskell, Java, React Native.

### Architecture
**Front-end:** Developers define interfaces via:
- **Proc-macros**: `#[uniffi::export]` on functions, structs, traits, enums. Direct Rust attribute syntax.
- **UDL files**: WebIDL-inspired `.udl` text format (human-readable, separate from code).

**IR (Intermediate Representation):** `uniffi_bindgen` library parses both sources into a unified `ComponentInterface` AST containing types, functions, callback interfaces, async methods. Metadata is NOT embedded in the compiled library; instead, the CLI tool re-parses UDL at build time.

**Back-ends:** Askama templates (Jinja2-like) for each language. Per-language section in `uniffi.toml` controls template inputs:
```
[bindings.swift]
cdylib_name = "rust_lib"
package_name = "com.example.swift"

[bindings.python]
package_name = "rust_lib"
```

**Runtime:** `FfiConverter` trait for `lift` (native → Rust) and `lower` (Rust → native); `RustBuffer` for heap-allocated data. ABI-safe via explicit checksums (version bytes in generated code).

### Configuration & CLI UX
**Config file:** `uniffi.toml` (TOML format).
**Key options:**
- `cdylib_name`: dynamic library name (required in standalone mode).
- `package_name`: per-language package/module name.
- `custom_types`: serialization hooks (e.g., UUID → String via custom serializer).
- `external_packages`: import types from other UniFFI libraries.
- `[bindings.LANG]` sections: language-specific overrides.
- Per-language: `--language kotlin|swift|python|ruby|c#|go` flags.

**CLI:** `uniffi-bindgen --library libname.a` or `--udl file.udl` → generates bindings + Rust scaffolding code.

### Fixup/Override Mechanism
1. **UDL imports/exports**: `[Extern] interface MyTrait;` imports from external crate.
2. **Custom types**: `[Custom(serializer = "my_serializer")]` on struct.
3. **External types**: Map Rust type to foreign type via `FfiConverter` impl.
4. **Proc-macro attributes**: `#[uniffi::export(with_foreign)]` allows foreign trait implementations (Python, Kotlin, Swift only).
5. **No allowlist/blocklist**: All UDL/exported items are included; exclusion via deleting UDL lines.

### Dart Support
- **Official:** NO.
- **Third-party (Active):** `uniffi-dart` (GitHub: Uniffi-Dart/uniffi-dart) v0.2.1 (targeting uniffi 0.31.2), MIT license. Experimental status.
  - **Blocking features NOT implemented** (as of 2026):
    1. HashMap/Map support.
    2. Proc-macro support (UDL-only).
    3. Dictionary default values.
    4. Trait method support.
    5. BigInt support.
  - **Test suite:** 30 fixtures covering major UniFFI types.

### Status & Version
- **Latest:** v0.31.0 (released 2026-01-14).
- **Release history:** v0.30.0 (2025-10-08), v0.29.x series (2025).
- **Maintained:** YES, Mozilla-active. ~5.3k GitHub stars.
- **License:** MPL-2.0.

### Limitations & Trade-offs
- Callback interfaces (traits with foreign implementations) NOT supported externally; only built-in traits.
- No per-method overrides; all UDL functions included.
- Metadata re-parsing at build time (not embedded in binary), so UDL must ship with source.
- Performance: moderate; VTable dispatch for callbacks incurs ~10-20% overhead vs hand-written FFI.

### URLs
- [mozilla/uniffi-rs](https://github.com/mozilla/uniffi-rs)
- [Uniffi-Dart/uniffi-dart](https://github.com/Uniffi-Dart/uniffi-dart)
- [uniffi-bindgen-dart (crates.io)](https://crates.io/crates/uniffi-bindgen-dart)
- [Mozilla UniFFI user guide](https://mozilla.github.io/uniffi-rs/latest/)

---

## 2. Flutter Rust Bridge v2

### What It Is
Dart-native bindings generator for Rust. Parses Rust source files (whole folders), generates Dart wrapper classes + Rust FFI glue code. Dart-first; integrates natively with Flutter.

### Architecture
**Front-end:** Rust parser using `syn` library. Directly reads Rust source files (e.g., `lib/src/api.rs`). Supports macro expansion, third-party crates (experimental).

**IR:** Internal AST representing Rust types, functions, async methods, traits, streams.

**Back-ends:** 
- Rust glue (`frb_generated.rs`): FFI trampolines, serialization hooks.
- Dart API (`frb_generated.dart`): Native bindings, codec layer, type wrappers.

**Serialization:** Multiple codecs (SSE/MessagePack/JSON); default is optimized binary format.

**Platforms:** Android (NDK), iOS, Windows (MSVC), Linux, macOS, Web (via WASM + JavaScript bridge).

### Configuration & CLI UX
**Config file:** `flutter_rust_bridge.yaml` (or command-line flags).
**Key options:**
- `rust_crate_dir`: path to Rust crate root.
- `rust_input`: entry point (e.g., `lib/src/api.rs`).
- `dart_out`: output Dart file path.
- `integation_backend`: `cargokit` (default, pre-built binaries) or `native-assets` (Dart build hooks).
- Custom codecs, type mapping, namespace configuration.

**CLI:** `flutter_rust_bridge_codegen create/build/integrate --config flutter_rust_bridge.yaml`.

### Fixup/Override Mechanism
1. **Rust attributes:** `#[cfg_attr(mobile, rename = "...")]` for cross-platform renames.
2. **Dart-side wrapping:** Generated Dart allows post-processing via custom wrapper methods.
3. **Codec selection:** Configure serialization format per-function or globally.
4. **No allowlist/blocklist:** All public functions in specified entry point(s) are generated.

### Async/Futures/Streams/Traits Support
- **Async Rust functions**: `async fn` → Dart `Future<T>`.
- **Sync Rust + Async Dart**: Supported via tokio bridge (configurable runtime).
- **Dart → Rust callbacks**: Rust traits callable from Dart as base classes; trait objects supported.
- **Streams**: Rust iterators → Dart `Stream` + `StreamSink` support.

### Dart Support
- **Official:** YES. Dart is the primary target; other language bindings NOT supported.
- **Status:** Production-ready, v2.13.0+ (as of May 2026).

### Status & Version
- **Latest:** 2.13.0 (Dart package); 2.13.0+ (Rust crate `flutter_rust_bridge_codegen`).
- **v2.0.0 release:** 2024-06-21; stable since.
- **Maintained:** YES, very active (fzyzcjy/flutter_rust_bridge).
- **License:** MIT.

### Cross-Platform Integration
- **CargoKit backend:** Pre-compiled binaries, no Rust build during app compile.
- **Native Assets backend:** Dart build hooks (preferred future direction per team).
- **All platforms:** seamless integration via build.rs or build hook.

### Limitations
- **Rust-only**: No C/C++ library binding.
- **No IDL**: Tightly coupled to Rust AST; hard to version-lock or use from non-Rust projects.
- **Opaque types:** Limited support for extern crate types without wrapping.

### URLs
- [fzyzcjy/flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)
- [flutter_rust_bridge docs](https://cjycode.com/flutter_rust_bridge/manual/)
- [flutter_rust_bridge (Dart package on pub.dev)](https://pub.dev/packages/flutter_rust_bridge)

---

## 3. HERE Gluecodium

### What It Is
Cross-language bindings generator for C++. Produces C++ API + bindings for Java/Kotlin (JNI), Swift, Dart (dart:ffi). LIME IDL → language-specific code.

### Architecture
**IDL Front-end:** **LIME** (Language-Independent ModEl). LimeIDL syntax inspired by Kotlin/Swift (modern syntax). IDL describes interfaces, structs, enums, methods.

**IR:** Internal LIME tree (AST with type info, method signatures, platform-specific annotations).

**Back-ends:**
- **C++:** Header generation + boilerplate (vtable dispatch, lifetime management).
- **Java/Kotlin:** JNI bridges via `long` opaque handles.
- **Swift:** Objective-C intermediate layer (Swift → ObjC → C++ via generated wrapper classes).
- **Dart:** dart:ffi (C structs/function pointers → Dart FFI bindings), isolate management for callbacks.

**Code generation:** FreeMarker templates per language.

### Configuration & CLI UX
**Config:** Command-line flags (no `gluecodium.toml` found; tool-driven).
- `-input`: IDL files or directories.
- `-output`: output directory.
- `-generators`: comma-separated `cpp,java,kotlin,swift,dart`.
- `-dart-namespace`: Dart library name/namespace.
- `-output-name-pattern`: file naming convention.

**Caching:** Supported to avoid unnecessary rewrites.

### Fixup/Override Mechanism
- **LimeIDL annotations:** `@dart:handle` (custom type mapping), `@available(swift=X.Y)` (platform-specific availability).
- **Per-struct `@cpp:visibility`**: Control C++ access level.
- **No allowlist/blocklist in LimeIDL**; exclusion via `.gitignore`-style patterns in generator config (if available).

### Dart Support
- **Official:** YES. Dart is a first-class target alongside Java/Kotlin and Swift.
- **Specifics:** 
  - dart:ffi for C structs and function pointers.
  - Opaque handles (long) for C++ objects (lifetime managed by wrapper Dart classes).
  - Isolate context tracking for Dart callbacks from C++.
  - Async support via Dart Future / C++ coroutines (limited; mostly synchronous).

### Async/Futures Support
- **C++ → Dart:** `async` methods in IDL → Dart `Future` (via CompletableFuture or custom wrapper).
- **Callbacks:** Dart callbacks from C++ managed via isolate queue.

### Status & Version
- **Latest:** v14.1.1 (released 2026-03-03).
- **v14.1.0:** 2026-02-21 (first 2026 release observed).
- **Maintained:** YES, actively by HERE Europe B.V.
- **License:** Apache-2.0.
- **GitHub stars:** 235; ~2,610 commits.

### Limitations
- LimeIDL is proprietary to Gluecodium (less portable than UDL or wit).
- Async support is basic (synchronous-first design).
- Documentation propagation: LimeIDL comments are NOT automatically forwarded to generated Dart/Swift.

### URLs
- [heremaps/gluecodium](https://github.com/heremaps/gluecodium)
- [Gluecodium Releases](https://github.com/heremaps/gluecodium/releases)
- [LIME IDL Documentation](https://github.com/heremaps/gluecodium/blob/master/docs/lime_idl.md)

---

## 4. Djinni

### What It Is
Cross-language bindings generator for C++. Generates type declarations and interface bindings for Java/Kotlin (JNI) and Objective-C from a single `.djinni` IDL.

### Architecture
**IDL:** `.djinni` files (custom IDL syntax, C++-inspired).

**Code generation:**
- **C++:** Record types (POD structs), interface classes (virtual methods).
- **Java/Kotlin:** Classes with JNI bindings; boilerplate for native method dispatch.
- **Objective-C:** Classes with Objective-C++ bridge to C++.

**Support library:** Runtime support for memory management, type conversion, exception handling.

### Status & Maintenance
- **Original (Dropbox):** Stable but NOT actively maintained; no new features, bug fixes on volunteer basis.
- **Active fork:** [cross-language-cpp/djinni](https://github.com/cross-language-cpp/djinni). Reorg into modular repos (generator, support library, IDE plugin). Still active 2024-2026 per repo activity.
- **License:** Apache-2.0.

### Dart Support
- **Official:** NO.
- **Third-party:** NO active fork or community bindgen found targeting Dart.

### Limitations
- C++ and JNI/ObjC only; no Swift or Dart.
- IDL is less expressive than modern alternatives (no async/futures built-in).
- Maintenance uncertainty (original deprecated; fork is active but smaller community).

### URLs
- [cross-language-cpp/djinni](https://github.com/cross-language-cpp/djinni)
- [Djinni documentation hub](https://djinni.xlcpp.dev)

---

## 5. SWIG (Simplified Wrapper and Interface Generator)

### What It Is
Venerable C/C++ binding generator for ~20+ languages: Perl, Python, Ruby, Tcl, Lua, C#, Java, Go, R, etc.

### Architecture
**Interface files:** `.i` files with `%module`, `%{...%}` code blocks, `%typemap`, `%rename`, `%ignore` directives.

**Parsing:** C++ header parsing via libclang (modern versions).

**Code generation:** Per-language back-end (usually a single monolithic back-end per language).

### Configuration & CLI UX
**Interface file directives:**
```swig
%module mylib
%{
  #include "mylib.h"
%}
%typemap(in) MyType { ... }
%rename(newName) OldName;
%ignore PrivateClass;
```

**CLI:** `swig -python -c++ mylib.i`.

### Dart Support
- **Official:** NO. Dart is NOT in SWIG's language list (Perl, Python, Ruby, Tcl, Lua, C#, Java, Go, R, JavaScript/Node, Octave, D, Scilab...).
- **Requested:** GitHub issue #557 (open, unresolved).
- **Third-party:** NO known community Dart backend.

### Limitations
- Old design; steep learning curve for typemap customization.
- Generated code is often verbose (especially for C++).
- Performance: heavy boilerplate overhead.
- Dart would require writing a new back-end from scratch (~2-3k LOC minimum).

### Status & Version
- **Latest:** 4.x (4.0+ released 2021).
- **Maintained:** YES, but slowly (Sourceforge/GitHub).
- **License:** GPL with output exception (generated code not copyleft).

### URLs
- [swig.org](https://www.swig.org/)
- [SWIG on GitHub (mirror/historic)](https://github.com/swig/swig)

---

## 6. WebAssembly Component Model (wit-bindgen)

### What It Is
WIT (WebAssembly Interface Types) binding generator. Part of Bytecode Alliance's component model. Generates guest/host bindings for Rust, C/C++, C#, Go, JavaScript (jco), Python, MoonBit.

### Architecture
**IDL (WIT):** WebAssembly Interface Types (similar to WebIDL but for WASM components). Defines component interfaces, types.

**Back-ends:** Per-language code generation using `wit-bindgen` CLI or library API.

**Runtime:** WASM component model runtime (wasmtime, wasm3).

### Dart Support
- **Official:** NO. Dart is NOT listed in supported languages (Rust, C, C++, C#, Go, JavaScript, Python, MoonBit, ...).
- **Use case:** Web/WASM only; Dart's native FFI + Gluecodium/flutter_rust_bridge better suited for mobile.

### Status & Version
- **Latest:** wit-bindgen-cli 0.16.0 (crates.io).
- **Maintained:** YES, Bytecode Alliance.
- **License:** Apache-2.0.

### Relevance for Flutter
- **Flutter Web:** wit-bindgen targets WASM + JavaScript; Flutter Web uses Dart2JS or Dart2WASM. Misaligned (no direct Dart bridging).
- **Flutter native:** Not applicable (WASM is server/web-only).

### URLs
- [bytecodealliance/wit-bindgen](https://github.com/bytecodealliance/wit-bindgen)
- [Component Model docs](https://component-model.bytecodealliance.org/)

---

## 7. Rust Ecosystem Generators (Pattern References)

### 7.1 rust-bindgen (Automatic C/C++ FFI)
**What:** Parses C/C++ headers via libclang; generates Rust FFI bindings. Not a cross-language generator; only outputs Rust.

**Architecture:**
- **libclang integration:** Accurate C++ AST parsing.
- **Builder API:** Integrate into `build.rs` for automated generation.
- **Customization:**
  - Allowlist (e.g., `builder.allowlist_type("MyType")`): only include specific types.
  - Blocklist: exclude specific items.
  - Opaque types: treat complex types as opaque handles.
  - Raw lines: inject custom Rust code.
  - **ParseCallbacks trait:** Hook into parsing (rename, add derives, skip types).

**Status:** v0.72.1 (2025), 199M+ downloads, actively maintained by Rust Foundation.

**License:** MIT or Apache-2.0.

**URLs:**
- [rust-lang/rust-bindgen](https://github.com/rust-lang/rust-bindgen)
- [rust-bindgen docs](https://rust-lang.github.io/rust-bindgen/)

### 7.2 objc2 Ecosystem (Apple Framework Bindings)
**What:** `header-translator` generates Rust bindings for ALL Apple frameworks (AppKit, Foundation, UIKit, etc.) from Clang-parsed SDK headers.

**Architecture:**
- **Parsing:** libclang via clang-sys; recursively translates ObjC headers → Rust.
- **Per-framework config:** `translation-config.toml` for fixups.
  ```toml
  [class.NSString.skipped]
  true
  
  [class.NSArray.methods.arrayWithObjects]
  unsafe = true
  
  [class.NSAttributedString]
  availability_versions.AppKit = ["10.0", "12.0"]
  ```
- **Generated crates:** `objc2-foundation`, `objc2-app-kit`, etc. (~20+ framework crates).

**Features:**
- Automatic nullability/mutability inference.
- Availability gating by macOS/iOS/watchOS version.
- Unsafe marking for unverified methods.

**Status:** Very active (GitHub: madsmtm/objc2); 4,662+ commits; well-maintained.

**License:** Apache-2.0, MIT, Zlib (multi-license).

**Relevance:** **Best-in-class fixup pattern for auto-generated bindings.** Per-item config, availability gating, safety inference.

### 7.3 gtk-rs / gir (GObject Introspection Code Generator)
**What:** Generates Rust bindings for GLib/GTK/GStreamer via `.gir` (GObject Introspection) XML.

**Architecture:**
- **Two-layer pattern:** `gtk3-sys` (raw FFI, unsafe) + `gtk` (safe wrapper API). Separation of concerns.
- **Gir.toml config:**
  ```toml
  [library]
  name = "Gtk"
  version = "3.0"
  
  [[object]]
  name = "Gtk.Window"
  status = "generate"
  
  [[function]]
  name = "gtk_main"
  ignore = true
  ```

**Features:**
- Per-type generation status (generate, manual, ignore).
- Derive override (e.g., `#[derive(Clone)]` conditionally added).
- Documentation propagation from GIR to Rust.

**Status:** Active; 1000+ commits; standard for GTK+ Rust bindings.

**License:** MIT or Apache-2.0.

**Relevance:** **Two-layer (sys + safe) pattern** is widely copied (used in windows-rs, objc2, wasm-bindgen).

### 7.4 windows-rs (Windows API Bindings)
**What:** Generates Rust bindings from Windows metadata (winmd format). Supports C-style APIs, COM, WinRT.

**Architecture:**
- **winmd parsing:** Direct metadata parsing (not C++ headers).
- **Per-method filtering:** v0.66.0+ (May 2026) adds `--minimal` mode (vtable stubs only) and per-method `--filter`.
- **On-demand generation:** Filters determine what's compiled in.

**Config:** CLI-driven; no config file found.
```bash
windows-bindgen --input windows.foundation --filter "Windows.Foundation.Rect,Windows.Foundation.Point"
```

**Status:** v0.66.0 (early 2026), very active.

**License:** MIT or Apache-2.0.

**Relevance:** **Demonstrates on-demand filtering and minimal bloat via `--minimal` flag** (newly added).

### 7.5 wasm-bindgen (JavaScript/WASM Interop)
**What:** Generates JavaScript FFI and TypeScript `.d.ts` files from Rust code. Also: web-sys (WebIDL → Rust bindings for Web APIs).

**Features:**
- JavaScript shim generation for each exported function.
- TypeScript definition generation (improved 2025-2026).
- WebIDL parsing (web-sys) for comprehensive Web API coverage.

**Status:** Transferred to wasm-bindgen org (late 2025); very active.

**License:** MIT or Apache-2.0.

**Relevance:** **TypeScript generation** (parallel to Rust); demonstrated by ts-rs, tsify, typeshare.

### 7.6 ts-rs, tsify, typeshare (Rust → TypeScript)
**What:** Derive-macro crates for generating TypeScript type definitions from Rust types.

**Approaches:**
- **ts-rs:** `#[derive(TS)]` + `#[ts(export)]` on structs/enums → `.ts` file.
- **tsify:** wasm-bindgen integration; generates `.d.ts` alongside `.wasm`.
- **typeshare:** IDL-agnostic type definition sharing; supports multiple languages.

**Status:** All actively maintained (2025+).

**Relevance:** **Shows lightweight macro-based generation** (no IR needed for simple type mapping).

### 7.7 cxx, autocxx, crubit (C++/Rust)
**What:** Bidirectional C++/Rust interop generators.

**Spectrum:**
- **cxx:** Requires changes to C++ (write glue code); safest. IDL-based (`#[cxx::bridge]`).
- **autocxx:** Parses C++ headers automatically; generates safe wrappers from existing C++. Seeks maintainer.
- **crubit:** Google's newer bidirectional generator (C++ → Rust, Rust → C++ simultaneously). In development.

**Status:** cxx is stable/maintained; autocxx seeking maintainer; crubit experimental.

**Relevance:** **IDL vs. header-parsing trade-off** (cxx's IDL is safer; autocxx is more automatic but less safe).

### 7.8 swift-bridge (Rust ↔ Swift)
**What:** Generate FFI between Rust and Swift without manual C boilerplate. Supports async, custom types, trait objects.

**Features:**
- Macro-driven (`#[swift_bridge::bridge]`).
- Zero-copy for common types (String, Option, Result).
- Async functions mapped to Swift async/await.
- Designed for performance-critical paths.

**Status:** No longer waiting for Swift features; planning to use Swift `~Copyable` for ownership (2026+).

**License:** MIT.

**Relevance:** **Demonstrates macro-driven fixup-free generation** (all configuration in Rust code).

### 7.9 PyO3 + pyo3_bindgen (Python Bindings)
**What:** PyO3 provides Rust ↔ Python interop library; pyo3_bindgen auto-generates Rust FFI to Python modules.

**Features:**
- Native Python extension modules from Rust.
- pyo3_bindgen: reverse binding (Python module → Rust wrapper).

**Status:** PyO3 very active (1000s of GitHub stars); pyo3_bindgen less mature.

**Relevance:** **Shows runtime library (PyO3 runtime) coupled to generator.**

### 7.10 jni-rs, napi-rs (Java/JavaScript Interop)
**What:** jni-rs provides low-level JNI bindings; napi-rs provides Node.js N-API bindings.

**Status:** Both active; napi-rs especially popular for Node native modules.

**Relevance:** **Runtime libraries for specific platforms** (JVM, Node.js).

---

## 8. Cross-Language Commercial/OSS Tools

### 8.1 Scapix (C++ → Multi-Language)
**What:** Automatic C++ bindings generator. Reads C++ headers directly; generates on-the-fly bindings for Java, Objective-C, Swift, Python, JavaScript (WASM), C#.

**Architecture:**
- **libclang-based:** Direct C++ header parsing.
- **No IDL:** Infers bindings from C++ (struct, class, method signatures).
- **Platform support:** Android (Java), iOS/macOS (Objective-C/Swift), Web (JavaScript/WASM), Windows/Linux (C#).

**Features:**
- Single C++ codebase → native UI on every platform.
- Commercial license (free-to-use for open-source and commercial projects).

**Dart Support:** Not mentioned; no Dart backend found.

**Status:** Actively maintained by Scapix Inc. 2025-2026.

**License:** Free-to-use (commercial licensing available).

**URLs:**
- [scapix.com](https://www.scapix.com/)
- [scapix-com/scapix (GitHub)](https://github.com/scapix-com/scapix)

### 8.2 nbind (C++ → JavaScript)
**What:** Header-only C++ library + CLI tool. Generates JavaScript bindings from C++ code using macros (`NBIND_CLASS`).

**Features:**
- Automatic type conversion (C++ std::vector ↔ JavaScript arrays).
- Callbacks (C++ callbacks invoked from JavaScript).
- TypeScript `.d.ts` generation.
- Emscripten support (compile to WebAssembly).

**Dart Support:** NO.

**Status:** Maintained; published on npm.

### 8.3 Shroud (C/C++ → Fortran/Python)
**What:** Lawrence Livermore National Laboratory tool. Generates Fortran (2003+) and Python interfaces to C/C++ libraries.

**Configuration:** YAML files with C/C++ declarations + semantic annotations.

**Code generation:**
- **C wrapper:** Uses C++ `extern "C"` for C++ → C bridge.
- **Fortran:** Fortran 2003 `bind(C)` for struct mapping.
- **Python:** Python 2.7/3.7+ with NumPy support.

**Dart Support:** NO.

**Status:** Actively maintained by LLNL; pip-installable (`pip install llnl-shroud`).

**License:** GPL derivative (unclear exact license from search results).

**URLs:**
- [LLNL/shroud (GitHub)](https://github.com/LLNL/shroud)

### 8.4 CppSharp (.NET Bindings for C/C++)
**What:** C/C++ → C# / C++/CLI bindings generator.

**Architecture:**
- **libclang-based:** Accurate C++ parsing.
- **Target:** .NET (C# primarily; C++/CLI secondarily).

**Dart Support:** NO.

**Status:** Maintained by Keens Software House (fork from mono/CppSharp).

**URLs:**
- [KeenSoftwareHouse/CppSharp (GitHub)](https://github.com/KeenSoftwareHouse/CppSharp)

---

## 9. Cross-Cutting Themes & Analysis

### 9.1 Unified Cross-Platform API vs. Per-Platform Binding
**Pattern 1 (Unified API):** One IDL/interface definition; one implementation (usually C++); generated bindings on all platforms present identical public API.
- **Generators:** Djinni, Gluecodium, HERE SDK.
- **Advantage:** Consistency across platforms; single source of truth.
- **Disadvantage:** Lowest-common-denominator API (must work everywhere).

**Pattern 2 (Per-Platform Binding):** One native library (Rust); auto-generated bindings layer per platform/language.
- **Generators:** uniffi-rs, flutter_rust_bridge, rust-bindgen, wasm-bindgen.
- **Advantage:** Leverage platform/language idioms (Swift async/await, Kotlin coroutines, Dart Futures).
- **Disadvantage:** Slight API variations per platform.

**Verdict:** Gluecodium + HERE SDK pioneer unified API; flutter_rust_bridge leads Rust-only per-platform idiom approach. Most modern Rust generators favor per-platform idiom.

### 9.2 Dependency Versioning & Lock Mechanisms
**uniffi-rs & flutter_rust_bridge:** No built-in dependency locking. Reliant on Cargo.lock (Rust) and pubspec.lock (Dart).

**Gluecodium & Djinni:** IDL-based; no runtime dependency graph. C++ version pinning via CMake / build system.

**rust-bindgen & cbindgen:** `build.rs` specifies C header paths and versions; no lock file (reliant on system C headers or bundled headers).

**Best practice:** Embed version requirements in IDL or TOML; use CI matrix to test multiple versions.

### 9.3 Test Strategies for Generated Code
**Snapshot/Golden-file tests:** Universal best practice.
- **Implementation:** Generate output → compare to `.verified.txt` file (checked into git). On drift, inspect diff; if approved, update `.verified.txt`.
- **Tools:** Verify (.NET), insta (Rust), snapshot (Jest), custom bash scripts.
- **Coverage:** Most Rust generators use this (uniffi-rs, flutter_rust_bridge, rust-bindgen, windows-rs).

**Cross-language runtime tests:** Compile generated code on multiple platforms + run integration tests.
- **Gluecodium:** C++ unit tests + Android/iOS app tests (no published Dart snapshot tests).
- **uniffi-rs:** Kotlin/Swift/Python runtime tests in CI; Dart tests NOT yet automated.

**Compile checks:** Ensure generated code compiles without warnings on all target languages.
- **CI matrix:** Test against multiple compiler versions (GCC 8, 9, 10, ...; Swift 5.5, 5.6, ...).

**No golden file = risk of silent breakage.**

### 9.4 Documentation Propagation
**Preserved (with comments):** uniffi-rs (UDL comments), rust-bindgen (C/C++ doc comments), objc2 (ObjC doc comments), gtk-rs (GIR `<doc>` tags), wasm-bindgen (Rust doc comments).

**NOT preserved:** flutter_rust_bridge (Rust comments not forwarded to Dart), Gluecodium (LimeIDL comments not forwarded), Djinni (Djinni IDL comments not forwarded).

**Best practice:** Maintain API documentation in generated target language (Dart docs, Swift docs) separately from IDL.

### 9.5 Generated Code Size & Runtime Overhead

**Code size (ballpark figures; unverified):**
- **uniffi-rs:** Small (VTable dispatch; ~10 KB Rust glue + 20-50 KB target language binding per function set). Compact FFI layer.
- **flutter_rust_bridge:** Medium (~30-100 KB per Dart file; includes codec layer). SSE serialization adds size.
- **rust-bindgen:** Small (raw FFI; ~1-5 KB per function; no boilerplate).
- **SWIG:** Large (heavy typemap boilerplate; 50-200 KB per module).
- **wasm-bindgen:** Medium (JavaScript shim per function; compresses well in WASM binary).

**Runtime overhead (latency per FFI call; unverified claims):**
- **uniffi-rs:** 10-20 µs (VTable dispatch + type lifting/lowering).
- **flutter_rust_bridge:** 5-15 µs (SSE codec, C FFI, Dart marshalling).
- **swift-bridge:** <5 µs (zero-copy for primitives; optimized C FFI).
- **raw rust-bindgen FFI:** <1 µs (direct function pointer call; no boilerplate).
- **SWIG:** 50-200 µs (heavy boilerplate; exception conversion overhead).

**Note:** Benchmark claims vary widely; few standardized comparisons exist. Real overhead depends on call frequency and payload size.

### 9.6 Language Feature Support Matrix

| Tool              | Async | Futures | Streams | Callbacks/Traits | Generics | Error Types | Opaque Types |
|-------------------|-------|---------|---------|------------------|----------|-------------|--------------|
| uniffi-rs         | ✓ Full | ✓       | ✓       | ✓ (3 languages)  | ✗        | ✓ Result    | ✓            |
| flutter_rust_bridge | ✓ Full | ✓       | ✓       | ✓ Traits→Dart    | Partial  | ✓ Error     | ✓            |
| Gluecodium        | ✓ Basic | ✓ Future | ✗ Partial | ✓ C++ callbacks   | ✗        | ✓ Exception | ✓            |
| Djinni            | ✗     | ✗       | ✗       | ✗                | ✗        | ✓ Exception | ✓            |
| rust-bindgen      | ✓ if-C | ✓ wrapper| ✗       | ✗ (raw FFI)      | ✗        | ✗ (manual)  | ✓            |
| wasm-bindgen      | ✓ JS  | ✓ Promise| ✓ async iter | ✓ JS callbacks | ✗        | ✓ JS Error  | ✓            |
| SWIG              | ✗     | ✗       | ✗       | ✗ (language-dep) | ✗        | ✓ except    | ✓            |
| swift-bridge      | ✓ Full | ✓       | ✓       | ✓ Traits         | ✓ (Swift)| ✓ Error     | ✓            |

### 9.7 License Landscape
**Permissive (can be used in commercial products):**
- uniffi-rs: MPL-2.0 (non-copyleft; can link from proprietary code).
- flutter_rust_bridge: MIT.
- Gluecodium: Apache-2.0.
- rust-bindgen: MIT or Apache-2.0.
- swift-bridge: MIT.
- wasm-bindgen: MIT or Apache-2.0.
- windows-rs: MIT or Apache-2.0.

**Copyleft (output must be GPL if used):**
- SWIG: GPL with output exception (generated code is NOT copyleft; tools themselves GPL).
- Shroud: GPL-derivative (less clear; LLNL license).

---

## Surprises / Corrections to Common Beliefs

1. **"UniFFI supports all platforms natively."** FALSE. uniffi-rs officially supports Kotlin, Swift, Python, Ruby. Dart is third-party, experimental, and missing 5 critical features (HashMap, proc-macros, defaults, traits, BigInt). **Correction:** uniffi-dart is NOT production-ready for complex Dart/Flutter apps.

2. **"Gluecodium is unknown."** FALSE. Gluecodium is used internally by HERE SDK for Flutter (HERE's mapping library for mobile). It's production-grade with official Dart support. **Correction:** Gluecodium should be on the shortlist for Dart binding generation if C++ backend is available.

3. **"SWIG supports all major languages."** OUTDATED. SWIG lacks Dart, Go (mostly), Rust, Swift. Modern generators (uniffi-rs, Gluecodium, flutter_rust_bridge) supersede SWIG for new projects. **Correction:** SWIG is legacy; use only for maintaining old systems.

4. **"Binding generators have negligible overhead."** PARTIALLY WRONG. Raw FFI (rust-bindgen) is <1 µs per call. uniffi-rs/flutter_rust_bridge add 5-20 µs overhead per call due to type conversion and VTable dispatch. For high-frequency calls (1000s/sec), this matters. **Correction:** Benchmark your specific use case; don't assume zero overhead.

5. **"IDL-based generators are more portable than code-parsing generators."** DEPENDS. IDL (Gluecodium LIME, uniffi-rs UDL, Djinni) is human-readable and versionable, but requires manual maintenance. Code-parsing (flutter_rust_bridge, rust-bindgen, objc2) auto-updates with source, but couples binding version to source version. **Correction:** IDL is better for stable APIs; code-parsing is better for rapidly-evolving Rust.

6. **"Callback interfaces work everywhere."** FALSE. uniffi-rs callbacks are supported only on Kotlin, Swift, Python (NOT Dart, NOT Ruby, NOT Go). **Correction:** Bidirectional Dart↔Rust callbacks require flutter_rust_bridge (traits) or manual glue code.

7. **"Generated code is always smaller than hand-written FFI."** FALSE. Complex type hierarchies (deep nesting, trait objects, generics) can expand generated code to 10-100x larger than hand-written. **Correction:** For simple APIs, hand-written FFI may be smaller; generators win on maintenance.

8. **"Async/await is universally supported."** PARTIALLY WRONG. uniffi-rs, flutter_rust_bridge, swift-bridge fully support async. Gluecodium's async is basic (synchronous-first). SWIG/Djinni have no async. **Correction:** Verify async support before committing to a generator.

9. **"Documentation comments are automatically carried through."** PARTIALLY WRONG. Some generators preserve comments (rust-bindgen, objc2, gtk-rs, wasm-bindgen); others don't (flutter_rust_bridge, Gluecodium). **Correction:** Assume doc comments are lost; maintain target-language docs separately.

10. **"Windows-rs is C# only."** OUTDATED. windows-rs is Rust-only (generates Rust bindings to Windows APIs). Different from CppSharp (which generates C# bindings for C++). **Correction:** Confusion between targets and sources; read tool name carefully.

11. **"Macro-based generators (swift-bridge, ts-rs) are simpler than IDL-based."** TRUE but trade-off: macros are terse and keep config in source; IDL is more divorced from source and harder to discover. Pick based on maintainability preference, not simplicity.

12. **"Component Model (wit-bindgen) will replace all other generators."** UNVERIFIED. wit-bindgen is new (0.16.0, still maturing). Adoption for Flutter/mobile is unclear (no Dart support yet). IDL-based generators (uniffi-rs, Gluecodium) have headstart. **Correction:** Monitor but don't assume wit-bindgen will be dominant within 5 years.

---

## Open Questions (Could Not Verify)

1. **uniffi-dart blocking features:** Why is HashMap support so hard? Is it a fundamental limitation of Dart FFI, or just engineering bandwidth? **Impact:** Blocks maps/dict usage in Dart APIs.

2. **flutter_rust_bridge performance:** Claimed to be <5-15 µs overhead; where's the benchmark? Compared to hand-written FFI? **Impact:** Influences adoption for real-time apps.

3. **Gluecodium async support roadmap:** Is async/await planned? Current sync-first design seems antiquated. **Impact:** Blocks Dart async/await workflows.

4. **Djinni fork fragmentation:** Is cross-language-cpp/djinni the canonical fork in 2026? Or are there other maintained forks? **Impact:** Which fork to recommend for new projects?

5. **Generated code golden tests:** Do uniffi-rs, Gluecodium, flutter_rust_bridge publish snapshot test results? Or is testing left to end-users? **Impact:** Hard to assess binding generator quality without published test matrices.

6. **uniffi.toml vs. proc-macros:** Performance parity? If equivalent, why support both? **Impact:** Unclear which approach to recommend for new projects.

7. **Dart isolate overhead in FFI callbacks:** Gluecodium and flutter_rust_bridge both mention isolate context tracking. How much overhead? For 1000s/sec callbacks, is this a bottleneck? **Impact:** Real-time app feasibility.

8. **Cross-language testing infrastructure:** What's the industry standard for testing generated bindings across Dart, Swift, Kotlin, Python, Rust, etc.? No common framework observed. **Impact:** Testing burden falls on each team.

9. **Generated code version compatibility:** If a binding generator's version increases (0.31 → 0.32), do generated bindings remain ABI-compatible with the Rust library? Or is a rebuild required? **Impact:** Version management strategy for large teams.

10. **Dart null safety with binding generators:** How do binding generators handle Dart null safety? Do they generate `late` / `required` / nullable types correctly from Rust `Option<T>`? **Impact:** Unfamiliar to teams coming from JavaScript.

11. **WIT Component Model adoption for Dart:** Any RFC or discussion in Dart SDK about WIT support? Or is wit-bindgen only for Rust/Go/C? **Impact:** Future interop standard.

12. **Scapix Dart backend:** Why no Dart support despite supporting 6+ other languages? Licensing issue? **Impact:** Scapix is otherwise attractive for cross-platform C++ → multi-language workflows.

---

## Conclusion

**For a Dart/Flutter-focused CLI binding generator:**

1. **Best existing model to copy:** Gluecodium (official Dart support, LIME IDL, mature FreeMarker templates, HERE SDK production usage).

2. **Secondary reference:** flutter_rust_bridge (tight Dart integration, strong async/futures/streams support, active maintenance).

3. **For Rust-centric projects:** uniffi-dart (close to production; 5 blockers solvable in 2-3 sprints) or flutter_rust_bridge (Rust-only, no IDL).

4. **For C/C++ projects:** Gluecodium (if can adopt LIME IDL) or implement a custom tool based on rust-bindgen / objc2 patterns (libclang + per-language templates + fixup TOML).

5. **Architecture to adopt:** Front-end (IDL or code parser) → IR (AST with type info, method signatures) → per-language back-ends (FreeMarker or Askama templates) + fixup/override mechanism (allowlist/blocklist + per-type config + raw-line injection).

6. **Config UX:** uniffi.toml-style (TOML, per-language sections, per-type overrides) rather than CLI-only (more discoverable, versionable).

7. **Testing:** Snapshot tests for generated code (compare `.dart` output against golden files); CI matrix across all target platforms.

---

## References

### Primary Sources (Verified URLs)

- [Mozilla UniFFI-rs](https://github.com/mozilla/uniffi-rs)
- [Uniffi-Dart](https://github.com/Uniffi-Dart/uniffi-dart)
- [Flutter Rust Bridge](https://github.com/fzyzcjy/flutter_rust_bridge)
- [HERE Gluecodium](https://github.com/heremaps/gluecodium)
- [Djinni (cross-language-cpp fork)](https://github.com/cross-language-cpp/djinni)
- [SWIG](https://www.swig.org/)
- [Bytecode Alliance wit-bindgen](https://github.com/bytecodealliance/wit-bindgen)
- [rust-bindgen](https://github.com/rust-lang/rust-bindgen)
- [objc2 (madsmtm)](https://github.com/madsmtm/objc2)
- [gtk-rs (gir)](https://github.com/gtk-rs/gir)
- [microsoft/windows-rs](https://github.com/microsoft/windows-rs)
- [wasm-bindgen](https://github.com/wasm-bindgen/wasm-bindgen)
- [swift-bridge](https://github.com/chinedufn/swift-bridge)
- [Scapix](https://github.com/scapix-com/scapix)
- [nbind](https://github.com/charto/nbind)
- [LLNL Shroud](https://github.com/LLNL/shroud)
- [CppSharp](https://github.com/KeenSoftwareHouse/CppSharp)
- [Rinf (Rust in Flutter)](https://github.com/FlutterWorks/rinf-rust-flutter)

### Documentation & Guides

- [Mozilla UniFFI User Guide](https://mozilla.github.io/uniffi-rs/latest/)
- [Flutter Rust Bridge Manual](https://cjycode.com/flutter_rust_bridge/manual/)
- [Gluecodium Docs](https://github.com/heremaps/gluecodium/blob/master/docs/lime_idl.md)
- [rust-bindgen Guide](https://rust-lang.github.io/rust-bindgen/)

---

*Research conducted September 2026; all version numbers and maintenance status reflect last-verified information as of that date.*
