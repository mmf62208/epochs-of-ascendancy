# LABEL-1 live recipe (HOLD merge)

Headless / xvfb ≠ live Play. Never `EOA_SKIP_TITLE`.

## What this slice changes

Country names (`PoliticalLabelsLayer` / `NationLabel_*`) at first-session
Europe → mid wheel-in. Font size follows Camera2D.zoom so the raster is not
magnified. `Label.scale` stays identity. City end-labels (Bonn / Köln /
Leverkusen) and unit counters are untouched.

## Human Play (product window)

1. `tools/run_godot.sh --path . res://scenes/TestScenario.tscn`
2. **Begin** → **Germany** → **1936**.
3. Press **Home** (Europe frame: Berlin+Paris+Rome).
4. Wheel **in** one or two notches to mid (~`0.776` on the Home camera).
5. Wheel **in** further to close (Rhineland / Köln).
6. Wheel **out** back to Home.

## What to look for

| Zoom | Country names | Cities (Köln / Bonn / Leverkusen) | Counters |
|---|---|---|---|
| Europe / Home | Crisp, modest (not a continent-sized smear) | Off | Painted |
| Mid ~0.776 | Still crisp and **smaller or equal** vs Home, full opacity | Off (floor 1.50) | Painted |
| Close / Rhineland | **Gone** (fade after 0.82, hide by 0.98) so they cannot cover cities or chips | On, no overlap | On top (z 28) |

Fail if "Germany" / "Netherlands" looks like blown-up bitmap at mid, or if
Köln / Bonn / Leverkusen vanish at close/mid 1.50+.

## Machine

```bash
python3 -m unittest tools.map_generation.tests.test_map_nation_label_landmass_product -v
tools/run_godot.sh --headless --path . --resolution 1280x720 \
  -s res://scripts/core/HeadlessLabel1NationZoomTest.gd
tools/eoa_label1_guard.sh
tools/eoa_full_test_gates.sh --quick
```
