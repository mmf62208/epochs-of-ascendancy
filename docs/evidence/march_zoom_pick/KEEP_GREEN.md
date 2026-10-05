# March dest pick vs zoom — isolated keep-green

Tip after this run. FAILS=0. KEEP_GREEN_RESULT=PASS. xvfb / headless ≠ live Play. Never EOA_SKIP_TITLE. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

Harness-only verdict: no product change. Fresh interior dest=710380 at z 0.32 / 0.80 / 1.50.

March-zoom wrapper RSS overlapped a parallel TestScenario and is not an isolated peak. Isolated CLOSE-1 windowed **2041.2**.

| gate | kind | result | peak RSS MB | note |
|---|---|---|---|---|
| March zoom dest | hd+xvfb | PASS | overlap | dest=710380 × 3 zooms; Köln 710417 × 3 |
| March zoom dest windowed 1280×740 | xvfb | PASS fresh 3/3 | overlap 3403 | screen 640,370; hops=8 days=11 |
| CRASH-1 Halt | 10× hd + 10× xvfb | PASS | wrapper | exactly one release swallow; latch clears |
| CLOSE-1 / CLOSE-1b | hd+xvfb | PASS | **1209.2 / 1340.8** | leftover 11/11 |
| CLOSE-1 windowed | xvfb | PASS | **2041.2** | first_move 20/20 · first_edge 20/20 · first_edge_direct 16/16 (z0.80 cy=382.5) |
| UI-1 | hd+xvfb | PASS | **1208.6 / 1354.4** | unedited |
| FLEET-1 | hd+xvfb | PASS | **1205.9 / 1340.1** | unedited |
| FLEET-2 | hd+xvfb | PASS | **1206.1 / 1341.6** | unedited |

FLEET-1 / FLEET-2 / Halt / CLOSE-1/1b / UI-1 **unedited**. Title / Fill% / spill / chip rank **untouched**.
