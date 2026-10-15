# HWY-3 hub-route highways (draft HOLD)

Stacked on HWY-2 `#100` `d4a3a1ff`. Display highways are trunk shortest paths between hubs (capitals, largest cities, significant ports). Urban-district neighbour count is an optional weight. Not live Play.

| File | Zoom | Notes |
|------|------|--------|
| `ruhr_koln_mid.png` | default 1.80 | Hub-route corridors vs HWY-2 zigzags. |
| `ruhr_koln_close.png` | close 3.20 | Casing vs fills; gold spine Bonn–Köln–Leverkusen. |
| `ruhr_koln_far.png` | far 0.32 | Europe/Home; highways on, dirt/paved culled. |
| `wide_germany.png` | far ~0.34 | Germany bbox; 33 highway runs ≥9 px. |
| `ruhr_koln_mid_highway.png` / `ruhr_koln_close_highway.png` | same | Pixel-guard highway-band captures. |
| `ruhr_koln_*_hwy2.png` | same | HWY-2 `#100` comparison shots. |

Pixel: one fixed orientation (`HWY3_FIXED_ORIENTATION=1`, flipped=false), hub-route sample pair by rule (nearest non-spine highway to Köln = `710425–710460`). Bars far **22** / default **13** / close **18** (mins 9 / 12 / 16). Wide Germany **33** runs ≥9 px.
