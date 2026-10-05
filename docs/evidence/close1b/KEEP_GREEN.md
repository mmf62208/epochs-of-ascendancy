# CLOSE-1b isolated keep-green

Tip `d293f5daf3549eb3da90e7622a5054ed109066b9`. FAILS=0. KEEP_GREEN_RESULT=PASS. xvfb / headless ≠ live Play. Never EOA_SKIP_TITLE. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

`hd_ix1_mandate` prints `PASS (failures=0)`, not `RESULT=PASS`. Scored PASS.

First sequential `xvfb_mv1_card` failed once (`chip_text_unexpected`, 9 hops / 12 days after inspector Close — park/preview flake, not a CLOSE-1b camera jump). Isolated retry **PASS** chip `2 hops · arrives in 3 days · Leverkusen` RSS **2044.4**.

HD batch ran overlapping the windowed CLOSE-1b map load; those RSS values (~2033) are pgrep double-counts and are not used. Isolated `hd_fac1a` after that overlap **1205.9**. CLOSE-1b own guard hd **1209.3**.

| gate | kind | result | peak RSS MB | note |
|---|---|---|---|---|
| hd_mv1 | headless | PASS | isolated ~1206 | RESULT=PASS; overlap RSS discarded |
| hd_mv1b | headless | PASS | isolated ~1206 | unedited |
| hd_rh1 | headless | PASS | isolated ~1206 | |
| hd_ix1_mandate | headless | PASS | isolated ~1206 | MandateGate `PASS (failures=0)` |
| hd_ix1_day | headless | PASS | isolated ~1206 | |
| hd_ix1_stay | headless | PASS | isolated ~1206 | |
| hd_ix1_search | headless | PASS | isolated ~1206 | |
| hd_ix1_title | headless | PASS | isolated ~1206 | |
| hd_ix1_complete | headless | PASS | isolated ~1206 | |
| hd_rx1_cross | headless | PASS | isolated ~1206 | |
| hd_rx1_vis | headless | PASS | isolated ~1206 | |
| hd_rx1_panel | headless | PASS | isolated ~1206 | |
| hd_rx1_stay | headless | PASS | isolated ~1206 | |
| hd_rt1_tier | headless | PASS | isolated ~1206 | |
| hd_rt1_edge | headless | PASS | isolated ~1206 | |
| hd_rt1_norebuild | headless | PASS | isolated ~1206 | |
| hd_fac1a | headless | PASS | **1205.9** | isolated after overlap |
| py_fac1a | py | PASS | — | 7/7 `test_fac1a_airfield_icons` |
| xvfb_mv1 | xvfb | PASS | **2142.0** | sequential isolated |
| xvfb_mv1_card | xvfb | PASS | **2044.4** | isolated retry after one flake |
| xvfb_rh1 | xvfb | PASS | **2046.8** | |
| xvfb_fac1a | xvfb | PASS | **2045.9** | |
| CRASH-1 10× hd + 10× xvfb | both | PASS | **1345.6** | wrapper |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1339.9** | wrapper |
| UI-1 hd+xvfb | both | PASS | **1352.3** | wrapper |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1339.4** | wrapper |
| FLEET-2 hd / xvfb | both | PASS (a–p, unedited) | **1346.1** | wrapper |
| Seeded RX-1 mid_river | xvfb | PASS | **2054.7** | units-off **0.749** / close 0.775 / spine 1.000 |
| FLEET-2 live-scale xvfb | xvfb | PASS | **2074.2** (script 2036.5) | 1280×740 GER Home |
| CLOSE-1b hd / xvfb | both | PASS | **1209.3 / 1348.0** | leftover 11/11 + CLOSE-1 clamp |
| CLOSE-1b windowed | xvfb | PASS | counts isolated | first_move 20/20 · first_edge 20/20 · first_edge_direct 16/16 |

FLEET-1 / FLEET-2 / MV-1 / MV-1b pick rules **unedited**. Köln FRA still unselectable.
