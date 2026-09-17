# Contributing

Repository prose (commits, PRs, docs, comments) is English. Read
[`AGENTS.md`](AGENTS.md) before changing anything — layout, conventions, and
trust boundaries live there.

## Checks

```bash
mise trust && mise install
mise run setup
mise run check
mise run test
```

Generated bindings are reviewed like any other code. Prefer answering
`@BindsmithVerify` markers (or an `ack: true` fixup) over deleting them quietly.

## Docs

User-facing guides live under [`docs/`](docs/). Keep the tone concrete and short;
do not invent features or metrics that the tree does not already document.
