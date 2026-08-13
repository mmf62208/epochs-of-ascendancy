# EVIDENCE — post-load conquest operational loop

After capture + full manager restore (map, production, leaders, design, factory),
the campaign can still **execute** combat, **produce** on seized industry, and
**field** acquired foreign designs.

## Elements

1. **execute** follow-on `execute_province_assault` from restored station (9281→92990) returns success + winner
2. **seized factory** `bootstrap_line_on_factory` + `advance_days(100)` → attacker stockpile grows (defender Δ=0)
3. **acquired design fielding** `country_may_use_design` + equip → `has_shortages=false` and soft_attack rises

## Prerequisites (prior slices)

- LeaderManager formations save `design_id`
- DesignManager / FactoryManager get/apply_save_data
- SaveLoad map `_serialize/_apply_map_state`
- ProductionManager stockpile/unit equip save

## Tests

- **Headless:** `scripts/core/HeadlessWorldFullPostCapturePostLoadConquestLoopTest.gd`
- **Pure:** `tools/map_generation/tests/test_world_full_post_capture_postload_conquest_loop.py`
- **CI:** `tools/run_map_ci.sh`

## Sample run

```
e1 execute success=true winner=attacker
e2 advance 100d att 0→3 (Δ+3) def 0→0 fac=GER
e3 soft 0.548→0.883 has_shortages=false
PASS (failures=0)
```
