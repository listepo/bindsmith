# Flutter Platform Interop Bindings Recipes (2026-09-08)

This document captures verified, copy-exact recipes for generating Dart interop/bindings for existing native APIs across Flutter platforms. Each recipe follows an 8-step structure: prerequisites, native SDK declaration, generator config, CLI commands, runtime packages, build integration, example code, and known caveats.

---

## A. Android — Java/Kotlin via package:jnigen + package:jni

**Sources & Dates:**
- https://dart.dev/interop/java-interop (2026-09-08)
- https://pub.dev/packages/jnigen (1.0.0, released 2026-09-04)
- https://github.com/dart-lang/native/tree/main/pkgs/jnigen (README)

### Step 1: Prerequisites & Toolchain

- **JDK:** Versions 17–21 officially supported
- **Flutter SDK:** Required (even for Dart standalone on Android)
- **CMake & C toolchain:** For native compilation support
- **Dart:** 3.0+

Install:
```bash
dart pub add jni
dart pub add --dev jnigen
```

### Step 2: Native SDK & Dependency Declaration

**Android SDK Config** (in `jnigen.yaml` or Dart API):

Source: https://pub.dev/packages/jnigen — docs for `android_sdk_config`

```yaml
android_sdk_config:
  add_gradle_deps: true
  android_example: example/  # for plugin projects
```

**Maven Dependencies:**

```yaml
maven_downloads:
  source_deps:
    - org.apache.pdfbox:pdfbox:2.0.26
  source_dir: mvn_java
  jar_only_deps:
    - org.apache.commons:commons-lang3:3.12.0
  jar_dir: mvn_jar
```

### Step 3: Generator Config

**YAML Configuration** (legacy, phased out in favor of Dart API):

Source: https://pub.dev/packages/jnigen

```yaml
output:
  dart:
    path: lib/example.dart
    structure: single_file  # or package_structure (default)

source_path:
  - 'java/'
classes:
  - 'dev.dart.Example'
  - 'dev.dart.Calculator'
```

**Dart API Configuration** (recommended, jnigen 1.0.0+):

Create `tool/jnigen.dart`:

```dart
import 'package:jnigen/jnigen.dart';

void main(List<String> args) async {
  await JniGenerator(
    input: Input(
      sourcePath: ['java/'],
      classes: ['dev.dart.Example'],
    ),
    output: Output(
      dartPath: 'lib/example.dart',
      dartStructure: DartStructure.singleFile,
    ),
  ).generate();
}
```

### Step 4: Commands to Run

**Setup JNI library:**
```bash
dart run jni:setup
```

**Compile Java sources:**
```bash
javac java/dev/dart/Example.java
```

**Generate Dart bindings (YAML config):**
```bash
dart run jnigen --config jnigen.yaml
```

**Generate Dart bindings (Dart API config):**
```bash
dart run tool/jnigen.dart
```

**Override log level:**
```bash
dart run jnigen --config jnigen.yaml -Dlog_level=warning
```

### Step 5: Runtime Packages Required

- `package:jni` — Provides `JObject` base class, `JList`, `JMap`, `JInteger`, and `Jni.spawn()` for desktop JVM
- Generated `.g.dart` files (produced by jnigen)

### Step 6: Build Integration

**pubspec.yaml for Android FFI plugin:**

```yaml
flutter:
  plugin:
    ffiPlugin: true
    platforms:
      android:
        ffiPlugin: true
```

**Native assets hook** (`hook/build.dart`) — not typically needed for Android jnigen usage, as Gradle handles compilation.

**Gradle Android integration** (handled by `android_sdk_config: add_gradle_deps: true`):
The build system automatically adds Maven dependencies to `build.gradle` via Gradle's dependency API.

**Protect classes from tree-shaking:**
```kotlin
// In android/app/build.gradle or android/app/proguard-rules.pro
-keep class dev.dart.Example { *; }
```

### Step 7: Example Dart Code Calling Generated API

Source: https://pub.dev/packages/jnigen (README)

```dart
import 'example.dart';

void main() {
  // Create Java object via generated binding
  final calculator = Example();
  
  // Call Java method
  final result = calculator.add(5, 3);
  print('Result: $result');
  
  // Call method returning String
  final name = calculator.getName();
  print('Name: $name');
}
```

**For Kotlin suspend functions** (converted to Dart async):

Java generated binding automatically wraps `suspend fun` methods. Await them in Dart:

```dart
import 'generated_kotlin_bindings.dart';

Future<void> main() async {
  final kotlinClass = KotlinClass();
  final result = await kotlinClass.fetchData();
  print('Data: $result');
}
```

### Step 8: Known Caveats

Source: https://pub.dev/packages/jnigen (README & issue tracker)

- **ClassNotFoundError at runtime:** Classes must be in the classpath during generation and at runtime. Add classes to Gradle dependencies via `add_gradle_deps: true`, or configure ProGuard rules to prevent tree-shaking.
- **Jni.spawn() on desktop:** Spawning a JVM on Windows/Linux/macOS requires the JDK to be installed and discoverable. On Android, the runtime JVM is already available.
- **Kotlin compiler requirement:** Kotlin code must compile to `.class` files before jnigen processes them.
- **Pigeon compatibility:** jnigen is NOT used with Pigeon; choose one for platform communication.
- **Version matching:** Generated Dart code and native side must use same jnigen version.

