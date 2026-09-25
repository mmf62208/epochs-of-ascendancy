# STATUS — FIX IX-1 live Esc never reaches title on tip `2a4ed6b` (PR 55)

**State:** DONE (machine). **HOLD merge.**  
**Assign:** `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_2A4ED6B.md`  
**Start tip:** `2a4ed6bcae5ec3c37e719bf813638396b95f171c` (`2a4ed6b`)  
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/55 (draft, HOLD merge)  
**Branch:** `cursor/ix1-road-spine-9d9b`

## Soft wall
Play RESULT FAIL tip `2a4ed6b` — 4th consecutive live Esc→CC HARD FAIL. Window stayed. Begin / past+6 / Search / spine NOT RUN.  
**Critical:** live `godot.log` had **zero** `EOA_LIVE_ESC`. Esc never reached title / MainMenu / LivingTitleBoot under computerUse + `tools/run_godot.sh`. Not toggle-close. Headless LivingTitleEscBegin + probes were green (DisplayServer=headless; not Play F5 proof).

## Cause
computerUse Escape was not delivered to Godot Input on Play's F5 session. MapRenderer also swallowed TopInfoBar Menu clicks while the living title was up (`set_input_as_handled` on every non-panel left-press).

## Fix
- Keep sticky **open-only** + `EOA_LIVE_ESC` (do not reintroduce toggle-close).
- Delivery attempts: window focus / `DisplayServer.window_move_to_foreground` / `Window.window_input` / explicit `ui_cancel` Esc binding.
- **Softpipe unblock:** `Command Center · Esc` button + `Esc · Menu` chip (layer 120). **Begin dismisses the title without Esc first.**
- Title-up `_input` lets `_top_bar_owns_click` through.
- Past-+6 / R2 / Search Go / spine / window-stay / layers 110/120/130 **kept**.

## Honest live-delivery claim
| Prove | Result |
|-------|--------|
| Headless LivingTitleEscBegin (mouse CC + Begin-without-Esc + two Esc stay) | **PASS** |
| LiveEscWindowProbe DisplayServer=**X11** (synthetic keys + mouse CC + Begin) | **PASS** |
| Lean living-title-only window + **xdotool Escape** on `DISPLAY=:1` | **PASS** — `title.window_input` saw keycode 4194305; two Esc kept CC (`EOA_LIVE_ESC` present) |
| Play computerUse Esc on full TestScenario F5 | **UNPROVEN** — that is the 2a4ed6b zero-`EOA_LIVE_ESC` hole. If Play still sees zero logs, use the click path. |

Full TestScenario F5 **not** driven on this CA (map OOM class). Lean X11 window is the same `tools/run_godot.sh` + real DisplayServer key path, not computerUse.

## Play should try
1. **Esc first** (HARD preferred). If `EOA_LIVE_ESC` appears and CC stays up ×2, continue softpipe.
2. If **zero** `EOA_LIVE_ESC`: click **Esc · Menu** (top-right) or **Command Center · Esc**, then **Begin · Germany · 1936**, then past+6 → Search → spine. Report Esc still FAIL separately.

## Gates
| Gate | Result |
|------|--------|
| IX-1 product 13/13 | **PASS** |
| HeadlessIx1SearchGoInspectorTest | **PASS** |
| HeadlessIx1RoadSpineMandateGateTest | **PASS** cost=0 |
| HeadlessIx1RoadSpineDayTickTest | **PASS** soak past 7 Jan day=9 elapsed=8 |
| HeadlessIx1LivingTitleEscBeginTest | **PASS** — mouse CC + Begin-without-Esc + two Esc keep CC |
| HeadlessIx1LiveEscWindowProbe | **PASS** DisplayServer=X11; no SCRIPT ERROR on cleanup |
| LeanLivingTitleX11KeyProve + xdotool Esc | **PASS** window_input delivery on this CA |
| `--quick` map_qc | **FAIL** env (Pillow missing) — same class as prior STATUS |

## Next
Scott → Play rebound. HOLD merge. Dig2/G PARKED. Quiet Mike beyond tip SHA / PR URL.
