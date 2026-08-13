# Asset Pass 10 — Weather mapmode · Airfield · Convoy routes · OOB All toggle

Skills: `game-asset-core` · `game-ui-icons`

## Units — `assets/graphics/units/retrowave/`

| Stem | Path |
|------|------|
| airfield | `airfield_32.png` · `airfield_64.png` (+ `icons/hud/airfield_32.png`) |

`UnitIconLibrary` keywords: airfield, airbase, airstrip, runway.  
Map special_features + unit path prefer retrowave airfield chip.

## Map modes — `assets/graphics/icons/map_modes/`

| Stem | Role |
|------|------|
| weather | 2×2 composite of dry/mud/snow/storm chips |

Toolbar mode **Weather** + hotkey **F8**.

## Weather mapmode tint

`MapRenderer.debug_tint_mode == "weather"`:

| Key | Fill bias |
|-----|-----------|
| dry | Warm sand |
| mud | Brown earth |
| snow | Cool white-blue |
| storm | Purple-gray (heavier on sea) |

Uses live `WeatherManager.get_province_weather()` (precip ≥ 0.55 → storm).

## Supply route convoy markers

`SupplyMapLayer` draws retrowave **convoy** chips at trade corridor midpoints (max 24, soft halo). Visible when supply overlay / supply mapmode shows routes.

## Province OOB strip — Yours / All

Pass 10 **Yours ↔ All** toggle on strip header:

- **Yours** (default): player `country_tag` only  
- **All**: every formation in province (intel read)  

Filter preference sticks while strip is open; re-applies on toggle without reselecting.

## Code

| File | Change |
|------|--------|
| `UnitIconLibrary.gd` | Airfield stem |
| `HudIconLibrary.gd` | weather map-mode key |
| `MapModeToolbar.gd` | Weather mode + wx legend on weather |
| `MapRenderer.gd` | Weather tint, F8, airfield feature/unit path, OOB All |
| `SupplyMapLayer.gd` | Trade convoy midpoint markers |
| `ProvinceOOBStrip.gd` | Yours/All filter toggle |
| New PNGs | airfield, weather mapmode icon |

## Limits / Pass 11 ideas

- Weather mapmode is soft fill lerp (not full textured weather overlay).  
- Convoy markers are mid-route only (not animated along path).  
- Airfield asset is crossed-runway + tower (not distinct from generic “airport”).  
- Pass 11 candidates: animated convoy travel, weather particle overlay, airfield hangar level variants, OOB nationality color chips. **Done — see PASS11_ASSETS_MANIFEST.md.**
