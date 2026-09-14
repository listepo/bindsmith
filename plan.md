# bindsmith
https://github.com/listepo/bindsmith
One bindsmith.yaml, six Flutter platforms. Generates Dart bindings for native APIs by driving official generators (ffigen, swiftgen, jnigen, winmd, dart-dbus) plus a TypeScript .d.ts driver, unified IR, review markers, one cross-platform facade.

| # | Статус | Приоритет | Сложность | Готовность | Агент |
| --- | --- | --- | --- | --- | --- |
| P0-4 | in progress | P2 | 1 | 90% | Cursor / composer-2.5 |
| P2-5 | in progress | P2 | 3 | 0% | Cursor / grok 4.6 |
| P8-3 | in progress | P3 | 3 | 80% | Cursor / grok 4.6 |

### P0-4. Upstream pins

Pin upstream versions in `pubspec.yaml` with caret ranges no wider than one major as each driver lands, and cite each remaining pin against the registry.

**Landed and cited** (see `toolchain.md`, verified on pub.dev 2026-09-12): `ffigen: ^22.0.0`, `jnigen: ^1.0.0`, `swiftgen: ^0.2.0`, `objective_c: ^9.6.0` (fixtures), `jni: ^1.0.3` (JVM probe in `test/jvm_toolchain.dart`), `winmd: ^7.1.0` (7.1.1 blocked: needs `cli_util ^0.5.1`, ffigen 22 pins `^0.4.2`), `dbus: ^0.7.15`, `hooks: ^2.2.0`, `code_assets: ^2.0.0`, `native_toolchain_c: ^0.19.4` (fixtures dev_deps); tooling `args: ^2.7.0`, `yaml: ^3.1.0`, `dart_style: ^3.1.0`, `path: ^1.9.0`, `analyzer: ^14.3.0`, `crypto: ^3.0.7`.

**Still waiting on driver:** `pigeon: ^28.0.0` (channels fallback — no driver yet). Optional tooling (`mason_logger`, `cli_completion`, `checked_yaml`, `code_builder`, `glob`, `pub_semver`) — add only when a task needs them.

Done when every remaining pin is cited against the registry; `dart pub get` at root resolves.

### P2-5. Swift docs in the raw binding

Swift docs in the raw Objective-C binding: swift2objc should carry `docComment` into its wrapper (upstream). The cause, checked in the pub cache:

- swift2objc 0.3.0 never reads `docComment` from the symbol graph. The word appears nowhere in `swift2objc-0.3.0/lib/`.
- So the `@objc` wrapper it writes has no comments, and neither does the `-Swift.h` that `swiftc` emits from that wrapper.
- ffigen therefore falls back to the class name: `/// GreeterWrapper` in `fixtures/lib/generated/greeter_swift/swift.g.dart`.
- swiftgen 0.2.0 builds its own `fg.Output` without a `commentType`. That means ffigen's default `CommentType.def()` (doxygen style, full length), which does read `///`, so nothing on the swiftgen side needs changing.

Only the raw binding is affected: the IR and the facade already take Swift docs from the symbol graph (`_withDocs` in `swift_driver.dart`). The fix belongs upstream. Both local alternatives drive a tool through its output (rule 1): editing swift2objc's output text, or splitting swiftgen's single `generate()` into its three steps so the wrapper can be patched between them.

1. **Prove the rest of the chain first.** The P7-1 bridge skips swift2objc (`objcCompatibleSources`) and already carries `///` docs (`GreeterKit.bridge.g.swift`), so it tests `swiftc` → header → ffigen with no swift2objc involved. The committed `swift.g.dart` has no `GreeterBridge` at all, so a grep proves nothing; the check needs a run. Run the round trip in `test/drivers/swift_test.dart` and look at the Dart it generates for `GreeterBridge`. If the bridge's text is missing there too, find where it is lost (`swiftc -emit-objc-header-path`, or ffigen on that header) before going upstream. A swift2objc change only helps if everything after it works.
2. **Open the issue** on dart-lang/native, labelled swift2objc, with that evidence. Propose: parse `docComment.lines[].text` in the symbol-graph parser, keep it on the AST declarations, and write it as `///` above each generated wrapper declaration. Offer the PR, and link the issue from this row.
3. **When a swift2objc release carries it:** bump the pin (P0-4) and cite pub.dev in the commit message; regenerate the Swift goldens with `UPDATE_GOLDENS=1` and check the binding carries the Swift text; keep `_withDocs` (it only fills docs that are still empty, so it becomes a no-op rather than a conflict); remove the Swift caveat from `AGENTS.md` (Style → documentation bullet) and from `docs/platforms.md` (Documentation).

