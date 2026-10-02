# FLEET-2 FIX #3 live-scale clicks (xvfb 1280×740, GER, Europe Home, world_accurate)

Tip `5b0c4d18`. Home zoom **0.318**. RSS peak **2031.6 MB**. RESULT=**PASS**. xvfb ≠ live Play.

## 8 labels + unit ids

| sea | tag | fid | label |
|---|---|---|---|
| North Sea `950000` | GER | `GER_formation_2` | GER Fleet 2 |
| North Sea `950000` | FRA | `FRA_formation_2` | FRA Fleet 2 |
| North Sea `950000` | JAP | `JAP_formation_2` | JAP Fleet 2 |
| North Sea `950000` | SOV | `fielded_sov_21559591` | SOV Fleet 1 |
| Channel `950001` | ENG | `ENG_formation_2` | ENG Fleet 2 |
| Channel `950001` | ITA | `ITA_formation_2` | ITA Fleet 2 |
| Channel `950001` | POL | `fielded_pol_21560167` | POL Fleet 1 |
| Channel `950001` | USA | `fielded_usa_21558889` | USA Fleet 1 |

## Clicks

All 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet (GER = own full card `fight=true assign=true`; others read-only). Never a land unit.

| zoom | extra | fid | result |
|---|---|---|---|
| 0.318 | East Kent `711453` | `ENG_formation_2` | Channel fleet, not GER Div |
| 0.318 | old ENG chip | `ENG_formation_2` | Channel fleet |
| 0.318 | GER-nearest gap | `GER_formation_2` | own GER fleet card |
| 1.500 | East Kent `711453` | `ENG_formation_2` | Channel fleet |
| 1.500 | old ENG chip | `ENG_formation_2` | Channel fleet |
| 1.500 | GER-nearest gap | `GER_formation_2` | own GER fleet card |