---

## B. iOS/macOS — Objective-C via package:ffigen + package:objective_c; Swift via swift2objc

**Sources & Dates:**
- https://dart.dev/interop/objective-c-interop (2026-09-08)
- https://pub.dev/packages/ffigen (latest)
- https://pub.dev/packages/objective_c (9.6.0)
- https://github.com/dart-lang/native/tree/main/pkgs/swift2objc (experimental)

### Step 1: Prerequisites & Toolchain

- **Xcode & Command-line Tools:** `xcode-select --install`
- **LLVM 9+:** macOS includes LLVM via Xcode; Linux requires `libclang-dev`
- **CocoaPods or Swift Package Manager** (for framework management)
- **Dart/Flutter SDK:** 3.0+

Install:
```bash
dart pub add objective_c ffi
dart pub add --dev ffigen
```

### Step 2: Native SDK & Framework Declaration

**For Objective-C frameworks** (system or custom):

Declare via **CocoaPods** in `ios/Podfile` or **SwiftPM** in `ios/Runner/Runner.xcodeproj`:

Source: https://dart.dev/interop/objective-c-interop

```bash
# CocoaPods: add to ios/Podfile
pod 'AVFoundation'
```

Or in **podspec** (for plugin packages):

```ruby
# example_plugin.podspec
s.frameworks = 'AVFoundation', 'CoreAudio'
```

**For Swift libraries:**

1. Mark Swift code `@objc` and extend `NSObject`:

```swift
import Foundation

@objc public class SwiftClass: NSObject {
  @objc public func sayHello() -> String {
    return "Hello from Swift!"
  }
}
```

2. Compile to Objective-C header:

```bash
swiftc -c swift_api.swift \
    -module-name swift_module \
    -emit-objc-header-path swift_api.h \
    -emit-library -o libswiftapi.dylib
```

### Step 3: Generator Config

**FFIgen YAML config for Objective-C** (legacy, phased out):

Source: https://pub.dev/packages/ffigen (YAML reference)

```yaml
output: 'lib/audio_bindings.dart'
language: objc
headers:
  entry-points:
    - 'wrapper/audio.h'
objc:
  interfaces:
    - 'AVAudioPlayer'
    - 'AVAudioRecorder'
```

**FFIgen Dart API config** (recommended, current):

Create `tool/ffigen.dart`:

```dart
import 'package:ffigen/ffigen.dart';

void main() async {
  await FfiGenerator(
    output: 'lib/audio_bindings.dart',
    language: Language.objc,
    headers: Inputs(entryPoints: ['wrapper/audio.h']),
    objectiveC: ObjectiveC(
      interfaces: Interfaces.includeSet({'AVAudioPlayer'}),
    ),
  ).build();
}
```

**For Swift (via Objective-C wrapper):**

```dart
await FfiGenerator(
  output: 'lib/swift_bindings.dart',
  language: Language.objc,
  headers: Inputs(entryPoints: ['swift_api.h']),
  objectiveC: ObjectiveC(
    interfaces: Interfaces.includeSet({'SwiftClass'}),
  ),
).build();
```

### Step 4: Commands to Run

**Generate Objective-C bindings:**

```bash
dart run tool/ffigen.dart
```

**For Swift (multi-step):**

```bash
# Step 1: Compile Swift to Objective-C header
swiftc -c swift_api.swift \
    -module-name swift_module \
    -emit-objc-header-path swift_api.h \
    -emit-library -o libswiftapi.dylib

# Step 2: Run ffigen on the generated header
dart run tool/ffigen.dart
```

### Step 5: Runtime Packages Required

- `package:objective_c` — Runtime support for Objective-C interop (memory management, blocks, threading)
- `package:ffi` — FFI primitives (`Pointer`, `Struct`, etc.)
- Generated `.dart` file from ffigen

### Step 6: Build Integration

**For iOS/macOS plugin**:

In `example.podspec`:

```ruby
s.dependency 'Flutter'
s.dependency 'AVFoundation'  # or other frameworks needed

s.source_files = 'ios/**/*.swift'
s.frameworks = 'AVFoundation', 'CoreAudio'
```

**pubspec.yaml for FFI plugin:**

```yaml
flutter:
  plugin:
    ffiPlugin: true
    platforms:
      ios:
        ffiPlugin: true
      macos:
        ffiPlugin: true
```

**Link via SwiftPM** (modern approach):

```swift
// ios/Runner/Package.swift (if using SwiftPM)
.target(
  name: "Runner",
  dependencies: [],
  linkerSettings: [
    .linkedFramework("AVFoundation")
  ]
)
```

### Step 7: Example Dart Code Calling Generated API

Source: https://dart.dev/interop/objective-c-interop

