# CLOSE-1 isolated keep-green FIX #1

Tip `5ad300e399f667eb3b38742883f970810804be3d`. FAILS=0. KEEP_GREEN_RESULT=PASS. xvfb / headless ≠ live Play. Never EOA_SKIP_TITLE. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

`hd_ix1_mandate` prints `PASS (failures=0)`, not `RESULT=PASS`. Scored PASS.

| gate | kind | result | peak RSS MB | note |
|---|---|---|---|---|
| hd_mv1 | headless | PASS | **1204.0** | unedited |
| hd_mv1b | headless | PASS | **1207.6** | unedited |
| hd_rh1 | headless | PASS | **1205.4** | |
| hd_ix1_mandate | headless | PASS | **1205.5** | MandateGate `PASS (failures=0)` |
| hd_ix1_day | headless | PASS | **1205.7** | |
| hd_ix1_stay | headless | PASS | **1205.5** | |
| hd_ix1_search | headless | PASS | **1207.4** | |
| hd_ix1_title | headless | PASS | **1205.7** | |
| hd_ix1_complete | headless | PASS | **1204.4** | |
| hd_rx1_cross | headless | PASS | **1204.0** | |
| hd_rx1_vis | headless | PASS | **1203.9** | |
| hd_rx1_panel | headless | PASS | **1205.4** | |
| hd_rx1_stay | headless | PASS | **1205.3** | |
| hd_rt1_tier | headless | PASS | **1204.3** | |
| hd_rt1_edge | headless | PASS | **1204.3** | |
| hd_rt1_norebuild | headless | PASS | **1204.3** | |
| hd_fac1a | headless | PASS | **1205.8** | |
| py_fac1a | py | PASS | — | 7/7 |
| xvfb_mv1 | xvfb | PASS | **2041.2** | |
| xvfb_mv1_card | xvfb | PASS | **2045.9** | |
| xvfb_rh1 | xvfb | PASS | **2044.5** | |
| xvfb_fac1a | xvfb | PASS | **2040.8** | stale_lag 15/15 lone+cluster; rx1_mid 0.843/0.843 |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× | 0 errors |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1204.1 / 1343.0** | |
| UI-1 hd+xvfb | both | PASS | **1208.7 / 1351.9** | |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1209.2 / 1340.9** | |
| FLEET-2 hd / xvfb | both | PASS (a–p, unedited) | **1204.9 / 1339.6** | |
| Seeded RX-1 mid_river | xvfb | PASS | units-off **0.749** / close 0.775 / spine 1.000 | |
| FLEET-2 live-scale xvfb | xvfb | PASS | **2038.2** | 1280×740 GER Home |
| CLOSE-1 hd / xvfb | both | PASS | **1204.3 / 1339.1** | first edge pans + clamps |
| CLOSE-1 windowed | xvfb | PASS | **2031.6** | first_move 20/20 · first_edge 20/20 clamped |

FLEET-1 / FLEET-2 / MV-1 / MV-1b pick rules **unedited**. Köln FRA still unselectable.
