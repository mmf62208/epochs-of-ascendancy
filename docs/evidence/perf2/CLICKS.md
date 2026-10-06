# PERF-2 live recipe — first-session idle hitch + wheel cost

Window **1280×740**. Begin → **Germany** → **1936**. Headless / xvfb ≠ live Play.
Do **not** change TipDismiss / ORDERS / camera / edge-pan. Measure frame gaps
and wheel-notch cost; plate positions and capital stars must look unchanged.

## Idle running-clock hitch (was every ~6th frame ~150–230 ms)

1. Begin GER 1936. Tip × if shown.
2. Press **Home**. Confirm Europe framing (~z 0.32).
3. Wheel in to about **z 0.9** (or sit at Home — hitch was also visible at z~0.9).
4. **Unpause at 1x**. Do not pan, click, or wheel. Sit **15 s**.
5. Log frame gaps (same method as the Ship triage: timestamp successive
   `EOA_ZOOM` / process frames, or a 1-second wall-clock frame counter).
6. Expect: no regular ~150–230 ms hitch on the idle 6th-frame detail refresh.
   Normal software-GL frames stay in the ~45 ms band; the every-6th refresh
   should sit near that, not 3–5×.

## Wheel ladder from Home (paused)

1. **Pause**. Home. Note zoom (Play Home is often **0.318**).
2. Four **wheel-in** notches toward the mouse. Log zoom + wall time per notch.
3. Prior main `d008ca42` (paused): `0.318→0.396` ~500 ms, `0.492→0.612` ~1 s,
   `0.612→0.760` ~900 + ~750 ms.
4. Expect each notch **clearly cheaper** than those (one light refresh, not two;
   capital-star font override skipped when px is unchanged).
5. After a short burst, one extra light refresh may land ~180 ms later
   (debounced post-burst). That is intended.

## Capital stars after map-mode / supply (FIX #1)

1. **Home** (or world, z ≤ 0.55). Switch map mode (F1 / F2 / toolbar).
   Expect: capital stars **stay hidden** (nation labels own that band). They
   stay hidden through two more same-px wheel notches and after Home again.
   Prior tip `b2674c6c` showed all 37 stars and they stuck.
2. At operational zoom (star px = 20), toggle the **supply overlay**, then
   one same-px wheel notch.
   Expect: stars return to **20 px** (not stuck at the glyph-pass 36 px).

## Must keep (visible)

- Channel 4-plate and North Sea 4-plate **positions** (Home spread + compact
  0.8 / 1.5 / 2.3) look the same as FLEET-2.
- Land counter scales and capital stars look the same.
- `EOA_FLEET2 who=plate_label` prints **only when a label changes**, not 8
  lines every refresh.
- Map-mode switch at Home means stars stay hidden; supply overlay toggle
  plus one notch means stars are back to 20 px.

## Must not change

FacilityIconLayer, country/political labels, MapZoomLOD, pick ranking /
draw-order / hit-test / spill, TipDismiss, ORDERS, camera, edge-pan,
MapRenderer fill-line area owned by PR #80.
