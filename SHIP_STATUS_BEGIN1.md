# BEGIN-1 — Begin leftover release must not click the map

Updated: 2026-10-06
From: Cloud Agent
**Status:** draft PR · **merge HOLD** · **FIX #2** (restamp clock + poll pending press)

| | |
|---|---|
| **Base** | main `425b4448c7bec8b7f8d5602193b8e8466d1e5ec2` (LABEL-1) |
| **Branch** | `cursor/begin1-title-release-swallow-d55e` |
| **Product** | `f18a341a02fc823c35e037cc8e8e61f951eac41b` |
| **Tip** | `bc081427b05955d3659d3d3a59b1ed756fb1f6a6` |
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/84 |
| Verdict | isolated keep-green **PASS**. xvfb ≠ live Play. Merge **HOLD**. |

## Proven cause (FIX #2 re-gate of `8a32fa6f`: NOT READY)

Two real gaps, both missed by the FIX #1 test:

1. The 750 ms clock started **before** the slow Begin frame. Arming happens
   before `apply_living_title_boot` (~0.7–1.1 s), so the leftover release
   arrived 671–757 ms old. 8 cores: swallowed 7/8 (one expired at exactly
   750 ms). 2 cores (`taskset`): a 100 ms Begin click opened Loir-et-Cher
   and zoomed to 0.900 in 2/2 runs. `e5e3e338` swallowed there.
2. The later-frame clear broke the poll path. When Begin fires from a
   `_process` poll (TestRunner, title poll, `handle_live_pointer(null)`),
   the click's own press arrives in frame N+1, clears the arm, and the
   release picks.

## Diff

- `MapRenderer._tick_begin_title_release_swallow`: first `_process` with
  frames > arm_frame restamps the clock to now. Expiry only after that
  restamp **and** frames >= arm_frame + 2.
- Poll-path arms (`handle_live_pointer(null)`) set `begin_press_pending`.
  The first left press (including `_input` + `_unhandled_input` in that
  same frame) clears pending and keeps the arm. Later presses clear as
  before. Event-path keeps the same-frame rule.
- `LivingTitleBoot._apply_pointer_hit` → `_on_begin_new(pending_press,
  from_pointer)` → `arm_begin_title_release_swallow(pending_press)`.
- Guard: (a) same-frame `OS.delay_msec(900)` then next-frame release;
  (b) poll-path N+1 press keeps arm, later click picks; (c) title `_input`
  then MapRenderer `_input` same frame (M3); (d) lost-release + keyboard.

Camera / edge-pan / TipDismiss / FacilityIconLayer / labels / fleet stack /
unit pick ranking **unedited**. TestRunner poll wiring **unedited**.

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

## Gates (tip `bc081427b05955d3659d3d3a59b1ed756fb1f6a6`, product `f18a341a`)

| gate | kind | result |
|---|---|---|
| `HeadlessBegin1TitleReleaseFallthroughTest` | hd | **PASS** (`eoa_begin1_guard.sh` 1212.7 MB) |
| `HeadlessBegin1TitleReleaseFallthroughTest` | xvfb | **PASS** (`eoa_begin1_guard.sh` 1376.4 MB) |
| `HeadlessFirstSessionReadabilityTest` (TipDismiss) | hd | **PASS** |
| `HeadlessIx1LivingTitleEscBeginTest` | hd | **PASS** |
| `HeadlessFleet1LandSpillGateTest` | hd | **PASS** |
| `HeadlessFleet2SharedSeaMarkerTest` | hd | **PASS** |
| `HeadlessFac1aPanIconsTest` (PERF-1) | hd | **PASS** |
| `HeadlessFac1aHoverCacheTest` (PERF-1b) | hd | **PASS** |
| `HeadlessLabel1NationZoomTest` (LABEL-1) | hd | **PASS** |
| `tools/eoa_full_test_gates.sh --quick` | pure | same **14** `unit_board_play_path` reds as main; no new red. `map_qc` env skip (no Pillow). HOI open_p0=0. |
| `tools/live2_ts.sh` | live 2-core | **not present** in tree |

## Mutants (each FAIL)

| mutant | fail |
|---|---|
| M1 no expiry | lost-release swallow stayed armed after 800 ms |
| M2 no later-press clear | later-frame left press did not clear |
| M3 clear on same-frame press | title `_input` then MapRenderer `_input` dropped the arm |

## Fail-before `8a32fa6f` / pass-after tip

| case | `8a32fa6f` | tip |
|---|---|---|
| (a) same-frame 900 ms stall, release next frame | **FAIL** (clock expired) | **PASS** |
| (b) poll-path N+1 press then leftover release | **FAIL** (N+1 press cleared arm) | **PASS** |

## Test-merge (local only)

- PR #83 `5f459614` (`cursor/perf2-idle-wheel-refresh-f611`): `docs/CURRENT_STATE.md` content conflict only. `MapRenderer.gd` + `TESTING_PLAN.md` auto-merged.
- PR #85 `2df6d4ba` (`cursor/vis-1-map-readability-bf03`): `docs/CURRENT_STATE.md` content conflict only. `MapRenderer.gd` + `TESTING_PLAN.md` auto-merged.

## Out of scope (follow-up)

Space-as-Begin resuming the clock at 1x is **not** this slice.
