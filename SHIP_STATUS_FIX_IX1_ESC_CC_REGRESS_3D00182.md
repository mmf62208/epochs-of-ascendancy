# STATUS — FIX IX-1 live Esc→CC still HARD FAIL on tip `3d00182` (PR 55)

**State:** DONE (machine). **HOLD merge.**  
**Assign:** `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_3D00182.md`  
**Start tip:** `3d001828b59904f3c1464b6c8b807372c429f162` (`3d00182`)  
**Functional fix:** `f0bc76336a4be9db151a228ad92d42d5acb34d48` (open-only + `_process` poll) + `1dde60380c639397747f30650b35bb19333ce16c` (title meta + X11 probe)  
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/55 (draft, HOLD merge)  
**Branch:** `cursor/ix1-road-spine-9d9b`

## Soft wall
Play RESULT FAIL tip `3d00182` — 3rd consecutive live Esc→CC HARD FAIL (`d53ee05` → `d18cbae` → `3d00182`) with headless LivingTitleEscBegin green. Window **stayed** (MapRenderer early-out held). Esc ×2 left Begin overlay unchanged.

## Cause (live gap, not layers / not single `_input`)
Play always presses Esc **×2** (dismiss-then-idle). First Esc opened Command Center; second Esc `MainMenu._input` / `_on_menu_pressed` **toggle-closed** it. One-frame guard is same-press only. Live computerUse Esc may also never reach title `_input` (focus / process_mode / who-handled). Headless sent one `_input` Esc and stayed green.

## Fix
- Sticky **open-only** while living title is up: `open_command_center_stay`; MainMenu will not `_force_close` (title walk + `eoa_opened_from_living_title` meta).
- Title + TestRunner `_process` poll the Input singleton when `_input` never fires.
- Esc also accepts `key_label` / unicode 27.
- `EOA_LIVE_ESC` who-saw-it logs (title / MapRenderer / TestRunner / TopInfoBar / CC).
- Headless two-Esc stay + poll/open-only source **fails** if that routing is missing.
- Lean windowed X11 probe (no 3520 board) proves two Esc keep CC on real DisplayServer.
- Window-stay / layers 110/120/130 / past-+6 / R2 / Search Go / spine **kept**.

## Gates
| Gate | Result |
|------|--------|
| IX-1 product 13/13 | **PASS** |
| HeadlessIx1SearchGoInspectorTest | **PASS** |
| HeadlessIx1RoadSpineMandateGateTest | **PASS** cost=0 |
| HeadlessIx1RoadSpineDayTickTest | **PASS** soak past 7 Jan day=9 elapsed=8 |
| HeadlessIx1LivingTitleEscBeginTest | **PASS** — two Esc keep CC; poll + open-only |
| HeadlessIx1LiveEscWindowProbe | **PASS** DisplayServer=X11 two Esc keep CC |

`--quick` `map_qc` FAIL is env (Pillow missing) — same class as prior STATUS. Not introduced here.

## Live F5 on this CA VM
Full `TestScenario` F5 **not** driven — 6.7 GiB available, prior Play/CA OOM 137 at ~14 GiB. Lean windowed `-s` probe on `DISPLAY=:1` (no 3520 board) **PASS** (X11; MainMenu `title_up=true`; two Esc keep CC). **Play must still prove** computerUse Esc→CC HARD on the living-title overlay over the map. Do not treat this STATUS as a full F5 Play PASS.

## Next
Scott → Play rebound: Esc→CC (×2 must leave CC visible) → Begin (window stays) → past+6 / past 7 Jan → Search→spine→RoadLayer→Essen. HOLD merge. Dig2/G PARKED. Quiet Mike.
