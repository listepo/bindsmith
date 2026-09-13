# Roadmap

Approved work that is not in the active `plan.md` table.

- GObject (Linux) `.gir` bindings, once a generator is mature enough to drive. The architecture table already names this as later; community `gir-binding-gen` is immature.
- When dart-lang/web publishes `js_interop_gen`, swap it in for the TypeScript sidecar.

## Out of scope for v1

- C++ parsing (emit an `extern "C"` shim instead)
- macros
- GUI
- mandatory AI features
- our own formatter/analyzer
- dynamic runtime
