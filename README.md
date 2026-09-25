# bindsmith

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=listepo_bindsmith&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=listepo_bindsmith) [![Coverage](https://sonarcloud.io/api/project_badges/measure?project=listepo_bindsmith&metric=coverage)](https://sonarcloud.io/component_measures?id=listepo_bindsmith&metric=coverage) [![Tests](https://img.shields.io/sonar/tests/listepo_bindsmith?server=https%3A%2F%2Fsonarcloud.io&compact_message)](https://sonarcloud.io/component_measures?id=listepo_bindsmith&metric=tests)

One `bindsmith.yaml`, six Flutter platforms. `bindsmith` generates Dart bindings for native APIs on Android, iOS, macOS, Windows, Linux and Web by driving the official generators through their library APIs (ffigen, swiftgen, jnigen, winmd, dart-dbus) and adding a TypeScript `.d.ts` driver for Web, a unified IR with fixup passes, review markers for everything that could not be mapped, and one cross-platform facade over the lot.

Work in progress: the drivers, the IR, the passes and the emitters are in place; the command line generates for the C and Objective-C drivers so far. `plan.md` tracks the rest.

## Getting started

```bash
dart run bindsmith doctor        # what this machine is missing, and how to install it
dart run bindsmith init          # writes bindsmith.yaml + bindsmith.schema.json
dart run bindsmith generate      # drivers → IR → passes → bindings + facade + hook/build.dart
dart run bindsmith verify        # what in the generated code still needs a human
```

`init` writes the JSON Schema next to the config and points at it from a `# yaml-language-server:` header, so an editor completes and checks the file as you fill it in.

| Command | What it does |
| --- | --- |
| `init` | Write a starter config and the schema it is checked against. `--force` overwrites. |
| `doctor` | Check the toolchains the configured platforms need (libclang, JDK, node, Xcode, Build Tools, pkg-config) and print how to install the missing ones. `--json` for a script; exits 1 when one is missing. |
| `resolve` | Resolve every declared dependency and pin what it turned out to be in `bindsmith.lock`. `--check` exits 1 when the lock is stale; `--offline` uses the download cache only. |
| `generate` | Run each platform's driver and write the bindings, the facade and `hook/build.dart`. |
| `generate --check` | The same run into a throwaway directory, compared against what is committed. Writes nothing; exits 1 if anything is stale. |
| `verify` | Read the committed generated code back: `@BindsmithVerify` markers still waiting on a human, the `size_budget`, and one public API across the io and web facades. Runs no generator; exits 1 while anything is unresolved. |
| `dump` | Print the IR as JSON, including everything that was dropped. |
| `diff <dump.json>` | Compare the API against an earlier `dump`, symbol by symbol. Exits 1 if anything changed. |
| `explain <pattern>` | Say what one symbol became on each platform, where it came from, and every marker on it. |
| `watch` | Regenerate whenever the config or one of its headers changes. |
| `schema` | Print the JSON Schema on its own. |

`doctor` runs without a configuration too — on a fresh machine it looks at everything the host could have and requires nothing. Every command but `init`, `doctor` and `schema` takes `--config` (default `bindsmith.yaml`), `--platform` (repeatable) and `--verbose`. Exit codes follow `sysexits(3)`: 1 something differs, 64 bad arguments, 65 a config that cannot be used, 66 a file that is not there, 70 generation itself — so a script can tell "fix your config" from "the generator broke".

Only `generate`, `watch` and `resolve` write into your project. `dump`, `diff`, `explain` and `generate --check` point the generators at a directory they throw away, so they are safe to run in CI on a clean checkout:

```bash
dart run bindsmith dump > api.json    # commit this
dart run bindsmith diff api.json      # in CI: fails when the native API moved
dart run bindsmith generate --check   # in CI: fails when the checked-in output is stale
dart run bindsmith resolve --check    # in CI: fails when bindsmith.lock is stale
```

## Dependencies and the lock

A platform that declares dependencies gets them resolved and pinned:

```yaml
platforms:
  android:
    driver: jvm
    deps:
      maven: ["androidx.biometric:biometric:1.2.0-alpha05"]
      repositories:
        - https://dl.google.com/dl/android/maven2/
        - https://repo1.maven.org/maven2/
```

`bindsmith resolve` follows the transitive graph, downloads into `.dart_tool/bindsmith/`, and writes `bindsmith.lock` with the sha256 of every file it landed on. Commit that file. The download cache mirrors a repository's own layout, so it *is* one, and every later run resolves from it — `--offline` makes that a requirement rather than a hope.

A repository URL is `https://` or a `file://` directory, the same two things Gradle accepts; plain `http://` is refused, because an artifact fetched over it is one that whoever sits between you and the mirror chose. A version range, `LATEST` and `-SNAPSHOT` are refused for the same kind of reason: each makes one coordinate mean different bytes on a different day, and there would be nothing honest to write in the lock.

## Configuration

```yaml
# yaml-language-server: $schema=bindsmith.schema.json
name: my_sdk
output: lib/src/generated       # under lib/, so every binding has a package: URI
facade:
  library: lib/my_sdk.dart

platforms:
  linux:
    driver: c
    headers: [third_party/example/include/example.h]
    include: { functions: ["example_*"], structs: ["example_*"] }
    build:
      sources: [src/example.c]
  macos:
    driver: objc
    headers: [third_party/Example.framework/Headers/Example.h]
    include: { types: ["EXAMPLE*"] }
```

Nothing is bound that was not asked for, and nothing asked for disappears quietly: a declaration a driver could not map keeps a marker saying why, which `dump` prints and which `@BindsmithVerify` carries into the generated code. `bindsmith verify` fails while any of them is still there, so a marker has to be answered rather than scrolled past — either by fixing the binding, by deleting the annotation, or by an [`ack: true` fixup](docs/fixups.md). It needs no toolchain, which makes it the cheap gate to run on every push.

## Repository

- `docs/` — the documentation site: [getting started](docs/getting-started.md), [configuration reference](docs/config.md) (generated from the schema), [platforms](docs/platforms.md), [fixups](docs/fixups.md), [upgrading](docs/upgrading.md).
- `plan.md` — the implementation plan, per task, with complexity and status.
- `research.md` — findings (RU): landscape, analogs, per-platform recipes, fact-check log.
- `report.html` — the same as a published artifact.
- `AGENTS.md` — how to work in this repository; read it before changing anything.
- `docs/adr/` — decisions already made. `docs/research-raw/` — raw agent reports and fact-check logs.


GitHub Releases ship a `dart compile exe` binary per OS. Homebrew is a formula
(`scripts/formula.sh`) in `listepo/homebrew-tap`. Packages are not published to
pub.dev until the creator says so.

## Development

```bash
mise trust && mise install
mise run setup       # dart pub get + npm ci for the .d.ts sidecar
mise run check       # format, dart analyze --fatal-infos, fixtures analyze
mise run test        # dart test (both packages) + node --test (sidecar)
```
