# FLEET-2 FIX #6 keep-green 2026-10-03T04:00:35Z tip=d15ac739 (docs tip later)

FAILS=0. KEEP_GREEN_RESULT=PASS. xvfb / headless ≠ live Play. Never EOA_SKIP_TITLE. `tools/run_godot.sh` only.

| gate | kind | result | peak RSS MB | note |
|---|---|---|---|---|
| hd_mv1 | headless | PASS | **1203.3** | unedited |
| hd_mv1b | headless | PASS | **1203.3** | unedited |
| hd_rh1 | headless | PASS | **1203.1** | |
| hd_ix1_mandate | headless | PASS | **1203.2** | MandateGate PASS |
| hd_ix1_day | headless | PASS | **1203.5** | |
| hd_ix1_stay | headless | PASS | **1203.2** | |
| hd_ix1_search | headless | PASS | **1203.4** | |
| hd_ix1_title | headless | PASS | **1207.7** | |
| hd_ix1_complete | headless | PASS | **1203.2** | |
| hd_rx1_cross | headless | PASS | **1203.2** | |
| hd_rx1_vis | headless | PASS | **1203.2** | |
| hd_rx1_panel | headless | PASS | **1203.1** | |
| hd_rx1_stay | headless | PASS | **1203.3** | |
| hd_rt1_tier | headless | PASS | **1203.3** | |
| hd_rt1_edge | headless | PASS | **1203.3** | |
| hd_rt1_norebuild | headless | PASS | **1203.1** | |
| hd_fac1a | headless | PASS | **1203.5** | |
| py_fac1a | py | PASS | — | 7 ok |
| xvfb_mv1 | xvfb | PASS | **2040.8** | |
| xvfb_mv1_card | xvfb | PASS | **2045.2** | |
| xvfb_rh1 | xvfb | PASS | **2041.1** | |
| xvfb_fac1a | xvfb | PASS | **2043.8** | stale_lag=true fails=0 iters=15 lone+cluster; rx1 mid 0.843/0.843 |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× | 0 errors |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1203.3 / 1343.4** | |
| UI-1 hd+xvfb | both | PASS | **1207.9 / 1353.7** | |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1203.5 / 1344.5** | |
| FLEET-2 hd / xvfb | both | PASS (a–n) | **1209.0 / 1340.7** | |
| Seeded RX-1 mid_river | xvfb | PASS | units-off **0.749** / close 0.775 / spine 1.000 | |
| FLEET-2 live-scale xvfb | xvfb | PASS | **2031.4** | 1280×740 GER Home; see CLICKS.md |

FLEET-1 / MV-1b **unedited**. Köln FRA still unselectable. Same-nation piles not retargeted.
