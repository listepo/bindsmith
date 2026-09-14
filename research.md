# bindsmith — research: a native-API bindings generator for every Flutter platform

Date: 2026-09-08. Method: 8 parallel research agents (Haiku) over dimensions D1–D8 → 5 adversarial fact-check agents (FC-1…FC-4) → synthesis (Fable). Raw reports live in `docs/research-raw/`. A Russian copy of this document is `docs/research.ru.md`. Claims the fact-check could not confirm are marked `[~]`; corrected ones `[✗→✓]`; unmarked claims were confirmed against a primary source.

---

## 1. Problem statement

We need a program that takes a description of a native API (C/Objective-C headers, Swift modules, JAR/AAR, `.d.ts`, `.winmd`, `.gir`, D-Bus XML) and generates Dart bindings for the six Flutter platforms — Android, iOS, macOS, Windows, Linux, Web — runs from the command line and is driven by config files. Reference points: Mono/Xamarin/.NET MAUI (bgen, Objective Sharpie, class-parse/generator, Metadata.xml), NativeScript (metadata generator + dynamic runtime), plus the Rust/IDL world (uniffi, flutter_rust_bridge, Gluecodium, Djinni, SWIG).

One distinction matters throughout:

| Direction | What it is | Dart tools |
|---|---|---|
| native → Dart ("bindings") | Dart calls an existing native API directly | ffigen (C/ObjC), swiftgen (Swift), jnigen (Java/Kotlin), dart:js_interop (JS), win32/winmd, dbus, gir |
| Dart ↔ native ("channels / scaffolding") | We define a message interface and generate both sides | pigeon (Kotlin/Java/Swift/ObjC/C++/GObject; no Web) |

The user's task is the first direction; pigeon stays an auxiliary path for cases where a direct call is impossible or undesirable.

---

## 2. What actually exists in Dart/Flutter (September 2026)

