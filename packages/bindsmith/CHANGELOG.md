# Changelog

All notable changes to bindsmith are recorded here.

Version policy: bindsmith takes a **minor** bump for every upstream generator
major it moves to (`ffigen` 22 → 23 is `0.x → 0.x+1`). The changelog names
the generator. Patch releases are fixes that do not change generated output
for a given configuration.

## Unreleased

- C and Objective-C drivers: `sysroot`, `framework_paths` and
  `compiler_options` keys; on macOS the C driver uses `xcrun --show-sdk-path`
  so Apple SDK C headers parse.
- Facade: facade enums convert to and from the binding's by value; types a
  bound signature mentions are wrapped; members it cannot spell are dropped
  with a reason; bare `Pointer<…>` and `objc.` spellings resolve.
- Build hook: Objective-C glue is compiled with `-fobjc-arc` and linked against
  the frameworks of its headers.

## 0.1.0

First public CLI: one `bindsmith.yaml`, six Flutter platforms, unified IR,
review markers, lockfile. Runtime lives in `bindsmith_runtime`.
