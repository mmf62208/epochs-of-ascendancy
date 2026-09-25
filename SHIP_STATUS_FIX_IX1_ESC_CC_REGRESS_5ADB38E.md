# STATUS — FIX IX-1 live title input dead under computerUse on tip `5adb38e` (PR 55)

**State:** DONE (machine). **HOLD merge.**  
**Assign:** `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_5ADB38E.md`  
**Start tip:** `5adb38ee1e54c0abde523b27f126696df1c1c341` (`5adb38e`)  
**New head:** `a0f576bb49cab622fb6d11a1e6e2126a0ccbc739` (`a0f576bb`)  
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/55 (draft, HOLD merge)  
**Branch:** `cursor/ix1-road-spine-9d9b`

## Soft wall
Play RESULT FAIL tip `5adb38e`. Esc×2 no CC / zero `EOA_LIVE_ESC`. Mouse **Command Center · Esc** + **Esc · Menu** did not open CC. **Begin** click left overlay; session never started. Window stayed. Past+6/Search/spine NOT RUN. Headless 5/5 had been PASS.

## Cause
MapRenderer `_input` swallowed every title-up left-press that `_living_title_owns_click()` missed. That helper used only `Viewport.get_mouse_position()`. Play computerUse clicks land on the visible Begin / CC chips, but the mouse singleton can be stale (or the event is `ScreenTouch`). The press was `set_input_as_handled()` before GUI / title `_input` could fire.

First lean X11 click prove on this CA confirmed the hole class: a real DisplayServer click *did* reach `window_input` but was classified `panel` because Begin’s printed rect was pre-layout (28×52). After layout wait + full-width Begin + lower-panel slab, the same xdotool path dismissed the title.

## Fix
- `LivingTitleBoot.handle_live_pointer` — event.position first, then DisplayServer fallback; `ScreenTouch`; CC classified before Begin slab.
- Grown Begin / CC hit pads; Begin+CC `SIZE_EXPAND_FILL`; lower panel slab below CC is Begin (status caption included).
- MapRenderer routes title-up presses through `handle_live_pointer` and **does not** blindly swallow.
- `window_input` + title `_process` + TestRunner `_process` poll left-button (same class as Esc poll).
- Sticky **open-only**, `EOA_LIVE_ESC`, Esc·Menu / Command Center·Esc **kept**.
- Past-+6 / R2 / Search Go / spine / window-stay / layers 110/120/130 **kept**.
- Lean prove: `tools/eoa_lean_title_click_prove.sh` + `LeanLivingTitleX11ClickProve.gd`.

## Honest live-delivery claim

| Prove | Result |
|-------|--------|
| Headless LivingTitleEscBegin (pointer event + ScreenTouch + mouse CC + Begin-without-Esc + two Esc stay) | **PASS** |
| Headless SearchGo / Mandate cost=0 / DayTick soak past 7 Jan day=9 | **PASS** |
| LiveEscWindowProbe DisplayServer=**headless** | **PASS** (not Play F5) |
| Lean title window + **xdotool left click** on Begin (`DISPLAY=:1`, `tools/run_godot.sh`, DisplayServer=**X11**) | **PASS** — `title.window_input` + `handle_live_pointer action=begin` + `live Begin · GER · 1936`; Begin laid out 364×52 |
| Play computerUse Esc on full TestScenario F5 | **UNPROVEN** — still the zero-`EOA_LIVE_ESC` delivery hole |
| Play computerUse mouse-CC / Begin on full TestScenario F5 | **UNPROVEN** — that is the 5adb38e FAIL. Lean X11 click is the same `run_godot.sh` + real DisplayServer pointer path, not computerUse |

`--quick` map_qc **FAIL** env (Pillow missing) — same class as prior STATUS.

## Play should try
1. **Click Begin · Germany · 1936** (Esc is not required). Overlay should dismiss; window stays; clock stays paused at 1 Jan until 4x.
2. If Begin still dead: click **Command Center · Esc** or **Esc · Menu**. Look for `EOA_LIVE_PTR` in `godot.log`.
3. Esc ×2 still preferred when `EOA_LIVE_ESC` appears. Report which of Esc / mouse-CC / Begin worked.
4. Then past+6 → Search Köln/Cologne + Go → Build Road Spine.

HOLD merge. Dig2/G PARKED. Quiet Mike beyond tip SHA / PR URL.
