# Dart Building Blocks & Prior Art: Unified Binding Generator Research
**Date:** 2026-09-08  
**Budget Used:** ~42 of 45 lookups

---

## Executive Summary

- **Prior Art:** One partial orchestrator found (dart-native `codegen`); no unified multi-platform binding generator from single config exists yet.
- **Individual generators:** ffigen (C/Obj-C/Swift, v22.0.0, 15h old), jnigen (Java/Kotlin, v1.0.0, 4d old), swiftgen (Swift→ObjC, unstable 2026), pigeon (platform channels), flutter_rust_bridge (Rust specialty).
- **Config trend:** YAML-based (`build.yaml`) remains standard; Dart script configs (tool/swiftgen.dart) are emerging but not dominant.
- **CLI framework:** args + cli_completion (VGV) + mason_logger; `dart pub global activate` + homebrew tap distribution patterns.
- **Code generation:** code_builder v4.12.0 (10d old) + source_gen + build_runner v2.16.1 (6d old); workspace support experimental.
- **Names available:** All 12 checked names free on pub.dev (bindgen, flutter_bindgen, dart_bindgen, unibind, omnibind, nativegen, dartbind, fbind, bridgen, polybind, allbind, xbind, bindkit).
- **Biggest gap:** No tool orchestrates ffigen + jnigen + swiftgen + pigeon from one YAML or Dart config; each platform has separate build loops.

---

## (A) PRIOR ART — Unified Binding Generators

### Summary Table

| Tool | Platforms | Status | Config | Single Entry? | Notes |
|------|-----------|--------|--------|---------------|-------|
| **dart-native codegen** | Obj-C, Java/Kotlin (auto) | Active, npm + GitHub | CLI flags | ✓ YES (partial) | _Transform native SDK to Flutter plugin;_ best existing fit but limited scope |
| **ffigen** | C/C++/Obj-C/Swift | Maintained (v22.0.0, 15h ago) | build.yaml / Dart script | — | Part of dart-lang/native; single-platform focus |
| **jnigen** | Java/Kotlin | Maintained (v1.0.0, 4d ago) | build.yaml | — | Part of dart-lang/native; Android only |
| **swiftgen** | Swift | Unstable (2026) | build.yaml or Dart script (tool/) | — | Via swift2objc + ffigen; recommended config: Dart script |
| **pigeon** | Platform channels (Android, iOS, web, C++) | Official Flutter | Dart (.dart files) | — | Type-safe channel codegen; not a native binding generator |
| **flutter_rust_bridge** | Rust (multi-platform binary output) | Active (v1.8.2) | build.yaml | — | Rust specialty; handles async, memory, streams |
| **uniffi-bindgen-dart** | Rust (via UniFFI) | Active | N/A (Rust-side FFI defs) | — | Rust ecosystem tool; Dart backend |
| **dart_bindgen** (sunshine-protocol or pingbird) | C headers | Community tools | N/A | — | Rust-based CLI; not Dart CLI |

### Key Insight
No tool generates Dart+Swift+Kotlin+C bindings from ONE config definition. Each language has its own generator; users manually coordinate:
- Run `ffigen` for C → Dart
- Run `jnigen` for Java/Kotlin → Dart
- Run `swiftgen` (via swift2objc + ffigen) for Swift → Dart
- Wire up platform channel for method calls

**Example workflow (manual today):**
```bash
# Run separately:
dart run ffigen:config         # C bindings
dart run jnigen:config         # Kotlin bindings
dart run swiftgen              # Swift bindings
```

### Closest Existing Orchestrator
**dart-native/codegen** (GitHub, npm package)
- Generates Flutter plugin from native SDK
- Supports Obj-C (iOS) and Java/Kotlin (Android) with auto-detection
- CLI: `dart_native_codegen -l auto -o lib/src/generated` (or `-l objc`/`-l java`)
- **Limitation:** Does not handle C++ FFI, not a general-purpose orchestrator for mixed codebases

