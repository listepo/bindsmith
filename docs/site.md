---
title: bindsmith
tagline: Generate Dart bindings for native APIs on all six Flutter platforms from one YAML config.
repo: https://github.com/pyrlyn/bindsmith
install: "git clone https://github.com/pyrlyn/bindsmith && cd bindsmith && mise install && mise run setup"
version: "0.1.0"
status: "In development · no release yet"
accent: "#4FB8AD"
order: 9
---

<!-- Website copy for the pyrlyn project site, copied to pyrlyn/landing as
content/projects/bindsmith.md; front matter follows CONTENT_CONTRACT.md in that repository.
Sources (checked 2026-10-14): README.md, docs/getting-started.md and docs/commands.md; version from packages/bindsmith/pubspec.yaml (no release yet, hence status). accent is --accent in the bindsmith site styles. -->

## Overview

One `bindsmith.yaml`, six Flutter platforms. bindsmith generates Dart bindings for native APIs on
Android, iOS, macOS, Windows, Linux and Web by driving the official generators (ffigen, swiftgen,
jnigen, winmd, dart-dbus) and a TypeScript `.d.ts` driver for Web, through a unified IR with fixup
passes and one cross-platform facade.

bindsmith is in development with no release yet: the drivers, IR, passes and emitters are in
place, and the command line generates for the C and Objective-C drivers so far.

## Features

- **One config.** `bindsmith init` writes `bindsmith.yaml` and the JSON Schema an editor checks it against.
- **doctor.** Says which native toolchains this machine is missing and how to install them.
- **Review markers.** Anything a driver could not map keeps a marker; `bindsmith verify` fails until each is answered.
- **CI checks.** `generate --check`, `diff` and `resolve --check` fail when output, the native API or the lock went stale.
- **Pinned dependencies.** `bindsmith resolve` pins Maven dependencies with sha256 in `bindsmith.lock`.
- **explain.** Says what one symbol became on each platform and where it came from.

## Install

Set up from the repository:

```bash
git clone https://github.com/pyrlyn/bindsmith && cd bindsmith && mise install && mise run setup
```

## Usage examples

Check the toolchains, then start a config:

```bash
dart run bindsmith doctor
dart run bindsmith init
```

Generate bindings and see what still needs a human:

```bash
dart run bindsmith generate
dart run bindsmith verify
```

## Links

- Repository: <https://github.com/pyrlyn/bindsmith>
- Documentation: <https://github.com/pyrlyn/bindsmith/tree/main/docs>
- License: your choice of GNU GPLv3, a royalty-free license, or a commercial license (see <https://github.com/pyrlyn/bindsmith#license>)
