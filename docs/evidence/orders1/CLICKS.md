# ORDERS-1 Play recipe (exact clicks)

1280×740 or 1680×960 · GER 1936 · `world_accurate` · **NOT** live-Play PASS from this harness.

**Halt vs Assign:** Halt and Assign share the bottom-left command row.
Halt is the **left** button (`Halt march`). Assign is **6 px to its right**
on the same row. On Play ~1680×960 the Halt center is about **(97, 731)**.
A click a few pixels right of Halt hits Assign (leader), not Halt.

## Halt

1. F5 / TestScenario. Living title → **Begin** (GER 1936). Do not use Esc to start.
2. Europe Home if the camera is not on Germany.
3. Click a **GER land chip** (Division / Garrison plate+label). Not an Air Wing.
   Empty land outside the hit disk must not open a distant card (PR #73).
4. With the unit card up, click **own adjacent land** (plain left click) to March.
   Amber `MarchPathLine` + card shows **Halt march**.
5. Click **Halt march** (left command button). Do **not** click Assign.
   Expect: Halt gone, path gone, unit still on the current hex, toast
   `March halted · …`.

## Hold

6. Select the same (or another) GER land unit.
7. **Ctrl+click** adjacent enemy land (Maginot FRA) so an open fight starts
   (not empty-hex instant). Card shows Fight + **Press ●** / **Hold**.
8. Click **Hold** (stance row, not Halt).
   Expect: button becomes **Hold ●**, Press loses the dot, fight bubble
   may read `HOLD`.

## Withdraw

9. Same fighting card. Click **Withdraw** (command row, left of Assign).
   Expect: body line **Withdrawing · bounce tomorrow**, button **Withdraw ●**,
   toast `Withdrawing · bounce tomorrow`, bubble ` WD`.
   Same-day does not instantly delete the fight; next day bounces.

Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.