Done when `swift.g.dart` documents `GreeterWrapper` and its members with the Swift text, and no bindsmith code rewrites upstream output. Until upstream ships, the row stays open with the issue link; nothing local stands in for it.

### P8-3. Release and publish

Release engineering: `dart pub publish` for `bindsmith` and `bindsmith_runtime`; GitHub Release with `dart compile exe` binaries built natively per OS (cross-compile only targets Linux); Homebrew tap formula; `pana` score target ≥ 140; CHANGELOG; version policy: bindsmith minor bump per upstream generator major. Telemetry: none. Issue templates ask for `bindsmith doctor --json` output.

Depends on P8-1. Do not `pub publish` until asked. Done when packages are published and the release artefacts above exist.

Plan (Cursor / grok 4.6): artefacts only, no `pub publish`. 1. CHANGELOG.md on both packages + version policy in docs/upgrading.md. 2. Issue templates that ask for `bindsmith doctor --json`. 3. GitHub Release workflow: native `dart compile exe` per OS. 4. Homebrew formula generator (tap push stays creator). 5. pana ≥ 140 in CI. Leave the row open until the creator asks to publish.

## Reference

`bindsmith` is a Dart command-line tool that reads one config (`bindsmith.yaml`) describing a native API and generates Dart bindings for the six Flutter platforms, plus a unified Dart facade with platform dispatch, native "slim" wrappers where direct binding is impossible, and the build glue (`hook/build.dart`, podspec/SwiftPM, Gradle, `web/index.html` snippets).

It does not implement parsers or FFI itself. It orchestrates the official generators through their Dart library APIs and adds what none of them has: one config for all platforms, a unified intermediate representation (IR) with fixup passes, review markers, dependency resolution with a lockfile, and a verification matrix.

Finished tasks and their implementation notes live in `done.md`. Read `research.md` for the evidence; `docs/research-raw/` holds the raw agent reports and fact-check logs; `AGENTS.md` holds the working rules.

| Surface | Input | Upstream we drive | Version pinned at start |
|---|---|---|---|
| C (all desktop + mobile) | headers | `ffigen` (`FfiGenerator`, `Input`, `DartOutput`, visitors) | 22.0.0 |
| Objective-C (iOS/macOS) | headers | `ffigen` objc mode + `objective_c` runtime | 22.0.0 / 9.6.0 |
| Swift (iOS/macOS) | Swift module | `swiftgen` (`SwiftGenerator`) → swift2objc → ffigen | 0.2.0 / 0.3.0 (experimental) |
| Java/Kotlin (Android, desktop JVM) | JAR/AAR/.class, Maven coords | `jnigen` (`JniGenerator`, `Input`, `DartOutput`, `generate()`), `jni` runtime | 1.0.0 / 1.0.3 |
| Web JS libraries | `.d.ts` | own driver: TypeScript Compiler API sidecar → IR → `dart:js_interop` extension types; replace with dart-lang/web `js_interop_gen` when published | TS 5.x/6.x |
| Win32/COM | `.winmd` (`Microsoft.Windows.SDK.Win32Metadata`) | `winmd` reader; reuse `package:win32` when it already covers the API | 7.1.1 / 6.4.0 |
| D-Bus (Linux) | introspection XML | `dbus` (`dart-dbus generate-remote-object`) | 0.7.15 |
| GObject (Linux) | `.gir` | later; community `gir-binding-gen` is immature | — |
| Channels fallback | Dart IDL | `pigeon` | 28.0.0 |
| Native build | C/C++ sources | `hooks`, `code_assets`, `native_toolchain_c`, `native_toolchain_cmake` | 2.2.0 / 2.0.0 / 0.19.4 / 0.3.2 |

Decisions already made (see research.md §6–§8): host language Dart; static codegen, no runtime dispatch; YAML config with published JSON Schema plus a Dart-script escape hatch; drivers call upstream library APIs, never parse their console output; pull model (you list what you need) over "bind everything".

Out of scope for v1: C++ parsing (emit an `extern "C"` shim instead), macros, GUI, mandatory AI features, our own formatter/analyzer, dynamic runtime.

