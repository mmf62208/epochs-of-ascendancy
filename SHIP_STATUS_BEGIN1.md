# BEGIN-1 — Begin leftover release must not click the map

Updated: 2026-10-06
From: Cloud Agent
**Status:** draft PR · **merge HOLD**

| | |
|---|---|
| **Base** | main `425b4448c7bec8b7f8d5602193b8e8466d1e5ec2` (LABEL-1) |
| **Branch** | `cursor/begin1-title-release-swallow-d55e` |
| **Tip** | `09a40c1c86ed6635592a2e3cbae916de191fe8f0` |
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

## Diff

- `LivingTitleBoot`: `button_down` + pointer `_on_begin_new` arm the swallow;
  `_on_begin_new` no-ops if already `_closed` (double apply — one start-date
  log per click on this tip).
- `MapRenderer`: TipDismiss-style `eoa_begin_swallow_release` on leftover
  `_input` / `_unhandled_input` / land-chip still-click / Area2D release.
  One-shot; next map click is not swallowed. Keyboard Begin does not arm.
- Guard `HeadlessBegin1TitleReleaseFallthroughTest` + `tools/eoa_begin1_guard.sh`.

Camera / edge-pan / TipDismiss / FacilityIconLayer / labels / fleet stack /
unit pick ranking **unedited**.

## Play recipe (human)

`docs/evidence/begin1/CLICKS.md` — 1280×740 Absolute @(0,29) no Ctrl.

1. Title. Germany · 1936. Cursor on **Begin**.
2. Normal click: press, hold **~80–150 ms**, release (not a 0 ms tap).
3. Home must have **no** inspector, **no** unit card, **no** click-zoom.
   Loir-et-Cher under ~**(284, 580)** must stay unselected.
4. A **new** still-click on a GER land chip must still open Fill%/TOE.

## Gates

| gate | kind | result |
|---|---|---|
| `HeadlessBegin1TitleReleaseFallthroughTest` | hd | **PASS** |
| `HeadlessBegin1TitleReleaseFallthroughTest` | xvfb | **PASS** |
| `HeadlessFirstSessionReadabilityTest` (TipDismiss) | hd | **PASS** |
| `HeadlessIx1LivingTitleEscBeginTest` | hd | **PASS** |
| `HeadlessFleet1LandSpillGateTest` | hd | **PASS** |
| `HeadlessFleet2SharedSeaMarkerTest` | hd | **PASS** |
| `HeadlessFac1aPanIconsTest` (PERF-1) | hd | **PASS** |
| `HeadlessFac1aHoverCacheTest` (PERF-1b) | hd | **PASS** |
| `HeadlessLabel1NationZoomTest` (LABEL-1) | hd | **PASS** |
| `tools/eoa_full_test_gates.sh --quick` | pure | `unit_board_play_path` **FAIL 14** — same known unit_pick / chrome / fill-toe / living_unit greps as main. **No new reds.** `map_qc` env-skipped here (no Pillow/venv). HOI matrix **PASS** (open P0=0). `unit_save_path` **OK**. |

## Test-merge onto draft PR #83

`origin/cursor/perf2-idle-wheel-refresh-f611` @ `b2674c6c` (already includes main `425b4448`).

- **`docs/CURRENT_STATE.md`**: content conflict (both prepend a HOLD changelog paragraph).
- `scripts/map/MapRenderer.gd`: **auto-merged**.
- `docs/TESTING_PLAN.md`: **auto-merged**.

Reverse (BEGIN-1 ← #83): same docs-only `CURRENT_STATE.md` conflict. Product input path does not conflict with PERF-2 fleet-offset / wheel-refresh.
