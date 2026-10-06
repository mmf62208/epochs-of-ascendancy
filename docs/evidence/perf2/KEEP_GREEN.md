# PERF-2 isolated keep-green

Off trusted main `d008ca42094bcb6df58872d0bd421f08a87c76b0` (EDGE-1 #79).
xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only
(Godot 4.7.1). HOLD merge.

Fences kept: FacilityIconLayer **unedited**. MapZoomLOD / country labels
**unedited**. Pick / draw-order / hit-test / spill **unedited**. TipDismiss /
ORDERS / camera / edge-pan **unedited**.

Official `--quick` `unit_board_play_path` still has the **14 known reds** on
main (living-unit product greps). Report any *new* ones only.