| Package | Version / date | What it does | Config | Limits |
|---|---|---|---|---|
| `ffigen` | 22.0.0 (2026-09-08) | C and Objective-C headers → Dart FFI via libclang | Dart script `tool/ffigen.dart`: `FfiGenerator`, `Input`, `DartOutput`, visitor API (`.name`, `.isIncluded`). YAML deprecated | No C++; macros, varargs, SAL annotations, `__stdcall` are trouble spots |
| `objective_c` | 9.6.0 (2026-08-20) | ObjC interop runtime: `ObjCObjectBase`, blocks (`.fromFunction/.listener/.blocking`), ARC via `NativeFinalizer`, protocols via `ObjCProtocolBuilder` | — | Apple only |
| `swift2objc` | 0.3.0 (2026-09-08) [✗→✓ it is on pub.dev] | Generates an ObjC wrapper from Swift code | Dart API | Experimental |
| `swiftgen` | 0.2.0 (2026-09-08) | Orchestrates swift2objc → swiftc → ffigen; emits `.g.dart` + `.m` | Dart script with class `SwiftGenerator` (`target`, `inputs`, `include`, `output`, `ffigen`) | Experimental; 4-line README; NSObject-compatible types only (Swift structs/generics do not bridge) |
| `jnigen` / `jni` | 1.0.0 (2026-09-03) / 1.0.3 (2026-07-30) [✗→✓ jni is not 1.0.0] | Java/Kotlin (bytecode or sources) → Dart via JNI | Dart script `tool/jnigen.dart`: `JniGenerator`, `Input`, `DartOutput`, `generate()`; YAML is legacy | Needs JDK 17–21 and Android SDK at generation time; Kotlin suspend → `Future`, nullability from Kotlin metadata; interfaces implemented via `implement()`; global refs released manually (`.release()`) |
| `pigeon` | 28.0.0 (2026-08-21) | Type-safe platform channels; `@HostApi`, `@FlutterApi`, `@ProxyApi` | Dart file with `@ConfigurePigeon(PigeonOptions(...))` | No Web; both sides on one pigeon version; pigeon in public APIs is "strongly discouraged" |
| `win32` / `winmd` | 6.4.0 (2026-08-05) / 7.1.1 (2026-08-04) | Win32/COM bindings generated from Microsoft `Win32Metadata` (`.winmd`) | Internal generator in `halildurmus/win32/packages/generator` (curated JSON lists) | Users do not generate; `winmd` is usable as a metadata reader library |
| `dbus` (Canonical) | 0.7.15 (2026-08-20) | `dart-dbus generate-remote-object <iface.xml>` / `generate-object` | CLI | D-Bus only (Linux), LGPL 2.1 |
| `dart-gobject-bindings` (`gir-binding-gen`) | community, updated 2026-09-06 | `.gir` (GObject-Introspection) → Dart | — | Immature, single author |
| `web` + `web_generator` | web_generator is an internal dart-lang/web tool, not on pub.dev [✗→✓] | Generates `package:web` from WebIDL (`@webref/idl`, `webidl2`) | — | Does NOT handle TypeScript `.d.ts` |
| `js_interop_gen` (dart-lang/web) | unpublished; 2025 PRs (#549, #554) | `.d.ts` → Dart `dart:js_interop` (extension types) | — | In development; the only living TS→Dart generator (js_facade_gen archived 2022) |
| `hooks` / `code_assets` / `native_toolchain_c` / `native_toolchain_cmake` | 2.2.0 / 2.0.0 / 0.19.4 / 0.3.2 (August 2026) | Build hooks (`hook/build.dart`, `hook/link.dart`): building and bundling native code | Dart | On by default in stable since Flutter 3.38 (Dart 3.10, November 2025) [✗→✓ not "September 2024"] |
| Template `package_ffi` | recommended since Flutter 3.38; `plugin_ffi` deprecated [✗→✓] | `lib/`, `src/`, `hook/build.dart` | — | — |

Also: `dart:js_interop` stable since Dart 3.3 (February 2024), `dart:js_util`/`package:js` deprecated since Dart 3.7; dart2wasm compiles `dart:js_interop` code only. Pub workspaces stable since Dart 3.6. `dart compile exe --target-os` cross-compiles to Linux targets only (arm, arm64, riscv64, x64) [✗→✓].

Who uses what in production (D7, partly unverified `[~]`): Flutter-team plugins (webview_flutter, camera, video_player, in_app_purchase, local_auth) — pigeon; path_provider/url_launcher/shared_preferences — hand-written channels; Dart team — `cupertino_http` (ffigen ObjC, `ffigen.yaml` in repo), `ok_http` (jnigen), `sqlite3` (ffigen C); Sentry moving to FFI/JNI `[~]`; Nutrient shipped a "bindings API" (beta February 2026 → GA July 2026) `[~]`; HERE SDK — Gluecodium (own generator with a Dart target). No vendor generates Flutter wrappers from an SDK automatically; flutter/flutter#98084 "Web interop in pigeon" has been open since 2022.

Conclusion: all the bricks for individual platforms exist and are officially maintained, but **no tool takes one declaration and emits bindings for six platforms** plus a unified Dart facade. The nearest "orchestrators" are swiftgen (Swift→ObjC→Dart only) and dart-native/codegen (ObjC+Java, undocumented).

---

## 3. How interop/bindings of a native API are generated on each platform

One scheme: **input → generator → config → commands → runtime → build integration → pitfalls**. Config snippets are schematic (class names from the ffigen 22 / jnigen 1.0 changelogs; exact signatures are in the package API docs).

### 3.1 Android — Java/Kotlin via jnigen + jni

- **Input:** `.class`/JAR/AAR (including Maven), or Java sources; Kotlin only compiled (Kotlin metadata read for nullability and `suspend`).
- **Config** `tool/jnigen.dart`:
  ```dart
  import 'package:jnigen/jnigen.dart';
  void main() => JniGenerator(
        input: Input(
          classes: ['androidx.biometric.BiometricPrompt'],
          // maven deps, android_sdk_config(add_gradle_deps), source_path...
        ),
        output: Output(dart: DartOutput(path: Uri.directory('lib/src/android/'))),
      ).generate();
  ```
  Legacy: `jnigen.yaml` (`classes:`, `maven_downloads: source_deps/jar_only_deps`, `android_sdk_config: add_gradle_deps: true`, `output: dart: path/structure`).
- **Commands:** `dart run tool/jnigen.dart` (or `dart run jnigen --config jnigen.yaml`). For a plugin with an Android example jnigen runs Gradle itself to build the classpath — hence "build Android first".
- **Runtime:** `package:jni` — `JObject`, `JString`, `JList/JMap`, `Jni.spawn()` for a desktop JVM; release global refs with `.release()`; Java interfaces implemented from Dart via `Interface.implement(...)`.
- **Build:** `ffiPlugin: true`/Gradle; R8/ProGuard keep rules for classes called from Dart; JDK 17–21.
- **Pitfalls:** numbered overload suffixes change between versions (`Intent.new$2` → `Intent.new$12`); coroutines/default params/companion objects need a Kotlin facade; keep callback objects referenced from Dart or the GC collects them.

### 3.2 iOS / macOS — Objective-C via ffigen + objective_c; Swift via swiftgen

- **ObjC input:** framework headers (system or from an xcframework/pod). **Swift input:** a Swift module; swiftgen runs `swift2objc` → `swiftc -emit-objc-header` → ffigen.
- **Config** `tool/ffigen.dart` (ObjC):
  ```dart
  import 'package:ffigen/ffigen.dart';
  void main() => FfiGenerator(
        input: Input(entryPoints: [Uri.file('src/wrapper.h')], /* language objc, compilerOpts */),
        output: Output(dart: DartOutput(path: Uri.file('lib/src/ios/av.dart'))),
        // objcInterfaces / protocols / categories — include filters;
        // visitor: renames, exclusions
      ).generate();
  ```
  Swift: `tool/swiftgen.dart` with `SwiftGenerator(target:, inputs:, include:, output:, ffigen:)`.
- **Commands:** `dart run tool/ffigen.dart`; `dart run tool/swiftgen.dart`. Commit both `.g.dart` and `.m` (the latter must fall under the podspec's `Classes/**`).
- **Runtime:** `package:objective_c` (ARC via `NativeFinalizer`, blocks `.fromFunction`/`.listener`/`.blocking`, protocols via `$Builder.implementAsListener`), `package:ffi`.
- **Build:** podspec `s.frameworks = 'AVFoundation'` or SwiftPM `linkerSettings: [.linkedFramework(...)]`; `ffiPlugin: true` for ios/macos.
- **Pitfalls:** only `@objc`/NSObject-compatible Swift APIs are visible; blocks invoked from foreign threads must be `.listener`/`.blocking`; UIKit/AppKit are main-thread; include filters are mandatory (otherwise millions of lines from transitive frameworks); macros are not carried over.

### 3.3 Windows — C via ffigen, Win32/COM via win32 (+winmd), C++ via a shim

- **Input:** C headers (own or SDK, paths `Windows Kits\10\Include\...\um|shared`); for Win32 — `.winmd` from NuGet `Microsoft.Windows.SDK.Win32Metadata`.
- **Generator:** ffigen (`Input(compilerOpts: ['-I...'])`); Win32 — the pre-generated `package:win32` (do not regenerate; for a custom slice use `package:winmd` as a metadata reader); C++ SDKs — an `extern "C"` shim built by `native_toolchain_c`/`native_toolchain_cmake` from `hook/build.dart`.
- **Runtime:** `package:ffi`, `package:win32` (COM vtables, `calloc/free`).
- **Build:** `hook/build.dart` (`build(args, (input, output) => CBuilder/CLibrary...)`), `ffiPlugin: true` for windows; channels — pigeon C++ (`cppHeaderOut/cppSourceOut`).
- **Pitfalls:** libclang required for ffigen; SAL annotations/`__stdcall`; MSVC redistributables when distributing; pigeon C++ forward-declaration bugs (issue #128330).

### 3.4 Linux — C via ffigen + pkg-config, D-Bus via dart-dbus, GObject via .gir

- **Input:** C headers (`pkg-config --cflags gtk+-3.0` → include paths); D-Bus introspection XML; `.gir`.
- **Generator:** ffigen (Canonical does this for `glib.dart`, `stdlibc.dart`); `dart-dbus generate-remote-object iface.xml -o lib/x.dart` (client) / `generate-object` (server); `gir-binding-gen` (community).
- **Runtime:** `package:ffi`, `package:dbus`.
- **Build:** `hook/build.dart` + `ffiPlugin: true`; channels — pigeon GObject (the Flutter Linux embedder is GTK3; the GTK4 migration has been stalled since 2021, issue #94804).
- **Pitfalls:** `G_OBJECT()` cast macros and `g_object_new` varargs are not carried over by ffigen; glibc versions; D-Bus code is "rough" and needs finishing by hand.

### 3.5 Web — dart:js_interop, package:web, generation from .d.ts

- **Input:** browser APIs — WebIDL (already generated into `package:web`); JS libraries — `.d.ts` (npm) or hand-written declarations.
- **Generator:** for apps — hand-written `extension type Chart(JSObject _) implements JSObject { external ... }` with `@JS()`; automation from `.d.ts` — only the unpublished `js_interop_gen` in dart-lang/web; `js_facade_gen` archived (2022).
- **Runtime:** `dart:js_interop` (`JSPromise.toDart`, `.toJS`, `JSFunction`), `package:web`.
- **Build:** `<script>` in `web/index.html` or loading in `flutter_bootstrap.js`; plugin — `pluginClass`/`fileName` under `flutter: plugin: platforms: web`.
- **Pitfalls:** TS structural typing vs nominal extension types; keep callbacks referenced (`.toJS`) or they are collected; `dart:html`/`package:js` do not compile under dart2wasm.

### 3.6 Packaging

- `flutter create --template=package_ffi <name>` (Flutter ≥ 3.38): `lib/`, `src/`, `hook/build.dart`; `hooks` + `code_assets` + `native_toolchain_c` in dev_dependencies.
- Federated plugin: app-facing package with `default_package:` per platform, implementations with `implements:`; FFI implementations use `ffiPlugin: true`.
- Pigeon: `dart run pigeon --input pigeons/messages.dart`; `@async` → Kotlin `suspend`/Swift `async throws` (default since v28).

### 3.7 Summary table

| Platform | Input | Generator | Config | Runtime | Build | Maturity |
|---|---|---|---|---|---|---|
| Android | .class/JAR/AAR, Maven | jnigen 1.0 | `tool/jnigen.dart` | jni 1.0.3 | Gradle, R8 keep | stable, breaking 0.14→1.0 |
| iOS/macOS ObjC | framework .h | ffigen 22 (objc) | `tool/ffigen.dart` | objective_c 9.6 | podspec/SwiftPM | stable |
| iOS/macOS Swift | Swift module | swiftgen 0.2 | `tool/swiftgen.dart` | objective_c | podspec Classes/** | experimental |
| Windows C | .h | ffigen 22 (c) | `tool/ffigen.dart` | ffi | hook/build.dart | stable |
| Windows Win32/COM | .winmd | win32 (pre-built), winmd | — | win32 | — | stable, no self-generation |
| Linux C/GLib | .h + pkg-config | ffigen 22 | `tool/ffigen.dart` | ffi | hook/build.dart | stable, macros by hand |
| Linux D-Bus | introspection XML | dart-dbus | CLI | dbus | — | stable |
| Linux GObject | .gir | gir-binding-gen | — | — | — | immature |
| Web browser API | WebIDL | web_generator (internal) | — | web | — | stable (pre-built package) |
| Web JS libraries | .d.ts | js_interop_gen (unpublished) / by hand | — | dart:js_interop | index.html | market gap |
| Channels | Dart IDL | pigeon 28 | `@ConfigurePigeon` | — | — | stable; no Web |

---

## 4. Analogs in other ecosystems

### 4.1 Mono / Xamarin / .NET MAUI

**iOS/macOS (dotnet/macios).** A binding is a hand-written `ApiDefinition.cs`/`StructsAndEnums.cs` with `[BaseType]`, `[Export]`, `[Protocol]`, `[Model]`, `[NullAllowed]`, `[Static]`, `[Wrap]`, `[BindAs]`, `[Field]`; the `bgen` generator emits objc_msgSend trampolines and the registrar. All Apple SDKs are bound the same way, by hand, with coverage checked by `xtro-sharpie` tests. RFC #21308 (moving bgen to Roslyn, "rgen") has been open since September 2024, milestone Future, no development [✗→✓].

**Objective Sharpie.** `dotnet tool install -g Sharpie.Bind.Tool`; macOS only; sources are not public, but it is an ordinary dotnet global tool, not a "closed utility" [✗→✓]. It parses headers with libclang and emits a draft ApiDefinition with a `[Verify]` attribute that **intentionally breaks compilation until the developer reviews the spot and removes the attribute** (hints: `InferredFromPreceedingTypedef`, `ConstantsInterfaceAssociation`, `MethodToProperty`, `StronglyTypedNSArray`, `PlatformInvoke`). The best known UX pattern for forced review of generated code.

**Android (.NET for Android).** `class-parse` reads bytecode (including Kotlin metadata) → `api.xml` → `generator` emits C# with `[Register]`/`JniPeerMembers`. Fixups — `Metadata.xml` on XPath: `<remove-node path="..."/>`, `<attr path="..." name="managedName">…</attr>`, `<add-node>`; plus `EnumFields.xml`/`EnumMethods.xml`. Dependencies — `<AndroidMavenLibrary Include="g:a" Version="…"/>` (.NET 9) with automatic Maven download and **Java dependency verification**. Kotlin `suspend` (hidden `Continuation`) does not bind `[~]`.

**Swift.** .NET 9: `CallConvSwift`, `SwiftSelf`/`SwiftError`; the experimental `dotnet/runtimelab` SwiftBindings consumes `.swiftinterface` + dylib, structs/enums/static functions only for now.

**Native Library Interop (MAUI Community Toolkit).** The officially recommended "slim binding" pattern: write a thin Swift/Kotlin wrapper with a simple surface → bind the wrapper, not the SDK. Template — the `CommunityToolkit/Maui.NativeLibraryInterop` repository (not `dotnet new`).

**C/C++/Win32.** CppSharp v1.2 (Clang 19; config is a C# `ILibrary` class, passes pipeline); ClangSharpPInvokeGenerator 21.1.8.4 (`.rsp` files, `--remap`, `--with-attribute`, `--exclude`, `--traverse`); CsWin32 0.3.333 — Roslyn source generator with a **pull model**: `NativeMethods.txt` lists the APIs you need, only those are generated from `Windows.Win32.winmd`; win32metadata 71.x — one machine-readable Win32 model consumed by CsWin32, windows-rs, Dart `win32`, Zig.

**.NET lessons:** (1) nullability and generics are permanent gaps; (2) no SDK binds without manual fixups; (3) slim binding beat "bind everything"; (4) dependency resolution must be part of the generator; (5) `[Verify]` is cheaper than production bugs; (6) generated code size is a linking/trimming problem.

### 4.2 NativeScript — the dynamic pole

Metadata for the whole platform API is generated at build time: iOS — `ios-metadata-generator` (C++/libclang) → binary `metadata-<arch>.bin`; Android — `android-metadata-generator` (ASM/BCEL) → `treeNodeStream/treeValueStream/treeStringsStream`. The runtime (V8 on iOS since NativeScript 7.0, 2020 — not "9.0/2025" [✗→✓]) dispatches calls through libffi/objc_msgSend and JNI reflection. Filtering — `native-api-usage.json` (whitelist/blacklist in plugins and `App_Resources`), not `.mdg` [✗→✓]. IDE types — `ns typings ios` / `ns typings android --jar|--aar`; packages `@nativescript/types-ios` 15.2 MB and `types-android` 48.1 MB (unpacked, 9.1.1). Subclassing native classes — Static Binding Generator.

Pros: 100% API coverage without per-library codegen; APIs are available as soon as the SDK ships. Cons: runtime and metadata in the binary, no tree-shaking, slower startup, per-call overhead **≈3.5× native** by NativeScript's own benchmark (49 ms vs 14 ms for 100k calls, iPhone 13 Pro, NS 8.3) [✗→✓ not "1.5–2×"]. For Flutter this path would mean its own runtime and the loss of AOT advantages — rejected (see §6). We borrow the idea of an **API-usage whitelist** as a pull model and type generation from metadata.

Relatives: dart_native (Alibaba; pub.dev 0.7.11, December 2022 — abandoned [✗→✓]; the `dart-native/codegen` repository is alive but has no README), PyObjC/rubicon-objc, Pyjnius/Chaquopy, Unity `AndroidJavaObject`, JNA, koffi.

### 4.3 Rust and IDL multi-targets

| Tool | Version | Input → output | Config | Lesson for us |
|---|---|---|---|---|
| uniffi-rs | 0.32.0 (2026-06-30) [✗→✓] | Rust (proc-macros/UDL) → Kotlin, Swift, Python, Ruby; third-party: Go, C#, RN, **Dart** (`Uniffi-Dart/uniffi-dart` 0.2.1, June 2026, active) | `uniffi.toml` `[bindings.<lang>]`, custom_types | One ComponentInterface + Askama templates + compatibility checksums |
| flutter_rust_bridge | 2.13.0 (2026-08-23); 2.14 beta [✗→✓ not 1.8.2] | Rust (syn) → Dart, all 6 platforms (Web via wasm) | `flutter_rust_bridge.yaml` (`rust_input`, `dart_output`, integration cargokit/native-assets) | The only mature "one declaration → 6 platforms", but Rust input only |
| Gluecodium (HERE) | 14.1.1 (2026-03-03), active | LIME IDL → C++, Java, Kotlin, Swift, **Dart** | CLI `-generators cpp,java,kotlin,swift,dart` | Official Dart target via dart:ffi and opaque handles; docs are not carried over |
| Djinni | 1.4.1 (December 2023) [✗→✓ unmaintained] | IDL → C++/Java/ObjC | — | No Dart; dead |
| SWIG / wit-bindgen | — | no Dart target (SWIG: issue #557; wit-bindgen: Rust, C, C++, C#, Go) | — | — |
| rust-bindgen | 0.72 | C/C++ → Rust | allowlist/blocklist, `ParseCallbacks` | Programmable fixups |
| objc2 header-translator | objc2 0.6.4 | Apple SDK → `objc2-*` crates | per-framework `translation-config.toml` (`skipped`, per-OS availability, safety flags) | Best model of declarative fixups + availability gating |
| gtk-rs gir | — | `.gir` → sys + safe layers | `Gir.toml` `[[object]] status = generate/manual/ignore` | Two layers: raw and idiomatic |
| windows-rs / windows-bindgen | 0.100.0 (2026-09-03) | `.winmd` → Rust | `--filter`, `--in/--out`, `--flat`, `--sys`, `--reference` (`--minimal` unconfirmed [~]) | Pull model by filter |

### 4.4 Kotlin / Swift / Java / JS ecosystems

- **Kotlin/Native cinterop** — `.def` (`headers`, `headerFilter`, `excludeFilter`, `compilerOpts`, `strictEnums`, C preamble after `---`); no macros. **Swift export** — experimental since Kotlin 2.2.20 (status on 2.4.20 not confirmed `[~]`). **SKIE** 0.10.14 (July 2026) — Touchlab's Gradle plugin fixing suspend/Flow/sealed on the Swift side. **karakum** 1.0.0-alpha.112 — TS `.d.ts` → Kotlin/JS via the TypeScript Compiler API.
- **swift-java** 0.6.0 (2026-09-05): modes `ffm` (JDK 25+, Swift 6.2) and `jni` (Android); JDK 17+ for macros. **jextract** (OpenJDK, active): libclang, `--include-*`, the "`--dump-includes` → edit → `--config`" dump-then-curate workflow. **JavaCPP presets** — `Info(...)` maps in Java code.
- **React Native** 0.87.1 (New Architecture default since 0.76 `[~]`), codegen from TS specs (`codegenConfig`); Nitro/nitrogen (`nitro.json`; repository moved); Expo Modules DSL. **Agora Terra** — `cxx-parser` (cppast + libclang) → TerraNode AST → TS renderers, YAML config; Dart renderer for agora_rtc_engine `[~]`.
- **Common lessons:** async mapping differs per ecosystem (suspend/Flow, Swift async, Promise → Future/Stream); nullability comes from annotations (JSpecify, Kotlin metadata, ObjC `nullable`); generics are erased; main-thread annotations must be carried over; docs are lost almost everywhere; snapshot tests of generated code + a compile matrix are universal practice; fixups range from "minimal renames" to "full override".

---

## 5. Comparison matrix

| Tool | Approach | Input | Targets | Config | Fixups | Review | Dependencies | Maturity / license |
|---|---|---|---|---|---|---|---|---|
| Xamarin/MAUI bgen + Sharpie | static codegen, hand-written IDL in C# | ObjC .h | C# iOS/macOS | C# attributes | in ApiDefinition | `[Verify]` | pod/xcframework by hand; NLI template | mature / MIT (Sharpie not public) |
| .NET for Android generator | static, from bytecode | JAR/AAR | C# Android | MSBuild + `Metadata.xml` | XPath | none | `AndroidMavenLibrary` + verification | mature / MIT |
| CsWin32 | source generator, pull | `.winmd` | C# Windows | `NativeMethods.txt` | JSON options | none | NuGet metadata | mature / MIT |
| NativeScript | dynamic runtime + metadata | whole SDK | JS/TS iOS/Android | `native-api-usage.json` | none | none | CocoaPods/Gradle from plugin | mature / Apache-2.0 |
| uniffi-rs | static from Rust | Rust | Kotlin/Swift/Py/Ruby (+Dart) | `uniffi.toml` | custom_types | none | cargo | mature / MPL-2.0 |
| flutter_rust_bridge | static from Rust | Rust | Dart × 6 platforms | YAML | attributes | none | cargokit/native-assets | mature / MIT |
| Gluecodium | static from IDL | LIME | C++/Java/Kotlin/Swift/Dart | CLI | in IDL | none | — | mature / Apache-2.0 |
| objc2 header-translator | static from SDK | Apple .h | Rust | `translation-config.toml` | declarative | none | — | mature / MIT |
| ffigen / jnigen / swiftgen / pigeon | static, one platform each | .h / .class / Swift / Dart IDL | Dart | Dart scripts | visitor / include | none | jnigen: Maven | stable / experimental; BSD |
| **bindsmith (proposed)** | static orchestrator + unified IR | .h, Swift, JAR/AAR, .d.ts, .winmd, .gir, D-Bus XML | Dart × 6 + facade + native wrappers | YAML + JSON Schema, Dart escape hatch | declarative + visitor | `verify` markers | Maven/CocoaPods/SwiftPM/npm/NuGet + lockfile | — |

---

## 6. Static codegen vs dynamic bridge

| Criterion | Static (ffigen/jnigen/bgen) | Dynamic (NativeScript) |
|---|---|---|
| API coverage | only what the config describes (pull) | 100% immediately |
| Type safety | full, `dart analyze` | types for the IDE only |
| App size | minimal (tree-shaking) | +metadata, +runtime |
| Call cost | direct FFI call | ≈3.5× slower than native |
| AOT/Flutter | natural | needs its own JIT/interpreter — impossible on iOS |
| Maintenance | generator × platforms | runtime × platforms + metadata |

Decision: static codegen. From the dynamic world we take the pull model (usage whitelist) and type generation from metadata.

---

## 7. Implementation language

| Criterion | Dart | Rust | Kotlin/JVM | TypeScript/Node | C# |
|---|---|---|---|---|---|
| Official generators as libraries (`FfiGenerator`, `JniGenerator`, `SwiftGenerator`, `Pigeon.runWithOptions`, `winmd`) | direct | subprocess only | subprocess | subprocess | subprocess |
| Emitting Dart (code_builder 4.12, dart_style 3.1, analyzer 14.3 for checks) | native | no | no | no | no |
| Distribution to Flutter developers | `dart pub global activate`, `dart run`, `dart compile exe` | cargo/binary | JVM | npm | dotnet tool |
| Parsing `.d.ts` | via a node sidecar or a port | swc/oxc — no type semantics | karakum approach | TypeScript Compiler API — ideal | no |
| Generation speed | not critical | excessive | JVM startup | fine | fine |
| Who will contribute | Flutter community | narrow | narrow | broad, but foreign to Flutter | narrow |

Decision: **Dart** for the core, CLI and all drivers; for `.d.ts` a narrow sidecar on the TypeScript Compiler API (node), invoked by the `web` driver, or reuse of `js_interop_gen` from dart-lang/web once it matures. No second language in the core.

---

## 8. Proposed bindsmith architecture

```
bindsmith.yaml ──► config loader (yaml + JSON Schema) ──► generation plan
                                                                    │
     ┌──────────────┬──────────────┬──────────────┬─────────────────┼──────────────┬──────────────┐
  driver c       driver objc    driver swift   driver jvm       driver web     driver winmd   driver dbus/gir
  (ffigen)       (ffigen+       (swiftgen)     (jnigen)         (.d.ts/WebIDL  (package:winmd) (dart-dbus,
                 objective_c)                                    → js_interop)                   gir)
     └──────────────┴──────────────┴──────────────┴─────────────────┴──────────────┴──────────────┘
                                                                    │
                                   unified IR (BindingModel: types, members, fields, async, nullability, availability, docs)
                                                                    │
                     passes: include/exclude → rename → nullability → async-mapping → threading → availability
                             → doc-propagation → fixups (DSL) → verify-markers → size budget
                                                                    │
                  emitters: platform bindings (.g.dart) │ unified facade (conditional imports, stubs) │
                           native wrappers (Swift @objc / Kotlin facade) │ build glue (hook/build.dart, podspec, Gradle)
                                                                    │
                  verify: dart analyze │ compile matrix (macOS/Linux/Windows runners) │ golden tests │ lockfile check
```

Components:

1. **Config** `bindsmith.yaml` with a published JSON Schema (`# yaml-language-server: $schema=...`) and a Dart escape hatch `tool/bindsmith.dart` (the same path ffigen/jnigen took).
2. **CLI** (`args`/`CommandRunner`, `mason_logger`, `cli_completion`): `init`, `doctor`, `resolve`, `generate [--platform]`, `verify`, `diff`, `watch`, `explain <symbol>`.
3. **Drivers** — thin adapters over the official generators through their library APIs (no parsing of their output), with version pins and adapters for breaking changes.
4. **IR + passes** — one model all front-ends are reduced to; declarative fixups in the style of `translation-config.toml`/`Metadata.xml`; pull model as in CsWin32 (`include:` lists), dump-then-curate as in jextract (`bindsmith dump` → edit → `include`).
5. **Facade** — one `lib/<pkg>.dart` with conditional imports (`dart.library.ffi` / `dart.library.js_interop`), per-platform implementations, `UnsupportedError` stubs, one async mapping (`Future`/`Stream`) and error mapping.
6. **Slim-binding generator** — from the IR, emits a Swift `@objc` wrapper / Kotlin facade for what does not bridge (Swift structs, suspend/Flow, generics), plus podspec/SwiftPM/Gradle integration (the MAUI NLI pattern, automated).
7. **Dependency resolution** — Maven (already in jnigen), CocoaPods/SwiftPM (xcframework), npm (`.d.ts`), NuGet (`Win32Metadata`), pkg-config; `bindsmith.lock` with checksums for reproducibility.
8. **Verify markers** — the `[Verify]` analog: doubtful spots get `@BindsmithVerify('reason')`, and `bindsmith verify` fails until the marker is removed or acknowledged.
9. **Verification** — golden tests of generated code, a compile matrix in CI (macOS: iOS/macOS; ubuntu: Linux/Android/Web; windows), a generated-size report, `doctor` for toolchains (libclang, JDK 17–21, Android SDK, Xcode, VS Build Tools, node).

YAGNI (not doing): own runtime/dynamic dispatch; own C++ parser (`extern "C"` shim + slim wrapper instead); macro support; GUI; mandatory AI dependency; own Dart formatter/analyzer.

---

## 9. Why bindsmith will beat what exists

1. **One declaration → 6 platforms + a unified facade.** Today only flutter_rust_bridge does this, and only for Rust input.
2. **Web parity.** `.d.ts` → `dart:js_interop` — no public tool since 2022; the pigeon Web issue has been open for 4 years.
3. **Pull model + declarative fixups + verify markers** — a synthesis of CsWin32, objc2, Sharpie; no Dart tool has any of it.
4. **Slim binding as a generated artifact**, not manual advice from MAUI docs.
5. **Dependencies and a lockfile** — generation reproducible on CI without "build Android first".
6. **Resilience to upstream** — pinned ffigen/jnigen/swiftgen, adapters, migration diffs (`bindsmith diff` shows what changed after a generator bump, including overload renumbering `new$2 → new$12`).
7. **Docs and availability carried over** (`@available`/`@RequiresApi` → dartdoc + runtime checks).
8. **Size budget** — a report of how many lines/symbols were generated per platform and what can be excluded.

---

## 10. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Upstream breaking changes (ffigen 22 — rewritten API; jnigen 1.0; swiftgen 0.x) | high | version pins in drivers, contract tests on generator APIs, adapters |
| swiftgen/swift2objc are experimental | high | slim-binding fallback: we generate the `@objc` wrapper ourselves |
| `.d.ts` → Dart: structural types, overloads, generics | medium | limited subset + verify markers; track `js_interop_gen` |
| Heavy toolchain (libclang, JDK, Android SDK, Xcode, VS) | high | `doctor`, CI containers, artifact cache |
| Six platforms on one team | high | phasing: C/ObjC/JVM first, then Swift/Web, then winmd/gir |
| Macros, C++ | medium | documented "no"; shim generator |

---

## 11. Fact-check log (what was refuted or corrected)

| # | Original claim | Outcome |
|---|---|---|
| 1 | jni 1.0.0 | jni 1.0.3 (2026-07-30); jnigen 1.0.0 (2026-09-03) |
| 2 | swift2objc not on pub.dev | it is: 0.3.0; swiftgen 0.2.0 (both 2026-09-08) |
| 3 | web_generator on pub.dev, supports `.d.ts` | internal dart-lang/web tool, WebIDL only; `.d.ts` is the separate unpublished `js_interop_gen` |
| 4 | flutter_rust_bridge 1.8.2 | 2.13.0 (2026-08-23), 2.14.0-beta.1 |
| 5 | uniffi 0.31.0 (January 2026) | 0.32.0 (2026-06-30) |
| 6 | windows-bindgen 0.66 (May 2026) with `--minimal` | 0.66 — January 2026; current 0.100.0; `--minimal` unconfirmed |
| 7 | NativeScript switched iOS to V8 in 9.0 (2025) | in 7.0 (2020) |
| 8 | metadata filtering via `.mdg` | `native-api-usage.json` |
| 9 | NativeScript overhead 1.5–2× | ≈3.5× by its own benchmark |
| 10 | dart_native maintained | last release December 2022 |
| 11 | Objective Sharpie is a closed utility | dotnet global tool `Sharpie.Bind.Tool`, sources not public |
| 12 | Djinni maintained, has Dart | release 1.4.1 (2023), C++/Java/ObjC only |
| 13 | template `plugin_ffi` | deprecated, current is `package_ffi` (Flutter 3.38) |
| 14 | `dart compile exe` cross-compiles | Linux targets only |
| 15 | YAML is the standard config for ffigen/jnigen | Dart scripts; YAML legacy |
| 16 | native assets stable in "Flutter 3.38 (September 2024)" | 3.38 = November 2025; build hooks on by default in 3.38 |
| 17 | Roslyn generator rgen in development | RFC #21308 open, no work |
| 18 | jnigen's Maven support is reusable through its library API | `GradleTools` writes a stub Gradle project and shells out to `gradlew`; no resolver API, no checksums |

Unverified `[~]`: Kotlin Swift export on 2.4.x; Nitro status after the repository move; D7 data on Sentry/Nutrient/Mapbox; jextract `--dump-includes` (a known flag, primary source not opened); Terra in the Agora Flutter SDK.

---

## 12. Sources (primary sources opened by the fact-check)

- pub.dev API: ffigen, objective_c, swift2objc, swiftgen, jnigen, jni, pigeon, win32, winmd, dbus, hooks, code_assets, native_toolchain_c, native_toolchain_cmake, web, flutter_rust_bridge, dart_native, args, cli_completion, mason_logger, code_builder, dart_style, analyzer, build_runner, melos and others.
- dart-lang/native (README/CHANGELOG ffigen, jnigen, swiftgen, swift2objc); dart.dev/interop/*; dart.dev/tools/hooks; dart.dev/tools/dart-compile; dart.dev/tools/pub/workspaces
- docs.flutter.dev: developing-packages (package_ffi), release notes 3.35/3.38, breaking-changes (merged threads)
- dart-lang/web (web_generator README/package.json, PR #549, #554); dart-lang/http (cupertino_http ffigen.yaml, ok_http jnigen.yaml)
- halildurmus/win32 (packages/generator); canonical/dbus.dart; llamadonica/dart-gobject-bindings
- learn.microsoft.com: Objective Sharpie get-started / verify; AndroidMavenLibrary; CallConvSwift; MAUI Native Library Interop; dotnet/macios#21308; dotnet/runtimelab SwiftBindings (#2518)
- mono/CppSharp releases; NuGet ClangSharpPInvokeGenerator, Microsoft.Windows.CsWin32; microsoft/win32metadata
- docs.nativescript.org (metadata, generate-typings); blog.nativescript.org (V8 beta 2020; perf-metrics part 1); NativeScript/ios-metadata-generator, android-metadata-generator; npm @nativescript/*
- crates.io: uniffi, windows-bindgen, objc2; Uniffi-Dart/uniffi-dart; heremaps/gluecodium; cross-language-cpp/djinni-generator; swig.org/compat.html; bytecodealliance/wit-bindgen; madsmtm/objc2 header-translator README
- JetBrains/kotlin releases; touchlab/skie; npm karakum; swiftlang/swift-java; openjdk/jextract; AgoraIO-Extensions/terra; npm react-native
- roszkowski.dev/2026/swiftgen-jnigen/ (May 18, 2026); flutter/flutter#98084
