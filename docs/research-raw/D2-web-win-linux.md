# Dart Binding Generation for Web, Windows, Linux
## Research Report: September 2026

---

## EXECUTIVE SUMMARY

1. **Web (JavaScript/TypeScript)**: dart:js_interop (stable, Dart 3.3+) provides extension types for JS values; web_generator (GSoC 2025 project, integrated into dart-lang/web) auto-generates Dart bindings from .d.ts files; package:web replaces deprecated dart:html; dart2wasm requires js_interop only (no dart:js_util/package:js on Wasm).

2. **web_generator status**: Lives in dart-lang/web repo, generates bindings from Web IDL & TypeScript declarations; supports variables, functions, enums, classes, interfaces, namespaces, type aliases, unions, typeof/keyof; successfully tested on nanoid/uuid.

3. **Legacy TS→Dart tool**: js_facade_gen (archived Dec 2022) was the predecessor; is_facade_gen generated package:js facades from .d.ts; community forking invited but official effort moved to web_generator.

4. **Windows (Win32/COM/WinRT)**: package:win32 (v6.4.0) generates from Microsoft's Win32 metadata (.winmd files, ECMA-335); internal generator tool processes winmd via package:winmd (v5.3+); COM interface support included; structs auto-generated.

5. **Windows WinRT**: dartwinrt (dart-windows/dartwinrt) provides idiomatic Dart projection of WinRT APIs via FFI; no evidence of windows_*_winrt family being archived in 2025-2026; project active.

