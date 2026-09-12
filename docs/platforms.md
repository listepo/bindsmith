# Platforms

Six platforms, six drivers, one model. Every driver reads a native API and
produces the same intermediate representation, which is what lets one facade
sit over all of them. What differs is what each one can see, and what it has to
give up — recorded as a marker rather than dropped.

## Linux, Windows and desktop C — the `c` driver

Reads C headers with ffigen, through its library API and its visitor
interface, and writes a `dart:ffi` binding.

```yaml
linux:
  driver: c
  headers: [third_party/example/include/example.h]
  include:
    functions: ["example_*"]
    structs: ["example_*"]
    enums: ["Example*"]
  deps:
    pkg_config: [glib-2.0]
  build:
    sources: [src/example.c]
```

Nothing is included by default: entry-point headers are selected by the
`headers:` list and symbols by `include:`, while typedefs follow whatever uses
them. On Linux, `deps.pkg_config` runs `pkg-config --cflags` for each entry and passes the resulting `-I` and `-D` flags to libclang through the driver's `compilerOptions`. What the driver cannot promise is marked rather than hidden — a variadic
function binds its fixed arguments only, a union shares storage, a C enum has
an implementation-defined width, and a function-pointer typedef needs
`Pointer.fromFunction` or `NativeCallable` on the Dart side, and GLib's `G_OBJECT()` cast macros and `g_object_new` varargs carry verify markers because ffigen cannot bind them.

The facade over C is where most of the marshalling lives. A `char*` crosses
through an arena, an opaque handle becomes a wrapper with a `dispose`, an enum
crosses by constant name, and a struct is built with `ffi.Struct.create` — on
the Dart heap, so it is garbage-collected and has no `dispose` at all. A struct
passed by pointer is an arena copy read back field by field after the call,
because `dart:ffi` copies a struct *into* a pointer and has nothing that copies
one out; a callee that keeps that pointer outlives the copy, which is what the
marker on those calls says.

## Apple — the `objc` driver

The same generator as C, in Objective-C mode: ffigen supplies `-x objective-c`
and the SDK sysroot itself, which is why generating for Apple platforms needs
macOS. It writes two files, a Dart binding and an Objective-C glue `.m` that
has to be compiled into your framework.

```yaml
macos:
  driver: objc
  headers: [third_party/Example.framework/Headers/Example.h]
  include:
    types: ["EX*"]
    protocols: ["EX*Delegate"]
ios:
  inherit: macos
```

Everything about Objective-C that can go wrong goes wrong at the call rather
than at compile time, so read the markers here. A protocol is implemented from
Dart through the static `implement` on its generated `$Builder`. A block that
the callee invokes from another thread needs the `listener` constructor, not
`fromFunction`. An `NSError**` argument is not in the Dart signature at all —
ffigen throws instead, and the marker says so. An `@optional` protocol method
throws when you did not implement it.

## Apple, Swift-first libraries — the `swift` driver

Dart reaches Swift through Objective-C, so this is three translations deep:
swift2objc writes an `@objc` wrapper class, `swiftc` emits the Objective-C
header for it, and ffigen binds that header. The driver returns all three
artifacts, and all three ship.

Two limits of swift2objc are load-bearing and will not be worked around: a
generic Swift type produces a wrapper that does not compile, so keep it out of
the pull list; and a method taking an array parameter is dropped with nothing
but a log record, which the driver turns into a marker. Everything the wrapper
path can recover — structs, generics, `async` — is generated as an `@objc`
bridge you commit and feed back through the same driver.

A Swift `async` method reaches Dart as a completion handler that Swift calls
from its own executor thread. That is a `listener` block, and an ordinary one
deadlocks.

## Android — the `jvm` driver

jnigen reads Java and Kotlin, from sources or from a classpath, and writes
bindings over `package:jni`.

```yaml
android:
  driver: jvm
  compile_sdk: 35
  deps:
    maven: ["androidx.biometric:biometric:1.2.0-alpha05"]
    repositories:
      - https://maven.google.com
      - https://repo1.maven.org/maven2
  include:
    classes: ["androidx.biometric.BiometricPrompt*"]
  kotlin:
    suspend: future
    flow: stream
```

