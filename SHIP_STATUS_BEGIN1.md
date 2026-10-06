# BEGIN-1 — Begin leftover release must not click the map

Updated: 2026-10-06
From: Cloud Agent
**Status:** draft PR · **merge HOLD**

| | |
|---|---|
| **Base** | main `425b4448c7bec8b7f8d5602193b8e8466d1e5ec2` (LABEL-1) |
| **Branch** | `cursor/begin1-title-release-swallow-d55e` |
| **Tip** | *(pending first push)* |
| **PR** | *(pending)* |
| Verdict | isolated keep-green pending. xvfb ≠ live Play. Merge **HOLD**. |

## Proven cause

Begin is `ACTION_MODE_BUTTON_PRESS`. `_on_begin_new` → `_finish` sets `_closed`
and `queue_free()`. `_living_title_boot_is_up()` is then false (closed **or**
queued). MapRenderer `_input` / `_unhandled_input` leftover left-release does
not require a matching map press, so a real ~80–150 ms mouse-up still-clicks
the hex under the cursor after Home (Loir-et-Cher at ~284,580 / 1280×740):
inspector + `_center_camera_on_province(..., "soft")` 0.776→0.900.

Instant 0 ms press+release stays on the still-alive Begin Control for that
frame, so GUI eats the up and the race stays hidden.

## Diff

- `LivingTitleBoot`: `button_down` + pointer `_on_begin_new` arm the swallow;
  `_on_begin_new` no-ops if already `_closed` (double apply).
- `MapRenderer`: TipDismiss-style `eoa_begin_swallow_release` on leftover
  `_input` / `_unhandled_input` / land-chip still-click / Area2D release.
  One-shot; next map click is not swallowed. Keyboard Begin does not arm.
- Guard `HeadlessBegin1TitleReleaseFallthroughTest` + `tools/eoa_begin1_guard.sh`.

Camera / edge-pan / TipDismiss / FacilityIconLayer / labels / fleet stack /
unit pick ranking **unedited**.

## Play recipe

`docs/evidence/begin1/CLICKS.md` — 1280×740 Absolute @(0,29) no Ctrl.
Normal-length Begin click. Home must stay uninspected / un-zoomed. Then a
new GER chip click must still open.

## Gates

Pending this tip. `--quick` expected: same 14 known `unit_board_play_path`
reds as main. No new reds.