6. **Windows Pigeon C++**: Pigeon (Flutter's platform channel codegen) supports C++ for Windows since 2024; generates classes, async callbacks, handlers; experimental/maturing (some issues with forward declarations); GObject support for Linux also in Pigeon.

7. **Linux (GTK/GLib/GObject)**: Flutter Linux uses GTK 3 embedder in C with GObject bindings; GTK4 migration pending (long-standing request, pre-release linking issues); no official timeline.

8. **D-Bus ecosystem (Canonical)**: package:dbus (v0.7.15) + dart-dbus CLI tool generate client/server classes from D-Bus introspection XML (standard freedesktop.org format); input: .xml interface definitions; supports properties, methods, signals; Canonical family: bluez, nm, gsettings, upower, xdg_desktop_portal all use it.

9. **GObject introspection bindings**: llamadonica/dart-gobject-bindings provides gir-binding-gen tool to auto-generate FFI bindings from GIR XML files; canonical/glib.dart (GLib utilities, uses ffigen) provides mid-level bindings; community-maintained, less mature than Rust/Python/Haskell equivalents.

10. **ffigen (FFI Binding Generator)**: v22.0.0 (latest as of September 2026), uses LibClang to parse C/ObjC/Swift headers; YAML-configurable; known issues with C macros, SAL annotations on Windows, __stdcall calling conventions; successfully used for Linux (GLib, stdlibc.dart by Canonical).

11. **Dart 3.7+ interop migration**: dart:html, dart:js_util, package:js deprecated (Feb 2025); all new Web code must use dart:js_interop + dart:js_interop_unsafe + package:web; dart2wasm requires this exclusively; platform-independent JS interop via JSPromise.toDart (converts to Future).

12. **Generator landscape**: No unified standard for describing/consuming C/Win32/GObject/D-Bus APIs in a source-agnostic way; each platform uses different input formats (Web IDL + .d.ts, .winmd ECMA-335, .gir XML, D-Bus introspection XML); ffigen is the only cross-platform tool, but limited to C headers.

---

## A. WEB PLATFORM

### A.1 dart:js_interop (Stable)

**What**: Dart's next-generation JavaScript interoperability library, stable since Dart 3.3 (February 2024).

**How it works**:
- Uses extension types to create zero-cost wrappers over JS values
- @JS() annotation marks Dart functions/types as JS-interoperable
- JS type prefixed types (JSString, JSNumber, JSArray<T>, JSObject, JSPromise<T>, etc.) distinguish Dart/JS boundary at compile-time
- JSPromise.toDart extension converts JS Promise to Dart Future
- dart:js_interop_unsafe for dynamic access when type checking unavailable

**API surface**:
- JSObject, JSArray, JSFunction, JSPromise extension types
- @JS() annotation for functions, external classes, static members
- toJS/toDart conversions for primitives
- @staticInterop for extending JSObject
- @anonymous for object literal types

**Status & lifecycle**:
- Stable (Dart 3.3.0+), actively maintained in dart-lang/sdk
- Breaking change: Dart 3.7 (Feb 2025) deprecated dart:js_util and package:js
- JSArray/JSPromise gained generics in recent updates
- Future: WasmGC (dart2wasm) support is primary use case

**License**: BSD (Dart SDK license)

**Known limitations**:
- No support for variadic arguments or default parameters in @JS methods
- No direct support for callback creation in Dart called from JS (requires JSFunction wrapper)
- Complex TypeScript generics (overloads, conditional types) require manual facades
- Requires opt-in unsafe library for dynamic property access

---

### A.2 web_generator (Dart Web Repository)

**What**: Integrated code generation tool in github.com/dart-lang/web repository, auto-generates Dart bindings from TypeScript .d.ts and Web IDL definitions.

**How it works**:
- **Front-end**: Parses Web IDL spec files and TypeScript declaration files using web standards
- **IR**: Internal AST representing types, methods, properties, signals
- **Emitter**: Generates Dart code using dart:js_interop extension types, implements JSObject as needed
- **Pipeline**: IDL → Dart bindings; .d.ts → Dart facades

**Supported TypeScript/IDL constructs**:
- Variables, functions, enums, classes, interfaces
- Namespaces, type aliases
- Anonymous objects and closures
- Unions, typeof/keyof operators
- Advanced: merged type definitions

**Library API & CLI UX**:
- No published pub.dev package (internal tooling only)
- **CLI**: `dart run web_generator` or via bin/gen_interop_bindings.dart in the web repo
- Config: YAML-based, specifies input IDL files, output Dart package, overrides
- Integration: Used within dart-lang/web to generate package:web

**Filters & fixups**:
- Automatically maps DOM APIs to dart:js_interop types
- Filters to include only standards-track APIs supported by Safari, Chrome, Firefox
- Removes APIs not in standards (vendor-specific removed)
- Generates convenience helpers for common patterns

**Status (2026)**:
- GSoC 2025 project "Translate TS Declarations to Dart JS Interop Interfaces" by Nikechukwu Okoronkwo **completed and merged**
- Successfully generated bindings for nanoid, uuid packages
- Actively maintained in dart-lang/web (288 commits on main, recent PRs)
- Version tracking: tied to package:web releases (latest 0.5.1+)
- Published: Bindings shipped in package:web (pub.dev, verified publisher)

**License**: BSD (Dart Web SDK)

**Known limitations**:
- Only works with Web IDL and TypeScript declarations, not arbitrary C headers
- No support for WasmGC-specific optimizations yet
- Complex TypeScript overloads may require manual intervention
- Limited to browser API scope

**URLs**:
- [dart-lang/web GitHub](https://github.com/dart-lang/web)
- [package:web on pub.dev](https://pub.dev/packages/web)
- [GSoC 2025 Results](https://dart.dev/blog/google-summer-of-code-2025-results)

---

### A.3 Older/Alternative Generators

**js_facade_gen (Archived)**:
- **What**: Predecessor to web_generator; generated package:js JavaScript facades from .d.ts files
- **Status**: Archived December 5, 2022 on dart-archive/js_facade_gen (read-only)
- **How it worked**: Parsed .d.ts using TypeScript Compiler API (Node.js), emitted package:js decorators
- **Why archived**: Dart team improved JS interop (dart:js_interop) making this tool obsolete; contributors welcome to fork
- **Output quality**: Had known issues with union types, enums, multiple .d.ts files; ~100 open issues
- **License**: Apache 2.0

**Other community tools** (GitHub/pub.dev search 2024-2026):
- `ts2dart` (no current maintained version found)
- `dts2dart` (no current maintained version found)
- `dart_ts_interop` (no evidence of active maintenance)
- **Conclusion**: No viable alternative; web_generator is the standard approach post-2025

---

### A.4 dart2wasm & WebAssembly

**What**: Dart-to-WebAssembly compilation target (experimental/preview, stable release in progress as of 2026).

**JS interop requirements**:
- dart2wasm **only supports** dart:js_interop and dart:js_interop_unsafe
- **Breaking**: Code importing dart:js_util or package:js causes compilation error on dart2wasm
- WasmGC (garbage collection in Wasm) required; browser support since Chromium 119
- package:web is built on dart:js_interop, so compatible by default

**FFI on WebAssembly**:
- package:wasm (experimental) provides WASI-based Wasm interop for desktop (Windows, Linux, macOS)
- Prototype status (incomplete); no browser-based FFI yet
- Future direction: native Wasm interop (WASI) may replace FFI for Wasm target

**Migration required**:
- All dart:html usage must migrate to package:web
- All package:js facades must convert to dart:js_interop
- Runtime cost: Same (zero-overhead via extension types)

**URLs**:
- [Dart Wasm Compilation Docs](https://dart.dev/web/wasm)
- [Package:web Migration Guide](https://dart.dev/interop/js-interop/package-web)
- [Dart 3.7 Breaking Changes](https://dart.dev/resources/breaking-changes)

---

## B. WINDOWS PLATFORM

### B.1 package:win32

**What**: Curated Dart FFI bindings for Win32 and COM APIs; auto-generated from Microsoft's Win32 metadata.

**Current version**: 6.4.0 (last updated 34 days from query date, September 2026)

**How bindings are generated**:
- **Source**: Microsoft.Windows.SDK.Win32Metadata (NuGet package downloaded on-demand)
- **Format**: .winmd files (ECMA-335 Common Language Infrastructure binary format)
- **Generator tool**: Internal `generator` package in halildurmus/win32 repo
  - **Input**: .winmd metadata file(s) from Microsoft
  - **Processing**: Uses package:winmd to parse ECMA-335 format, query type definitions, resolve symbol hierarchy
  - **Output**: Generated Dart .dart files with @Native/@struct declarations, FFI int handles (HANDLE), COM vtable bindings
- **Config format**: JSON lists of Win32 functions/interfaces/COM classes to expose (curated surface, not exhaustive)

**Binding features**:
- Win32 typedefs (HANDLE, WPARAM, LPARAM, etc.) as strongly-typed Dart structs
- Struct auto-generation with field offsets computed from metadata
- COM interface generation with vtable pointers and method bindings
- Callbacks via C function pointers (requires wrapper functions)
- Resource cleanup hooks (CloseHandle, DeleteObject, etc.)

**Generator architecture**:
- No published CLI tool; internal to pub.dev package
- Manual curation of API surface (not auto-derived)
- Struct definitions auto-generated from metadata
- Function signatures hand-curated or auto-derived

**Status (2026)**:
- Actively maintained (halildurmus/win32 on GitHub)
- Latest metadata integration (Microsoft.Windows.SDK.Win32Metadata v1.x via NuGet)
- No breaking changes planned
- Package:winmd (v5.3+) is the stable ECMA-335 parser library

**License**: MIT (halildurmus/win32)

**Known limitations**:
- Only covers curated API surface (100s of functions, not 1000s)
- No SAL annotation support (Microsoft's Source Code Annotation Language macros)
- Callbacks require manual wrapper functions (no auto-generation)
- Struct packing/alignment: relies on ECMA-335 metadata encoding

**URLs**:
- [package:win32 on pub.dev](https://pub.dev/packages/win32)
- [halildurmus/win32 GitHub](https://github.com/dart-windows/win32)
- [package:winmd on pub.dev](https://pub.dev/packages/winmd)
- [Microsoft Win32 Metadata GitHub](https://github.com/microsoft/win32metadata)

---

### B.2 WinRT Bindings (dartwinrt)

**What**: Dart FFI projection of Windows Runtime (WinRT) APIs, modern Windows API surface (replaces Win32 for modern apps).

**Package**: dartwinrt (dart-windows/dartwinrt on GitHub, no pub.dev package as of 2026)

**Status**: Active project, not archived; provides idiomatic Dart bindings for WinRT APIs.

**Scope**: Limited set of WinRT APIs exposed; expansion based on user demand.

**Relation to win32**: Complementary; Win32 covers legacy APIs, WinRT covers modern/new APIs.

**windows_* package family**: Search found no evidence of windows_*_winrt packages being archived; no separate COM/WinRT generator tool published.

---

### B.3 Pigeon C++ for Windows

**What**: Flutter's platform channel code generator; added C++ support for Windows (experimental, maturing in 2024-2026).

**How it works**:
- **Input**: Dart file defining message interface (classes, enums, methods)
- **Annotations**: @async for async methods, standard @HostApi/@FlutterApi for direction
- **Output**: Generated C++ header (.h) and source (.cpp) files with message handlers
- **Naming**: Configurable C++ namespace via CppOptions(namespace: '...')
- **Structure**: Generates classes with handler methods, uses flutter::MessageReply<Value> for results

**Features**:
- **Async callbacks**: @async annotation generates callback-based methods
- **Structs**: Nested Dart classes → C++ struct types
- **Enums**: Enumerated types with proper type safety
- **Config**: pubspec.yaml with `cppOptions`, `cppHeaderOut`, `cppSourceOut`

**Generator status (2026)**:
- Basic C++ support landed in 2024 (PR #476)
- Experimental → Production track ongoing
- Known issues with forward declarations (Issue #128330)
- Minimum SDK updated to Flutter 3.27 / Dart 3.6 (recent change)

**File output**:
- messages.g.h (types, serialization, handler interfaces)
- messages.g.cpp (implementation)

**Linux GObject support**: Pigeon also generates GObject C code for Linux plugins (less mature than C++).

**URLs**:
- [pigeon on pub.dev](https://pub.dev/packages/pigeon)
- [Flutter Docs: Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [Pigeon GitHub (flutter/packages)](https://github.com/flutter/packages)

---

## C. LINUX PLATFORM

### C.1 Flutter Linux Embedder & GObject

**What**: Flutter's Linux embedder built on GTK 3 with GObject bindings for plugin integration.

**Architecture**:
- **Base**: GTK 3.0+ (C library)
- **Plugin interface**: GObject-based (fl_plugin, fl_method_channel, fl_event_channel classes)
- **Rendering**: Raster thread (recent refactor)
- **Window**: FlView widget for embedding Flutter in GTK apps

**GObject bindings in embedder**:
- Handwritten C bindings to GLib/GObject (not auto-generated)
- GObject property/signal support for plugin communication
- GType system used for class hierarchies

**GTK4 migration status**:
- **Blockers**: GTK4 pre-release soversion change (0 → 1) caused linking issues
- **Timeline**: Pending since Issue #94804 (December 2021); no official ETA
- **Community**: Active interest in gtk-flutter org; libadwaita for Flutter (April 2025 update)
- **Decision**: No breaking timeline announced for GTK3 deprecation

**URLs**:
- [Flutter Linux Embedder API Docs](https://api.flutter.dev/linux-embedder/)
- [Issue #94804: Use gtk4 for linux desktop](https://github.com/flutter/flutter/issues/94804)
- [gtk.dart (Canonical)](https://github.com/canonical/gtk.dart)

---

### C.2 Dart Bindings for GTK/GLib/GObject

**GObject Introspection (GIR) approach**:

**llamadonica/dart-gobject-bindings**:
- **What**: Auto-generator for Dart FFI bindings from GObject Introspection (GIR) metadata
- **Components**: gir-binding-gen (main generator), gir-bootstrapper
- **Input**: .gir XML files (GObject Introspection format, standard freedesktop.org)
- **Output**: Dart FFI classes with automatic serialization/deserialization
- **Status**: Community project, not Canonical; less mature than Rust/Haskell equivalents
- **Activity**: Ongoing development (recently updated)
- **License**: Unknown (not found in search)

**canonical/glib.dart**:
- **What**: GLib utilities for Dart/Flutter (mid-level bindings)
- **Generation**: Uses ffigen to auto-generate some bindings from GLib headers
- **Scope**: GLib, GObject core utilities
- **Last update**: 2 years ago (July 2024, per pub.dev)
- **Status**: Dart 3 compatible, actively maintained by Canonical
- **Related**: canonical/stdlibc.dart (GNU C Library FFI bindings, updated July 27, 2026)

**Other projects**:
- kevin-sakemaer/gtk (GTK binding for Dart, GitHub repo exists)
- No stable pub.dev package for full GTK4 bindings

**Comparison to other languages**:
- Rust: gtk-rs/gir (robust, well-maintained)
- Haskell: haskell-gi (high-level, comprehensive)
- Nim: gintro (high-level GTK3/GTK4)
- Python: pygobject (canonical implementation)
- **Dart**: Significantly less mature; community-driven

---

### C.3 package:ffigen on Linux

**What**: FFI Binding Generator; uses LibClang to parse C/ObjC/Swift headers; produces Dart FFI bindings.

**Current version**: 22.0.0 (published September 2026, within hours of query date)

**How it works**:
- **Front-end**: LibClang (LLVM 9+) parses C headers, expands macros, builds AST
- **Config**: YAML-based (in pubspec.yaml under ffigen: key or custom file)
- **Output**: Dart source with @Native, @Struct, Function() pointers
- **CLI**: `dart run ffigen` (via build_runner integration optional)

**Linux-specific capabilities**:
- Parses glib.h, gtk/gtk.h, wayland headers, pipewire, libcurl successfully
- Expands C preprocessor macros (uses clang's macro expansion)
- Handles inline functions (limited support)
- Struct packing/alignment computed from clang AST

**Known issues on Linux headers**:
- **Macros**: Constants defined by #define not exported (Issue #12, open)
- **G_OBJECT() casts**: Macro-based type casting not supported; need manual wrappers
- **Varargs** (g_object_new variadic calls): No auto-binding; requires manual wrapper
- **SAL annotations**: Not an issue on Linux (Windows-specific), but related macro handling broken

**Configuration**:
```yaml
ffigen:
  name: 'gtk_bindings'
  description: 'GTK FFI bindings'
  headers:
    - '/usr/include/gtk-3.0/gtk.h'
  excludes:
    - 'G_OBJECT'  # Macro not bindable
```

**Supported platforms**: Linux, macOS, Windows, Android, iOS

**Status (2026)**:
- Actively maintained (dart-lang/native repo)
- Stable API for FFI generation
- No major breaking changes in recent releases
- Performance: fast incremental generation

**License**: BSD/Apache (dart-lang/native)

**Limitations**:
- No macro expansion for complex macros
- No callback generation (requires manual function pointers)
- C++ limited (primarily C)
- No const-correct binding (all const stripped)

**URLs**:
- [ffigen on pub.dev](https://pub.dev/packages/ffigen)
- [dart-lang/ffigen GitHub](https://github.com/dart-lang/ffigen)
- [canonical/glib.dart](https://github.com/canonical/glib.dart) (uses ffigen)
- [canonical/stdlibc.dart](https://github.com/canonical/stdlibc.dart) (uses ffigen)

---

### C.4 Canonical D-Bus Ecosystem

**What**: D-Bus client/server code generation system for Linux inter-process communication; built on package:dbus.

**package:dbus (Core Library)**:
- **Current version**: 0.7.15 (published September 2026, Canonical)
- **Purpose**: Native Dart implementation of D-Bus message bus client
- **Code generator**: CLI tool `dart-dbus` included

**D-Bus Code Generator (dart-dbus CLI)**:

**Input format**:
- D-Bus interface introspection XML (freedesktop.org standard)
- Example structure:
  ```xml
  <node name="/com/example/Test/Object">
    <interface name="com.example.Test">
      <property name="Version" type="s" access="read"/>
      <method name="ReverseText">
        <arg name="input" type="s" direction="in"/>
        <arg name="output" type="s" direction="out"/>
      </method>
    </interface>
  </node>
  ```

**Tool usage**:
```bash
dart-dbus generate-remote-object interface.xml -o output.dart     # Client classes
dart-dbus generate-object interface.xml -o output.dart            # Server classes
```

**Output**:
- Dart classes with typed methods and properties
- Automatic DBus serialization/deserialization (no manual marshaling)
- RemoteObject subclasses for clients, Object subclasses for servers
- Enums and custom types supported

**Configuration**: None (XML-driven, minimal CLI options)

**Canonical ecosystem packages** (built on dbus):
- **package:bluez** (Bluetooth BlueZ service)
- **package:nm** (NetworkManager service)
- **package:gsettings** (Settings storage access)
- **package:upower** (Power management service)
- **package:xdg_desktop_portal** (Desktop portal access)
- All generate D-Bus client classes from introspection XML

**Generator architecture**:
- **Front-end**: XML parser (freedesktop.org spec)
- **IR**: Interface/method/property AST
- **Emitter**: Dart classes with type-safe call signatures, property getters

**Status (2026)**:
- Actively maintained (Canonical, multiple recent releases)
- Stable API (no breaking changes in 2025-2026)
- Comprehensive D-Bus support (methods, properties, signals, variants)
- Well-tested (used in Ubuntu/GNOME ecosystem)

**License**: LGPL 2.1 (canonical/dbus.dart)

**Known limitations**:
- Output is "starting point" (per docs); manual modification common
- No support for D-Bus security (SELinux, apparmor) introspection
- Signals must be manually subscribed (no auto-binding)
- Variant types require runtime type checks

**URLs**:
- [package:dbus on pub.dev](https://pub.dev/packages/dbus)
- [canonical/dbus.dart GitHub](https://github.com/canonical/dbus.dart)
- [Canonical packages](https://pub.dev/publishers/canonical.com/packages)

---

## SURPRISES & CORRECTIONS TO COMMON BELIEFS

1. **web_generator is not published**: Despite being a mature tool (GSoC 2025 project), web_generator is **not a pub.dev package**. It's internal tooling within dart-lang/web. Users cannot `dart pub add web_generator`; they consume it indirectly via package:web.

2. **js_facade_gen is dead, not dormant**: Archived in December 2022; not "maintained in the shadows" or "used internally." The Dart team officially moved to web_generator as the replacement. Forking is explicitly invited.

3. **Pigeon C++ is *not* stable**: Marketed as "experimental" and "maturing" in 2024-2026; real blockers exist (forward declaration issues, async callback bugs). Not production-hardened like Objective-C or Java generators.

4. **Windows WinRT is fragmented**: No unified dartwinrt generator on pub.dev. Bindings are hand-curated + auto-derived structs. Contrast with package:win32 which has a clear generator pipeline; WinRT bindings are incomplete and curated-only.

5. **ffigen can't bind C macros**: Fundamental limitation; not fixable without runtime introspection. GLib's G_OBJECT() cast macro is *not* bindable by ffigen; requires manual wrapper functions. This breaks naive porting of C code to Dart.

6. **Canonical's D-Bus generator is the *only* working large-scale Linux binding generator for Dart**: Unlike ffigen (limited by macro/varargs issues), dart-dbus works reliably at scale. All 5+ Canonical packages use it successfully. This is **the** model for Linux interop on Flutter.

7. **GTK4 migration is genuinely stalled, not "in progress"**: Issue #94804 (Dec 2021) → April 2025 (libadwaita updates) → Sept 2026 (no official migration). Pre-release soversion breakage was never decisively fixed. Flutter Linux still GTK3-only.

8. **dart2wasm breaks all legacy JS interop**: Not a version bump; a hard break. Code using dart:html or package:js won't even *compile* to Wasm. Migration required before adoption (not post-hoc compatible).

9. **llamadonica/dart-gobject-bindings exists but is not Canonical-endorsed**: Community project; significantly less mature than equivalent Rust/Python tools. GObject introspection *could* work at scale (standard interface format), but Dart ecosystem hasn't invested in production tooling.

10. **No unified "source-agnostic" binding format across platforms**: Web uses Web IDL + .d.ts, Windows uses .winmd (ECMA-335), GObject uses .gir (XML), D-Bus uses introspection XML. A hypothetical "generate Dart bindings from *any* platform" CLI would need 4 separate front-ends. No single tool does this.

---

## OPEN QUESTIONS (Not Verified)

1. **web_generator TypeScript support scope**: Does it handle all TypeScript 5.x features (const type parameters, satisfies, template literal types)? Docs mention "advanced features" but no exhaustive checklist found.

2. **win32 generator curation policy**: What determines which Win32 APIs are exposed? Is there a public RFC/issue tracker for adding new APIs, or is it ad-hoc?

3. **Pigeon C++ callback lifecycle**: How are C++ callbacks created from Dart? Are they GCable, or do they leak? No documentation found on this detail.

4. **dart-gobject-bindings maturity**: Can it handle Gtk4? Has it been used for large GTK libraries (Gedit, Nautilus)? No production examples found.

5. **ffigen macro expansion strategy**: For G_OBJECT() and similar macros, is the plan to add a whitelist of "known safe macros," or to expose clang's expanded macro bodies?

6. **Linux plugin channel stability**: Are fl_method_channel/fl_event_channel ABIs stable across Flutter versions, or do plugins need rebuilding per Flutter minor version?

7. **Dart2wasm browser support timeline**: Which browsers will ship WasmGC support by 2027? Only Chromium 119+ confirmed; Safari/Firefox timelines unclear.

8. **win32 metadata freshness**: How often does halildurmus/win32 pull the latest Microsoft.Windows.SDK.Win32Metadata? Lag time between Windows SDK release and win32 package update?

9. **D-Bus variant type handling performance**: For D-Bus variants (dynamic type), is there runtime type introspection overhead? Any benchmarks vs. hand-written code?

10. **Canonical package maintenance commitment**: Are bluez.dart, nm.dart, gsettings.dart guaranteed to track upstream D-Bus API changes indefinitely, or are they "frozen" at specific versions?

---

## REFERENCE LINKS

### Web
- [dart.dev: JavaScript interoperability](https://dart.dev/interop/js-interop)
- [Dart Blog: New in Dart 3.3](https://dart.dev/blog/new-in-dart-3-3-extension-types-javascript-interop-and-more)
- [dart:js_interop API](https://api.dart.dev/stable/latest/dart-js_interop/index.html)
- [package:web on pub.dev](https://pub.dev/packages/web)
- [dart-lang/web GitHub](https://github.com/dart-lang/web)
- [Dart GSoC 2025 Results](https://dart.dev/blog/google-summer-of-code-2025-results)
- [Migration Guide: dart:html → package:web](https://dart.dev/interop/js-interop/package-web)
- [Dart Wasm Compilation](https://dart.dev/web/wasm)

### Windows
- [package:win32 on pub.dev](https://pub.dev/packages/win32)
- [halildurmus/win32 GitHub](https://github.com/dart-windows/win32)
- [package:winmd on pub.dev](https://pub.dev/packages/winmd)
- [Microsoft Win32 Metadata GitHub](https://github.com/microsoft/win32metadata)
- [dartwinrt GitHub](https://github.com/dart-windows/dartwinrt)
- [pigeon on pub.dev](https://pub.dev/packages/pigeon)
- [Pigeon GitHub (flutter/packages)](https://github.com/flutter/packages)
- [Flutter: Writing custom platform-specific code](https://docs.flutter.dev/platform-integration/platform-channels)

### Linux
- [Flutter Linux Embedder API Docs](https://api.flutter.dev/linux-embedder/)
- [canonical/dbus.dart GitHub](https://github.com/canonical/dbus.dart)
- [package:dbus on pub.dev](https://pub.dev/packages/dbus)
- [canonical/glib.dart GitHub](https://github.com/canonical/glib.dart)
- [canonical/stdlibc.dart GitHub](https://github.com/canonical/stdlibc.dart)
- [llamadonica/dart-gobject-bindings GitHub](https://github.com/llamadonica/dart-gobject-bindings)
- [ffigen on pub.dev](https://pub.dev/packages/ffigen)
- [dart-lang/ffigen GitHub](https://github.com/dart-lang/ffigen)
- [gtk.dart (Canonical) GitHub](https://github.com/canonical/gtk.dart)
- [Issue #94804: Use gtk4 for linux desktop](https://github.com/flutter/flutter/issues/94804)
- [Canonical packages (pub.dev)](https://pub.dev/publishers/canonical.com/packages)

---

**Document version**: 1.0  
**Date compiled**: September 8, 2026  
**Research scope**: Dart binding generation for Web, Windows (Win32/COM/WinRT), Linux (GTK/GLib/GObject/D-Bus)  
**Primary sources**: Official Dart/Flutter docs, pub.dev packages, GitHub repositories (Dart team + community), Google Summer of Code 2025 results
