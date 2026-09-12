# Fact-Check Report: Dart/Flutter Binding Tools

## C1. swiftgen on pub.dev

**VERDICT: CONFIRMED (with minor clarification)**

- **Latest version**: 0.2.0
- **Published**: 2026-09-08T00:33:15.997052Z (today)
- **Publisher**: dart-lang (dart-lang/native pkgs/swiftgen)
- **What it does**: Generates Dart bindings for Swift libraries via swift2objc → ffigen orchestration
- **README status**: "An experimental tool for generating bindings that allow interop between Dart and Swift code."
- **Config form**: Dart script with `SwiftGenerator` class (not YAML). See swiftgen/lib/src/config.dart.
- **README example**: The README on GitHub is only 4 lines (minimal documentation at this stage).

Config structure (from pubspec.yaml dependencies):
- Orchestrates: swift2objc (^0.3.0), ffigen (^22.0.0), objective_c (^9.6.0)
- Configuration is a Dart `SwiftGenerator` class with fields: `target`, `inputs`, `include`, `output`, `ffigen`
- Output includes: Dart bindings file + Objective-C bindings file

**Quote from config.dart**: "Dart's interop with Swift is built on Objective-C interop. Swift APIs can be accessed through Objective-C, and Dart can access Objective-C using FFIgen. Swift -> Objective-C -> Dart"

---

## C2. swift2objc on pub.dev

**VERDICT: CONFIRMED**

- **Latest version**: 0.3.0
- **Published**: 2026-09-08T00:27:15.147622Z
- **Publisher**: dart-lang (dart-lang/native pkgs/swift2objc)
- **Relationship**: Direct dependency of swiftgen (swiftgen depends on swift2objc ^0.3.0)
- **What it does**: Generates Objective-C bindings from Swift code

---

## C3. dart_native (pub.dev) and dart-native/codegen (GitHub)

**VERDICT: CONFIRMED but OUTDATED**

- **dart_native pub.dev**: Version 0.7.11, published 2022-12-27 (last release over 3 years ago)
- **dart_native GitHub**: Updated 2026-09-08T02:20:47Z (recently active)
- **dart-native/codegen GitHub**: 
  - Last commit: 2026-08-24T02:55:23Z
  - Not archived (archived: false)
  - Description: "Generator for dart_native bindings. Codegen can transform native SDK to Flutter plugin."
  - README: 404 (repo has no README)
- **Relationship**: dart_native pub package is unmaintained since 2022; codegen repo is separate and recent

**Status**: dart_native is effectively unmaintained on pub.dev (no release since Dec 2022); codegen repo appears active but undocumented.

---

## C4. Dart CLI Building Blocks

**VERDICT: ALL CONFIRMED (maintained, recent versions)**

| Package | Latest Version | Published | Notes |
|---------|---|---|---|
| args | 2.7.0 | 2025-03-12 | dart-lang/core |
| cli_completion | 0.6.0 | 2026-08-10 | VeryGoodOpenSource |
| mason_logger | 0.3.5 | 2026-03-20 | Active |
| cli_util | 0.6.0 | 2026-08-21 | Active |
| code_builder | 4.12.0 | 2026-08-28 | Active |
| dart_style | 3.1.13 | 2026-08-26 | Active |
| analyzer | 14.3.0 | 2026-09-01 | Recent |
| build_runner | 2.16.1 | 2026-09-02 | Recent |
| source_gen | 4.3.0 | 2026-08-19 | Active |
| yaml | 3.1.4 | 2026-08-28 | Active |
| checked_yaml | 2.0.4 | 2025-06-05 | Maintained |
| json_schema | 5.2.2 | 2025-10-08 | Active |
| file | 7.0.1 | 2024-10-08 | Older release |
| process | 5.0.6 | 2026-08-28 | Active |
| glob | 2.2.0 | 2026-08-28 | Active |
| archive | 4.2.0 | 2026-08-22 | Active |
| pub_semver | 2.2.1 | 2026-08-28 | Active |
| pubspec_parse | 1.6.0 | 2026-08-28 | Active |
| native_toolchain_c | 0.19.4 | 2026-08-18 | Active |
| native_toolchain_cmake | 0.3.2 | 2026-08-19 | EXISTS - Active |
| hooks | 2.2.0 | 2026-08-18 | Active |
| code_assets | 2.0.0 | 2026-08-18 | Active |
| mason | 0.1.2 | 2025-11-25 | Maintained |
| melos | 8.6.0 | 2026-08-29 | Recently updated |

---

## C5. dart compile exe Cross-Compilation

**VERDICT: CONFIRMED with LIMITATION**

From dart.dev documentation (dart-compile.md):

- **Flags supported**: `--target-os` and `--target-arch`
- **Current limitation**: Only `--target-os=linux` is supported
- **Target architectures** (for Linux): arm, arm64, riscv64, x64
- **Quote from docs**: "`--target-os=linux` - The target operating system for the compiled executable. Only the Linux operating system is supported at this time."
- **Which Dart version**: Not found in this research; CHANGELOG mentions "support for cross-compilation to `dart build cli` command via `--target-os` and `--target-arch`" but version unclear

**Finding**: Cross-compilation flags exist but are limited to Linux targets only, not Windows/macOS.

---

## C6. Pub Workspaces Stability

**VERDICT: CONFIRMED**

From dart.dev/tools/pub/workspaces documentation:

- **Stable since**: SDK constraint specifies `^3.6.0`
- **Workspace feature**: Requires SDK `^3.6.0` in workspace packages
- **Date**: Dart 3.6 was released in December 2024 (aligns with claim)
- **Config**: Root `pubspec.yaml` has `workspace:` entry listing package paths; child packages need `resolution: workspace`
- **build_runner workspace support**: Not verified in this research (changelog search inconclusive)

