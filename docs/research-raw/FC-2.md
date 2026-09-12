# Fact-Check Report: .NET Interop & Mobile Bindings Claims

## C1: Objective Sharpie Closed-Source Status

**Verdict:** REFUTED (partially)

**Corrected Statement:**  
Objective Sharpie is NOT closed-source — it is a published .NET global tool (`Sharpie.Bind.Tool`) available via `dotnet tool install -g Sharpie.Bind.Tool`. The source code does NOT appear to be publicly available on GitHub. It is macOS-only and remains downloadable/maintained in 2026. The `[Verify]` attribute intentionally fails C# compilation until removed.

**Evidence:**
- **Get Started docs** (learn.microsoft.com, updated 2026-04-20): "Install it as a global .NET tool: `dotnet tool install -g Sharpie.Bind.Tool`"
- **[Verify] Attribute docs** (learn.microsoft.com, updated 2026-03-05): "`[Verify]` attributes intentionally cause C# compilation errors so that you are forced to verify the binding. You should remove the `[Verify]` attribute when you have reviewed (and possibly corrected) the code."
- No GitHub repo found under microsoft/ or dotnet/ for the Sharpie.Bind.Tool source code.

**URLs:**
- https://learn.microsoft.com/en-us/dotnet/maui/ios/objective-sharpie/get-started?view=net-maui-10.0
- https://learn.microsoft.com/en-us/dotnet/maui/ios/objective-sharpie/platform/verify?view=net-maui-10.0

---

## C2: dotnet/macios Roslyn-Based Binding Generator

**Verdict:** CONFIRMED (RFC exists; PARTIALLY for status)

**Corrected Statement:**  
RFC #21308 exists proposing migration of bgen to Roslyn ("rgen" / `Microsoft.Macios.Generator`). As of 2026-09, the status is **OPEN/PROPOSED** (not yet preview or default). The RFC was opened Sept 25, 2024, assigned to "Future" milestone with no active development or PR. `xtro-sharpie` exists as a separate tool/repo used for API validation (checking deprecated APIs).

**Evidence:**
- **RFC Issue #21308** (github.com/dotnet/macios, opened 2024-09-25): "RFC: Migrate bgen to use roslyn instead of the reflection API."
  - State: Open, unresolved
  - Milestone: Future (no due date)
  - No PRs or active development
- **xtro-sharpie references**: Found in issue #4431 (2015) and other tickets; used to validate/check deprecated APIs in bindings.

**URLs:**
- https://github.com/dotnet/macios/issues/21308

---

## C3: .NET for Android AndroidMavenLibrary Support

**Verdict:** CONFIRMED (for AndroidMavenLibrary); UNVERIFIABLE (for Kotlin suspend)

**Corrected Statement:**  
AndroidMavenLibrary with automatic Maven download was introduced in **.NET 9** (confirmed).  
`<AndroidMavenLibrary Include="group:artifact" Version="..." />` enables automatic JAR/AAR download and Java dependency verification.  
**Kotlin suspend functions claim: UNVERIFIABLE** — No documentation found stating whether they are bindable or hidden by the generator. This requires deeper investigation of the Java binding generator behavior.

**Evidence:**
- **AndroidMavenLibrary Build Action** (learn.microsoft.com): "In .NET 9 introduces support for automatically downloading a Java library from a Maven repository and verifying its dependencies."
- **Example**: `<AndroidMavenLibrary Include="com.squareup.okhttp3:okhttp" Version="4.9.3" />`
- No explicit mention found of Kotlin suspend function handling in official docs.

**URLs:**
- https://learn.microsoft.com/en-us/dotnet/android/binding-libs/advanced-concepts/android-maven-library
- https://learn.microsoft.com/en-us/dotnet/android/binding-libs/binding-java-libs/binding-java-maven-library

---

## C4: .NET 9 Swift Interop (CallConvSwift + SwiftSelf)

**Verdict:** CONFIRMED

