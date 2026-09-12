# ADR-0005: Pull model, review markers and no silent drops

Status: accepted (2026-09-08)

Generation is opt-in per symbol: the config lists the types, functions and members to bind (globs allowed), as in CsWin32 `NativeMethods.txt` and windows-bindgen `--filter`; `bindsmith dump` prints everything visible in that syntax so the list is copied, not typed. Anything a driver or pass cannot map is not removed: it becomes a `Marker` on the IR (`verify` with a reason, or `dropped`), is emitted as `@BindsmithVerify` on the facade or listed in the generated file, and makes `bindsmith verify` fail until the developer acknowledges it in `fixups` (`ack: true`) or fixes the mapping — the Objective Sharpie `[Verify]` idea. This trades convenience for a binding whose every gap is visible in review.
