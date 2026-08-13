# Asset Pass 12 — Fort tiers · OOB bars · Convoy attack FX · Per-province weather

Skills: `game-asset-core` · `game-ui-icons`

## Units — fort level variants

| Stem | Role |
|------|------|
| `fort_bunker` | Light bunker / field fort (lv ≤ 1) |
| `fort` | Standard fort (lv 2) |
| `fort_heavy` | Fortress / citadel (lv ≥ 3) |

Paths: `units/retrowave/{stem}_32/64.png` + `icons/hud/{stem}_32.png`.

`MapRenderer._special_feature_sprite_path` uses `special_features` level.  
`UnitIconLibrary`: fortress/citadel → heavy; field_bunker → bunker.

## OOB org / strength mini-bars

Each formation chip under the name:

| Bar | Color | Source |
|-----|-------|--------|
| Org | Cyan | `organization` 0–1 |
| Strength | Magenta | `strength` 0–1 |

Tooltip shows `Org · Str` percentages. Uses slim `ProgressBar` styleboxes.

## Convoy attack / interdiction flash

`SupplyMapLayer` when `interdiction_chance ≥ threshold` (~0.18):

- Lead convoy tinted warm/red  
- Pulsing strike rings + radial burst spokes  
- Hot core flash on peak pulse  

Applies to trade corridors and high-risk military supply routes.

## Per-province weather particles

`WeatherOverlayLayer._seed_particles_per_province()`:

- Samples `province_centroids` × live `get_province_weather`  
- Storm/snow/mud get denser local clusters; dry mostly skipped  
- Cap `PARTICLE_MAX` (120); step-sample on large boards  
- Respawn near home centroid; reseed every ~3.5s  

Falls back to global field if centroids unavailable.

## Code

| File | Change |
|------|--------|
| `UnitIconLibrary.gd` | fort_bunker / fort_heavy stems |
| `MapRenderer.gd` | Fort level sprites; weather layer map_renderer bind |
| `ProvinceOOBStrip.gd` | Org/strength mini-bars |
| `SupplyMapLayer.gd` | Interdiction flash FX |
| `WeatherOverlayLayer.gd` | Per-province particle seed |
| New PNGs | fort_bunker, fort_heavy |

## Limits / Pass 13 ideas

- Interdiction flash is visual only (not a combat event popup).  
- OOB bars assume 0–1 stats; values >1 clamp.  
- Per-province particles still approximate (step sample, not viewport cull).  
- Pass 13 candidates: port level variants, fort damage states, OOB readiness bar, weather mapmode legend click-to-filter. **Done — see PASS13_ASSETS_MANIFEST.md.**
