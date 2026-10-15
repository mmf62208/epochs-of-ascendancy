# EDGE-2 Play recipe — 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl.
Headless / xvfb ≠ live Play.

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**.

## What the #105 probe measured

Cursor parked on the right rim: edge-pan started ~0.5 s after the last wheel
notch (WHEELDRIFT-1 hold) then ran at full speed instantly (~2200–2600 screen
px/s, ÷ zoom). Home zoom ~0.33 made world speed ~3×. A resting cursor ran
Europe→Asia in ~3 s. No dwell outside the post-wheel window, no ramp, no
far-zoom cap. Left rim never panned (left HUD hover / 6px strip).

## Product (this slice)

- **250 ms** continuous rim contact before any edge pan starts (wheel 350+150 stay).
- Speed ramps 0→full over **~600 ms** of contact after dwell; leave-rim resets.
- Below Home zoom **0.33**, world speed does not scale by 1/zoom past Home.
- Left HUD (MapModeToolbar / legend / InfoPanel / minimap) is exempt **only**
  in the UI-1 6px left strip. Toasts / unit cards / Leaders still block.
- Strip sizes unchanged: 6 px L/T/B, 10 px right (EDGE-1).

## Path (no Ctrl)

1. Begin GER 1936. Tip × if shown. Pause.
2. Park the cursor on the **right** rim (x≈1270–1279, y=370). Do not wheel.
   Camera must sit still for ~250 ms, then ease up to full over ~0.6 s more.
3. Wheel-out past Home (z < 0.33) and park on the right rim again. After the
   ramp, world speed must not feel ~3× Home (Europe→Asia in 3 s).
4. Park on the **left** rim (x=2–4, y=370) over the map-mode toolbar / legend /
   inspector dock. After the dwell, the camera must pan west.

## Machine

```bash
tools/run_godot.sh --headless --path . --resolution 1280x740 \
  -s res://scripts/core/HeadlessEdge2RimFeelTest.gd
tools/eoa_edge2_guard.sh
```

Must **FAIL** on b7affe58 (WHEELDRIFT-1 tip) and **PASS** on this tip.

Draft until Ship squash-merges. Never claim live Play PASS from this harness.
