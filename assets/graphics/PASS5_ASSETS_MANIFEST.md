# Asset Pass 5 — Battleship · Tundra/Snow · Minimap frame · Stack badges

Skills: `game-asset-core` · `game-ui-icons` · `game-tilesets`

## Units — `assets/graphics/units/retrowave/`

| Stem | Notes |
|------|--------|
| battleship | Capital ship, triple-turret silhouette |

Path resolution prefers battleship for capital hulls / Bismarck / KGV design ids.

## Terrain — `assets/graphics/tiles/`

| Asset | Role |
|-------|------|
| `tundra_seamless.png` (+ 2×2 preview) | Pale blue-gray arctic mottling |
| `snow_seamless.png` | Alias of tundra pack (snow/ice keys) |

Tinted via `TerrainTileLibrary`; edge mix includes cold fronts.

## Minimap chrome — `assets/graphics/ui/minimap_frame_512.png`

Cyan ring / magenta ticks retrowave frame.

**Wired:** `MapMinimap._apply_minimap_frame` — StyleBoxTexture + overlay TextureRect (mouse-ignore so pan still works).

## Formation stack badges — `assets/graphics/icons/hud/`

| Asset | Role |
|-------|------|
| `stack_badge_circle_24/32.png` | Circular count bubble |
| `stack_badge_diamond_24/32.png` | Diamond alternate |

**Wired:** `MapRenderer._make_formation_stack_badge` when ≥2 formations share a province.  
Index now accumulates counts (`_counts` dict).

## Files

| File | Change |
|------|--------|
| `MapRenderer.gd` | Battleship paths, stack counts, stack badges |
| `MapMinimap.gd` | Frame chrome |
| `TerrainTileLibrary.gd` | Tundra/snow keys + tints |
| New PNGs | battleship, tundra, snow, minimap frame, badges |

## Limits / Pass 6 ideas

- Stack badge digit is Label (crisp); bubble art is blank center by design.  
- Minimap frame is square 9-slice on a rectangular panel — slight stretch at corners.  
- Snow/tundra still tint-only.  
- Pass 6: amphib unique, marsh tile, OOB list unit icons, stacking multi-icon fan-out.
