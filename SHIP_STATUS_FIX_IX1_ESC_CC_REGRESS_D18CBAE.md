# STATUS — FIX IX-1 Esc→CC / Begin LIVE regress on tip `d18cbae`

**State:** DONE (machine). **HOLD merge.**  
**Assign:** `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_D18CBAE.md`  
**Start tip:** `d18cbae8dd96b0c53072810d1e482aa840785280` (`d18cbae`)  
**New head:** `8fe682c1042613ee9449bafee79fa103e8b60104`  
**Functional fix:** `8cfb02e80db53e5f506e44b3db97afea849bbe9a`  
**Follow-up:** parse-safe Esc helpers `49ac0770d6456b5913e76db268f9f50dbea44dd3`  
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/55 (draft, HOLD merge)  
**Branch:** `cursor/ix1-road-spine-9d9b`

## Soft wall
Play RESULT FAIL on `d18cbae` — same as `d53ee05`: Esc→CC HARD FAIL; Begin · Germany · 1936 no transition; Godot DEBUG window exited. Headless LivingTitleEscBegin (title 120 / CC 130) was green. Layer-only is not enough.

## Cause (live gap, not layers)
MapRenderer `_input` arms map pick / chip / assault **before** GUI. After living title, `gui_get_hovered_control()` misses the Begin panel (same class as Search Go / 4x). Begin used release-default `pressed`, so a swallowed release never started. Esc listened for `keycode == KEY_ESCAPE` only — live DisplayServer can deliver `physical_keycode` or `ui_cancel`. Title + renderer both opening CC on one Esc would toggle-close (looks like a no-op). Map clicks under the title could still open chips/assault (window-exit class).

## Fix (beyond layers)
- Living title owns `_input` / `_unhandled_input`: Esc keycode + physical + `ui_cancel`; Begin `ACTION_MODE_BUTTON_PRESS` + `gui_input` + rect-first `_input` backup; `handle_live_escape` one-frame guard.
- MapRenderer `_living_title_owns_click()` rect-first early-out (do not handle title clicks). While title is up, map clicks select country only — never chips / inspector / assault.
- Layers **kept**: UILayer 110, title 120, CC 130. Past-+6 skip / toast+Map Mode IGNORE / soak past 7 Jan **kept**.
- `HeadlessIx1LivingTitleEscBeginTest` now fails if that live routing is missing (not layer-only).

## Kept
R2 clock ownership. Search Go (`5732d34`). Build Road Spine pin (`36485b9`). Mandate 0. Corridor IDs unchanged. Dig2/G **PARKED**. No `world_full` renumber. No dual packages.

## Gates
| Gate | Result |
|------|--------|
| IX-1 product suite | **13/13** |
| HeadlessIx1SearchGoInspectorTest | **PASS** |
| HeadlessIx1RoadSpineMandateGateTest | **PASS** cost=0 |
| HeadlessIx1RoadSpineDayTickTest | **PASS** — soak past 7 Jan day=9 elapsed=8 paused=false toast_ignore=1 |
| HeadlessIx1LivingTitleEscBeginTest | **PASS** — layers + live Esc shapes + Begin PRESS wiring + `_input` owns Begin/Esc |

`--quick` `unit_board_play_path` / `living_unit_order_loop_product` still FAIL on this branch for pre-existing needles (`air_region_cas`, `peace_occupation`, `nation_era_next`, `map_country_select`, `playtest_clock`) — same on `d18cbae` before this FIX. Not introduced here. `map_qc` needs Pillow in the gates venv (env).

## Live F5 on this VM
Driven: `DISPLAY=:1 tools/run_godot.sh --path . res://scenes/TestScenario.tscn`. Living title boot logged; window `Epochs-of-Ascendancy (DEBUG)` 1680×960; 3536 provinces. Map/panel clicks did **not** exit the window (window-exit class not reproduced). Esc via xdotool and Begin clicks (cursor on Begin · Germany · 1936) did **not** log title-closed before the process was **OOM-killed (exit 137)** at ~14 GiB RSS. **Play must prove** live Esc→CC HARD and Begin transition (window stays). Do not treat this STATUS as a live Esc/Begin PASS.

## Next
Scott → Play rebound: Esc→CC → Begin (window stays) → past+6 / past 7 Jan → Search→spine→RoadLayer→Essen. HOLD merge until Play RESULT.
