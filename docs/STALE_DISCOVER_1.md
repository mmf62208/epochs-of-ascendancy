# STALE-DISCOVER-1

Retarget of pre-existing `python3 -m unittest discover tools/map_generation/tests` pins. Product behavior is unchanged. This slice does not clear the deferred discover failures and does not wire these tests into `tools/eoa_full_test_gates.sh`.

Base: `e0388c58fb3a72d38084a9ff812a4d99d518e543`. Measured on that tree before edits: 13 in-scope failures, `test_names1` already PASS (full clone can `git show 5d099346`).

## In scope (was FAIL, retargeted)

| Id | Was looking at | Now requires |
|----|----------------|--------------|
| `test_combat_equip_shortage` … `test_production_manager_formation_combat_and_reinforce_apis` | First 350 chars of `ProductionManager._on_game_day_advanced` (the light-path return hides the tick) | Whole function body: `daily_production_tick()` and `daily_formation_reinforce_from_stockpile()` (`ProductionManager.gd` around 3864–3893) |
| `test_designer_domain_live_product.TestLive.test_docs` | Phrases in root `TODO.md`, `Project_State_Summary.md`, `Next_30_Days_Roadmap.md`, `GAME_STATUS_ASSESSMENT.md` | `OrderCommandPanel` title `Designer domain live (major #33)`, `GameData.apply_designer_domain_seed_live`, `ScenarioLoader` `phase3_depth_live` |
| `test_manpower_cohort_reserve_product.TestLive.test_docs` | Same four catalogues | Panel `Manpower cohort/reserve (major #36)`, `GameData.apply_manpower_cohort_live`, `phase4_depth_live` |
| `test_manpower_laws_training_product.TestLive.test_docs` | Same four catalogues | Panel `Manpower laws/training (major #30)`, `GameData.apply_manpower_law_live` and `apply_manpower_training_tick_live`, `phase2_conquest_live` |
| `test_next20_integration` … `test_gd_cross_system_call_sites` | Comment `Sole mult: trade_supply_weather_chain` in `TradeManager.gd` | Inside `advance_trade_flows`: `MapPolishFormatters.trade_supply_weather_chain(sea_trade, "dry", clampf(1.0 - wx_trade…)` and one `amount *= float(chain.get("health", 1.0))`. File still must not contain `amount *= sea_trade` or `amount *= wx_trade` |
| `test_next20_ops_depth` … `test_gd_multi_province_and_order_panel` | First 90000 chars of `GameData.apply_order_panel_action` | Whole function, including `return apply_production_priority_mutation("primary", "primary")` (call is inside the function, past the old window; definition stays earlier in `GameData.gd`) |
| `test_next20_priority_systems` … `test_gd_priority_surfaces_and_panel` | Panel labels `Industry / economy` and `Save slots` (`Agent AI` already had a live fallback) | Panel calls `industry_economy_depth_for_province` / `format_industry_economy_plain` / `industry_economy_day`, `save_slot_browser_day`, and `agent_campaign_depth_day` plus `apply_agent_dispatch` |
| `test_next20_product_depth` … `test_gd_surfaces_and_docs` | Panel label `Agent AI` | Panel `format_agent_ai_board_day_plain`, button `agent_ai_board_day`, `apply_agent_dispatch`. Formatter still labels `Agent AI board` |
| `test_next20_week2_core_polish` … `test_wiring` | `format_day_package_apply_audit_plain` and `format_save_slot_flair_plain` in `OrderCommandPanel.gd` | Those functions in `GameData.gd`: audit body calls `MapPolishFormatters.day_package_apply_audit(`. Flair body calls `SaveLoadManager.list_slots_for_ui()` and `MapPolishFormatters.save_slot_browser_flair(`. Panel still has `flair_label` |
| `test_slot_save_ui_gis_sea_control` … `test_shipped_wiring_detailed_apis` | `load_game_detailed` in `TopInfoBar.gd` | `func load_game_detailed` stays in `SaveLoadManager.gd`. Call sites: `MainMenu` `slm.call("load_game_detailed", slot)` and `LivingTitleBoot` `SaveLoadManager.load_game_detailed(slot)`. Top bar still lists slots and calls `save_game_detailed` |
| `test_stream_alpha_primary_packs_product` … `test_stack` | `apply_save_browser_resume` in `TopInfoBar.gd` | `GameData` routes `aid == "apply_save_browser_resume"` / `checkpoint` to `return apply_save_browser_resume()` / `checkpoint()`. Panel buttons `Save resume` / `Save checkpoint`. Formatter map `"save_browser_resume": "apply_save_browser_resume"` and `"save_checkpoint": "apply_save_browser_checkpoint"` |
| `test_relabel_strategic_regions` … `test_road_layer_earlier_zoom` | One line `road_layer.visible = show_roads and z > 0.10`, plus a `1.15` arterial width multiplier in the same file | Split expression in `InfrastructureOverlayLayer._update_sub_layer_visibilities`: `show_roads or _road_layer_has_explicit_lines() or not _road_edge_cache.is_empty()` and `z > 0.10`. Rail stays `rail_layer.visible = show_rails and z > 0.14`. Width pin is `ROAD_EXPLICIT_SCREEN_PX` (7) via `_road_world_width`, `RoadTierVisual.HIGHWAY_SCREEN_PX`, and `screen_width_for_tier` (highway casing 12 vs dirt 2.6). Zoom thresholds unchanged |
| `test_world_class_map_review_docs` … `test_live_membership_matches_review_numbers` | `base_n >= 5000` | `base_n == 3596`. Other asserts already held |

`docs/WORLD_CLASS_MAP_REVIEW.md` was not edited. Its scale line already says ~3520, not a 5000+ accurate board. Historical 8761 sentences stay.

## Measured accurate-board pins (e0388c58)

| Pin | Value |
|-----|-------|
| `provinces_base` `base_n` | 3596 |
| `province_to_region` region ids | 31 |
| `province_to_state` state ids | 429 |
| land (`len(province_to_state)`) | 3256 (= 3596 − 340) |
| seas | 340 |

## names1

`TestNames1Board` already PASSes here because `git show 5d099346:data/provinces_world_accurate/provinces_base.json` works on this clone. Happy path left unchanged. No fixture added.

## Deferred (untouched, still FAIL)

- `test_live_membership_mutation_product` (integrity + cross_region): province 40140 region/super `5 != 2`
- `test_rebuild_strategic_regions` … `test_world_full_rebalanced_share`: world_full share `0 not >= 8`
- `test_world_accurate_campaign_feel` hierarchy scaffold: province coverage set difference
- `test_world_full_post_capture_acquired_design_fielding`, `test_world_full_post_capture_defender_displace`, `test_world_full_post_capture_seized_factory_production`
- `test_world_hotspots_and_cities` … `test_shipped_cities_near_anchors`
- `test_world_ownership_1936` … `test_payload_file_matches_scenario_owners` (`ENG` != `FRA`)

`tools/map_generation/tests/test_gap_usa1.py` is unmodified (open #208).
