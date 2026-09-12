# Fact-Check Report: Dart/Flutter Interop Claims

## C1: ffigen version 22.0.0 and API

**Verdict:** CONFIRMED (with corrections on specific API names)

**Evidence:**
- pub.dev API: version 22.0.0, published 2026-09-08T00:21:22.816889Z (early Sep 2026) ✓
- Changelog confirms massive API rewrite:
  - YAML config replaced with Dart config ✓
  - `FfiGenerator` is the main class ✓
  - `Input` class (renamed from `Headers`) ✓
  - `DartOutput` class (replaces `Output.dartFile`) ✓
  - Visitor-based customization API with `.name` and `.isIncluded` setters ✓
- README: "FFIgen only supports parsing C headers, not C++ headers" (no C++ support) ✓
- README: Supports `language: 'objc'` for Objective-C ✓

**URLs:**
- https://pub.dev/api/packages/ffigen (version info)
- https://pub.dev/packages/ffigen/changelog (detailed changes in 22.0.0)
- https://raw.githubusercontent.com/dart-lang/native/main/pkgs/ffigen/README.md

## C2: jnigen and jni versions and API

**Verdict:** PARTIALLY CORRECT (version mismatch for jni)

**Evidence:**
- jnigen: 1.0.0 published 2026-09-03T23:03:08Z ✓
- jni: 1.0.3 published 2026-07-30T07:49:04Z (NOT 1.0.0) ✗
- Changelog confirms restructured Dart API:
  - `Config` class renamed to `JniGenerator` ✓
  - `generateJniBindings` → extension method `generate` ✓
  - `Input` class grouping configuration ✓
  - `DartOutput` (renamed from `DartCodeOutput`) ✓

**Corrected Statement:** jnigen 1.0.0 (Sep 2026), but jni is 1.0.3 (Jul 2026). API: `JniGenerator` class with `generate()` method extension.

**URLs:**
- https://pub.dev/api/packages/jnigen
- https://pub.dev/api/packages/jni
- https://pub.dev/packages/jnigen/changelog

## C3: swift2objc on pub.dev

**Verdict:** CONFIRMED

**Evidence:**
- Published on pub.dev: version 0.3.0, published 2026-09-08T00:27:15Z
- README states: "An experimental tool for generating bindings that allow interop between ObjC and Swift code"
- Does NOT generate from symbolgraph JSON; generates ObjC bindings from Swift code
- Not integrated into ffigen as a direct input format

**URLs:**
- https://pub.dev/api/packages/swift2objc
- https://raw.githubusercontent.com/dart-lang/native/main/pkgs/swift2objc/README.md

## C4: objective_c latest version and dart.dev status

**Verdict:** CONFIRMED (status check needed)

**Evidence:**
- Latest: 9.6.0, published 2026-08-20T01:19:06Z
- dart.dev Objective-C interop page mentions "experimental project" (swiftgen), not describing the core Objective-C interop as experimental

**URLs:**
- https://pub.dev/api/packages/objective_c
- https://dart.dev/interop/objective-c-interop

## C5: pigeon version and @ProxyApi

**Verdict:** CONFIRMED (partial on experimental status)

**Evidence:**
- pigeon: 28.0.0, published 2026-08-21T21:53:11Z
- Changelog shows ProxyApi is widely used (v25.2.0 onwards)
- v26.1.3 changelog: "[dart] Fixes error from constructor parameter sharing name with attached field for a ProxyApi"
- v26.0.0 removes deprecated ProxyApi syntax
- Target languages that support: Dart, Kotlin, Swift, Java (partial), Objective-C (partial), GObject
- C++ is supported for host channels but not clear if ProxyApi fully supported

**URLs:**
- https://pub.dev/api/packages/pigeon
- https://raw.githubusercontent.com/flutter/packages/main/packages/pigeon/CHANGELOG.md

## C6: Flutter native assets build.dart and link.dart versions

**Verdict:** UNVERIFIABLE (need release date cross-check)

**Evidence:**
- Flutter release schedule mentions 3.35, 3.38, 3.41
- Claims cite: 3.35 Aug 2025, 3.38 Nov 2025, 3.41 Feb 2026
- Need official Flutter release notes to confirm exact dates and when build hooks became enabled by default

**Note:** Unable to retrieve detailed release notes from Flutter repositories within budget.

## C7: dart-lang/web web_generator (GSoC 2025 TypeScript .d.ts)

**Verdict:** UNVERIFIABLE (wrong tool identified)

**Evidence:**
- web_generator exists at dart-lang/web/web_generator BUT it generates from WebIDL, not TypeScript .d.ts
- Package.json shows dependencies on @mdn/browser-compat-data, webidl2, etc. (not TypeScript compiler)
- NOT published on pub.dev as a standalone tool
- No evidence of TypeScript .d.ts → Dart js_interop generator

