# STATUS — FIX IX-1 Esc→CC / Begin softpipe regress

**State:** DONE (machine). **HOLD merge.**  
**Assign:** `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_D53EE05.md`  
**Start tip:** `d53ee054d5b9429ae9066e4be74d831c6dadb53b` (`d53ee05`)  
**Functional fix:** `8aca6cbf98293b1896f0a0339e9170396b837b7b` (`8aca6cb`)  
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/55 (draft, HOLD merge)  
**Branch:** `cursor/ix1-road-spine-9d9b`

## Soft wall
Play RESULT FAIL on `d53ee05` — Esc→CC HARD FAIL; Begin · Germany · 1936 no transition; Godot DEBUG window exited on map click (×2). Past +6 / Search / spine NOT RUN. SCRIPT_ERROR 0. Headless SearchGo + Mandate 0 + soak past 7 Jan stayed green.

## Cause
Past-+6 raised UILayer to **110** (TopInfoBar above Map Mode 20 / toasts 90) without raising living title **90** or Command Center **100**. TestRunner also smashed UILayer back to **20**. Title-map misses fell through to inspector/assault (window-exit class).

## Fix (scope layering, keep +6 intent)
- Keep UILayer **110** + toast/Map Mode `MOUSE_FILTER_IGNORE` + agent-pulse / factory-presence skip + reinforce/harvest caps + soak gate.
- Living title **120**, Command Center **130** — above that HUD so Begin and Esc→CC are not buried.
- TestRunner keeps UILayer at 110 (no smash to 20). First-session toast waits until title closes.
- Esc on the title opens CC immediately. Title owns map clicks (no inspector/assault).
- New runtime gate `HeadlessIx1LivingTitleEscBeginTest` (layer 120/130 + Begin Germany 1936 STOP).

## Kept
R2 clock ownership. Search Go (`5732d34`). Build Road Spine pin (`36485b9`). Mandate 0. Corridor IDs unchanged. Dig2/G **PARKED**. No `world_full` renumber. No dual packages.

## Gates
| Gate | Result |
|------|--------|
| Product suite | **13/13** |
| HeadlessIx1SearchGoInspectorTest | **PASS** |
| HeadlessIx1RoadSpineMandateGateTest | **PASS** cost=0 |
| HeadlessIx1RoadSpineDayTickTest | **PASS** — soak past 7 Jan day=9 elapsed=8 paused=false autosave=0 toast_ignore=1 |
| HeadlessIx1LivingTitleEscBeginTest | **PASS** — title 120 / CC 130 / Begin · Germany · 1936 STOP |

## Live softpipe
Full F5 GUI Esc→CC + Begin was **not** driven on this VM (world_accurate boot is the Play path; ~6.7 GiB free is tight for a 3520-board window). Machine proof is the new runtime instantiate gate + source/layer contract. **Play must prove:** Esc→CC HARD → Begin · Germany · 1936 (window stays up) → past +6 / past 7 Jan → Search→spine→RoadLayer→Essen.

## Next
Scott → Play rebound. HOLD merge until Play RESULT.