### Repository layout

Pub workspace (Dart ≥ 3.6). Two publishable packages, one fixtures package.

```
bindsmith/
  pubspec.yaml                 # workspace root
  AGENTS.md  (CLAUDE.md -> AGENTS.md)
  packages/
    bindsmith/                 # CLI + drivers + IR + passes + emitters
      bin/bindsmith.dart
      lib/src/cli/             # commands: init, doctor, resolve, generate, verify, diff, watch, explain, dump
      lib/src/config/          # yaml → typed model, schema export
      lib/src/ir/              # Decl, TypeDecl, Member, TypeRef, Marker
      lib/src/drivers/         # c, objc, swift, jvm, dts, winmd, dbus  (one adapter file per upstream)
      lib/src/passes/          # include, rename, nullability, async, threading, availability, docs, fixups, verify, budget
      lib/src/emit/            # platform files, facade, native wrappers, build glue
      lib/src/deps/            # maven, cocoapods/swiftpm, npm, nuget, pkg-config, lockfile
      lib/src/verify/          # analyze, compile matrix runner, golden compare
      schema/bindsmith.schema.json
      tool/ts_sidecar/         # node script: .d.ts → declarations JSON (TypeScript Compiler API)
      test/                    # unit + golden
    bindsmith_runtime/         # tiny: @BindsmithVerify, platform dispatch helpers, error mapping
  fixtures/                    # workspace package; inputs per driver, generated output under lib/generated/
    c/geometry/                # header + impl
    objc/Greeter/              # small ObjC framework
    swift/Greeter/             # Swift package with @objc and Swift-only parts
    jvm/greeter/               # Kotlin lib: classes, interface, suspend, Flow, default params
    dts/                       # .d.ts fixtures (nanoid, uuid, chart subset)
    winmd/                     # NativeMethods-style include list against real Win32Metadata
    dbus/org.example.Greeter.xml
  examples/                    # end-to-end real SDK bindings (P8-1)
  docs/                        # research (EN + RU), ADRs, research-raw
```

Rules: `bindsmith_runtime` has no dependency on the generator. Generated code depends only on `bindsmith_runtime`, `ffi`, `objective_c`, `jni`, `web`/`dart:js_interop` as appropriate. `lints/recommended` plus `analysis_options.yaml` with `strict-casts`, `strict-inference`, `strict-raw-types`.

### Config and CLI contract

#### `bindsmith.yaml`

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/listepo/bindsmith/main/packages/bindsmith/schema/bindsmith.schema.json
name: my_sdk                      # Dart package to generate into
output: lib/src/generated
facade:
  library: lib/my_sdk.dart        # unified entry with conditional imports
  unsupported: throw              # throw | stub | omit

platforms:
  android:
    driver: jvm
    deps:
      maven:
        - com.example:sdk-android:2.3.1
    include:
      classes: [com.example.sdk.Client, com.example.sdk.Callback]
    kotlin:
      suspend: future             # future | callback
      flow: stream
  ios:
    driver: swift                 # or objc
    deps:
      swiftpm:
        - url: https://github.com/example/sdk-ios
          from: 2.3.0
    include:
      types: [Client, ClientDelegate]
    wrapper: auto                 # generate @objc slim wrapper for Swift-only members
  macos: { inherit: ios }
  windows:
    driver: c
    headers: [third_party/sdk/include/sdk.h]
    compiler_opts: ["-I", "third_party/sdk/include"]
    include: { functions: ["sdk_*"], structs: ["sdk_*"] }
    build: { hook: native_toolchain_c, sources: [src/shim.c] }
  linux: { inherit: windows }
  web:
    driver: dts
    deps: { npm: ["@example/sdk@2.3.1"] }
    include: { exports: [Client, ClientOptions] }