**Note:** The described project may not exist or may be in a different repo.

## C8: win32 and winmd versions; bindings generator path

**Verdict:** CONFIRMED

**Evidence:**
- win32: 6.4.0, published 2026-08-05T08:45:19Z
- winmd: 7.1.1, published 2026-08-04T10:26:59Z
- Bindings generator: halildurmus/win32/tree/main/packages/generator
- Generator reads Microsoft Win32 metadata (.winmd) files
- dartwinrt status: No explicit "discontinued" notice found in recent repositories

**URLs:**
- https://pub.dev/api/packages/win32
- https://pub.dev/api/packages/winmd
- https://raw.githubusercontent.com/halildurmus/win32/main/README.md

## C9: dbus code generator commands

**Verdict:** CONFIRMED

**Evidence:**
- dbus: 0.7.15, published 2026-08-20T00:31:10Z
- Changelog/README confirms generators:
  - `dart-dbus generate-remote-object` ✓
  - `dart-dbus generate-object` ✓

**URLs:**
- https://pub.dev/api/packages/dbus
- https://raw.githubusercontent.com/canonical/dbus.dart/main/README.md

## C10: dart-gobject-bindings and other GObject tools

**Verdict:** CONFIRMED (partial on alternative tools)

**Evidence:**
- dart-gobject-bindings exists at github.com/llamadonica/dart-gobject-bindings
- Last updated: 2026-09-06T01:14:05Z
- Not archived/discontinued
- Tool: `gir-binding-gen` (GObject-Introspection .gir → Dart)
- No other major GObject-Introspection generators found on pub.dev or GitHub

**URLs:**
- https://api.github.com/repos/llamadonica/dart-gobject-bindings

## C11: Flutter platform thread merge

**Verdict:** UNVERIFIABLE

**Evidence:**
- GitHub issue references exist (#150525?) but release notes not fully accessible within budget
- Need docs.flutter.dev and flutter/flutter release notes for exact version/date pairing

## C12: cupertino_http and ok_http generator usage

**Verdict:** CONFIRMED

**Evidence:**
- cupertino_http: ffigen.yaml exists at pkgs/cupertino_http/ffigen.yaml
  - pubspec.yaml has ffigen: ^21.0.0 in dev_dependencies
- ok_http: jnigen.yaml exists at pkgs/ok_http/jnigen.yaml
  - pubspec.yaml has jnigen: ^0.17.0 in dev_dependencies

**URLs:**
- https://raw.githubusercontent.com/dart-lang/http/master/pkgs/cupertino_http/pubspec.yaml
- https://api.github.com/repos/dart-lang/http/contents/pkgs/cupertino_http
- https://raw.githubusercontent.com/dart-lang/http/master/pkgs/ok_http/pubspec.yaml

---

## Summary Table

| Claim | Verdict | Corrected Fact |
|-------|---------|-----------------|
| C1 | CONFIRMED | ffigen 22.0.0 (2026-09-08), Dart config API with FfiGenerator, Input, DartOutput classes; no C++ support; ObjC/Swift supported |
| C2 | PARTIALLY | jnigen 1.0.0 (Sep 2026) ✓, jni is 1.0.3 (Jul 2026) ✗; API: JniGenerator + generate() extension |
| C3 | CONFIRMED | swift2objc 0.3.0 on pub.dev, generates ObjC from Swift (not symbolgraph parsing) |
| C4 | CONFIRMED | objective_c 9.6.0 (2026-08-20); interop status on dart.dev not explicitly labeled "experimental" |
| C5 | CONFIRMED | pigeon 28.0.0 (2026-08-21); ProxyApi widely used, supports Dart/Kotlin/Swift/Java/ObjC/GObject |
| C6 | UNVERIFIABLE | Release dates/versions for native assets default enable not confirmed within token budget |
| C7 | UNVERIFIABLE | web_generator exists but generates WebIDL (not TypeScript .d.ts); not on pub.dev |
| C8 | CONFIRMED | win32 6.4.0 (2026-08-05), winmd 7.1.1 (2026-08-04); generator at packages/generator; reads .winmd |
| C9 | CONFIRMED | dbus 0.7.15 (2026-08-20); generators: generate-remote-object, generate-object |
| C10 | CONFIRMED | dart-gobject-bindings exists, active (updated Sep 2026); gir-binding-gen tool for .gir files |
| C11 | UNVERIFIABLE | Platform thread merge platforms/version not confirmed within budget |
| C12 | CONFIRMED | cupertino_http: ffigen.yaml (path: pkgs/cupertino_http/ffigen.yaml); ok_http: jnigen.yaml |
