# Walkthrough: a C library in five minutes

[Getting started](getting-started.md) explains each command. This page runs them all, in order, on
a tiny C library, and shows what you get. Every command and output below comes from a real run on
macOS with Xcode's command line tools and bindsmith's `main`; the C driver needs libclang
(`bindsmith doctor` checks).

## The library

`include/counter.h`:

```c
#ifndef COUNTER_H
#define COUNTER_H
#include <stdint.h>

typedef struct counter counter;

counter *counter_new(int32_t start);
int32_t counter_add(counter *c, int32_t n);
int32_t counter_get(const counter *c);
void counter_free(counter *c);

#endif
```

`src/counter.c` implements the four functions. The package is a normal Dart package with
`bindsmith` as a dev dependency and `bindsmith_runtime` as a dependency (see
[getting started](getting-started.md#add-it-to-your-package)), and this `bindsmith.yaml`:

```yaml
# yaml-language-server: $schema=bindsmith.schema.json
name: my_sdk
output: lib/src/generated
facade:
  library: lib/my_sdk.dart

platforms:
  macos:
    driver: c
    headers: [include/counter.h]
    include:
      functions: ["counter_*"]
      structs: ["counter"]
    build:
      sources: [src/counter.c]
```

## Check the machine, generate, verify

```console
$ dart run bindsmith doctor
ok      dart        Dart SDK version: 3.13.1 (stable) ... on "macos_arm64"
ok      libclang    /Library/Developer/CommandLineTools/usr/lib/libclang.dylib
ok      xcode       /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
ready: 3 checks

$ dart run bindsmith generate
lib/src/generated/macos/c.g.dart
lib/my_sdk.dart
lib/my_sdk_io.g.dart
hook/build.dart

$ dart run bindsmith verify
4 generated files verified, 79 lines
```

(`dart run` also prints `Running build hooks...` while it starts; the lines above leave it out.)

The binding is plain `dart:ffi`, one `@Native` declaration per function you pulled in:

```dart
@ffi.Native<ffi.Int32 Function(ffi.Pointer<counter>, ffi.Int32)>()
external int counter_add(ffi.Pointer<counter> c, int n);

@ffi.Native<ffi.Pointer<counter> Function(ffi.Int32)>()
external ffi.Pointer<counter> counter_new(int start);

final class counter extends ffi.Opaque {}
```

`lib/my_sdk.dart` is the facade you import; `hook/build.dart` compiles `src/counter.c` as a native
asset.

## Ask what a symbol became

```console
$ dart run bindsmith explain counter_add
macos  counter_add(counter c, int n) -> int
  from    include/counter.h
```

## Notice when the native API moves

Save the model once, commit it, and compare against it later. `dump` prints JSON on stdout (redirect
stderr away from the file, or `Running build hooks...` ends up in it):

```console
$ dart run bindsmith dump 2>/dev/null > api.json
$ dart run bindsmith diff api.json
no change: 6 symbols
```

Now add `int32_t counter_reset(counter *c);` to the header:

```console
$ dart run bindsmith diff api.json; echo "exit $?"
+ macos counter_reset  counter_reset(counter c) -> int
1 changed of 7 symbols
exit 1

$ dart run bindsmith generate --check; echo "exit $?"
lib/src/generated/macos/c.g.dart is out of date
lib/my_sdk_io.g.dart is out of date
bindsmith: run "bindsmith generate" and commit the result
exit 1
```

Run `dart run bindsmith generate` and commit; `generate --check` then reports
`4 generated files are up to date` and exits 0. Put `diff`, `generate --check` and `verify` in CI,
as in [Keep it honest in CI](getting-started.md#keep-it-honest-in-ci).
