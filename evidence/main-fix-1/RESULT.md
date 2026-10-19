# MAIN-FIX-1 FIX #1 — live capture toast + peace buttons

**Branch:** `cursor/main-fix1-toast-peace-9624` (off `grok/main-fix-1`)  
**Base PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/116 (`grok/main-fix-1` @ `f60a6d39`)  
**Merge:** HOLD  
**Date:** 2026-10-19

Playtest confirm on `f60a6d39` came back MIXED (`uploads/RESULT_0fd4.md`). Esc/Prod **PASS**. Two remaining problems: live false capture toast; peace sheet buttons.

## Root causes

### 1. Live `Province captured · POL vs GER at Elbląski` (BUG — fixed)

Unique body `"%s vs %s at %s"` is only `BattleManager._post_battle_news` (`scripts/combat/BattleManager.gd`). Title `Province captured` + that body is what LeaderEventUI paints as `Province captured · POL vs GER at Elbląski`.

**Why headless missed it:** `HeadlessCampaignLoop1DeclareClickTest` clears `LeaderManager.formations` then stations only GER hold units, so POL never `start_land_battle`. Live F5 parks POL at Warsaw and runs `TimeManager._maybe_run_ai_land_battle_starts` → `try_ai_start_land_battles` after Declare.

**Why it looked false:** Elbląski `711086` (and Słupski `711091` on main) are **GER-owned in 1936** (`province_ownership_1936.json`) with Polish NUTS names and `core_for_tags: POL`. POL AI empty-hex (`start_land_battle` → `_apply_attacker_win_capture_light`) flipped owner GER→POL in ~2–3 s (`call_deferred` / first day tick). Inspector on 30 Jan showed Owner POL / Core POL. `godot.log` had nothing because `_post_battle_news` did not print.

`WarStateDomain.player_declare_from_province` is still diplomatic-only (`declare_war` + `invalidate_fronts`). Controller does **not** flip on declare. The flip was a real (but wrong) AI empty-hex of the human player's land.

**Fix:**
- Every `Province captured` path logs `MAIN_FIX1_CAPTURE_SRC` (`_post_battle_news`, `_apply_attacker_win_capture_light`, `apply_combat_outcome`, `start_land_battle` skip, `LeaderEventUI.post_news` / `show_toast` / `_show_toast`, `MapRenderer` assault flair + AAR, `MapNextListHelpers.format_capture_assault_flair`, TimeManager Maginot demo).
- Toast only when **owner** actually becomes the attacker. Controller-only is logged and not toasted (not a capture).
- Interactive light sim **skips AI empty-hex vs the human player's land** (`_is_ai_empty_hex_vs_human_player`) — that stop the Elbląski/Słupski flip. Player empty-hex of POL (force-capture hook) still toasts.

Other `Province captured` strings: TimeManager Maginot demo (`USA vs ENG at North Coast` — not live F5); MapNextListHelpers `"%s captured %s"` (player assault flair, different format).

### 2. Peace sheet buttons darkened but did nothing (BUG — fixed)

Raw unstyled `Button` at `ACTION_MODE_BUTTON_RELEASE`. MapRenderer `_campaign_modal_consumes_pointer` handles the mouse-up, so `pressed` never fired; only the pressed visual. Hook-opened sheets also had empty `pending_sheet`, so `apply_player_choice` was a no-op even if emit ran.

**Fix:** Retrowave `style_primary_button` / `style_secondary_button`, `ACTION_MODE_BUTTON_PRESS`, `arm_pending_sheet`, `_campaign_peace_choose` applies + logs `MAIN_FIX1_PEACE_BTN` + closes (once).

### 3. Camera jumped to the Baltic during Esc+Prod+Leaders (not Esc)

`MapRenderer._handle_escape_key` does not pan. Home / End / **B** (fronts centroid) / `_center_camera_on_province` do. Not an Esc-handler bug — no code change.

### 4. Play hooks (dev-only, off by default)

- `EOA_MAIN_FIX1_FORCE_CAPTURE=1` — GER takes one POL border province through `_apply_attacker_win_capture_light`.
- `EOA_MAIN_FIX1_PEACE_HOLD_S=600` — open the campaign peace sheet and hold ≥600 s.
- Wrapper: `tools/eoa_main_fix1_play_hooks.sh --force-capture` / `--peace-hold`.

## Constraints held

- Never renumber `world_full` IDs
- No new residual dual packages
- No GameData rewrite
- Godot only via `tools/run_godot.sh`
- `--quick` same 14 known `unit_board_play_path` reds
- map_qc NE **0.9853**
- Seed 193601 `20fe9063` unedited
- 0 SCRIPT ERROR
- No force push

## Tests

See the commit / later update of this file after the gate run.
