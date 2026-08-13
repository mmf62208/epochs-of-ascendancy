# EVIDENCE — post-capture defender displace

See also: `/tmp/grok-goal-1b8ca76ada87/implementer/EVIDENCE.md` (goal scratch).

**Fix:** `BattleManager._displace_defender_from_captured_province` after ownership flip + attacker station.
Prefer adjacent friendly land; else any remaining friendly; else clear station to -1.

**Headless:** `HeadlessWorldFullPostCaptureDefenderDisplaceTest` — def 9281→92990 (with rear), 9281→-1 (no friendly); att→9281; reinforce OK.

**Pure:** `test_world_full_post_capture_defender_displace.py`  
**CI:** `tools/run_map_ci.sh` hooks both GD + pure.
