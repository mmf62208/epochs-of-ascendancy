# BEGIN-1 — Begin leftover release must not click the map

Updated: 2026-10-06
From: Cloud Agent
**Status:** draft PR · **merge HOLD** · **FIX #1** (lost-release expiry)

| | |
|---|---|
| **Base** | main `425b4448c7bec8b7f8d5602193b8e8466d1e5ec2` (LABEL-1) |
| **Branch** | `cursor/begin1-title-release-swallow-d55e` |
| **Tip** | `1a29087f3f4eb06201191bcd94d015b7d82c9a95` |
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/84 |
| Verdict | isolated keep-green **PASS**. xvfb ≠ live Play. Merge **HOLD**. |

## Proven cause

Begin is `ACTION_MODE_BUTTON_PRESS`. `_on_begin_new` → `_finish` sets `_closed`
and `queue_free()`. `_living_title_boot_is_up()` is then false (closed **or**
queued). MapRenderer leftover left-release does not require a matching map
press, so a real ~80–150 ms mouse-up still-clicks the hex under the cursor
after Home (Loir-et-Cher at ~284,580 / 1280×740): inspector +
`_center_camera_on_province(..., "soft")` 0.776→0.900.

Instant 0 ms press+release stays on the still-alive Begin Control for that
frame, so GUI eats the up and the race stays hidden.

**FIX #1:** the swallow could stay armed forever if the leftover up never
reached Godot (unfocused window / keyboard Begin). A same-frame clear-on-press
also dropped a `button_down` arm before the leftover up. Product now expires
after **~750 ms** (time, not frames — uncapped headless can burn 24 frames in
well under 80 ms), and a **later-frame** left press clears it. `button_down`
arms only while the left mouse button is actually held (Enter/Space must not
eat the first map click).

## Diff

- `LivingTitleBoot`: `button_down` + pointer `_on_begin_new` arm the swallow
  only while `os_left_button_held()`; `_on_begin_new` no-ops if already
  `_closed`.
- `MapRenderer`: TipDismiss-style `eoa_begin_swallow_release` on leftover
  `_input` / `_unhandled_input` / land-chip still-click / Area2D release.
  Stores arm time (`Time.get_ticks_msec`) + arm frame. Expires after 750 ms.
  A new left press in a later frame than the arming clears the flag.
- Guard `HeadlessBegin1TitleReleaseFallthroughTest` + `tools/eoa_begin1_guard.sh`
  drives real `InputEventMouseButton` through `_input` / `_unhandled_input`
  (no emit / `_select_province` fallback). 80 ms leftover; follow-up pid != -1
  + inspector; lost-release expiry; later-frame press; keyboard Enter/Space.

Camera / edge-pan / TipDismiss / FacilityIconLayer / labels / fleet stack /
unit pick ranking **unedited**.

## Play recipe (human)

`docs/evidence/begin1/CLICKS.md` — 1280×740 Absolute @(0,29) no Ctrl.

Pre-step: `tools/run_godot.sh --headless --import --quit`

1. Title. Germany · 1936. Cursor on **Begin**.
2. Normal click: press, hold **~80–150 ms**, release (not a 0 ms tap).
3. Home must have **no** inspector, **no** unit card, **no** click-zoom.
   Loir-et-Cher under ~**(284, 580)** must stay unselected.
4. A **new** still-click on a GER land chip must still open Fill%/TOE.
5. If the leftover up never arrives (unfocused window): after ~750 ms, or
   after a fresh press, the first map click must pick.

## Gates (tip `1a29087f`)

| gate | kind | result |
|---|---|---|
| `HeadlessBegin1TitleReleaseFallthroughTest` | hd | **PASS** (`eoa_begin1_guard.sh` 1212.6 MB) |
| `HeadlessBegin1TitleReleaseFallthroughTest` | xvfb | **PASS** (`eoa_begin1_guard.sh` 1355.6 MB) |
| `HeadlessFirstSessionReadabilityTest` (TipDismiss) | hd | **PASS** |
| `HeadlessIx1LivingTitleEscBeginTest` | hd | **PASS** |
| `HeadlessFleet1LandSpillGateTest` | hd | **PASS** |
| `HeadlessFleet2SharedSeaMarkerTest` | hd | **PASS** |
| `HeadlessFac1aPanIconsTest` (PERF-1) | hd | **PASS** |
| `HeadlessFac1aHoverCacheTest` (PERF-1b) | hd | **PASS** |
| `HeadlessLabel1NationZoomTest` (LABEL-1) | hd | **PASS** |
| `tools/eoa_full_test_gates.sh --quick` | pure | same **14** `unit_board_play_path` reds as main; no new red. `map_qc` env skip (no Pillow). HOI open_p0=0. |

## Test-merge onto draft PR #83

`origin/cursor/perf2-idle-wheel-refresh-f611` @ `5f459614e00a24919959ccb3673e1274098912da`.

- **`docs/CURRENT_STATE.md`**: content conflict (both prepend a HOLD changelog paragraph).
- `scripts/map/MapRenderer.gd`: **auto-merged**.
- `docs/TESTING_PLAN.md`: **auto-merged**.

Product input path does not conflict with PERF-2 fleet-offset / wheel-refresh.

## Out of scope (follow-up)

Space-as-Begin resuming the clock at 1x is **not** this slice.
