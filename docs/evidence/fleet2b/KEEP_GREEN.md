# FLEET-2b keep-green 2026-10-03 tip=`c62d85b6` (docs tip later)

FAILS=0. KEEP_GREEN_RESULT=PASS. xvfb / headless ≠ live Play. Never EOA_SKIP_TITLE. `tools/run_godot.sh` only.

Wrapper `rss_mb=` on Godot RESULT lines is 0.0 (test prints `rss_mb=0.0 peak_kb=0`). Peak RSS below is `who=wrapper.rss mb=` / `who=hd.rss` / `who=xvfb.rss`.

`hd_ix1_mandate` prints `PASS (failures=0)` / `MandateGate ok`, not `RESULT=PASS`. Isolated runner first marked FAIL on that pattern; the log is PASS. Re-scored PASS.

FLEET-2 live-scale first failed when StatBars beat every foreign plate interior (Emden NLD centre + neighbours stolen). Re-run after the 60% inner-face fix: **PASS** RSS **2037.5**.

| gate | kind | result | peak RSS MB | note |
|---|---|---|---|---|
| hd_mv1 | headless | PASS | **1203.5** | unedited |
| hd_mv1b | headless | PASS | **1203.5** | unedited |
| hd_rh1 | headless | PASS | **1203.2** | |
| hd_ix1_mandate | headless | PASS | **1203.3** | MandateGate `PASS (failures=0)` |
| hd_ix1_day | headless | PASS | **1205.3** | |
| hd_ix1_stay | headless | PASS | **1203.2** | |
| hd_ix1_search | headless | PASS | **1204.7** | |
| hd_ix1_title | headless | PASS | **1208.0** | |
| hd_ix1_complete | headless | PASS | **1203.4** | |
| hd_rx1_cross | headless | PASS | **1203.4** | |
| hd_rx1_vis | headless | PASS | **1203.3** | |
| hd_rx1_panel | headless | PASS | **1203.2** | |
| hd_rx1_stay | headless | PASS | **1203.3** | |
| hd_rt1_tier | headless | PASS | **1205.0** | |
| hd_rt1_edge | headless | PASS | **1203.3** | |
| hd_rt1_norebuild | headless | PASS | **1203.2** | |
| hd_fac1a | headless | PASS | **1203.9** | |
| py_fac1a | py | PASS | — | 7 ok |
| xvfb_mv1 | xvfb | PASS | **2077.8** | wrapper.rss |
| xvfb_mv1_card | xvfb | PASS | **2043.9** | wrapper.rss |
| xvfb_rh1 | xvfb | PASS | **2042.4** | wrapper.rss |
| xvfb_fac1a | xvfb | PASS | **2047.2** | stale_lag=true fails=0 iters=15 lone+cluster; rx1 mid 0.843/0.843 |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× | 0 errors |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1203.4 / 1338.6** | |
| UI-1 hd+xvfb | both | PASS | **1208.1 / 1347.4** | |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1203.7 / 1340.5** | |
| FLEET-2 hd / xvfb | both | PASS (a–p) | **1209.1 / 1344.6** | re-run after 60% inner face |
| Seeded RX-1 mid_river | xvfb | PASS | units-off **0.749** / close 0.775 / spine 1.000 | |
| FLEET-2 live-scale xvfb | xvfb | PASS | **2037.5** | 1280×740 GER Home; see CLICKS.md |

FLEET-1 / MV-1b **unedited**. Köln FRA still unselectable. Same-nation piles not retargeted.