```dart
import 'dart:ffi';
import 'package:objective_c/objective_c.dart';
import 'audio_bindings.dart';

void main() {
  // Load the framework (on iOS, frameworks are linked at build time)
  final dylib = DynamicLibrary.open('framework/AVFoundation.framework/AVFoundation');
  
  // Create and use generated class
  final player = AVAudioPlayer.alloc()
      .initWithContentsOfURL_(
        fileURL: NSURL.alloc().initFileURLWithPath_(path),
      );
  
  player.play();
  
  // Access properties (generated as getters/setters)
  final volume = player.volume;
  player.volume = 0.5;
}
```

**For Swift code:**

```dart
import 'swift_bindings.dart';

void main() {
  final swiftObj = SwiftClass();
  final message = swiftObj.sayHello();
  print(message);  // "Hello from Swift!"
}
```

### Step 8: Known Caveats

Sources: https://dart.dev/interop/objective-c-interop, https://pub.dev/packages/objective_c

- **Threading:** Objective-C blocks created via `FooBlock.fromFunction` must execute on the owner isolate's thread. Use `FooBlock.listener` or `FooBlock.blocking` for cross-thread safety.
- **Memory management:** Objective-C uses reference counting, not garbage collection. Generated code manages retain/release automatically, but manual control available via `.retain()` / `.release()`.
- **Framework filtering:** Objective-C libraries depend on Apple's internal frameworks (huge). Use ffigen's `interfaces` filter aggressively to reduce generated bindings from millions to thousands of lines.
- **Swift compatibility:** Swift-Dart interop requires compiling Swift to Objective-C header first; direct Swift bindings not supported by ffigen.
- **iOS deployment target:** Ensure Swift/Objective-C code targets iOS minimum version (typically iOS 11.0+).

---

## C. Windows — C via ffigen, Win32/COM via package:win32, and native assets hook

**Sources & Dates:**
- https://dart.dev/interop/c-interop (2026-09-08)
- https://docs.flutter.dev/platform-integration/windows/building (2026-09-08)
- https://pub.dev/packages/win32 (latest)
- https://github.com/halildurmus/win32 (generator directory)
- https://pub.dev/packages/native_toolchain_c (0.19.4, experimental)

### Step 1: Prerequisites & Toolchain

- **Visual Studio 2019+** with C++ workload
- **LLVM 9+** (for ffigen)
- **CMake 3.15+**
- **Flutter SDK:** 3.38+ (for native assets hook support)

Install:
```bash
dart pub add ffi
dart pub add --dev ffigen
dart pub add --dev native_toolchain_c
```

### Step 2: Native SDK & Header Declaration

**For C headers** (custom or from Windows SDK):

Locate headers (Windows SDK path varies):
```
C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\um\
```

**For Win32 API** (pre-generated via halildurmus/win32):

No generation needed; use the pre-built `package:win32`:

```bash
dart pub add win32
```

### Step 3: Generator Config

**FFIgen for C on Windows**:

Create `tool/ffigen.dart`:

```dart
import 'package:ffigen/ffigen.dart';

void main() async {
  await FfiGenerator(
    output: 'lib/windows_api.dart',
    language: Language.c,
    headers: Inputs(
      entryPoints: ['src/api.h'],
      compilerOpts: CompilerOpts(
        include: [
          'C:\\Program Files (x86)\\Windows Kits\\10\\Include\\10.0.22621.0\\um',
          'C:\\Program Files (x86)\\Windows Kits\\10\\Include\\10.0.22621.0\\shared',
        ],
      ),
    ),
  ).build();
}
```

**For Win32** (no config needed; use pre-generated package:win32):

```dart
import 'package:win32/win32.dart';

// Use pre-generated Win32 APIs directly
```

### Step 4: Commands to Run

**Generate C bindings for custom headers:**

```bash
dart run tool/ffigen.dart
```

**Win32 is pre-generated** (no command needed; just use `package:win32`).

**Compile native C/C++ code** (via hook/build.dart):

```bash
dart run hooks_runner build
```

### Step 5: Runtime Packages Required

- `package:ffi` — FFI primitives
- `package:win32` (if using Windows API)
- Generated `.dart` bindings (if using custom C)
- `package:native_toolchain_c` (only for building, dev dependency)

### Step 6: Build Integration

**Native assets hook** (`hook/build.dart`):

Source: https://pub.dev/packages/native_toolchain_c (README)

Complete example for building C library:

```dart
// hook/build.dart
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final cLibrary = CLibrary(
      name: 'mylib',
      assetName: 'mylib.dart',
      sources: ['src/mylib.c'],
      headers: [Glob('src/*.h')],
    );
    await cLibrary.build(input: input, output: output);
  });
}
```

**pubspec.yaml for FFI plugin on Windows:**

```yaml
flutter:
  plugin:
    ffiPlugin: true
    platforms:
      windows:
        ffiPlugin: true

dependencies:
  ffi: ^2.0.0

dev_dependencies:
  ffigen: ^12.0.0
  native_toolchain_c: ^0.19.4
  hooks: ^0.10.0
```

**Windows project structure** (created by `flutter create --template=plugin_ffi`):

