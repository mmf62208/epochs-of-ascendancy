# Asset Pass 11 — Animated convoys · Weather particles · Airfield tiers · OOB nation chips

Skills: `game-asset-core` · `game-ui-icons`

## Units — airfield hangar levels

| Stem | Role |
|------|------|
| `airfield_strip` | Minor airstrip (lv ≤ 1) |
| `airfield` | Standard airbase (lv 2) |
| `airfield_hangar` | Hangar complex (lv ≥ 3) |

Paths under `units/retrowave/` (+ `icons/hud/*_32.png` for strip/hangar).

`MapRenderer._special_feature_sprite_path(feature, level)` picks variant from `special_features` level.  
`UnitIconLibrary` keywords: hangar / airstrip / airfield.

## Animated convoy travel

`SupplyMapLayer`:

- Convoy chips **travel** along trade corridor polylines (`_point_along_polyline`)
- Loop period ~14s, staggered per route
- Optional trail ghost (1 default)
- Max 24 routes; animates while supply overlay visible (including paused sim)

## Weather particle overlay

`WeatherOverlayLayer.set_particle_mode(true)` when mapmode = **weather** (F8):

| Dominant state | Particles |
|----------------|-----------|
| snow | Soft white flakes |
| rain/mud | Cyan diagonal streaks |
| storm | Purple streaks + flashes |
| dry | Sparse warm dust dots |

Capped (~120), wraps in rendered bounds, independent of full snow-veil toggle.

## OOB nationality color chips

Each formation chip:

- Left **nation color bar** (`MapManager.get_country_color`)
- Icon frame border tinted to nation color
- In **All** mode: tag label under name in nation hue

## Code

| File | Change |
|------|--------|
| `SupplyMapLayer.gd` | Animated convoy path travel |
| `WeatherOverlayLayer.gd` | Particle field + `set_particle_mode` |
| `MapRenderer.gd` | Weather particle sync, airfield level sprites |
| `ProvinceOOBStrip.gd` | Nation color bar + frame |
| `UnitIconLibrary.gd` | Hangar/strip stems |
| New PNGs | airfield_strip, airfield_hangar |

## Limits / Pass 12 ideas

- Particles are global field (not per-province density).  
- Convoy animation redraws full layer each frame (capped routes).  
- Airfield levels only from special_features int level, not site tier manager.  
- Pass 12 candidates: per-province weather particles, convoy attack flash FX, fort level variants, OOB strength/org mini-bars. **Done — see PASS12_ASSETS_MANIFEST.md.**