Maven resolution is bindsmith's own rather than jnigen's, because jnigen
resolves by writing a stub Gradle project and running `gradlew` — a tool driven
through its console output, pinning nothing. One repository is not enough in
practice: an AndroidX artifact usually comes from Google's Maven while the
Kotlin standard library it needs comes only from Central, so `repositories:` is
a list searched in order. Version ranges, `LATEST`, `RELEASE` and `-SNAPSHOT`
are refused by name: each makes one coordinate mean different bytes on a
different day, and there is nothing honest to write in a lockfile.
`bindsmith resolve` writes that lockfile; see
[pinning what you depend on](getting-started.md#pin-what-you-depend-on).
A repository is `https://` or a `file://` directory — the same two Gradle takes
— so a vendored or mirrored repository on disk works without a network at all.

From Kotlin, a `suspend fun` binds as a Dart `Future`. A function returning
`Flow` binds too, but carries a marker, because Dart gets the raw `Flow`
object and nothing that collects it. A default argument is invisible to Dart:
the binding takes every parameter, and the `f$default` method Kotlin compiles
for the shorter calls is listed as dropped in `bindsmith dump`. Annotate the
function or constructor with `@JvmOverloads` to bind each arity. jnigen needs
`package:jni` to resolve from the project — a Flutter plugin gets it from
`flutter pub get` — and bindsmith checks that before running it, since jnigen
would otherwise end the process.

A release build also has to be told to keep the classes the binding uses:
jnigen finds each one by name at run time, which R8 cannot see, so without
rules the app fails with `ClassNotFoundException` — in release only. bindsmith
writes two files for that beside your package's `android/build.gradle`, never
into it: `android/bindsmith-rules.pro`, one `-keep` rule per bound class, and
`android/bindsmith.gradle`, which hands those rules to every app using the
package (`consumerProguardFiles`) and declares the Maven dependencies. Apply
the script once with `apply from: 'bindsmith.gradle'`, and set `ffiPlugin: true`
under `flutter.plugin.platforms.android` in the pubspec so that Flutter builds
the library at all. `bindsmith generate` writes the binding, the facade, and
both Android glue files from the lock and the configured `compile_sdk`.

Kotlin constructs that have no Java shape — `suspend`, `Flow`, default
parameters, sealed classes — are bridged by generated Kotlin you commit, the
same way the Swift wrapper works.

## Windows — the `winmd` driver

There is no upstream generator for Windows. `package:winmd` *reads* Windows
metadata and does not emit anything, so bindsmith writes the `dart:ffi` binding
itself, and the work splits into a driver that turns metadata into the model
and an emitter that turns the model into Dart. Both run on any host.

```yaml
windows:
  driver: winmd
  deps:
    nuget: ["Microsoft.Windows.SDK.Win32Metadata"]
  include:
    functions: ["CreateFile*", "CloseHandle"]
    types: ["IFileDialog"]
```

A symbol `package:win32` already binds is not generated again: the declaration
is kept, marked, and re-exported from that package, so an interface from either
side is the same type. The generated COM shape follows `package:win32` — a
class over `IUnknown` holding a vtable pointer, a chained vtable struct, one
`asFunction` per slot — for the same reason.

## Web — the `dts` driver

The only driver with no upstream generator to lean on, because none exists: the
one living TypeScript-to-Dart tool was archived in 2022. A Node sidecar on the
TypeScript Compiler API emits a JSON model of the declarations, the driver
turns that into the model, and the emitter writes `dart:js_interop` extension
types.

```yaml
web:
  driver: dts
  deps:
    npm: ["chart.js@4.4.7"]
  include:
    exports: ["Chart", "ChartConfiguration"]
```

Everything the type system cannot carry across is marked: an overload set binds
as separate members, a generic becomes `JSAny?`, an inline literal union
becomes a Dart enum named after where it was declared, a callback parameter
takes a Dart function converted with `.toJS`. That conversion goes one way
only, and every call to it makes a new JavaScript function, which is why a
callback coming *out* of JavaScript stays untyped and carries a marker rather
than being quietly wrapped.

Generated web code is compiled by both dart2js and dart2wasm in the test suite,
because those two decide what is legal js_interop and the analyzer does not.
The bug that check exists for is real: a top-level `external` member needs its
own `@JS()`, and nothing reports it otherwise.

## Documentation

A declaration's own documentation follows it into what is generated from it —
the binding, the facade, a bridge — written the way that file's language
writes documentation. In a C or Objective-C header a plain `//` or `/* */`
comment counts, not only `///`, and a comment after a declaration on the same
line belongs to that declaration. Javadoc's `{@code}` and `{@link}` become Markdown; JSDoc's `{@link X}`
becomes a Dart reference, matched `@param` tags land in `Param.docs`, and
`@returns` / `@deprecated` stay in the member's prose (as `Returns …` and
`@Deprecated`). Doxygen `@param` / `@returns` on C and Objective-C headers
split the same way. A Swift class
reaches Dart through a wrapper swift2objc writes without comments, so its
documentation is taken from the Swift symbol graph instead, with
`- Parameter …` on `Param.docs` and `- Returns:` / `- Throws:` in member
prose: the facade and `bindsmith dump` carry it, while the Objective-C
binding underneath has only what ffigen found. Kotlin KDoc is read from `.kt`
sources configured on `JvmDriver.kotlinSources` (jnigen's summarizer does not
carry it). ffigen still drops the comments on macros and opaque structs.

## Sharing one entry between platforms

`inherit:` copies another platform's whole configuration rather than repeating
it, and a platform that inherits takes nothing else:

```yaml
platforms:
  macos:
    driver: objc
    headers: [third_party/Example.framework/Headers/Example.h]
  ios:
    inherit: macos
```

The platform inherited from has to be configured directly. Inheriting from a
platform that itself inherits is refused, with the line and column of the
`inherit:` that did it.
