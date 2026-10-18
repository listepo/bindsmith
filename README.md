# bindsmith

One `bindsmith.yaml`, six Flutter platforms. `bindsmith` generates Dart bindings for native APIs on Android, iOS, macOS, Windows, Linux and Web by driving the official generators through their library APIs (ffigen, swiftgen, jnigen, winmd, dart-dbus) and adding a TypeScript `.d.ts` driver for Web, a unified IR with fixup passes, review markers for everything that could not be mapped, and one cross-platform facade over the lot.

Work in progress: the drivers, the IR, the passes and the emitters are in place; the command line generates for the C and Objective-C drivers so far. `plan.md` tracks the rest.

## Getting started

```bash
dart run bindsmith doctor        # what this machine is missing, and how to install it
dart run bindsmith init          # writes bindsmith.yaml + bindsmith.schema.json
dart run bindsmith generate      # drivers → IR → passes → bindings + facade + hook/build.dart
dart run bindsmith verify        # what in the generated code still needs a human
```

Every command, exit codes and the CI checks: [docs/commands.md](docs/commands.md).

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

- `docs/` — the documentation site: [getting started](docs/getting-started.md), [commands](docs/commands.md), [configuration reference](docs/config.md) (generated from the schema), [dependencies and the lock](docs/dependencies.md), [platforms](docs/platforms.md), [fixups](docs/fixups.md), [upgrading](docs/upgrading.md).
- `plan.md` — the implementation plan, per task, with complexity and status.
- `research.md` — findings (RU): landscape, analogs, per-platform recipes, fact-check log.
- `report.html` — the same as a published artifact.
- `AGENTS.md` — how to work in this repository; read it before changing anything.
- `docs/adr/` — decisions already made. `docs/research-raw/` — raw agent reports and fact-check logs.


There is no release yet. Releases are set up to ship a `dart compile exe` binary per OS on
GitHub Releases and a Homebrew formula (`scripts/formula.sh`) in `pyrlyn/homebrew-tap`.
Packages are not published to pub.dev until the creator says so.

## Development

```bash
mise trust && mise install
mise run setup       # dart pub get + npm ci for the .d.ts sidecar
mise run check       # format, dart analyze --fatal-infos, fixtures analyze
mise run test        # dart test (both packages) + node --test (sidecar)
```

## License

You can use this project under **any** of the following licenses, at your choice:

1. [GNU GPLv3](LICENSE): free for open source applications on any platform, including embedded systems.
2. [Royalty-free License](LICENSE-ROYALTY-FREE.md): free for proprietary desktop, mobile, and web applications, as long as you disclose that your application uses this project. Embedded systems are not covered.
3. [Commercial license](PRICING.md): for proprietary applications, including embedded systems, without the attribution requirement.
