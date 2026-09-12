# Fixups

A generated API is not always the API you want to ship. A fixup is a
declarative edit applied to the model after the drivers have run and before
anything is emitted, so the result is still generated code you never hand-edit.

```yaml
fixups:
  - match: { symbol: "Client.*Legacy*" }
    hide: true
  - match: { platform: android, symbol: "com.example.Client#connect$2" }
    rename: connectWithTimeout
```

Fixups apply in the order they are written, each to whatever the previous ones
left, so a rename followed by a match on the new name works and a match on the
old one no longer does.

## Matching

`match.symbol` is a glob, in one of three spellings:

| Spelling | Matches |
| --- | --- |
| `Client` or `com.example.Client` | a declaration, by its Dart name or its native identifier |
| `Client.connect` | members of declarations named `Client` |
| `com.example.Client#connect` | members, with the declaration matched by native identifier |

`*` stands for any run of characters and `?` for one. Everything else is
literal, including the `$` in a jnigen overload suffix, so
`com.example.Client#connect$2` needs no escaping.

`match.platform` restricts a fixup to one platform. Leave it out and the fixup
applies to every platform that has the symbol — which is usually what you want
for a rename, and rarely what you want for a threading annotation.

## What a fixup can do

| Key | Effect |
| --- | --- |
| `rename` | Give the declaration or member a different Dart name. |
| `hide` | Keep it in the model, marked as dropped, and never emit it. |
| `threading` | `main` or `any`: declare which thread the symbol has to be called on. On a declaration this applies to every member. |
| `nullability` | `returns: nonnull \| nullable \| unknown`, overriding what the driver inferred. |
| `ack` | Remove the verify markers: a human has reviewed this symbol. |

## Recipes

**Hide a deprecated family.** Hiding keeps the symbol in `bindsmith dump` with
a marker saying a fixup hid it, so a reviewer can see the API was trimmed
rather than never generated.

```yaml
- match: { symbol: "*_deprecated_*" }
  hide: true
```

**Fix a name a generator had to mangle.** jnigen numbers overloads, and
`connect$2` tells a reader nothing:

```yaml
- match: { platform: android, symbol: "com.example.Client#connect$2" }
  rename: connectWithTimeout
```

**Declare a main-thread requirement.** Nothing in a C or Objective-C header
says a function must be called on the platform thread, but the documentation
does, and calling it elsewhere fails in ways that look like corruption:

```yaml
- match: { platform: ios, symbol: "AVPlayer.play" }
  threading: main
```

**Tighten a nullability a driver had to guess.** An Objective-C header with no
audited regions yields `unknown`, which becomes nullable plus a verify marker.
When you have read the implementation, say so:

```yaml
- match: { symbol: "Client.fetch" }
  nullability: { returns: nonnull }
```

**Acknowledge a marker you have reviewed.** `ack` removes the verify markers
from one symbol and nothing else, which is what stops `bindsmith verify`
failing on it. Use it per symbol, never with a broad glob — the markers are the
only record that a translation was inexact, and a pattern like `symbol: "*"`
with `ack: true` silently discards every one of them.

```yaml
- match: { symbol: "Client.onEvent" }
  ack: true
```

## What a fixup is not for

A fixup edits the model, not the semantics. It cannot change a parameter type,
add a method, or make a callback safe to invoke from another thread — it can
only record what you already know to be true. If you need a different shape at
the boundary, that is a wrapper: a generated `@objc` Swift bridge, a generated
Kotlin bridge, or a C++ `extern "C"` shim, each committed and fed back through
the ordinary driver.

The one thing to be careful with is `ack`. Everything else here is visible in
the generated code; `ack` removes a warning, and it is the one fixup that can
make a real problem invisible.
