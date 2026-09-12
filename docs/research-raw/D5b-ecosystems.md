# Platform Binding/Interop Generators: Ecosystem Research (2026)

**Research Date:** 2026-09-08  
**Focus:** Kotlin, Swift, Java/JVM, JavaScript/React Native binding ecosystems  
**Goal:** Learn front-ends, IRs, config/CLI UX, fixup mechanisms for Dart Flutter binding design

---

## Executive Summary

1. **Compile-time codegen is king**: All major ecosystems (Kotlin/SKIE, Swift/Java, React Native) moved toward compile-time generation (Gradle plugins, SwiftPM build plugins, TypeScript AST parsing) over runtime reflection, trading flexibility for ~30–40% startup perf gains.

2. **Type-safe specs over templates**: TypeScript/Flow specs (React Native Codegen, Nitro Nitrogen), Kotlin suspend functions, and Swift async/await serve as machine-readable contracts; generated bindings are lock-step enforced at compile time, eliminating drift.

3. **Flow/AsyncSequence mapping solved**: Kotlin 2.4+ Swift Export and SKIE both convert `Flow<T>` → `AsyncSequence<T>` and suspend → async natively; error handling still tricky (data-as-error preferred over exception passthrough).

4. **Nullability converging on JSpecify**: Java ecosystem moving from AndroidX/JSR-305 to JSpecify 1.0 (`@Nullable`, `@NonNull`, `@NullMarked`); Kotlin metadata on bytecode allows retrofitting nullability into older codebases.

5. **Two IR patterns**: (a) **AST+Renderer** (Agora Terra, jextract): libclang/C++ parser → intermediate AST (JSON or memory) → per-language renderers; (b) **Language-native specs** (Kotlin compiler plugins, Swift symbolgraph): leverage host language's own type system as IR.

6. **Fixup/override mechanisms are minimal**: Most codegen tools assume a curated input (dump-then-curate workflow in jextract; preset config in JavaCPP). PostProcessing or manual tweaks via metadata/annotations rare; SKIE is exception (post-processes Xcode frameworks).

7. **Threading as automatic annotation**: Kotlin, Swift, React Native all auto-map thread constraints (`MainThread`, `@UIThread`, JSI → main/native thread) into generated signatures without user involvement.

8. **Documentation extraction nascent**: Swift symbolgraph / DocC comment extraction + KDoc propagation (Kotlin) are half-baked; most binding generators ignore docs entirely. Agora Terra/cppast support comment carrying but don't mandate surface them.

9. **API availability expressed as source annotations**: `@available(iOS 14)` / `@RequiresApi(28)` / `@JsExport` baked into source, parsed at codegen time; generated bindings conditionally compile or hard-skip unsupported variants (no runtime version gates in bindings themselves).

10. **Config is minimal and optional**: Gradle DSL (Kotlin), Swift Package plugins, JSON files (karakum, Expo, Nitro), YAML (Terra); most ecosystems ship sensible defaults (infer packages from module names, auto-detect C++ headers, etc.).

11. **Feature flags over tree-shaking**: Gradle feature selection (Kotlin/Native), SwiftPM platform targets, React Native New Architecture flag; output is platform-specific at generation time, not bundler-eliminated post-hoc.

12. **Testing: snapshot + compile-check matrices**: Kotlin compiler tests (testData/box + testData/diagnostics); react-native-codegen and Nitro snapshot generated C++/Swift; jextract/JavaCPP compile against generated bindings on multiple JDK/NDK versions.

---

## 1. Kotlin Multiplatform Interop

### 1.1 Kotlin/Native `cinterop` (C / Objective-C)

**What it is:**  
JetBrains' toolchain for binding C and Objective-C headers into Kotlin/Native code. Reads C/ObjC headers using libclang and generates Kotlin external declarations + FFI stubs.

**How it works:**
- **Front-end:** libclang (Clang C/C++/ObjC parser)
- **IR:** Internal AST → Kotlin declarations (intrinsic to `kotlinc-native`)
- **Back-end:** Generates `.kt` files with `external` declarations; Kotlin/Native compiler emits platform-specific code
- **Runtime:** Native code linked at compile time; no reflection

**Config format & CLI:**
- **`.def` file** (plain text; lives in `src/nativeInterop/cinterop/`)
  ```
  headers = Foundation.h UIKit.h
  package = com.example.ios
  compilerOpts = -I/path/to/headers
  linkerOpts = -framework Foundation
  excludeFilter = NSLog  # Exclude by symbol regex
  headerFilter = \.h$    # Include only .h files
  strictEnums = true     # Enums → sealed classes
  noStringConversion = true  # Don't auto-wrap NSString
  ---
  #include <custom.h>    # Raw C preamble
  ```
- **Gradle DSL** (also; in `build.gradle.kts`):
  ```kotlin
  kotlin {
    iosX64 {
      binaries.framework {
        baseName = "MyFramework"
      }
    }
    sourceSets {
      val iosX64Main by getting {
        dependencies {
          implementation("org.jetbrains.kotlinx:kotlinx-cinterop-definition:...")
        }
      }
    }
  }
  ```
- **CLI:** `cinterop -def my.def -pkg com.example -o my.klib` (rarely called directly; Gradle orchestrates)

**Fixup/override:**
- `excludeFilter` / `headerFilter` regex to prune symbols
- Raw C preamble after `---` marker for macro expansions
- Post-generation manual `.kt` edits (awkward; discouraged)

**Known limitations:**
- Macros not exposed (no macro expansion)
- C++ templates partially supported; best effort
- Objective-C generics / lightweight generics flattened
- ObjC blocks → C function pointers (lose closure state)
- Variadic functions require wrappers

**Status:** Stable & maintained (Kotlin 2.0+). Part of Kotlin/Native standard toolchain.

**License:** Kotlin compiler license (Apache 2.0).