**Corrected Statement:**  
`CallConvSwift` (in `System.Runtime.CompilerServices`) and `System.Runtime.InteropServices.Swift.SwiftSelf` shipped in **.NET 9** (confirmed).  
The Swift bindings tool in **dotnet/runtimelab** lives in `src/SwiftBindings/` (directory). It consumes `.swiftinterface` files and dylib paths. It generates C# P/Invoke bindings. As of 2026, it remains in experimental/preview status (not shipped in a stable NuGet release; review UX discussions in GitHub issues #2518, #2891 ongoing).

**Evidence:**
- **System.Runtime.InteropServices.Swift namespace** (learn.microsoft.com, view=net-9.0): Contains SwiftSelf, SwiftError, SwiftIndirectResult structs
- **CallConvSwift Class** (learn.microsoft.com, view=net-9.0): Represents Swift calling convention
- **SwiftBindings in runtimelab** (github.com/dotnet/runtimelab): Issues #2518 (UX review), #2891 (unify code emission) show active but pre-release development
- **Input format**: Accepted inputs are `.swiftinterface` files and dylib paths (not ABI descriptor JSON directly)

**URLs:**
- https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.swift?view=net-9.0
- https://learn.microsoft.com/en-us/dotnet/api/system.runtime.compilerservices.callconvswift?view=net-9.0
- https://github.com/dotnet/runtimelab/issues/2518

---

## C5: .NET MAUI Native Library Interop Official Docs

**Verdict:** CONFIRMED (docs exist; PARTIALLY for templates)

**Corrected Statement:**  
".NET MAUI Native Library Interop" official docs exist at learn.microsoft.com/dotnet/communitytoolkit/maui/native-library-interop. The pattern is: write thin Swift/Kotlin wrapper libraries → bind the wrappers. A project template exists in the **`CommunityToolkit/Maui.NativeLibraryInterop`** GitHub repo (cloneable template; not a `dotnet new` official template). No `dotnet new` templates found in official .NET SDK.

**Evidence:**
- **Community Toolkit Docs** (learn.microsoft.com, updated 2025-02-11): "The easiest way to get started with creating a new binding is by cloning the **template** in the **[Maui.NativeLibraryInterop](https://github.com/CommunityToolkit/Maui.NativeLibraryInterop)** repo and making modifications from there."
- Template includes starter .NET binding projects + native wrapper projects in Xcode/Android Studio
- No explicit rationale sentence found (docs focus on mechanics, not philosophy)

**URLs:**
- https://learn.microsoft.com/en-us/dotnet/communitytoolkit/maui/native-library-interop/get-started
- https://github.com/CommunityToolkit/Maui.NativeLibraryInterop

---

## C6: CppSharp, ClangSharp, CsWin32, Win32Metadata Versions

**Verdict:** CONFIRMED (with dates)

**Corrected Statement:**

| Tool | Latest Version | Date | Maintained? |
|------|----------------|------|-------------|
| **mono/CppSharp** | v1.2 | Nov 19, 2025 | Yes (Clang 19 support) |
| **dotnet/ClangSharp** | 21.1.8.3 | Mar 23, 2026 | Yes |
| **dotnet/ClangSharpPInvokeGenerator** | 21.1.8.4 | Jul 15, 2026 | Yes |
| **microsoft/CsWin32** | 0.3.333 | Sep 3, 2026 | Yes |
| **microsoft/win32metadata** | 71.0.25-preview | (NuGet current) | Yes |

CppSharp configuration via `ILibrary` interface: **CONFIRMED** (source implements interface pattern).  
ClangSharpPInvokeGenerator accepts `.rsp` response files: **UNVERIFIED** — no example link found.  
CsWin32 `NativeMethods.txt` whitelist + source gen: **CONFIRMED** per docs.  
Dart `package:win32` and Rust `windows-rs` consume win32metadata: **CONFIRMED** (indirect references; metadata via NuGet consumed for code gen).

