# LABEL-1 live recipe (HOLD merge)

Headless / xvfb ≠ live Play. Never `EOA_SKIP_TITLE`.

## What this slice changes

Country names (`PoliticalLabelsLayer` / `NationLabel_*`) at first-session
Europe → mid wheel-in. Font size follows Camera2D.zoom so the raster is not
magnified. `Label.scale` stays identity. The layer recomputes its own visible
box from the live MapCamera while paused (Home / Far-East pan). Fade 0.82–0.98
holds mid on-screen size and fades `modulate.a` (outline included). City
end-labels (Bonn / Köln / Leverkusen) and unit counters are untouched.

## Human Play (product window)

1. `tools/run_godot.sh --path . res://scenes/TestScenario.tscn`
2. **Begin** → **Germany** → **1936**.
3. Press **Home** (Europe frame: Berlin+Paris+Rome).
4. **Pause** (first-session clock is often already paused). Confirm country names still cover Europe (not a handful left over from the last unpaused cull box).
5. While still **paused**, pan toward the Far East (or wheel out). Names must follow the live camera — Japan / China / neighbors appear; Europe names drop off-screen. Unpause is not required for this.
6. Return **Home**. Wheel **in** one or two notches to mid (~`0.776` on the Home camera).
7. Wheel **in** through the fade band (~`0.82`–`0.98`). Names stay mid-size (or larger) and fade via alpha, including the outline — they must not shrink to 9–10 px while staying dark-outlined.
8. Wheel **in** further to close (Rhineland / Köln).
9. Wheel **out** back to Home.

## What to look for

| Zoom | Country names | Cities (Köln / Bonn / Leverkusen) | Counters |
|---|---|---|---|
| Europe / Home (paused) | Crisp, modest; **many** names over Europe after Home, even while paused | Off | Painted |
| Paused Far-East pan | Names follow the live camera (>0 over Asia) | Off | Painted |
| Mid ~0.776 | Still crisp and **smaller or equal** vs Home, full opacity | Off (floor 1.50) | Painted |
| Fade 0.82–0.98 | Mid-size or larger; **fade alpha** (outline too), not 9–10 px dark text | Off | Painted |
| Close / Rhineland | **Gone** (hide by 0.98) so they cannot cover cities or chips | On, no overlap | On top (z 28) |

Fail if Home-then-pause shows only a handful of names, if a paused pan to Asia
shows none until unpause, if "Germany" / "Netherlands" looks like a blown-up
bitmap at mid, if fade-band names shrink to faint 9–10 px, or if Köln / Bonn /
Leverkusen vanish at close/mid 1.50+.

## Machine

```bash
python3 -m unittest tools.map_generation.tests.test_map_nation_label_landmass_product -v
tools/run_godot.sh --headless --path . --resolution 1280x720 \
  -s res://scripts/core/HeadlessLabel1NationZoomTest.gd
tools/eoa_label1_guard.sh
tools/eoa_full_test_gates.sh --quick
```
