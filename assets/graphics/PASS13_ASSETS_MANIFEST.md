# Asset Pass 13 — Port tiers · Fort damage · OOB readiness · Weather filter

Skills: `game-asset-core` · `game-ui-icons`

## Units — port level variants

| Stem | Role |
|------|------|
| `port_jetty` | Minor dock / jetty (lv ≤ 1) |
| `port` | Standard harbor (lv 2) |
| `port_major` | Deepwater major port (lv ≥ 3 / major_port) |

Paths: `units/retrowave/{stem}_32/64.png` + `icons/hud/{stem}_32.png`.

## Units — fort damage state

| Stem | Role |
|------|------|
| `fort_damaged` | Cracked / burning fort glyph |

Used when `ProvinceInsight.classify_province_map_damage` reports site/infra sabotage on fort features. Slight warm modulate on map sprite.

## OOB readiness bar

Third mini-bar under formation chips:

| Bar | Color | Source |
|-----|-------|--------|
| Org | Cyan | `organization` |
| Strength | Magenta | `strength` |
| **Readiness** | Lime | `readiness` |

Tooltip: `Org · Str · Rdy` percentages.

## Weather legend click-to-filter

Map mode toolbar **Wx** chips (dry/mud/snow/storm) are toggle buttons:

- Active only meaningful in **Weather** mapmode (F8)  
- Matching provinces boosted; others dimmed  
- Click same chip again (or leave weather mode) clears filter  

`MapRenderer.weather_ground_filter` + `set_weather_ground_filter`.

## Code

| File | Change |
|------|--------|
| `UnitIconLibrary.gd` | port_jetty/major, fort_damaged |
| `MapRenderer.gd` | Port tiers, fort damage path, weather filter |
| `ProvinceOOBStrip.gd` | Readiness mini-bar |
| `MapModeToolbar.gd` | Clickable Wx filter chips |
| New PNGs | port_jetty, port_major, fort_damaged |

## Limits / Pass 14 ideas

- Fort damage is one shared glyph (not bunker/heavy damaged variants).  
- Port damage art not yet separate.  
- Weather filter is fill-tint only (particles not re-filtered).  
- Pass 14 candidates: damaged port glyph, weather particle filter sync, OOB combat XP bar, mapmode presets. **Done — see PASS14_ASSETS_MANIFEST.md.**
