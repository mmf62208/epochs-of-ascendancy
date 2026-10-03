# FLEET-2 FIX #6 live-scale clicks (xvfb 1280×740, GER, Europe Home, world_accurate)

Live-scale tip `d15ac739` (docs follow-up on the same pick rule). Home zoom **0.318**. RSS peak **2031.4 MB**. RESULT=**PASS**. xvfb ≠ live Play.

## Topmost-painted rule

The **topmost painted counter** under the cursor wins (NationPlate, StatBars, or designation/label; own or foreign). Ownership (a foreign chip stationed elsewhere cannot win on player-owned land) applies **only in the halo** — when no painted body contains the click. That halo is what keeps Cuxhaven / Heidekreis from opening Emden NLD when the click misses every plate/bars/label.

How topmost is determined (every `DemoUnitIcon_*` shares `z_index=28`, `z_as_relative=false` at Home):

1. Higher CanvasItem `z_index` (absolute, then parent-relative walk)
2. Same z: **NationPlate interior > StatBars > plate rim > designation/label**
3. Same class → nearest painted centre
4. True distance tie → scene-tree / `Node.is_greater_than`

Interior vs rim: the outer ~28% of the 44×40 NationPlate (`|local.x| > 15.84` or `|local.y| > 14.4`) is rim. DNK AW3 bars at +44 sit on the Emden plate rim, so the bars win. Emden centre and east +20 stay NLD plate interior. Neighbour chip centres stay their own interiors. Tree order is not treated as a visual stack at Home inverse-zoom.

Painted rect (hit) = NationPlate 44×40 local (−22,−20)–(22,20) ∪ StatBars 44×14 at (−22,20) (to y=34) ∪ Designation / TypeLetter / StrNum. StatBars hit unions that canonical strip with the live chrome. Own StatBars still beat a foreign plate that draws on top of them (Berlin AW3 +46).

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

All 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet (GER = own full card `fight=true assign=true`; others read-only). **32/32**.

| zoom | East Kent `711453` | old ENG chip | GER-nearest gap |
|---|---|---|---|
| 0.318 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 0.400 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 0.800 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 1.500 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |

## Land / air + coasts + AW3 painted (0.318 / 0.40)

Each neighbour opened **its own unit** (foreign read-only). Never a fleet. Never a neighbour GER steal. **24/24**.

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
| Emden NLD east +20 | `NLD_formation_1` | `NLD_formation_1` |
| DNK AW3 bars +44 | `DNK_formation_3` (exact +44) | `DNK_formation_3` (exact +44) |
| coast `710374` Cuxhaven | covered_by_paint topmost=`NLD_formation_1` (entire hex under Emden plate) | covered_by_paint topmost=`DNK_formation_3` |
| coast `710380` Heidekreis | covered_by_paint topmost=`DNK_formation_2` | covered_by_paint topmost=`NLD_formation_1` |
| GER AW3 bars +46 px | `GER_formation_3` own | `GER_formation_3` own |
| GER AW3 corner | `GER_formation_3` own | `GER_formation_3` own |

Cuxhaven / Heidekreis centroids sit inside a painted body at Home inverse-zoom (Cuxhaven’s whole hex is inside the Emden NationPlate). There is no in-pid halo pixel; the probe logs `covered_by_paint` instead of demanding GER spill on a painted chip. An empty German-land click that opens Garrison 4 (Karlsruhe) instead of the province is pre-existing land spill and out of scope.

## Emden NLD Div 1 painted-rect grid

Every cell inside the NLD_1 painted rect must open `NLD_formation_1` unless a different counter’s painted body is on top there.

**z0.318 — 28 cells: 6 × `NLD_formation_1`, 22 other (named topmost), 0 outside.**

| dx,dy | pick / topmost | why not NLD_1 |
|---|---|---|
| −30,−24 / −20,−24 / −10,−24 | `fielded_sov_*` | SOV North Sea plate on top |
| −30,0 / −20,0 | `NLD_formation_0` | NLD Div 0 plate on top |
| −10,0 | `NLD_formation_3` | NLD AW3 plate on top |
| 0,−24 | `NLD_formation_2` | NLD Div 2 plate on top |
| 0,0 / 10,0 / 10,24 / 20,0 / 20,24 / 30,24 | `NLD_formation_1` | NLD_1 interior / face |
| 10,−24 / 20,−24 / 30,−24 / 30,0 | `DNK_formation_3` | DNK AW3 StatBars on the NLD rim |
| −30,24 | pick `BEL_formation_1` / topmost `ITA_formation_2` | BEL / ITA face on top |
| −20,24 | `BEL_formation_2` | BEL plate on top |
| −10,24 / 0,24 | `BEL_formation_3` | BEL AW3 on top |
| −30,46 / −20,46 | `BEL_formation_3` | BEL AW3 on top |
| −10,46 / 0,46 / 10,46 | `LUX_formation_0` | LUX plate on top |
| 20,46 / 30,46 | `GER_formation_4` | GER Garrison 4 plate on top |

**z0.400 — 15 cells: 4 × `NLD_formation_1`, 11 other (named topmost), 0 outside.**

| dx,dy | pick / topmost | why not NLD_1 |
|---|---|---|
| −30,−20 / −15,−20 | `NLD_formation_3` | NLD AW3 on top |
| −30,5 / −15,5 | `NLD_formation_0` | NLD Div 0 on top |
| 0,−20 / 15,−20 | `NLD_formation_2` | NLD Div 2 on top |
| 0,5 / 15,5 / 15,35 / 30,35 | `NLD_formation_1` | NLD_1 interior / face |
| −30,35 | `BEL_formation_2` | BEL plate on top |
| −15,35 / 0,35 | `BEL_formation_3` | BEL AW3 on top |
| 30,−20 / 30,5 | `DNK_formation_3` | DNK AW3 StatBars on the NLD rim |

## Own GER drawn bodies (Berlin / Baden)

| click | z0.318 | z0.400 |
|---|---|---|
| GER Div 6 | `GER_formation_6` own | `GER_formation_6` own |
| GER Div 7 | `GER_formation_7` own | `GER_formation_7` own |
| GER Garrison 4 | `GER_formation_4` own | `GER_formation_4` own |
| GER AW3 body | `GER_formation_3` own | `GER_formation_3` own |

## Screenshots

- `docs/evidence/fleet2_fix6/fleet2_channel_home.png`
- `docs/evidence/fleet2_fix6/fleet2_channel_z15.png`
- `docs/evidence/fleet2_fix6/fleet2_north_sea_home.png`
- `docs/evidence/fleet2_fix6/fleet2_north_sea_z15.png`
