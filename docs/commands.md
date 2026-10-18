# Commands

Every `bindsmith` command, its exit codes, and which commands are safe in CI. A first run is in [getting-started.md](getting-started.md).

## Reference

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