---

## (B) DART BUILDING BLOCKS

### (B1) CLI Framework

| Package | Version | Date | Maintainer | Use Case | Notes |
|---------|---------|------|-----------|----------|-------|
| **args** | (stdlib-adjacent) | — | dart-lang | ArgParser, CommandRunner | GNU/POSIX option parsing; `--flag`, `-f`, subcommands |
| **cli_completion** | latest | 2026 | Very Good Ventures | Shell completion | Works bash/zsh, Linux/macOS/Windows; depends on `args` + `mason_logger` |
| **mason_logger** | 0.3.5 | 5mo ago | brickhub.dev | Progress bars, prompts, spinners | Used by Mason CLI; colorized output, choice menus, confirmations |
| **interact** | — | — | — | Interactive prompts | Alternative to mason_logger; simpler |
| **io** | (dart:io-adjacent) | — | dart-lang | File I/O stdlib | Native Dart package; no extra dependency |

**Distribution Patterns:**
- **pub global:** `dart pub global activate <package>` installs to ~/.pub-cache; users add to PATH
- **homebrew tap:** `brew tap dart-lang/dart` (official Dart tap exists); common pattern for CLI tools (very_good_cli, melos, fvm)
- **GitHub Releases:** Direct binary distribution; users curl/unzip; less friction than homebrew
- **Workaround:** `dart compile exe` for standalone binaries (added Dart 3.x; supports `--target-os` for cross-compilation on select platforms; macOS → Linux cross-compile is NOT supported)

**2025-2026 Trend:** pub global + homebrew tap remains dominant; GitHub Releases + binary distribution gaining traction for developer tools.

---

### (B2) Configuration

| Package | Version | Date | Maintainer | Use Case | Notes |
|---------|---------|------|-----------|----------|-------|
| **yaml** | (core) | — | dart-lang | Parse YAML | Read-only; maintained in dart-lang/sdk |
| **yaml_edit** | latest | 2026 | dart-archive | Modify YAML | Comment + whitespace preservation |
| **checked_yaml** | latest | 2026 | dart-lang | Validation + errors | Better error msgs on parse failures (for config validation) |
| **json_annotation** | (latest) | 2026 | Google | Annotations for serialization | Pairs with json_serializable for codegen |
| **json_serializable** | (latest) | 2026 | Google | JSON codegen | `@JsonSerializable()` + build_runner |
| **build_config** | — | — | dart-lang | build.yaml parser | Used by build_runner; standardizes YAML format for builders |
| **pubspec_parse** | — | — | dart-lang | pubspec.yaml parser | Read package metadata |

