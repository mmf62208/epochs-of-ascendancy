# March zoom dest pick (headless)

NOT live Play. Tip after first PASS run. `tools/run_godot.sh` Godot 4.7.1-rc2.

GIS interiors: Heidekreis `710380` world=`7461.096,1530.885` · Köln `710417` world=`7350.861,1631.095`.
d(Heidekreis, Harz)=**73.2** · d(Heidekreis, Börde)=**72.0** (not adjacent).

## Fresh picks (camera on interior; dest must match)

| kind | zoom | target | screen | dest |
|---|---|---|---|---|
| fresh | z=0.32 | Heidekreis 710380 | 1060.8,489.9 | **710380** Heidekreis |
| fresh | z=0.80 | Heidekreis 710380 | 753.0,483.0 | **710380** Heidekreis |
| fresh | z=1.50 | Heidekreis 710380 | 726.7,456.7 | **710380** Heidekreis |
| fresh | z=0.32 | Köln 710417 | 970.5,492.5 | **710417** Köln |
| fresh | z=0.80 | Köln 710417 | 740.4,470.4 | **710417** Köln |
| fresh | z=1.50 | Köln 710417 | 728.2,458.2 | **710417** Köln |

`mm_screen` matched dest on every row. `_screen_to_world` round-trip world unchanged.

## Stale-screen hypothesis (Köln camera)

| src zoom | reuse zoom | stale dest | fresh dest |
|---|---|---|---|
| 1.50 | 0.80 | **710318 Uckermark** | 710380 Heidekreis |
| 1.50 | 0.32 | miss `-1` | 710380 Heidekreis |
| 0.32 | 0.80 | **711075 Jeleniogórski** | 710380 Heidekreis |
| 0.32 | 1.50 | **710549 Sömmerda** | 710380 Heidekreis |

Stale screens miss by whole provinces. Fresh recompute never misses. Harz/Börde are that miss class (south of Heidekreis toward Home), not a 1-hex product offset.

RESULT=**PASS** (failures=0).
