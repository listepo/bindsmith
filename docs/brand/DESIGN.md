# bindsmith — Design System

## Overview

**bindsmith** generates Flutter bindings from one YAML to six platforms. The brand metaphor is a forge: wires converging into a single bind node on an anvil plate. Visual tone is calm industrial nerd — copper heat against ink slate, mono labels, hairline borders, no purple AI chrome.

Identity: copper/amber accent family + ink slate surfaces. Distinct from ketch mint and rtok cyan.

## Colors

### Light

| Token | Hex | Use |
|-------|-----|-----|
| bg | `#F7F4EF` | Page background (warm paper) |
| bg-elevated | `#FFFFFF` | Cards, panels |
| surface-1 | `#EFEAE3` | Nested surface |
| surface-2 | `#E4DDD3` | Hover / selected |
| surface-3 | `#D6CCC0` | Pressed / deep nest |
| border | `#C9BDB0` | Default border |
| border-hairline | `#DDD4C9` | Divider / subtle edge |
| fg | `#1A1C1F` | Primary text / ink |
| fg-muted | `#5C564E` | Secondary text |
| fg-subtle | `#8A8278` | Tertiary / captions |
| accent | `#C87941` | Primary CTA / links |
| accent-hover | `#B06835` | Hover state |
| accent-muted | `#E8A05C` | Soft accent / charts |
| accent-soft | `#F5E6D4` | Accent wash / badges |
| code-bg | `#1A1C1F` | Code blocks |
| code-fg | `#F0C078` | Code highlight |

### Dark

| Token | Hex | Use |
|-------|-----|-----|
| bg | `#121416` | Page background |
| bg-elevated | `#1A1C1F` | Cards, panels |
| surface-1 | `#22252A` | Nested surface |
| surface-2 | `#2A2E34` | Hover / selected |
| surface-3 | `#353A42` | Pressed |
| border | `#3E444E` | Default border |
| border-hairline | `#2C3038` | Divider |
| fg | `#EDE8E1` | Primary text |
| fg-muted | `#A39B90` | Secondary |
| fg-subtle | `#6E675E` | Tertiary |
| accent | `#E8A05C` | Primary CTA |
| accent-hover | `#F0C078` | Hover |
| accent-muted | `#C87941` | Soft accent |
| accent-soft | `#2A2218` | Accent wash |
| code-bg | `#0C0D0F` | Code blocks |
| code-fg | `#F0C078` | Code highlight |

## Typography

- **Mono (primary UI labels, code, nav):** IBM Plex Mono (fallback JetBrains Mono, ui-monospace)
- **Sans (body, long-form):** IBM Plex Sans (fallback system-ui)
- Scale: 12 / 14 / 16 / 20 / 28 / 40 — tracking tight on display (−0.02em), normal on body
- Weights: 400 body, 500 labels, 600 headings / wordmark

## Layout

- Max content width: 960px docs, 720px marketing prose
- Grid: 8px base; cards 12–16px padding; section gaps 48–64px
- Hairline 1px borders; prefer surface ladder over heavy shadows
- Logo tile: 64×64 viewBox, 12px corner radius

## Components

- **Buttons:** solid accent fill, mono label, 8px radius; ghost = hairline + muted fg
- **Inputs:** surface-1 fill, hairline border, focus ring = accent at 40% opacity
- **Code:** dark slate block even in light theme; copper syntax accents
- **Chips / platform tags:** accent-soft bg, accent text, mono 12px
- **Nav:** mono uppercase micro-labels (letter-spacing 0.06em) for section titles

## Mini landing wire

1. Hero: mark + wordmark + one-line pitch (“One YAML. Six platforms.”)
2. Feature strip: 6 platform chips in mono
3. Code sample: YAML → bindings preview
4. Footer: Listepo mark + docs link

## Do / Don't

**Do**
- Use copper for forge heat and CTAs; ink for structure
- Keep marks geometric; readable at 16px favicon
- Prefer mono for CLI/docs affinity

**Don't**
- Do not use teal/mint (ketch) or cyan (rtok)
- No purple AI gradients, no neon glow, no skeuomorphic anvil photos
- Don’t stretch the wordmark; keep letter-spacing restrained
