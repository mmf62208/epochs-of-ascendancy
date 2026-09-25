# STATUS — FIX IX-1 Play computerUse never hits title pointer path on tip `f9f249c` (PR 55)

From: Ship
Assign: `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_F9F249C.md`
Evidence: `/workspace/eoa-smoke-f9f249c/RESULT.md` (zero `EOA_LIVE_PTR` + zero `EOA_LIVE_ESC`)
Start tip: `f9f249cf0927e8782cf875dda22e4a4df5691274`
**New tip (GitHub `head.sha`):** `329ab971c3311b003edabb2179eb5d757397e58e`
PR: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 (**HOLD merge**, draft)

## State: DONE — HOLD await Play

## Soft wall
Play RESULT FAIL tip `f9f249c`. Begin first FAIL; mouse CC / Esc·Menu FAIL; Esc×2 FAIL. Live godot.log: **zero `EOA_LIVE_PTR`**, **zero `EOA_LIVE_ESC`**. Window stayed. Softpipe NOT RUN.

## Dig (why computerUse never printed EOA_LIVE_PTR)
Prior lean **xdotool + windowactivate** Begin PASS is not Play's driver. Play computerUse clicks screenshot pixels **without activating** Godot. Two holes:

1. **Click-to-focus** can eat the first ButtonPress so `Input.is_mouse_button_pressed` / GUI `pressed` stay false.
2. Hit-only logs hid misses — zero `EOA_LIVE_PTR` did not prove the handler never ran.

On this CA, a **live computerUse left-click** on the lean title (same `tools/run_godot.sh`, DisplayServer=X11, no xdotool) produced:

```
EOA_LIVE_RAW_PTR who=title.window_input class=mouse btn=1 pressed=true ev_pos=(240.0, 624.0)
EOA_LIVE_PTR who=title.handle_live_pointer action=begin
LivingTitleBoot: live Begin · GER · 1936
```

Full TestScenario F5 (3520 + MapRenderer) is still Play's rebound — not claimed PASS here.

## Shipped
- `DisplayServer.mouse_get_button_state()` poll (global OS pointer) + TestRunner same
- `EOA_LIVE_RAW_PTR` / `EOA_LIVE_RAW_KEY` on any title-up mouse/key + 2s heartbeat
- Left-column Begin fallback after panel miss; taller Begin
- Documented **Enter / Space / B** (`eoa_living_begin` + Window + MapRenderer)
- `tools/eoa_playlike_title_click_prove.sh` — steal focus, hold-click, **no** `windowactivate`

Held: sticky-open · window-stay · layers 110/120/130 · past-+6 · R2 · Search Go · spine · `EOA_LIVE_ESC` · mouse CC. Dig2/G PARKED. No toggle-close.

## Honest live-delivery claim

| Path | Proven? |
|------|---------|
| Headless 5/5 (LivingTitleEscBegin includes raw + DS poll + Enter; SearchGo; Mandate 0; DayTick; LiveEscWindowProbe) | **PASS** |
| Lean title + xdotool **unfocused** hold-click (`tools/eoa_playlike_title_click_prove.sh`, `tools/run_godot.sh`, X11) | **PASS** (`window_input` + `action=begin`) |
| Lean title + **computerUse** screenshot click (same launch, no xdotool) | **PASS** on this CA — `title.window_input` + `handle_live_pointer action=begin` + `live Begin · GER · 1936` |
| Play F5 computerUse on full TestScenario | **UNPROVEN** — rebound Play. Watch `EOA_LIVE_RAW_PTR` first. |

## Play should try
1. **Click Begin · Germany · 1936** (Esc not required). Overlay dismisses; window stays. Log should show `EOA_LIVE_RAW_PTR` then `EOA_LIVE_PTR action=begin`.
2. If mouse still dead: press **Enter** (or Space). Look for `EOA_LIVE_RAW_KEY` / `action=begin_key`.
3. Else **Command Center · Esc** / **Esc · Menu**.
4. Esc ×2 if `EOA_LIVE_ESC` appears.
5. Then past+6 → Search Köln/Cologne + Go → spine.

If the next fail still has **zero `EOA_LIVE_RAW_PTR`**, computerUse never delivered an OS event into this Godot window (not a hit-box miss).
