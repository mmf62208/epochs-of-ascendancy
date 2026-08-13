---
name: eoa-full-test
description: >
  Epochs of Ascendancy (EOA) full-test constraints and gate commands for the
  Godot grand-strategy default board. Use when building EOA, working on map,
  densify, WarLoop/Fronts, supply, save/Command Center, HOI gaps, world_accurate,
  dual board, or when the user runs /eoa-full-test or /eoa-gates. Prefer pure
  products + headless Godot gates; never renumber world_full IDs.
---

# EOA full-test skill

You are helping build **Epochs of Ascendancy** — Godot **4.7.1** grand strategy.
Default play path is **`world_accurate`**, not scaffold.

## Source of truth (read before inventing work)

| Doc | Role |
|-----|------|
| `docs/GAME_STATUS_SNAPSHOT.md` | What is true now (~3520 board, map machine closed) |
| `docs/HOI4_EOA_GAP_REVIEW.md` | HOI pillars · **open P0 = 0** · PARTIAL/DEFER |
| `docs/WORLD_CLASS_MAP_REVIEW.md` | Map-as-living-star inventory |
| `docs/PLAYTEST_AND_DECISION_GUIDE.md` | Human checklist (scale must stay ~3520) |
| `docs/GAME_DIRECTOR_PLAN.md` | Phases / agents |

## Hard constraints (never violate)

1. **Default board:** `data/provinces_world_accurate/` · **~3520** provinces (land ~3180 + sea 340).
2. **Dual board:** `EOA_SCENARIO=world_full` scaffold (~2665) exists for duals only.
3. **Never renumber `world_full` province IDs** in place.
4. Prefer **pure products** under `tools/map_generation/lib/` + **headless harnesses** over residual dual-package spam.
5. Board writes (densify/merge): **backup → remap → adjacency rebuild → protect capitals**; reuse US/RoW merge scripts.
6. **M6** human 20d/60d narrative notes are **human-only** — not an automated gate.
7. Soft **30fps** may **FAIL honestly** on map-tick proxy — do not invent PASS.
8. Non-goals for full-test: museum borders, 13k provinces, multiplayer product, full V3 markets/pops, commercial HOI designer parity.

## Dual ID blocks (world_accurate)

| Block | IDs | Notes |
|-------|-----|-------|
| Europe NUTS | 710000+ | Dense theater (~1514) |
| US playable | 800000+ | ~130 (post county merge) |
| RoW | 900000–949999 | Post sparse merge (~1536) |
| Seas | 950000+ | ~340 |

## Gate commands (run from repo root)

### One-shot (preferred)

```bash
# Pure + Godot headless pick/assault
tools/eoa_full_test_gates.sh

# Pure only (no Godot binary needed)
tools/eoa_full_test_gates.sh --quick

# Full + optional perf sample (soft 30fps FAIL OK)
tools/eoa_full_test_gates.sh --with-perf --log /tmp/eoa-gates-logs
```

### Manual suites (if debugging a step)

```bash
python3 -m unittest tools.map_generation.tests.test_world_accurate_board -v
python3 -m unittest tools.map_generation.tests.test_hoi_full_test_gap_matrix_product -v
python3 tools/map_generation/scripts/map_accuracy_qc.py \
  --dir data/provinces_world_accurate --min-land-hit 0.90
tools/run_godot.sh --headless --path . -s res://tools/map_manager_pick_harness_accurate.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMultiFrontAssaultTest.gd
```

Godot: always use **`tools/run_godot.sh`** (resolves 4.7.1 under `~/Applications`).

## First-session play surfaces (must stay green)

| Surface | Control | Product / API |
|---------|---------|----------------|
| Capitals | Click / pick harness | `world_accurate_capital_pick_product` |
| Fronts | **B** / toolbar Fronts | `map_live_border_fronts_surface_product` |
| WarLoop | **Shift+I** / toolbar | `map_war_path_surface_product` |
| Supply corridor | **G** | `map_supply_corridor_product` |
| Resources / states / terrain | F9 / Shift+F9 / Ctrl+F9 | mapmode products |
| Save | Menu / Command Center | `save_resume_*` · `SaveLoadManager` · MainMenu CC |

## Workflow when building features

1. Read SNAPSHOT + HOI gap review if touching map/war/save.
2. Implement pure product (or extend existing) under `tools/map_generation/lib/`.
3. Add/adjust unit test under `tools/map_generation/tests/` that calls the **real** builder.
4. Run `tools/eoa_full_test_gates.sh --quick` while iterating; full script before claiming done.
5. After non-trivial work, prefer `/check-work` with focus on the gate set.
6. Update SNAPSHOT only when truth changes (scale, landed items, honest FPS).

## Map densify / merge

- US: `merge_us_counties_to_state_provinces.py` (done).
- RoW sparse: `merge_row_sparse_to_playable.py` (done; product `row_sparse_density_product`).
- Do **not** re-open densify unless integrity fails or human reports density spam (e.g. SE Asia optional).

## HOI gap policy

- Machine **open P0 = 0** (see `hoi_full_test_gap_matrix_product`).
- PARTIAL depth (designer, deep supply hubs) is post full-test — do not invent filler duals.
- Closing a real regression: fix shipped path + test that fails if broken again.

## Graphical play (human)

```bash
tools/run_godot.sh --path . res://scenes/TestScenario.tscn
```

Default scenario is world_accurate via TestRunner; scaffold dual: `EOA_SCENARIO=world_full`.