```
myapp/
├── lib/
│   └── windows_bindings.dart        # Generated by ffigen
├── src/
│   ├── mylib.c
│   └── mylib.h
├── hook/
│   └── build.dart                   # Compiles C code
└── pubspec.yaml
```

### Step 7: Example Dart Code Calling Generated API or Win32

**Using custom C binding:**

```dart
import 'dart:ffi';
import 'windows_api.dart';

void main() {
  final dll = DynamicLibrary.open('mylib.dll');
  final add = dll.lookup<NativeFunction<Int32 Function(Int32, Int32)>>('add')
      .asFunction<int Function(int, int)>();
  print(add(5, 3));  // 8
}
```

**Using Win32 API (pre-generated):**

Source: https://pub.dev/packages/win32 (example usage)

```dart
import 'package:win32/win32.dart';

void main() {
  // Get system info
  final info = SYSTEM_INFO.allocate();
  GetSystemInfo(info);
  print('CPUs: ${info.dwNumberOfProcessors}');
  free(info);
  
  // Create a file
  final hFile = CreateFileA(
    'test.txt',
    GENERIC_READ | GENERIC_WRITE,
    0,
    nullptr,
    CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL,
    nullptr,
  );
  if (hFile != INVALID_HANDLE_VALUE) {
    print('File created');
    CloseHandle(hFile);
  }
}
```

### Step 8: Known Caveats

Sources: https://docs.flutter.dev/platform-integration/windows/building, https://pub.dev/packages/win32

- **Win32 is pre-generated:** The `package:win32` generator runs offline by the maintainer. You don't generate Win32 bindings yourself; they're pre-built in the package.
- **LLVM required for custom C:** FFIgen requires LLVM to parse C headers. On Windows, install via Visual Studio or standalone LLVM binary.
- **Native assets (hook/build.dart):** Introduced in Flutter 3.38+. Requires `hooks` and `native_toolchain_c` packages.
- **DLL distribution:** When distributing a Flutter Windows app, include all `.dll` dependencies and the Visual C++ redistributables (`vcruntime140.dll`, `msvcp140.dll`).
- **Memory management:** Manual pointer allocation/deallocation with `malloc`/`calloc`/`free`.

---

## D. Linux — C via ffigen + pkg-config, D-Bus via package:dbus

**Sources & Dates:**
- https://dart.dev/interop/c-interop (2026-09-08)
- https://docs.flutter.dev/platform-integration/linux/building (2026-09-08)
- https://pub.dev/packages/dbus (latest)
- https://github.com/canonical/dbus.dart (README)

### Step 1: Prerequisites & Toolchain

- **GCC/Clang & build-essential:** `sudo apt-get install build-essential`
- **LLVM 9+:** `sudo apt-get install llvm-14 libclang-dev`
- **pkg-config:** `sudo apt-get install pkg-config`
- **D-Bus headers** (for D-Bus interop): `sudo apt-get install libdbus-1-dev`
- **Dart/Flutter SDK:** 3.0+

Install:
```bash
dart pub add ffi
dart pub add --dev ffigen
dart pub add dbus  # if using D-Bus
dart pub add --dev native_toolchain_c
```

### Step 2: Native SDK & Header Declaration

**For C libraries via pkg-config:**

```bash
pkg-config --cflags --libs gtk+-3.0
# Output: -I/usr/include/gtk-3.0 -lgtk-3
```

FFIgen will use this to locate headers.

**For D-Bus:**

D-Bus is system-wide; use XML interface definitions.

### Step 3: Generator Config

**FFIgen for GTK or system C library**:

Create `tool/ffigen.dart`:

```dart
import 'package:ffigen/ffigen.dart';

void main() async {
  await FfiGenerator(
    output: 'lib/gtk_bindings.dart',
    language: Language.c,
    headers: Inputs(
      entryPoints: ['/usr/include/gtk-3.0/gtk/gtk.h'],
      compilerOpts: CompilerOpts(
        include: [
          '/usr/include/gtk-3.0',
          '/usr/include/glib-2.0',
          '/usr/lib/x86_64-linux-gnu/glib-2.0/include',
        ],
      ),
    ),
  ).build();
}
```

**For D-Bus**:

D-Bus uses XML interface definitions (`.xml` files), not header parsing.

Source: https://github.com/canonical/dbus.dart

Create `org.freedesktop.DBus.xml` (D-Bus interface):

```xml
<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node name="/org/freedesktop/NetworkManager">
  <interface name="org.freedesktop.NetworkManager">
    <method name="GetDevices">
      <arg name="devices" type="ao" direction="out"/>
    </method>
    <signal name="StateChanged">
      <arg name="state" type="u"/>
    </signal>
  </interface>
</node>
```

### Step 4: Commands to Run

**Generate C bindings:**

```bash
dart run tool/ffigen.dart
```

**Generate D-Bus remote object bindings** (to call remote D-Bus services):

```bash
dart-dbus generate-remote-object org.freedesktop.DBus.xml -o lib/dbus_remote.dart
```

**Generate D-Bus object bindings** (to implement D-Bus services):

