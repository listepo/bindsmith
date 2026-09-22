# bindsmith — Design System

## Overview

**bindsmith** generates Flutter bindings from one YAML to six platforms. The brand mark is a **flat Swiss army knife** (multi-tool) on an ink rounded-square tile in copper `#C87941` / amber `#E8A05C` on ink `#1A1C1F` — metaphor: one multi-tool for multi-platform bindings. Geometry is tight (even tool widths, optical balance) so the mark stays readable at 16px favicon and 64px tile. Not a B monogram, not FAB+braces, not chevron/pips, not a Flutter/Dart logo.

Visual direction: **Material 3 first** (tonal surfaces, calm actions — **exactly one Filled primary + one Text secondary**, calm AppBar over hero, FilterChips, outlined Card variant, NavigationBar pill, snackbar tip, surface-container ladder, 4/8pt rhythm, radius 12/16/28). Hero sits on a **terminal `bindsmith generate`** card (mono grid, status line, copper success ticks) with a light/dark scrim for AA contrast. Copper is the seed / primary. Flutter/Dart azure is **secondary only**. Theme cycle **system → light → dark** via `bindsmith-theme` must keep working.

## Material 3 color roles

Seed: copper `#C87941`. Full role map (see `tokens.css`):

| Role | Light | Dark | Use |
|------|-------|------|-----|
| primary | `#C87941` | `#E8A05C` | Filled CTA, brand |
| on-primary | `#FFFFFF` | `#1A1C1F` | Text/icons on primary |
| primary-container | `#F5E6D4` | `#2A2218` | Tonal buttons, soft wash |
| on-primary-container | `#5C3318` | `#F5E6D4` | Text on primary-container |
| secondary | `#0175C2` | `#13B9FD` | Flutter badge / azure cue |
| on-secondary | `#FFFFFF` | `#003554` | On azure |
| secondary-container | `#E3F2FD` | `#0D2A3A` | FilterChips selected / nav pill |
| tertiary | `#A35F2E` | `#E8A05C` | Warm forge accent |
| surface | `#F7F4EF` | `#121416` | Page |
| surface-bright | `#FFFBFF` | `#1A1C1F` | AppBar / elevated |
| surface-container-lowest | `#FFFFFF` | `#0C0D0F` | Ladder lowest |
| surface-container-low | `#F0EBE4` | `#1A1C1F` | Cards low |
| surface-container | `#E8E1D8` | `#22252A` | Cards / nav bar |
| surface-container-high | `#DED5CA` | `#2A2E34` | Hover / high |
| surface-container-highest | `#D4CBC0` | `#353A42` | Highest tonal |
| on-surface | `#1A1C1F` | `#EDE8E1` | Body text |
| on-surface-variant | `#5C564E` | `#A39B90` | Muted |
| outline | `#CAC3B8` | `#3E444E` | Borders / outlined cards |
| outline-variant | `#DDD6CC` | `#2C3038` | Hairlines |
| inverse-surface | `#2F3134` | `#EDE8E1` | Snackbar strip |
| error | `#B5403A` | `#E07068` | Errors |

Legacy `--bs-accent*` / `--bs-surface-*` aliases map onto these roles.

## Typography

- **Sans:** Roboto (webfont) + IBM Plex Sans / system-ui
- **Mono:** IBM Plex Mono (CLI, chips, labels)
- Scale: 12 / 14 / 16 / 20 / 28 / 40 — display tracking −0.02em
- Weights: 400 body, 500 labels / buttons, 600 titles

## Layout & shape

- Max width: 960px landing, 720px prose
- Grid: 8px base; card padding 16–20px; section gaps 48–64px
- **Radius scale:** 12 (controls) / 16 (md) / 20 (cards) / 28 (hero tiles / sheets)
- **Elevation:** elev-1 AppBar & cards, elev-2 code cards, elev-3 hero mark
- **State layers:** hover/press via `--bs-state-hover` / `--bs-state-press`

## Components

- **FilledButton:** primary fill, on-primary, radius 12, elev-1 — **default primary CTA**
- **TextButton:** primary/on-surface fg, no border, state-layer hover — **default secondary**
- Tonal / Outlined exist in tokens but are **not stacked** in hero chrome (keep CTAs calm)
- **FilterChip:** stadium; selected → secondary-container + check
- **Card:** surface-container-low; **outlined** variant → surface + outline, no elev
- **Snackbar tip:** inverse-surface strip under AppBar (optional)
- **AppBar:** sticky surface-bright, denser ~64px, avatar + icon actions + theme
- **NavigationBar:** surface-container; selected **M3 pill** (secondary-container)
- **Theme toggle:** system → light → dark (`bindsmith-theme`)

## Logo

**Locked mark (do not reinvent):** Flat **Swiss army knife / multi-tool** — geometric handle + blade + bit/side tools around a pivot rivet, even stroke weights, 2–3 flat copper/amber fills on ink, **no gradients / skeuomorph / photo realism**. Metaphor: multi-tool = multi-platform bindings. Sync `logo.svg` / favicon / wordmark / PNGs. No Flutter bird, no Dart logo, no anvil.

## Mini landing wire

1. Dense M3 AppBar: mark + wordmark + nav + icon + theme + avatar
2. Optional snackbar tip strip
3. Hero: terminal generate backdrop (`hero-terminal.{png,svg}`) + scrim, mark, pitch, badges, **one Filled + one Text** CTAs only
4. Actions detail (Filled + Text only — no Tonal/Outlined stack)
5. Platforms: FilterChips + six cards (one outlined)
6. Generate CLI + YAML cards
7. Features + surface-container ladder
8. Mobile NavigationBar with pill indicator
9. Footer

## Do / Don't

**Do**
- Lead with M3 tonal surfaces and copper primary
- Map every color to an M3 role in `tokens.css`
- Keep azure secondary only (FilterChip / nav pill)

**Don't**
- Don’t lead with glass / nerd-forge chrome
- Don’t reuse B monogram, FAB+`{ }` braces, or chevron/pips marks
- Don’t crowd CTAs with Tonal/Outlined stacks — prefer Filled + Text
- Don’t copy Flutter bird or Dart logo
- Don’t use teal (ketch) or cyan-as-primary (rtok)
