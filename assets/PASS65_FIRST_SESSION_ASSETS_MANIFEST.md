# PASS 65 — First-session play assets (2026-08-03)

## Purpose

Close first-session visual gaps for `world_accurate` play: mapmode icons that were text-only, strategic resource glyphs, and branding already wired in Command Center.

## Map modes (`assets/graphics/icons/map_modes/`)

| Stem | 32 | 64 | Notes |
|------|----|----|-------|
| `states` | ✓ | ✓ | Stacked region bars (retrowave cyan/magenta) |
| `terrain` | ✓ | ✓ | Mountain silhouette |
| `resources` | ✓ | ✓ | Diamond / oil / bar cluster (no longer fuel alias only) |
| `fronts` | ✓ | ✓ | Opposing front-line arrows |
| `war_loop` | ✓ | ✓ | Circular war-path loop + star |

Style: navy `#0f0f1e`, cyan `#33e6ff`, magenta `#ff33cc` — matches `political` / `supply` HUD contract.

## Resources (`assets/graphics/icons/resources/`)

| Stem | 24 | 64 |
|------|----|----|
| `coal` | ✓ | ✓ |
| `chromium` | ✓ | ✓ |
| `tungsten` | ✓ | ✓ |

Existing steel / aluminum / fuel / rubber unchanged.

## Wiring

- `scripts/ui/HudIconLibrary.gd` — MODE_KEYS includes states/terrain/resources/fronts/war_loop; RES_KEYS coal/chromium/tungsten
- `scripts/ui/map/MapModeToolbar.gd` — preset buttons use preset id icons (Fronts / WarLoop)
- `scripts/ui/MainMenu.gd` — wordmark + `style_menu_panel` (existing branding PNGs)

## Non-goals this pass

- App `icon.svg` still default Godot (optional follow-up)
- Loading screen hero regen
- Leader portrait gap fill
