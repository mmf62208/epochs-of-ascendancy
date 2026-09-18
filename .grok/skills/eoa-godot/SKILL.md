---
name: eoa-godot
description: >
  Godot 4.7.1 launch and hang-class rules for Epochs of Ascendancy. Use when
  writing GDScript, launching F5/headless, debugging grey map, SCRIPT ERROR,
  ClassDB clashes, 3520 freezes, or when the user mentions run_godot,
  has_method, Control Labels on chips, or F5 hang.
---

# EOA Godot 4.7.1

Always launch via **`tools/run_godot.sh`** (resolves 4.7.1). Never a bare `godot`.

Graphical: `tools/run_godot.sh --path . res://scenes/TestScenario.tscn`  
Headless scripts: `tools/run_godot.sh --headless --path . -s res://scripts/core/<Harness>.gd`

## Parse / ClassDB (grey map)

- Do **not** add `class_name` that matches an autoload singleton (`GameData`, `BattleManager`, `MapManager`, …).
- Do **not** call `ClassName.has_method()` on a `RefCounted` `class_name` — Godot 4.7.1 parse failure. Call the method on the instance (`FormationMovement.enqueue_own_land_march`).

## Hang-class (3520 board)

- No full-board BFS / `preview_player_route` / `find_land_path` on **G** or **L**.
- No full inspector / `_update_unit_icons_for_test` / full fill rebuild on pick or assault click.
- Chip text is **Node2D**, not Control Labels (hundreds of Labels freeze F5).
- Pin-first pick when chips are visible. `can_assault` uses cheap `land_combat_power`, not CombatResolver.
- Click / AI initiator uses `BattleManager.start_land_battle`, never `execute_province_assault`.
- F5 day flush is split: `day_emit` / `day_ai` / `day_battles`. RSS tripwire ~2.5 GB.

Default board `world_accurate` ~3520. Dual only `EOA_SCENARIO=world_full`. Never renumber `world_full` IDs.

Details: `docs/GAME_STATUS_SNAPSHOT.md` · `.grok/skills/eoa-living-units/SKILL.md`.
