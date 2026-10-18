# HWY-3 hub-route highways (draft HOLD)

Stacked on HWY-2 `#100` `d4a3a1ff`. Display highways are trunk shortest paths between hubs (capitals, largest cities, significant ports). FIX #1 paints **one connected tree per large country** (Kruskal skip-if-connected + same-tag bridges). Urban-district neighbour count is an optional weight. Not live Play.

| File | Zoom | Notes |
|------|------|--------|
| `ruhr_essen_z24.png` | 2.4 | FIX #5 Essen `(7356, 1606)`. Casing **463** px; 5 labels (Düsseldorf, Duisburg, Essen, Mülheim, Dortmund). `HWY3_FIXED_ORIENTATION=1` flipped=false. |
| `ruhr_essen_z4.png` | 4.0 | Same camera. Casing **541** px; 5 labels. Highways z=24 above Rhine 22. |
| `ruhr_koln_mid.png` | default 1.80 | Connected GER corridor: Ruhr–Köln and east–west spine. |
| `ruhr_koln_close.png` | close 3.20 | Casing vs fills; gold spine Bonn–Köln–Leverkusen. |
| `ruhr_koln_far.png` | far 0.32 | Europe/Home; highways on, dirt/paved culled. |
| `wide_germany.png` | far ~0.34 | Germany bbox; **20** hub-route highway runs ≥9 px (main/d4a3 → 0). |
| `ruhr_koln_mid_highway.png` / `ruhr_koln_close_highway.png` / `ruhr_koln_far_highway.png` | same | Pixel-guard highway-band captures. |
| `ruhr_koln_*_hwy2.png` | same | HWY-2 `#100` comparison shots. |

Pixel: one fixed orientation (`HWY3_FIXED_ORIENTATION=1`, flipped=false), hub-route sample pair by rule (nearest non-spine highway to Köln = `710401–710412`). Bars far **21** / default **12** / close **20** (mins 9 / 12 / 16; ceilings 26 / 18). Wide Germany **20** hub-route runs ≥9 px. FIX #2 HeadlessHwy3 **PASS**: 114/9/0/median **10.00**, ITA Rome–Milan trunk, Ruhr 4/5, Munich–Frankfurt, `dropped_cap=80` `dropped_parallel=6`. FIX #4 live ScenarioLoader **PASS**: Rome-north `Milan → … → Rome`; Ruhr **3/3**; Paris one north Lille. FIX #5: THE count = drawn `display_tier==2` edges — live **114** / headless **113**/8/0/median **12.00** (both ≤114). Essen z2.4/**463** / z4/**541**; 5 Ruhr labels; labels-off + under-river killed. Source mutant `second_zero` kills Rome-north; env branches gone. Hwy1 band 60–114. `--quick` 14 known reds; map_qc NE **0.9853**.
