# SHIP STATUS — FIX1 RX-1 visibility (PR 57)

**HOLD for Play. Do not merge. Same draft PR 57.**

| | |
|--|--|
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/57 (draft) |
| **Branch** | `cursor/rx1-rhine-crossing-e117` |
| **Base Play fail** | `9750f3d3` (Rhine under unit counters; Neuss spine overlap; stale class cache) |
| **Tip** | see git on the PR after this commit |

## Fixes

1. **Rhine above units:** `Rx1RhineLayer.ABOVE_UNIT_COUNTERS_Z = 36` (`z_as_relative=false`) vs DemoUnitIcon **28**. Halo + brighter stroke. `_draw` only — no rebuild on zoom.
2. **IX-1 roads above units:** `InfrastructureOverlayLayer.ROAD_ABOVE_UNIT_COUNTERS_Z = 32`, spine preview **33**.
3. **Neuss panel:** `_hide_ix1_spine_inspector_chrome` when `inspector_should_show_spine_status` is false. Spine chrome only on Bonn **710416** / Köln **710417** / Leverkusen **710418**. Rhine chrome stacks on its own row (y=66 / 94 when spine is hidden).
4. **Fresh checkout:** `tools/run_godot.sh` one-time `--headless --import` when `.godot/global_script_class_cache.cfg` is missing or lacks `Rx1RhineCrossing`. Autoloads GameData / MapManager / IDM **preload** `res://scripts/map/Rx1RhineCrossing.gd`.

## Later (logged, not this slice)

Move ETA preview UI — none exists today; inspector hop × / attack −% stays the living copy.

## Guards

| Guard | on `9750f3d` | on tip |
|-------|----------------|--------|
| `test_visibility_order_above_unit_counters` | **FAIL** | must **PASS** |
| `test_fresh_checkout_launch_imports_class_cache` | **FAIL** | must **PASS** |
| `HeadlessRx1RhineVisibilityTest` | **FAIL** (z=7 / no helpers) | must **PASS** |
| existing RX-1 / IX-1 headless + py | stay green | stay green |

Smoke harness is **not** the product.
