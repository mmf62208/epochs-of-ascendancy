# EVIDENCE — post-load combat equip cycle

After capture + map/prod/leader restore, combat equipment durability still works:

1. **write-off** `apply_combat_equipment_loss` reduces restored on-hand  
2. **shortages** empty hand → `has_shortages=true` and lower soft_attack; equipped clears shortages  
3. **re-reinforce** `request_equipment_for_unit` from restored stockpile refills hand and clears shortages  

## Tests

- **Headless:** `HeadlessWorldFullPostCapturePostLoadCombatEquipCycleTest.gd`
- **Pure:** `test_world_full_post_capture_postload_combat_equip_cycle.py`
- **CI:** hooked in `tools/run_map_ci.sh`

## Sample

```
e1 loss hand 4→2 removed={cv33_tankette: 2}
e2 empty short=true soft=0.692 | full short=false soft=1.117
e3 reinforce stock 8→6 hand 0→2 short=false
PASS (failures=0) dual green
```
