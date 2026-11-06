# STARTUP-BLANK evidence

Windowed pointer-Begin vs Enter-Begin. Not live Play. MERGE: HOLD.

Extends the merged STARTUP-PARITY harness (`WindowedStartupParityTest.gd`, `tools/eoa_startup_parity.sh`). `tools/eoa_startup_blank.sh` is a thin env wrapper — it does not duplicate inventory / garrison / seed / xvfb.

## Run

```bash
EOA_STARTUP_BLANK_OUT=/tmp/eoa-startup-blank tools/eoa_startup_blank.sh
# or:
EOA_STARTUP_BLANK=1 EOA_STARTUP_PARITY_OUT=/tmp/eoa-startup-blank tools/eoa_startup_parity.sh
# drag A/B (left-drag pan after Begin):
EOA_STARTUP_BLANK_ONLY=drag_move tools/eoa_startup_blank.sh
EOA_STARTUP_BLANK_ONLY=drag_nomove tools/eoa_startup_blank.sh
```

Xvfb 1920×1200 + xfwm4. Launch `--resolution 1280x800 --position 0,0 --maximized`, then harness un-maximizes to 1280×800 (`window` + `root.size`). Godot via `tools/run_godot.sh`. Isolated `XDG_*`.

## Variants

| name | Begin | mutant | want |
|------|-------|--------|------|
| pointer | synthetic mouse press on LivingTitleBegin, leftover release | off | map populated, Berlin in view |
| enter | KEY_ENTER, mouse parked interior | off | same |
| mutant_pointer | pointer | harness sets MapRenderer meta `eoa_startup_blank_mutant` | pointer FAIL |
| drag_move | pointer, warp ≥6px to interior, then left-drag 100px | off | `DRAG_AB` logged |
| drag_nomove | pointer, left-drag 100px from leftover (no prior move) | off | `DRAG_AB` logged |

Harness/test files may log. Product code has no `EOA_STARTUP_BLANK` prints.

## Mechanism (pointer leftover on un-max bottom rim)

Pre-fix excerpt: `pointer_rim_pre_fix.log.txt`.

- Launch maximized 1920×1176; Begin press `(268, 819)`; AOT-clear un-maximizes to 1280×800.
- `root_size_changed` **dcam=0.00** dzoom=0, `berlin_in_view=true` — resize is not the throw.
- Leftover parked at `(268, 797)` (live leftover y=800 on the 800-tall window).
- `camera_moved` n=1 `reason=left_drag` dcam=30.69; n=2+ `edge=(0, 1)` with EDGE-2 ramp. Cam y **1525.72 → 8412.90** (theater clamp). `berlin_in_view=false` by n=11. Soak mesh_in_view=1.
- Product fix: swallow leftover pointer (edge pan + leftover left-drag) after Begin until the cursor moves ≥6 px from the post-settle leftover. Dead recenter-on-resize path dropped. Mutant is test-only: harness sets MapRenderer meta `eoa_startup_blank_mutant` (env `EOA_STARTUP_BLANK_MUTANT=1`); product does not read the env.

## Pan button (by design)

**Left** (`MOUSE_BUTTON_LEFT`) pans after 8px slop (`LEFT_PAN_SLOP_PX`). That is the leftover-Begin path the swallow gates.

- `scripts/map/MapRenderer.gd:239` `LEFT_PAN_SLOP_PX := 8.0`
- `scripts/map/MapRenderer.gd:1804` `_left_down_is_live_map_drag` polls `Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)`
- `scripts/map/MapRenderer.gd:3398` `_input` `MOUSE_BUTTON_LEFT`
- `scripts/map/MapRenderer.gd:4528–4547` apply: `cam.global_position -= drag_delta * middle_mouse_pan_speed / cam.zoom.x` when `_left_pan_active`

Middle and right also pan immediately via `_is_middle_dragging` (`MapRenderer.gd:3387`). They are not the leftover-Begin button.

## Drag A/B (required before KEEP)

Same harness overlay on main `53f87116` (no swallow) and the cleaned tip (swallow on). 20×5px left-drag, `screen_dx=100`. Raw lines: `drag_ab.log.txt`.

| | tip (swallow) | main `53f87116` |
|--|---------------|-----------------|
| **with ≥6px move first** (interior 640,400) | (7601.51, 1525.72) → (7468.98, 1525.72) **dcam=132.53** Δx=-132.53 Δy=0 | (7082.58, 6909.88) → (6950.05, 6909.88) **dcam=132.53** Δx=-132.53 Δy=0 |
| **no prior move** (leftover rim 268,797) | (7601.51, 1525.72) → (7468.98, 5629.27) **dcam=4105.69** | (7601.51, 7411.71) → (7468.98, 8412.90) **dcam=1009.92** |

KEEP: with prior move, both pans match **dcam=132.53**. Main's `cam_before` is already south because leftover rim edge-panned during settle (no swallow). Without prior move, tip `cam_before` is still Berlin — that is what the swallow suppresses — until the 100px drag itself moves ≥6px and rim edge-pan throws Y.

## Results (xvfb+xfwm4, not live Play)

| run | soak | STARTUP_BLANK | camera | mesh_in_view |
|-----|------|---------------|--------|--------------|
| pointer + leftover on rim, swallow on | 120 s | PASS | (7601.51, 1525.72) z=0.8602 Berlin in view | 1188 |
| enter, mouse interior (640,400) | 25 s then 120 s | PASS | same, no throw | 1188 |
| pointer mutant (test-only meta) | 25 s | FAIL (killed) | y 1525.72 → 8412.90, Berlin out | 1 |
| drag_move (tip, after ≥6px) | — | DRAG_AB | dcam=132.53 (matches main) | — |

Seed md5 `20fe9063de285f19d4f9b8a105abfd31`. Empty-board garrisons 575. Live identity 535+40=575. Provinces 3596. map_qc NE **0.9853**. Godot 4.7.1.stable.official.a13da4feb via `tools/run_godot.sh`.