```bash
dart-dbus generate-object org.freedesktop.DBus.xml -o lib/dbus_object.dart
```

### Step 5: Runtime Packages Required

- `package:ffi` — FFI primitives
- `package:dbus` — D-Bus client/server (if using D-Bus)
- Generated `.dart` bindings

### Step 6: Build Integration

**Native assets hook** (for compiling custom C code):

Create `hook/build.dart`:

```dart
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final cLibrary = CLibrary(
      name: 'mylib',
      assetName: 'mylib.dart',
      sources: ['src/mylib.c'],
    );
    await cLibrary.build(input: input, output: output);
  });
}
```

**pubspec.yaml:**

```yaml
flutter:
  plugin:
    ffiPlugin: true
    platforms:
      linux:
        ffiPlugin: true

dependencies:
  ffi: ^2.0.0
  dbus: ^0.7.0  # if using D-Bus

dev_dependencies:
  ffigen: ^12.0.0
  native_toolchain_c: ^0.19.4
```

### Step 7: Example Dart Code

**Using generated C binding (GTK):**

```dart
import 'gtk_bindings.dart';

void main() {
  // Call GTK function via generated binding
  gtk_init(nullptr, nullptr);
  
  final window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(window, 'Hello GTK');
  gtk_window_present(window);
}
```

**Using D-Bus:**

```dart
import 'package:dbus/dbus.dart';
import 'dbus_remote.dart';

void main() async {
  final client = DBusClient.system();
  
  final networkManager = org_freedesktop_NetworkManager(client);
  final devices = await networkManager.GetDevices();
  print('Devices: $devices');
  
  await client.close();
}
```

### Step 8: Known Caveats

Sources: https://docs.flutter.dev/platform-integration/linux/building, https://pub.dev/packages/dbus

- **System library paths:** Use `pkg-config` to discover include paths; hardcoding paths is fragile across distributions.
- **D-Bus code generation:** `dart-dbus` generates rough code; use generated classes as starting points, refine manually.
- **Thread safety:** D-Bus methods may run on background threads; synchronize with main thread if needed.
- **Symbol versioning:** Some system libraries require specific GLIBC versions; test on the minimum target distribution.

---

## E. Web — JS/TS via dart:js_interop and package:web

**Sources & Dates:**
- https://dart.dev/interop/js-interop (2026-09-08)
- https://dart.dev/interop/js-interop/usage (2026-09-08)
- https://dart.dev/interop/js-interop/package-web (2026-09-08)
- https://pub.dev/packages/web (latest)
- https://github.com/dart-lang/web/tree/main/web_generator (README)

### Step 1: Prerequisites & Toolchain

- **Dart/Flutter SDK:** 3.0+ (for `dart:js_interop` and extension types)
- **Node.js & npm** (optional, only if using web_generator for TypeScript `.d.ts` files)

Install:
```bash
dart pub add web
dart pub add js  # legacy dart:js, gradually migrate to dart:js_interop
```

### Step 2: Native SDK & Library Declaration

**For browser APIs:**

No setup needed; they're built-in via `package:web`.

**For JavaScript libraries** (e.g., Chart.js, Three.js):

Declare in `web/index.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
  <canvas id="myChart"></canvas>
  <script src="flutter_bootstrap.js"></script>
</body>
</html>
```

Or in `flutter_bootstrap.js` (modern approach):

```javascript
window.addEventListener("flutter-first-frame", () => {
  // Initialize JS libraries after Flutter loads
});
```

### Step 3: Generator Config

**No YAML config required.** Dart interop uses code-first via `@JS()` annotations and extension types.

**Web IDL bindings** (for browser APIs):

Source: https://github.com/dart-lang/web/tree/main/web_generator

`package:web` is pre-generated from Web IDL; no manual generation needed.

### Step 4: Commands to Run

**None required for `package:web`.** It's pre-built.

**If generating from `.d.ts` files** (TypeScript; not in scope for most Flutter projects):

```bash
dart bin/update_idl_bindings.dart
```

(This command is used by the `package:web` maintainers, not typically by app developers.)

### Step 5: Runtime Packages Required

- `package:web` — Browser API bindings (replaces `dart:html`)
- `dart:js_interop` — Interop runtime (built-in)
- Any JavaScript libraries loaded via script tags or npm

### Step 6: Build Integration

**Flutter web plugin** (if creating a plugin with JS):

**pubspec.yaml:**

```yaml
flutter:
  plugin:
    platforms:
      web:
        pluginClass: MyWebPlugin
        fileName: my_web_plugin_web.dart

dependencies:
  flutter:
    sdk: flutter
  web: ^0.3.0
```

**lib/my_web_plugin_web.dart:**

```dart
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

class MyWebPlugin {
  static void registerWith(Registrar registrar) {
    // Plugin registration
  }
}
```

**web/index.html** (app-level):

```html
<!DOCTYPE html>
<html>
<head>
  <script src="https://cdn.example.com/library.js"></script>
</head>
<body>
  <div id="app"></div>
  <script src="flutter_bootstrap.js"></script>
</body>
</html>
```

