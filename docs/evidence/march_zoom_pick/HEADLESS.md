# March zoom dest pick (headless / xvfb)

NOT live Play. `tools/run_godot.sh` Godot 4.7.1-rc2. xvfb 1280×740 numbers below.

GIS interiors: Heidekreis `710380` world=`7461.096,1530.885` · Köln `710417` world=`7350.861,1631.095`.
d(Heidekreis, Harz)=**73.2** · d(Heidekreis, Börde)=**72.0** (not adjacent).

## Fresh picks (camera on interior; dest must match)

| kind | zoom | target | screen | dest |
|---|---|---|---|---|
| fresh | z=0.32 | Heidekreis 710380 | 902.8,370.0 | **710380** Heidekreis |
| fresh | z=0.80 | Heidekreis 710380 | 640.0,370.0 | **710380** Heidekreis |
| fresh | z=1.50 | Heidekreis 710380 | 640.0,370.0 | **710380** Heidekreis |
| fresh | z=0.32 | Köln 710417 | 867.5,370.0 | **710417** Köln |
| fresh | z=0.80 | Köln 710417 | 640.0,370.0 | **710417** Köln |
| fresh | z=1.50 | Köln 710417 | 640.0,370.0 | **710417** Köln |

`mm_screen` matched dest on every row. `_screen_to_world` round-trip world unchanged.

## Stale-screen hypothesis (Köln camera)

| src zoom | reuse zoom | stale dest | fresh dest |
|---|---|---|---|
| 1.50 | 0.80 | Vest- og Sydsjælland | 710380 Heidekreis |
| 1.50 | 0.32 | miss `-1` | 710380 Heidekreis |
| 0.32 | 0.80 | Zielonogórski | 710380 Heidekreis |
| 0.32 | 1.50 | **Mansfeld-Südharz** (Harz neighbor) | 710380 Heidekreis |

Stale screens miss by whole provinces (including the Harz-adjacent cell). Fresh recompute never misses.

RESULT=**PASS** (failures=0) hd+xvfb.
