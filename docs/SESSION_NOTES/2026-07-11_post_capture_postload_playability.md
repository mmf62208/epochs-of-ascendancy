# EVIDENCE — post-save/load restore still enables playability

Post-capture campaign continuity: after map + production + leader save/load,
assault entry, **daily** reinforce, and combat equip stats still work.

## Fix

`LeaderManager.get_save_data` / `apply_save_data` now round-trip formation
`design_id` (plus air/naval design ids). Without this, post-load
`get_formation_required_equipment` / `daily_formation_reinforce_from_stockpile`
/ combat stats resolve as empty OOB even when unit on-hand stockpile restored.

## Elements

1. **can_assault** from restored capture station (attacker on 9281) toward FRA rear 92990 — non-empty formation id
2. **daily reinforce** `daily_formation_reinforce_from_stockpile()` after restore + empty hand (design_id via OOB; **not** hardcoded `request_equipment_for_unit`)
3. **combat equip stats** from **restored** on-hand: `has_shortages=false` soft>empty baseline

## Tests

- **Headless:** `scripts/core/HeadlessWorldFullPostCapturePostLoadPlayabilityTest.gd`
- **Pure:** `tools/map_generation/tests/test_world_full_post_capture_postload_playability.py`
- **CI:** `tools/run_map_ci.sh` (Godot + pure hooks)
- **Dual world_full scene:** `EOA_SCENARIO=world_full … TestScenario.tscn` → `headless_world_full_1/2.log`

## Sample (after criterion-2 fix)

```
e1 can_assault ok=true fid=wf_plp_ger_div power≈1.877
e3 restored-hand has_shortages=false soft=1.117 hand=2
e2 daily_formation_reinforce_from_stockpile stock 5→4 hand 0→1 moved=1
PASS (failures=0)
```

## Fixture

- GER 9276 → FRA 9281 capture (stochastic assault + forced outcome fallback)
- design `cv33_tankette`, stock seed 5, hand seed 2
- save map `_serialize_map_state` + prod `get_save_data` + leader `get_save_data`
- mutate owner/station/design/stock/hand → apply all three
