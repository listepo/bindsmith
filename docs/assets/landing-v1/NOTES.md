# bindsmith landing v1 — screenshots + icons

Restyled for **Material 3** with a **flat Swiss army knife** mark and a **terminal generate** hero background.
Captured from local Jaspr static build (`site/build/jaspr`) via Chrome CDP.
Desktop ~1440×900; mobile ~390×844 @2x.

## Screens
| File | Theme | Notes |
|------|-------|-------|
| `home-light.png` / `home-dark.png` | light/dark | desktop hero (terminal bg) + platforms |
| `home-mobile-light.png` / `home-mobile-dark.png` | light/dark | ~390×844 |
| `mobile-light.png` / `mobile-dark.png` | light/dark | mobile viewport (+ NavigationBar) |
| `features-light.png` / `features-dark.png` | light/dark | `#features` cards |
| `platforms-light.png` / `platforms-dark.png` | light/dark | `#platforms` grid |
| `cli-light.png` / `cli-dark.png` | light/dark | `#cli` terminal |
| `yaml-light.png` / `yaml-dark.png` | light/dark | YAML card |
| `appbar-detail-light.png` / `appbar-detail-dark.png` | light/dark | AppBar + hero crop |
| `cards-detail-light.png` / `cards-detail-dark.png` | light/dark | platform cards crop |
| `chips-detail-light.png` / `chips-detail-dark.png` | light/dark | FilterChips |
| `buttons-detail-light.png` / `buttons-detail-dark.png` | light/dark | Filled + Text actions |
| `nav-detail-light.png` / `nav-detail-dark.png` | light/dark | NavigationBar pill |
| `theme-toggle-light.png` / `theme-toggle-dark.png` | light/dark | theme control crop |
| `hero-terminal.png` / `hero-terminal.svg` | — | terminal generate backdrop asset |

## Brand icons
| File | Notes |
|------|-------|
| `logo.png` / `icon-logo.png` | Flat Swiss army knife on ink tile |
| `logo-wordmark.png` / `icon-wordmark.png` | mark + wordmark |
| `favicon.png` / `icon-favicon.png` | compact mark |

## UI icon set (M3 outlined, ≥10)
`generate` `platforms` `verify` `doctor` `yaml` `flutter` `init` `watch` `schema` `resolve` `dump` `explain`
SVG sources: `icons/*.svg`

Theme storage key: `bindsmith-theme` (system → light → dark).
Brand SSOT: `docs/brand/` (`DESIGN.md`, `tokens.css`, SVGs).
Logo concept: **flat Swiss army knife / multi-tool** (copper + ink) — multi-platform bindings metaphor.
Hero: `site/web/images/hero-terminal.{png,svg}` with scrim for a11y contrast.
CTAs: one Filled primary + one Text secondary.
