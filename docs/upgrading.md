# Upgrading

## How bindsmith is pinned

Every upstream generator is pinned to a single major version — `ffigen:
^22.0.0`, not `>=22`. Two of them, swiftgen and swift2objc, are pre-1.0 and
still moving. That pin is deliberate: a generator's *output* is bindsmith's
input, so a new major does not merely change an API call, it changes the code
your users compile.

Each upstream generator is reached through exactly one adapter file under
`lib/src/drivers/<name>/`, and nothing else in bindsmith imports it. When an
upstream release breaks something, the fix is in that one file. It is never a
`try`/`catch` spread into a pass or an emitter.

## What a bindsmith release means for you

bindsmith takes a minor version bump for every upstream generator major it
moves to. So `0.4.x → 0.5.0` may change what is generated even though your
configuration did not change, and the changelog says which generator moved.

Nothing regenerates behind your back. Generated files are committed in your
repository, and they change when you run `bindsmith generate`.

## Upgrading safely

The safe order is: know what you have, upgrade, then see what moved.

```bash
dart run bindsmith dump > before.json     # what you have now
dart pub upgrade bindsmith
dart run bindsmith diff before.json       # what the new version does differently
```

`diff` compares symbol by symbol, on shape rather than on the raw model,
because markers and doc comments move constantly while a changed signature is
what breaks a caller. It exits 1 when anything differs and prints a `~` line
with the previous shape underneath, so the review is a diff of your API, not a
diff of thousands of generated lines.

Then regenerate and read what changed:

```bash
dart run bindsmith generate
git diff
```

Pay attention to markers that appeared. A new verify marker means the new
version knows something the old one did not, and it is the one thing in a
regeneration diff that is always worth reading.

## Keeping the check in CI

```bash
dart run bindsmith generate --check
```

fails when the committed output is not what the current bindsmith, on the
current headers, would produce. It regenerates into a directory it deletes and
compares, so it never writes into the checkout. Add it beside your analyzer
step: the failure you want to catch is a dependency bump that changed generated
code that nobody regenerated.

Because the throwaway directory is somewhere different on every run, a passing
check also proves that no generated file has recorded where it was generated.
That is not hypothetical: ffigen used to write the Objective-C glue's `#import`
as a relative walk from the generated file to the header it parsed, which for
an absolute entry point put a developer's home directory into a committed file
that then built on no other machine.

## When an upstream generator drops something new

A generator that stops supporting a construct does not make it disappear from
your API silently. It arrives as a marker: the driver diffs what it asked for
against what came back, and anything missing is recorded with the reason.
`bindsmith explain` on the symbol tells you which one it was, and the wrapper
path — a generated Swift `@objc` bridge, a Kotlin bridge, or a C++ shim — is
how you get it back.