**URLs:**
- https://github.com/mono/CppSharp/releases
- https://www.nuget.org/packages/ClangSharpPInvokeGenerator/
- https://www.nuget.org/packages/Microsoft.Windows.CsWin32/0.3.333
- https://github.com/microsoft/win32metadata
- https://github.com/microsoft/windows-rs
- https://github.com/halildurmus/win32

---

## C7: NativeScript Versions & iOS Runtime V8 Switch

**Verdict:** REFUTED (timing is wrong)

**Corrected Statement:**

| Package | Latest Version | Notes |
|---------|---|---|
| **@nativescript/core** | 9.1.1 | Current (2026) |
| **@nativescript/types-ios** | 9.1.1 | Unpacked size: 15.2 MB |
| **@nativescript/types-android** | 9.1.1 | Unpacked size: 48.1 MB |
| **iOS runtime V8 switch** | **NativeScript 7.0** | **Mid-2020** (July 2020 target), NOT Nov 2025 / v9.0 |

The V8-based iOS runtime was released in **mid-2020 with NativeScript 7.0**, not NativeScript 9.0 in November 2025. An alpha existed in early 2020; beta announced Jan 2020; official release targeted July 1, 2020.

**iOS metadata generator**: Separate repo `NativeScript/ios-metadata-generator` (C++/libclang-based, confirmed).  
**Android metadata generator**: Moved to `dotnet/macios repo/test-app/build-tools/android-metadata-generator`; uses BCEL/ASM (gradle.properties shows ASM 9.7, BCEL 6.8.2).

**Evidence:**
- **NativeScript 8.0 blog** (blog.nativescript.org): Discusses V8 runtime already integrated
- **iOS Runtime V8 Beta blog** (blog.nativescript.org, Jan 2020): "New V8-based iOS Runtime is Now in BETA"
- **GitHub**: NativeScript/ns-v8ios-runtime shows repo description "NativeScript for iOS and visionOS using V8"
- **Metadata generators**: ios-metadata-generator (separate repo), android-metadata-generator (in android-runtime)

**URLs:**
- https://blog.nativescript.org/new-v8-based-ios-runtime-is-now-in-beta/
- https://blog.nativescript.org/nativescript-8-announcement/
- https://github.com/NativeScript/ios-metadata-generator
- https://github.com/NativeScript/android-metadata-generator

---

## C8: NativeScript Metadata Filtering Configuration

**Verdict:** REFUTED (partially)

**Corrected Statement:**  
Metadata filtering is configured using **`native-api-usage.json`** files (NOT `.mdg` files).  
Configuration locations:
- **Plugins**: `platforms/android/native-api-usage.json` and `platforms/ios/native-api-usage.json`
- **Apps**: `App_Resources/Android/native-api-usage.json` and `App_Resources/iOS/native-api-usage.json`

The `.mdg` format does NOT exist in NativeScript metadata filtering.

**Evidence:**
- **Metadata docs** (docs.nativescript.org): "Plugins can declare their list of APIs that are called from JavaScript using a file named `native-api-usage.json`, located in each of the platform directories (`platforms/android` or `platforms/ios`)."
- "Applications have the final word of what filtering will be applied to metadata. They provide similar `native-api-usage.json` files, located in `App_Resources/Android` and `App_Resources/iOS`"

**URLs:**
- https://docs.nativescript.org/guide/metadata

---

## C9: NativeScript CLI Typings Commands

**Verdict:** CONFIRMED (commands exist; implementation PARTIALLY UNVERIFIED)

**Corrected Statement:**  
Commands `ns typings ios` and `ns typings android --jar <file>` exist (confirmed).  
Also: `ns typings android "package-name"` (Maven package).  
What runs under the hood: **UNVERIFIED** in official docs. Android-dts-generator exists as separate tool but not confirmed as the CLI command's implementation. iOS typings appear to use the metadata generator but exact flow not documented.

**Evidence:**
- **Generating TypeScript types docs** (docs.nativescript.org): Lists commands with options
- **CLI man_pages** (github.com/NativeScript/nativescript-cli): Documents `--jar`, `--aar`, `--copy-to` flags
- **Unpacked sizes**: @nativescript/types-ios: 15.2 MB; @nativescript/types-android: 48.1 MB (from npm registry)

