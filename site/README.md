# bindsmith site (Jaspr static)

Static marketing landing for **bindsmith**, built with [Jaspr](https://docs.jaspr.site/) in **static** (SSG) mode.

This is **not** Hugo. Sibling Listepo sites (ketch / cox / rtok) use Hugo; bindsmith uses Jaspr so the landing can stay in Dart and ship plain HTML/CSS to GitHub Pages.

## Layout

| Path | Purpose |
|------|---------|
| `lib/pages/home.dart` | Landing structure (hero, chips, code sample, footer) — keep thin |
| `lib/app.dart` | Root `@client` component |
| `lib/main.server.dart` | SSG document shell (`<base href="/bindsmith/">`, meta, CSS links) |
| `web/images/` | Logos (`logo.svg`, `logo-wordmark.svg`) |
| `web/favicon.svg` | Favicon |
| `web/styles/tokens.css` | Design tokens (from `docs/brand/tokens.css` + `prefers-color-scheme`) |
| `web/styles/landing.css` | Landing layout / component styles |
| `docs/brand/` (repo root) | Brand source of truth — copy refined assets into `web/` |

Built output: **`build/jaspr/`** (ignored by git).

## Commands

From this directory (`site/`):

```bash
# one-time: activate CLI (ensure ~/.pub-cache/bin is on PATH)
dart pub global activate jaspr_cli

dart pub get
jaspr serve    # local preview
jaspr build    # writes build/jaspr/
```

Project Pages base URL: `https://listepo.github.io/bindsmith/`  
`Document(base: 'bindsmith')` sets `<base href="/bindsmith/">` for asset resolution.

## For design / logo refinements

1. Prefer updating **`docs/brand/`** first (source of truth).
2. Copy into the site:
   - `docs/brand/logo.svg` → `web/images/logo.svg`
   - `docs/brand/logo-wordmark.svg` → `web/images/logo-wordmark.svg`
   - `docs/brand/favicon.svg` → `web/favicon.svg`
   - `docs/brand/tokens.css` → `web/styles/tokens.css` (re-add the `prefers-color-scheme` block at the bottom if you overwrite)
3. Tweak layout in **`web/styles/landing.css`** — avoid heavy Dart styling.
4. Screenshots for the PR still belong under **`docs/assets/landing-v1/`** (not auto-generated here).

Light/dark: FOUC-safe toggle cycles **system → light → dark** (`localStorage["bindsmith-theme"]`), sets `data-theme` on `<html>`. CSS tokens honor light, dark, and system (`prefers-color-scheme`). Boot script in `lib/main.server.dart`; logic in `web/js/theme.js`.

## Deploy

GitHub Actions workflow: `.github/workflows/pages.yml`  
On push to `main` (paths under `site/` / brand / workflow), builds with Dart + `jaspr_cli` and deploys `site/build/jaspr` to GitHub Pages.
