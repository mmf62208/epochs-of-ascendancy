# STATUS — FIX IX-1 Esc→CC / Begin LIVE regress (post-merge PR 55)

**State:** machine work. **HOLD merge.**  
**Assign:** `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_D18CBAE.md`  
**Start tip (assign):** `d18cbae8dd96b0c53072810d1e482aa840785280`  
**PR 55:** merged at `8f666bf1c70d919dfeb9e3c423412a8a9436869e` → `main` `1d092a14`  
**This follow-up branch:** `cursor/ix1-live-esc-begin-26e3` (new PR — cannot push onto merged 55)

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
See the PR / later section after the gate run.

## Live F5
Play must prove Esc→CC + Begin on the **host Window**. Lean X11 prove (no 3520 board) is corroboration only. Do not claim live F5 PASS from headless.

## Next
Scott → Play rebound: Esc→CC (host hides, CC visible) → Begin (window stays) → past+6 / past 7 Jan → Search→spine→RoadLayer→Essen. **HOLD merge.**
