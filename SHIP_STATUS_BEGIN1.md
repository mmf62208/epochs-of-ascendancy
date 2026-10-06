# BEGIN-1 — Begin leftover release must not click the map

Updated: 2026-10-06
From: Cloud Agent
**Status:** draft PR · **merge HOLD** · **FIX #4** (gate wiring only)

| | |
|---|---|
| **Base** | main `425b4448c7bec8b7f8d5602193b8e8466d1e5ec2` (LABEL-1) |
| **Branch** | `cursor/begin1-title-release-swallow-d55e` |
| **Code SHA** | `f18a341a02fc823c35e037cc8e8e61f951eac41b` (product frozen) |
| **Later commits** | **test / docs / gates only** — MapRenderer / LivingTitleBoot unedited after `f18a341a` |
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/84 |
| Verdict | isolated keep-green **PASS**. xvfb ≠ live Play. Merge **HOLD**. |

## Proven cause (FIX #3 re-gate of `bef7fef2`: test NOT READY)

Product at `f18a341a` is READY. The FIX #2 test was not a behavior proof:

- Event-path 80 ms / (a) / (c) also **PASS on main** `425b4448` (no swallow). Direct `_mr._input` leftover does not pick.
- Only (b) poll caught the bug by behavior.
- M1 / M2 / M3 were caught only by internal-flag checks.
- M7 / M9 were caught only by source-text needles.
- A real-pipeline probe does catch it: main picks Loir-et-Cher; the tip does not.

## Diff (FIX #3, test-only)

`HeadlessBegin1TitleReleaseFallthroughTest` leftover / follow-up uses the real pipeline: `_title._input` **and** same-frame `Input.parse_input_event` + `Input.flush_buffered_events`. Leftover / follow-up judged by pid / inspector / zoom only (no swallow-flag early-out).

| case | what it proves |
|---|---|
| **T1** | Event-path 80 ms through the real pipeline. **FAIL** on main (Loir picked). **PASS** on the tip. |
| **T2** | Event Begin, drop leftover, real click 3 frames later must pick. Catches **M2**. |
| **T3** | Poll Begin, no press / no release, wait ≥1000 ms + 3 frames, first click must pick. Catches **M1**. |
| **T4** | T1 pipeline + `OS.delay_msec(900)` in the Begin frame, release in N+2, must be swallowed. Catches **M7**. |
| **T5** | Keep poll-path **(b)**. M3: Begin hit **outside** the button rect. **M9** makes no T1–T5 behavior difference. |

Camera / edge-pan / TipDismiss / FacilityIconLayer / labels / fleet stack /
unit pick ranking **unedited**. Product `f18a341a` **unedited**.

## FIX #4 (gate wiring only)

Re-gate of tip `f5bb5d6d`: (A)–(E) pass. (F) the full gate never ran BEGIN-1 —
`tools/eoa_full_test_gates.sh` had no `HeadlessBegin1TitleReleaseFallthroughTest`
or `eoa_begin1_guard.sh` reference. FIX #4 adds, after `launch_ix1_title_esc_begin`:

```
run_step launch_begin1_title_release \
  tools/run_godot.sh --headless --resolution 1280x740 -s res://scripts/core/HeadlessBegin1TitleReleaseFallthroughTest.gd || fail
```

No product change. No test-logic rewrite. Code SHA stays `f18a341a`.
Later commits are test / docs / gates only.

## Play recipe (human)

`docs/evidence/begin1/CLICKS.md` — 1280×740 Absolute @(0,29) no Ctrl.

Pre-step: `timeout 1500 tools/run_godot.sh --headless --path . --import --quit`

1. Title. Germany · 1936. Cursor on **Begin**.
2. Normal click: press, hold **~80–150 ms**, release (not a 0 ms tap).
3. Home must have **no** inspector, **no** unit card, **no** click-zoom.
   Loir-et-Cher under ~**(284, 580)** must stay unselected.
4. A **new** still-click on a GER land chip must still open Fill%/TOE.
5. Lost leftover up: after ~750 ms **from the first frame after Begin**,
   or after a later fresh press (not the poll-path Begin click itself),
   the first map click must pick.

## Gates (code SHA `f18a341a`; later commits test/docs/gates only)

| gate | kind | result |
|---|---|---|
| `HeadlessBegin1TitleReleaseFallthroughTest` | hd | **PASS** (`eoa_begin1_guard.sh` 1212.8 MB) |
| `HeadlessBegin1TitleReleaseFallthroughTest` | xvfb | **PASS** (`eoa_begin1_guard.sh` 1343.4 MB) |
| `HeadlessFirstSessionReadabilityTest` (TipDismiss) | hd | **PASS** |
| `HeadlessIx1LivingTitleEscBeginTest` | hd | **PASS** |
| `HeadlessFleet1LandSpillGateTest` | hd | **PASS** |
| `HeadlessFleet2SharedSeaMarkerTest` | hd | **PASS** |
| `HeadlessFac1aPanIconsTest` (PERF-1) | hd | **PASS** |
| `HeadlessFac1aHoverCacheTest` (PERF-1b) | hd | **PASS** |
| `HeadlessLabel1NationZoomTest` (LABEL-1) | hd | **PASS** |
| `launch_begin1_title_release` in `eoa_full_test_gates.sh` | hd | **PASS** (extracted `run_step` line on tip) |
| `tools/eoa_full_test_gates.sh --quick` | pure | same **14** `unit_board_play_path` reds as main; no new red. `map_qc` env skip (no Pillow). HOI open_p0=0. |
| `tools/live2_ts.sh` | live 2-core | **not present** in tree |

## Fail-on-main / pass-on-tip (T1–T4, xvfb)

| case | main `425b4448` | tip |
|---|---|---|
| T1 event-path 80 ms leftover | **FAIL** (Loir-et-Cher `710671`) | **PASS** |
| T2 drop leftover, click 3 frames later | PASS (no swallow to eat the click) | **PASS** |
| T3 poll, 1000 ms + 3 frames, first click | PASS (no swallow to eat the click) | **PASS** |
| T4 same-frame 900 ms, release N+2 | **FAIL** (Loir-et-Cher `710671`) | **PASS** |

T2 / T3 are mutant catchers (M2 / M1), not fail-on-main leftover proofs. T1 and T4 leftover-pick on main.

## Behavior-only mutants (flag + source-text assertions removed)

| mutant | behavior | caught by |
|---|---|---|
| M1 no expiry | **FAIL** | T3 first click `pid=-1` |
| M2 no later-press clear | **FAIL** | T2 click `pid=-1` |
| M3 clear on same-frame press | **FAIL** | T5 outside-button leftover picked Loir (T1 on-button still PASSes — `button_down` re-arms) |
| M7 clock not re-stamped | **FAIL** | T4 leftover picked Loir |
| M9 drop `arm_frame+2` only | **PASS** | no T1–T5 behavior difference |

## Test-merge (local only)

- PR #83 `5f459614` (`cursor/perf2-idle-wheel-refresh-f611`): `docs/CURRENT_STATE.md` content conflict only. `MapRenderer.gd` + `TESTING_PLAN.md` auto-merged.
- PR #85 `2df6d4ba` (`cursor/vis-1-map-readability-bf03`): `docs/CURRENT_STATE.md` content conflict only. `MapRenderer.gd` + `TESTING_PLAN.md` auto-merged.

## Out of scope (follow-up)

Space-as-Begin resuming the clock at 1x is **not** this slice.
