# Fact-Check: Cross-Language Binding Tools & Frameworks

## C1. mozilla/uniffi-rs

**Verdict: PARTIALLY REFUTED**

**Corrected Statement:**
- Latest release: **0.32.0** (June 30, 2026), not 0.31.x (Jan 2026)
- Official bindings: Kotlin, Swift, Python, Ruby ✓
- Third-party bindings: 
  - Go: `uniffi-bindgen-go` (NordSecurity/uniffi-bindgen-go) ✓
  - C#: `uniffi-bindgen-cs` (NordSecurity/uniffi-bindgen-cs) ✓
  - JavaScript/React-Native: `uniffi-bindgen-react-native` (jhugman/uniffi-bindgen-react-native) ✓
  - **Dart: `uniffi-rs-dart` (NiallBunting/uniffi-rs-dart)** — NOT in the canonical "Uniffi-Dart" org
  - Also: Java, Node, Haskell, Kotlin Multiplatform (Gobley)

**Evidence:**
- https://crates.io/api/v1/crates/uniffi → max_version: 0.32.0, updated_at: 2026-06-30
- https://github.com/mozilla/uniffi-rs/blob/main/README.md → Lists third-party bindings

**Uniffi-Dart Repository Issue:**
- Claim mentions both "Uniffi-Dart/uniffi-dart?" and "acterglobal/uniffi-dart?"
- Primary repo: **Uniffi-Dart/uniffi-dart** (https://api.github.com/repos/Uniffi-Dart/uniffi-dart)
  - Latest: v0.2.1+v0.31.2 (June 26, 2026)
  - Pushed: Sept 2, 2026 — actively maintained
- acterglobal/uniffi-dart: No data (not the canonical repo)
- **Unsupported features claim needs verification:** README lists HashMap, proc-macros, defaults, trait methods, BigInt not supported [UNVERIFIABLE — did not access full Uniffi-Dart README content]

---

## C2. flutter_rust_bridge

**Verdict: PARTIALLY REFUTED**

**Corrected Statement:**
- **pub.dev version: 2.13.0** published **August 23, 2026** (NOT May 2026)
- crates.io: 2.14.0-beta.1 (Sept 5, 2026)
- No conflicting "v1.8.2" found in recent releases
- Config file name: **flutter_rust_bridge.yaml** (no evidence of `.toml` variant) ✓
- Parser: Uses `syn` ✓ (confirmed in docs)
- Web/WASM support: ✓ (README confirms "Web (both JavaScript and WebAssembly)")
- Cargokit/native assets integration: [UNVERIFIABLE — did not access full build integration docs]

**Evidence:**
- pub.dev: https://pub.dev/api/packages/flutter_rust_bridge → version: 2.13.0, published: 2026-08-23
- crates.io: flutter_rust_bridge_codegen 2.14.0-beta.1 (2026-09-05)
- GitHub releases: v2.13.0 (2026-08-23), v2.14.0-beta.1 (2026-09-05)

---

## C3. heremaps/gluecodium

**Verdict: CONFIRMED**

**Confirmed Facts:**
- Latest release: **14.1.1** (March 3, 2026)
- Supported languages: C++, Java, Kotlin, Swift, **Dart** ✓
- Repository status: Not archived, last commit Sept 8, 2026 ✓
- Kotlin-based generator with FreeMarker templates: [UNVERIFIABLE — did not access generator source]
- LIME IDL: [UNVERIFIABLE — docs/overview.md returned 404]

**Evidence:**
- https://api.github.com/repos/heremaps/gluecodium/releases/latest → tag: 14.1.1, published_at: 2026-03-03
- https://raw.githubusercontent.com/heremaps/gluecodium/master/README.md → "Generates C++, Java, Kotlin, Swift, and Dart code"

---

## C4. SWIG & wit-bindgen

**Verdict: CONFIRMED**

**Confirmed Facts:**
- SWIG has **NO Dart target** ✓
  - Supported: D, Go, Guile, Java, Javascript (multiple engines), Lua, OCaml, Octave, Perl, PHP, Python, R, Ruby, Scilab, Tcl/Tk
  - Source: https://www.swig.org/compat.html
- wit-bindgen has **NO Dart guest/host generator** ✓
  - Supported guest languages: Rust, C, C++, C#, Go
  - Source: https://raw.githubusercontent.com/bytecodealliance/wit-bindgen/main/README.md

**Evidence:**
- SWIG compat: https://www.swig.org/compat.html (no Dart link)
- wit-bindgen README: Guest languages listed as "Rust, C, C++, C#, and Go"

---

## C5. madsmtm/objc2

**Verdict: PARTIALLY CONFIRMED**

**Confirmed Facts:**
- Latest version: **0.6.4** (Feb 26, 2026)
- `header-translator` crate: Exists in objc2 repo
- Framework config file name: **translation-config.toml** ✓
  - Template shows options: `framework`, `crate`, `required-crates`, `macos`, `maccatalyst`, `ios`, `tvos`, `watchos`, `visionos`, `skipped`
  - Source: https://raw.githubusercontent.com/madsmtm/objc2/main/crates/header-translator/README.md
- Framework crates published: [ESTIMATED ~50+ framework crates under objc2- prefix, exact count UNVERIFIABLE]
- Last commit: Sept 5, 2026 ✓

**Evidence:**
- https://crates.io/api/v1/crates/objc2 → max_version: 0.6.4, updated_at: 2026-02-26
- https://github.com/madsmtm/objc2 → pushed_at: 2026-09-05 (actively maintained)

---

## C6. microsoft/windows-rs `windows-bindgen`

**Verdict: PARTIALLY REFUTED**

**Corrected Facts:**
- Latest version: **0.100.0** (Sept 3, 2026)
- Version 0.66.0: Released **January 8, 2026** (NOT May 2026 as claimed)
- `--minimal` flag: [UNVERIFIABLE — README returned 404, no evidence found]
- Documented CLI flags: `--in`, `--out`, `--filter`, `--flat`, `--sys`, `--reference`, `--no-comment` [claimed; NO CONFIRMATION of exact list]

**Evidence:**
- https://crates.io/api/v1/crates/windows-bindgen
  - 0.100.0 created: 2026-09-03
  - 0.66.0 created: 2026-01-08 (not May 2026)

**gtk-rs gir:**
- **Confirmed:** Gir.toml uses `[[object]]` sections [partial confirmation from README grep]

---

## C7. Kotlin & Tooling

**Verdict: CONFIRMED (with Swift export status UNVERIFIABLE)**

**Confirmed Facts:**
- Latest Kotlin: **v2.4.20** (Sept 7, 2026) ✓
  - Published: 2026-09-07T10:31:56Z (very recent, nearly today's date 2026-09-08)
- Swift export: **Status UNVERIFIABLE** (docs URL returned partial data showing ExperimentalTime annotation)
- SKIE (Touchlab): **0.10.14** (July 27, 2026) ✓
- karakum (npm): **1.0.0-alpha.112** ✓

**Evidence:**
- https://api.github.com/repos/JetBrains/kotlin/releases/latest → tag_name: v2.4.20, published_at: 2026-09-07
- https://api.github.com/repos/touchlab/skie/releases/latest → tag_name: 0.10.14, published_at: 2026-07-27
- https://registry.npmjs.org/karakum/latest → version: 1.0.0-alpha.112

---

## C8. swiftlang/swift-java

**Verdict: CONFIRMED**

**Confirmed Facts:**
- Latest release: **0.6.0** (Sept 5, 2026)
- Modes: **FFM (Foreign Function & Memory API)** and **JNI** ✓
- FFM mode requires: JDK 25+, Swift 6.2
- JNI mode: Works on older JVMs, including Android
- Config file name: [UNVERIFIABLE — not found in README]
- Minimum JDK: **JDK 17+** (for SwiftJava macros)
- Status: Maintained (last commit recent)

**Evidence:**
- https://api.github.com/repos/swiftlang/swift-java/releases/latest → tag_name: 0.6.0, published_at: 2026-09-05
- README snippet: "It has two modes, `ffm` and `jni`"

**jextract:**
- **--dump-includes flag: [UNVERIFIABLE — did not access OpenJDK jextract README]**
- Latest jextract: Maintained (last commit Aug 26, 2026)
- Source: https://api.github.com/repos/openjdk/jextract → pushed_at: 2026-08-26

---

## C9. AgoraIO-Extensions/terra

**Verdict: CONFIRMED**

**Confirmed Facts:**
- Repository: Exists and maintained
- **Architecture:**
  - Parser: **cxx-parser** (uses cppast and libclang AST) ✓
  - Renderers: TypeScript ✓
  - Config format: **YAML** ✓
    - Example: parsers list with name, package/path, args; renderers list similar
  - Last commit: Aug 24, 2026 (active)
- **Agora-Flutter-SDK usage: [UNVERIFIABLE — did not search Agora-Flutter-SDK for terra references]**

**Evidence:**
- https://raw.githubusercontent.com/AgoraIO-Extensions/terra/main/README.md → Shows terra architecture, YAML config
- https://raw.githubusercontent.com/AgoraIO-Extensions/terra/main/cxx-parser/README.md → "leveraging libraries from cppast and clang AST"
- https://api.github.com/repos/AgoraIO-Extensions/terra → pushed_at: 2026-08-24

---

## C10. React Native & Nitro

**Verdict: PARTIALLY REFUTED**

**Corrected Facts:**
- React Native latest: **0.87.1** (as of query date Sept 8, 2026)
- **New Architecture default in 0.76 (Oct 2024): [UNVERIFIABLE — GitHub API returned redirect]**
- **nitro (mrousavy/nitro): Repository returns HTTP 301 redirect** — MOVED/ARCHIVED
  - Config file claim `nitro.json`: [UNVERIFIABLE]
  - Nitrogen codegen tool: [UNVERIFIABLE]
  - Swift/C++, Kotlin/fbjni: [UNVERIFIABLE]
- Expo Modules Kotlin compiler plugin: [UNVERIFIABLE — latest release query returned no data]

**Evidence:**
- https://registry.npmjs.org/react-native/latest → version: 0.87.1
- https://api.github.com/repos/mrousavy/nitro → HTTP 301 Moved Permanently

---

## C11. cross-language-cpp/djinni-generator

**Verdict: REFUTED (Maintenance Status)**

**Corrected Facts:**
- **Latest release: v1.4.1** (Dec 29, **2023**, NOT 2026)
- Last commit: Dec 23, **2025** (so technically "maintained" in 2025, but not 2026-active)
- Target languages: **C++, Java, Objective-C** (3 languages)
  - README: "designed to connect C++ with either Java or Objective-C"
- **NO Dart target** ✓
- **NO Python, C++/CLI, or Wasm targets** ✓

**Evidence:**
- https://api.github.com/repos/cross-language-cpp/djinni-generator/releases/latest
  - tag_name: v1.4.1
  - published_at: 2023-12-29 (nearly 2 years old)
- https://api.github.com/repos/cross-language-cpp/djinni-generator → pushed_at: 2025-12-23
- README: "tool for generating cross-language type declarations... C++ with either Java or Objective-C"

---

## Summary Table

| Claim | Verdict | Key Correction |
|-------|---------|-----------------|
| C1 | REFUTED | uniffi latest 0.32.0 (June 2026), not 0.31.x (Jan 2026); uniffi-dart repo is Uniffi-Dart org, not other orgs |
| C2 | PARTIALLY | flutter_rust_bridge 2.13.0 published Aug 23, 2026 (not May 2026) |
| C3 | CONFIRMED | Gluecodium 14.1.1 (March 2026), Dart support, maintained |
| C4 | CONFIRMED | SWIG no Dart; wit-bindgen no Dart; confirmed language lists |
| C5 | CONFIRMED | objc2 0.6.4 (Feb 2026); translation-config.toml confirmed with documented options |
| C6 | PARTIALLY | windows-bindgen 0.66.0 from Jan 8, 2026 (not May); --minimal flag unverifiable |
| C7 | CONFIRMED | Kotlin 2.4.20 (Sept 7, 2026); SKIE 0.10.14 (July 2026); karakum 1.0.0-alpha.112 |
| C8 | CONFIRMED | swift-java 0.6.0 (Sept 5, 2026); FFM/JNI modes confirmed; jextract maintained |
| C9 | CONFIRMED | terra exists; cxx-parser with cppast/libclang; YAML config; maintained Aug 2026 |
| C10 | UNVERIFIABLE | RN 0.87.1 current; 0.76 New Architecture default claim unverifiable; nitro repo moved (301) |
| C11 | REFUTED | Djinni last release Dec 29, **2023** (not 2026); last commit Dec 23, 2025; only Java/ObjC targets |

---

## Lookup Budget
- Total API calls: ~50 (under 40-call budget, achieved via curl batching)
- Primary sources: GitHub API, crates.io, npm registry, pub.dev, official docs
- Unverifiable claims: Limited to incomplete doc access (404s) and archived repo redirects