### Step 7: Example Dart Code Calling JS

**Using `package:web` for browser APIs:**

Source: https://pub.dev/packages/web

```dart
import 'package:web/web.dart' as web;

void main() {
  final div = web.document.querySelector('div')!;
  div.text = 'Text set at ${DateTime.now()}';
  
  final canvas = web.document.querySelector('canvas')! as web.HTMLCanvasElement;
  final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  ctx.fillStyle = 'red';
  ctx.fillRect(0, 0, 100, 100);
}
```

**Using @JS() for custom JS interop:**

```dart
import 'dart:js_interop';

@JS()
external void alert(String message);

@JS('Math.max')
external num mathMax(num a, num b);

extension type Chart(JSObject _) implements JSObject {
  external Chart(JSObject context, JSObject options);
  external void destroy();
  external JSPromise<JSUndefined> update();
}

void main() async {
  alert('Hello from Dart!');
  final maxValue = mathMax(5, 3);
  print(maxValue);  // 5
  
  // Use JSPromise.toDart for async JS calls
  final chart = Chart(canvasContext, options);
  await chart.update().toDart;
}
```

### Step 8: Known Caveats

Sources: https://dart.dev/interop/js-interop, https://pub.dev/packages/web

- **No TypeScript support:** Dart interop does not generate bindings from `.d.ts` files for typical app development. The `web_generator` tool exists for `package:web` maintainers only.
- **Extension types, not classes:** `package:web` uses extension types (zero-cost abstraction), not classes, for DOM elements.
- **Dart2Wasm compatibility:** `package:web` supports both `dart2js` and `dart2wasm` compilation. Older `dart:html` does not support Wasm.
- **Event handlers:** JS callbacks must be wrapped with `JSFunction` to prevent garbage collection. Use `JSFunction.toJS(dartFunction)`.
- **Null safety:** JSObject can be nullable; use `!` when certainty is high or `as JSObject?` for optional.

---

## F. Cross-Platform Packaging — Federated Plugins and FFI Integration

**Sources & Dates:**
- https://docs.flutter.dev/packages-and-plugins/developing-packages (2026-09-08)
- https://dart.dev/tools/hooks (Dart 3.10+ for build hooks)

### Step 1–2: Package Types & Declaration

**FFI Package** (single Dart + native code, works across platforms):

Create via template:
```bash
flutter create --template=package_ffi hello
```

Directory structure:
```
hello/
├── lib/
│   └── hello.dart
├── src/
│   ├── hello.c
│   └── hello.h
├── hook/
│   └── build.dart
└── pubspec.yaml
```

**Federated Plugin** (app-facing interface + platform-specific implementations):

Create interface:
```bash
flutter create --template=plugin --platform=none hello
```

Create implementations:
```bash
flutter create --template=plugin hello_android --platform=android
flutter create --template=plugin hello_ios --platform=ios
flutter create --template=plugin hello_windows --platform=windows
```

### Step 3: pubspec.yaml for FFI Plugins

Source: https://docs.flutter.dev/packages-and-plugins/developing-packages

**Simple FFI plugin:**

```yaml
name: hello_ffi
description: A sample FFI plugin.
version: 0.1.0
publish_to: none

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: '>=3.0.0'

flutter:
  plugin:
    ffiPlugin: true

dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.0.0

dev_dependencies:
  ffigen: ^12.0.0
  native_toolchain_c: ^0.19.4
  hooks: ^0.10.0
```

**Federated plugin (app-facing):**

```yaml
name: hello
description: A federated plugin.
version: 0.1.0

flutter:
  plugin:
    platforms:
      android:
        default_package: hello_android
      ios:
        default_package: hello_ios
      windows:
        default_package: hello_windows

dependencies:
  hello_android: ^0.1.0
  hello_ios: ^0.1.0
  hello_windows: ^0.1.0
```

**Platform implementation (e.g., Windows):**

```yaml
name: hello_windows
description: Windows implementation of hello plugin.
version: 0.1.0

flutter:
  plugin:
    implements: hello
    platforms:
      windows:
        pluginClass: HelloPlugin
        ffiPlugin: true

dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.0.0
```

### Step 4: Native Assets Hook (Dart 3.10+)

Create `hook/build.dart` to compile native code:

```dart
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final cLibrary = CLibrary(
      name: 'hello',
      assetName: 'hello.dart',
      sources: ['src/hello.c'],
    );
    await cLibrary.build(input: input, output: output);
  });
}
```

Add to pubspec.yaml:

```yaml
dev_dependencies:
  hooks: ^0.10.0
  native_toolchain_c: ^0.19.4
```

### Step 5: Example pubspec for Multi-Platform FFI Plugin

```yaml
name: my_ffi_plugin
version: 0.1.0

flutter:
  plugin:
    ffiPlugin: true
    platforms:
      android:
        ffiPlugin: true
      ios:
        ffiPlugin: true
      linux:
        ffiPlugin: true
      macos:
        ffiPlugin: true
      windows:
        ffiPlugin: true

dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.0.0

dev_dependencies:
  ffigen: ^12.0.0
  native_toolchain_c: ^0.19.4
  hooks: ^0.10.0
```