---

## C7. Name Availability on pub.dev and GitHub

**VERDICT: MIXED RESULTS**

### pub.dev Availability (HTTP API endpoint check):

| Name | pub.dev Status | Notes |
|------|---|---|
| bindgen | 404 - Available | Not published |
| flutter_bindgen | 404 - Available | Not published |
| dart_bindgen | 404 - Available | Not published |
| unibind | 404 - Available | Not published |
| omnibind | 404 - Available | Not published |
| nativegen | 404 - Available | Not published |
| bridgen | 404 - Available | Not published |
| bindkit | 404 - Available | Not published |
| xbind | 404 - Available | Not published |
| polybind | 404 - Available | Not published |
| fbind | 404 - Available | Not published |
| dartbind | (not checked, budget limit) | - |

### GitHub Collisions Found:

**flutter_bindgen**: 2 results (none exact match)
- trdthg/flutter_rust_bindgen_book_zh (2026-01-16)
- dev-cetera/df_wasm_interop (2026-06-01)

**dart_bindgen**: 5 results (including active repos)
- dart-bindgen (2026-03-05) - **Recently updated**
- dart-bindgen (2023-10-11)
- dart-bindgen (2023-10-03)
- uniffi-bindgen-dart (2026-06-13)
- bindgen-bootstrap (2019-12-10)

**unibind**: 14 results (multiple repos with "Bind" theme)
- UniBind (multiple recent updates 2026)
- Unibind (2026-05-25)
- UniBinder (2021-10-26)
- ClassicBinds (2024-05-19)

---

## C8. roszkowski.dev Blog Post on swiftgen/jnigen

**VERDICT: CONFIRMED - POST EXISTS**

**URL**: https://roszkowski.dev/2026/swiftgen-jnigen/

**Title**: "jnigen and swiftgen in 2026 - some lessons learned"

**Published**: May 18, 2026

**Key Practical Lessons/Pain Points**:

1. **Migration Complexity**: jni 1.0.0 breaking changes require regenerating bindings; config moved from YAML to Dart scripts (tool/jnigen.dart, tool/swiftgen.dart); constructor overrides changed (e.g., Intent.new$2 → Intent.new$12)

2. **Callbacks Are Cumbersome**: Android uses Kotlin interfaces with `implement()` pattern; iOS uses @objc protocol with `$Builder.implementAsListener(...)`; essential to keep Dart-side callback reference to prevent garbage collection breaking silent callbacks

3. **Memory Management Differences**: Android requires explicit `.release()` for JNI global refs; iOS uses automatic reference counting (ARC) via ObjC runtime; fundamentally different mental models per platform

4. **Generated File Locations Matter**: Both Dart bindings and native ObjC files must be committed; .m file must be in podspec's Classes/** coverage; swiftgen produces both .g.dart + .m files that are co-dependent

5. **Type Restrictions on iOS**: Swift structs/generics cannot bridge to ObjC; only NSObject-compatible types work; jnigen accepts any JNI-compatible Java/Kotlin type, but swiftgen enforces ObjC compatibility limits

**Quote from article** (on setup effort): "The setup experience requires some effort, but once you have the bindings ready, it's pretty smooth sailing."

---

## C9. flutter create --template=plugin_ffi

**VERDICT: CONFIRMED (but DEPRECATED)**

From Flutter tools source (create.dart):

- **Template name**: `plugin_ffi` (exists)
- **Status**: **DEPRECATED** - Warning: "The 'plugin_ffi' template is deprecated and will be removed in a future version of Flutter. Use the 'package_ffi' template instead."
- **Generation**: Template generates FFI plugin structure
- **Limitations**: Web platform not supported in plugin_ffi template

**File list**: Not found in this research (Flutter docs excerpt timeout); template generates standard plugin FFI structure with native code directories.

**Note**: Flutter now recommends `package_ffi` template instead of `plugin_ffi`.

---

## C10. package:web_generator

**VERDICT: REFUTED - NOT ON PUB.DEV**

- **pub.dev status**: 404 - Package does not exist
- **Alternative location**: Internal tooling in dart-lang/web repository
- **dart-lang/web README**: States "web_generator | Internal tooling to generate the `web` package bindings. | N/A | (CI badge)"
- **Status**: Not published as public package; internal-only tool within dart-lang/web project

---

# Summary Table

| Claim | Verdict | Key Fact |
|-------|---------|----------|
| C1 | CONFIRMED | swiftgen 0.2.0 (2026-09-08), experimental, uses SwiftGenerator Dart class |
| C2 | CONFIRMED | swift2objc 0.3.0 (2026-09-08), dependency of swiftgen |
| C3 | PARTIALLY | dart_native 0.7.11 unmaintained (2022); dart-native/codegen active (2026-08-24) |
| C4 | CONFIRMED | All CLI tools exist with recent versions (2026) |
| C5 | PARTIALLY | --target-os/--target-arch exist but limited to Linux targets only |
| C6 | CONFIRMED | Workspaces stable in Dart 3.6.0 (Dec 2024) |
| C7 | CONFIRMED | All tested names available on pub.dev; GitHub collisions exist (dart-bindgen, UniBind) |
| C8 | CONFIRMED | Blog post exists, URL: https://roszkowski.dev/2026/swiftgen-jnigen/ |
| C9 | PARTIALLY | plugin_ffi template exists but DEPRECATED; flutter recommends package_ffi |
| C10 | REFUTED | web_generator NOT on pub.dev; internal tool only in dart-lang/web repo |
