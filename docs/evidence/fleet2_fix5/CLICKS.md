# FLEET-2 FIX #5 live-scale clicks (xvfb 1280×740, GER, Europe Home, world_accurate)

Live-scale tip `a50cdeed`. Home zoom **0.318**. RSS peak **2045.6 MB**. RESULT=**PASS**. xvfb ≠ live Play.

Painted rect = NationPlate 44×40 local (−22,−20)–(22,20) ∪ StatBars 44×14 at (−22,20) (to y=34) ∪ Designation / TypeLetter / StrNum. Own StatBars hit beats a nearer foreign plate. Player-owned GIS land never opens a foreign chip stationed elsewhere.

**Correction of FIX #4:** `710374` / `710380` → `NLD_formation_1` was **not** intended. Those hexes are German-owned (Cuxhaven / Heidekreis).

## 8 labels + unit ids

| sea | tag | fid | label |
|---|---|---|---|
| North Sea `950000` | GER | `GER_formation_2` | GER Fleet 2 |
| North Sea `950000` | FRA | `FRA_formation_2` | FRA Fleet 2 |
| North Sea `950000` | JAP | `JAP_formation_2` | JAP Fleet 2 |
| North Sea `950000` | SOV | `fielded_sov_*` | SOV Fleet 1 |
| Channel `950001` | ENG | `ENG_formation_2` | ENG Fleet 2 |
| Channel `950001` | ITA | `ITA_formation_2` | ITA Fleet 2 |
| Channel `950001` | POL | `fielded_pol_*` | POL Fleet 1 |
| Channel `950001` | USA | `fielded_usa_*` | USA Fleet 1 |

## Plates + East Kent + GER gap

All 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet (GER = own full card `fight=true assign=true`; others read-only).

| zoom | East Kent `711453` | old ENG chip | GER-nearest gap |
|---|---|---|---|
| 0.318 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 0.400 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 0.800 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 1.500 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |

## Land / air + coasts + AW3 painted (0.318 / 0.40)

Each neighbour opened **its own unit** (foreign read-only). Never a fleet. Never a neighbour GER steal.

| click | z0.318 | z0.400 |
|---|---|---|
| ENG Div 0 | `ENG_formation_0` | `ENG_formation_0` |
| ENG Div 1 | `ENG_formation_1` | `ENG_formation_1` |
| BEL Div 0 | `BEL_formation_0` | `BEL_formation_0` |
| BEL Div 1 | `BEL_formation_1` | `BEL_formation_1` |
| BEL Div 2 | `BEL_formation_2` | `BEL_formation_2` |
| NLD Div 0 | `NLD_formation_0` | `NLD_formation_0` |
| NLD Div 2 | `NLD_formation_2` | `NLD_formation_2` |
| NLD AW3 | `NLD_formation_3` | `NLD_formation_3` |
| FRA Garrison 4 | `FRA_formation_4` | `FRA_formation_4` |
| Emden NLD | `NLD_formation_1` | `NLD_formation_1` |
| BEL AW3 | `BEL_formation_3` | `BEL_formation_3` |
| DNK AW3 | `DNK_formation_3` | `DNK_formation_3` |
| coast `710374` Cuxhaven | own GER spill / not NLD | own GER spill / not NLD |
| coast `710380` Heidekreis | own GER spill / not NLD | own GER spill / not NLD |
| GER AW3 bars +46 px | `GER_formation_3` own | `GER_formation_3` own |
| GER AW3 corner | `GER_formation_3` own | `GER_formation_3` own |

## Own GER drawn bodies

| click | z0.318 | z0.400 |
|---|---|---|
| GER Div 6 | `GER_formation_6` own | `GER_formation_6` own |
| GER Div 7 | `GER_formation_7` own | `GER_formation_7` own |
| GER Garrison 4 | `GER_formation_4` own | `GER_formation_4` own |
| GER AW3 body | `GER_formation_3` own | `GER_formation_3` own |
