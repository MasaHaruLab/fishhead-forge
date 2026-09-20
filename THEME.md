# Theme — 鱼头健身 (Forge fork)

This repository is a **鱼头** fork of [bndct-devops/forge](https://github.com/bndct-devops/forge).
It is the gym-logging shell for checklist sessions that will later feed **健身教练**.
Workout logic, Docker, and auth are unchanged in the theming pass; only tokens,
default appearance, and visible product name differ.

Display name in the app chrome: **鱼头健身** (PWA / titles) or **Forge · 鱼头**.

## Palette (authoritative)

From 乐理大师 docs theme `navy` (RubatoCore / plan-page default):

| Token | Hex | Role |
|-------|-----|------|
| `--palette-bg` / paper | `#F7F4EF` | Page background (warm rice-paper) |
| `--palette-navy` | `#1B3A5C` | Primary ink: titles, nav mark, primary button fill |
| `--palette-blue` | `#2E6DA4` | Links, selected chrome, primary-button hover (light) |
| `--palette-slate` | `#455A64` | Muted text, borders (tinted) |
| `--palette-gold` | `#C9A84C` | Accent: completed sets, PR badges, chart emphasis |
| `--palette-on-navy` | `#F7F4EF` | Text on navy fills |

## Semantic map (app)

Defined once in `frontend/src/index.css` (`:root` / `.dark` / `.theme-black`)
and exposed to Tailwind via `@theme inline`. One place drives the UI.

| UI | Token | Light (default) | Notes |
|----|-------|-----------------|-------|
| Page background | `--background` | `#F7F4EF` | |
| Body / title ink | `--foreground` | `#1B3A5C` | |
| Primary buttons | `--primary` / `--primary-foreground` | navy / paper | Hover → `--primary-hover` (`#2E6DA4`) |
| Links / selected | `--link` (`text-link`) | `#2E6DA4` | Also `--info` |
| Muted text | `--muted-foreground` | `#455A64` | |
| Borders | `--border` | slate @ ~22% | |
| PR / records | `--record` | `#C9A84C` | |
| Completed sets | `--set-done` | gold mixed into card | Flash overlay uses `--record` |
| Charts (emphasis) | `--chart-accent` / `--series-1` | `#C9A84C` | |
| Charts (series 2) | `--series-2` | `#2E6DA4` | |

The marketing site (`website/src/styles/global.css`) uses the same hexes:
`--bg` paper, `--accent` navy (CTAs), `--link` blue, `--gold` turmeric.

## Modes

- **Light navy-gold is the default** (first visit, unset `forge_theme`).
- Dark and true-black OLED remain in Settings → Theme. On those surfaces,
  primary buttons flip to gold so CTAs stay visible on navy cards.

## What this is not

- Not maple / wood, not paper-sage, not Forge ember, not neon green / purple.
- Not a rewrite of Forge as a new product — it is a branded shell for 鱼头 gym logging.
