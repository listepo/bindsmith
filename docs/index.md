# bindsmith

One `bindsmith.yaml`, six Flutter platforms. bindsmith reads a native API and
writes the Dart that calls it — for Android, iOS, macOS, Windows, Linux and
Web — by driving the official generators through their library APIs and adding
what none of them cover.

- **[Getting started](getting-started.md)** — install, `init`, `generate`, and
  what lands in your package.
- **[Configuration reference](config.md)** — every key, generated from the JSON
  Schema the loader validates against.
- **[Platforms](platforms.md)** — one page per driver: what it needs on the
  host, what it takes, what it cannot do.
- **[Fixups](fixups.md)** — the cookbook for the edits you apply to a
  generated API without hand-editing generated files.
- **[Upgrading](upgrading.md)** — what happens when an upstream generator
  releases a new major.

Decisions already made are in [`docs/adr/`](adr/). Background research is in
`research.md`; raw evidence lives under `docs/research-raw/`.

Contributors: see [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## What it is not

bindsmith generates code ahead of time and commits it. There is no runtime
reflection, no dynamic proxy, and nothing that inspects a native library while
your app is running. What you ship is Dart you can read, and a review marker
anywhere the translation was not exact.

It also does not hide a failure. A declaration that no driver can map is not
dropped: it stays in the model with a marker saying why, `bindsmith dump`
prints it, and `bindsmith explain` tells you what happened to one symbol.
