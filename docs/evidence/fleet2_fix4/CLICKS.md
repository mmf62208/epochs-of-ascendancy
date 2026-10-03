# FLEET-2 FIX #4 live-scale clicks (xvfb 1280×740, GER, Europe Home, world_accurate)

Tip `c080e435`. Home zoom **0.318**. RSS peak **2030.0 MB**. RESULT=**PASS**. xvfb ≠ live Play.

Option (a): **drawn body first** (not shrink-to-drawn+4px). (c) own land/air cap **40 screen px** below z0.65.

## 8 labels + unit ids

| sea | tag | fid | label |
|---|---|---|---|
| North Sea `950000` | GER | `GER_formation_2` | GER Fleet 2 |
| North Sea `950000` | FRA | `FRA_formation_2` | FRA Fleet 2 |
| North Sea `950000` | JAP | `JAP_formation_2` | JAP Fleet 2 |
| North Sea `950000` | SOV | `fielded_sov_20096448` | SOV Fleet 1 |
| Channel `950001` | ENG | `ENG_formation_2` | ENG Fleet 2 |
| Channel `950001` | ITA | `ITA_formation_2` | ITA Fleet 2 |
| Channel `950001` | POL | `fielded_pol_20097025` | POL Fleet 1 |
| Channel `950001` | USA | `fielded_usa_20095778` | USA Fleet 1 |

## Plates + East Kent + GER gap

All 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet (GER = own full card `fight=true assign=true`; others read-only).

| zoom | East Kent `711453` | old ENG chip | GER-nearest gap |
|---|---|---|---|
| 0.318 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 0.400 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 0.800 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |
| 1.500 | `ENG_formation_2` Channel | `ENG_formation_2` Channel | `GER_formation_2` own card |

## Land / air counters (Play FAIL list)

Each opened **its own unit** (foreign read-only). Never a fleet. Never a neighbour GER steal.

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
| coast `710374` | `NLD_formation_1` (not GER AW3) | `NLD_formation_1` |
| coast `710380` | `NLD_formation_1` (not GER AW3) | `NLD_formation_1` |

## Own GER drawn bodies at z0.318 (radius-cap check)

| click | fid | card |
|---|---|---|
| GER Div 6 | `GER_formation_6` | own `fight=true assign=true` |
| GER Div 7 | `GER_formation_7` | own `fight=true assign=true` |
| GER Garrison 4 | `GER_formation_4` | own `fight=true assign=true` |
| GER AW3 | `GER_formation_3` | own `fight=true assign=true` |
