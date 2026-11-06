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
