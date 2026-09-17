# bindsmith — Design System

## Overview

**bindsmith** generates Flutter bindings from one YAML to six platforms. The brand metaphor is a **Dart forge**: six platform pips converge into a birdless geometric chevron / bind node on a Material tile — bindings forged, not anvils hammered.

Visual direction: **Material 3 (Google) + Flutter/Dart cues + nerd**. Tonal surface ladder, 12–16px radii, filled/tonal buttons, subtle elevation (shadows or tonal layers), state layers. Primary brand copper `#C87941` stays locked; Flutter/Dart azure (`#0175C2` / `#13B9FD`) is secondary only — chips, badges, one logo pip. Nerd layer: IBM Plex Mono labels, YAML/CLI cards, platform chips, hairlines.

Theme cycle **system → light → dark** via `bindsmith-theme` must keep working. Reduced-transparency / no-backdrop fallbacks may remain where useful; glass is **not** the primary look.

Identity: copper forge heat on ink `#1A1C1F` Material tiles; azure as a Flutter wink, never the hero accent.

## Colors

### Brand / accents

| Token | Hex | Use |
|-------|-----|-----|
| accent | `#C87941` | Primary CTA / brand (copper) |
| accent-hover | `#B06835` | Hover |
| accent-muted | `#E8A05C` | Soft copper |
| accent-soft | `#F5E6D4` | Tonal copper wash (light) |
| flutter | `#0175C2` | Flutter badge / secondary |
| dart | `#13B9FD` | Dart chip / logo pip |
| ink | `#1A1C1F` | Logo tile / primary ink |

### Light (Material tonal ladder)

| Token | Hex | Use |
|-------|-----|-----|
| bg | `#F7F4EF` | Page / surface |
| bg-elevated | `#FFFBFF` | AppBar / elevated surface |
| surface-1 | `#F0EBE4` | Surface container low |
| surface-2 | `#E8E1D8` | Surface container |
| surface-3 | `#DED5CA` | Surface container high |
| border | `#CAC3B8` | Outline |
| border-hairline | `#DDD6CC` | Outline variant |
| fg | `#1A1C1F` | On-surface |
| fg-muted | `#5C564E` | On-surface variant |
| fg-subtle | `#8A8278` | Hint / caption |
| code-bg | `#1A1C1F` | Code blocks |
| code-fg | `#F0C078` | Code highlight |

### Dark (Material tonal ladder)

| Token | Hex | Use |
|-------|-----|-----|
| bg | `#121416` | Page |
| bg-elevated | `#1A1C1F` | AppBar / elevated |
| surface-1 | `#22252A` | Container low |
| surface-2 | `#2A2E34` | Container |
| surface-3 | `#353A42` | Container high |
| border | `#3E444E` | Outline |
| border-hairline | `#2C3038` | Outline variant |
| fg | `#EDE8E1` | On-surface |
| fg-muted | `#A39B90` | On-surface variant |
| fg-subtle | `#6E675E` | Hint |
| accent | `#E8A05C` | Primary CTA (dark) |
| accent-hover | `#F0C078` | Hover |
| accent-muted | `#C87941` | Soft copper |
| accent-soft | `#2A2218` | Tonal copper wash |
| code-bg | `#0C0D0F` | Code |
| code-fg | `#F0C078` | Highlight |

## Typography

- **Sans (body / Material UI):** Roboto (webfont) with IBM Plex Sans / system-ui fallback
- **Mono (nerd labels, chips, CLI, YAML headers):** IBM Plex Mono (fallback JetBrains Mono, ui-monospace)
- Scale: 12 / 14 / 16 / 20 / 28 / 40 — display tracking −0.02em
- Weights: 400 body, 500 labels / buttons, 600 section titles

## Layout & shape

- Max content width: 960px landing, 720px prose
- Grid: 8px base; card padding 16px; section gaps 48–64px
- Radii: **12px** controls, **16px** cards / logo tile (Material 3)
- Elevation: tonal layering first; soft shadow (`elev-1` / `elev-2`) for AppBar and cards
- State layers: hover/press via surface step or translucent accent wash

## Components

- **Filled button:** copper fill, on-primary white/ink, 12px radius, mono or Roboto medium label
- **Tonal button:** accent-soft / surface-2 fill, accent fg, no heavy border
- **Outlined / ghost:** outline variant + on-surface muted
- **Cards:** surface elevated or container, 16px radius, elev-1; platform cards may use tonal fill
- **Chips:** tonal copper or azure (Flutter/Dart badges only); mono 12px
- **Code / YAML cards:** dark slate block; mono header with hairline; CLI prompt in copper
- **AppBar:** sticky tonal elevated surface, 1px outline-variant bottom, subtle elev-1 (not glass-first)
- **Theme toggle:** cycles system → light → dark (`bindsmith-theme`)

## Logo

Material ink tile + six platform pips (one azure) converging into a **Dart-like chevron bind node** in copper. No Flutter bird, no anvil plate. Works at 16px favicon and 64px tile.

## Mini landing wire

1. Material AppBar: mark + wordmark + nav + theme
2. Hero: mark, pitch, Flutter/Dart tonal badges, filled + tonal CTAs
3. Platforms: six M3 cards / tonal chips
4. Generate CLI card + YAML snippet card
5. Features: tonal Material cards (nerd mono eyebrows)
6. Footer: Listepo / bindsmith

## Do / Don't

**Do**
- Lead with Material tonal surfaces and copper CTAs
- Keep azure as secondary Flutter/Dart cue only
- Prefer mono for CLI/YAML/platform nerd labels

**Don't**
- Don’t make glass the primary lock (fallback OK)
- Don’t use teal/mint (ketch) or cyan-as-primary (rtok)
- Don’t copy the Flutter logo bird or use purple AI gradients
