# MAIN-FIX-1 FIX #1 — capture toast wording + peace buttons (on grok/main-fix-1)

**Branch:** `grok/main-fix-1` (PR **#116**)  
**Cursor PR #117:** closed without merge (commits fast-forwarded here; we do not merge `cursor/*`)  
**Merge:** HOLD until live Play re-runs GER Declare + peace click  
**Date:** 2026-10-19

Playtest MIXED on `f60a6d39`: Esc/Prod **PASS**. The Elbląski toast was a **true** empty-hex capture, not a false notice.

## Capture toast

**`scripts/combat/BattleManager.gd:_post_battle_news`** still owns the notice. After GER Declare, live F5 runs `try_ai_start_land_battles` → empty-hex `start_land_battle` → `_apply_attacker_win_capture_light`. Elbląski `711086` and Słupski `711091` are **GER-owned in 1936** (Polish NUTS names + POL cores). POL AI took undefended GER hexes. Play seeing Owner POL afterwards **matches**. Polish names on GER land are a data backlog; provinces are not renamed here.

**Gameplay:** AI empty-hex vs the human player is **not** skipped (reverted). AI-CREDIBLE-1 owns AI behaviour. Empty-hex capture is the same as on main.

**Kept / added:**
- Toast only when **owner** actually becomes the attacker. Controller-only is logged, not toasted. Declare does not flip controller.
- `MAIN_FIX1_CAPTURE_SRC` on every capture path, including a print in `_post_battle_news` so it shows in `godot.log`.
- Wording: **`Poland captured Elbląski from Germany (undefended)`** — attacker captured X from owner. Empty-hex adds `(undefended)`. Not `POL vs GER at X`.
- Peace buttons: Retrowave press-on-down, apply + `MAIN_FIX1_PEACE_BTN` + close.
- Play hooks (off): `EOA_MAIN_FIX1_FORCE_CAPTURE=1`, `EOA_MAIN_FIX1_PEACE_HOLD_S=600`.

Camera Baltic jump is not the Esc handler. No change.

## Constraints held

- Never renumber `world_full` IDs
- No GameData rewrite
- Godot only via `tools/run_godot.sh`
- `--quick` same 14 known `unit_board_play_path` reds
- map_qc NE **0.9853**
- Seed 193601 `20fe9063` unedited
- 0 SCRIPT ERROR
- No force push

## Tests

See the following commit after the gate run.