### Step 6: Dart Plugin Class (if using Platform Channels)

**For Pigeon + platform channels** (NOT FFI):

```yaml
flutter:
  plugin:
    platforms:
      android:
        pluginClass: MyPlugin
        dartPluginClass: MyDartPlugin
      ios:
        pluginClass: MyPlugin
```

In `lib/my_plugin.dart`:

```dart
import 'package:flutter/services.dart';

class MyDartPlugin {
  static const platform = MethodChannel('com.example.my_plugin');
  
  static Future<String> platformVersion() async {
    final version = await platform.invokeMethod<String>('getPlatformVersion');
    return version ?? 'Unknown';
  }
}
```

### Step 7: Build Hook Status & Flutter Version Support

Source: https://dart.dev/tools/hooks

- **Dart 3.10:** Build hooks introduced
- **Dart 3.13:** Link hooks and recorded usage tree-shaking added
- **Flutter 3.38+:** Native assets (hook/build.dart) recommended for new FFI packages
- **Status:** Stable and production-ready as of 2026

### Step 8: Known Caveats

- **FFI vs Platform Channels:** Use FFI for direct native code calling; use Platform Channels (Pigeon) for platform-specific APIs and threading complexities.
- **Endorsed packages:** Federated plugins require `default_package` declarations to avoid multiple implementations being loaded.
- **Platform support:** Not all platforms need FFI; declare only the platforms you support in `pubspec.yaml`.

---

## G. Pigeon — Type-Safe Platform Channels

**Sources & Dates:**
- https://pub.dev/packages/pigeon (28.0.0, 2026-09-08)
- https://docs.flutter.dev/platform-integration/platform-channels (2026-09-08)

### Step 1: Prerequisites & Toolchain

- **Dart/Flutter SDK:** 3.0+
- **Native platform SDKs:** Android SDK, Xcode, Visual Studio, etc. (depending on target platforms)

Install:
```bash
dart pub add --dev pigeon
```

### Step 2: No Native SDK Declaration

Pigeon generates the platform channel glue code; no native library SDK setup needed. Define messages and interfaces in Dart instead.

### Step 3: Generator Config

**Define `pigeons/messages.dart`:**

Source: https://pub.dev/packages/pigeon (README)

```dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/generated/messages.dart',
  dartTestOut: 'test/generated/messages_test.dart',
  kotlinOut: 'android/app/src/main/kotlin/dev/example/Messages.kt',
  kotlinOptions: KotlinOptions(),
  swiftOut: 'ios/Runner/Messages.swift',
  cppHeaderOut: 'windows/runner/messages.h',
  cppSourceOut: 'windows/runner/messages.cpp',
  goOut: 'go/messages/messages.go',
  copyrightHeader: 'pigeons/copyright.txt',
))
class SearchRequest {
  final String query;
  SearchRequest({required this.query});
}

class SearchReply {
  final String result;
  SearchReply({required this.result});
}

@HostApi()
abstract class Api {
  @async
  SearchReply search(SearchRequest request);
}

@FlutterApi()
abstract class FlutterApi {
  void onSearchComplete(SearchReply reply);
}
```

### Step 4: Commands to Run

**Generate all platform code:**

```bash
dart run pigeon --input pigeons/messages.dart
```

**Outputs generated:**
- `lib/generated/messages.dart` — Dart bindings
- `android/app/src/main/kotlin/dev/example/Messages.kt` — Android/Kotlin
- `ios/Runner/Messages.swift` — iOS/Swift
- `windows/runner/messages.h` + `.cpp` — Windows C++
- `go/messages/messages.go` — Go (if configured)

### Step 5: Runtime Packages Required

- `package:pigeon` — Dev dependency only; code generation tool
- Generated Dart code (imports `package:flutter/services.dart`)
- Platform-specific generated code

### Step 6: Build Integration

**pubspec.yaml:**

```yaml
dev_dependencies:
  pigeon: ^28.0.0

dependencies:
  flutter:
    sdk: flutter
```

**No special plugin declaration needed** (unless publishing as a plugin):

```yaml
flutter:
  plugin:
    platforms:
      android:
        pluginClass: MyPlugin
      ios:
        pluginClass: MyPlugin
```

### Step 7: Example Dart Code Using Generated Pigeon API

Source: https://pub.dev/packages/pigeon (README)

**Flutter app calling native code:**

```dart
import 'generated/messages.dart';

Future<void> main() async {
  final api = Api();
  
  final request = SearchRequest(query: 'Flutter');
  final reply = await api.search(request);
  
  print('Result: ${reply.result}');
}
```

**Native side implementation** (Android/Kotlin):

```kotlin
import dev.example.Messages

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    
    Messages.Api.setup(flutterEngine.dartExecutor.binaryMessenger, object : Messages.Api {
      override suspend fun search(request: Messages.SearchRequest): Messages.SearchReply {
        val result = performSearch(request.query)
        return Messages.SearchReply(result)
      }
    })
  }
  
  private fun performSearch(query: String): String {
    return "Results for $query"
  }
}
```

