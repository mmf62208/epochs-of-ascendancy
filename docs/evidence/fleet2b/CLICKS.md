# FLEET-2b live-scale clicks (xvfb 1280×740, GER, Europe Home, world_accurate)

Live-scale tip `c62d85b6` (painted-pixel + 60% inner face). Home zoom **0.318**. RSS peak **2037.5 MB**. RESULT=**PASS**. xvfb ≠ live Play.

## Painted-pixel rule (FLEET-2b)

The **topmost painted counter** under the cursor wins. Only actually painted pixels count:

- NationPlate 44×40 local (−22,−20)–(22,20)
- StatBars 44×14 at (−22,20) (to y=34), plus live bar chrome
- Drawn glyph ink (Designation / TypeLetter / StrNum / LeaderMark via `ThemeDB.fallback_font` string size + outline capped at 1.5), **and only if that ink sits on/near the plate** (plate grown 2.0 local)

A fat designation AABB with no ink cannot win. That is the Heidekreis 710380 z0.40 bug: ~40 px east of Emden NLD on bare German land used to open `NLD_formation_1` through the label box. `_world_in_unit_plate_or_bars` is wired into `_world_in_unit_painted_rect`; glyph hits are clipped to the plate face.

Ownership (a foreign chip stationed elsewhere cannot win on player-owned land) applies **only in the halo** — when no painted pixel contains the click. Scott’s FLEET-2 rule is unchanged: coasts 710374/710380 open the topmost painted chip at far zoom and own GER at 0.8+.

How topmost is determined (every `DemoUnitIcon_*` shares `z_index=28` at Home):

1. Higher CanvasItem `z_index` (absolute, then parent-relative walk)
2. Same z: **NationPlate inner face > StatBars > plate rim / outer face > designation/label**
3. Same class → nearest painted *piece* centre (bars use the strip centre at local (0,27))
4. True distance tie → scene-tree / `Node.is_greater_than`

Inner face is **~60%** of the 44×40 plate (`|local.x| ≤ 13.4`, `|local.y| ≤ 12.2`), not the old 72%. StatBars over the outer face / rim therefore win across more of the visible strip (Play: only ±4 around the DNK AW3 bar centre at 72%). Emden NLD centre and east +20 stay inside that inner face. Same-nation piles are unedited (Play +8 → DNK Div 2 by nearer bar centre).

Removed unused FLEET-2 helpers: `_foreign_land_air_blocked_on_player_hex`, `_province_owner_tag`. `_cycle_province_owner_tag` kept. `_stat_bars_beat_other_plate_interior` was added then removed (it stole NLD centre / neighbour chips at Home scale).

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
| DNK AW3 bars +44 | `DNK_formation_3` | `DNK_formation_3` |
| DNK AW3 bars ±4 | `DNK_formation_3` / `DNK_formation_3` | `DNK_formation_3` / `DNK_formation_3` |
| DNK AW3 bars ±8 | −8 `NLD_formation_1` (NLD inner face) / +8 `DNK_formation_2` (same-nation pile) | `DNK_formation_3` / `DNK_formation_3` |
| DNK AW3 bar ends | west `NLD_formation_1` (inner) / east `DNK_formation_2` (pile) | `NLD_formation_2` / `DNK_formation_2` |
| DNK AW3 2 px sweep | **21/21** (DNK_3, or NLD inner / same-nation DNK) | **21/21** |
| coast `710374` Cuxhaven | covered_by_paint topmost=`DNK_formation_3` | covered_by_paint topmost=`DNK_formation_3` |
| coast `710380` Heidekreis | covered_by_paint topmost=`DNK_formation_2` | **halo** own GER/province (`painted=false`, never NLD through empty label) |
| NLD label-east local 28 / 32 / +40 px | not NLD paint; topmost CZE_3 / DNK_2 / DNK_2 | local 28/32 halo own GER/province; +40 px covered_by_paint `DNK_formation_3` |
| GER AW3 bars +46 px | `GER_formation_3` own | `GER_formation_3` own |
| GER AW3 corner | `GER_formation_3` own | `GER_formation_3` own |

Cuxhaven’s hex still sits under a painted body at Home inverse-zoom. Heidekreis at z0.40 is **not** painted (empty label box rejected) and opens own GER/province — never `NLD_formation_1`.

## Emden NLD Div 1 painted-rect grid

**z0.318 — 28 cells: 8 × `NLD_formation_1`, 20 other (named topmost), 0 outside.**

| dx,dy | pick / topmost | why not NLD_1 |
|---|---|---|
| −30,−24 / −20,−24 / −10,−24 | `fielded_sov_*` | SOV North Sea plate on top |
| −30,0 / −20,0 | `NLD_formation_0` | NLD Div 0 plate on top |
| −10,0 | `NLD_formation_3` | NLD AW3 plate on top |
| 0,−24 | `NLD_formation_2` | NLD Div 2 plate on top |
| 0,0 / 10,0 / 10,24 / 20,0 / 20,24 / 20,46 / 30,24 / 30,46 | `NLD_formation_1` | NLD_1 inner / face |
| 10,−24 / 20,−24 / 30,−24 / 30,0 | `DNK_formation_3` | DNK AW3 StatBars on the NLD outer face / rim |
| −30,24 | pick `BEL_formation_1` / topmost `ITA_formation_2` | BEL / ITA face on top |
| −20,24 | `BEL_formation_2` | BEL plate on top |
| −10,24 / 0,24 | `BEL_formation_3` | BEL AW3 on top |
| −30,46 / −20,46 | `BEL_formation_3` | BEL AW3 on top |
| −10,46 / 0,46 / 10,46 | `LUX_formation_0` | LUX plate on top |

**z0.400 — 15 cells: 4 × `NLD_formation_1`, 11 other (named topmost), 0 outside.**

| dx,dy | pick / topmost | why not NLD_1 |
|---|---|---|
| −30,−20 / −15,−20 | `NLD_formation_3` | NLD AW3 on top |
| −30,5 / −15,5 | `NLD_formation_0` | NLD Div 0 on top |
| 0,−20 / 15,−20 | `NLD_formation_2` | NLD Div 2 on top |
| 0,5 / 15,5 / 15,35 / 30,35 | `NLD_formation_1` | NLD_1 inner / face |
| −30,35 | `BEL_formation_2` | BEL plate on top |
| −15,35 | `BEL_formation_3` | BEL AW3 on top |
| 0,35 | `NLD_formation_2` | NLD Div 2 on top |
| 30,−20 / 30,5 | `DNK_formation_3` | DNK AW3 StatBars on the NLD rim |

## Own GER drawn bodies (Berlin / Baden)

| click | z0.318 | z0.400 |
|---|---|---|
| GER Div 6 | `GER_formation_6` own | `GER_formation_6` own |
| GER Div 7 | `GER_formation_7` own | `GER_formation_7` own |
| GER Garrison 4 | `GER_formation_4` own | `GER_formation_4` own |
| GER AW3 body | `GER_formation_3` own | `GER_formation_3` own |

## Screenshots

- `docs/evidence/fleet2b/fleet2_channel_home.png`
- `docs/evidence/fleet2b/fleet2_channel_z15.png`
- `docs/evidence/fleet2b/fleet2_north_sea_home.png`
- `docs/evidence/fleet2b/fleet2_north_sea_z15.png`
