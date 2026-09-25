# STATUS — FIX IX-1 live past-+6 softpipe wedge on `3648dc9` (PR 55)

Updated: Fri Sep 25, 2026

## DONE
- Same draft PR 55: https://github.com/mmf62208/epochs-of-ascendancy/pull/55
- Parent tip: `3648dc9956d34f53c7a358a2bf2324da12724b05` (`3648dc9`)
- New head: (see git after push)

## Still PASS (do not drop)
- R2 clock ownership (TopInfoBar 4x/pause; Begin releases blockers; TestRunner does not re-pause)
- Search Go live wiring
- Build Road Spine CTA pin
- Mandate day-0 cost 0
- Esc→CC; SCRIPT_ERROR 0
- Dig2/G PARKED; no world_full renumber; no Godot bump; no dual packages

## Soft wall (Play FAIL `3648dc9`)
After Begin GER 1936 + 4x the clock **left 1 Jan** (R2 held) → `1 Jan 08:00` → `3 Jan 20:00` → **`6 Jan 1936 20:00 (+5d)` then stuck** (>20s pause/play/speed). Map Mode open + stacked Province-captured toasts. Past +6 / past 7 Jan **FAIL**. Search / spine / RoadLayer / Essen NOT RUN.

## Cause (both classes)
- **Class A:** day-+5 harvest/reinforce still on the live path; day-6 (`elapsed % 3 == 0`) `AgentManager.advance_networks_daily` plus factory/presence day rebuilds under llvmpipe. Prior +5/+6 autosave skip / harvest cap / network-*layer* pulse skip were still present — the **AgentManager** pulse was not.
- **Class B:** WorldMap UI CanvasLayer **20** (expanded Map Mode preset HBox overflow) and toast CanvasLayer **90** sat **above** TopInfoBar UILayer **10**. Softpipe hover-miss + leftover pick-block meant pause/speed never reached TimeManager after the toast stack appeared.

## Fix
- Skip live-F5 agent-network daily pulse; skip factory-status / agent-presence day rebuild
- Live-F5 reinforce is player-tag only (cap 32); harvest cap 96 + calendar autosave skip **kept**
- Toast container `MOUSE_FILTER_IGNORE` + clip; combat capture toasts coalesced to 1 (news history kept)
- Map Mode IGNORE + clip (no full-width overflow steal)
- TestScenario UILayer **110** (above Map Mode 20 and toasts 90)
- Gate `simulate_live_f5_softpipe_past_plus6` FAILS if still on 6 Jan / paused / autosave gathered / toast steals

## HOLD
**HOLD merge.** Scott rebounds Play: past +6 / past 7 Jan → Search→spine visible+start → complete → RoadLayer → Essen. Quiet Mike beyond PR URL / head SHA.