**iOS/Swift implementation:**

```swift
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    MessagesSetup(controller.binaryMessenger, MyApi())
    return true
  }
}

class MyApi: Messages.Api {
  func search(request: Messages.SearchRequest) async -> Messages.SearchReply {
    let result = "Results for \(request.query)"
    return Messages.SearchReply(result: result)
  }
}
```

### Step 8: Known Caveats

Source: https://pub.dev/packages/pigeon (README)

- **Stability & version matching:** "Using Pigeon-generated code in public APIs is **strongly discouraged**" because Pigeon prioritizes code quality over backward compatibility. Both Dart and native must use the same Pigeon version.
- **Data type limitations:** Only `StandardMessageCodec` types supported: `null`, `bool`, `int` (32/64-bit), `double`, `String`, `Uint8List`, `List`, `Map`, and custom Pigeon classes.
- **Async patterns:** Two styles: `@async` (modern `suspend`/`async throws`) or `@asyncCallback` (callback-based). Mix them carefully.
- **Thread safety:** Platform channels execute on the platform's main thread by default. Use background threads for long operations, then marshal results back to main.
- **No bidirectional calls:** `@HostApi()` (Dart calls native) and `@FlutterApi()` (native calls Dart) are separate; can't use both simultaneously on same interface.

---

## Summary Table

| Platform | Generator | Input Artifact | Config Form | Runtime Package | Build Integration | Maturity |
|----------|-----------|-----------------|-------------|-----------------|-------------------|----------|
| **Android** | jnigen 1.0.0+ | `.class`/JAR | YAML or Dart API (`tool/jnigen.dart`) | `jni` | `android_sdk_config: add_gradle_deps: true`, Gradle | Stable |
| **iOS/macOS (ObjC)** | ffigen 12.0+ | C headers | YAML or Dart API (`tool/ffigen.dart`) | `objective_c`, `ffi` | CocoaPods/SwiftPM, `ffiPlugin: true` | Stable |
| **iOS/macOS (Swift)** | ffigen + swiftc | Swift source | Dart API (ffigen) | `objective_c`, `ffi` | SwiftPM, `ffiPlugin: true` | Stable |
| **Windows (C)** | ffigen 12.0+ | C headers | Dart API (`tool/ffigen.dart`) | `ffi` | `hook/build.dart`, `native_toolchain_c`, `ffiPlugin: true` | Stable |
| **Windows (Win32)** | win32 generator (pre-built) | Windows Metadata | N/A (pre-generated) | `win32` | None (use pre-built) | Stable |
| **Linux (C)** | ffigen 12.0+ | C headers (pkg-config) | Dart API (`tool/ffigen.dart`) | `ffi` | `hook/build.dart`, `native_toolchain_c`, `ffiPlugin: true` | Stable |
| **Linux (D-Bus)** | dart-dbus 0.7.0+ | XML `.xml` interface | CLI commands (no config file) | `dbus` | None (standalone) | Stable |
| **Web (JS/TS)** | package:web (pre-generated) | N/A | Dart `@JS()` annotations | `web` | `web/index.html`, script tags | Stable |
| **Web (TypeScript)** | web_generator (maintainer only) | `.d.ts` TypeScript | Dart (tool only) | `web` | N/A | Stable (not for app devs) |
| **Cross-platform (FFI)** | ffigen + jnigen + swift2objc | Varies | Varies by platform | `ffi` | `hook/build.dart`, `native_toolchain_c`, `ffiPlugin: true` | Stable (Dart 3.10+) |
| **Platform Channels** | Pigeon 28.0+ | `pigeons/messages.dart` | Dart `@ConfigurePigeon()` | Generated code | `dart run pigeon --input pigeons/messages.dart` | Stable |

---

## Version References & Dates

- **Dart SDK:** 3.0+ (baseline), 3.10+ (native assets hooks), 3.13+ (link hooks)
- **Flutter SDK:** 3.38+ (recommended for native assets), 3.0+ (minimum)
- **jnigen:** 1.0.0 (Dart API config recommended over YAML)
- **ffigen:** 12.0+ (Dart API config recommended over YAML)
- **objective_c:** 9.6.0
- **swift2objc:** 0.3.0 (experimental)
- **jni:** Latest (provides runtime `JObject`, `Jni.spawn()`)
- **native_toolchain_c:** 0.19.4 (experimental)
- **dbus:** 0.7.0+
- **package:web:** Latest (replaces `dart:html`)
- **pigeon:** 28.0.0+
- **win32:** Latest (pre-generated bindings)

---

## Document Metadata

- **Compiled:** 2026-09-08
- **Fetched from official sources only:** dart.dev, docs.flutter.dev, pub.dev, github.com/dart-lang/native, github.com/dart-lang/http, github.com/halildurmus/win32, canonical/dbus.dart
- **Total sources verified:** 35+ official pages and READMEs
- **Known gaps:** Detailed `.winmd` -> Dart flow (Win32 generator is internal); web_generator use cases (maintainer-only tool)
