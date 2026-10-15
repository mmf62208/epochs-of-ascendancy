# WHEELDRIFT-1 human tester recipe (HOLD merge)

Headless + xvfb ≠ live Play. Display/input only.

## What Play saw (d4a3a1ff)

- Wheel-only (cursor held still): the point under the cursor stayed put.
- In ×1.243 / out ×0.757 — 5 in + 5 out left the view ~26% further out.
- Edge-pan fired ~3–4 px from right/top/bottom at ~1000 px/s; left never moved (Home clamp / rim). 15 px in did not pan (UI-1 6 px strip, not the dead 64 px export).
- A wheel notch cleared `_close_suppress_edge`, so a cursor on the rim edge-scrolled while zooming.

## Product (this slice)

- Wheel anchors on `event.position`. Zoom min/max is clamped, then the world point is corrected, then theater clamp (no re-anchor).
- In/out are exact inverses (`factor_out = 1 / factor_in`).
- Every wheel notch arms a 350 ms edge hold + 150 ms strip dwell. EDGE-1 6/10 px strips and speed are unchanged.

## Machine

```bash
tools/run_godot.sh --headless --path . --resolution 1280x740 \
  -s res://scripts/core/HeadlessWheelDrift1Test.gd
```

Must **FAIL** on main `61a80433` MapRenderer and **PASS** on this tip.

## Live Play (when a human opens F5)

Window 1280×740, paused, Units off, Search/Go Köln.

1. Cursor mid-map: 5 wheel-in + 5 wheel-out. Zoom returns; Köln stays under the cursor.
2. Cursor 4 px from each rim (no wheel): all four edges pan. Interior 15 px does not.
3. Cursor on the bottom-right rim: 10 wheel notches. The view must not slide to the Adriatic. After ~0.5 s of holding the rim with no further wheel, edge-pan may resume.
