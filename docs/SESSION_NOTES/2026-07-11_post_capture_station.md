# EVIDENCE — post-capture attacker station on captured province

**Date:** 2026-07-11  
**Slice:** After land assault capture, attacker formation `stationed_province_id` equals target province (not still staging/from).

## Baseline gap

- `BattleManager.apply_combat_outcome` already flipped ownership via `MapManager.update_province_owner`.
- It called `FormationMovement.move_formation_to_province` → `SupplyManager.move_formation_to_province`, which requires:
  - SupplyManager `provinces` network (`build_network`)
  - Division template for the formation id
  - Controller match on destination
- Under headless / OOB custom fids, move returned `ok:false` and **station stayed on from_pid** even after owner flip.

## Fix

`BattleManager._station_attacker_on_captured_province`:

1. Best-effort `FormationMovement` / `SupplyManager.move_formation_to_province` (deployments + engineer pipeline when available).
2. **Always** set `LeaderManager.get_formation(fid).stationed_province_id = target_pid` (OOB / combat source of truth).
3. If move failed, sync `SupplyManager.division_deployments[fid]` to target.

Capture path: owner flip → station helper → map refresh.

## Fixture

- Edge: GER **9276** → FRA **9281** (world_full adjacency + 1936 ownership).
- Deterministic: forced `apply_combat_outcome` with `province_control_change=true`.
- Live path: `execute_province_assault` (retry + forced fallback).

## Evidence (headless)

```
HeadlessWorldFullPostCaptureStationTest: PASS (failures=0)
  apply_combat_outcome station 9276→9281 owner=GER
  execute attempt 1 winner=attacker pcc=true station=9281 owner=GER
  reinforce stock 12→10 def_equip=1 station_att=9281

HeadlessWorldFullAssaultCaptureTest: PASS (failures=0)
  capture result ... station=9281 (want 9281)
```

## Tests / CI

| Check | Path |
|-------|------|
| Headless station | `scripts/core/HeadlessWorldFullPostCaptureStationTest.gd` |
| Headless capture (+ station assert) | `scripts/core/HeadlessWorldFullAssaultCaptureTest.gd` |
| Pure wiring | `tools/map_generation/tests/test_world_full_post_capture_station.py` |
| Pure capture | `tools/map_generation/tests/test_world_full_assault_capture.py` |
| Map CI hooks | `tools/run_map_ci.sh` (both headless + pure) |

## Non-goals (this slice)

- Full movement orders / pathfinding between non-adjacent provinces
- Defender retreat station logic
- Multi-division stack station redistribution
