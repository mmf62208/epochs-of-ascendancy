# Asset Pass 3 — Unique chips · Doctrine icons · Menu brand · Live transitions

Skills: `game-asset-core` · `game-ui-icons` · `game-tilesets`

## Unique unit chips (overwrite variants)

`assets/graphics/units/retrowave/` now has **dedicated** art for:

| Stem | Notes |
|------|--------|
| bomber | Unique strategic bomber silhouette |
| submarine | Unique sub + periscope |
| carrier | Unique flight-deck carrier |
| helicopter | Unique attack helo |
| logistics | Unique truck counter |
| rocket | Unique MLRS / rocket |

Prior infantry / tanks / fighter / destroyer / artillery retained.

**Wired:** existing `MapRenderer._prefer_retrowave_unit_icon` picks these automatically.

## Dedicated tech domain icons

Replaced HUD aliases with unique icons in `assets/graphics/icons/tech_domains/`:

- `doctrine_*` — book + swords  
- `support_*` — radio + wrench  
- `strategic_future_*` — star over globe  

**Wired:** `TechnologyScreen` domain filter + research rows.

## Main menu wordmark

`assets/graphics/branding/epochs_wordmark.png`  

**Wired:** `MainMenu._ensure_wordmark()` — brand above “Command Center” caption; save manager still framed.

## Live terrain transitions

When a **plains** province borders **hills/mountains** (or reverse), province fill gets a soft midpoint tint from the plains↔hills transition pack (`_terrain_transition_edge_mix`).

Cheap (adjacency sample ≤8 neighbors); no per-pixel textured poly cost.

## Files touched

| File | Change |
|------|--------|
| `scripts/ui/MainMenu.gd` | Wordmark |
| `scripts/map/MapRenderer.gd` | Transition edge mix |
| `scripts/map/TerrainTileLibrary.gd` | Edge tint helper |
| Unit / tech domain PNGs | New art |

## Limits / Pass 4 ideas

- Cruiser still can share destroyer family visual weight (unique cruiser optional).  
- Full mesh texturing with transition autotile painter still not on (tint-only).  
- Main menu wordmark is TextureRect; no hover state.  
- Pass 4: unique cruiser/frigate, forest/desert tiles, main-menu panel skin, unit counter nation color frames.
