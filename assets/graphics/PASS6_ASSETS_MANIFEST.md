# Asset Pass 6 — Amphib · Marsh · OOB icons · Fan-out stacks

Skills: `game-asset-core` · `game-ui-icons` · `game-tilesets`

## Units — `assets/graphics/units/retrowave/`

| Stem | Notes |
|------|--------|
| amphib / amphib_vehicle | Landing craft / amphib counter |
| apc | Armored personnel carrier |
| recon | Scout / recon car |

Map path resolution prefers these for amphib / APC / recon archetypes.

## Terrain — `assets/graphics/tiles/marsh_seamless.png`

Wetland mottling (+ 2×2 preview). Tints + edge mix vs plains/forest.

## Shared library — `scripts/ui/UnitIconLibrary.gd`

Keyword → retrowave stem resolution for:

- Formation picker ItemList icons  
- Leaders screen unassigned-formation rows  
- Map fan-out sample paths  

## OOB / list wiring

| UI | Change |
|----|--------|
| `FormationPickerPopup` | ItemList icons per formation |
| `LeaderAssignmentScreen` | TextureRect icon on formation rows |

## Map stack fan-out

When **2–4** formations share a province:

- Fan of up to 4 chips at offset positions  
- Uses formation samples for variety when available  
- Stack count badge still shown  

When **5+**: primary chip + badge (avoids clutter).

## Files

| File | Change |
|------|--------|
| `UnitIconLibrary.gd` | New |
| `FormationPickerPopup.gd` | List icons |
| `LeaderAssignmentScreen.gd` | Row icons |
| `MapRenderer.gd` | Amphib paths, samples, fan-out |
| `TerrainTileLibrary.gd` | Marsh keys |
| New PNGs | amphib, apc, recon, marsh |

## Limits / Pass 7 ideas

- Fan-out samples max 4; types beyond that only in badge count.  
- DesignPicker design list still text-first (optional icons next).  
- Pass 7: AA/AT guns unique, jungle tile, DesignPicker icons, zoom-scaled counter sizes.
