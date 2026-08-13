# Asset Pass 9 — Player OOB · Fort markers · Convoy · Weather icons

Skills: `game-asset-core` · `game-ui-icons`

## Units — `assets/graphics/units/retrowave/`

| Stem | Path |
|------|------|
| convoy | `convoy_32.png` · `convoy_64.png` (+ `icons/hud/convoy_32.png`) |

`UnitIconLibrary.resolve_stem` keywords: convoy, sealane, merchant, armed_merchant.  
Map unit path prefers retrowave convoy chip.

## Weather — `assets/graphics/icons/weather/`

| Stem | Role |
|------|------|
| dry | Clear / fair ground |
| mud | Wet / muddy ground |
| snow | Snow-covered / frozen |
| storm | Storm / high precip (+ `icons/hud/storm_32.png`) |

`WeatherIconLibrary` resolves `ground_state` + precip intensity → icon.  
BBCode `[img]` prefix on inspector weather chip.  
Map mode toolbar shows Wx legend strip on **supply / naval / infra**.

## Province OOB strip (player-only)

`ProvinceOOBStrip.player_only = true` (default):

- Filters to `country_tag == LeaderManager.get_player_country_tag()`
- Title: `OOB · yours (TAG) · province N · K units`
- Hidden when player has ≤1 formation in province (foreign stacks not listed)

## Fort / port special_feature map markers

When province `special_features` includes fort/port keys, MapRenderer places **Sprite2D** retrowave chips (~16px) instead of emoji Labels.

Keys: fort, bunker, coastal_fort, fortress · port, major_port, harbor, dock.

## Code

| File | Change |
|------|--------|
| `WeatherIconLibrary.gd` | New weather icon resolver |
| `UnitIconLibrary.gd` | Convoy stem |
| `ProvinceOOBStrip.gd` | Player-only filter |
| `MapRenderer.gd` | OOB player filter, fort/port sprites, convoy path |
| `MapModeToolbar.gd` | Weather icon legend strip |
| `ProvinceInsight.gd` | Weather chip `[img]` prefix |
| `WeatherManager.gd` | `get_province_weather()` |

## Limits / Pass 10 ideas

- Weather icons are solid dark-bg chips (not chroma-keyed transparent).  
- OOB still needs 2+ **player** formations to show (single unit stays inspector-only).  
- Feature sprites do not yet re-scale with camera zoom (fixed ~16px world).  
- Pass 10 candidates: full weather mapmode tint, port/airfield sprite pack, supply route convoy markers, OOB toggle for intel “all nations”. **Done — see PASS10_ASSETS_MANIFEST.md.**
