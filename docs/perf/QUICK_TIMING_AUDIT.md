# `--quick` wall-time audit (GATES-TIMING-1)

**Question:** why does `tools/eoa_full_test_gates.sh --quick` swing between about **488s** and **838s**?

**Short answer:** the only inner-step wall times that can be read from the attached logs are the three Python unittest blocks (`Ran N tests in Xs`). Those sit in a tight band (~109–120s) on both the fastest and slowest runs. The ~350s swing lives in the **residual after Python** — the Godot `--headless` steps — but those processes do **not** print wall clocks, and their `--quick` stdout is nearly identical across the 488s and 838s runs. Per-Godot-step durations inside `--quick` **cannot** be derived from this archive. The three likeliest variance sources are named below with the evidence that *does* exist.

This note uses **only** the attached `eoa_quick_logs.tgz` plus `mtimes.txt`. No numbers are invented. Where a duration cannot be derived, that is stated.

The runner change in this PR (`TIME` / `TIMING SUMMARY` / `eoa-gates-step-timings.json`) exists so the next `--quick` does not have this gap.

## Sources and how times were derived

| Source | What it is | Confidence for `--quick` inner steps |
|---|---|---|
| `results/quick.elapsed_s` and `runner.log` `[gate] END quick … elapsed=Ns` | Whole `--quick` wall time | **High** (wrapper timed the process) |
| `quick.log` lines `Ran N tests in Xs` | `unit_board_play_path` / `unit_save_path` / `air_physics_p1` | **High** (unittest's own timer) |
| `quick.log` `[eoa-gates] STEP` / `OK` / `FAIL` | Step **order** and pass/fail, not duration | n/a |
| `HeadlessOrdersPerf1Test` `first refresh Nms` / `[STEP] … Nms` | Inner test work **after** Godot is up | **High for inner ms**, **none for process wall** |
| `runner.log` `[gate] END case-g elapsed=Ns` (and other `case-*`) | Wrapper **re-runs after** `--quick`, not the inner `headless_orders_perf1` | **High for those extra processes**; only a **proxy** for the same binary inside `--quick` |
| `mtimes.txt` on `results/case-*-xdg/.../quicksave.json` | When that wrapper case **wrote a save** | **Medium** corroboration of wrapper case length; **not** `--quick` inner steps (those xdg dirs are created after `END quick`) |
| `mtimes.txt` on `results/quick.log` | Close time of the captured stdout | **High** for `--quick` **end**, no per-step split (there are **no** per-step `*.log` files in the archive) |
| Godot `TimeManager: … (elapsed=N)` | In-game **days**, not wall seconds | **Do not use** |

There is **no** `--log DIR` tree of `unit_board_play_path.log` / `headless_garrison1.log` in the archive, so mtimes cannot be differenced across inner steps.

## Whole `--quick` wall (high confidence)

From `quick.elapsed_s` (same figures as `runner.log` `END quick elapsed=`):

| Run dir | SHA (`SOURCE_SHA.txt`) | `--quick` s | exit (`quick.exit` / `END quick ec=`) |
|---|---|---:|---|
| `eoa-postmerge-5de4bbf0` | `5de4bbf0` | **468** | 1 (`headless_tutorial1` FAIL in `quick.log`) |
| `eoa-postmerge-5d099346` | `5d099346af1304eccf71bcf6e0d9c0afb4b715c0` | **488** | 0 |
| `eoa-smoke-12b3db7f-gate` | `12b3db7f` | **488** | 1 |
| `eoa-smoke-7a585f53-gate` | `7a585f53` | **489** | 0 |
| `eoa-postmerge-330644ef` | `330644ef` | **492** | 0 |
| `eoa-postmerge-26f9eb8f` | `26f9eb8f` | **502** | 0 |
| `eoa-smoke-aaeef1e5-gate` / `eoa-smoke-764dc8b4-gate` | those tips | **507** | 0 / 1 |
| `eoa-smoke-85ede6b5-gate` | `85ede6b5` | **531** | 0 |
| `eoa-smoke-8fed6890-gate` | `8fed6890` | **555** | 1 |
| `eoa-smoke-5916404c-gate` | `5916404c740c1bbafa76ee8f23afd415c1822c10` | **563** | 0 |
| `eoa-smoke-240e2c3e-gate` | `240e2c3e` | **571** | 0 |
| `eoa-smoke-393bbf54-gate` | `393bbf54` | **606** | 0 |
| `eoa-smoke-db6a1adb-gate` | `db6a1adb34bf5e212f789b9521cfa12f358be1d9` | **622** | 1 |
| `eoa-smoke-1b753e7d-gate` | `1b753e7d` | **681** | 0 |
| `eoa-postmerge-78a34631` | `78a34631` | **693** | 0 |
| `eoa-postmerge-e471e125` | `e471e1257979f11f59f9e927dc1c4de68fbfc118` | **838** | 0 |

Observed range in this archive: **468–838s**. The 488 / 838 pair is `5d099346` vs `e471e125`.

## Python unittest blocks (high confidence)

`quick.log` always has three `Ran N tests in Xs` lines, matching `run_step unit_board_play_path`, `unit_save_path`, and `air_physics_p1`.

| Run | `--quick` s | `unit_board_play_path` (`Ran N tests in Xs`) | `unit_save_path` (51) | `air_physics_p1` (12) | Python sum | Residual (`--quick` − Python) | `Godot Engine v` count |
|---|---:|---:|---:|---:|---:|---:|---:|
| `5de4bbf0` | 468 | 433 in 108.623s | 0.285s | 0.002s | 108.910s | **359.090s** | 27 |
| `5d099346` | 488 | 433 in 110.029s | 0.288s | 0.002s | 110.319s | **377.681s** | 27 |
| `5916404c` | 563 | 433 in 108.842s | 0.293s | 0.002s | 109.137s | **453.863s** | 27 |
| `e471e125` | 838 | 433 in 114.298s | 0.291s | 0.002s | 114.591s | **723.409s** | 27 |
| `db6a1adb` | 622 | 435 in 107.793s (**FAIL**) | 0.272s | 0.002s | 108.067s | **513.933s** | 29 |
| `78a34631` | 693 | 433 in 116.759s | 0.297s | 0.002s | 117.058s | **575.942s** | 25 |
| `1b753e7d` | 681 | 433 in 110.395s | 0.293s | 0.002s | 110.690s | **570.310s** | 27 |

`map_qc` and `hoi_matrix_product` have **no** timer in `quick.log` (6 lines and 3 lines of output). Their wall times are unknown; they are not large enough in log size to explain hundreds of seconds.

**488 vs 838:** Python differs by **4.272s**. Residual differs by **345.728s**. The swing is not the unittest steps.

## Godot steps inside `--quick`: what can and cannot be derived

On `5d099346` (488s) and `e471e125` (838s) the `--quick` step lists match (same `STEP` names, all `OK`). Line counts per step match except `headless_tutorial1` (108 vs 98 lines — the faster tip has the extra P1a hug `[INFO]` lines). `Godot Engine v` appears **27** times on both.

Inner `HeadlessOrdersPerf1Test` millisecond prints are also in the same band:

| Run | `--quick` s | `first refresh` ms list | sum of those refresh ms |
|---|---:|---|---:|
| `5d099346` | 488 | 547, 537, 373, 554, 386, 556, 552, 373, 553 | 4431 |
| `e471e125` | 838 | 550, 549, 384, 555, 390, 569, 559, 378, 551 | 4485 |
| `5916404c` | 563 | 551, 560, 391, 577, 397, 550, 556, 393, 579 | 4554 |
| `db6a1adb` | 622 | 721, 566, 424, 593, 437, 554, 618, 422, 688 | 5023 |

Those figures are **in-process test work**, not engine boot / process wall. They do **not** move with the 350s swing.

`headless_garrison1` is 6029 lines on both 488s and 838s (same 100-day soak log). Wall time of that process is **unknown**.

**Cannot derive** per-step wall for: `headless_garrison1`, `headless_ai_war1`, `headless_cl1_siege_hold1`, `headless_ink_tooltips0`, `headless_campaign_save1`, `headless_autosave1`, `headless_orders_perf1` (as a process), `headless_rtt_*`, `headless_audio*`, `headless_stability_justice1`, `headless_victory_paths1`, `headless_settings_toggles1`, `headless_first20_*`, `headless_search_hotkey1`, `headless_tutorial1`, `headless_input_polish1`.

## Wrapper processes after `--quick` (high confidence, different job)

`runner.log` times extra Godot jobs **after** `END quick`. Those xdg trees (`autosave1-xdg`, `case-a-xdg`, …) match `mtimes.txt`. They are **not** the inner `--quick` `run_step` processes (inner steps use `mktemp -d` and are not in the archive).

Typical isolated wrapper times on `5d099346` (`runner.log`): autosave1 **14s**, siegehold1 **12s**, cases a–f **12–16s**, case-g **11s**. `mtimes.txt` save writes sit on those same timestamps (e.g. case-a `14:42:45`, case-b `14:42:57`).

Two wrapper **case-g** outliers exist in this archive:

| Run | `--quick` s | wrapper `END case-g elapsed=` | `mtimes.txt` case-f → case-g save |
|---|---:|---:|---|
| `eoa-smoke-393bbf54-gate` | 606 | **248s** | `08:54:47` → `08:59:00` (~253s between save writes) |
| `eoa-smoke-db6a1adb-gate` | 622 | **63s** | `15:14:57` → `15:16:06` (~69s) |
| `eoa-postmerge-5d099346` | 488 | **11s** | `14:43:47` → `14:44:03` (~16s) |
| `eoa-postmerge-e471e125` | 838 | **12s** | `11:07:31` → `11:07:48` (~17s) |

`eoa_full_test_gates.sh` comments that `headless_orders_perf1` is “unfixed several minutes total; fixed < ~70s total”, with per-case caps **150s** (a–f) and **400s** (g). The 248s isolated case-g is direct evidence that **this binary can sit in the several-minute band** even when `RESULT=PASS`.

Note: the **838s** `--quick` (`e471e125`) is **not** explained by its own post-quick case-g (12s). If case-g stalled, it did so **inside** `--quick` without extra log lines — which this archive cannot prove or disprove per step.

## Composition differences (not the 488/838 pair, but they add wall)

- `db6a1adb` (`--quick` 622s, FAIL): extra `headless_sim1110a_defence` (3821 lines) and `headless_sim1110a_r_threat_cache` (5626 lines); 29 Godot banners vs 27. Those two steps’ wall times are **unknown**. `unit_board_play_path` still only **107.793s**.
- `1b753e7d` (681s): extra `headless_sim1110a_defence` (4498 lines); no `headless_cl1_siege_hold1` in the STEP list.
- `78a34631` (693s): **25** Godot banners, no `headless_cl1_siege_hold1` / `headless_input_polish1` — **fewer** Godot steps than the 488s run, so the 693s is not “more steps”. Per-process wall was higher; which process is **unknown**.

## Three likeliest steps behind the variance

1. **`headless_orders_perf1`** — Seven sequential Godot processes with 150s/400s caps. Inner logged work is ~the same on 488s and 838s (~4.4s of `first refresh` sums), so any stall is **outside** those prints (boot, wait, or a quiet loop). Wrapper-isolated case-g has been **11s, 63s, and 248s** in this archive; 248s alone is most of a 488→~740s move. Highest-capacity, best-evidenced suspect. Confidence that it *can* swing: **high**. Confidence that it *did* swing **inside** the 838s `--quick`: **low** (no inner wall clock).

2. **`headless_garrison1`** — Largest inner `--quick` log (6029 lines, 100-day soak) on both 488s and 838s. Same line count ⇒ same logged work; wall still unknown. One slow 100-day soak would move the residual without changing stdout. Confidence it is heavy: **high**. Confidence it caused the 350s swing: **low** (no timer).

3. **Godot process startup across the other ~20 single-engine `run_step`s** (not one named step, but the residual class). Fast-run residual ~359–378s with 27 engines is ~13–14s per engine if split evenly, which matches wrapper isolated autosave/siege/tutorial times (**11–15s**). Slow-run residual **723s** with the **same** 27 banners is ~27s average, or a subset stalled. Individual heads (`headless_campaign_save1` 1148 lines, `headless_tutorial1`, …) cannot be ranked from this archive. Treat this as “the unnamed Godot boots”, not a pinned step. Confidence the residual is Godot: **high**. Confidence for any one of those names: **none**.

On tips that include them, **`headless_sim1110a_defence` / `headless_sim1110a_r_threat_cache`** are additional large Godot steps (thousands of lines) and are the obvious extra cost for `db6a1adb` / `1b753e7d` versus `5d099346`. They are **absent** from the 488 vs 838 pair.

## What the next `--quick` will add

`run_step` now prints `[eoa-gates] TIME <name> <seconds>s passed=true|false` after the existing `OK`/`FAIL` line, writes `eoa-gates-step-timings.json` next to the run log, and prints a slowest-first `TIMING SUMMARY`. Existing `ALL PASSED (quick)` / `FAILED (quick)` / `[eoa-gates] FAIL` strings are unchanged.
