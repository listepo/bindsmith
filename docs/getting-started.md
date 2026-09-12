# Getting started

## Before you begin

bindsmith is a pure-Dart command-line tool, but each driver leans on a native
toolchain that has to be on the host:

| Driver | Needs |
| --- | --- |
| `c`, `objc` | libclang — Xcode command line tools on macOS, `libclang-dev` on Linux, LLVM on Windows |
| `objc`, `swift` | macOS with Xcode; the Objective-C headers are parsed against the SDK `xcrun --show-sdk-path` reports |
| `jvm` | a JDK on `PATH` (Temurin 21 is what CI uses) |
| `dts` | Node.js 24 for the TypeScript sidecar |
| `winmd` | nothing — `package:winmd` is a pure-Dart metadata reader, so Windows bindings generate on any host |

`bindsmith doctor` answers this for the machine in front of you, and prints the
command that installs whatever is missing:

```bash
dart run bindsmith doctor
```

Before there is a `bindsmith.yaml` it looks at everything this host could have
and requires nothing; once there is one, only the toolchains the configured
platforms need are required, and it exits 1 while any of them is missing —
`--json` is the same report for a script.

## Add it to your package

```yaml
dev_dependencies:
  bindsmith: ^0.1.0
dependencies:
  bindsmith_runtime: ^0.1.0
```

`bindsmith_runtime` is what generated code imports: the verify annotation, the
platform enum, and the error thrown where a platform has no symbol. It never
depends on the generator.

## Write a configuration

```bash
dart run bindsmith init
```

That writes two files beside your `pubspec.yaml`: `bindsmith.yaml`, and
`bindsmith.schema.json` for your editor. The configuration points at the schema
from its first line, so a YAML language server completes the keys and
underlines the ones that do not exist.

Fill in one platform to start:

```yaml
# yaml-language-server: $schema=bindsmith.schema.json
name: my_sdk
output: lib/src/generated
facade:
  library: lib/my_sdk.dart

platforms:
  linux:
    driver: c
    headers: [third_party/example/include/example.h]
    include:
      functions: ["example_*"]
      structs: ["example_*"]
    build:
      sources: [src/example.c]
```

Two rules the loader enforces and it is worth knowing why. `output` and
`facade.library` must be under `lib/`, because a generated binding is reached
by a `package:` URI and its native asset is named after that URI — a file
anywhere else has neither. And `include:` is a pull list, not a filter: nothing
is bound that you did not ask for, so a header that includes half the platform
SDK still produces a small binding.

## Generate

```bash
dart run bindsmith generate
```

It prints every path it wrote:

```
lib/src/generated/linux/c.g.dart     the binding: one file per platform
lib/my_sdk.dart                      the facade entry point
lib/my_sdk_io.g.dart                 the facade for the native platforms
hook/build.dart                      the native build, for platforms with build:
```

Commit all of it. Generated code is reviewed like any other code, and the
review markers in it are the point.

## Answer the markers

```bash
dart run bindsmith verify
```

reads the generated code that is committed — not a fresh run — and fails while
anything in it is still waiting on a human:

```
lib/my_sdk_io.g.dart:39: signature differs: (double) -> double on web vs (int) -> int on android
bindsmith: 1 marker(s) still need a human; acknowledge one by deleting its
annotation or with a fixups entry carrying "ack: true", or set
"verify: { markers: warn }"
```

A marker is answered in one of three ways: fix the binding so it stops being
emitted, delete the annotation, or [acknowledge it](fixups.md) with an
`ack: true` fixup. `verify: { markers: warn }` downgrades all of them to a
report that does not fail.

Two more things are checked at the same time, and neither is an opinion the
configuration can hold. `verify.size_budget.lines` caps the whole generated
output, which is what catches a pull list that quietly grew a framework. And
the two facade group files must declare the identical public API — that is
what makes the facade usable from platform-independent Dart, and it is checked
by parsing both and comparing what a caller can name:

```
bindsmith: lib/my_sdk_io.g.dart and lib/my_sdk_web.g.dart do not declare the same API:
  Client.count is "int count(int n)" on io and "double count(double n)" on web
```

`verify` runs no generator, so it needs no libclang, no JDK and no network:
`generate --check` is the command that says whether the output is *current*,
and this one says whether it is *finished*.

## Look at what happened

```bash
dart run bindsmith explain 'example_open'
```

prints, per platform, what the symbol became, where it came from, and every
marker on it and its members. `bindsmith dump` prints the whole model as JSON,
including everything a driver could not map.

## Pin what you depend on

A platform that declares dependencies resolves them once and records exactly
what arrived:

```yaml
platforms:
  android:
    driver: jvm
    compile_sdk: 35
    deps:
      maven: ["androidx.biometric:biometric:1.2.0-alpha05"]
      repositories:
        - https://dl.google.com/dl/android/maven2/
        - https://repo1.maven.org/maven2/
```

```bash
dart run bindsmith resolve
```

follows the transitive graph, downloads into `.dart_tool/bindsmith/`, and writes
`bindsmith.lock` with the sha256 of every file it landed on. Commit that file.
It records the digest rather than the repository, because once the digest
matches, which mirror served the bytes does not change what you compiled
against.

The download cache mirrors a repository's own layout, so it *is* a repository:

```bash
dart run bindsmith resolve --offline
```

resolves from it and never reaches the network — a requirement rather than a
hope, so a build that has quietly started depending on a download fails here
instead of on someone else's machine.

A coordinate whose bytes no longer match the lock is an error naming it, never
a rewrite. A released artifact does not change, so either the lock was edited
or something is serving different bytes under that name, and both are worth
stopping for.

Repository URLs are `https://` or a `file://` directory, the two forms Gradle
accepts. Plain `http://` is refused: an artifact fetched over it is one that
whoever sits between you and the mirror chose, and it would then be pinned as
if it were yours. Version ranges, `LATEST` and `-SNAPSHOT` are refused too,
because each makes one coordinate mean different bytes on a different day.

## Keep it honest in CI

```bash
dart run bindsmith dump > api.json        # commit this
dart run bindsmith diff api.json          # fails when the native API moved
dart run bindsmith generate --check       # fails when the committed output is stale
dart run bindsmith verify                 # fails while a marker is unanswered
dart run bindsmith resolve --check        # fails when bindsmith.lock is stale
```

`diff`, `dump`, `explain` and `generate --check` never write into your package:
the generators are pointed at a directory that is deleted afterwards, so all
four are safe on a clean checkout. Both `diff` and `--check` exit 1 when
something differs, the same as `diff(1)`.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | fine |
| 1 | the answer is no (`diff`, `generate --check`, `resolve --check`, `doctor`, `verify`) |
| 64 | bad arguments |
| 65 | `bindsmith.yaml` was read and cannot be used |
| 66 | a file that was needed is not there |
| 70 | generation itself failed |

The split between 65 and 70 is the reason to have codes at all: a script can
tell "fix your configuration" from "the generator broke".

## While you work

```bash
dart run bindsmith watch
```

regenerates whenever the configuration or one of its headers changes. It keeps
running while the configuration does not parse, which is most of the time while
you are editing it, and stops when the file is deleted.
