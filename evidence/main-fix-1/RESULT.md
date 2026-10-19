# MAIN-FIX-1 — Prod Esc, false capture notice, CL1 peace sheet

**Branch:** `grok/main-fix-1`  
**Base:** `origin/main` `d00dc8ed` (#114 UI-POLISH-1 + #113 CAMPAIGN-LOOP-1)  
**Code tip (tests ran on):** `eb4d546faeb7d85a8814072e67e93adc8aa14c57`  
**Draft PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/116  
**Merge:** HOLD  
**Date:** 2026-10-19

Playtest confirm on main came back MIXED (`uploads/RESULT.md` / `RESULT_01f1.md`).

## Root causes

### 1. Esc with Production open opened Command Center (BUG — fixed)

MapRenderer `_input` owns the live Esc stack (`_handle_escape_key`). After #114, Leaders / Agents / Space were dismissed before `_esc_open_command_center`. Production is a `DraggablePanel` whose Esc lives in `_unhandled_input`, which never ran because MapRenderer already consumed the key. Idle Esc therefore opened Command Center **on top of** the still-open Prod window (reproduced twice: `p3_prod_esc_closed`, `p5_prod_esc2_closed`).

**Fix:** `_handle_escape_key` dismisses `ProductionAssignmentScreen` via `_dismiss_named_overlay_screen` → `close_screen()` (rename `_dying` + `queue_free`, same class as Close). Prod is also on `_dismiss_map_overlays_esc`. Idle Esc still calls `_esc_open_command_center` → deferred `TopInfoBar._on_menu_pressed`.

### 2. `Province captured · POL vs GER at Słupski` after diplomatic Declare (likely false notice — fixed)

Unique format is `BattleManager._post_battle_news`: title `Province captured`, body `"%s vs %s at %s"`. `WarStateDomain.player_declare_from_province` is diplomatic-only (`declare_war` + `invalidate_fronts` cache clear). Light capture / `apply_combat_outcome` toasted capture whenever that path ran, including a same-owner / controller-only flip (`update_province_owner` with the current owner). Słupski stayed POL-owned; no march/assault/battle log line.

**Fix:** record `previous_owner_tag` before the owner write. Post the capture toast only when previous owner ≠ attacker **and** live `owner_tag` is the attacker. Same-owner light capture posts nothing (not a fallback `Battle:` toast).

### 3. CL1 peace sheet logged but not drawn (investigate; small UI only)

`CapitulationDomain._open_sheet` → `PeaceConferenceWindow._open_campaign_peace_sheet` **does** add a `CanvasLayer` 124 `CampaignPeaceSheet`. Two reasons nothing readable showed on the CL1 hook path:

1. **Panel size (0,0) + no StyleBox.** `custom_minimum_size` 480×220 was set but `size` stayed (0,0) and the default Panel is unstyled — invisible on the GIS map. **Small fix applied:** explicit `size = Vector2(480, 220)` + opaque `StyleBoxFlat` + title chrome (same class as `CampaignEndScreen` panel).
2. **Victory dismiss (not rewritten).** `CampaignEndScreen.present` (layer 125) `_dismiss_overlays` queue_frees `campaign_peace_sheet`. The two_majors hook latches Victory on the second major, so the sheet is created then immediately destroyed. That is campaign-end behavior, not a peace-sheet UI bug; left as-is.

Headless `_open_campaign_peace_sheet` still returns the dict without drawing (`DisplayServer.get_name() == "headless"`), which is why the log line exists in CL1 tests.

## Constraints held

- Never renumber `world_full` IDs — unedited vs `d00dc8ed`
- No new residual dual packages
- No GameData rewrite — `scripts/autoload/GameData.gd` unedited vs `d00dc8ed` (seed path unchanged; `multi_ai_decisions` md5 stays `20fe9063`)
- No Godot bump; Godot only via `tools/run_godot.sh` → `4.7.1.rc2.official.d6096250e`
- `--quick` same 14 known `unit_board_play_path` reds (`Ran 374 tests` / `FAILED (failures=14)`)
- map_qc NE **0.9853** (3148/3195)
- 0 SCRIPT ERROR in all Godot logs below
- No force push

## Tests

Godot: `tools/run_godot.sh` 4.7.1-rc2. Logs under `/tmp/main-fix-1/`.

| Check | Result |
|-------|--------|
| Code tip | `eb4d546faeb7d85a8814072e67e93adc8aa14c57` |
| `HeadlessMainFix1ProdEscTest` | **PASS** (failures=0) — Esc closed Prod without CC; idle Esc opened CC |
| `HeadlessCampaignLoop1DeclareClickTest` | **PASS** (failures=0) — on declare GER 421 / POL 53 unchanged, capture news +0; same-owner POL light capture at `711054` silent; after 3 days still +0 |
| `HeadlessCampaignLoop1WarGateTest` | **PASS** (failures=0) |
| `HeadlessCampaignLoop1CapitulationPeaceTest` | **PASS** (failures=0) |
| Soak `HeadlessCampaignLoop1SoakTest` | **PASS** (failures=0) S3 victory day 39 |
| `HeadlessCampaignLoop1TopBarFitTest` | **PASS** (failures=0) |
| `HeadlessUiPolish1Test` | **PASS** (failures=0) |
| `HeadlessProd1ButtonOpenTest` | **PASS** (failures=0) |
| `HeadlessUi1LeadersEdgePanMarchTest` | **PASS** (failures=0) |
| `--quick` | exit 1 · **14** known `unit_board_play_path` reds · `unit_save_path` OK · `map_qc` OK · `hoi_matrix` OK · `air_physics_p1` OK |
| map_qc NE | **0.9853** (3148/3195) |
| SCRIPT ERROR | **0** |
| Seed 193601 | GameData unedited; prefix **`20fe9063`** |

DeclareClick capture lines:

```
[PASS] on declare no capture notice (GER 421 / POL 53 unchanged, news +0)
[PASS] same-owner POL light capture at 711054 posted no capture notice
[PASS] after 3 days no capture notice (GER 421 / POL 53 unchanged, news +0)
```
