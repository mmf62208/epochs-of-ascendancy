# Asset Pass 7 — AA/AT · Jungle · DesignPicker icons · Zoom counters

Skills: `game-asset-core` · `game-ui-icons` · `game-tilesets`

## Units — `assets/graphics/units/retrowave/`

| Stem | Notes |
|------|--------|
| aa / anti_air | Flak / AA gun counter |
| at / anti_tank | AT gun / TD counter |

`UnitIconLibrary.resolve_stem` recognizes AA/AT keywords. Map path prefers these stems.

## Terrain — `assets/graphics/tiles/jungle_seamless.png`

Dense emerald canopy (distinct from forest tint). 2×2 preview present.  
Jungle is no longer aliased to forest in `TerrainTileLibrary`.

## DesignPicker icons

`DesignPickerPopup` rows set `ItemList` icons via `UnitIconLibrary.icon_for_design_id` (template archetype + design id keywords).

## Zoom-scaled map counters

`_unit_counter_scale_for_zoom()`: far-out ≈ **0.38**, close-up ≈ **0.95**.  
`_sync_unit_counter_scales` runs from `_refresh_terrain_zoom_light` (wheel zoom) so sizes update without full icon rebuild.

## Files

| File | Change |
|------|--------|
| `UnitIconLibrary.gd` | AA/AT + `icon_for_design_id` |
| `DesignPickerPopup.gd` | List icons |
| `MapRenderer.gd` | AA/AT paths, zoom scale sync |
| `TerrainTileLibrary.gd` | Jungle key + tint |
| New PNGs | aa, at, jungle |

## Limits / Pass 8 ideas

- Zoom scale is world-scale (not pure screen-constant); very extreme zooms may still look small/large.  
- Design icons only as good as design_id/archetype keywords.  
- Pass 8: coastal/port tile, fort chip, multi-select OOB strip, animated stack pulse.
