---
name: eoa-living-units
description: >
  EOA HOI-style living map units: selectable counters with org/strength that
  take march and assault orders. Use when building or QA-ing units, chips,
  NATO counters, Maginot 710173, pick→march→Ctrl+click assault, or when the
  user says units are missing / unselectable. Slash: /eoa-living-units.
---

# EOA living units

Human playtest is **not** the unit-quality gate. Prove the loop in machine
code before asking anyone to F5.

## Ready means all of these

1. GER land stationed on Maginot **`710173`** (FRA defender **`710739`**).
2. A `DemoUnitIcon` on that hex with **org bar, str bar, and str %**.
3. Pin-first pick (`_try_open_unit_at_world` before hex).
4. Click own land → `FormationMovement.enqueue_own_land_march`.
5. Ctrl+click enemy → `BattleManager.start_land_battle` (not `execute` on the click).
6. Headless harness **RESULT=PASS**. Grep products alone are not ready.

## Commands

```bash
# Wiring (on official --quick)
python3 -m unittest tools.map_generation.tests.test_living_unit_order_loop_product -v

# Live F5 path (no window)
EOA_UNIT_ORDER_QA=1 tools/run_godot.sh --headless --path . \
  res://scenes/TestScenario.tscn --quit-after 180

# Autoload API (no full scene)
tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessWorldAccurateUnitOrderLoopTest.gd
```

Godot only via `tools/run_godot.sh`. Board `world_accurate` ~3520. Never
renumber `world_full` IDs.

## Hang-class (do not regress)

- No 3520 BFS / `preview_player_route` / `find_land_path` on **G** or **L**.
- No `ClassName.has_method()` on RefCounted `class_name` (Godot 4.7.1 parse).
- No full inspector / full-board icon rebuild on pick or assault click.

## Product

`living_unit_order_loop_product` greps the shipped path. Keep it AND-ed with
the headless RESULT line. Do not claim HOI quality from greps.
