# EDGE-1 — first-session camera feel (edge-pan)

Updated: 2026-10-05
From: Ship / CA
**Status:** draft PR · **merge HOLD**

| | |
|---|---|
| **Base** | TRUSTED main `251d26280bdc186c9db7cedf74ef98b6c051c5f5` (COMBAT-1) |
| **Branch** | `cursor/edge1-camera-feel-3a71` |
| **Tip** | see git after keep-green commit |
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/79 |
| Verdict | isolated keep-green **PASS**. xvfb ≠ live Play. Merge **HOLD**. |

## Proven cause

6px right strip starts at **x=1274** on 1280×740. Play hover **x=1270**
(and corner **(1270, 1)** east) returned ZERO / north-only. Left/top/bottom
already fired. Fix: `EDGE_PAN_RIGHT_SCREEN_PX = 10` in existing
`MapViewInput.edge_pan_direction_at`. Other rims stay 6px.

Toast-before-drag and large-drag-south were **hunches** — not reproduced
(toast still blocks; drag activate reseeds `_last_mouse_pos`).

## Keep

CLOSE-1/1b Close-held suppress. UI-1 top-edge under TopInfoBar. Home framing
unedited. TipDismiss / ORDERS layout / chip hit-rank unedited.

## Play recipe

`docs/evidence/edge1/CLICKS.md` — 1280×740 Absolute @(0,29) no Ctrl.
Begin GER → Tip × ≈(1029, 114). Hover left (3,370), right (1270,370),
top (640,1), bottom (640,737), corner (1270,1). Close-held on north strip
must not pan.
