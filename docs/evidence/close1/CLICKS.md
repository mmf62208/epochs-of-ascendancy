# CLOSE-1 windowed xvfb 1280x740 (FIX #1)

Tip `5ad300e399f667eb3b38742883f970810804be3d`. GER · Europe Home · `world_accurate`. `tools/eoa_close1_windowed_check.sh`. RSS peak **2031.6 MB**. RESULT=**PASS**. xvfb ≠ live Play. Never `EOA_SKIP_TITLE`.

Close at real BtnClose **(304, 523)**. First move after Close: camera delta **0.00** on all 20 trials (zooms 0.32–1.50 including **0.32 and 0.80**, 1/4/8 steps, with and without leftover `button_mask`). First top-edge pan after Close: north **and** theater-clamped (cam_y = `_apply_camera_bounds`; no EDGE032b cy≈−12384 runaway). 60-frame hold. No leftover `_left_btn_down` / `_left_pan_active`.

first_move 20/20 · first_edge 20/20

| # | zoom | close | steps | move_d | first_move | edge_dy | cam_y | first_edge |
|---|---|---|---|---|---|---|---|---|
| 1 | 0.32 | 304,523 | 1 | 0.00 | PASS | -745.8 | 1076.2 | PASS |
| 2 | 0.32 | 304,523 | 4 | 0.00 | PASS | -420.0 | 1076.2 | PASS |
| 3 | 0.32 | 304,523 | 1 | 0.00 | PASS | -420.0 | 1076.2 | PASS |
| 4 | 0.32 | 304,523 | 8 | 0.00 | PASS | -420.0 | 1076.2 | PASS |
| 5 | 0.50 | 304,523 | 1 | 0.00 | PASS | -420.0 | 660.0 | PASS |
| 6 | 0.50 | 304,523 | 4 | 0.00 | PASS | -420.0 | 660.0 | PASS |
| 7 | 0.50 | 304,523 | 1 | 0.00 | PASS | -420.0 | 660.0 | PASS |
| 8 | 0.50 | 304,523 | 8 | 0.00 | PASS | -420.0 | 660.0 | PASS |
| 9 | 0.80 | 304,523 | 1 | 0.00 | PASS | -420.0 | 382.5 | PASS |
| 10 | 0.80 | 304,523 | 4 | 0.00 | PASS | -420.0 | 382.5 | PASS |
| 11 | 0.80 | 304,523 | 1 | 0.00 | PASS | -420.0 | 382.5 | PASS |
| 12 | 0.80 | 304,523 | 8 | 0.00 | PASS | -420.0 | 382.5 | PASS |
| 13 | 1.20 | 304,523 | 1 | 0.00 | PASS | -351.2 | 228.3 | PASS |
| 14 | 1.20 | 304,523 | 4 | 0.00 | PASS | -365.9 | 228.3 | PASS |
| 15 | 1.20 | 304,523 | 1 | 0.00 | PASS | -365.9 | 228.3 | PASS |
| 16 | 1.20 | 304,523 | 8 | 0.00 | PASS | -362.1 | 228.3 | PASS |
| 17 | 1.50 | 304,523 | 1 | 0.00 | PASS | -585.9 | 166.7 | PASS |
| 18 | 1.50 | 304,523 | 4 | 0.00 | PASS | -615.4 | 166.7 | PASS |
| 19 | 1.50 | 304,523 | 1 | 0.00 | PASS | -615.4 | 166.7 | PASS |
| 20 | 1.50 | 304,523 | 8 | 0.00 | PASS | -615.3 | 166.7 | PASS |
