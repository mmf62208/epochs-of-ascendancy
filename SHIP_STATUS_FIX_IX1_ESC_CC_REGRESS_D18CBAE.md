# STATUS — FIX IX-1 Esc→CC / Begin LIVE regress (post-merge PR 55)

**State:** machine work. **HOLD merge.**  
**Assign:** `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_D18CBAE.md`  
**Start tip (assign):** `d18cbae8dd96b0c53072810d1e482aa840785280`  
**PR 55:** merged at `8f666bf1c70d919dfeb9e3c423412a8a9436869e` → `main` `1d092a14`  
**This follow-up:** https://github.com/mmf62208/epochs-of-ascendancy/pull/56 (draft)  
**Branch:** `cursor/ix1-live-esc-begin-26e3`  
**Functional fix:** `4868b880ef50586b176482d4f317d7df82d96148`  
**New head:** `8bce8b7f23e5a2730503ab8d77501fa0b10b99e6`

## Soft wall
Play RESULT FAIL on `d18cbae` (same as `d53ee05`): Esc→CC HARD FAIL; Begin · Germany · 1936 no transition; Godot DEBUG window exited. Headless LivingTitleEscBegin (layers 120/130) was green. Later PR 55 work added poll / `window_input` / mouse-CC / smoke hatch and still recorded **product Begin/Esc FAIL** (zero post-boot `EOA_LIVE_RAW_*` — computerUse never activated the main game X11 client).

## Cause (live gap, not layers)
Layer ints and in-tree `_input` are not enough. Play computerUse clicks the visible panel **without activating** the main Godot window. Click-to-focus eats ButtonPress; DisplayServer poll on the main client stayed silent after `title.ready`. Main-window `FLAG_ALWAYS_ON_TOP` + `window_move_to_foreground` every 0.4s also restacked under Alt+Tab (game_exit class).

## Fix (beyond layers)
- Host the living-title UI in a transient **exclusive** `LivingTitleHost` Window (separate X11 client at the panel pixels). Headless `-s` keeps the CanvasLayer path.
- Esc hides the host so Command Center (layer 130) is visible; closing CC restores the host until Begin.
- WM close of the host is **Begin**, not `quit` (window-exit class).
- Stop always-on-top / move-to-foreground on the **main** game window.
- Keep: title `_input` + sticky-open + DisplayServer poll + Command Center · Esc / Esc · Menu + Begin PRESS + layers 110/120/130 + past-+6 softpipe + R2 clock + Search Go + spine pin.

## Kept
R2 clock ownership. Search Go. Build Road Spine pin. Mandate 0. Corridor IDs unchanged. Dig2/G **PARKED**. No `world_full` renumber. No dual packages.

## Gates
| Gate | Result |
|------|--------|
| HeadlessIx1SearchGoInspectorTest | **PASS** |
| HeadlessIx1RoadSpineMandateGateTest | **PASS** cost=0 |
| HeadlessIx1RoadSpineDayTickTest | **PASS** — soak past 7 Jan day=9 elapsed=8 paused=false toast_ignore=1 |
| HeadlessIx1LivingTitleEscBeginTest | **PASS** — native host path + live Esc shapes + Begin PRESS + sticky Esc×2 |
| Lean X11 Begin (`eoa_lean_title_click_prove.sh`) | **PASS** — `EOA_LIVE_HOST` exclusive Window; `title.window_input` → Begin GER 1936 |
| Play-like unfocused click | **PASS** — host grabbed Begin after Desktop focus steal |
| Lean X11 Esc | **PASS** — `title.window_input` keycode Esc → Command Center (sticky) |

Full `world_accurate` F5 TestScenario was **not** driven here (3520-board OOM class on this VM). Play must still prove Esc→CC + Begin on the host Window over the live map.

## Live F5
Lean / play-like DisplayServer on this VM **did** reach the host Window (Begin + Esc). That is not a substitute for Play computerUse on TestScenario. Do not claim full live F5 PASS from headless or from the lean title-only window.

## Next
Scott → Play rebound: Esc→CC (host hides, CC visible) → Begin (window stays) → past+6 / past 7 Jan → Search→spine→RoadLayer→Essen. **HOLD merge.**
