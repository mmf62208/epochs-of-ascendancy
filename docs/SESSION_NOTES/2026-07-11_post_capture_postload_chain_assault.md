# EVIDENCE — post-load chain/flank assault

Budget revision: continue campaign continuity within ~300k tokens.

After map + production + leader restore of a pre-battle chain fixture:

1. **`execute_chain_assault_or_flank`** ≥ 2 successful steps with first capture (GER 9276→FRA 9281)
2. **Follow-on** stages from captured province (`from=9281`) toward next enemy (BEL 92991)
3. **`daily_formation_reinforce_from_stockpile`** still works via restored `design_id`

## Tests

- Headless: `HeadlessWorldFullPostCapturePostLoadChainAssaultTest.gd`
- Pure: `test_world_full_post_capture_postload_chain_assault.py`
- CI: `tools/run_map_ci.sh`

## Sample

```
e1 post-load chain size=2 owner=GER
e2 follow from=9281 target=92991 winner=attacker
e3 daily reinforce stock 6→5 hand→1
PASS (failures=0)
```