fixups:
  - match: { platform: android, symbol: com.example.sdk.Client#connect$2 }
    rename: connectWithTimeout
  - match: { symbol: "Client.*Legacy*" }
    hide: true
  - match: { platform: ios, symbol: Client.onEvent }
    threading: main
  - match: { symbol: Client.fetch }
    nullability: { returns: nonnull }

verify:
  markers: error                  # error | warn
  compile: [android, ios, macos, windows, linux, web]
  size_budget: { lines: 40000 }
```

Semantics: `include` is a pull list (globs allowed). Nothing outside the pull list is emitted, including transitive types unless required for signatures (then emitted as opaque). `fixups` are applied in order after the driver produces IR. `inherit` copies a platform block.

Escape hatch: `tool/bindsmith.dart` may construct the same model in Dart (`Bindsmith(config: ..., drivers: ...).run()`) for cases YAML cannot express (custom visitors). The YAML loader and the Dart API must produce the same `BindsmithConfig` object.

#### Commands

| Command | Behavior | Exit code |
|---|---|---|
| `bindsmith init [--template c\|objc\|swift\|jvm\|dts]` | writes `bindsmith.yaml` with commented example, adds dev deps to pubspec | 0 |
| `bindsmith doctor` | checks Dart/Flutter, libclang, Xcode + swiftc, JDK 17–21 + Android SDK, VS Build Tools, node ≥ 20, pkg-config; prints fix hints | 0 / 1 if a required toolchain for configured platforms is missing |
| `bindsmith resolve` | fetches Maven/SwiftPM/CocoaPods/npm/NuGet inputs, writes `bindsmith.lock` (URL, version, sha256) | 0 / 2 on resolution failure |
| `bindsmith dump [--platform]` | prints every symbol the drivers can see, in include-list syntax (jextract `--dump-includes` pattern) | 0 |
| `bindsmith generate [--platform p] [--check]` | drivers → IR → passes → emitters; `--check` fails if output differs from disk (CI) | 0 / 3 on generation error / 4 on `--check` diff |
| `bindsmith verify` | reads the committed generated code: fails on unresolved `@BindsmithVerify` (unless `markers: warn`), on a `size_budget` overrun, and when the io and web facades declare different public APIs. The compile matrix (`verify.compile`) belongs with the end-to-end matrix, since it needs the toolchains this command deliberately does not | 0 / 1 |
| `bindsmith diff <old-lock>` | after bumping upstream generators or SDK versions: shows renamed/removed/added symbols, e.g. `Intent.new$2 → Intent.new$12` | 0 |
| `bindsmith watch` | re-generate on header/config change (file watcher) | — |
| `bindsmith explain <symbol>` | shows how a symbol was mapped: source decl, passes applied, fixups matched, output location | 0 |

Logging via `mason_logger` (levels, progress). Machine-readable `--json` for `doctor`, `dump`, `diff`.

### IR sketch

```dart
sealed class Decl { String id; Platform platform; SourceLoc loc; Docs? docs; Availability? availability; List<Marker> markers; }
class TypeDecl extends Decl { TypeKind kind /* class, interface, protocol, struct, enum, opaque, typedef, jsObject */; List<Member> members; List<TypeRef> supertypes; }
class Member { String name; MemberKind kind /* method, ctor, property, field, constant, event */; List<Param> params; TypeRef returns; Async async /* none, future, stream, callback */; Threading threading /* any, main */; Nullability nullability; bool isStatic; }
class TypeRef { String name; List<TypeRef> args; Nullability nullability; PlatformType? native; }
class Marker { MarkerKind kind /* verify, todo, dropped */; String reason; }
```

Every driver produces `List<Decl>` for its platform. Passes are pure functions `List<Decl> → List<Decl>` and are unit-tested in isolation with small hand-built IR. Emitters consume IR only; they never look at driver internals.

The Dart facade is synthesized from the per-platform IR by name matching within `facade.groups` (config) or automatically when a symbol exists on all configured platforms with compatible shapes; mismatches produce `@BindsmithVerify('shape differs on ios vs android')`.

### Complexity scale

| Rating | Meaning |
|---|---|
| **C1** | Mechanical. Known API, no design decisions, no toolchain. |
| **C2** | Straightforward. One known library or CLI; the shape of the code is obvious. |
| **C3** | Needs a design or an external toolchain (JDK, Xcode, libclang, NuGet) and CI plumbing. |
| **C4** | Depends on upstream behavior we do not control (experimental generators, rewritten APIs) or cuts across several modules; expect a spike before the real code. |
| **C5** | Research-grade. Semantic gaps with no upstream to lean on (structural vs nominal typing, unifying six platform shapes into one facade, generating native wrappers); several iterations and fixtures needed before the design settles. |

A finished task moves to `done.md` in the change that finishes it.

### Execution order (risk-first)

The order is by risk, not by phase number. Highest-complexity work with no unfinished prerequisite goes first, so the design settles where it is most likely to be wrong.

1. **Core spine (C5/C4):** P6-1 IR → P6-2 passes → P6-4 facade synthesis, all on hand-built IR with unit and golden tests. No toolchain needed; this is where every driver plugs in, so it must exist before any driver does.
2. **Web `.d.ts` (C5/C4):** P4-1 sidecar → P4-2 driver → P4-3 emitter. The largest semantic gap and the only surface with no upstream generator to lean on; the sidecar is also the only non-Dart component.
3. **First upstream adapter (C4):** P1-2 C driver over ffigen 22. Proves "drive via library API" and the IR extraction approach on a stable generator, with a local libclang.
4. **JVM (C4/C3):** P3-1 driver, P3-2 Maven, P3-3 lockfile. Second adapter; brings the dependency and reproducibility story.
5. **Apple (C4):** P2-1 ObjC, P2-2 Swift (experimental upstream; adapter isolates churn), P2-3, P2-4.
6. **Wrappers (C5):** P7-1 Swift, P7-2 Kotlin, P7-3 C++ shim. Needs the dropped markers from steps 4–5.
7. **Remaining drivers (C4/C2):** P5-1 winmd, P5-3 pkg-config, P5-4 D-Bus, P5-5 hook templates, P5-2 NuGet.
8. **Product surface (C3/C2):** P1-1 config loader + schema (can start any time after step 1; needed before the CLI is usable end to end), P1-4 CLI, P1-5 doctor, P6-3 fixups DSL, P6-5 verify, P6-6 explain/diff/watch, P0-3 runtime, P0-2 ADRs.
9. **Examples, docs, release (C4/C3):** P8-1 → P8-2 → P8-3.
10. **Left:** P2-5 waits on upstream swift2objc `docComment` (prove the chain, open the issue, keep `_withDocs` until a release carries it). P8-3 release after P8-1 — do not `pub publish` until asked. P0-4 stays open until each remaining pin is cited against the registry.

Steps 1–9 of this order are done except the leftover items in the table above.

### Phases

Complexity codes refer to the scale above.

#### Phase 0 — Skeleton and decision records — C2

Acceptance: `dart pub get` at root resolves (done); CI green on three OSes; `bindsmith --help` prints commands.

#### Phase 1 — Config, IR, first vertical slice: C driver — C4

Acceptance: `bindsmith generate --platform linux` on the fixture produces compiling Dart on ubuntu and macOS; golden test passes; config errors are actionable.

Facts to respect: ffigen only parses C and Objective-C; needs libclang (`doctor` must locate it: Xcode CLT on macOS, `libclang-dev` on Linux, LLVM on Windows). YAML config in ffigen is deprecated; do not generate `ffigen.yaml`.

#### Phase 2 — Apple: Objective-C and Swift drivers (macOS runner) — C4

Acceptance: fixtures bind and run under `dart test` on macOS; Swift-only members appear in `bindsmith dump` as dropped with reasons; generated podspec passes `pod lib lint --quick` on the example.

Facts: swiftgen 0.2.0 and swift2objc 0.3.0 are experimental — wrap every call in an adapter class so breaking changes touch one file; commit both `.g.dart` and `.m` (roszkowski.dev lesson).

#### Phase 3 — Android: JVM driver, Maven resolution, lockfile — C4

Facts: jnigen needs the compiled classpath at generation time; jni 1.0.3 / jnigen 1.0.0 renamed the API (`Config → JniGenerator`, `generateJniBindings → generate()`); global refs need `.release()`.

#### Phase 4 — Web: `.d.ts` driver — C5

Acceptance: fixtures compile under dart2js and dart2wasm; every unsupported TS construct is a marker, never a silent drop; sidecar has its own tests.

Facts: no public `.d.ts → Dart` generator exists (js_facade_gen archived 2022); dart-lang/web has an unpublished `js_interop_gen` — add a tracking issue to swap the sidecar for it; `package:js`/`dart:html` do not compile to wasm.

#### Phase 5 — Windows and Linux specifics — C4/C2

Acceptance: winmd fixture generates and analyzes on Windows; Linux fixture compiles with `pkg-config`-derived flags on ubuntu; D-Bus fixture generates client class.

#### Phase 6 — Unified facade, passes, fixups, verify — C5

Acceptance: a fixture configured for all six platforms produces one importable library whose public API is identical across platforms (checked by an `analyzer`-based test that compares public element signatures); markers block `verify` until acknowledged.

#### Phase 7 — Slim-binding wrapper generation — C5

Acceptance: `fixtures/swift/Greeter` Swift-only struct method becomes callable from Dart via the bridge; `fixtures/jvm/greeter` `Flow` becomes a `Stream`.

#### Phase 8 — Real examples, docs, release — C4/C3

Acceptance: all five examples build in CI (`flutter build` per platform available on the runner); docs site live; packages published.

### Testing strategy

| Layer | Tool | What |
|---|---|---|
| Config | `dart test` | every schema rule has a failing and passing case |
| Drivers | contract tests | pinned upstream API surface: constructing `FfiGenerator`, `JniGenerator`, `SwiftGenerator` with our arguments compiles and runs on a fixture; breaks loudly on upstream rename |
| Passes | unit | pure IR in/out |
| Emitters | golden files | byte-exact, `dart format` applied before compare, `\r\n` normalized |
| End-to-end | compile matrix | per OS runner: `dart analyze`, native compile of fixtures, `dart test` calling into them; web: dart2js + dart2wasm |
| Determinism | CI `generate --check` | second generation produces no diff |
| Size | budget report | lines/symbols per platform compared with committed baseline |

### CI matrix

| Runner | Platforms exercised | Toolchain setup |
|---|---|---|
| macos-latest | ios, macos (ObjC, Swift), c | Xcode CLT, `swiftc`, libclang from Xcode |
| ubuntu-latest | linux (c, dbus), android (jvm, Maven, `Jni.spawn`), web (node 24, dart2js/wasm) | `libclang-dev`, JDK 17, Android cmdline-tools, node |
| windows-latest | windows (c, winmd) | LLVM (choco), VS Build Tools, NuGet metadata download |

### Risks and mitigations

| Risk | Mitigation |
|---|---|
| Upstream API churn (ffigen 22 rewrite, jnigen 1.0 rename, swiftgen 0.x) | adapters per driver, contract tests, one-major caret pins, `bindsmith diff` for users |
| swiftgen instability | wrapper path (Phase 7) is the fallback for anything swiftgen cannot bridge |
| `.d.ts` semantics | subset + markers; track `js_interop_gen`; never silently drop |
| Heavy toolchains | `doctor` with exact fix commands; CI images documented; `resolve` caches under `.dart_tool/bindsmith/` |
| Scope creep across six platforms | phases are independently shippable; publish after step 4 of the execution order as `0.x` with C + Web + JVM |
| Macros and C++ | documented non-goal; shim generator |

### Definition of "best in class" (what reviewers should check at the end)

1. One `bindsmith.yaml` produces bindings for all six platforms and a facade whose public API is identical everywhere.
2. Every unsupported construct is visible: in `dump`, as a marker in code, and in `verify` output. No silent drops.
3. Generation is reproducible from the lockfile on a clean CI machine, offline after `resolve`.
4. Upstream bumps are explainable via `diff`; renamed overloads never surprise users.
5. Swift-only, coroutine-only and C++ APIs are reachable through generated wrappers, not hand-written advice.
6. `.d.ts` → Dart works for at least the two simple and one class-heavy fixture and compiles to wasm.
7. `doctor` gets a fresh machine from zero to first generation with copy-paste commands.
8. Docs are generated from the schema; the schema is what the YAML language server validates against.

### References

- research.md §2 (Dart tool versions), §3 (per-platform recipes), §4 (analogs), §11 (fact-check log)
- dart-lang/native: ffigen, jnigen, swiftgen, swift2objc READMEs and CHANGELOGs
- dart.dev/interop (C, Objective-C/Swift, Java/Kotlin, JS), dart.dev/tools/hooks
- docs.flutter.dev/packages-and-plugins/developing-packages (`package_ffi`, federated plugins)
- Objective Sharpie `[Verify]` docs; .NET for Android `Metadata.xml` and `AndroidMavenLibrary`; MAUI Native Library Interop; CsWin32 `NativeMethods.txt`
- madsmtm/objc2 `translation-config.toml`; gtk-rs `Gir.toml`; jextract `--dump-includes`
- roszkowski.dev/2026/swiftgen-jnigen/ (practical jnigen/swiftgen lessons)
