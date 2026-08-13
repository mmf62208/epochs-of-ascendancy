# Asset Pass 4 — Cruiser/Frigate · Forest/Desert · Menu chrome · Nation frames

Skills: `game-asset-core` · `game-ui-icons` · `game-tilesets`

## Units — `assets/graphics/units/retrowave/`

| Stem | Notes |
|------|--------|
| cruiser | Unique dual-turret cruiser counter |
| frigate | Unique smaller escort hull |

Path resolution prefers these for cruiser/frigate/battleship tags.

## Terrain tiles — `assets/graphics/tiles/`

| Asset | Role |
|-------|------|
| `forest_seamless.png` (+ 2×2 preview) | Deep canopy mottling |
| `desert_seamless.png` (+ 2×2 preview) | Sand/ochre mottling |

Indexed in `TerrainTileLibrary`. Soft tints already apply via `terrain_tint_for_key`.  
Edge mix now also triggers on forest/desert fronts vs plains.

## Menu chrome — `assets/graphics/ui/menu_panel_frame_512.png`

Dedicated command-center panel frame (cyan border + magenta corners, thicker glow).

**Wired:** `RetrowaveTheme.style_menu_panel` → Main Menu save manager panel + darker menu background.

## Nation-color frames on unit counters

Retrowave chips no longer full-modulate to nation color (was washing out cyan art).  
Instead: **Line2D square frame** in owner color + soft glow (`_make_unit_nation_frame`).  
Legacy NATO icons still get modulate when appropriate, plus the same frame for consistency.

## Files

| File | Change |
|------|--------|
| `MapRenderer.gd` | Cruiser/frigate paths, nation frames |
| `TerrainTileLibrary.gd` | Forest/desert keys |
| `RetrowaveTheme.gd` | `style_menu_panel` |
| `MainMenu.gd` | Menu chrome + background |
| New PNGs | cruiser, frigate, forest, desert, menu panel |

## Limits / Pass 5 ideas

- Frigate only on retrowave path (no classic NATO frigate file).  
- Forest/desert still tint-only (no full textured fills).  
- Nation frame is axis-aligned square; not rotated with camera.  
- Pass 5: battleship unique, snow/tundra tiles, minimap frame, formation stack badges.
