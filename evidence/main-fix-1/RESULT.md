# MAIN-FIX-1 FIX #1 — live capture toast + peace buttons

**Branch:** `cursor/main-fix1-toast-peace-9624` (off `grok/main-fix-1`)  
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/117  
**Base:** https://github.com/mmf62208/epochs-of-ascendancy/pull/116 (`grok/main-fix-1` @ `f60a6d39`)  
**Tip:** `6e5af5ef`  
**Merge:** HOLD until live Play re-runs GER Declare + peace click  
**Date:** 2026-10-19

Playtest confirm on `f60a6d39` came back MIXED (`uploads/RESULT_0fd4.md`). Esc/Prod **PASS**. Two remaining problems: live false capture toast; peace sheet buttons.

## Root cause of the live toast (file:line)

**`scripts/combat/BattleManager.gd:_post_battle_news` line 3008** (title/body at **3047–3053**).

The unique live string `Province captured · POL vs GER at Elbląski` is only that function: title `"Province captured"` + body `"%s vs %s at %s"`. `LeaderEventUI.post_news` paints it as one toast. Headless `--headless` skips the toast UI (`_should_skip_toast_ui`), which is why the first probe logged nothing.

**Live fire path after GER Declare on POL (~2–3 s):**

1. `TimeManager._maybe_run_ai_land_battle_starts` → `BattleManager.try_ai_start_land_battles`
2. `start_land_battle` empty-hex branch **529** / **557** → `_apply_attacker_win_capture_light` **1471**
3. `_post_battle_news(..., captured=true)` **3008** → `LeaderEventUI.post_news` **3053**

Elbląski `711086` and Słupski `711091` are **GER-owned in 1936** (`province_ownership_1936.json`) with Polish NUTS names and `core_for_tags: POL`. POL AI empty-hex flipped owner GER→POL. The inspector on 30 Jan (Owner POL / Core POL) is that flip, not a false-positive toast on unchanged land.

`WarStateDomain.player_declare_from_province` is diplomatic-only (`declare_war` + `invalidate_fronts`). **Controller does not flip on declare.** The live toast was a real (wrong) AI empty-hex of the human player's land, not a controller-only notice.

Headless `HeadlessCampaignLoop1DeclareClickTest` missed it because it cleared `LeaderManager.formations` and only stationed GER, so POL never `start_land_battle`.

**Fix:**
- Interactive light sim **skips AI empty-hex vs the human player's land** (`_is_ai_empty_hex_vs_human_player` **1449**, skip at **529** / **557**).
- Every `Province captured` path logs `MAIN_FIX1_CAPTURE_SRC` (`_post_battle_news`, `_apply_attacker_win_capture_light`, `apply_combat_outcome`, `start_land_battle` skip, `LeaderEventUI.post_news` / `show_toast` / `_show_toast`, `MapRenderer` assault flair + AAR, `MapNextListHelpers.format_capture_assault_flair`, TimeManager Maginot demo).
- Toast only when **owner** actually becomes the attacker. Controller-only is logged and not toasted.
- Player empty-hex of POL (force-capture hook) still toasts.

Other `Province captured` strings: TimeManager Maginot demo (`USA vs ENG at North Coast` — not live F5); MapNextListHelpers `"%s captured %s"` (player assault flair, different format).

## Peace buttons

Raw unstyled `Button` at `ACTION_MODE_BUTTON_RELEASE`. MapRenderer `_campaign_modal_consumes_pointer` handled the mouse-up, so `pressed` never fired; only the pressed visual. Hook-opened sheets also had empty `pending_sheet`, so `apply_player_choice` was a no-op even if emit ran.

**Fix:** Retrowave `style_primary_button` / `style_secondary_button`, `ACTION_MODE_BUTTON_PRESS`, `arm_pending_sheet`, `_campaign_peace_choose` applies (`apply_player_choice` then `apply_outcome` fallback) + logs `MAIN_FIX1_PEACE_BTN` + closes once.

## Camera (Esc + Prod + Leaders)

`MapRenderer._handle_escape_key` does not pan. Home / End / **B** (fronts centroid) / `_center_camera_on_province` do. Not an Esc-handler bug — no code change.

## Play hooks (dev-only, off by default)

- `EOA_MAIN_FIX1_FORCE_CAPTURE=1` — GER takes one POL border province through `_apply_attacker_win_capture_light`.
- `EOA_MAIN_FIX1_PEACE_HOLD_S=600` — open the campaign peace sheet and hold ≥600 s (`max(env, 600)`).
- Wrapper: `tools/eoa_main_fix1_play_hooks.sh --force-capture` / `--peace-hold`. Never turns the flags on by itself.

## Constraints held

- Never renumber `world_full` IDs
- No new residual dual packages
- No GameData rewrite (`git diff origin/grok/main-fix-1 -- scripts/autoload/GameData.gd` empty)
- Godot only via `tools/run_godot.sh` (4.7.1.rc2)
- `--quick` same 14 known `unit_board_play_path` reds (`Ran 374` / `FAILED (failures=14)`). A skip-comment `"must not instantly"` briefly tripped `land_battle_stance` `st not in` (16 reds); reworded; stance **ok**.
- map_qc NE **0.9853** (3148/3195)
- Seed 193601 `20fe9063` unedited (GameData / AI decision path untouched)
- 0 SCRIPT ERROR on current tip (ProdEsc / UI-POLISH-1 / PROD-1)
- No force push

## Tests

| Guard | Result |
|---|---|
| `HeadlessMainFix1ProdEscTest` | **RESULT=PASS** (failures=0) · 0 SCRIPT ERROR |
| `HeadlessMainFix1PeaceClickTest` | **RESULT=PASS** Annex all moved=1, Keep occupied moved=0, both closed |
| `WindowedMainFix1DeclareToastGuard` (xvfb, 10 in-game days) | **RESULT=PASS** Elbląski/Słupski stayed GER; skip=`ai_empty_hex_vs_player` pid 711080/711057; toast cards=0 |
| `HeadlessCampaignLoop1DeclareClickTest` | **RESULT=PASS** GER 421 / POL 53 unchanged; POL empty-hex vs GER 711057 skipped |
| `HeadlessCampaignLoop1WarGateTest` | **RESULT=PASS** |
| `HeadlessCampaignLoop1CapitulationPeaceTest` | **RESULT=PASS** |
| `HeadlessUiPolish1Test` (#114 keep-green) | **RESULT=PASS** (failures=0) · 0 SCRIPT ERROR |
| `HeadlessProd1ButtonOpenTest` (#112 keep-green) | **RESULT=PASS** (failures=0) · 0 SCRIPT ERROR |
| `tools/eoa_full_test_gates.sh --quick` | EXIT 1 · `Ran 374` · **FAILED (failures=14)** same known set (se_england 1, first_session 1, unit_centric_pick 3, unit_counter_chrome 2, unit_card_fill_toe 3, living_unit_order_loop 4). `land_battle_stance` **ok**. HOI open_p0=0 |
| `map_qc` | NE **0.9853** (3148/3195) |

Logs: `/tmp/main-fix-1/`.