**Config Trend (2025-2026):**
- **YAML is standard:** build.yaml remains the config format for build_runner + ffigen + jnigen
- **Emerging: Dart scripts in tool/** → swiftgen now recommends `tool/swiftgen.dart` + `dart run tool/swiftgen.dart` instead of YAML
- **Rationale for Dart scripts:** IDE autocomplete, type safety, easier refactoring; YAML has no validation beyond schema
- **NOT dominant yet:** Most tools still use YAML; Dart script trend is gradual

**JSON Schema for IDE Autocomplete:**
- YAML Language Server supports `# yaml-language-server: $schema=<url>` header
- Tools can publish JSON schemas → better IDE UX for config validation

---

### (B3) Code Generation & Formatting

| Package | Version | Date | Maintainer | Use Case | Notes |
|---------|---------|------|-----------|----------|-------|
| **code_builder** | 4.12.0 | 10d ago | dart-lang | Fluent Dart code generation | Builds AST → formatted Dart; auto-scoping (handles nested functions, imports) |
| **dart_style** | (latest) | 2026 | dart-lang | Format Dart code | `DartFormatter` API; Dart 3.7+ "tall style" changes  |
| **analyzer** | — | — | dart-lang | Parse Dart, resolve types | Needed if tool reads user annotations or existing code |
| **source_gen** | — | — | dart-lang | Annotation-driven codegen | Wrapper over build_runner; `PartBuilder`, `LibraryBuilder` |
| **build_runner** | 2.16.1 | 6d ago | dart-lang | Build system for codegen | Supports `--workspace` flag (experimental); 2.x has speed improvements (2025) |
| **mustache_template** | — | — | Community | Template rendering | Lightweight; no dependencies |
| **jinja** | — | — | Community | Jinja-style templating | More feature-rich than mustache |
| **mason** | (bricks) | 2026 | VGV | Scaffolding templates | Embeddable bricks; plugin scaffold available via `flutter create --template=plugin_ffi` |

**Key Build.yaml Pattern:**
```yaml
targets:
  $default:
    builders:
      ffigen:
        enabled: true
        generate_for:
          - lib/src/bindings/*.h
```

---

### (B4) Native Tool Invocation & Files

| Package | Version | Date | Maintainer | Use Case | Notes |
|---------|---------|------|-----------|----------|-------|
| **process** | — | — | Google | Spawn processes, test-friendly | Pluggable via ProcessManager; easier to mock than dart:io |
| **process_run** | latest | 2026 | Community | Process helpers | Shell-like API; `which`-style executable lookup |
| **file** | — | — | Google | File I/O abstraction | MemoryFileSystem for unit tests |
| **path** | — | — | dart-lang | Path manipulation | Cross-platform; handles /\\\ on Windows |
| **glob** | latest | 2026 | dart-lang | Bash-style globbing | `Glob("**.dart").listSync()` |
| **archive** | 4.2.0 | 16d ago | Community | Zip/tar/gzip/bzip2/xz | Encode/decode; file I/O optimized |
| **native_toolchain_c** | — | — | dart-lang | Invoke C compiler | Experimental; part of dart-lang/native for build hooks |
| **native_toolchain_cmake** | — | — | dart-lang | Invoke CMake | Experimental; seeking new owner (2026) |
| **native_toolchain_rust** | — | — | dart-lang | Invoke Rust compiler | Part of native_toolchain suite |
| **http** / **dio** | — | — | — | HTTP requests | Download Maven artifacts, CocoaPods metadata, etc. |

**No Unified Maven/CocoaPods Library Yet:**
- jnigen contains custom Maven artifact download logic (not extracted to shared lib)
- CocoaPods spec resolution is manual in Swift interop
- Opportunity: Extract as reusable dart-lang/native helper

---

### (B5) Testing & CI

| Package | Version | Date | Maintainer | Use Case | Notes |
|---------|---------|------|-----------|----------|-------|
| **test** | — | — | dart-lang | Unit, widget, integration testing | Supports `--platform` flag, `@Tags('skip-on-web')` |
| **coverage** | — | — | dart-lang | Collect coverage data | `dart test --coverage=coverage` + lcov report |
| **dart_test.yaml** | — | — | — | Test config | Parallel testing, custom timeout, test selection |

**Monorepo Support (2025-2026):**
- **pub workspaces (stable in Dart 3.6+):** Experimental workspace support in build_runner 2.16.1; allows `dart run build_runner build --workspace`
- **melos:** Community tool; orchestrates scripts across packages; integrates with pub workspaces (as of 2025)
- **Status:** Pub workspaces stable, but Flutter 3.38+ + newer Dart required; Melos documentation improving but still partial

**GitHub Actions:** Standard dart test matrix with macOS + Android emulator + Windows runners (ffigen/jnigen use this pattern)

---

### (B6) Documentation & Quality

| Package | Version | Date | Maintainer | Use Case | Notes |
|---------|---------|------|-----------|----------|-------|
| **dartdoc** | — | — | dart-lang | Generate HTML docs | CLI: `dart doc .` (part of Dart SDK) |
| **pana** | 0.23.16 | 2026 | dart-lang | Package analyzer | Scores pub points; runs dartdoc coverage checks |
| **pubspec_parse** | — | — | dart-lang | Read pubspec.yaml | Extract metadata for versioning, dependencies |
| **pub_semver** | — | — | dart-lang | Semantic versioning | Version comparisons, constraints |

---

## (C) NAME AVAILABILITY

All names checked on pub.dev API (`GET https://pub.dev/api/packages/<name>`); 404 = available.

| Name | Status | Alternative Contexts |
|------|--------|----------------------|
| **bindgen** | ✅ AVAILABLE | Generic, clear; risk: too generic for discovery |
| **flutter_bindgen** | ✅ AVAILABLE | Flutter-specific; good SEO |
| **dart_bindgen** | ✅ AVAILABLE | Dart-specific; aligns with dart-native ecosystem |
| **unibind** | ✅ AVAILABLE | "Unified" + "bind"; memorable |
| **omnibind** | ✅ AVAILABLE | "Omni" + "bind"; all-platforms connotation |
| **nativegen** | ✅ AVAILABLE | Clear intent; shorter |
| **dartbind** | ✅ AVAILABLE | Compact; less discoverable |
| **fbind** | ✅ AVAILABLE | Flutter abbreviation; trendy |
| **bridgen** | ✅ AVAILABLE | "Bridge" + "gen"; descriptive |
| **polybind** | ✅ AVAILABLE | "Polymorphic bind"; sophisticated |
| **allbind** | ✅ AVAILABLE | "All platforms bind"; clear but long |
| **xbind** | ✅ AVAILABLE | Short, X = "cross"; minimal |
| **bindkit** | ✅ AVAILABLE | "Bind toolkit"; suggests completeness |

**Recommendation:** `flutter_bindgen` or `dart_bindgen` (clear, ecosystem-aligned); if tool is Dart-first, `dart_bindgen` is stronger branding.

---

## (D) SURPRISES & CORRECTIONS TO COMMON BELIEFS

1. **"There's a unified binding generator"** → FALSE. No tool orchestrates all platforms. dart-native codegen is the closest but handles only Obj-C + Java/Kotlin, not C++ FFI or web.

2. **"Dart is moving to script-based config"** → HALF-TRUE. swiftgen is experimenting with Dart scripts (tool/swiftgen.dart), but build.yaml remains dominant. No RFC for framework-wide shift.

3. **"ffigen and jnigen coordinate"** → FALSE. They are independent tools with separate build.yaml sections. No cross-tool dependency tracking; no joint config.

4. **"Swift interop is simple"** → FALSE. Requires swift2objc wrapper generator (to expose Swift APIs to Objective-C) THEN ffigen (to expose Obj-C to Dart). Two-stage pipeline.

5. **"pigeon is for native bindings"** → FALSE. Pigeon is for platform channels (async message passing). Not a native binding generator. Often confused because it also generates Swift/Kotlin code.

6. **"Dart compile exe supports cross-compilation"** → HALF-TRUE. Supports `--target-os` on some platforms, but macOS→Linux cross-compile NOT supported; simpler than Rust but limited.

7. **"maven_downloads logic is reusable"** → FALSE. jnigen has inline Maven artifact download code; not extracted to a library. Opportunity for dart-lang/native to standardize.

8. **"build_runner is mature and stable"** → TRUE, but workspace support is experimental (2026); full support expected later.

---

## (E) OPEN QUESTIONS UNVERIFIED

1. **Do ffigen + jnigen + swiftgen share any internal IR?** → No evidence found; likely each has own AST. Orchestrating would require translation layer.

2. **Is there a CocoaPods / Swift Package Manager abstraction in Dart?** → Not found. Plugins handle SwiftPM manually (e.g., cupertino_http). Opportunity for dart-lang/native.

3. **What's the exact breakdown of how dart-native/codegen transforms native SDK to Flutter plugin?** → GitHub README is sparse; likely uses AST parsing per language, generates FFI/JNI glue, plus Dart method stubs.

4. **Do any plugins use AI (LLM) to auto-generate bindings?** → No specific tools found in 2025-2026 ecosystem. LLMs used *manually* by developers (as noted in Flutter blog), but no framework-integrated AI codegen tool.

5. **What's the adoption rate of Dart script configs (tool/build.dart) vs. YAML?** → No statistics found. Anecdotal evidence suggests swiftgen promoting Dart scripts, but no framework-level adoption.

6. **Is Melos the de facto standard for Dart monorepos, or is pub workspaces replacing it?** → Both used in 2025-2026; Melos still necessary for script orchestration and versioning. Workspaces handle dependency resolution; Melos adds lifecycle management.

---

## RECOMMENDATIONS FOR YOUR UNIFIED BINDING GENERATOR

1. **Start with Dart CLI:** Use args + cli_completion + mason_logger. Shell completion is important for dev ergonomics.

2. **Config: YAML or Dart script?**
   - Use **build.yaml** for ecosystem familiarity (ffigen/jnigen template).
   - Offer optional **Dart script override** (tool/bindgen.dart) for advanced users → future-proof as ecosystem shifts.
   - Provide JSON Schema + YAML LS support for IDE validation.

3. **Orchestration pattern:**
   - Single entry config (YAML) listing all platforms + target languages.
   - Internally spawn `ffigen`, `jnigen`, `swiftgen` as subprocesses or library calls (if they're published as Dart libraries—currently mostly CLI).
   - Coordinate build.yaml injection/merging so users don't manually configure each tool.

4. **Reuse existing generators:**
   - Don't rewrite ffigen/jnigen/swiftgen.
   - Wrap them via library APIs (if available) or shell subprocess invocation.
   - Add orchestration value: single config, unified error reporting, progress tracking, test scaffold generation.

5. **Distribution:**
   - Use `dart pub global activate <your_package>` as primary mechanism.
   - Homebrew tap is nice-to-have (use dart-lang/homebrew-dart as model).
   - GitHub releases + direct binary distribution (via `dart compile exe`) is lower-friction alternative.

6. **Testing:**
   - Golden tests for generated code (per platform).
   - Integration tests with real .h/.java/.swift files (small test fixtures).
   - CI matrix: macOS (ffigen + swiftgen), Linux (ffigen + jnigen), Windows (ffigen).

7. **Names:** `dart_bindgen` (if Dart-focused ecosystem play) or `flutter_bindgen` (if Flutter-specific marketing). Both available.

---

## SOURCES

- [Flutter's path towards seamless interop](https://flutter.dev/blog/flutters-path-towards-seamless-interop)
- [dart-lang/native GitHub](https://github.com/dart-lang/native)
- [ffigen pub.dev](https://pub.dev/packages/ffigen)
- [jnigen pub.dev](https://pub.dev/packages/jnigen)
- [swiftgen pub.dev](https://pub.dev/packages/swiftgen)
- [pigeon docs](https://docs.flutter.dev/platform-integration/platform-channels)
- [flutter_rust_bridge GitHub](https://github.com/fzyzcjy/flutter_rust_bridge)
- [dart-native/codegen GitHub](https://github.com/dart-native/codegen)
- [code_builder pub.dev](https://pub.dev/packages/code_builder)
- [build_runner pub.dev](https://pub.dev/packages/build_runner)
- [cli_completion pub.dev](https://pub.dev/packages/cli_completion)
- [mason_logger pub.dev](https://pub.dev/packages/mason_logger)
- [archive pub.dev](https://pub.dev/packages/archive)
- [Dart pub workspaces](https://dart.dev/tools/pub/workspaces)
- [Melos docs](https://melos.invertase.dev/)
- [jnigen and swiftgen in 2026 lessons learned](https://roszkowski.dev/2026/swiftgen-jnigen/)
- [Dart testing](https://dart.dev/tools/testing)
- [pana pub.dev](https://pub.dev/packages/pana)
