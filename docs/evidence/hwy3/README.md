# HWY-3 hub-route highways (draft HOLD)

Stacked on HWY-2 `#100` `d4a3a1ff`. Display highways are trunk shortest paths between hubs (capitals, largest cities, significant ports). Urban-district neighbour count is an optional weight. Not live Play.

| File | Zoom | Notes |
|------|------|--------|
| `ruhr_koln_mid.png` | default 1.80 | Hub-route corridors vs HWY-2 zigzags. |
| `ruhr_koln_close.png` | close 3.20 | Casing vs fills; gold spine Bonn–Köln–Leverkusen. |
| `ruhr_koln_far.png` | far 0.32 | Europe/Home; highways on, dirt/paved culled. |
| `wide_germany.png` | far ~0.38 | Germany bbox; ≥3 highway runs ≥9 px. |
| `ruhr_koln_mid_highway.png` / `ruhr_koln_close_highway.png` | same | Pixel-guard highway-band captures. |

Pixel: one fixed orientation (`HWY3_FIXED_ORIENTATION=1`), hub-route sample pair by rule (nearest non-spine highway to Köln). Bars far ≥9 / default ≥12 / close ≥16.