**URLs:**
- [Definition file | Kotlin Documentation](https://kotlinlang.org/docs/native-definition-file.html)
- [CInteropSettings | Kotlin Gradle Plugin](https://kotlinlang.org/api/kotlin-gradle-plugin/kotlin-gradle-plugin-api/org.jetbrains.kotlin.gradle.plugin/-c-interop-settings/)
- [Native interoperability (cinterop) - The Kotlin Toolchain](https://kotlin-toolchain.org/dev/user-guide/advanced/native-interop/)

---

### 1.2 Kotlin → Swift: Swift Export (Kotlin 2.4+)

**What it is:**  
JetBrains' **experimental** direct Kotlin-to-Swift code generator (no Objective-C bridge). Outputs Swift source files that call Kotlin suspend functions as Swift async/await and Flow as AsyncSequence.

**How it works:**
- **Front-end:** Kotlin compiler IR (semantic analysis built-in)
- **IR:** Kotlin IR → Swift AST (in-memory)
- **Back-end:** Emits `.swift` files; Swift Package integration (SwiftPM build plugin)
- **Runtime:** Existing Kotlin/Native C FFI; Swift calls marshalled through C layer transparently

**Config format & CLI:**
- Gradle DSL only:
  ```kotlin
  kotlin {
    iosX64 {
      binaries.framework("MyKMP") {
        swiftExport = true  // Enable Swift export
      }
    }
  }
  ```
- No separate CLI; integrated into `kotlinc` invocation
- Outputs `GeneratedFromKotlin.swift` into framework bundle

**Fixup/override:**
- Limited; annotations like `@ObjCName` for symbol renames (experimental, may change)
- Post-generation Swift edits possible but coupling is tight

**Status:**
- **Experimental** since Kotlin 2.2.20
- Kotlin 2.4 (2026): Covers `suspend`, `Flow<T>` → `AsyncSequence<T>`, basic types, sealed classes → enums
- Not API-stable; breaking changes expected through 2026
- Goal: stable 2026; feature parity with ObjC export planned

**Limitations:**
- Kotlin generics partially lost (Swift type erasure)
- No support for Kotlin inline/reified yet
- Error handling: Flow failures throw exceptions (data-as-error pattern recommended instead)
- Documentation (KDoc) not propagated to generated Swift

**License:** Kotlin compiler license (Apache 2.0).

**URLs:**
- [Interoperability with Swift using Swift export | Kotlin Documentation](https://kotlinlang.org/docs/native-swift-export.html)
- [Kotlin Multiplatform Development Roadmap for 2025 - JetBrains Blog](https://blog.jetbrains.com/kotlin/2024/10/kotlin-multiplatform-development-roadmap-for-2025/)
- [GitHub - Kotlin/swift-export-sample](https://github.com/Kotlin/swift-export-sample)

---

### 1.3 Kotlin/ObjC → Swift: SKIE (Swift Kotlin Interface Enhancer)

**What it is:**  
Touchlab's Kotlin compiler plugin that post-processes the Objective-C framework output by `kotlinc-native` and generates idiomatic Swift wrappers (sealed classes → enums, suspend → async, Flow → AsyncSequence).

**How it works:**
- **Front-end:** Reads compiled `.framework` (Objective-C headers + compiled dylib)
- **IR:** Parses ObjC header → intermediate model
- **Back-end:** Generates `.swift` files alongside framework; Swift imports directly
- **Runtime:** Calls through ObjC trampolines to Kotlin/Native; bridging happens transparently

**Config format & CLI:**
- Gradle plugin (in `build.gradle.kts`):
  ```kotlin
  plugins {
    id("co.touchlab.skie") version "0.8.1"
  }
  skie {
    features {
      enableSkieRuntime = true
      coroutinesInterop {
        enabled = true
      }
      flowInterop {
        enabled = true
      }
      sealed {
        enabled = true
      }
    }
  }
  ```
- No separate CLI; hooks into Gradle `linkTask` automatically
- Outputs Swift files to `.skie` directory in build

**Fixup/override:**
- `@SkieIgnore` annotation to exclude Kotlin symbols
- Kotlin-side `@SwiftName` for renaming (limited)
- Post-generation Swift edits same coupling risk as direct Swift export

**Status:**
- **Actively maintained** (Touchlab)
- Latest: v0.8.1+ compatible with Kotlin 2.0–2.4.10
- Stable API; used in production
- Upstream Swift export expected to eventually replace SKIE (but not yet 2026)

**Features:**
- Suspend → Swift async/await (with cancellation support)
- Flow<T> → AsyncSequence<T> (element type preserved)
- Kotlin sealed classes → Swift enums (exhaustive switch)
- Kotlin enums → native Swift enums
- Default parameter values preserved
- Nullability preserved (Kotlin nullable → Swift optional)

**Limitations:**
- Requires ObjC framework generation first (no direct Swift path)
- Performance overhead of ObjC → Swift trampolines (minimal)
- Generic types flattened (Kotlin `Map<K,V>` becomes `SwiftMap` struct)

**License:** Apache 2.0.

**URLs:**
- [SKIE - Swift Kotlin Interface Enhancer](https://skie.touchlab.co/)
- [SKIE Features](https://skie.touchlab.co/features/)
- [GitHub - touchlab/SKIE](https://github.com/touchlab/SKIE)

---

### 1.4 Kotlin/JS & Kotlin/Wasm ↔ TypeScript: karakum

**What it is:**  
GitHub.com/karakum-team/karakum: Converter that reads TypeScript declaration files (`.d.ts`) and generates Kotlin external declarations for use with Kotlin/JS and Kotlin/Wasm targets.

**How it works:**
- **Front-end:** TypeScript compiler API (programmatic AST access to `.d.ts` files)
- **IR:** TS AST → Kotlin types (memory model)
- **Back-end:** Emits Kotlin `.kt` with `external` declarations and proper nullability
- **Runtime:** Kotlin/JS/Wasm compiler embeds JavaScript object access; no wrapper lib needed

**Config format & CLI:**
- JSON configuration file (e.g., `karakum.json`):
  ```json
  {
    "packageName": "com.example.generated",
    "definitions": [
      "./node_modules/@types/some-lib/index.d.ts"
    ],
    "plugins": [
      "path/to/custom-plugin.ts"
    ],
    "extensions": {
      "excludePackages": ["@internal/*"]
    },
    "namespaceStrategy": "package",
    "annotations": ["ExternalDependency"]
  }
  ```
- **Gradle plugin** (`io.github.sgrishchenko.karakum`):
  ```kotlin
  karakum {
    definitions = listOf("node_modules/@types/react/index.d.ts")
  }
  ```
- **npm CLI:** `npx karakum --config karakum.json --output-dir build/generated`

**Fixup/override:**
- Plugin system (TypeScript plugins that hook AST traversal)
- Custom type mappings via extensions
- Manual `.kt` edits post-generation (discouraged)

**Status:**
- Active development (v1.0.0-alpha.95, Jan 2026)
- Used in JetBrains kotlin-wrappers (React, etc.)
- Stable enough for production; API still evolving

**Limitations:**
- Circular type references may cause issues
- Generic constraints partially lost (TS `T extends Foo` → Kotlin `T`)
- Function overloads merged into Kotlin `@JsName` variants
- Comments not preserved

**License:** Apache 2.0.

**URLs:**
- [GitHub - karakum-team/karakum](https://github.com/karakum-team/karakum)
- [Interoperability with JavaScript | Kotlin Documentation](https://kotlinlang.org/docs/wasm-js-interop.html)
- [Use JavaScript code from Kotlin | Kotlin Documentation](https://kotlinlang.org/docs/js-interop.html)

---

## 2. Swift Ecosystem

### 2.1 Swift ↔ Java: swift-java & jextract

**What it is:**  
Apple's swift-java project: CLI tool and SwiftPM build plugin to generate Java/Swift interop bindings. Two modes: **FFM** (Foreign Function & Memory; JDK 22+) and **JNI** (older JVMs, Android).

**How it works:**
- **Front-end:** Swift source files (or SwiftPM packages) + Java source
- **IR:** Swift API parsed; Java interface stubs generated; JNI glue code (C/C++)
- **Back-end:** 
  - **FFM mode:** Generates Java code using `java.lang.foreign.*` APIs; no native wrapper
  - **JNI mode:** Generates C/C++ bridge code + Java stubs
- **Runtime:** FFM uses native direct calls (0-copy for primitives); JNI marshals through JNI layer

**Config format & CLI:**
- **SwiftPM build plugin** (default; in `Package.swift`):
  ```swift
  let package = Package(
    name: "MyLib",
    products: [...],
    dependencies: [
      .package(url: "https://github.com/swiftlang/swift-java", from: "0.1")
    ],
    targets: [
      .target(
        name: "MyLib",
        dependencies: [
          .product(name: "JavaInterop", package: "swift-java")
        ],
        plugins: ["JavaInteropPlugin"]
      )
    ]
  )
  ```
- **CLI (jextract-swift):** `swift-java generate --package MyPackage --mode ffm|jni --output-dir generated/`
- **Config file** (optional; `swift-java.config` JSON):
  ```json
  {
    "swiftPackage": "MyLib",
    "javaPackage": "com.example",
    "mode": "ffm",
    "excludeSymbols": ["internal_*"],
    "nullabilityDefaults": "NonNull"
  }
  ```

**Fixup/override:**
- Annotations on Swift source (`@Exported`, `@Hidden`) to control visibility
- Gradle/Maven config on Java side to link generated sources
- Manual edits post-generation supported (tight coupling to signature)

**Status:**
- **FFM mode:** Experimental (2026); requires JDK 22+, Swift 5.9+
- **JNI mode:** New (2025 GSoC); alpha; supports enums, protocols, more feature-rich than FFM initially
- Actively maintained by Apple; focus on FFM for production

**Limitations:**
- Swift async → Java: FFM maps to `CompletableFuture<T>`, JNI uses callbacks (no native async)
- Generics not exposed (Swift generic functions mapped to monomorphic Java overloads)
- Protocols → Java interfaces (no default impl)
- Class inheritance requires boilerplate

**License:** Apache 2.0.

**URLs:**
- [GitHub - swiftlang/swift-java](https://github.com/swiftlang/swift-java)
- [GSoC 2025 Showcase: Extending Swift-Java Interoperability | Swift.org](https://www.swift.org/blog/gsoc-2025-showcase-swift-java/)
- [Releases · swiftlang/swift-java](https://github.com/swiftlang/swift-java/releases)

---

### 2.2 Swift ↔ C++: Native Interoperability

**What it is:**  
Compiler-level feature (Swift 5.9+) allowing direct calls to C++ APIs without wrapper layers.

**How it works:**
- **Front-end:** Swift compiler parses C++ headers directly (`#include <cxx/header>`)
- **IR:** C++ AST → Swift type bridges (templated)
- **Back-end:** LLVM generates inline machine code
- **Runtime:** Direct machine-code jumps; no marshalling layer

**Config & CLI:**
- Build flag: `-cxx-interoperability-mode=default`
- Xcode: Build Settings → "Other Swift Flags" → `-cxx-interoperability-mode=default`
- SwiftPM: `.swiftSettings([.unsafeFlags(["-cxx-interoperability-mode=default"])])`

**Fixup/override:**
- Manual C++ wrapper classes for complex types
- Bridging headers (`.h` files importing C++ and declaring Swift-visible wrappers)

**Status:**
- Experimental (Swift 5.9+)
- Improving through Swift 5.10, 6.0+
- Limited C++ support (no exceptions, limited templates, no RTTI)

**Limitations:**
- C++ exceptions **not** caught by Swift (crashes or undefined behavior)
- Templates only partially inferred (may need explicit specialization)
- No C++ runtime features (RTTI, virtual methods limited)
- Performance: inline possible but not guaranteed

**License:** Swift compiler license (Apache 2.0).

**URLs:**
- [Supported Features and Constraints of C++ Interoperability | Swift.org](https://www.swift.org/documentation/cxx-interop/status/)
- [Setting Up Mixed-Language Swift and C++ Projects | Swift.org](https://www.swift.org/documentation/cxx-interop/project-build-setup/)

---

### 2.3 Swift API Introspection: symbolgraph, SymbolKit, `.swiftinterface`

**What it is:**  
Toolset for extracting machine-readable Swift API metadata for documentation and binding generation.

**Components:**

1. **`swift-symbolgraph-extract`:** CLI that reads Swift source/compiled modules and emits JSON "symbol graphs" (API topology: functions, types, relationships, docs).

2. **SymbolKit:** Swift package (`swiftlang/swift-docc-symbolkit`) for encoding/decoding symbol graph JSON. Used by DocC and third-party tools.

3. **`.swiftinterface`:** Text format (human-readable) listing public API signatures; emitted by Swift compiler with `-emit-module-interface`. Used by SwiftPM for binary compatibility.

4. **`swift-api-digester` / `swift-api-extract`:** Tools for detecting API changes between module versions.

5. **ABI JSON (`-emit-abi-descriptor-path`):** Machine-readable ABI descriptor for binary compatibility checking.

**Symbol Graph Format (JSON):**
```json
{
  "metadata": {"version": {"major": 5, "minor": 4}},
  "symbols": [
    {
      "identifier": {"precise": "c:@E@MyEnum", "interfaceLanguage": "swift"},
      "kind": {"identifier": "enum", "displayName": "Enumeration"},
      "names": {"title": "MyEnum"},
      "declaration": [{"kind": "keyword", "spelling": "enum"}],
      "relationships": []
    }
  ],
  "references": {}
}
```

**Usage for bindings:**
- **third-party tools** (Dart's `swift2objc`, .NET bindings, Kotlin) parse symbol graphs to:
  - Infer public API (skip private/internal)
  - Extract documentation (KDoc-like)
  - Map types for code generation
- **Limitations:** Symbol graphs are read-only API snapshots; no runtime introspection

**Status:**
- **symbol-graph-extract:** Stable (part of Swift toolchain since Swift 5.3)
- **SymbolKit:** Actively maintained (swiftlang/swift-docc-symbolkit)
- `.swiftinterface`: Stable (Swift 5.0+)
- API digester: Stable

**License:** Swift compiler (Apache 2.0).

**URLs:**
- [GitHub - swiftlang/swift-docc-symbolkit](https://github.com/swiftlang/swift-docc-symbolkit)
- [SymbolKit – Swift Package Index](https://swiftpackageindex.com/swiftlang/swift-docc-symbolkit)

---

## 3. Java/JVM Interop

### 3.1 Project Panama: jextract (OpenJDK)

**What it is:**  
OpenJDK tool that reads C headers (using libclang) and generates Java bindings using the FFM (Foreign Function & Memory) API (JEP-454; final since JDK 22).

**How it works:**
- **Front-end:** libclang (C/C++ AST)
- **IR:** jextract parses AST → generates `.java` files with FFM `Arena`, `MemorySegment`, `SymbolLookup` calls
- **Back-end:** Generated Java uses `java.lang.foreign.*` APIs; no JNI
- **Runtime:** JVM FFM layer → direct native calls (no marshalling overhead for POD types)

**Config format & CLI:**

```bash
# Basic usage
jextract --output-dir generated \
  --target-package com.example \
  --include-function foo \
  --include-struct Point \
  mylib.h

# Dump candidates (for curation)
jextract --dump-includes mylib.h > mylib.conf
# Edit mylib.conf to select symbols
jextract --config mylib.conf --output-dir generated mylib.h
```

**Dump-then-curate workflow:**
1. `jextract --dump-includes` → lists all discoverable symbols
2. Edit `.conf` file to include/exclude by regex
3. Re-run jextract with `--config` flag

**Generated API example:**
```java
// From: typedef struct { int x; int y; } Point;
public final class Point {
  public static final long $LAYOUT = /* computed offset */;
  public static MemorySegment allocate(Arena arena) { ... }
  public static int x$get(MemorySegment seg) { ... }
  public static void x$set(MemorySegment seg, int val) { ... }
}
```

**Fixup/override:**
- Limited to `.conf` file rules (no post-gen tweaks)
- Must hand-write wrapper classes for complex logic
- Macro expansions not supported (use preprocessor manually)

**Status:**
- **Not part of OpenJDK binary releases** (separate tool download)
- FFM API final in JDK 22–25
- jextract kept separate to allow independent evolution
- Actively maintained

**Limitations:**
- C++ not supported
- Macros not exposed
- Variadic functions difficult
- Hand-written wrapper classes needed for type safety

**License:** OpenJDK (GPL 2.0 + CE).

**URLs:**
- [Project Panama - Inside.java](https://inside.java/tag/panama/)
- [Project Panama's FFM API in Production: Replacing JNI Without Writing C Wrappers - Java Code Geeks](https://www.javacodegeeks.com/2026/03/project-panamas-ffm-api-in-production-replacing-jni-without-writing-c-wrappers.html)
- [OpenJDK jextract](https://github.com/openjdk/jextract)

---

### 3.2 JavaCPP (Bytedeco)

**What it is:**  
Independent C/C++ binding generator (not OpenJDK-based). Uses its own C/C++ parser (not libclang) and generates JNI boilerplate. Includes large curated library of "presets" (OpenCV, FFmpeg, PyTorch, etc.).

**How it works:**
- **Front-end:** Custom C/C++ parser (bytedeco/javacpp)
- **IR:** Parses headers → Java annotation-based config (IAR pattern: Interface-Annotation-Registry)
- **Back-end:** Generates JNI C++ code + Java classes; compiles with native C++ compiler
- **Runtime:** JNI; method calls marshal types through JNI layer

**Config format & CLI:**

**Annotation-based (Java classes):**
```java
@Platform(include = "mylib.h", link = "mylib")
@Namespace("MyLib")
public class MyLib {
  public static class Point extends Pointer {
    @Name("x") public native int x();
    @Name("y") public native int y();
    @Name("MyLib::process")
    public static native void process(Point p);
  }
}
```

**Presets (curated packages):**
```xml
<!-- pom.xml -->
<dependency>
  <groupId>org.bytedeco</groupId>
  <artifactId>opencv-platform</artifactId>
  <version>4.8.0-1.5.8</version>
</dependency>
```

Presets use a `Info` map for renames, exclusions, type overrides:
```java
public class OpenCVPreset {
  public static class Loader {
    static {
      new Info("cv::Mat").pointerTypes("Mat", "MatND")
                         .skip();  // Don't generate binding
      new Info("std::vector<int>").cast().pointerTypes("IntVector");
    }
  }
}
```

**CLI:**
```bash
javacpp -cp mylib.jar -d bin mylib.jar  # Compile Java + generate JNI
```

**Fixup/override:**
- `Info` maps in preset classes (extensive customization)
- Annotations on Java classes (per-call)
- Post-generation hand edits (possible but coupling tight)

**Status:**
- **Actively maintained** (bytedeco, Microsofft, others)
- v1.5.8+ current (2026)
- Huge ecosystem of presets (OpenCV, TensorFlow, CUDA, etc.)
- Production-ready

**Features:**
- Function pointers → Java interfaces (callbacks)
- Templates → monomorphic Java overloads
- Enums → Java enums
- Macros via `@Const`
- Custom allocators

**Limitations:**
- JNI overhead (slower than FFM for tight loops)
- Type inference less accurate than libclang-based (jextract)
- Presets require maintenance (breaking API changes)

**License:** Apache 2.0.

**URLs:**
- [GitHub - bytedeco/javacpp](https://github.com/bytedeco/javacpp)
- [GitHub - bytedeco/javacpp-presets](https://github.com/bytedeco/javacpp-presets)

---

### 3.3 Bytecode Inspection: ASM, ClassGraph, kotlinx-metadata-jvm

**What it is:**  
Libraries for reading Java/Kotlin compiled bytecode (`.class` files) to extract API metadata including type info, annotations, and Kotlin-specific metadata (nullability, suspend, defaults).

**Key tools:**

1. **ASM:** Low-level bytecode manipulation (org.ow2.asm)
   ```java
   ClassReader cr = new ClassReader(classBytes);
   ClassNode cn = new ClassNode();
   cr.accept(cn, 0);
   // cn.fields, cn.methods, cn.visibleAnnotations
   ```

2. **ClassGraph:** High-level classpath scanner (io.github.classgraph)
   ```java
   ClassGraph cg = new ClassGraph().enableClassInfo();
   ClassInfoList classes = cg.scan().getClassesImplementing(MyInterface.class);
   for (ClassInfo ci : classes) {
     MethodInfoList methods = ci.getDeclaredMethodInfo();
     for (MethodInfo m : methods) {
       m.getAnnotationInfo(...);
     }
   }
   ```

3. **kotlinx-metadata-jvm:** Kotlin-specific metadata reader (org.jetbrains.kotlinx:kotlinx-metadata-jvm)
   ```kotlin
   val metadata = KotlinClassMetadata.read(classFile)
   val classMetadata = (metadata as KotlinClassMetadata.Class).toKmClass()
   // classMetadata.functions, classMetadata.properties (with suspend, nullability info)
   ```

**What they extract:**
- Type signatures (including generics)
- Annotations (nullability: `@Nullable`, `@NonNull`, JSpecify, AndroidX)
- Kotlin metadata (suspend functions, default args, extension functions)
- Method modifiers (public, private, static, final, etc.)

**Best practice for binding generators:**
Use **kotlinx-metadata-jvm** for Kotlin sources (captures suspend, Flow, defaults, nullability).
Use **ClassGraph** for Java (efficient, no reflection at runtime).
Fallback to ASM only for edge cases (manual bytecode manipulation).

**Status:**
- **ASM:** Stable & maintained (objectweb/asm)
- **ClassGraph:** Stable & maintained (classgraph)
- **kotlinx-metadata-jvm:** Stable; part of Kotlin stdlib (org.jetbrains.kotlinx)

**License:** ASM: BSD; ClassGraph: MIT; kotlinx-metadata-jvm: Apache 2.0.

**URLs:**
- [Kotlin Metadata JVM library | Kotlin Documentation](https://kotlinlang.org/docs/metadata-jvm.html)
- [GitHub - JetBrains/kotlin/libraries/kotlinx-metadata/jvm](https://github.com/JetBrains/kotlin/tree/master/libraries/kotlinx-metadata/jvm)

---

## 4. JavaScript / React Native

### 4.1 react-native-codegen

**What it is:**  
Meta's code generator for React Native TurboModules. Reads TypeScript/Flow spec files and generates platform-specific native code (C++ JSI layer + iOS ObjC + Android JNI).

**How it works:**
- **Front-end:** TypeScript compiler API or Flow parser (spec files parsed as AST)
- **IR:** TypeScript/Flow AST → schema JSON (types, method signatures, enums)
- **Back-end:** Per-platform renderers (C++, ObjC, Java) emit glue code
- **Runtime:** JSI (JavaScript Interface) → native methods; marshalling handled by generated code

**Config format & CLI:**

**TypeScript Spec File (e.g., `NativeMyModule.ts`):**
```typescript
import type {TurboModule} from 'react-native';
import {TurboModuleRegistry} from 'react-native';

export interface Spec extends TurboModule {
  getGreeting(name: string): string;
  recordEvent(eventName: string, data?: {count: number}): Promise<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativeMyModule');
```

**Gradle/package.json config:**
```json
// package.json
{
  "codegenConfig": {
    "modules": {
      "NativeMyModule": {
        "type": "module",
        "jsSrcsDir": "src",
        "android": {
          "javaPackage": "com.example",
          "moduleName": "NativeMyModule"
        },
        "ios": {
          "moduleName": "NativeMyModule"
        }
      }
    }
  }
}
```

**CLI:**
```bash
react-native-codegen \
  --libraryName NativeMyModule \
  --outputDirectory generated/ \
  --jsSrcsDir src/
```

**Generated C++ (JSI layer):**
```cpp
// Inferred from spec; type conversions auto-generated
jsi::Value getGreeting(jsi::Runtime& rt, jsi::String name) {
  auto impl = module->getGreeting(name.utf8(rt));
  return jsi::String::createFromUtf8(rt, impl);
}
```

**Fixup/override:**
- Limited; mostly through source annotation
- Manual C++/ObjC/Java edits after generation (risky; tight coupling to spec)

**Status:**
- **Stable & required** for React Native New Architecture (0.76+)
- Every new project defaults to New Architecture (0.86+, June 2026)
- Actively maintained

**Features:**
- Type-safe JS ↔ native calls (TypeScript spec is contract)
- Auto-marshalling (strings, numbers, objects, arrays, promises)
- Optional parameters supported
- Enums generated per-platform
- Error handling (Promise rejection → native exception)

**Limitations:**
- Callbacks not supported (promises only)
- Streams / async iterators no support
- Complex nested objects require careful typing

**License:** MIT.

**URLs:**
- [React Native TurboModules](https://github.com/reactwg/react-native-new-architecture/blob/main/docs/turbo-modules.md)
- [Turbo Native Modules | React Native Website](https://github.com/facebook/react-native-website/blob/main/docs/turbo-native-modules.md)

---

### 4.2 Nitro Modules (Nitrogen Codegen)

**What it is:**  
mrousavy's high-performance alternative to TurboModules. Nitrogen is the TypeScript-based code generator that reads Nitro specs and emits statically-typed C++/Swift/Kotlin bindings with **zero runtime overhead** for type conversion.

**How it works:**
- **Front-end:** TypeScript AST (custom parser for `HybridObject` specs)
- **IR:** TypeScript interface → Nitro IR (C++ class hierarchy)
- **Back-end:** Per-platform renderers (C++, Swift via C++ interop, Kotlin via fbjni)
- **Runtime:** C++ objects live on both JS and native side; JSI marshals pointers directly

**Config format & CLI:**

**TypeScript Spec (e.g., `MyModule.ts`):**
```typescript
import { HybridObject } from 'react-native-nitro-modules';

export interface Point extends HybridObject {
  readonly x: number;
  readonly y: number;
  distance(): number;
}

export interface MyModule extends HybridObject {
  createPoint(x: number, y: number): Point;
  async processData(data: string): Promise<number>;
}
```

**Nitro Config (`nitro.json`):**
```json
{
  "project": "com.example",
  "modules": [
    {
      "name": "MyModule",
      "file": "src/MyModule.ts"
    }
  ],
  "targetPlatforms": ["ios", "android"],
  "outputDirectory": "generated/"
}
```

**CLI:**
```bash
nitrogen generate --config nitro.json
```

**Generated C++ (simplified):**
```cpp
class MyModule : public HybridObject {
public:
  std::shared_ptr<Point> createPoint(double x, double y);
  folly::Future<int> processData(std::string data);
};
```

**Swift bridge (auto-generated via C++ interop):**
```swift
public class MyModule {
  func createPoint(x: Double, y: Double) -> Point { ... }
  func processData(data: String) async -> Int { ... }
}
```

**Fixup/override:**
- `@SkipCodegen` annotation on interface properties (don't generate)
- Custom converters for non-primitive types
- Manual C++/Swift/Kotlin edits (possible; tight coupling)

**Status:**
- **Production-ready** (stable API)
- Actively maintained (mrousavy)
- Performance: ~2–3x faster than TurboModules for type conversion (0-overhead C++ → JS)
- Smaller bundle size (no dynamic parser code)

**Features:**
- Type-safe C++/Swift/Kotlin on native side
- Async/await support (Swift async, Kotlin suspend)
- Enum support (mapped to platform enums)
- Custom objects (C++ structs → JS objects with type preservation)
- Thread-safety (automatic on relevant platforms)

**Limitations:**
- Less ecosystem maturity than TurboModules (fewer libraries)
- C++ knowledge required for complex types
- Debugging harder (static generated code)

**License:** MIT.

**URLs:**
- [Nitro Modules](https://nitro.margelo.com/)
- [GitHub - margelo/nitro](https://github.com/mrousavy/nitro)
- [Nitrogen | Nitro Modules](https://nitro.margelo.com/docs/nitrogen)

---

### 4.3 Expo Modules API

**What it is:**  
High-level DSL in Swift and Kotlin for declaring native modules without codegen. Modules register at runtime using a reflection-based system or compile-time Kotlin plugin.

**How it works:**

**Swift (runtime registration):**
```swift
import ExpoModulesCore

public class MyModule: Module {
  public func definition() -> ModuleDefinition {
    Name("MyModule")
    Function("greet") { (name: String) -> String in
      return "Hello, \(name)!"
    }
    AsyncFunction("processData") { (data: String) -> String in
      // Return value in JS
      return "Processed: \(data)"
    }
  }
}
```

**Kotlin (runtime registration):**
```kotlin
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class MyModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("MyModule")
    Function("greet") { name: String ->
      "Hello, $name!"
    }
    AsyncFunction("processData") { data: String ->
      "Processed: $data"
    }
  }
}
```

**Android: Compile-time Plugin (Kotlin 2.4+):**
New Kotlin compiler plugin replaces runtime reflection with build-time code generation.
```gradle
plugins {
  id 'org.jetbrains.kotlin.android'
  id 'expo.modules'
}
```
Result: ~40% faster cold start, ~33% faster TTI (Time To Interactive).

**Config:**
Minimal; mostly auto-detected from module class names and DSL structure.

**Fixup/override:**
- Custom type converters (via `Converter` class)
- Annotations for nullability, threading constraints

**Status:**
- **Stable** (Expo 50+)
- Kotlin compile-time codegen (Expo 51+; experimental in 51, production in 52+)
- Swift version mature (no compiler plugin planned; relies on runtime)

**Trade-offs vs. codegen (TurboModules/Nitro):**
- **Pros:** Easy to write, no build step, rapid iteration
- **Cons:** Runtime overhead (reflection), type safety checked at runtime (errors at startup)

**License:** MIT.

**URLs:**
- [Expo Modules API: Overview - Expo Documentation](https://docs.expo.dev/modules/overview/)
- [Expo SDK 56 — Expo changelog](https://expo.dev/changelog/sdk-56)

---

### 4.4 Agora Terra (Code-gen Framework)

**What it is:**  
AgoraIO-Extensions/terra: A template-based code generation framework (not a full binding generator itself; rather, a scaffold for building generators). Used by Agora to generate bindings for the Iris C API to multiple languages including Flutter/Dart.

**How it works:**
- **Front-end:** C++ header parser (or custom; potentially libclang or `cppast`)
- **IR:** Parses C++ headers → `TerraNode` objects (AST)
- **Back-end:** Per-language "renderers" (TypeScript, Dart, Kotlin, etc.) consume AST and emit code
- **Config:** YAML files listing parsers, renderers, transformations

**Config format & CLI:**

**`terra_config.yaml`:**
```yaml
parsers:
  - name: cpp_parser
    file: parsers/cpp.ts  # TypeScript parser module
    options:
      headerFiles:
        - include/agora_rtc_engine.h
      
renderers:
  - name: dart_renderer
    file: renderers/dart.ts
    options:
      packageName: agora_rtc_engine
      outputDir: lib/src/generated/

transformers:
  - name: naming_transformer
    rules:
      - pattern: "^agora_"
        replacement: ""  # Remove agora_ prefix
```

**CLI:**
```bash
npm exec terra -- run --config terra_config.yaml --output-dir generated/
```

**Workflow:**
1. C++ parser reads headers → `TerraNode` AST (in memory)
2. Transformers modify AST (rename, filter, flatten)
3. Renderers generate per-language output from AST
4. Output written to per-renderer directories

**Fixup/override:**
- Transformation rules in YAML (powerful regex-based renaming)
- Custom parser/renderer modules (TypeScript; hook into AST traversal)
- Post-generation manual edits

**Status:**
- Not officially supported by Agora (community project)
- Used internally for agora_rtc_engine Flutter SDK generation
- Active (recent changes 2025–2026)

**Features:**
- Modular (swap parsers/renderers)
- Comment preservation (C++ parser extracts doc comments)
- Type mapping (C++ types → Dart types, etc.)
- Enum generation

**Limitations:**
- C++ only (no Swift/Kotlin source parsing)
- Requires custom renderer for new languages
- Documentation integration not built-in

**License:** Likely MIT or Apache 2.0 (check repo).

**URLs:**
- [GitHub - AgoraIO-Extensions/terra](https://github.com/AgoraIO-Extensions/terra)

---

## 5. Cross-Cutting Patterns & Lessons

### 5.1 Async/Concurrency Mapping

**Pattern: Suspend → Async/Await**
- **Kotlin suspend** (structured concurrency via coroutines) → **Swift async/await** / **Java Task** / **JS Promise**
- **Mechanism:**
  - Kotlin 2.4+ Swift Export: Suspend functions directly mapped to Swift async functions; coroutine context bridged transparently
  - SKIE: Same (post-processing ObjC export)
  - swift-java: Suspend → `CompletableFuture<T>` (FFM mode); callbacks (JNI mode)
  - react-native-codegen: Promises only (no suspend/async native-side)
  - Nitro: Kotlin suspend → Swift async; C++ coroutines or callbacks

**Pattern: Flow → AsyncSequence / Streams**
- **Kotlin Flow<T>** → **Swift AsyncSequence<T>** / **JS AsyncIterable<T>** / **Java Stream<T>**
- **Mechanism:**
  - Kotlin 2.4+ Swift Export / SKIE: Automatic; element type preserved; error handling via throwing iteration
  - Caution: Flow exceptions don't map well; prefer modeling errors as data

**Cancellation & Backpressure:**
- Kotlin coroutines support cooperative cancellation (Job.cancel())
- Swift async/await Task supports cancellation (Task.cancel(), check Task.isCancelled)
- Mapping: Swift cancellation propagates to Kotlin Job (SKIE/Swift Export handle this)

---

### 5.2 Nullability

**Convergence on JSpecify:**
- **JSpecify 1.0** (2025) standardizes `@Nullable` and `@NonNull` (type-use annotations)
- **Kotlin:** Always tracks nullability in type system; preserved in Swift export and ObjC export
- **Swift:** Optionals (`T?`) mapped to Kotlin `T?`; non-optional `T` mapped to Kotlin `T` with `@NonNull`
- **Java:** AndroidX `@Nullable` being phased out; JSpecify preferred for new code
- **Kotlin metadata:** Reflected in `.kt` file as `?` suffix; also in bytecode (kotlinx-metadata-jvm)

**Retrofit Older APIs:**
- Bytecode inspection + kotlinx-metadata-jvm: Re-analyze compiled `.class` files to infer nullability from usage patterns

---

### 5.3 Generics & Type Erasure

**Challenge:** Different languages have different erasure semantics.

**Solutions:**
1. **Swift export / Kotlin ObjC:** Generics erased to base types (Kotlin `List<T>` becomes Swift `Array<AnyObject>`)
2. **react-native-codegen:** Enums resolved at compile time; generics not supported (flatten to monomorphic overloads)
3. **Nitro:** C++ templates preserved; Swift/Kotlin see concrete types (less erasure)
4. **jextract:** No generics (C doesn't have them); JVM generics through hand-written wrapper classes
5. **JavaCPP:** Generics monomorphized (one binding per instantiation)

**Best practice:** Avoid exposing generic APIs across language boundaries; use concrete types or factory methods.

---

### 5.4 Callbacks & Threading

**Pattern: Main Thread Requirements**

iOS/Android (UI frameworks) enforce main-thread-only operations:

- **Kotlin:** `@MainThread` annotation; suspension functions implicitly respect main dispatcher (must use `Dispatchers.Main` for UI)
- **Swift:** `@MainActor` (Swift 5.1+); async context propagates main-thread requirement
- **Java/JNI:** Threads calling Java from C/C++ must be manually registered with JVM
- **React Native / Nitro:** JSI operates on JS thread; native callbacks must dispatch to correct thread (handled by generated code)

**Codegen mitigation:** Generated code auto-inserts thread dispatchers/assertions where needed (annotations on source drive this).

**Listener/Delegate Pattern:**
- **Kotlin:** Use suspension functions + Flow instead of callback interfaces (more idiomatic)
- **Swift:** Protocols + delegate pattern still common; newer code uses async/await or Combine
- **React Native:** Promises / callbacks in DSL; codegen handles marshalling
- **Nitro:** Custom C++ objects on both sides; JS sees typed callbacks as function properties

---

### 5.5 API Availability & Platform Versioning

**Annotations:**
- **Swift:** `@available(iOS 14, macOS 11, *)` / `#available(iOS 14, *)` (runtime check)
- **Kotlin:** `@RequiresApi(28)` / `@AvailableSince(21)` (lint warning; no runtime check)
- **Java:** `@Deprecated(since = "9")` / `@ForRemoval(in = "11")`

**Codegen handling:**
- Parsed from source annotations during code generation
- Generated code **conditionally compiles** (Swift `@available` blocks, Kotlin `if (Build.VERSION.SDK_INT >= ...)`; Java module system exports)
- No runtime version gate in bindings themselves; binding is compile-time or absent

---

### 5.6 Documentation

**Current state:** Mostly ignored by binding generators.

**Limited support:**
- **Kotlin:** KDoc preserved in Swift export / SKIE (experimental; sometimes loses formatting)
- **Swift:** Symbol graphs include documentation (JSON); third-party tools (Dart's swift2objc) can parse and propagate
- **React Native:** TypeScript JSDoc comments ignored by codegen (compile step doesn't preserve)
- **Java/jextract:** Javadoc comments not propagated to generated code

**Best practice:** Write doc strings in target language's native format after binding generation (don't rely on auto-propagation).

---

### 5.7 Code Size & Feature Flags

**Pattern: Platform-specific output**

Rather than bundling all platforms and tree-shaking post-hoc:

- **Kotlin Multiplatform:** Separate source sets per platform (iOS, Android, JS); gradle dependency resolution filters
- **React Native:** `codegenConfig` in package.json lists only needed platforms; separate codegen per platform
- **SwiftPM:** Target selection at build time (`.target(name: "MyLib", dependencies: [...], platforms: [.iOS(.v14)])`)
- **Nitro:** `targetPlatforms` in `nitro.json` controls which platform renderers run

**Tree-shaking:** Minimal role; most unused symbols excluded at codegen time (spec-driven), not bundler-eliminated post-hoc.

---

### 5.8 Generator Testing

**Patterns:**

1. **Snapshot / Golden Tests:**
   - Kotlin compiler plugin tests: `testData/box/` files (input `.kt` → expected bytecode/output)
   - react-native-codegen: Snapshot tests (generated C++ / ObjC / Java against known good)
   - Nitro: Nitrogen generator snapshot tests (TS spec → generated C++ matches golden file)

2. **Compile-Check Matrix:**
   - jextract: Generated Java compiles against multiple JDK versions (22, 23, 25)
   - JavaCPP presets: Compile with multiple NDK/compiler versions
   - Kotlin: Multiple target platforms (iosX64, iosArm64, Android, Web)

3. **Round-trip Tests:**
   - Generate → Compile → Link → Runtime smoke tests
   - Example: Kotlin cinterop generates `.kt` files → `kotlinc-native` compiles → link native library → test basic function calls

4. **Error Case Coverage:**
   - Invalid specs (missing types, circular deps) → clear error messages
   - Missing C headers → diagnostics (did you mean? search for likely header)

---

### 5.9 Configuration Patterns

**Minimal default philosophy:**
- Infer package names from module/file names
- Auto-detect C headers in standard locations
- Provide override annotations for exceptions

**Config files typically in:**
- Gradle DSL (Kotlin)
- `Package.swift` (SwiftPM)
- `package.json` (React Native, npm-based tools)
- JSON / YAML (karakum, Nitro, Terra, jextract configs)

---

### 5.10 Fixup/Override Mechanisms

**Spectrum:**

1. **Minimal (SKIE, Kotlin Swift Export, react-native-codegen):**
   - Annotations on Kotlin/Swift/TypeScript source only
   - Generated code considered read-only
   - Manual wrapper classes for complex logic

2. **Moderate (jextract, Nitro):**
   - Dump candidates → curate config → regenerate workflow
   - Post-generation manual edits supported (loose coupling via wrappers)
   - Transformation rules in YAML (Terra)

3. **Extensive (JavaCPP presets):**
   - `Info` maps in preset classes for renames, exclusions, type mappings
   - Per-symbol customization; Pointer type overloads
   - Great flexibility; high maintenance burden

**Lesson:** Minimalist fixup → simpler generator, easier to maintain; more complex fixup → flexible but hard to evolve.

---

## 6. Surprises & Corrections to Common Beliefs

1. **Codegen ≠ Reflection (REVERSED):**
   - Older belief: binding generators = dynamic introspection → runtime overhead
   - **Reality:** Modern ecosystems (Kotlin compiler plugins, Expo Codegen, Nitro) moved toward compile-time codegen; reflection minimized
   - **Perf gain:** ~30–40% startup improvement on Android (Expo modules example)

2. **C++ Interop Not Universal:**
   - Older belief: Most binding generators handle C++
   - **Reality:** Primary support for C (jextract, cinterop, JavaCPP); C++ partial/limited (Swift C++ interop experimental, JavaCPP extensible but manual)
   - **Lesson:** C++ often bypassed via C wrappers or language-native APIs

3. **Macros Unsupported, Full Stop:**
   - All major generators **cannot** access preprocessor macros
   - Workaround: Hand-write wrapper C functions or constants; include in `.def` file post-expansion
   - **Exception:** cinterop's `---` raw C preamble allows manual macro usage

4. **Type Safety Achieved via Specs, Not Runtime:**
   - Kotlin compiler plugin, react-native-codegen, Nitro: TypeScript/Flow/Kotlin specs are the "contract"
   - Build fails if native implementation doesn't match spec (no runtime type discovery)
   - **Benefit:** Type errors at compile time, not runtime startup

5. **Async/Await Mapping is Language-Specific:**
   - No universal "Futures" protocol; each ecosystem chose its own:
     - Kotlin: suspend functions + Flow
     - Swift: async/await + AsyncSequence
     - JS: Promises + AsyncIterable
     - Java: CompletableFuture + Stream
   - Mapping one to another requires shim layer (SKIE does this; Nitro C++ layer abstracts)

6. **Documentation Lost in Translation (NOT YET SOLVED):**
   - Common assumption: generated bindings will auto-inherit docs from source
   - **Reality:** Most generators ignore KDoc/JSDoc/Javadoc
   - **Exception:** Swift symbolgraph preserves doc; third-party tools can parse
   - **Lesson:** Write docs in target language after generation

7. **Reflection Kills Startup, But Codegen Also Bloats:**
   - Avoided reflection with codegen (good); but generated code footprint can be large (per-platform, per-method stubs)
   - **Mitigation:** Platform-specific codegen (only generate what's used), lazy loading, feature flags

8. **Generics Mostly Erased in Bindings:**
   - Cross-language generics are nearly impossible to preserve perfectly
   - **Pragmatic solutions:** Monomorphize (one binding per type), erase to base, or use factory methods
   - **Lesson:** Avoid exposing generic types in public binding APIs

---

## 7. Open Questions / Limitations of Research

1. **Nitro Modules performance benchmarks vs. TurboModules:**
   - Nitro claims 2–3x faster type conversion; no peer-reviewed comparison found
   - May be deployment-specific (bundle size, startup, throughput)

2. **Agora Terra current status & adoption:**
   - Found the repo; minimal documentation on usage or production readiness
   - Is it still actively used by Agora internally (2026)?

3. **Swift Export stability & API finalization timeline:**
   - Goal stated as "stable 2026", but no official release date confirmed
   - When will JetBrains formally deprecate ObjC export path?

4. **Symbol graph adoption by third-party binding tools:**
   - Swift symbolgraph JSON is documented; unclear how many non-Apple tools consume it
   - Dart's swift2objc, .NET bindings, Kotlin: Do they actually use symbolgraph or parse headers independently?

5. **Error handling in Flow → AsyncSequence mapping:**
   - SKIE/Swift Export docs recommend "data as error" pattern
   - Are there production examples of handling errors well without throwing?

6. **Kotlin metadata extraction from .class files (version skew):**
   - Can kotlinx-metadata-jvm reliably read metadata from Kotlin 1.8/1.9 compiled code when running on Kotlin 2.4 tooling?
   - Any compatibility matrix?

7. **jextract macro support roadmap:**
   - Dump-then-curate is manual; any plans for programmatic macro expansion (e.g., preprocessing step)?

8. **React Native / Expo module library ecosystem:**
   - How many third-party modules have migrated to TurboModules / Nitro vs. legacy?
   - Performance data in production apps?

---

## Summary Table

| Tool | Language Pair | Front-End | IR | CLI/Config | Fixup | Status | License |
|------|---------------|-----------|----|-----------|----|--------|---------|
| **cinterop** | Kotlin ↔ C/ObjC | libclang | Internal | `.def` + Gradle | excludeFilter, `---` | Stable | Apache 2.0 |
| **Swift Export** | Kotlin → Swift | Kotlin IR | Kotlin IR → Swift AST | Gradle DSL | Minimal; `@ObjCName` | Experimental | Apache 2.0 |
| **SKIE** | Kotlin ObjC → Swift | ObjC framework | ObjC AST | Gradle plugin | `@SkieIgnore` | Stable | Apache 2.0 |
| **karakum** | TS ↔ Kotlin/JS | TS compiler API | TS AST | JSON config | Plugins, extensions | Active | Apache 2.0 |
| **swift-java** | Swift ↔ Java | Swift source + Java source | Swift API model | SwiftPM plugin | Annotations (`@Exported`) | Experimental | Apache 2.0 |
| **Swift C++ interop** | Swift ↔ C++ | C++ header | C++ type model | `-cxx-interoperability-mode=default` | Wrapper classes | Experimental | Apache 2.0 |
| **symbolgraph** | Swift API → JSON | Swift compiler | Symbol graph JSON | `swift-symbolgraph-extract` | Read-only | Stable | Apache 2.0 |
| **jextract** | C headers → Java FFM | libclang | Java FFM bindings | `.conf` + CLI flags | Dump-then-curate | Stable | GPL 2.0 + CE |
| **JavaCPP** | C/C++ → Java JNI | Custom parser | Java annotations | Presets + `@Platform` | `Info` map | Stable | Apache 2.0 |
| **react-native-codegen** | TS spec → native | TS compiler API | TS AST → schema JSON | `codegenConfig` in package.json | Source annotation | Stable | MIT |
| **Nitro Nitrogen** | TS spec → C++/Swift/Kotlin | TS AST parser | TS interface → IR | `nitro.json` | Custom converters | Stable | MIT |
| **Expo Modules API** | Swift/Kotlin DSL → native | Runtime reflection / Kotlin plugin | Module definition | Auto-detected | Custom converters | Stable | MIT |
| **Terra** | C++ headers → multi-lang | Custom parser / libclang | `TerraNode` AST | `terra_config.yaml` | Transformers, custom renderers | Active | Likely MIT/Apache 2.0 |

---

## References & URLs

**Kotlin Ecosystem:**
- https://kotlinlang.org/docs/native-definition-file.html
- https://blog.jetbrains.com/kotlin/2024/10/kotlin-multiplatform-development-roadmap-for-2025/
- https://skie.touchlab.co/
- https://github.com/karakum-team/karakum

**Swift Ecosystem:**
- https://github.com/swiftlang/swift-java
- https://www.swift.org/documentation/cxx-interop/status/
- https://github.com/swiftlang/swift-docc-symbolkit

**Java Ecosystem:**
- https://inside.java/tag/panama/
- https://github.com/bytedeco/javacpp
- https://kotlinlang.org/docs/metadata-jvm.html

**JavaScript / React Native:**
- https://github.com/reactwg/react-native-new-architecture/blob/main/docs/turbo-modules.md
- https://nitro.margelo.com/
- https://docs.expo.dev/modules/overview/
- https://github.com/AgoraIO-Extensions/terra

**Async/Concurrency:**
- https://medium.com/@santimattius/kotlin-2-4-swift-export-flow-asyncsequence-and-swift-packages-6a97c3afe7b7

**Nullability:**
- https://jspecify.dev/
- https://www.jetbrains.com/help/idea/annotating-source-code.html

**API Availability:**
- https://www.avanderlee.com/swift/available-deprecated-renamed/
- https://dev.to/vtsen/requiresapi-and-checkssdkintatleast-annotation-4fh
