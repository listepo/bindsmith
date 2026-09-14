# Toolchain

Project programs and direct packages from manifests. Versions in `pubspec.yaml` are caret ranges no wider than one major; version source is pub.dev (verified 2026-09-12).

## Programs

| Program | How to install | Why here | Source |
| --- | --- | --- | --- |
| mise | brew / curl, then `mise install` | Pinned tool versions | https://github.com/jdx/mise |
| dart | mise | matches the SDK bundled with Flutter 3.47 | https://github.com/dart-lang/sdk |
| node | mise | TypeScript sidecar (.d.ts driver) | https://github.com/nodejs/node |
| java | mise | jnigen needs JDK 17–21 | https://github.com/adoptium/temurin-build |
| kotlin | mise | compiles the Kotlin fixture and the generated bridge (P7-2) | https://github.com/JetBrains/kotlin |
| flutter | mise | package:jni declares a Flutter SDK constraint (P3-5) | https://github.com/flutter/flutter |
| cmake | mise | builds libdartjni for the desktop JVM runtime test (P3-5) | https://github.com/Kitware/CMake |

## npm / pnpm

| Package | Where | Source | Why here |
| --- | --- | --- | --- |
| typescript | local | https://www.npmjs.com/package/typescript | TS types / build |

## pub

### `packages/bindsmith` (CLI + drivers)

| Package | Pin | Where | Source | Why here |
| --- | --- | --- | --- | --- |
| ffigen | ^22.0.0 | local | https://pub.dev/packages/ffigen | C/ObjC driver (P1-2, P2-1) |
| swiftgen | ^0.2.0 | local | https://pub.dev/packages/swiftgen | Swift driver (P2-2) |
| jnigen | ^1.0.0 | local | https://pub.dev/packages/jnigen | JVM driver (P3-1) |
| winmd | ^7.1.0 | local | https://pub.dev/packages/winmd | WinMD driver (P5-1); 7.1.1 blocked by ffigen 22 `cli_util ^0.4.2` |
| dbus | ^0.7.15 | local | https://pub.dev/packages/dbus | D-Bus driver (P5-4) |
| analyzer | ^14.3.0 | local | https://pub.dev/packages/analyzer | Read-back of generated Dart signatures |
| args | ^2.7.0 | local | https://pub.dev/packages/args | CLI (`CommandRunner`) |
| yaml | ^3.1.0 | local | https://pub.dev/packages/yaml | `bindsmith.yaml` / lockfile |
| dart_style | ^3.1.0 | local | https://pub.dev/packages/dart_style | Format emitted Dart |
| path | ^1.9.0 | local | https://pub.dev/packages/path | Path helpers |
| crypto | ^3.0.7 | local | https://pub.dev/packages/crypto | sha256 in `bindsmith.lock` |
| archive | ^4.2.0 | local | https://pub.dev/packages/archive | `.aar` / `.zip` unpacking (Maven, npm, NuGet) |
| xml | ^7.0.1 | local | https://pub.dev/packages/xml | Maven POM parsing |
| package_config | ^3.0.0 | local | https://pub.dev/packages/package_config | `package:jni` lookup before jnigen `exit(1)` |
| logging | ^1.3.0 | local | https://pub.dev/packages/logging | Driver / CLI logging (until P1-4 switches to mason_logger) |
| lints | ^6.0.0 | local | https://pub.dev/packages/lints | Lint rules |
| test | ^1.26.0 | local | https://pub.dev/packages/test | Unit / golden tests |

### `fixtures` (generated bindings + hook templates)

| Package | Pin | Where | Source | Why here |
| --- | --- | --- | --- | --- |
| objective_c | ^9.6.0 | local | https://pub.dev/packages/objective_c | Runtime for ObjC/Swift generated bindings |
| ffi | ^2.2.0 | local | https://pub.dev/packages/ffi | Runtime for C generated bindings |
| win32 | ^6.4.0 | local | https://pub.dev/packages/win32 | WinMD re-export path fixture (P5-1) |
| hooks | ^2.2.0 | local | https://pub.dev/packages/hooks | Type-check emitted `hook/build.dart` |
| code_assets | ^2.0.0 | local | https://pub.dev/packages/code_assets | Type-check emitted `hook/build.dart` |
| native_toolchain_c | ^0.19.4 | local | https://pub.dev/packages/native_toolchain_c | Type-check C hook template (P5-5) |
| native_toolchain_cmake | ^0.3.2 | local | https://pub.dev/packages/native_toolchain_cmake | Type-check CMake hook template (P5-5) |
| bindsmith_runtime | ^0.1.0 | local | https://pub.dev/packages/bindsmith_runtime | Runtime annotations in generated code |

### JVM probe (not in workspace — jni needs Flutter SDK)

| Package | Pin | Where | Source | Why here |
| --- | --- | --- | --- | --- |
| jni | ^1.0.3 | probe | https://pub.dev/packages/jni | Runtime for JVM generated bindings; pinned in `test/jvm_toolchain.dart` because this workspace cannot depend on jni directly |

### Waiting on driver (not pinned yet)

| Package | Planned pin | Source | Why here |
| --- | --- | --- | --- |
| pigeon | ^28.0.0 | https://pub.dev/packages/pigeon | Channels fallback — no driver yet |
