# SHIP STATUS — FIX1 RX-1 visibility (PR 57)

**HOLD for Play. Do not merge. Same draft PR 57.**

| | |
|--|--|
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/57 (draft) |
| **Branch** | `cursor/rx1-rhine-crossing-e117` |
| **Base Play fail** | `9750f3d3` (Rhine under unit counters; Neuss spine overlap; stale class cache) |
| **Tip** | `431c30e92a0a55d93cc8ecc03d78011c9c03c3e9` |

## Fixes

1. **Rhine above units:** `Rx1RhineLayer.ABOVE_UNIT_COUNTERS_Z = 36` (`z_as_relative=false`) vs DemoUnitIcon **28**. Halo + brighter stroke. `_draw` only — no rebuild on zoom.
2. **IX-1 roads above units:** `InfrastructureOverlayLayer.ROAD_ABOVE_UNIT_COUNTERS_Z = 32`, spine preview **33**.
3. **Neuss panel:** `_hide_ix1_spine_inspector_chrome` when `inspector_should_show_spine_status` is false. Spine chrome only on Bonn **710416** / Köln **710417** / Leverkusen **710418**. Rhine chrome stacks on its own row (y=66 / 94 when spine is hidden).
4. **Fresh checkout:** `tools/run_godot.sh` one-time `--headless --import` when `.godot/global_script_class_cache.cfg` is missing or lacks `Rx1RhineCrossing`. Autoloads GameData / MapManager / IDM **preload** `res://scripts/map/Rx1RhineCrossing.gd`.

## Later (logged, not this slice)

Move ETA preview UI — none exists today; inspector hop × / attack −% stays the living copy.

## Guards

| Guard | on `9750f3d` | on tip `431c30e9` |
|-------|----------------|--------|
| `test_visibility_order_above_unit_counters` | **FAIL** (z=-1 / no helpers) | **PASS** |
| `test_fresh_checkout_launch_imports_class_cache` | **FAIL** (no import gate / no preload) | **PASS** |
| `test_product` (visibility + fresh extras) | **FAIL** shipped_apis / visibility_order / fresh_checkout | **PASS** 7/7 RX-1 |
| `HeadlessRx1RhineVisibilityTest` | **RESULT=FAIL** (3) | **RESULT=PASS** |
| `HeadlessRx1RhineCrossingTest` | n/a (already green) | **RESULT=PASS** |
| `HeadlessRx1RhineLiveStayAliveTickTest` | n/a | **RESULT=PASS** |
| `HeadlessIx1RoadSpineLiveStayAliveTickTest` | n/a | **RESULT=PASS** |
| `test_ix1_road_spine_product` | n/a | **PASS** 15/15 |

Smoke harness is **not** the product.
