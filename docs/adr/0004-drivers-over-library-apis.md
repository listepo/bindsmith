# ADR-0004: Drivers wrap upstream generators through their library APIs

Status: accepted (2026-09-08)

Each platform driver constructs the upstream generator object (`FfiGenerator`, `JniGenerator`, `SwiftGenerator`, winmd reader, dart-dbus) in-process and reads back its declarations; no driver parses console output or generated text as its primary source. Where an upstream exposes names but not types (ffigen 22 public AST), the driver reads the generated Dart with package:analyzer — still a library API. Upstream is pinned to one major per driver behind exactly one adapter file, with contract tests, so a breaking release is fixed in one place. Rejected: re-implementing parsers (libclang, class-file, Swift) ourselves.
