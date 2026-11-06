# STARTUP-BLANK evidence

Windowed pointer-Begin vs Enter-Begin. Not live Play. MERGE: HOLD.

Extends the merged STARTUP-PARITY harness (`WindowedStartupParityTest.gd`, `tools/eoa_startup_parity.sh`). `tools/eoa_startup_blank.sh` is a thin env wrapper — it does not duplicate inventory / garrison / seed / xvfb.

## Run

```bash
EOA_STARTUP_BLANK_OUT=/tmp/eoa-startup-blank tools/eoa_startup_blank.sh
# or:
EOA_STARTUP_BLANK=1 EOA_STARTUP_PARITY_OUT=/tmp/eoa-startup-blank tools/eoa_startup_parity.sh
```

Xvfb 1920×1200 + xfwm4. Launch `--resolution 1280x800 --position 0,0 --maximized`, then harness un-maximizes to 1280×800 (`window` + `root.size`). Godot via `tools/run_godot.sh`. Isolated `XDG_*`.

## Variants

| name | Begin | mutant | want |
|------|-------|--------|------|
| pointer | synthetic mouse press on LivingTitleBegin, leftover release | off | map populated, Berlin in view |
| enter | KEY_ENTER, mouse parked interior | off | same |
| mutant_pointer | pointer | `EOA_STARTUP_BLANK_MUTANT=1` | pointer FAIL |

Logs: `EOA_STARTUP_BLANK who=` camera/viewport numbers at `_finish`, after `_center_on_player`, first `size_changed`, first post-Begin pointer, and each camera move.

## Mechanism (pointer leftover on un-max bottom rim)

Pre-fix excerpt: `pointer_rim_pre_fix.log.txt`.

- Launch maximized 1920×1176; Begin press `(268, 819)`; AOT-clear un-maximizes to 1280×800.
- `root_size_changed` **dcam=0.00** dzoom=0, `berlin_in_view=true` — resize is not the throw.
- Leftover parked at `(268, 797)` (live leftover y=800 on the 800-tall window).
- `camera_moved` n=1 `reason=left_drag` dcam=30.69; n=2+ `edge=(0, 1)` with EDGE-2 ramp. Cam y **1525.72 → 8412.90** (theater clamp). `berlin_in_view=false` by n=11. Soak mesh_in_view=1.
- Product fix: swallow leftover pointer (edge pan + leftover left-drag) after Begin until the cursor moves ≥6 px from the post-settle leftover. Recenter-on-size_changed is unused (would be a no-op). Mutant `EOA_STARTUP_BLANK_MUTANT=1` disables the swallow.

## Results (xvfb+xfwm4, not live Play)

| run | soak | STARTUP_BLANK | camera | mesh_in_view |
|-----|------|---------------|--------|--------------|
| pointer + leftover on rim, swallow on | 120 s | PASS | (7601.51, 1525.72) z=0.8602 Berlin in view | 1188 |
| enter, mouse interior (640,400) | 25 s then 120 s | PASS | same, no `camera_moved` | 1188 |
| pointer mutant (`EOA_STARTUP_BLANK_MUTANT=1`) | 25 s | FAIL (killed) | y 1525.72 → 8412.90, Berlin out | 1 |

Seed md5 `20fe9063de285f19d4f9b8a105abfd31`. Empty-board garrisons 575. Live identity 535+40=575. Provinces 3596. map_qc NE **0.9853**. Godot 4.7.1.stable.official.a13da4feb via `tools/run_godot.sh`.
