<!-- GENERATED from packages/bindsmith/lib/src/config/schema.dart — do not
     edit. Run `dart test` with UPDATE_GOLDENS=1 to rewrite it. -->

# Configuration reference

Every key `bindsmith.yaml` accepts, written from the JSON Schema the loader
validates against — so this page cannot drift away from what bindsmith
enforces. `bindsmith init` writes that same schema next to your configuration
and points the file at it, so an editor completes and checks these keys as you
type them.

The schema settles shape: spelling, types, which keys exist. It cannot say
which keys a *particular* driver reads — `headers:` means nothing to the JVM
driver, `include: {classes:}` means nothing to the C driver — and the loader
refuses those with a line and a column rather than ignoring them. See
[platforms.md](platforms.md) for what each driver takes.

## Top level

One config, six Flutter platforms.

| Key | Type | Notes |
| --- | --- | --- |
| `name` | string | **Required.** Base name of the generated library: my_sdk.dart. |
| `output` | string | **Required.** Directory for the generated bindings, relative to this file. Under lib/, because a binding is reached by a package: URI. |
| `facade` | [object](#facade) | — |
| `platforms` | [object](#platforms) | **Required.** One entry per Flutter platform to generate for. |
| `fixups` | list of [fixup](#fixup) | Declarative edits applied to the IR after the drivers. |
| `verify` | [object](#verify) | — |

## facade

| Key | Type | Notes |
| --- | --- | --- |
| `library` | string | Path of the facade library to write. Under lib/, because it is what callers import. |
| `unsupported` | string | What the facade does where a platform has no symbol. One of `throw`, `stub`, `omit`. |

## platforms

One entry per Flutter platform to generate for.

| Key | Type | Notes |
| --- | --- | --- |
| `android` | [platform](#platform) | — |
| `ios` | [platform](#platform) | — |
| `macos` | [platform](#platform) | — |
| `windows` | [platform](#platform) | — |
| `linux` | [platform](#platform) | — |
| `web` | [platform](#platform) | — |

## fixup

| Key | Type | Notes |
| --- | --- | --- |
| `match` | [object](#fixupmatch) | **Required.** |
| `rename` | string | — |
| `hide` | boolean | — |
| `threading` | string | One of `any`, `main`. |
| `nullability` | [object](#fixupnullability) | — |
| `ack` | boolean | A human reviewed this symbol: drop its verify markers. |

## verify

| Key | Type | Notes |
| --- | --- | --- |
| `markers` | string | Whether an unacknowledged verify marker fails. One of `error`, `warn`. |
| `compile` | list of string | Platforms whose generated code must compile. |
| `size_budget` | [object](#verifysize_budget) | — |

## platform

| Key | Type | Notes |
| --- | --- | --- |
| `driver` | string | Which generator reads the native API. One of `c`, `objc`, `swift`, `jvm`, `winmd`, `dts`, `dbus`. |
| `inherit` | string | Take this platform's whole configuration from another one. One of `android`, `ios`, `macos`, `windows`, `linux`, `web`. |
| `headers` | list of string | Entry-point headers, for the c and objc drivers. |
| `xml` | list of string | D-Bus introspection XML files, for the dbus driver. |
| `deps` | [deps](#deps) | — |
| `include` | [include](#include) | — |
| `compile_sdk` | any | Android API level whose android.jar jnigen binds against. |
| `module` | string | Swift module the sources and generated wrapper compile into. |
| `sources` | list of string | Swift or Kotlin sources the driver reads. |
| `kotlin` | [object](#platformkotlin) | How Kotlin constructs cross into Dart. |
| `wrapper` | string | Generate a native bridge for members the driver cannot carry across. One of `auto`, `off`, `only`. |
| `build` | [object](#platformbuild) | — |

## fixup.match

| Key | Type | Notes |
| --- | --- | --- |
| `symbol` | string | **Required.** |
| `platform` | string | One of `android`, `ios`, `macos`, `windows`, `linux`, `web`. |

## fixup.nullability

| Key | Type | Notes |
| --- | --- | --- |
| `returns` | string | One of `nonnull`, `nullable`, `unknown`. |

## verify.size_budget

| Key | Type | Notes |
| --- | --- | --- |
| `lines` | integer | At least 1. |

## deps

Packages to resolve and pin in bindsmith.lock.

| Key | Type | Notes |
| --- | --- | --- |
| `maven` | list of string | group:artifact:version coordinates. |
| `repositories` | list of string | Maven repository URLs, searched in order, each https:// or a file:// directory. Defaults to Maven Central; an Android dependency usually needs Google's too. |
| `swiftpm` | list of [object](#depsswiftpm) | — |
| `npm` | list of string | — |
| `nuget` | list of string | — |
| `pkg_config` | list of string | — |

## include

Glob patterns for the symbols to bind, by kind.

| Key | Type | Notes |
| --- | --- | --- |
| `classes` | list of string | — |
| `types` | list of string | — |
| `protocols` | list of string | — |
| `functions` | list of string | — |
| `structs` | list of string | — |
| `enums` | list of string | — |
| `globals` | list of string | — |
| `typedefs` | list of string | — |
| `exports` | list of string | — |

## platform.kotlin

How Kotlin constructs cross into Dart.

| Key | Type | Notes |
| --- | --- | --- |
| `suspend` | string | One of `future`, `callback`. |
| `flow` | string | One of `stream`, `callback`. |

## platform.build

| Key | Type | Notes |
| --- | --- | --- |
| `hook` | string | One of `native_toolchain_c`, `native_toolchain_cmake`. |
| `sources` | list of string | — |

## deps.swiftpm

| Key | Type | Notes |
| --- | --- | --- |
| `url` | string | **Required.** |
| `from` | string | **Required.** |