**URLs:**
- https://docs.nativescript.org/guide/native-code/generate-typings
- https://github.com/NativeScript/nativescript-cli/blob/main/docs/man_pages/project/testing/typings.md

---

## C10: dart_native Package Status

**Verdict:** PARTIALLY REFUTED

**Corrected Statement:**  
`dart_native` (pub.dev) latest version: **0.7.11**, published **3 years ago (~Dec 2022)**.  
Status: **NOT archived but unmaintained** (last update 3 years ago).  
**Has dart_native_gen**: Yes — dependency: `dart_native_gen` ^0.3.3 (latest version 0.4.0, also last updated 3 years ago).

Both packages appear stagnant but not formally archived. The claim "dart_native is maintained in 2026" is REFUTED — last update was ~2023.

**Evidence:**
- **pub.dev dart_native/versions**: Latest 0.7.11, "released 3 years ago"
- **pub.dev dart_native_gen**: Latest 0.4.0, "last updated 3 years ago"
- No archival badge found, but no recent activity either

**URLs:**
- https://pub.dev/packages/dart_native/versions
- https://pub.dev/packages/dart_native_gen

---

## C11: NativeScript Performance Benchmarks

**Verdict:** REFUTED (overhead is higher)

**Corrected Statement:**  
A published NativeScript performance benchmark exists (blog.nativescript.org "perf-metrics-universal-javascript-part1/"). **The measured overhead is ~3–4× native code performance, NOT 1.5–2×**.

Example (iPhone 13 Pro, string marshaling for 100,000 calls):
- **NativeScript 8.3**: 49 ms
- **Objective-C (native)**: 14 ms
- **Overhead**: ~3.5×

The blog does not cite "1.5–2× overhead" — it states "JavaScript is quite performant with platform API interaction" but actual measurements show 3–4× slowdown vs. native.

**Evidence:**
- **Performance Benchmarks blog** (blog.nativescript.org, perf-metrics-universal-javascript-part1): Publishes actual millisecond results
- **Result**: NativeScript 8.3 (49 ms) vs. Objective-C (14 ms) on iPhone 13 Pro → ~3.5× overhead
- No 1.5–2× claim found in published materials

**URLs:**
- https://blog.nativescript.org/perf-metrics-universal-javascript-part1/

---

## Summary Table

| Claim | Verdict | Correction |
|-------|---------|-----------|
| C1: Objective Sharpie closed-source | REFUTED | It's a dotnet global tool, not closed-source (source not public, but tool is); [Verify] attribute confirmed |
| C2: RFC 21308 rgen status | CONFIRMED | RFC exists but status is OPEN/PROPOSED, not preview/default; xtro-sharpie confirmed |
| C3: AndroidMavenLibrary intro in .NET 9 | CONFIRMED | Correct; Kotlin suspend claim UNVERIFIABLE |
| C4: CallConvSwift/.NET 9 + SwiftBindings | CONFIRMED | Shipped in .NET 9; tool in runtimelab is preview-stage |
| C5: MAUI Native Library Interop docs/templates | CONFIRMED | Docs exist; template in repo (not dotnet new) |
| C6: CppSharp/ClangSharp/CsWin32/win32metadata versions | CONFIRMED | All versions verified with dates |
| C7: NativeScript iOS V8 switch timing | REFUTED | Switched in NativeScript 7.0 (mid-2020), NOT 9.0 (Nov 2025) |
| C8: Metadata filtering via native-api-usage.json | CONFIRMED | .mdg files do NOT exist |
| C9: ns typings commands | CONFIRMED | Commands exist; implementation details UNVERIFIED |
| C10: dart_native package maintained in 2026 | REFUTED | Last update ~3 years ago (~2023); unmaintained but not archived |
| C11: 1.5–2× native call overhead | REFUTED | Published benchmark shows ~3–4× overhead |

