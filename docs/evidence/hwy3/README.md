# HWY-3 hub-route highways (draft HOLD)

Stacked on HWY-2 `#100` `d4a3a1ff`. Display highways are trunk shortest paths between hubs (capitals, largest cities, significant ports). FIX #1 paints **one connected tree per large country** (Kruskal skip-if-connected + same-tag bridges). Urban-district neighbour count is an optional weight. Not live Play.

| File | Zoom | Notes |
|------|------|--------|
| `ruhr_koln_mid.png` | default 1.80 | Connected GER corridor: Ruhr–Köln and east–west spine. |
| `ruhr_koln_close.png` | close 3.20 | Casing vs fills; gold spine Bonn–Köln–Leverkusen. |
| `ruhr_koln_far.png` | far 0.32 | Europe/Home; highways on, dirt/paved culled. |
| `wide_germany.png` | far ~0.34 | Germany bbox; **13** hub-route highway runs ≥9 px (main/d4a3 → 0). |
| `ruhr_koln_mid_highway.png` / `ruhr_koln_close_highway.png` / `ruhr_koln_far_highway.png` | same | Pixel-guard highway-band captures. |
| `ruhr_koln_*_hwy2.png` | same | HWY-2 `#100` comparison shots. |

Pixel: one fixed orientation (`HWY3_FIXED_ORIENTATION=1`, flipped=false), hub-route sample pair by rule (nearest non-spine highway to Köln = `710401–710412`). Bars far **14** / default **12** / close **29** (mins 9 / 12 / 16; ceilings 26 / 18). Wide Germany **13** hub-route runs ≥9 px (FIX #1 tip). FIX #2: capital↔2nd-hub trunks, near-parallel drop, Ruhr urban span, hook-back trap in H3. Hwy1 band 60–114.
