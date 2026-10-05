# PERF-1b human tester recipe (HOLD merge)

xvfb / headless ≠ live Play. Confirm on product Play.

1. `tools/run_godot.sh --path .` → **Begin GER 1936**.
2. **Home**. Zoom should read ~0.776 (Europe Home).
3. Move the mouse around the map **without** holding a button (hover only).
4. Then edge-pan (far-right ~x=1270 or any rim).
5. **Expect:** no 0.7–1.2 s hitch on the first mouse move or first pan start.
   Steady pan stays in the ~24 ms band from PERF-1.
6. Click the Rhineland airfields (same seeds):
   - Borken `710430` L1
   - Warendorf `710434` L2
   - Oberbergischer Kreis `710423` L3
   - Siegen-Wittgenstein `710451` L4
7. **Expect:** the clicked airfield still opens (same pid as before this slice).
   Wheel-zoom then click again — still the icon under the cursor.

Do not merge. PR #80 stays draft / owner KEEP pick.
