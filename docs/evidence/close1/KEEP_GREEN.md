# CLOSE-1 isolated keep-green 2026-10-05 tip=`ddc955c9`

FAILS=0. KEEP_GREEN_RESULT=PASS. xvfb / headless ≠ live Play. Never EOA_SKIP_TITLE. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

Wrapper `rss_mb=` on some Godot RESULT lines is 0.0 (test prints `rss_mb=0.0 peak_kb=0`). Peak RSS below is `who=wrapper.rss mb=` / `who=hd.rss` / `who=xvfb.rss`.

`hd_ix1_mandate` prints `PASS (failures=0)` / `MandateGate ok`, not `RESULT=PASS`. Isolated runner first marked FAIL on that pattern; the log is PASS. Re-scored PASS.

`FLEET-2 live-scale` wrapper prints `FLEET-2 live-scale: RESULT=PASS` and `WindowedFleet2LiveScaleCheck: RESULT=PASS` in `fleet2live/live.log`. Isolated runner first marked FAIL looking only at the capture log needle; the log is PASS. Re-scored PASS.

| gate | kind | result | peak RSS MB | note |
|---|---|---|---|---|
| hd_mv1 | headless | PASS | **1212.3** | unedited |
| hd_mv1b | headless | PASS | **1203.9** | unedited |
| hd_rh1 | headless | PASS | **1203.7** | |
| hd_ix1_mandate | headless | PASS | **1204.8** | MandateGate `PASS (failures=0)` |
| hd_ix1_day | headless | PASS | **1205.6** | |
| hd_ix1_stay | headless | PASS | **1203.8** | |
| hd_ix1_search | headless | PASS | **1203.9** | |
| hd_ix1_title | headless | PASS | **1205.6** | |
| hd_ix1_complete | headless | PASS | **1207.7** | |
| hd_rx1_cross | headless | PASS | **1203.8** | |
| hd_rx1_vis | headless | PASS | **1204.2** | |
| hd_rx1_panel | headless | PASS | **1203.7** | |
| hd_rx1_stay | headless | PASS | **1203.8** | |
| hd_rt1_tier | headless | PASS | **1203.8** | |
| hd_rt1_edge | headless | PASS | **1204.3** | |
| hd_rt1_norebuild | headless | PASS | **1207.3** | |
| hd_fac1a | headless | PASS | **1204.0** | |
| py_fac1a | py | PASS | — | |
| xvfb_mv1 | xvfb | PASS | **2047.1** | wrapper.rss |
| xvfb_mv1_card | xvfb | PASS | **2044.9** | wrapper.rss |
| xvfb_rh1 | xvfb | PASS | **2036.1** | wrapper.rss |
| xvfb_fac1a | xvfb | PASS | **2045.5** | stale_lag=true fails=0 iters=15 lone+cluster; rx1 mid 0.843/0.843 |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× | 0 errors |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1204.0 / 1340.7** | |
| UI-1 hd+xvfb | both | PASS | **1208.5 / 1353.1** | |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1208.6 / 1339.6** | |
| FLEET-2 hd / xvfb | both | PASS (a–p, unedited) | **1209.3 / 1340.8** | |
| Seeded RX-1 mid_river | xvfb | PASS | units-off **0.749** / close 0.775 / spine 1.000 | |
| FLEET-2 live-scale xvfb | xvfb | PASS | **2041.4** | 1280×740 GER Home; `RESULT=PASS` reasons=[] |
| CLOSE-1 hd / xvfb | both | PASS | **1207.6 / 1339.0** | first edge pans |
| CLOSE-1 windowed | xvfb | PASS | **2129.0** | first_move 20/20 · first_edge 20/20 |

FLEET-1 / FLEET-2 / MV-1 / MV-1b pick rules **unedited**. Köln FRA still unselectable.
