# Epochs of Ascendancy — TODO

> **L1 war loop (2026-08-16, machine):** pick → march hops → multi-day battle → AAR/NEXT · **AI `start_land_battle` (1/day)** · **`land_war` save** (open fights + marches). Human M6 20d/60d notes still open. Truth → [`docs/GAME_STATUS_SNAPSHOT.md`](docs/GAME_STATUS_SNAPSHOT.md).

> **Playtest cycle (2026-07-17):** freeze new residual dual packages · human playlists · launch commands → [`docs/PLAYTEST_AND_DECISION_GUIDE.md`](docs/PLAYTEST_AND_DECISION_GUIDE.md) · status → [`GAME_STATUS_ASSESSMENT.md`](GAME_STATUS_ASSESSMENT.md)


> **Program roadmap (all pillars, phased, no permanent deferrals):** [`docs/MASTER_COMPLETION_PLAN.md`](docs/MASTER_COMPLETION_PLAN.md)  
> **Cursor prompt packs:** same doc §8. Feed Pack A + one task pack per session.

## Launch team 2026-07-15…16 (pure products + dual-green packages)

### Dual-green (world_full SCRIPT ERROR 0 + live markers — do not invent)

- [x] **Stream α primary (C1/P1/S1/L1)** — pure `stream_alpha_primary_command_product` + GD dual · `stream_alpha_primary_live=1 majors_ok=4 dead_n=0 ticks=14 ok=true` · qa dual2 + skeptic ACCEPT · OrderCommandPanel `_rebuild_stream_alpha_primary_command`
- [x] **C2 fleet autonomy primary** — pure `fleet_autonomy_primary_command_product` + GD dual · `fleet_autonomy_primary_live=1 majors_ok=4 dead_n=0 ticks=4 ok=true` · c2_gd dual + skeptic_wave2 ACCEPT · real `apply_fleet_day_*` / `apply_naval_ops_close_live`
- [x] **Di1 peace conference primary** — pure `peace_conference_primary_command_product` + GD dual · `peace_conference_primary_live=1 majors_ok=5 dead_n=0 ticks=5 ok=true` · di1_gd dual · open·claim·cede·puppet·close
- [x] **O1 occupation primary** — pure `occupation_primary_command_product` + GD dual · `occupation_primary_live=1 majors_ok=5 dead_n=0 ticks=5 ok=true` · o1_gd dual · mapmode·law·garrison·pulse·close
- [x] **N1 hotseat turn banner** — pure `hotseat_turn_banner_product` + SessionPlayers helpers + GD dual · `hotseat_turn_banner_live=1 locked=true active=USA ok=true` · n1_m3_dual dual3 + skeptic_wave2 ACCEPT · lock audit via `is_command_allowed_for_tag` · **hotseat only** (N3 network still open)
- [x] **M3 FPS harness dual honest-empty** — pure `map_perf_fps_harness_product` + GD dual crumb · `map_perf_fps_harness_live=1 measured=0 empty=true status=EMPTY ok=true` · n1_m3_dual dual3 + skeptic_wave2 ACCEPT · **no fake FPS**
- [x] **T1 research queue primary** — pure `research_queue_primary_command_product` + GD dual · `research_queue_primary_live=1 majors_ok=5 dead_n=0 ticks=5 ok=true` · final_skeptic dual_final ACCEPT · real tech catalog/branch/priority/close APIs · **no apply_focus**
- [x] **I1 agent mission board primary** — pure `agent_mission_board_primary_command_product` + GD dual · `agent_mission_board_primary_live=1 majors_ok=5 dead_n=0 ticks=5 ok=true` · final_skeptic dual_final ACCEPT · real agent board/dispatch/missions/counter/close APIs · **no apply_focus**
- [x] **E1 war economy primary** — pure `war_economy_primary_command_product` + GD dual · `war_economy_primary_live=1 majors_ok=5 dead_n=0 ticks=5 ok=true` · post-E1 dual×2 under goal SCRATCH · board·civ↔war·stockpile·close · sustain leaf **`apply_production` only** (fixed: was deep `apply_focus` via `apply_economy_conversion_live`) · routing test `test_economy_conversion_live_sustain_no_apply_focus`

### Sprint 2026-07-16 — residual high-value (C3 / C4 / N2)

- [x] **C3 air theater primary** — pure `air_theater_primary_command_product` + GD dual · `air_theater_primary_live=1 majors_ok=4 dead_n=0 ticks=4 ok=true` · real `apply_air_theater_*` / close day · OrderCommandPanel C3 section
- [x] **C4 battle AAR primary** — pure `battle_aar_primary_command_product` + GD dual · `battle_aar_primary_live=1 majors_ok=5 entry_n≥1` · multi-phase + combat_ops_close + phase_engage + `apply_battle_aar_persist/close_live` · no apply_focus
- [x] **N2 command journal** — pure `command_journal_primary_command_product` + SessionPlayers seed/enqueue/flush + GD dual · `command_journal_primary_live=1 majors_ok=5 verify=true` · batch **never** enqueues `apply_focus` · **honest verify**: pre-flush journal fingerprint vs post-flush applied trail (`fingerprint_command_journal` / `fingerprint_commands`); mutated trail fails pure tests

### Sprint residual 2026-07-16 — M3 measured · Di2 · P2

- [x] **M3 measured FPS primary** — pure `map_perf_measured_primary_command_product` + GD dual · `map_perf_measured_primary_live=1 measured=8 measured_ok=true source=performance_monitor` · real `Performance.TIME_PROCESS` / MapRenderer samples · empty still honest (no invent FPS)
- [x] **Di2 war goal + alliance primary** — pure `war_goal_alliance_primary_command_product` + GD dual · `war_goal_alliance_primary_live=1 majors_ok=5` · real war_goal_* + alliance_guarantee APIs · no apply_focus
- [x] **P2 factory retool primary** — pure `factory_retool_primary_command_product` + GD dual · `factory_retool_primary_live=1 majors_ok=5` · honesty/risk/horizon80/prove60/close · no apply_focus


### Sprint U1 / A3 / G0 — 2026-07-16

- [x] **U1 tutorial first-session primary** — pure `tutorial_first_session_primary_command_product` + GD dual · `tutorial_first_session_primary_live=1 majors_ok=5 g0_domain=TutorialSessionDomain` · brief·guide·checkpoint·product·close
- [x] **A3 multi-faction AI primary** — pure `multi_faction_ai_primary_command_product` + GD dual · `multi_faction_ai_primary_live=1 majors_ok=5` · scan·rank·execute·multi_faction·close · doctrine tags
- [x] **G0 TutorialSessionDomain** — `scripts/core/TutorialSessionDomain.gd` owns package state; GameData public API stable · dual green


### Sprint W1 / O2 / G0 MultiFactionAIDomain — 2026-07-16

- [x] **W1 weather theater primary** — pure `weather_theater_primary_command_product` + GD dual · `weather_theater_primary_live=1 majors_ok=5` · pressure·gate·crisis·product·close
- [x] **O2 manpower laws primary** — pure `manpower_laws_primary_command_product` + GD dual · `manpower_laws_primary_live=1 majors_ok=5` · law·train·cohorts·mobilize·close
- [x] **G0 MultiFactionAIDomain** — `scripts/core/MultiFactionAIDomain.gd` owns multi_faction_ai_primary state · dual A3 still green


### Sprint T2 / L2 / G0 WeatherTheaterDomain — 2026-07-16

- [x] **T2 focus tree primary** — pure `focus_tree_primary_command_product` + GD dual · `focus_tree_primary_live=1 majors_ok=5` · catalog·path·commit·product·close
- [x] **L2 leader theater primary** — pure `leader_theater_primary_command_product` + GD dual · `leader_theater_primary_live=1 majors_ok=5` · hq·station·ops·product·close
- [x] **G0 WeatherTheaterDomain** — `scripts/core/WeatherTheaterDomain.gd` owns weather_theater_primary state · dual W1 still green

### Sprint I2 / U2 / G0 ManpowerLawsDomain — 2026-07-16

- [x] **I2 intel network primary** — pure `intel_network_primary_command_product` + GD dual · `intel_network_primary_live=1 majors_ok=5 dead_n=0 ticks=5 ok=true` · coverage·counterintel·counterplay·product·close · real intel APIs · **no apply_focus** as step live_api
- [x] **U2 product UX primary** — pure `product_ux_primary_command_product` + GD dual · `product_ux_primary_live=1 majors_ok=5 dead_n=0 ticks=5 ok=true` · compact·chips·hotkeys·product·close
- [x] **G0 ManpowerLawsDomain** — `scripts/core/ManpowerLawsDomain.gd` owns manpower_laws_primary state · dual O2 still green · routing `test_sprint_i2_u2_g0_routing.py`

### Sprint I2b / E2 / G0 FocusTreeDomain — 2026-07-16

- [x] **I2b combat intel estimate primary** — pure `combat_intel_estimate_primary_command_product` + GD dual · `combat_intel_estimate_primary_live=1 majors_ok=5 dead_n=0 impact=true` · estimate·recon·sabotage·product·close · bias visible on estimate path · **no apply_focus** step live_api
- [x] **E2 convoy sealane primary** — pure `convoy_sealane_primary_command_product` + GD dual · `convoy_sealane_primary_live=1 majors_ok=5 dead_n=0` · escort·sealane·joint·trade·close
- [x] **G0 FocusTreeDomain** — `scripts/core/FocusTreeDomain.gd` owns focus_tree_primary state · dual T2 still green · routing `test_sprint_i2b_e2_g0_routing.py`

### Sprint D1 / S2 / G0 LeaderTheaterDomain — 2026-07-16

- [x] **D1 designer suite primary** — pure `designer_suite_primary_command_product` + GD dual · `designer_suite_primary_live=1 majors_ok=5 dead_n=0` · catalog·pick·seed·product·close · real designer suite APIs · **no apply_focus** step live_api
- [x] **S2 autosave session primary** — pure `autosave_session_primary_command_product` + GD dual · `autosave_session_primary_live=1 majors_ok=5 dead_n=0` · browser·autosave·resume·checkpoint·close
- [x] **G0 LeaderTheaterDomain** — `scripts/core/LeaderTheaterDomain.gd` owns leader_theater_primary state · dual L2 still green · routing `test_sprint_d1_s2_g0_routing.py`

### Sprint X1 / I3 / G0 IntelNetworkDomain — 2026-07-16

- [x] **X1 historical OOB primary** — pure `historical_oob_primary_command_product` + GD dual · `historical_oob_primary_live=1 majors_ok=5 dead_n=0` · catalog·seed·equip·product·close · **no apply_focus** step live_api
- [x] **I3 intel counter primary** — pure `intel_counter_primary_command_product` + GD dual · `intel_counter_primary_live=1 majors_ok=5 dead_n=0` · counterintel·sweep·counterplay·cell ops·close (product-style leaves; heavy day queues avoided)
- [x] **G0 IntelNetworkDomain** — `scripts/core/IntelNetworkDomain.gd` owns intel_network_primary state · dual I2 still green · routing `test_sprint_x1_i3_g0_routing.py`

### Sprint A4 / P3 / G0 DesignerSuiteDomain — 2026-07-16

- [x] **A4 faction personality primary** — pure `faction_personality_primary_command_product` + GD dual · `faction_personality_primary_live=1 majors_ok=5 dead_n=0` · board·event·drive·product·close · **no apply_focus** step live_api
- [x] **P3 production honesty primary** — pure `production_honesty_primary_command_product` + GD dual · `production_honesty_primary_live=1 majors_ok=5 dead_n=0` · honesty product·prove60·prove100·oob·close
- [x] **G0 DesignerSuiteDomain** — `scripts/core/DesignerSuiteDomain.gd` owns designer_suite_primary state · dual D1 still green · routing `test_sprint_a4_p3_g0_routing.py`

### Sprint HH multi-month / logistics supply / G0 FactoryRetoolDomain — 2026-07-16

- [x] **HH multi-month primary** — pure `hh_multi_month_primary_command_product` + GD dual · `hh_multi_month_primary_live=1 majors_ok=5 dead_n=0` · product·trail·brief·sequence·close · product-style HH leaves · **no apply_focus** step live_api
- [x] **Logistics supply primary** — pure `logistics_supply_primary_command_product` + GD dual · `logistics_supply_primary_live=1 majors_ok=5 dead_n=0` · product·route·sustain·readiness·close
- [x] **G0 FactoryRetoolDomain** — `scripts/core/FactoryRetoolDomain.gd` owns factory_retool_primary state · dual P2 still green · routing `test_sprint_hh_log_g0_routing.py`

### Sprint front continuity / designer depth / G0 LogisticsSupplyDomain — 2026-07-16

- [x] **Front continuity primary** — pure `front_continuity_primary_command_product` + GD dual · `front_continuity_primary_live=1 majors_ok=5 dead_n=0` · campaign·combat·assault·sustain·close · **no apply_focus** step live_api
- [x] **Designer depth primary** — pure `designer_depth_primary_command_product` + GD dual · `designer_depth_primary_live=1 majors_ok=5 dead_n=0` · module·board·stats·multi·close
- [x] **G0 LogisticsSupplyDomain** — `scripts/core/LogisticsSupplyDomain.gd` owns logistics_supply_primary state · dual LOG still green · routing `test_sprint_fc_dd_g0_routing.py`

### Sprint air multi-phase / inspector decision / G0 FrontContinuityDomain — 2026-07-16

- [x] **Air multi-phase primary** — pure `air_multi_phase_primary_command_product` + GD dual · `air_multi_phase_primary_live=1 majors_ok=5 dead_n=0` · product·sortie·weather·airland·close · **no apply_focus** step live_api
- [x] **Inspector decision primary** — pure `inspector_decision_primary_command_product` + GD dual · `inspector_decision_primary_live=1 majors_ok=5 dead_n=0` · decision·primary·collapse·apply·close
- [x] **G0 FrontContinuityDomain** — `scripts/core/FrontContinuityDomain.gd` owns front_continuity_primary state · dual FC still green · routing `test_sprint_amp_ins_g0_routing.py`

### Sprint balance combat-supply / fleet multi-day / G0 AirMultiPhaseDomain — 2026-07-16

- [x] **Balance combat/supply primary** — pure `balance_combat_supply_primary_command_product` + GD dual · `balance_combat_supply_primary_live=1 majors_ok=5 dead_n=0` · product·estimate·sample·variance·close · **no apply_focus** step live_api
- [x] **Fleet multi-day primary** — pure `fleet_multi_day_primary_command_product` + GD dual · `fleet_multi_day_primary_live=1 majors_ok=5 dead_n=0` · product·posture·escort·follow·sequence
- [x] **G0 AirMultiPhaseDomain** — `scripts/core/AirMultiPhaseDomain.gd` owns air_multi_phase_primary state · dual AMP still green · routing `test_sprint_bal_fmd_g0_routing.py`

### Sprint agent campaign / GS cycle primary / G0 FleetMultiDayDomain — 2026-07-16

- [x] **Agent campaign primary** — pure `agent_campaign_primary_command_product` + GD dual · `agent_campaign_primary_live=1 majors_ok=5 dead_n=0` · board·dispatch·counterplay·sequence·product · **no apply_focus** step live_api
- [x] **Grand strategy cycle primary** — pure `grand_strategy_cycle_primary_command_product` + GD dual · `grand_strategy_cycle_primary_live=1 majors_ok=5 dead_n=0` · product·scan·rank·execute·close
- [x] **G0 FleetMultiDayDomain** — `scripts/core/FleetMultiDayDomain.gd` owns fleet_multi_day_primary state · dual FMD still green · routing `test_sprint_acp_gsc_g0_routing.py`

### Sprint world-class / multi-front primary / G0 BalanceDomain — 2026-07-16

- [x] **World-class campaign primary** — pure `world_class_primary_command_product` + GD dual · `world_class_primary_live=1 majors_ok=5 dead_n=0` · product·scan·rank·execute·close · **no apply_focus** step live_api
- [x] **Multi-front campaign AI primary** — pure `multi_front_primary_command_product` + GD dual · `multi_front_primary_live=1 majors_ok=5 dead_n=0` · product·plan·weekly·execute·close
- [x] **G0 BalanceDomain** — `scripts/core/BalanceDomain.gd` owns balance_combat_supply_primary state · dual BAL still green · routing `test_sprint_wcc_mfc_g0_routing.py`

### Sprint strategic war-goal / naval search-strike / G0 ProductUxDomain — 2026-07-16

- [x] **Strategic war-goal primary** — pure `strategic_war_goal_primary_command_product` + GD dual · `strategic_war_goal_primary_live=1 majors_ok=5 dead_n=0` · product·board·justify·execute·close · **no apply_focus** (distinct from war_goal_alliance_primary)
- [x] **Naval search/strike primary** — pure `naval_search_strike_primary_command_product` + GD dual · `naval_search_strike_primary_live=1 majors_ok=5 dead_n=0` · product·patrol·asw·strike·close
- [x] **G0 ProductUxDomain** — `scripts/core/ProductUxDomain.gd` owns product_ux_primary state · dual UX still green · routing `test_sprint_swg_nss_g0_routing.py`

### Sprint weather crisis / campaign AI multi-month / G0 ConvoySealaneDomain — 2026-07-16

- [x] **Weather crisis primary** — pure `weather_crisis_primary_command_product` + GD dual · `weather_crisis_primary_live=1 majors_ok=5 dead_n=0` · product·forecast·gate·sustain·close · **no apply_focus**
- [x] **Campaign AI multi-month primary** — pure `campaign_ai_multi_month_primary_command_product` + GD dual · `campaign_ai_multi_month_primary_live=1 majors_ok=5 dead_n=0` · product·board·weekly·execute·close
- [x] **G0 ConvoySealaneDomain** — `scripts/core/ConvoySealaneDomain.gd` owns convoy_sealane_primary state · dual CS still green · routing `test_sprint_wcr_cam_g0_routing.py`

### Sprint tech research / focus war-path / G0 HistoricalOobDomain — 2026-07-16

- [x] **Tech research primary** — pure `tech_research_primary_command_product` + GD dual · `tech_research_primary_live=1 majors_ok=5 dead_n=0` · product·catalog·priority·field·close · **no apply_focus**
- [x] **Focus war-path primary** — pure `focus_war_path_primary_command_product` + GD dual · `focus_war_path_primary_live=1 majors_ok=5 dead_n=0` · product·pick·path·commit·close
- [x] **G0 HistoricalOobDomain** — `scripts/core/HistoricalOobDomain.gd` owns historical_oob_primary state · dual HOB still green · routing `test_sprint_trc_fwp_g0_routing.py`

### Sprint naval multi-phase / diplomacy-peace / G0 InspectorDecisionDomain — 2026-07-16

- [x] **Naval multi-phase primary** — pure `naval_multi_phase_primary_command_product` + GD dual · `naval_multi_phase_primary_live=1 majors_ok=5 dead_n=0` · product·posture·escort·strike·close · **no apply_focus**
- [x] **Diplomacy/peace primary** — pure `diplomacy_peace_primary_command_product` + GD dual · `diplomacy_peace_primary_live=1 majors_ok=5 dead_n=0` · product·board·leverage·settle·close
- [x] **G0 InspectorDecisionDomain** — `scripts/core/InspectorDecisionDomain.gd` owns inspector_decision_primary state · dual INS still green · routing `test_sprint_nmp_dpc_g0_routing.py`

### Sprint save-resume / play-session / G0 ProductionHonestyDomain — 2026-07-16

- [x] **Save/resume primary** — pure `save_resume_primary_command_product` + GD dual · `save_resume_primary_live=1 majors_ok=5 dead_n=0` · product·checkpoint·save·resume·close · **no apply_focus**
- [x] **Play-session primary** — pure `play_session_primary_command_product` + GD dual · `play_session_primary_live=1 majors_ok=5 dead_n=0` · product·brief·execute·resolve·close
- [x] **G0 ProductionHonestyDomain** — `scripts/core/ProductionHonestyDomain.gd` owns production_honesty_primary state · dual PH still green · routing `test_sprint_srp_psc_g0_routing.py`

### Sprint G0 Occupation / PeaceConference / CommandJournal domains — 2026-07-16

- [x] **G0 OccupationDomain** — `scripts/core/OccupationDomain.gd` commits occupation_primary state · dual `occupation_primary_live=1 majors_ok=5`
- [x] **G0 PeaceConferenceDomain** — `scripts/core/PeaceConferenceDomain.gd` commits peace_conference_primary state · dual `peace_conference_primary_live=1 majors_ok=5`
- [x] **G0 CommandJournalDomain** — `scripts/core/CommandJournalDomain.gd` owns command_journal_primary state · dual `command_journal_primary_live=1 majors_ok=5 verify=true` · routing `test_sprint_occ_pc_cj_g0_routing.py`

### Sprint G0 BattleAar / WarEconomy / MapPerfMeasured domains — 2026-07-16

- [x] **G0 BattleAarDomain** — `scripts/core/BattleAarDomain.gd` owns battle_aar_primary · dual `battle_aar_primary_live=1 majors_ok=5 entry_n≥1`
- [x] **G0 WarEconomyDomain** — `scripts/core/WarEconomyDomain.gd` owns war_economy_primary · dual `war_economy_primary_live=1 majors_ok=5`
- [x] **G0 MapPerfMeasuredDomain** — `scripts/core/MapPerfMeasuredDomain.gd` owns map_perf_measured_primary · dual `map_perf_measured_primary_live=1 majors_ok=5 measured_ok=true source=performance_monitor` · routing `test_sprint_baa_we_mp_g0_routing.py`

### Sprint G0 AgentMissionBoard / ResearchQueue / FactionPersonality domains — 2026-07-16

- [x] **G0 AgentMissionBoardDomain** — `scripts/core/AgentMissionBoardDomain.gd` owns agent_mission_board_primary · dual `agent_mission_board_primary_live=1 majors_ok=5`
- [x] **G0 ResearchQueueDomain** — `scripts/core/ResearchQueueDomain.gd` owns research_queue_primary · dual `research_queue_primary_live=1 majors_ok=5`
- [x] **G0 FactionPersonalityDomain** — `scripts/core/FactionPersonalityDomain.gd` owns faction_personality_primary · dual `faction_personality_primary_live=1 majors_ok=5` · routing `test_sprint_amb_rq_fp_g0_routing.py`

### Sprint G0 FleetAutonomy / WarGoalAlliance / IntelCounter domains — 2026-07-16

- [x] **G0 FleetAutonomyDomain** — `scripts/core/FleetAutonomyDomain.gd` owns fleet_autonomy_primary · dual `fleet_autonomy_primary_live=1 majors_ok=4` (4-major package)
- [x] **G0 WarGoalAllianceDomain** — `scripts/core/WarGoalAllianceDomain.gd` owns war_goal_alliance_primary · dual `war_goal_alliance_primary_live=1 majors_ok=5`
- [x] **G0 IntelCounterDomain** — `scripts/core/IntelCounterDomain.gd` owns intel_counter_primary · dual `intel_counter_primary_live=1 majors_ok=5` · routing `test_sprint_fa_wga_ic_g0_routing.py`

### Sprint G0 StreamAlpha / HhMultiMonth / AirTheater domains — 2026-07-16

- [x] **G0 StreamAlphaDomain** — `scripts/core/StreamAlphaDomain.gd` owns stream_alpha_primary · dual `stream_alpha_primary_live=1 majors_ok=4 dead_n=0 ticks=14`
- [x] **G0 HhMultiMonthDomain** — `scripts/core/HhMultiMonthDomain.gd` owns hh_multi_month_primary · dual `hh_multi_month_primary_live=1 majors_ok=5`
- [x] **G0 AirTheaterDomain** — `scripts/core/AirTheaterDomain.gd` owns air_theater_primary · dual `air_theater_primary_live=1 majors_ok=4` · routing `test_sprint_sa_hh_at_g0_routing.py`

### Sprint G0 AgentCampaign / GrandStrategyCycle / WorldClass domains — 2026-07-16

- [x] **G0 AgentCampaignDomain** — `scripts/core/AgentCampaignDomain.gd` owns agent_campaign_primary · dual `agent_campaign_primary_live=1 majors_ok=5`
- [x] **G0 GrandStrategyCycleDomain** — `scripts/core/GrandStrategyCycleDomain.gd` owns grand_strategy_cycle_primary · dual `grand_strategy_cycle_primary_live=1 majors_ok=5`
- [x] **G0 WorldClassDomain** — `scripts/core/WorldClassDomain.gd` owns world_class_primary · dual `world_class_primary_live=1 majors_ok=5` · routing `test_sprint_acp_gsc_wcc_g0_routing.py`

### Sprint residual G0 queue (14 packages) — 2026-07-16

- [x] **G0 residual package domains** — CombatIntelEstimate · AutosaveSession · DesignerDepth · MultiFront · StrategicWarGoal · NavalSearchStrike · WeatherCrisis · CampaignAiMultiMonth · TechResearch · FocusWarPath · NavalMultiPhase · DiplomacyPeace · SaveResume · PlaySession · dual×2 `*_primary_live=1 majors_ok=5` (CIE impact=true) SCRIPT ERROR 0 · routing `test_sprint_residual_g0_queue_routing.py`

### Sprint AI difficulty primary residual — 2026-07-16

- [x] **AI difficulty primary** — pure `ai_difficulty_primary_command_product` + `AiDifficultyDomain` + GD dual · `ai_difficulty_primary_live=1 majors_ok=5 preset=hard ok=true` · catalog·easy·normal·hard·close · real personality/strategic AI leaves · **no apply_focus**

### Sprint residual 350k — hotseat session · Pack N era · M3 density measured — 2026-07-16

- [x] **Hotseat session primary** — pure `hotseat_session_primary_command_product` + `HotseatSessionDomain` + GD dual · `hotseat_session_primary_live=1 majors_ok=5` · lobby·banner·rotate·lock·close · **not N3**
- [x] **Pack N era primary (thin)** — pure `pack_n_era_primary_command_product` + `PackNEraDomain` + GD dual · `pack_n_era_primary_live=1 majors_ok=5 era_n=2` · catalog·1936·1918·equip·close
- [x] **M3 density pilot measured dual** — `map_perf_density_pilot_live=1 pilot=density measured≥1 measured_ok=true source=performance_monitor` on `EOA_SCENARIO=world_pilot_global_density` dual×2 SCRIPT 0

### Sprint residual 300k — Pack N events · HOI panel · Q1 validator — 2026-07-16

- [x] **Pack N events/focus primary** — pure `pack_n_events_primary_command_product` + `PackNEventsDomain` + GD dual · `pack_n_events_primary_live=1 majors_ok=5` · catalog·path·war_pick·commit·close
- [x] **HOI panel polish primary** — pure `hoi_panel_primary_command_product` + `HoiPanelDomain` + GD dual · `hoi_panel_primary_live=1 majors_ok=5` · compact·chips·inspector·apply·close
- [x] **Q1 validator honesty primary** — pure `q1_validator_primary_command_product` + `Q1ValidatorDomain` + GD dual · `q1_validator_primary_live=1 majors_ok=5` · balance·estimate·sample·honesty·close
- [x] **Combat/production partial primary** — pure `combat_production_partial_primary_command_product` + `CombatProductionPartialDomain` + GD dual · `combat_production_partial_primary_live=1 majors_ok=5` · estimate·combat·prod·oob·close

### Sprint residual major open items depth — 2026-07-16

- [x] **Pack N narrative primary** — pure `pack_n_narrative_primary_command_product` + `PackNNarrativeDomain` + GD dual · `pack_n_narrative_primary_live=1 majors_ok=5` · event·catalog·path·commit·close
- [x] **HOI screen depth primary** — pure `hoi_screen_primary_command_product` + `HoiScreenDomain` + GD dual · `hoi_screen_primary_live=1 majors_ok=5` · hotkeys·polish·primary·collapse·close
- [x] **Q1 checklist depth primary** — pure `q1_checklist_primary_command_product` + `Q1ChecklistDomain` + GD dual · `q1_checklist_primary_live=1 majors_ok=5` · balance·variance·prove60·prove100·close
- [x] **Combat/production depth primary** — pure `combat_production_depth_primary_command_product` + `CombatProductionDepthDomain` + GD dual · `combat_production_depth_primary_live=1 majors_ok=5` · estimate·phase·joint·fleet·close
- [x] **N3 preflight primary (thin)** — pure `n3_preflight_primary_command_product` + `N3PreflightDomain` + GD dual · `n3_preflight_primary_live=1 majors_ok=5 netcode_ready=false not_full_n3=true` · lobby·seed·enqueue·flush·verify (majors only when live_result.ok) · **does not close N3**

### Sprint residual continue — Pack N content · HOI fullscreen · Q1 RC · combat engine depth — 2026-07-16

- [x] **Pack N content depth primary** — pure `pack_n_content_primary_command_product` + `PackNContentDomain` + GD dual · `pack_n_content_primary_live=1 majors_ok=5` · event_day·catalog·war_step·ops·close
- [x] **HOI fullscreen surface primary** — pure `hoi_fullscreen_primary_command_product` + `HoiFullscreenDomain` + GD dual · `hoi_fullscreen_primary_live=1 majors_ok=5` · compact·inspector·apply·polish·close
- [x] **Q1 RC checklist primary** — pure `q1_rc_checklist_primary_command_product` + `Q1RcChecklistDomain` + GD dual · `q1_rc_checklist_primary_live=1 majors_ok=5` · balance·sample·prove100·variance·close
- [x] **Combat engine depth primary** — pure `combat_engine_depth_primary_command_product` + `CombatEngineDepthDomain` + GD dual · `combat_engine_depth_primary_live=1 majors_ok=5` · ops·campaign·surge·oob100·close

### Sprint resource production strategic soft shortage — 2026-07-16

- [x] **Resource design brief** — `docs/RESOURCE_PRODUCTION_STRATEGIC_DESIGN.md` · **8 majors** (steel·aluminum·energy·fuel·rubber·electronics·specials·fissiles) · ops triad · HOI4/Stellaris/Vic3 · model `strategic_stockpile_soft_shortage`
- [x] **Resource production primary slice** — pure shortage product + `ProductionCostCalculator` shortage math + `ResourceProductionDomain` · dual `resource_production_primary_live=1 majors_ok=5 shortage_matters=true full_speed=1.0 shortage_speed=0.55` · Energy sources typed on map; fissiles unlock-gated; plastics/He-3/antimatter as tech/endgame not always-visible majors
- [x] **Resource harvest plants+tech slice** — `resource_harvest_rules.json` · `ResourceHarvestCalculator` · plant factory types · `resource_industry` tech tree · plastics/synth/fissiles gates · dual `resource_harvest_primary_live` (catalog·harvest·plants·tech·close)
- [x] **Resource economy depth** — food→supplies→cohesion · production shortage reliability→combat · plant auto-seed/upgrade · fuel ops burn (jets>trucks) · dual `resource_economy_depth_primary_live`
- [x] **Resource open items** — plant place/upgrade surface · He-3/antimatter year deposits · majors trade board/offers · dual `resource_open_items_primary_live`
- [x] **Trade + Relations foundation (R0–R2)** — design freeze `TRADE_RELATIONS_STRATEGIC_DESIGN.md` · SUU valuation · `RelationsManager` multi-vector CRS · AI concern flags · tariffs policy hooks · dual `trade_relations_primary_live`
- [x] **Trade power intel (R2b–d)** — national power + nuclear danger/placate · transit loss plain reasons (subs/planes/province) · spy relation+trade intel · long-term discounts · dual `trade_power_intel_primary_live`
- [x] **Trade Desk R3–R5** — auto monthly interdict · import tariff skim/treasury · `build_trade_desk_board` + TradeMarketView DESK · dual `trade_desk_primary_live` (interdict_ok·tariff_ok·desk_ok · SCRIPT 0 ×2)
- [x] **Trade AI R6** — monthly propose/accept · acceptance floors · hard-block flags · nuclear placate · dual `trade_ai_primary_live` (propose_ok·accept_ok·refuse_ok · SCRIPT 0 ×2)
- [x] **Trade basing R7** — DOCKING_RIGHTS → basing graph (host/guest edges) · monthly expire · desk basing strip · dual `trade_basing_primary_live` (grant_ok·query_ok·expire_ok · SCRIPT 0 ×2)
- [x] **Basing fleet station** — treaty docking tips `get_preferred_fleet_station` · dual `basing_fleet_station_primary_live` (score_ok·grant_ok·prefer_ok · SCRIPT 0 ×2) · AI surplus-aware monthly propose pair pick
- [x] **Space layer S0** — design freeze `SPACE_STRATEGIC_LAYER_DESIGN.md` · `orbital_compact_ledger` · gates/graph/SpaceFlow math · dual `space_layer_primary_live` (gates_ok·graph_ok·routes_ok · SCRIPT 0 ×2)
- [x] **Space depth S1** — full Sol multi-site · habitability · orbital_command (not MC) · space power in threat · loft staging · generational independence · dual `space_depth_primary_live` (sites_ok·capacity_ok·power_ok · SCRIPT 0 ×2)
- [x] **Space ops S2** — `SpaceLayerManager` autoload · claim sites · habitats · SpaceFlow interdict/monthly · dual `space_ops_primary_live` (claim_ok·habitat_ok·flow_ok · SCRIPT 0 ×2)
- [x] **Space colony S3** — parent CRS · range-gated interact · generational independence · landing/bombard hooks · save/load · dual `space_colony_primary_live` (rel_ok·indep_ok·combat_ok · SCRIPT 0 ×2)
- [x] **Space survey S4** — probe missions · discovery classes · dual `space_survey_primary_live` (launch_ok·advance_ok·discover_ok · SCRIPT 0 ×2)
- [x] **Space fog S5** — layer fog silhouettes · reveal · view toggle · dual `space_fog_primary_live` (fog_ok·reveal_ok·view_ok · SCRIPT 0 ×2)
- [x] **Space terraform S6** — multi-stage megaproject · garden unlock · dual `space_terraform_primary_live` (start_ok·advance_ok·garden_ok · SCRIPT 0 ×2)
- [x] **Space galaxy S7** — sparse bridge nodes · claim · dual `space_galaxy_primary_live` (unlock_ok·claim_ok·board_ok · SCRIPT 0 ×2)
- [x] **N3 network** — `NetSessionManager` MultiplayerAPI lockstep journals · dual `n3_network_primary_live` (lobby_ok·seed_ok·sync_ok · netcode_ready=true · SCRIPT 0 ×2) · **not** N4 dedicated server
- [x] **N4 dedicated** — dedicated server authority · client join · disconnect/reconnect catch-up · dual `n4_dedicated_primary_live` (host_ok·client_ok·reconnect_ok · dedicated_server_ready=true · SCRIPT 0 ×2) · ops `docs/N4_DEDICATED_SERVER_OPS.md`
- [x] **Space supply residual** — commercial lift charter · sustain SpaceFlows · supply board · dual `space_supply_primary_live` (lift_ok·flow_ok·board_ok · SCRIPT 0 ×2)
- [x] **Space supply AI** — monthly AI sustain flows + lift charter · dual `space_supply_ai_primary_live` (setup_ok·tick_ok·flows_ok · SCRIPT 0 ×2)
- [x] **Space survey events** — discovery campaign chains · no re-fire · dual `space_survey_events_primary_live` (survey_ok·fire_ok·chain_ok · SCRIPT 0 ×2)
- [x] **Space board UI** — `SpaceLayerBoardView` + `build_space_layer_ui_board` · dual `space_board_ui_primary_live` (board_ok·layer_ok·strips_ok · SCRIPT 0 ×2)
- [x] **Space open path** — TopInfoBar Space button + Diplomacy Space Board · dual `space_open_path_primary_live` (topbar_ok·diplo_ok·board_ok · SCRIPT 0 ×2)
- [x] **Space rival survey** — AI monthly rival probes · dual `space_rival_survey_primary_live` (seed_ok·tick_ok·compete_ok · SCRIPT 0 ×2)
- [x] **Space discovery choice** — player agency resolve (one-shot) · dual `space_discovery_choice_primary_live` (discover_ok·list_ok·resolve_ok · SCRIPT 0 ×2)
- [x] **Matchmaking residual** — queue pair → dedicated session · dual `matchmaking_primary_live` (queue_ok·match_ok·session_ok · SCRIPT 0 ×2) · not full NAT/WebRTC
- [x] **Space discovery UI** — board unresolved list + one-shot resolve · dual `space_discovery_ui_primary_live` (unresolved_ok·choose_ok·reresolve_blocked · SCRIPT 0 ×2)
- [x] **Matchmaking lobby** — `MatchmakingLobbyView` + TopInfoBar Match · dual `matchmaking_lobby_primary_live` (open_ok·path_ok·session_ok · SCRIPT 0 ×2) · not NAT/WebRTC
- [x] **Combat/production design freeze (CP0)** — `docs/COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md` · identity-weighted scale · EquipmentFlow path · map symbols · dual `combat_production_design_primary_live` (scale_ok·flow_ok·phases_ok · SCRIPT 0 ×2) · **not** full engine rewrite (CP1–CP6 later)
- [x] **CP1 EquipmentFlow ledger** — pure `equipment_flow_product` · `EquipmentFlowCalculator` · ProductionManager create/advance/interdict/ship · dual `equipment_flow_primary_live=1 create_ok·interdict_ok·deliver_ok ok=true` SCRIPT 0×2 · model `equipment_flow_compact_ledger`
- [x] **CP2 stock→flow→reinforce** — complete always credits country stockpile (batch scale) · `credit_production_complete_to_stockpile` · `demand_reinforce_via_equipment_flow` / tick · dual `equipment_stock_reinforce_primary_live=1 stock_ok·reinforce_ok ok=true` SCRIPT 0×2 · model `equipment_flow_compact_ledger`
- [x] **RF0/RF1 reinforce logistics + experience** — `docs/REINFORCEMENT_EXPERIENCE_LOGISTICS_DESIGN_FREEZE.md` · non-instant transit (hub/era/resources) · manpower vs rearm XP asymmetry · Formation `combat_experience` · CombatResolver mult · dual `reinforcement_logistics_primary_live=1 time_ok·exp_ok·hub_ok ok=true` SCRIPT 0×2 · model `reinforce_experience_logistics_ledger`
- [x] **RF2–RF4 reinforcement depth** — non-instant flow demo · combat XP mult · training policy matrix (volunteer/crash/clone…) · era mode unlocks (rail→airlift→drone→orbital) · dual `reinforcement_depth_primary_live=1 non_instant_ok·combat_xp_ok·policy_ok·era_mode_ok ok=true` SCRIPT 0×2
- [x] **CP3 EquipmentFlow map symbols** — mode→glyph table (train/truck/air/sea/drone/orbital) · board glyphs · map strip plain · dual `equipment_flow_symbols_primary_live=1 modes_ok·board_ok·symbols_ok ok=true` SCRIPT 0×2
- [x] **RF5 reinforce story plains** — order panel section · format_reinforce_story_plain · XP dilution + transit + flow symbols · dual `reinforce_story_primary_live=1 xp_plain_ok·transit_ok·story_ok ok=true` SCRIPT 0×2
- [x] **CP4 munitions + drone categories** — missile 1:1 · drone_swarm batch×6 · consume_munitions_from_stockpile · dual `munitions_drone_primary_live=1 missile_ok·drone_ok·consume_ok ok=true` SCRIPT 0×2
- [x] **CP5 combat munitions consume** — battle aftermath burns missile/drone stock · reliability combat mult · troop XP gain · dual `combat_consume_primary_live=1 combat_consume_ok·reliability_ok·xp_ok ok=true` SCRIPT 0×2
- [x] **CP3 map paint EquipmentFlow glyphs** — `StrategicFlowOverlayLayer` train/truck/air/sea/drone/orbital · dual `equipment_flow_paint_primary_live=1 symbols_ok·board_ok·paint_ok ok=true` SCRIPT 0×2
- [x] **CP6 deep combat + AI logistics** — `resolve_deep_combat` equipment-weighted · `ai_select_logistics_doctrine` mode/escort · dual `combat_depth_primary_live=1 deep_ok·logistics_ok·joint_ok ok=true` SCRIPT 0×2
- [x] **Map flow LOD + glyph toggle** — zoom tiers aggregate/discrete · KEY_I independent toggle · dual `map_flow_lod_primary_live=1 lod_ok·toggle_ok·wire_ok ok=true` SCRIPT 0×2
- [x] **AI logistics in strategic AI daily apply** — `apply_ai_logistics_doctrine_day` for non-player majors · dual `ai_logistics_day_primary_live=1 doctrine_ok·apply_ok·seed_ok ok=true` SCRIPT 0×2
- [x] **RF6 AI training policy doctrine** — `ai_select_training_policy` cadre/crash/clone by war·strain·year · dual `ai_training_policy_primary_live=1 peace_ok·war_ok·ai_policy_ok ok=true` SCRIPT 0×2

### Still open
- [x] **G0 TutorialSessionDomain extract** (CampaignAlphaDomain + TutorialSessionDomain) — further domain splits still open
- [x] **G0 MultiFactionAIDomain extract** (with TutorialSessionDomain + CampaignAlphaDomain)
- [x] **G0 WeatherTheaterDomain extract**
- [x] **G0 ManpowerLawsDomain extract**
- [x] **G0 FocusTreeDomain extract**
- [x] **G0 LeaderTheaterDomain extract**
- [x] **G0 IntelNetworkDomain extract**
- [x] **G0 DesignerSuiteDomain extract**
- [x] **G0 FactoryRetoolDomain extract**
- [x] **G0 LogisticsSupplyDomain extract**
- [x] **G0 FrontContinuityDomain extract**
- [x] **G0 AirMultiPhaseDomain extract**
- [x] **G0 FleetMultiDayDomain extract**
- [x] **G0 BalanceDomain extract**
- [x] **G0 ProductUxDomain extract**
- [x] **G0 ConvoySealaneDomain extract**
- [x] **G0 HistoricalOobDomain extract**
- [x] **G0 InspectorDecisionDomain extract**
- [x] **G0 ProductionHonestyDomain extract**
- [x] **G0 OccupationDomain extract**
- [x] **G0 PeaceConferenceDomain extract**
- [x] **G0 CommandJournalDomain extract**
- [x] **G0 BattleAarDomain extract**
- [x] **G0 WarEconomyDomain extract**
- [x] **G0 MapPerfMeasuredDomain extract**
- [x] **G0 AgentMissionBoardDomain extract**
- [x] **G0 ResearchQueueDomain extract**
- [x] **G0 FactionPersonalityDomain extract**
- [x] **G0 FleetAutonomyDomain extract**
- [x] **G0 WarGoalAllianceDomain extract**
- [x] **G0 IntelCounterDomain extract**
- [x] **G0 StreamAlphaDomain extract**
- [x] **G0 HhMultiMonthDomain extract**
- [x] **G0 AirTheaterDomain extract**
- [x] **G0 AgentCampaignDomain extract**
- [x] **G0 GrandStrategyCycleDomain extract**
- [x] **G0 WorldClassDomain extract**
- [x] **G0 CombatIntelEstimateDomain extract**
- [x] **G0 AutosaveSessionDomain extract**
- [x] **G0 DesignerDepthDomain extract**
- [x] **G0 MultiFrontDomain extract**
- [x] **G0 StrategicWarGoalDomain extract**
- [x] **G0 NavalSearchStrikeDomain extract**
- [x] **G0 WeatherCrisisDomain extract**
- [x] **G0 CampaignAiMultiMonthDomain extract**
- [x] **G0 TechResearchDomain extract**
- [x] **G0 FocusWarPathDomain extract**
- [x] **G0 NavalMultiPhaseDomain extract**
- [x] **G0 DiplomacyPeaceDomain extract**
- [x] **G0 SaveResumeDomain extract**
- [x] **G0 PlaySessionDomain extract** · routing `test_sprint_residual_g0_queue_routing.py` · dual×2 all 14 markers SCRIPT 0
- [x] **G0 combat/production partial package** — dual green `combat_production_partial_primary` (deeper engine rewrites still open)
- [x] **HOI panel polish primary** — dual green `hoi_panel_primary` (deeper full-screen HOI redesign still open)
- [x] **M3 density pilot measured dual** — denser-board path dual green (`world_pilot_global_density` + real Performance samples; province_n counter may still refine)
- [x] **I2b combat estimate intel impact** — dual package with `impact=true` (estimate bias path); full combat-engine wiring can deepen further
- [x] **S2 autosave primary package** — dual green (deeper crash-recovery policy can still extend)
- [x] **X1 historical OOB primary package** — dual green (era fill still open for Pack N depth)
- [x] **I3 intel counter primary package** — dual green
- [x] **A4 faction personality primary package** — dual green
- [x] **AI difficulty primary package** — dual green (easy/normal/hard presets via `ai_difficulty_primary`)
- [x] **P3 production honesty primary package** — dual green
- [x] **HH multi-month primary package** — dual green (L1 depth)
- [x] **Logistics supply primary package** — dual green
- [x] **Front continuity primary package** — dual green
- [x] **Designer depth primary package** — dual green
- [x] **Air multi-phase primary package** — dual green (C3 depth)
- [x] **Inspector decision primary package** — dual green
- [x] **Balance combat/supply primary package** — dual green (Q residual)
- [x] **Fleet multi-day primary package** — dual green (C2 depth)

Catalogue labels: + map_perf_measured_primary · war_goal_alliance_primary · factory_retool_primary  

Honesty: dual claims only where PROOF + dual.log show SCRIPT ERROR **0** + markers — see goal SCRATCH `dual/` + routing tests.

---

## Ownership eras + hierarchy scaffold (landed)

## Campaign Alpha Phase 1 — primary command strip (landed 2026-07-15)

## Stream α packs C/E/F/G (+ B/D/H/I/J/K/L/M) — landed 2026-07-15

- [x] **Pack C** — combat ribbon on primary strip · `combat_ops_close` · Ctrl+A/E/D phase keys
- [x] **Pack E** — OOB 60/100d board on ProductionAssignmentScreen (real `apply_oob_horizon_*`)
- [x] **Pack F** — TopInfoBar **HH Agenda** primary screen · `hh_agenda_close`
- [x] **Pack G** — F6 Save Browser uses `save_browser_campaign_product_live` + resume/checkpoint
- [x] **Pack D** — `naval_ops_close` on strip · End Turn advances multi-faction AI daily
- [x] **Pack I** — `MapRendererPerf.passes_budget` + SCRATCH writer · `map_fps_budget_live`
- [x] **Pack L** — Hotseat banner · End Turn · order lock when AI active
- [x] **Pack B** — `CampaignAlphaDomain` first GameData extraction (public APIs stable)
- [x] **Pack H** — `nuts3_to_world_full_overlap.json` nearest-centroid remap (no renumber)
- [x] **Pack J** — `DesignManager.compute_design_stats` · SpaceDesignPopup live
- [x] **Pack K** — war_goal / multi_front / personality buttons on primary strip
- [x] **Pack M** — MASTER progress table + COMPLETION_PLAN / roadmap / perf docs synced
- [x] **Pack N thin era primary** — dual green `pack_n_era_primary` (deeper focus/events era fill still open)
- [ ] Next: 100d player-path dual · full GameData split G0.1 · N2 journal replay

Catalogue labels: stream_alpha · pack_c · pack_e · pack_f · pack_g · campaign alpha · primary strip · phase1_alpha  

Dual markers: `campaign_alpha_primary_live=1` · `stream_alpha_packs_live=1` · `map_fps_budget_live=1`

---

## Campaign Alpha Phase 1 — primary command strip (landed 2026-07-15)

- [x] **Primary strip** — top 8 always-visible live actions (station · assault · production · day ops · theater · HH · occupation · checkpoint)
- [x] **Recommended-next** — HH / theater / front / occupation pressure → one Apply
- [x] **Dead-button audit** — `dead_n=0` on primary strip
- [x] Majors collapsed under “Campaign depth” · day packages `max_expanded=1`
- [x] PI chip priority **163** · dual `campaign_alpha_primary_live=1`
- [ ] Next: 100d player-path dual · tutorial polish · GER 1936 vertical

Catalogue labels: campaign alpha · primary strip · phase1_alpha · playability  

Dual marker: `campaign_alpha_primary_live=1` (dead_n · ticks · board/rec/audit)

---

## Ownership eras + hierarchy scaffold (landed)

- [x] Multi-era ownership tables **1910 / 1918 / 1936 / 1945 / 2026** (`province_ownership_*.json`)
- [x] Scenario `start_date` → era seed via `ScenarioLoader._apply_era_ownership_seed` (**seed only**, player agency)
- [x] `ownership_era_index.json` + pure product + CI tests
- [x] Hierarchy scaffold: province→state (~152)→region (~15) sparse/dense rules

Catalogue labels: ownership era · 2026 ownership · player agency · hierarchy scaffold · map hierarchy  

---

## Europe densify pilot + world-class map path (landed 2026-07-13)

- [x] Parallel pilot dir `data/provinces_pilot_europe` (~**1840** land, IDs **700000+**, no world_full renumber)
- [x] Scenario `world_pilot_europe` · hierarchy live (`states=196` `regions=10` `super=1`) · ownership eras seed-only
- [x] Dual SCRIPT **0**: world_full + pilot (+ 2026 seed) · pure tests + map CI hooks
- [x] Decision package (Producer / Designer / Skeptic) in `docs/MAP_HIERARCHY_AND_GIS_ROADMAP.md`
- [x] **Shared-edge adjacency** (pilot + world_full) · method `shared_edge_plus_knn_fallback` · orphans=0 · dual SCRIPT 0
- [x] **US 8-band pilot** `data/provinces_pilot_us` (~1488 land, IDs **800000+**) · scenario `world_pilot_us` · dual SCRIPT 0
- [x] Global density pilot `provinces_pilot_global_density` land **4650** (toward ~6k band, IDs 900000+)
- [x] **NUTS-3 Europe GIS pilot** `provinces_pilot_europe_nuts3` (IDs **710000+**, **1514** land, Eurostat GISCO 20M 2021)
- [x] Scenario `world_pilot_europe_nuts3` · hierarchy 210 states / 12 regions · shared-edge adjacency orphans=0
- [x] Dual `nuts3_gis_live=1` · pure tests + map CI
- [ ] **Next residual:** graphical 60 fps measure on ~6k · promote NUTS mesh into world_full (id-stable remap table)

Catalogue labels: europe pilot densify · world_pilot_europe · hierarchy_live · ownership_era_seed · pilot dual · nuts3_gis  


---

## Completion playability close (landed 2026-07-15)

- [x] Combat multi-phase UI/ops live close (approach→engage→disengage)
- [x] Fleet/naval multi-phase ops live close (posture→escort→strike)
- [x] HH multi-month agenda surface live close (trail→brief→quarterly)
- [x] Dual `completion_playability_live=1` · combat/naval/hh PASS
- [x] Global density pilot toward ~6k (4650 land, IDs 900000+)
- Still deferred (high cost): true multiplayer netcode · full HOI4 3D designer previews · full-world photoreal NUTS/GADM remesh

Catalogue labels: completion playability · combat_ops_close · naval_ops_close · hh_agenda_close · global density  

---

## Full designer duties + multiplayer foundation + AI daily (landed 2026-07-15)

- [x] **DesignManager.register_custom_design** — authoring API + save/load + catalog merge
- [x] **Full designer duties** live cycle all domains: catalog→compose→freeze→register→seed
- [x] **DomainDesignPopup** multi-domain UI (land/naval/air/space)
- [x] Dual `full_designer_duties_live=1` PASS · registered=4 seeded=4
- [x] **SessionPlayers** hotseat foundation (lobby · command queue · rotate · LeaderManager hinge)
- [x] Dual `session_players_hotseat_live=1` PASS
- [x] **Multi-faction AI daily depth** — non-human slots apply production/supply/focus; skip humans
- [x] Dual `strategic_ai_multi_faction_daily_live=1` PASS · `vision_close_live=1` PASS
- [x] Event/tech missing 64px icons filled + designer domain icons
- Still deferred: dedicated-server netcode · lobby matchmaking · full HOI module 3D designer · NUTS-3 GIS · graphical 60 fps measure on ~6k

Catalogue labels: full_designer_duties · register_custom_design · SessionPlayers · hotseat · multi_faction_ai_daily · vision_close  

---

## Quality gap close + asset fill (landed 2026-07-15)

- [x] Gap inventory (code/play/dual/assets) under goal SCRATCH
- [x] Custom designs register as live `UnitTemplate` via `DesignDataLoader.register_runtime_template*`
- [x] ProductionLine late-bind for `custom_*` designs
- [x] Dual `quality_gap_close_live=1` (template_ok + registered)
- [x] Referenced icon fill: **918 → 0** missing module paths via `tools/fill_referenced_icons.py`
- [x] Imagine-upgraded designer domain + sample tech/event icons
- Still deferred: true multiplayer netcode · full HOI 3D designers · NUTS-3 GIS · 60 fps measure · unreferenced orphan imports

Catalogue labels: quality_gap_close · register_runtime_template · fill_referenced_icons · custom template honesty  



---

## Hierarchical map division system (Phase 1–4 design + samples) (landed 2026-07-13)

- [x] Design: `docs/MAP_HIERARCHY_SYSTEM_DESIGN.md` — 4-tier roles, density bands, 1900–2100 dynamics, AI/supply implications
- [x] Schema: `docs/MAP_HIERARCHY_JSON_SCHEMA.md` + product `hierarchy_system_product.py`
- [x] Samples: US Midwest (`800000+` counties→states→Midwest→NA) · Europe core (districts→Flanders/Bavaria/…→regions→Europe)
- [x] Pure helpers: `reassign_province` (gory borders), state size gates 5–20 soft, super-region catalog (12)
- [x] Map CI: `test_hierarchy_system_product.py`
- [x] Locked decisions: US **8-band** regions · **~6k** province target (60 fps first) · membership **1910/1918/1936/2026 full**
- [x] Full membership snapshots + `membership_era_index.json` on world_full, pilot, samples
- [x] ScenarioLoader `_apply_era_membership_seed` (seed-only, mode=full)
- [x] Runtime membership mutation API on GameData/ScenarioLoader (reassign · create_state · transfer_state)
- [x] Dual marker `membership_live_mut=1` · seed-only · reapply_on_year_tick=0
- [x] Membership **save/load** (`hierarchy_membership_live`) + **peace annex** creates occupation state
- [x] Dual marker `membership_peace_saveload=1` · peace+saveload live PASS
- [x] Shared-edge adjacency product + load path (`adjacency_live`) on pilot/world_full
- [x] US pilot dir (`provinces_pilot_us`, 8-band, shared-edge, membership full eras)
- [x] Density bar step: global densify pilot 2325→4650 land (procedural interim)
- [x] NUTS-3 Europe GIS pilot landed (`provinces_pilot_europe_nuts3`) · [ ] graphical 60 fps measure · [ ] NUTS promote to world_full (see MASTER_COMPLETION_PLAN Phase M)

Catalogue labels: hierarchy system · four_tier · us_midwest_sample · europe_core_sample · membership era · 8_band · 6k target  

---

---

---

## Map visual gap-closure Phase 2 + Phase 3 (complete)

### Phase 2
- [x] **Occupation mapmode** — resistance/compliance heatmap · partisan markers · PI chip (extends #24)
- [x] **Supply/sealane flow** — animated arrows · chokepoint rings · key **U**
- [x] **Battle indicators** — front clash · phase ribbon pips · assault trail · key **J**
- [x] **LOD/perf budgets** — `MapZoomLOD` overlay caps · lower-vert far zoom · 60 fps target ms
- [x] **Naval/air domain ops** — task groups · sortie arrows · carrier arcs · key **K**

### Phase 3
- [x] **Construction progress rings** on infra/special sites
- [x] **Leader OOB station markers** (#26 visual)
- [x] **ProvinceEditor property inspector + export roundtrip helpers**
- [x] **Weather move-cost tint** (`apply_movement_cost_tint`)
- [x] **GPU pan/zoom soft targets** (cull stride · frame ms · lower-vert)

Catalogue labels: phase2 · phase3 · battle indicator · supply flow · map_phase23 · world_class_map · LOD · domain ops  

Dual marker: `map_phase23_live=1` (flow · battle · domain · lod · build · leader · editor · wx)

---

## Map visual gap-closure Phase 1 (complete)

- [x] **Signal graph harness (F11)** — `SignalGraphVisualizer` + `SignalGraphHarness` for MapManager / day-package / OrderCommandPanel routes  
- [x] **MapRenderer perf profile** — `MapRendererPerf` · `EOA_MAP_PERF=1` · `[PERF MAP EVIDENCE]` · `docs/MAP_RENDERER_PERF.md`  
- [x] **Occupation visual layer (#24 depth)** — resistance tint + garrison icons · key **O** · PI compliance chip  
- [x] **Visual regression CI** — pure fingerprint `mvg1-*` · baseline · map CI hooks (screenshot path documented)  

Catalogue labels: map gap · occupation overlay · signal graph · map_gap_closure · phase1_gap · world_class_map · MapRenderer  

Dual marker: `map_gap_closure_live=1` (occ · sig · perf · overlay)

---

## Majors #56 + #57 + #58 + Next-470 — PHASE 11 WORLD-CLASS GS DEPTH (complete)

### Major #56 — ALLIANCE GUARANTEE NETWORK PRODUCT
- [x] **Alliance guarantee network** — alliance board → guarantee/invite commit → coalition ops package  
- [x] **Per-step** — `alliance_board` · `alliance_guarantee` · `alliance_coalition`  
- [x] Live `apply_alliance_live` · PI priority **160** · deepens #16  

Catalogue labels: alliance · major #56 · phase11_depth · world_class_gs · diplomacy  

### Major #57 — FACTION PERSONALITY AI PRODUCT
- [x] **Faction personality AI** — personality board → event-driven reaction → doctrine drive package  
- [x] **Per-step** — `personality_board` · `personality_event` · `personality_drive`  
- [x] Live `apply_personality_live` · PI priority **161** · deepens #9/#53–#55  

Catalogue labels: personality · major #57 · phase11_depth · world_class_gs · campaign_ai  

### Major #58 — OCCUPATION REVOLT NETWORK PRODUCT
- [x] **Occupation revolt network** — multi-province revolt map → cascade risk → network suppress package  
- [x] **Per-step** — `revolt_network_map` · `revolt_cascade_risk` · `revolt_network_suppress`  
- [x] Live `apply_revolt_network_live` · PI priority **162** · deepens #29/#35  

Catalogue labels: revolt network · major #58 · phase11_depth · world_class_gs · occupation  

### Next-470 — PHASE11 DEPTH (12)
Alliance board/guarantee/coalition/close · personality board/event/drive/close · revolt map/cascade/suppress/close.

Catalogue labels: alliance board day · alliance guarantee day · alliance coalition day · alliance guarantee network close day · personality board day · personality event day · personality drive day · faction personality AI close day · revolt network map day · revolt cascade risk day · revolt network suppress day · occupation revolt network close day · next-470  

Dual marker: `phase11_depth_live=1` (al_ticks · pers_ticks · rev_ticks)

---

## Majors #53 + #54 + #55 + Next-460 — PHASE 10 WORLD-CLASS GS (complete)

### Major #53 — STRATEGIC WAR-GOAL PRODUCT
- [x] **Strategic war-goal product** — war-goal board → justify/select package → execute strategic push  
- [x] **Per-step** — `war_goal_board` · `war_goal_justify` · `war_goal_execute`  
- [x] Live `apply_war_goal_live` · PI priority **157** · deepens #34/#9  

Catalogue labels: strategic war · major #53 · phase10_gs · world_class_gs · war_goal  

### Major #54 — MULTI-FRONT CAMPAIGN AI PRODUCT
- [x] **Multi-front campaign AI** — multi-front plan → weekly AI tick → theater execute package  
- [x] **Per-step** — `multi_front_plan` · `multi_front_weekly` · `multi_front_execute`  
- [x] Live `apply_multi_front_live` · PI priority **158**  

Catalogue labels: multi-front · major #54 · phase10_gs · world_class_gs · campaign_ai  

### Major #55 — GRAND STRATEGY CYCLE PRODUCT
- [x] **Grand strategy cycle** — scan all domains → rank priorities → execute top GS package  
- [x] **Per-step** — `gs_cycle_scan` · `gs_cycle_rank` · `gs_cycle_execute`  
- [x] Live `apply_gs_cycle_live` · PI priority **159** · open 7/7 COMPLETE  

Catalogue labels: grand strategy · major #55 · phase10_gs · world_class_gs · full gameplay cycle  

### Next-460 — PHASE10 GS (12)
War goal board/justify/execute/close · multi front plan/weekly/execute/close · GS cycle scan/rank/execute/close.

Catalogue labels: war goal board day · war goal justify day · war goal execute day · strategic war goal close day · multi front plan day · multi front weekly day · multi front execute day · multi front campaign ai close day · gs cycle scan day · gs cycle rank day · gs cycle execute day · grand strategy cycle close day · next-460  

Dual marker: `phase10_gs_live=1` (wg_ticks · mf_ticks · gs_ticks)

---

## Majors #50 + #51 + #52 + Next-450 — PHASE 9 FULL GAMEPLAY CYCLE (complete)

### Major #50 — WEATHER CRISIS CAMPAIGN PRODUCT
- [x] **Weather crisis campaign** — multi-day forecast pressure → multi-theater weather gate → crisis sustain  
- [x] **Per-step** — `weather_crisis_forecast` · `weather_crisis_gate_multi` · `weather_crisis_sustain`  
- [x] Live `apply_weather_crisis_live` · PI priority **154** · deepens #22  

Catalogue labels: weather crisis · major #50 · phase9_cycle · full gameplay cycle · weather  

### Major #51 — INTEL CELL NETWORK PRODUCT
- [x] **Intel cell network** — multi-province cell coverage → cell ops/recruit → counterintel sweep  
- [x] **Per-step** — `intel_cell_coverage` · `intel_cell_ops` · `intel_counter_sweep`  
- [x] Live `apply_intel_cell_live` · PI priority **155** · deepens #19  

Catalogue labels: intel cell · major #51 · phase9_cycle · full gameplay cycle · intel  

### Major #52 — LEADER THEATER COMMAND PRODUCT
- [x] **Leader theater command** — HQ assign board → multi-formation station → theater command ops  
- [x] **Per-step** — `leader_hq_board` · `leader_multi_station` · `leader_theater_ops`  
- [x] Live `apply_leader_theater_live` · PI priority **156** · deepens #26  

Catalogue labels: leader theater · major #52 · phase9_cycle · full gameplay cycle · leader  

### Next-450 — PHASE9 CYCLE (12)
Weather forecast/gate/sustain/close · intel coverage/ops/sweep/close · leader HQ/station/ops/close.

Catalogue labels: weather crisis forecast day · weather crisis gate multi day · weather crisis sustain day · weather crisis campaign close day · intel cell coverage day · intel cell ops day · intel counter sweep day · intel cell network close day · leader hq board day · leader multi station day · leader theater ops day · leader theater command close day · next-450  

Dual marker: `phase9_cycle_live=1` (wx_ticks · intel_ticks · leader_ticks)

---

## Majors #47 + #48 + #49 + Next-440 — PHASE 8 FULL DESIGNERS (complete)

### Major #47 — DESIGNER MODULE EDITOR PRODUCT
- [x] **Real module catalog** — `data/designers/full_module_catalog.json` · **1084** modules · domain option boards · `assets/graphics/icons/modules/*`  
- [x] **Designer module editor** — module slot board → edit chassis/armament/engine → reliability/cost gate  
- [x] **Per-step** — `designer_module_board` · `designer_module_edit` · `designer_reliability_gate`  
- [x] Live `apply_designer_module_live` · PI priority **151** · deepens #10/#33  

Catalogue labels: designer module editor · major #47 · phase8_designers · full designers · full designers complete · modules · real catalog 1084  

### Major #48 — DESIGNER STATS/FIELD PRODUCT
- [x] **Designer stats/field** — stats board → freeze design variant → field production seed  
- [x] **Per-step** — `designer_stats_board` · `designer_freeze_design` · `designer_field_seed`  
- [x] Live `apply_designer_field_live` (+ domain seed trail) · PI priority **152**  

Catalogue labels: designer stats · major #48 · phase8_designers · full designers · field  

### Major #49 — DESIGNER MULTI-DOMAIN CAMPAIGN PRODUCT
- [x] **Full designers multi-domain** — catalog all domains → multi-domain seeds → equip campaign close  
- [x] **Per-step** — `designer_catalog_all_domains` · `designer_seed_multi_domain` · `designer_equip_campaign_close`  
- [x] Live `apply_designer_campaign_live` · PI priority **153** · land/naval/air/space COMPLETE  

Catalogue labels: full designers · major #49 · phase8_designers · multi-domain  

### Next-440 — PHASE8 DESIGNERS (12)
Module board/edit/reliability/close · stats board/freeze/field/close · catalog all/seed multi/equip/close.

Catalogue labels: designer module board day · designer module edit day · designer reliability gate day · designer module editor close day · designer stats board day · designer freeze design day · designer field seed day · designer stats field close day · designer catalog all domains day · designer seed multi domain day · designer equip campaign close day · designer multi domain campaign close day · next-440  

Dual marker: `phase8_designers_live=1` (mod_ticks · field_ticks · camp_ticks)

---

## Majors #44 + #45 + #46 + Next-430 — PHASE 7 THEATER OPS DEPTH (complete)

### Major #44 — AIR MULTI-PHASE THEATER PRODUCT
- [x] **Air multi-phase theater product** — recon/sortie fuel → weather/CAS gate → interdiction joint (deepens #13)  
- [x] **Per-step** — `air_theater_recon` · `air_theater_cas_gate` · `air_theater_interdiction`  
- [x] Live `apply_air_theater_live` · PI priority **148**  

Catalogue labels: air multi-phase theater · major #44 · phase7_depth · air  

### Major #45 — NAVAL SEARCH/STRIKE PRODUCT
- [x] **Naval search/strike product** — search/patrol → ASW/escort → carrier strike (deepens #15)  
- [x] **Per-step** — `naval_search_patrol` · `naval_asw_escort` · `naval_carrier_strike`  
- [x] Live `apply_naval_search_live` · PI priority **149**  

Catalogue labels: naval search · major #45 · phase7_depth · naval  

### Major #46 — WAR ECONOMY CONVERSION PRODUCT
- [x] **War economy conversion product** — civilian board → war conversion → stockpile sustain (deepens #21)  
- [x] **Per-step** — `economy_civ_board` · `economy_war_convert` · `economy_stockpile_sustain`  
- [x] Live `apply_economy_conversion_live` · PI priority **150**  

Catalogue labels: war economy conversion · major #46 · phase7_depth · economy  

### Next-430 — PHASE7 DEPTH (12)
Air theater recon/cas/interdiction/close · naval search/asw/carrier/close · economy civ/convert/sustain/close.

Catalogue labels: air theater recon day · air theater cas gate day · air theater interdiction day · air multi-phase theater close day · naval search patrol day · naval asw escort day · naval carrier strike day · naval search strike close day · economy civ board day · economy war convert day · economy stockpile sustain day · war economy conversion close day · next-430  

Dual marker: `phase7_depth_live=1` (air_ticks · naval_ticks · econ_ticks)

---

## Phase 1 HONESTY — COMPLETE (thorough parity with Phases 2–5)

### Major #27 — MEDIUM-TANK PRODUCTION HONESTY
- [x] Pure → formatters → MapManager → GameData → panel → PI **131** → tests → CI → dual `medium_tank_complete`  
Catalogue labels: medium-tank production honesty · medium honesty · major #27 · medium_tank_complete · phase1_honesty  

### Major #28 — APPLY-QUEUE LIVE MANAGERS
- [x] Pure → formatters → MapManager → GameData live leaves → panel → PI **132** → tests → CI → dual `apply_queue_live=6/6`  
Catalogue labels: apply-queue live managers · apply queue live · major #28 · apply_queue_live · phase1_honesty  

### Next-360 / Next-370
- [x] Medium honesty 10 days · apply-queue live 10 days · dual regression green with SCRIPT ERROR: 0  

---

## Majors #41 + #42 + #43 + Next-420 — PHASE 6 DEPTH (complete)

### Major #41 — TUTORIAL FIRST-SESSION PRODUCT
- [x] **Tutorial first-session product** — session brief → guided first-week actions → continuity checkpoint  
- [x] **Per-step** — `tutorial_session_brief` · `tutorial_session_guide` · `tutorial_session_checkpoint`  
- [x] Live `apply_tutorial_session_live` · PI priority **145**  

Catalogue labels: tutorial first-session · major #41 · phase6_depth · tutorial  

### Major #42 — FOCUS TREE CONTENT PRODUCT
- [x] **Focus tree content product** — focus catalog → path pick → commit trail  
- [x] **Per-step** — `focus_tree_catalog` · `focus_tree_path` · `focus_tree_commit`  
- [x] Live `apply_focus_content_live` · PI priority **146**  

Catalogue labels: focus tree content · major #42 · phase6_depth · focus  

### Major #43 — BALANCE COMBAT/SUPPLY PRODUCT
- [x] **Balance combat/supply product** — estimate board → live sample → variance close  
- [x] **Per-step** — `balance_estimate_board` · `balance_live_sample` · `balance_variance_close`  
- [x] Live `apply_balance_live` · PI priority **147**  

Catalogue labels: balance combat · major #43 · phase6_depth · supply  

### Next-420 — PHASE6 DEPTH (12)
Tutorial session brief/guide/checkpoint/close · focus tree catalog/path/commit/close · balance estimate/sample/variance/close.

Catalogue labels: tutorial session brief day · tutorial session guide day · tutorial session checkpoint day · tutorial first session close day · focus tree catalog day · focus tree path day · focus tree commit day · focus tree content close day · balance estimate board day · balance live sample day · balance variance close day · balance combat supply close day · next-420  

Dual marker: `phase6_depth_live=1` (tut_ticks · focus_ticks · bal_ticks)

---

## Majors #38 + #39 + #40 + Next-410 — PHASE 5 DEPTH (complete)

### Major #38 — HISTORICAL OOB CONTENT PRODUCT
- [x] **Historical OOB content product** — national OOB catalog → seed production lines → equip formations  
- [x] **Per-step** — `historical_oob_catalog` · `historical_oob_seed` · `historical_oob_equip`  
- [x] Live `apply_historical_oob_live` · PI priority **142**  

Catalogue labels: historical oob · major #38 · phase5_depth · content  

### Major #39 — TECH TREE BRANCHING PRODUCT
- [x] **Tech tree branching product** — branch catalog (year gates) → research path → field unlock  
- [x] **Per-step** — `tech_tree_branches` · `tech_tree_path` · `tech_tree_field`  
- [x] Live `apply_tech_branch_live` · PI priority **143**  

Catalogue labels: tech tree branching · major #39 · phase5_depth · branch  

### Major #40 — SAVE/RESUME CAMPAIGN PRODUCT
- [x] **Save/resume campaign product** — checkpoint board → slot save → mid-war resume verify  
- [x] **Per-step** — `save_resume_checkpoint` · `save_resume_save` · `save_resume_resume`  
- [x] Live `apply_save_resume_live` · PI priority **144**  

Catalogue labels: save/resume · major #40 · phase5_depth · continuity  

### Next-410 — PHASE5 DEPTH (12)
Historical OOB catalog/seed/equip/close · tech tree branches/path/field/close · save resume checkpoint/save/resume/close.

Catalogue labels: historical oob catalog day · historical oob seed day · historical oob equip day · historical oob content close day · tech tree branches day · tech tree path day · tech tree field day · tech tree branching close day · save resume checkpoint day · save resume save day · save resume resume day · save resume campaign close day · next-410  

Dual marker: `phase5_depth_live=1` (oob_ticks · tech_ticks · save_ticks)

---

## Majors #35 + #36 + #37 + Next-400 — PHASE 4 DEPTH (complete)

### Major #35 — OCCUPATION REVOLT/GARRISON PRODUCT
- [x] **Occupation revolt/garrison product** — revolt risk board → deploy garrison → suppress flashpoint  
- [x] **Per-step** — `occupation_revolt_board` · `occupation_revolt_garrison` · `occupation_revolt_suppress`  
- [x] Live `apply_occupation_revolt_live` · PI priority **139**  

Catalogue labels: occupation revolt · major #35 · phase4_depth · garrison  

### Major #36 — MANPOWER COHORT/RESERVE PRODUCT
- [x] **Manpower cohort/reserve product** — age-cohort board → reserve tiers → mobilize field  
- [x] **Per-step** — `manpower_cohort_board` · `manpower_cohort_reserve` · `manpower_cohort_mobilize`  
- [x] Live `apply_manpower_cohort_live` · PI priority **140**  

Catalogue labels: manpower cohort · major #36 · phase4_depth · reserve  

### Major #37 — MULTI-PARTY PEACE CONFERENCE PRODUCT
- [x] **Multi-party peace conference product** — multi-victor board → war-goal packages → multi-party settle  
- [x] **Per-step** — `multi_party_peace_board` · `multi_party_peace_wargoals` · `multi_party_peace_settle`  
- [x] Live `apply_multi_party_peace_live` · PI priority **141**  

Catalogue labels: multi-party peace · major #37 · phase4_depth · war-goal  

### Next-400 — PHASE4 DEPTH (12)
Occupation revolt board/garrison/suppress/close · manpower cohort board/reserve/mobilize/close · multi-party peace board/wargoals/settle/close.

Catalogue labels: occupation revolt board day · occupation revolt garrison day · occupation revolt suppress day · occupation revolt garrison close day · manpower cohort board day · manpower cohort reserve day · manpower cohort mobilize day · manpower cohort reserve close day · multi-party peace board day · multi-party peace wargoals day · multi-party peace settle day · multi-party peace campaign close day · next-400  

Dual marker: `phase4_depth_live=1` (revolt_ticks · cohort_ticks · multi_party_settlements)

---

## Majors #32 + #33 + #34 + Next-390 — PHASE 3 DEPTH (complete)

### Major #32 — PRODUCT UX COMMAND POLISH PRODUCT
- [x] **Product UX command polish product** — compact section board → top-8 always-on chips → primary hotkeys 1–8  
- [x] **Per-step** — `product_ux_compact_board` · `product_ux_top_chips` · `product_ux_hotkeys`  
- [x] Live `apply_product_ux_polish_live` · PI priority **136**  

Catalogue labels: product ux · major #32 · phase3_depth · hotkeys  

### Major #33 — DESIGNER DOMAIN LIVE PRODUCT
- [x] **Designer domain live product** — multi-domain catalog → pick design → seed production line live  
- [x] **Per-step** — `designer_domain_live_catalog` · `designer_domain_live_pick` · `designer_domain_live_seed`  
- [x] Live `apply_designer_domain_seed_live` · PI priority **137**  

Catalogue labels: designer domain · major #33 · phase3_depth · seed  

### Major #34 — CAMPAIGN AI MULTI-MONTH PRODUCT
- [x] **Campaign AI multi-month product** — month plan board → weekly AI plan → theater execute  
- [x] **Per-step** — `campaign_ai_month_board` · `campaign_ai_weekly_plan` · `campaign_ai_theater_execute`  
- [x] Live `apply_campaign_ai_week_live` · PI priority **138**  

Catalogue labels: campaign ai · multi-month · major #34 · phase3_depth  

### Next-390 — PHASE3 DEPTH (12)
Product UX compact/chips/hotkeys/close · designer domain catalog/pick/seed/close · campaign AI board/weekly/execute/close.

Catalogue labels: product ux compact day · product ux chips day · product ux hotkeys day · product ux polish close day · designer domain catalog day · designer domain pick day · designer domain seed day · designer domain live close day · campaign ai month board day · campaign ai weekly plan day · campaign ai theater execute day · campaign ai multi-month close day · next-390  

Dual marker: `phase3_depth_live=1` (ux_ticks · designer_seeds · ai_weeks)

---

## Majors #29 + #30 + #31 + Next-380 — PHASE 2 CONQUEST (complete)

### Major #29 — OCCUPATION RESISTANCE/COMPLIANCE PRODUCT
- [x] **Occupation resistance/compliance product** — board R/C → set policy (harsh/moderate/lenient) → daily occupation tick  
- [x] **Per-step** — `occupation_resistance_board` · `occupation_resistance_policy` · `occupation_resistance_tick`  
- [x] Live `apply_occupation_policy_live` / `apply_occupation_daily_tick_live` · PI priority **133**  

Catalogue labels: occupation resistance · resistance/compliance · major #29 · phase2_conquest  

### Major #30 — MANPOWER LAWS/TRAINING PRODUCT
- [x] **Manpower laws/training product** — law board → training pipeline → field trained manpower  
- [x] **Per-step** — `manpower_law_board` · `manpower_train_pipeline` · `manpower_field_trained`  
- [x] Live `apply_manpower_law_live` / `apply_manpower_training_tick_live` · PI priority **134**  

Catalogue labels: manpower laws · manpower training · major #30 · phase2_conquest  

### Major #31 — PEACE CONFERENCE SETTLEMENT PRODUCT
- [x] **Peace conference settlement product** — end-war board → demands package → settle map ownership  
- [x] **Per-step** — `peace_conference_board` · `peace_conference_demands` · `peace_conference_settle`  
- [x] Live `apply_peace_conference_settlement_live` · PI priority **135**  

Catalogue labels: peace conference · settlement · major #31 · phase2_conquest  

### Next-380 — PHASE2 CONQUEST DEPTH (12)
Occupation resistance board/policy/tick/close · manpower law/train/field/close · peace board/demands/settle/close.

Catalogue labels: occupation resistance board day · occupation resistance policy day · occupation resistance tick day · occupation resistance close day · manpower law board day · manpower train pipeline day · manpower field trained day · manpower laws training close day · peace conference board day · peace conference demands day · peace conference settle day · peace conference campaign close day · next-380  

Dual marker: `phase2_conquest_live=1` (occupation_ticks · manpower_ticks · peace_settlements)

---

## Major #28 + Next-370 — APPLY-QUEUE LIVE MANAGERS (Phase 1 P0 complete)

### Major #28 — APPLY-QUEUE LIVE MANAGERS PRODUCT
- [x] **Apply-queue live managers product** — audit core leaves → production/supply live harden → combat/station/focus/agent prove  
- [x] **Per-step** — `apply_queue_live_audit` · `apply_queue_live_production` · `apply_queue_live_combat`  
- [x] Hardened leaves: ProductionManager.daily_production_tick · SupplyManager.advance_supply_day · focus trail · Battle/Fleet paths  
- [x] Dual marker `apply_queue_live=N/6` · PI priority **132**  

Catalogue labels: apply-queue live managers · apply queue live · major #28 · apply_queue_live  

### Next-370 — APPLY-QUEUE LIVE DEPTH (10)
Audit · production/combat/supply/focus/agent/station live days · six-leaf joint · honesty joint · close.

Catalogue labels: apply queue audit day · apply queue production live day · apply queue combat live day · apply queue supply live day · apply queue focus live day · apply queue agent live day · apply queue station live day · apply queue six leaf joint day · apply queue honesty joint day · apply queue live managers close day · next-370  

---

## Major #27 + Next-360 — MEDIUM-TANK PRODUCTION HONESTY (Phase 1 P0)

### Major #27 — MEDIUM-TANK PRODUCTION HONESTY PRODUCT
- [x] **Medium-tank production honesty product** — prove 60d seed → 80d factory risk → 100d complete unit equip  
- [x] **Per-step** — `medium_honesty_prove_60d` · `medium_honesty_prove_80d` · `medium_honesty_prove_100d`  
- [x] Unit sheet (crew/reliability/modules) · `medium_tank_complete` dual marker · PI priority **131**  

Catalogue labels: medium-tank production honesty · medium honesty · major #27 · medium_tank_complete  

### Next-360 — PRODUCTION HONESTY DEPTH (10)
60/80/100 windows · unit stats · factory risk · stockpile · readiness/manpower/economy joints · close.

Catalogue labels: medium honesty 60d day · medium honesty 80d day · medium honesty 100d day · medium honesty unit stats day · medium honesty factory risk day · medium honesty stockpile day · medium honesty readiness joint day · medium honesty manpower joint day · medium honesty economy joint day · medium tank production honesty close day · next-360  

---

# Epochs of Ascendancy — Project State Summary

> **Full assessment (2026-07-13):** see root `GAME_STATUS_ASSESSMENT.md` for done vs remaining across all pillars.  
> **Latest delivery:** Majors **#24 Occupation · #25 Manpower · #26 Leader** + **Next-350** (dual world_full 2665 · majors_grew=7/7 · SCRIPT 0).  
> **Product count:** 26 vertical majors · day waves through next-350 · PI priorities through 130.

---

## Majors #24 + #25 + #26 + Next-350 — OCCUPATION · MANPOWER · LEADER COMMAND

### Major #24 — OCCUPATION CONTROL PRODUCT
- [x] **Occupation control product** — control board → garrison/secure → integrate economy/front  
- [x] **Per-step** — `occupation_control_board` · `occupation_control_garrison` · `occupation_control_integrate`  
- [x] PI priority 128 · always-on  

Catalogue labels: occupation control · occupation control board · major #24 · occupation  

### Major #25 — MANPOWER REINFORCEMENT PRODUCT
- [x] **Manpower reinforcement product** — draft/readiness board → reinforce lines → field OOB units  
- [x] **Per-step** — `manpower_draft_board` · `manpower_reinforce_lines` · `manpower_field_units`  
- [x] PI priority 129 · always-on  

Catalogue labels: manpower reinforcement · manpower draft · major #25 · manpower  

### Major #26 — LEADER COMMAND PRODUCT
- [x] **Leader command product** — assign board → formation station → command ops  
- [x] **Per-step** — `leader_command_assign` · `leader_command_station` · `leader_command_ops`  
- [x] PI priority 130 · always-on  

Catalogue labels: leader command · leader command assign · major #26 · leader  

### Next-350 — OCCUPATION / MANPOWER / LEADER DEPTH (20)
Occupation advanced, manpower advanced, leader joints + close.

Catalogue labels: occupation control advanced day · occupation garrison advanced day · occupation integrate advanced day · occupation front joint day · occupation economy joint day · occupation control close day · manpower draft advanced day · manpower reinforce advanced day · manpower field advanced day · manpower front joint day · manpower economy joint day · manpower reinforcement close day · leader assign advanced day · leader station advanced day · leader ops advanced day · leader occupation joint day · leader manpower joint day · leader intel joint day · leader theater joint day · occupation manpower leader close day · next-350 occupation  

---

## Majors #21 + #22 + #23 + Next-340 — ECONOMY · WEATHER · FRONT CONTINUITY

### Major #21 — WAR ECONOMY MOBILIZATION PRODUCT
- [x] **War economy mobilization product** — board factories/trade → allocate production → sustain war economy  
- [x] **Per-step** — `war_economy_board` · `war_economy_allocate` · `war_economy_sustain`  

Catalogue labels: war economy mobilization · war economy board · major #21 · economy  

### Major #22 — WEATHER THEATER OPS PRODUCT
- [x] **Weather theater ops product** — pressure board → combat/logistics weather gate → crisis response  
- [x] **Per-step** — `weather_theater_pressure` · `weather_theater_gate` · `weather_theater_crisis`  

Catalogue labels: weather theater ops · weather theater pressure · major #22 · weather  

### Major #23 — FRONT CONTINUITY CAMPAIGN PRODUCT
- [x] **Front continuity campaign product** — multi-phase combat → assault follow-on → force/logistics sustain  
- [x] **Per-step** — `front_continuity_combat` · `front_continuity_assault` · `front_continuity_sustain`  

Catalogue labels: front continuity · front continuity combat · major #23 · front  

### Next-340 — ECONOMY / WEATHER / FRONT DEPTH (20)
War economy advanced, weather theater advanced, front continuity joints + close.

Catalogue labels: war economy board advanced day · war economy allocate advanced day · war economy sustain advanced day · war economy logistics joint day · war economy tech joint day · war economy mobilization close day · weather pressure advanced day · weather gate advanced day · weather crisis advanced day · weather front joint day · weather economy joint day · weather theater ops close day · front combat advanced day · front assault advanced day · front sustain advanced day · front weather joint day · front economy joint day · front logistics joint day · front theater command joint day · front continuity campaign close day · next-340 economy  

---

## Majors #18 + #19 + #20 + Next-330 — LOGISTICS · INTEL · WORLD-CLASS COMMAND

### Major #18 — LOGISTICS SUPPLY THEATER PRODUCT
- [x] **Logistics supply theater product** — route audit → basing/fuel sustain → force readiness joint  
- [x] **Per-step** — `logistics_supply_route` · `logistics_supply_sustain` · `logistics_supply_readiness`  

Catalogue labels: logistics supply theater · logistics supply route · major #18 · logistics  

### Major #19 — INTELLIGENCE NETWORK PRODUCT
- [x] **Intelligence network product** — coverage board → counterintel → HH/agent counterplay  
- [x] **Per-step** — `intel_network_coverage` · `intel_network_counterintel` · `intel_network_counterplay`  

Catalogue labels: intelligence network · intel network coverage · major #19 · intelligence  

### Major #20 — WORLD-CLASS CAMPAIGN COMMAND PRODUCT
- [x] **World-class campaign command product** — scan multi-domain majors → rank urgency → execute top leaf  
- [x] **Per-step** — `world_class_scan` · `world_class_rank` · `world_class_execute`  

Catalogue labels: world-class campaign command · world class scan · major #20 · world class  

### Next-330 — WORLD-CLASS DEPTH (20)
Logistics advanced, intelligence advanced, world-class command joints + close.

Catalogue labels: logistics route advanced day · logistics sustain advanced day · logistics readiness advanced day · logistics naval joint day · logistics tech industry joint day · logistics supply close day · intel coverage advanced day · intel counterintel advanced day · intel counterplay advanced day · intel diplomacy joint day · intel session joint day · intelligence network close day · world class scan advanced day · world class rank advanced day · world class execute advanced day · world class logistics intel joint day · world class air naval joint day · world class session ai joint day · world class theater command joint day · world class campaign close day · next-330 world  

---

## Majors #16 + #17 + Next-320 — DIPLOMACY · TECH · 20 ADVANCED

### Major #16 — DIPLOMACY / PEACE CAMPAIGN PRODUCT (deferred diplomacy first slice)
- [x] **Diplomacy peace campaign product** — board pressure → agent/HH leverage → settle  
- [x] **Per-step** — `diplomacy_peace_board` · `diplomacy_peace_leverage` · `diplomacy_peace_settle`  
- [x] Panel · PI (priority 121) · CI · integrity  

Catalogue labels: diplomacy peace · diplomacy peace board · major #16 · diplomacy  

### Major #17 — TECH / RESEARCH CAMPAIGN PRODUCT (deferred research first slice)
- [x] **Tech research campaign product** — design catalog → production priority → field seed/OOB  
- [x] **Per-step** — `tech_research_catalog` · `tech_research_priority` · `tech_research_field`  
- [x] Panel · PI (priority 120) · CI · integrity  

Catalogue labels: tech research · tech research catalog · major #17 · research  

### Next-320 — DIPLOMACY/TECH ADVANCED (20)
- [x] Diplomacy board/leverage/settle/trade/agent-HH/focus/close (7)  
- [x] Tech catalog/priority/field/designer/OOB/industry-focus/close (7)  
- [x] Diplo-tech joint · tech-AI · diplo-naval-air · session joint · multi-faction · campaign close (6)  

Catalogue labels: diplomacy board advanced day · diplomacy leverage advanced day · diplomacy settle advanced day · diplomacy trade pressure day · diplomacy agent hh joint day · diplomacy focus peace joint day · diplomacy peace close day · tech catalog advanced day · tech priority advanced day · tech field advanced day · tech designer joint day · tech oob fielding joint day · tech industry focus joint day · tech research close day · diplomacy tech joint day · tech ai research joint day · diplomacy naval air joint day · session diplomacy tech joint day · multi faction diplo tech day · diplomacy tech campaign close day · next-320 diplomacy  

### Deferred key items (updated)
- Multiplayer — N3/N4 dual foothold (product multiplayer still open)  
- Diplomacy / peace conference — **first product slice LANDED** (major #16)  
- Tech / research trees — **first product slice LANDED** (major #17)  
- Focus trees · naval multi-phase · air ops — first slices LANDED (#13–#15)  
- Designers HOI4 suite · full campaign AI — later  

## Majors #14 + #15 + Next-310 — DEFERRED ADVANCED PILLARS (20+ deliverables)

### Major #14 — FOCUS WAR PATH PRODUCT (deferred focus-tree first slice)
- [x] **Focus war path product** — pick → war-path order → commit/execute  
- [x] **Per-step** — `focus_war_pick` · `focus_war_path_step` · `focus_war_commit`  
- [x] Panel · PI (priority 119) · CI · integrity  

Catalogue labels: focus war path · focus war pick · major #14 · war path  

### Major #15 — NAVAL MULTI-PHASE CAMPAIGN PRODUCT (deferred naval combat first slice)
- [x] **Naval multi-phase campaign product** — posture → escort → strike  
- [x] **Per-step** — `naval_phase_posture` · `naval_phase_escort` · `naval_phase_strike`  
- [x] Panel · PI (priority 118) · CI · integrity  

Catalogue labels: naval multi-phase · naval phase posture · major #15 · naval  

### Next-310 — ADVANCED DEFERRED (20)
- [x] Focus advanced board/path/commit/naval/industry/air/close (7)  
- [x] Naval posture/escort/strike/fuel/autonomy/air-joint/close (7)  
- [x] Designer domain/seed · strategic AI multi-day · designer-AI industry · play session joint · advanced close (6)  

Catalogue labels: focus pick board advanced day · focus war path advanced day · focus commit execute advanced day · focus naval effort advanced day · focus industry army joint day · focus air effort joint day · focus war path close day · naval posture advanced day · naval escort phase advanced day · naval strike phase advanced day · naval fleet fuel advanced day · naval fleet autonomy joint day · naval air joint advanced day · naval multi-phase close day · designer domain advanced day · designer seed advanced day · strategic ai multi-day advanced day · designer ai industry joint day · play session advanced joint day · advanced deferred campaign close day · next-310 advanced  

### Deferred key items (updated)
- Multiplayer — N3/N4 dual foothold (product multiplayer still open)  
- Focus trees — **first product slice LANDED** (major #14)  
- Full multi-phase naval combat — **first product slice LANDED** (major #15)  
- Designers HOI4 suite — first slice + advanced days; full suite later  
- Deep campaign AI — board/daily/multi-day advanced days; full AI later  

## Major #12 + #13 — PLAY SESSION · AIR OPS CAMPAIGN PRODUCTS

### Major #12 — PLAY SESSION CAMPAIGN PRODUCT
- [x] **Play session campaign product** — brief → execute orders → resolve (AI day + feedback)  
- [x] **Per-step** — `play_session_brief` · `play_session_execute` · `play_session_resolve`  
- [x] Composes theater command · order execute · strategic AI daily · next-day feedback · save browser  
- [x] OrderCommandPanel orders strip · PI chip (priority 117) · CI · integrity  

Catalogue labels: play session campaign · play session brief · play session execute · major #12 · play session  

### Major #13 — AIR OPS CAMPAIGN PRODUCT (first vertical air)
- [x] **Air ops campaign product** — sortie readiness → weather gate → air-land joint  
- [x] **Per-step** — `air_ops_sortie` · `air_ops_weather_gate` · `air_ops_air_land`  
- [x] Composes air packages · forecast · multi-phase combat support  
- [x] OrderCommandPanel orders strip · PI chip (priority 116) · CI · integrity  

Catalogue labels: air ops campaign · air ops sortie · air ops weather gate · major #13 · air ops  

### Deferred key items (updated)
- Multiplayer — still deferred  
- Complete tank/ship/space designers suite — first slice LANDED (#10)  
- Deep multi-faction strategic AI — board + daily tick LANDED (#9/#11); full campaign AI later  
- Full air/naval multi-phase combat suite — **air ops first product slice LANDED** (#13)  

## Next 48 hours (Top 5) — NEXT-300 PLAYABILITY CAMPAIGN (20)

- [x] **#1 Air ops sortie · forecast planning · sortie weather gate · convoy escort campaign** — next-300 air  
- [x] **#2 Air land campaign · air front readiness · air convoy campaign close** — next-300 air close  
- [x] **#3 Focus pick · focus order path · focus war path · war path urgency** — next-300 focus  
- [x] **#4 Intel counter · leader campaign assign · focus intel leader close** — next-300 intel  
- [x] **#5 Order execute session · next day feedback · campaign decision · theater AI session · force readiness session · play session campaign close + dual** — next-300 session  

Catalogue (labels for gates):
- air ops sortie depth day · air forecast planning depth day · air sortie weather gate day · convoy escort campaign depth day  
- air land campaign depth day · air front readiness depth day · air convoy campaign close day  
- focus pick depth day · focus order path day · focus war path depth day · war path urgency depth day  
- intel counter depth campaign day · leader campaign assign day · focus intel leader close day  
- order execute session day · next day feedback session day · campaign decision session day · theater ai session joint day  
- force readiness session day · play session campaign close day · next-300 playability  

## Next 48 hours (Top 5) — NEXT-290 FULL-GAME CAMPAIGN (20)

- [x] **#1 Strategic AI doctrine · urgency board · player skip · budget depth** — next-290 AI  
- [x] **#2 Domain weight · daily joint · strategic AI campaign close** — next-290 AI close  
- [x] **#3 Designer catalog · seed production · domain balance · OOB horizon joint** — next-290 designers  
- [x] **#4 Production bootstrap · industry design joint · designer industry close** — next-290 industry  
- [x] **#5 Theater AI command · fleet/agent/combat AI depth · save session AI · full game campaign close + dual** — next-290 campaign  

Catalogue (labels for gates):
- strategic ai doctrine depth day · strategic ai urgency board day · strategic ai player skip day · strategic ai budget depth day  
- strategic ai domain weight day · strategic ai daily joint day · strategic ai campaign close day  
- designer catalog depth day · designer seed production day · designer domain balance day · oob horizon joint day  
- production line bootstrap day · industry design joint day · designer industry close day  
- theater ai command joint day · fleet ai campaign depth day · agent ai campaign depth day · combat ai phase depth day  
- save session ai joint day · full game campaign close day · next-290 full-game  

## Major #11 — STRATEGIC AI DAILY CAMPAIGN PRODUCT (deferred AI day tick)

- [x] **Strategic AI daily campaign product** — multi-faction board → AI day budget (skip player) → apply queue  
- [x] **Per-step** — `strategic_ai_daily_board` · `strategic_ai_daily_budget` · `strategic_ai_daily_apply`  
- [x] **Live day tick** — `run_daily_theater_auto_tick_multi` injects apply on each auto day  
- [x] OrderCommandPanel orders strip · PI chip (priority 115) · CI · integrity  

Catalogue labels: strategic AI daily campaign · strategic ai daily board · major #11 · strategic AI · daily campaign  

### Deferred key items (updated)
- Multiplayer — still deferred  
- ~~Full Natural Earth~~ LANDED  
- Complete tank/ship/space designers suite — first product slice LANDED (major #10); full HOI4 suite still later  
- Deep multi-faction strategic AI — product board LANDED (#9) + **daily tick slice LANDED** (#11); full campaign AI still later  

## Major #10 — DESIGNER SUITE PRODUCT (first deferred designers slice)

- [x] **Designer suite product** — land/naval/air/space catalog → pick → seed production  
- [x] **Live catalog** from DesignManager active designs when available  
- [x] **Per-step** — `designer_suite_catalog` · `designer_suite_pick` · `designer_suite_seed`  
- [x] Domain buttons · production bootstrap on seed · panel/PI/CI  

Catalogue labels: designer suite product · designer suite catalog · designer domain land · major #10 · designers  

### Deferred key items (updated)
- Multiplayer — still deferred  
- ~~Full Natural Earth~~ LANDED  
- Complete tank/ship/space designers suite — **first product slice LANDED** (major #10); full HOI4 suite still later  
- Deep multi-faction strategic AI — first product slice LANDED (major #9); daily tick #11 LANDED  

## Major #9 — MULTI-FACTION STRATEGIC AI PRODUCT (first deferred AI slice)

- [x] **Multi-faction strategic AI product** — GER/FRA/ENG/USA/SOV/ITA/JAP doctrine × theater domains  
- [x] **Per-step** — `strategic_ai_scan` · `strategic_ai_rank` · `strategic_ai_execute`  
- [x] Urgency board · top faction/domain leaf apply  
- [x] OrderCommandPanel orders strip · PI · CI · integrity  

Catalogue labels: multi-faction strategic AI · strategic ai scan · strategic ai rank · major #9 · strategic AI  

### Deferred key items (updated)
- Multiplayer — N3/N4 dual foothold (product multiplayer still open)  
- ~~Full Natural Earth province geometry~~ LANDED  
- Complete tank/ship/space designers suite — still deferred (hooks only)  
- Deep multi-faction strategic AI — **first product slice LANDED** (not finished campaign AI)  

## Natural Earth full geometry — ALL 2665 (COMPLETE)

- [x] **NE 10m land** rasterized to world_full canvas · snap all province rings  
- [x] **`align_ne_full_geometry.py --write --full --backup`** — id-stable full stamp  
- [x] **2665/2665** `gis_ne_full` + `gis_pilot` · land 2325 · water 340 · triangles=0  
- [x] Pure integrity · map CI · dual bar  

Catalogue labels: Natural Earth · NE full · gis_ne_full · ne_10m_land · 2665  

## GIS littoral expand — depth-2 near-coast inland (753 → 1343)

- [x] **`near_coast_inland_ids` + `littoral_depth`** — ring-2 inland belt beyond water-adjacent littoral  
- [x] CLI `--littoral-depth 2` on `ingest_gis_coastlines.py` (with `--include-littoral`)  
- [x] Guarded write: **1343** id-stable stamps · triangles=0 · min verts ≥16 · backup `.bak`  
- [x] Pool: depth1 **753** · depth2 **1343** (+590 near-coast inland)  
- [x] Pure gates + map CI hook · dual bar held  

Catalogue labels: GIS×1343 · littoral depth · near-coast inland · gis pilot  

## High-value workset — INSPECTOR DECISION · THEATER COMMAND · MEDIUM COMPLETE WINDOW

### Major #7 — INSPECTOR DECISION PRODUCT
- [x] **Inspector decision product** — primary strip · chip budget collapse · apply leaf  
- [x] **Per-step apply** — `inspector_product_primary` · `inspector_product_collapse` · `inspector_product_apply`  
- [x] Major product chip priority boost (combat/fleet/OOB/agent/HH always-on band)  
- [x] OrderCommandPanel orders section · PI chip · CI · integrity  

Catalogue labels: inspector decision product · inspector product primary · inspector product collapse · major #7  

### Major #8 — THEATER COMMAND PRODUCT
- [x] **Theater command product** — ranks combat · fleet · industry · HH · agent into one strip  
- [x] **Per-step apply** — `theater_command_scan` · `theater_command_rank` · `theater_command_execute`  
- [x] OrderCommandPanel primary strip (reduces day-package sprawl) · PI · CI · integrity  

Catalogue labels: theater command product · theater command scan · theater command rank · major #8  

### Medium complete window evidence
- [x] `EOA_MEDIUM_OOB_EVIDENCE_DAYS` optional extended ticks after OOB window  
- [x] Progress evidence uses day-based `production_progress` / days_per_unit  

Catalogue labels: medium complete window · EOA_MEDIUM_OOB_EVIDENCE_DAYS · multi-month equip honesty  

## Major #6 + medium-tank progress evidence — AGENT CAMPAIGN PRODUCT

### Major #6 — AGENT CAMPAIGN PRODUCT (high priority)
- [x] **Agent campaign product** — board → coverage dispatch → counterplay/escalation  
- [x] **Per-step apply path** — `agent_product_board` · `agent_product_dispatch` · `agent_product_counterplay`  
- [x] **Live signals** — HH map signal + trail → MapManager product  
- [x] **OrderCommandPanel agent section** — product body (major #6)  
- [x] **ProvinceInsight chip** · CI · pure integrity + signal-shift gate  

Catalogue labels: agent campaign product · agent product board · agent product dispatch · agent product counterplay · major #6  

### Medium-tank OOB progress evidence (P1 honesty)
- [x] **ScenarioLoader medium-line progress print** after OOB evidence window  
- [x] Reports prog% / units done for medium OOB lines (complements infantry stockpile growth)  

Catalogue labels: medium-tank OOB progress · medium OOB lines · multi-month equip honesty  

## Major #3 + #5 shipped — MEDIUM-TANK OOB · HH MULTI-MONTH AGENDA

### Major #3 — MEDIUM-TANK OOB / MULTI-MONTH EQUIP PRODUCT
- [x] **Medium-tank OOB product** — 60/80/100d equip horizons · factory risk · production priority  
- [x] **Per-horizon apply path** — `oob_horizon_60d` · `oob_horizon_80d` · `oob_horizon_100d`  
- [x] **Live province product** — MapManager factories/weather · sequence apply  
- [x] **OrderCommandPanel industry section** — product body with three horizon buttons (major #3)  
- [x] **ProvinceInsight chip** · CI · pure integrity + complete-100d gate  

Catalogue labels: medium-tank OOB · oob horizon 60d · oob horizon 80d · oob horizon 100d · major #3  

### Major #5 — HH MULTI-MONTH AGENDA PRODUCT
- [x] **HH multi-month agenda product** — trail board · monthly brief · quarterly counterplay  
- [x] **Class filter** · commit/counterplay as primary product actions  
- [x] **Per-step apply path** — `hh_month_trail_board` · `hh_month_brief` · `hh_month_quarterly_counter`  
- [x] **OrderCommandPanel HH section** — multi-month product body (major #5)  
- [x] **ProvinceInsight chip** · CI · pure integrity + multi-month trail gate  

Catalogue labels: HH multi-month agenda · hh month trail board · hh month brief · hh month quarterly counter · major #5  

## Major #2 hardened + Major #4 shipped — FLEET SEQUENCE · SAVE BROWSER CAMPAIGN

### Major #2 (fleet multi-day autonomy) — complete
- [x] Product surface Day 0–2 + recommended step  
- [x] **Full multi-day sequence** `fleet_multi_day_sequence` (0→1→2 apply path)  
- [x] Panel button · GameData/MapManager sequence apply  

### Major #4 — SAVE BROWSER CAMPAIGN PRODUCT
- [x] **Save browser campaign product** — live slots from SaveLoadManager  
- [x] **Resume recommended** · **Checkpoint autosave** · Quicksave  
- [x] Per-row Save/Load via `save_slot:` / `load_slot:` → `save_game_detailed` / `load_game_detailed`  
- [x] OrderCommandPanel saves section rebuilt as major #4 product body  
- [x] ProvinceInsight chip · CI · pure integrity  

Catalogue labels: save browser campaign · save browser resume · save browser checkpoint · fleet multi-day sequence · major #4 · major #2  

## Major #2 in progress — FLEET MULTI-DAY AUTONOMY PRODUCT (+ next-70/80 depth)

- [x] **Fleet multi-day autonomy product** — Day 0 posture/tasking · Day 1 station/escort · Day 2 follow-through  
- [x] **Per-day apply path** — `fleet_day_posture` · `fleet_day_station_escort` · `fleet_day_follow_through`  
- [x] **Live province product** — MapManager fuel/basing tag · station mutation on posture/follow  
- [x] **OrderCommandPanel fleet section** — product surface with recommended day step + three day buttons (major #2 body)  
- [x] **Playability/execution depth** — decision strip compose + next-70/80 recheck green  
- [x] **ProvinceInsight chip** · CI hook · pure integrity + fuel-shift gate  

Catalogue labels: fleet multi-day autonomy · fleet day posture · fleet day station escort · fleet day follow-through · major #2  

## Major #1 in progress — MULTI-PHASE COMBAT PRODUCT UI

- [x] **Multi-phase combat product package** — approach/engage/disengage estimate + phase ribbon + recommendation  
- [x] **Per-phase apply path** — `phase_approach` → supply soften · `phase_engage` → assault · `phase_disengage` → station hold  
- [x] **Live province product** — MapManager resolves force/weather · BattleManager product APIs  
- [x] **OrderCommandPanel combat section** — product ribbon · phase rows · recommended + three phase buttons (major #1 body)  
- [x] **ProvinceInsight chip** · CI hook · pure integrity + weather shift gate  

Catalogue labels: multi-phase combat product · phase approach · phase engage · phase disengage · major #1  

## Policy shift — un-defer majors (post next-280)

Day-package product depth (next-10…next-280), dual world_full green (2665 · Industry · Formation · majors_grew=7/7 · SCRIPT 0), and map CI exit 0 are enough to **stop treating every large pillar as permanently deferred**.

### Still deferred (high cost / thin foundation)
- **Multiplayer** — N3/N4 dual foothold (not full product multiplayer)  
- **~~Full Natural Earth province geometry for all 2665~~ LANDED** — NE 10m full stamp; optional higher-res fjord mesh later  
- **Complete tank/ship/space designers as HOI4 suite** — **first product slice LANDED** (major #10); full HOI4 suite still later  
- **Deep multi-faction strategic AI** — product board LANDED (#9) + **daily tick slice LANDED** (#11); full campaign AI still later  

### Now OPEN (un-deferred) — next major build targets

| # | Major item | Why foundation is ready | First concrete slice |
|---|------------|-------------------------|----------------------|
| **1** | **Multi-phase combat product UI** | estimate/UI product/assault ready/BattleManager + next-260 combat surface | Interactive phase ribbon + engage/disengage apply path on live map (not day-stub only) |
| **2** | **Fleet AI autonomy (multi-day)** | task groups, naval campaign, basing sustain, convoy/sealane, fleet_autonomy day | Theater fleet decision loop: posture → station/escort → multi-day follow-through |
| **3** | **Medium-tank OOB / multi-month equip honesty** | equip plan, production surge, infantry OOB @ 20d proven | Prove major medium lines complete units in a 60–100d evidence window |
| **4** | **Save-browser campaign UX** | next-260 save/session depth + SaveLoadManager slots | Occupied/empty browser → resume → checkpoint without day-package indirection |
| **5** | **HH multi-month agenda product** | agenda screen/pick/actions/trail/counterplay landed as days | Multi-week trail board with faction filter + commit/counterplay as primary UI |

---

## Next-20 completion package (landed 2026-07-16)

Vertical slices of OPEN majors #1–#5 — **20 live steps** (4 each):

- [x] Combat UI: ribbon · approach · engage · disengage
- [x] Fleet multi-day: posture · station/escort · follow-through · autonomy close
- [x] Medium OOB: line scan · 60d · 100d · equip close
- [x] Save browser: list · resume · checkpoint · close
- [x] HH agenda: faction filter · monthly commit · quarterly counter · depth close
- [x] Pure product `next20_completion_package_product.py` · GameData `apply_next20_*` · dual `next20_completion_live=1`
- Still deferred (high cost): true multiplayer netcode · full HOI 3D designers · full-world photoreal remesh · graphical 60 fps hard gate

Catalogue labels: next20_completion · open_major_1_combat_ui · open_major_2_fleet · open_major_3_medium_oob · open_major_4_save_browser · open_major_5_hh  

### Build rule going forward
- Prefer **vertical slices** of these five over another pure day-wave catalogue unless dual/CI regresses.  
- Day packages remain the composition pattern **inside** each major, not a substitute for shipping the major.  
- Dual + map CI + SCRIPT 0 remain the quality bar.

---

## Next 48 hours (Top 5) — NEXT-280 WEATHER/ECONOMY/FORCE (20)

- [x] **#1 Weather pressure depth · foul combat ops · weather logistics depth · weather move depth** — next-280 weather  
- [x] **#2 Weather crisis depth · weather pressure joint · weather ops close depth** — next-280 weather close  
- [x] **#3 Trade pressure depth · sealane health depth · war economy sustain · stockpile economy depth** — next-280 economy  
- [x] **#4 Convoy economy joint · trade sealane joint · war economy close depth** — next-280 trade  
- [x] **#5 Force ready surface · formation equip depth · reinforce stockpile · readiness board · force reinforce joint · weather economy force close + dual** — next-280 force  

Catalogue (labels for gates):
- weather pressure depth day · foul combat ops day · weather logistics depth day · weather move depth day · weather crisis depth day  
- weather pressure joint day · weather ops close depth day · trade pressure depth day · sealane health depth day · war economy sustain day  
- stockpile economy depth day · convoy economy joint day · trade sealane joint day · war economy close depth day  
- force ready surface day · formation equip depth day · reinforce stockpile depth day · readiness board ops day  
- force reinforce joint day · weather economy force close day · next-280 weather  

## Next 48 hours (Top 5) — NEXT-270 NAVAL/THEATER/INSPECTOR (20)

- [x] **#1 Naval basing sustain · port fuel depth · basing repair depth · fleet task sustain** — next-270 naval  
- [x] **#2 Convoy basing joint · naval logistics depth · naval basing close** — next-270 basing close  
- [x] **#3 Multi day theater depth · theater campaign continuity · campaign day chain · theater session ops** — next-270 theater  
- [x] **#4 Daily theater sustain · theater continuity joint · theater campaign depth close** — next-270 continuity  
- [x] **#5 Inspector decision depth · decision strip depth · insight strip · province decision joint · inspector campaign ops · theater naval inspector close + dual** — next-270 inspector  

Catalogue (labels for gates):
- naval basing sustain day · port fuel depth day · basing repair depth day · fleet task sustain day · convoy basing joint day  
- naval logistics depth day · naval basing close day · multi day theater depth day · theater campaign continuity day · campaign day chain day  
- theater session ops day · daily theater sustain day · theater continuity joint day · theater campaign depth close day  
- inspector decision depth day · decision strip depth day · insight strip depth day · province decision joint day  
- inspector campaign ops day · theater naval inspector close day · next-270 naval  

## Next 48 hours (Top 5) — NEXT-260 SAVE/PROD/COMBAT (20)

- [x] **#1 Save slot depth · autosave session depth · campaign session depth** — next-260 save  
- [x] **#2 Save resume · session checkpoint · save audit · save session close depth** — next-260 session  
- [x] **#3 Factory risk surge · production priority depth · stockpile surge ops · line continuity depth** — next-260 production  
- [x] **#4 Industry surge joint · production oob depth · production surge close** — next-260 industry  
- [x] **#5 Multi phase estimate depth · assault ready surface · combat order surface · phase product ops · multi phase joint · save prod combat close + dual** — next-260 combat  

Catalogue (labels for gates):
- save slot depth day · autosave session depth day · campaign session depth day · save resume depth day · session checkpoint depth day  
- save audit depth day · save session close depth day · factory risk surge day · production priority depth day · stockpile surge ops day  
- line continuity depth day · industry surge joint day · production oob depth day · production surge close day  
- multi phase estimate depth day · assault ready surface day · combat order surface day · phase product ops day  
- multi phase joint day · save prod combat close day · next-260 save  


## Next 48 hours (Top 5) — NEXT-250 LEADER/INTEL/THEATER (20)

- [x] **#1 Leader assign depth · formation ready depth · leader weather depth · formation station depth · leader formation joint depth** — leader/formation command  
- [x] **#2 OOB leader · leader formation close depth** — leader formation close path  
- [x] **#3 Intel counter depth · HH counterplay depth · agent response depth · trail intel · counterintel board** — intel/counterintel  
- [x] **#4 Intel response joint · intel counter close · theater daily depth · multi province rank depth · daily auto depth** — intel close + theater  
- [x] **#5 Theater brief · multi province command · leader intel theater close + dual** — next-250 leader  

### Next-250 leader/intel/theater package catalogue (20)

- leader assign depth day · formation ready depth day · leader weather depth day · formation station depth day · leader formation joint depth day  
- oob leader ops day · leader formation close depth day · intel counter depth day · hh counterplay depth day · agent response depth day  
- trail intel ops day · counterintel board ops day · intel response joint day · intel counter close day · theater daily depth day  
- multi province rank depth day · daily auto depth day · theater brief ops day · multi province command day · leader intel theater close day  

## Next 48 hours (Top 5) — NEXT-240 AIR/CONVOY/ORDER (20)

- [x] **#1 Air sortie depth · air land joint depth · multi domain · air front readiness · domain joint** — air-land multi-domain  
- [x] **#2 Air land campaign · air domain close** — air domain close path  
- [x] **#3 Convoy escort depth · sealane health · trade pressure · convoy sealane joint · sealane logistics** — convoy/sealane logistics  
- [x] **#4 Wartime trade · convoy sealane close · order execute depth · map effect resolve · next day feedback depth** — convoy close + order  
- [x] **#5 Order effect joint · feedback loop · air convoy order close + dual** — next-240 air  

### Next-240 air/convoy/order package catalogue (20)

- air sortie depth day · air land joint depth day · multi domain ops day · air front readiness day · domain joint ops day  
- air land campaign day · air domain close day · convoy escort depth day · sealane health ops day · trade pressure ops day  
- convoy sealane joint day · sealane logistics ops day · wartime trade ops day · convoy sealane close day · order execute depth day  
- map effect resolve day · next day feedback depth day · order effect joint day · feedback loop ops day · air convoy order close day  

## Next 48 hours (Top 5) — NEXT-230 FORCE/WEATHER/FOCUS (20)

- [x] **#1 Force readiness depth · multi front supply depth · depot route · force posture depth · front supply rank** — force readiness/multi-front supply  
- [x] **#2 Force supply joint · force supply close** — force supply close path  
- [x] **#3 Weather pressure · campaign crisis · prod weather crisis · combat weather · weather crisis brief** — weather×campaign crisis  
- [x] **#4 Weather campaign joint · weather crisis close · focus war path · strategic strip depth · strategic continuity depth** — weather close + focus  
- [x] **#5 War cabinet pulse · focus continuity joint · force weather focus close + dual** — next-230 force  

### Next-230 force/weather/focus package catalogue (20)

- force readiness depth day · multi front supply depth day · depot route ops day · force posture depth day · front supply rank day  
- force supply joint day · force supply close day · weather pressure ops day · campaign crisis ops day · prod weather crisis day  
- combat weather ops day · weather crisis brief day · weather campaign joint day · weather crisis close day · focus war path ops day  
- strategic strip depth day · strategic continuity depth day · war cabinet pulse ops day · focus continuity joint day · force weather focus close day  

## Next 48 hours (Top 5) — NEXT-220 OOB/FLEET/HH (20)

- [x] **#1 Equip horizon depth · stockpile line · OOB line continuity · factory OOB depth · medium horizon plan** — medium-horizon OOB/equip  
- [x] **#2 Equip stockpile joint · equip OOB close** — equip close path  
- [x] **#3 Fleet multi theater · fleet redeploy · task group posture · fleet posture · redeploy route** — fleet multi-theater/redeploy  
- [x] **#4 Fleet theater joint · fleet redeploy close · HH monthly · HH quarterly · agenda pulse** — fleet close + HH  
- [x] **#5 Trail counterplay · HH agenda depth joint · OOB fleet HH close + dual** — next-220 oob  

### Next-220 oob/fleet/hh package catalogue (20)

- equip horizon depth day · stockpile line ops day · oob line continuity day · factory oob depth day · medium horizon plan day  
- equip stockpile joint day · equip oob close day · fleet multi theater ops day · fleet redeploy ops day · task group posture ops day  
- fleet posture ops day · redeploy route ops day · fleet theater joint day · fleet redeploy close day · hh monthly ops day  
- hh quarterly ops day · agenda pulse ops day · trail counterplay ops day · hh agenda depth joint day · oob fleet hh close day  

## Next 48 hours (Top 5) — NEXT-210 ASSAULT/CHOKE/AGENT (20)

- [x] **#1 Follow on assault · reinforced combat · war path urgency · assault follow · reinforce step** — reinforced assault/follow-on  
- [x] **#2 Combat urgency · follow reinforce close** — combat close path  
- [x] **#3 Choke sea wx · sea zone mod · basing choke · choke control · sea zone control** — choke/sea-zone control  
- [x] **#4 Choke basing joint · choke sea close · agent escalation · coverage · counter ops board** — choke close + agent  
- [x] **#5 Escalation ladder · agent coverage joint · assault choke agent close + dual** — next-210 assault  

### Next-210 assault/choke/agent package catalogue (20)

- follow on assault ops day · reinforced combat ops day · war path urgency ops day · assault follow ops day · reinforce step ops day  
- combat urgency ops day · follow reinforce close day · choke sea wx ops day · sea zone mod ops day · basing choke ops day  
- choke control ops day · sea zone control ops day · choke basing joint day · choke sea close day · agent escalation ops day  
- coverage ops day · counter ops board ops day · escalation ladder ops day · agent coverage joint day · assault choke agent close day  

## Next 48 hours (Top 5) — NEXT-200 INSPECTOR/INFRA/AUTO (20)

- [x] **#1 Panel surface · tooltip chip · insight budget · order surface · product chip** — inspector/product-surface  
- [x] **#2 Surface refresh · inspector surface close** — surface close path  
- [x] **#3 Infra invest · special site · construction · infra project · investment status** — infrastructure/investment  
- [x] **#4 Infra site joint · infra invest close · daily auto · theater tick · multi-domain auto** — invest close + daily auto  
- [x] **#5 Daily apply · theater auto joint · inspector infra auto close + dual** — next-200 inspector  

### Next-200 inspector/infra/auto package catalogue (20)

- panel surface ops day · tooltip chip ops day · insight budget ops day · order surface ops day · product chip ops day  
- surface refresh ops day · inspector surface close day · infra invest ops day · special site ops day · construction ops day  
- infra project ops day · investment status ops day · infra site joint day · infra invest close day · daily auto ops day  
- theater tick ops day · multi domain auto ops day · daily apply ops day · theater auto joint day · inspector infra auto close day  

## Next 48 hours (Top 5) — NEXT-190 SAVE/LEADER/TRADE (20)

- [x] **#1 Save slot integrity · autosave session · campaign session · save resume · session checkpoint** — save/session continuity  
- [x] **#2 Save audit · save session close** — save close path  
- [x] **#3 Leader assign · formation ready · OOB assign · leader command · formation station** — leader/formation command  
- [x] **#4 Leader formation joint · leader formation close · trade chain · convoy escort · sealane economy** — leader close + trade  
- [x] **#5 Trade route · convoy trade joint · save leader trade close + dual** — next-190 save  

### Next-190 save/leader/trade package catalogue (20)

- save slot integrity ops day · autosave session ops day · campaign session ops day · save resume ops day · session checkpoint ops day  
- save audit ops day · save session close day · leader assign ops day · formation ready ops day · oob assign ops day  
- leader command ops day · formation station ops day · leader formation joint day · leader formation close day · trade chain ops day  
- convoy escort ops day · sealane economy ops day · trade route ops day · convoy trade joint day · save leader trade close day  

## Next 48 hours (Top 5) — NEXT-180 PRODUCTION/AIR/FOCUS (20)

- [x] **#1 Prod factory risk · medium equip horizon · production priority · OOB equip · factory line** — production/OOB continuity  
- [x] **#2 Stockpile growth · production OOB close** — production close path  
- [x] **#3 Air sortie front · multi-front rank · air-land joint · assault front · air forecast** — air multi-front depth  
- [x] **#4 Multi-front supply · air front close · focus path · war cabinet · strategic strip** — air close + focus strategic  
- [x] **#5 Focus priority · strategic continuity · prod air focus close + dual** — next-180 production  

### Next-180 production/air/focus package catalogue (20)

- prod factory risk ops day · medium equip horizon ops day · production priority ops day · oob equip continuity day · factory line ops day  
- stockpile growth ops day · production oob close day · air sortie front ops day · multi front rank ops day · air land joint ops day  
- assault front ops day · air forecast ops day · multi front supply ops day · air front close day · focus path ops day  
- war cabinet ops day · strategic strip ops day · focus priority ops day · strategic continuity ops day · prod air focus close day  

## Next 48 hours (Top 5) — NEXT-170 COMBAT/AGENT/JOINT (20)

- [x] **#1 Combat phase · assault ready · multi-phase estimate · combat order · assault rank** — combat multi-phase continuity  
- [x] **#2 Phase ribbon · combat phase close** — combat phase close path  
- [x] **#3 Agent mission · dispatch · HH commit · counterplay · HH agenda** — agent/HH campaign path  
- [x] **#4 Agent HH joint · agent HH close · joint theater combat · joint naval combat · focus joint** — joint multi-domain  
- [x] **#5 Joint command · multi domain strip · combat agent joint close + dual** — next-170 combat  

### Next-170 combat/agent/joint package catalogue (20)

- combat phase ops day · assault ready ops day · multi phase est ops day · combat order ops day · assault rank ops day  
- phase ribbon ops day · combat phase close day · agent mission campaign day · agent dispatch ops day · hh commit campaign day  
- counterplay campaign day · hh agenda ops day · agent hh joint day · agent hh close day · joint theater combat day  
- joint naval combat day · focus joint ops day · joint command ops day · multi domain strip day · combat agent joint close day  

## Next 48 hours (Top 5) — NEXT-160 THEATER/NAVAL/SESSION (20)

- [x] **#1 Multi-province · theater auto · daily command · readiness · move path** — theater campaign continuity  
- [x] **#2 Theater order board · theater campaign close** — theater campaign close path  
- [x] **#3 Basing fleet · fleet wx · convoy sustain · sealane joint · naval order** — naval/sealane sustain  
- [x] **#4 Fleet station · naval sealane close · player surface · order panel · mutation feedback** — naval + session path  
- [x] **#5 Apply audit · decision strip · theater naval session close + dual** — next-160 theater  

### Next-160 theater/naval/session package catalogue (20)

- multi province campaign day · theater auto campaign day · daily command ops day · theater readiness ops day · move path campaign day  
- theater order board day · theater campaign close day · basing fleet sustain day · fleet wx sustain day · convoy sustain ops day  
- sealane joint ops day · naval order ops day · fleet station sustain day · naval sealane close day · player surface session day  
- order panel session day · mutation feedback ops day · apply audit session day · decision strip ops day · theater naval session close day  

## Next 48 hours (Top 5) — NEXT-150 WEATHER/ECONOMY/INTEL (20)

- [x] **#1 Combat wx · prod wx · air sortie · morale · convoy wx ops** — weather–ops continuity  
- [x] **#2 Daylight wx · weather ops close** — weather ops close path  
- [x] **#3 War economy · prod campaign · focus wx/mut · supply/depot economy** — strategic / war-economy  
- [x] **#4 War economy close · intel counter · agent intel · HH counter** — intel-counterplay  
- [x] **#5 Map effect · coherence intel · weather economy intel close + dual** — next-150 weather  

### Next-150 weather/economy/intel package catalogue (20)

- combat wx ops day · prod wx ops day · air sortie wx day · morale wx ops day · convoy wx ops day  
- daylight wx ops day · weather ops close day · war economy ops day · prod campaign ops day · focus wx ops day  
- focus mut ops day · supply economy ops day · depot economy ops day · war economy close day · intel counter ops day  
- agent intel ops day · hh counter ops day · map effect ops day · coherence intel day · weather economy intel close day  

## Next 48 hours (Top 5) — NEXT-140 LOGISTICS/FORCE/PANEL (20)

- [x] **#1 Depot logistics · supply route · move path · multi-province · theater auto tick** — logistics/theater path  
- [x] **#2 Daily supply · logistics theater close** — supply continuity  
- [x] **#3 Force readiness · OOB factory · medium equip · naval skim · basing logistics** — force/OOB honesty  
- [x] **#4 Production force · force OOB close · player surface · order panel · panel sections** — force + panel surface  
- [x] **#5 Tooltip flair · apply audit · logistics force panel close + dual** — next-140 logistics  

### Next-140 logistics/force/panel package catalogue (20)

- depot logistics day · supply route ops day · move path ops day · multi province ops day · theater auto tick day  
- daily supply ops day · logistics theater close day · force readiness ops day · oob factory ops day · medium equip ops day  
- naval skim ops day · basing logistics ops day · production force ops day · force oob close day · player surface ops day  
- order panel ops day · panel sections ops day · tooltip flair ops day · apply audit ops day · logistics force panel close day  

## Next 48 hours (Top 5) — NEXT-130 FLEET/HH/COMBAT (20)

- [x] **#1 Fleet AI task · fleet wx ops · basing fuel · naval phase · coastal fog** — fleet AI / naval ops path  
- [x] **#2 Fleet station mut · naval task mut** — fleet mutation path  
- [x] **#3 HH agenda pick/actions · order path · theater HH · trail ops** — HH agenda path  
- [x] **#4 Agent mission/campaign ops · combat inspect stack · phase ribbon · joint timeline** — agent + combat inspector  
- [x] **#5 Assault rank inspect · combat campaign ops · fleet HH combat close + dual** — next-130 fleet  

### Next-130 fleet/HH/combat package catalogue (20)

- fleet ai task day · fleet wx ops day · basing fuel ops day · naval phase ops day · coastal fog ops day  
- fleet station mut day · naval task mut day · hh agenda pick day · hh agenda actions day · hh order path day  
- theater hh path day · hh trail ops day · agent mission ops day · agent campaign ops day · combat inspect stack day  
- phase ribbon inspect day · joint timeline inspect day · assault rank inspect day · combat campaign ops day · fleet hh combat close day  

## Next 48 hours (Top 5) — NEXT-120 INDUSTRY/SAVE (20)

- [x] **#1 Prod/supply mut apply · execute prod live · day budget · apply audit** — live apply path  
- [x] **#2 Live apply results · mutation gate apply** — apply feedback + integrity  
- [x] **#3 Daily/theater prod auto · campaign risk · wx stack · factory risk · depot stack** — industry surface  
- [x] **#4 Industry close loop · save slot surface · save browser live** — production close + save  
- [x] **#5 Campaign continuity · ops dash · execution gate cont · industry save close + dual** — next-120 industry  

### Next-120 industry/save package catalogue (20)

- prod mut apply day · supply mut apply day · execute prod live day · day budget apply day · apply audit live day  
- live apply results day · mutation gate apply day · daily prod auto live day · theater prod live day · prod campaign risk day  
- prod wx stack day · factory risk live day · depot prod stack day · industry close loop day · save slot surface day  
- save browser live day · campaign continuity day · ops dash continuity day · execution gate cont day · industry save close day  

## Next 48 hours (Top 5) — NEXT-110 INCOMPLETE LOOPS (20)

- [x] **#1 Live mut board · feedback chain · mut close stack · dual domain mutate** — live mutation + apply feedback  
- [x] **#2 Assault/agent/supply mut feedback days** — mutation→feedback path  
- [x] **#3 Combat surface stack · phase timeline · rank card · joint naval land · multi-front** — multi-phase combat surface  
- [x] **#4 Combat depth strip · phase estimate ribbon · fleet path · basing mission** — combat UI + fleet path  
- [x] **#5 HH path stack · trail counter · agent mission path · incomplete loop close + dual** — next-110 incomplete  

### Next-110 incomplete loops package catalogue (20)

- live mut board day · feedback chain day · mut close stack day · dual domain mutate day · assault mut fb day  
- agent mut log day · supply mut fb day · combat surface stack day · phase timeline stack day · assault rank card day  
- joint naval land day · multi front surface day · combat depth strip day · phase estimate ribbon day · fleet path stack day  
- basing mission day · hh path stack day · hh trail counter day · agent mission path day · incomplete loop close day  

## Next 48 hours (Top 5) — NEXT-100 WORLD-CLASS (20)

- [x] **#1 Best assault/station live · execute-one live** — live theater apply packages  
- [x] **#2 Basing fuel loop · fleet wx package · convoy wx window** — logistics + fleet + trade  
- [x] **#3 Focus wx · morale wx · campaign risk · depot wx** — weather-aware campaign surface  
- [x] **#4 Daily fleet/combat/agent/supply auto** — full daily auto cabinet  
- [x] **#5 Basing signals/rates · combat wx mult · sea zone trade · HH trail · agent campaign + dual** — next-100 world-class  

### Next-100 world-class package catalogue (20)

- best assault live day · best station live day · execute one live day · basing fuel loop day · fleet wx package day  
- convoy wx window day · focus wx score day · morale wx day · campaign risk live day · depot wx live day  
- daily fleet auto day · daily combat auto day · daily agent auto day · daily supply auto day · basing signals day  
- basing rates day · combat wx mult day · sea zone trade day · hh secondary trail day · agent campaign live day  

## Next 48 hours (Top 5) — NEXT-90 LIVE COMMAND (20)

- [x] **#1 Mutation result · strip · close · gate** — live mutation loop surface  
- [x] **#2 Agenda pick · actions · HH commit order · theater HH · counterplay** — HH player path  
- [x] **#3 Task group · naval basing · multi-phase · coastal fog** — fleet depth  
- [x] **#4 Phase ribbon · assault rank · joint timeline · daylight combat** — combat UI depth  
- [x] **#5 Production auto · risk alert · day results flair + GIS×753 dual** — next-90 live command  

### Next-90 live command package catalogue (20)

- mutation result day · mutation strip day · close mutation day · mutation gate day · agenda pick day  
- agenda actions day · hh commit order day · theater hh commit day · hh counterplay day · task group day  
- naval basing day · naval multi phase day · coastal fog gate day · phase ribbon day · assault rank day  
- joint timeline day · daylight combat day · production auto day · production risk alert day · day results flair day  

## Next 48 hours (Top 5) — NEXT-80 EXECUTION SURFACE (20)

- [x] **#1 Result feedback · day budget · HH auto plan · append/log strip** — feedback + budget + log  
- [x] **#2 Assault readiness · coherence delta · agent order** — readiness + dispatch  
- [x] **#3 Execution / cohesion / command gates · execute order** — integrity gates  
- [x] **#4 Air sortie ready · weather combat brief · day audit · map visible** — estimate + audit  
- [x] **#5 Assault card · save slot list · multi-phase estimate · campaign strip + GIS×753 dual** — next-80 execution  

### Next-80 execution surface package catalogue (20)

- result feedback day · day budget day · hh auto plan day · append log day · log strip day  
- assault readiness day · coherence delta day · agent order day · execution gate day · cohesion gate day  
- command gate day · execute order day · air sortie ready day · weather combat brief day · day audit day  
- map visible day · assault card day · save slot list day · multi phase estimate day · campaign strip day  

## Next 48 hours (Top 5) — NEXT-70 PLAYABILITY (20)

- [x] **#1 Leader weather · OOB factory · move ops · fleet wx mission** — leader/OOB/move/fleet playability  
- [x] **#2 Player surface · multi-province plan · theater prod auto · focus mutation** — surface + auto  
- [x] **#3 Mutation feedback · HH quarterly · depot weather · fleet patrol strip** — feedback + HH + logistics  
- [x] **#4 Close loop · agent missions · supply route · basing fuel · ops dashboard** — close command loop  
- [x] **#5 Daily theater tick · command log · integrity gate + GIS×753 dual held** — next-70 playability  

### Next-70 playability package catalogue (20)

- leader weather day · oob factory day · move ops day · fleet wx mission day · player surface day  
- multi province plan day · theater prod auto day · focus mutation day · mutation feedback day · hh quarterly day  
- depot weather day · fleet patrol strip day · close loop day · agent missions day · supply route mutation day  
- basing fuel day · ops dashboard day · daily theater tick day · command log day · integrity gate day  


# TODO — Epochs of Ascendancy

**Updated:** 2026-08-12 (live board **~3520** · dual markers still here)  
**Source of truth (live status / full-test phases):** [`docs/GAME_STATUS_SNAPSHOT.md`](docs/GAME_STATUS_SNAPSHOT.md) · [`docs/GAME_DIRECTOR_PLAN.md`](docs/GAME_DIRECTOR_PLAN.md)  
**Dual markers / backlog:** this file · companions `Project_State_Summary.md` · `Next_30_Days_Roadmap.md` (historical day-wave catalogue; board default supersedes older headers)  
**Engine:** Godot **4.7.1+** · `tools/run_godot.sh`  
**Primary play data:** `data/provinces_world_accurate` (**~3520** GIS hybrid)  
**Default F5 / TestRunner:** scenario **`world_accurate`**  
**Scaffold (CI dual / fallback):** `EOA_SCENARIO=world_full` → `data/provinces_world_full` (**2665**; never renumber IDs in place)

---



## Next 48 hours (Top 5) — NEXT-60 COMMAND DEPTH (20)

- [x] **#1 Air ops sortie · agent escalation · agent coverage** — sortie + intel ladder  
- [x] **#2 Combat/production/supply order days** — execute order surface  
- [x] **#3 Combat phase strip · fleet patrol · execute-one** — ops strip queue  
- [x] **#4 Daily plans (fleet/combat/prod/agent/supply) + mutations + HH monthly** — close 20-pack  
- [x] **#5 GIS×753 + dual bar held** — map CI · next60 command pure gates  

### Next-60 command depth package catalogue (20)

- air ops sortie day · agent escalation day · agent coverage day · combat order day · production order day  
- supply order day · combat phase strip day · fleet patrol day · execute-one day · daily fleet plan day  
- daily combat plan day · daily production plan day · daily agent plan day · daily supply plan day · agent dispatch mutation day  
- fleet station mutation day · assault stage mutation day · naval task mutation day · air-land stage mutation day · hh monthly day  

## Next 48 hours (Top 5) — NEXT-50 OPS/MUTATION

- [x] **#1 Factory risk day** + **trade chain day** — factory wear risk + trade health  
- [x] **#2 War path urgency day** + **combat morale day** — urgency path + morale wx  
- [x] **#3 Choke sea day** + **redeploy route day** — choke control + redeploy score  
- [x] **#4 Theater report / best station / best assault / theater mutation days** — close ops loop  
- [x] **#5 GIS×753 + dual bar held** — map CI · next50 ops pure gates  

### Next-50 ops/mutation package catalogue (10)

- factory risk day · trade chain day · war path urgency day · combat morale day · choke sea day  
- redeploy route day · theater report day · best station day · best assault day · theater mutation day  

## Next 48 hours (Top 5) — NEXT-40 CAMPAIGN SURFACE

- [x] **#1 Sealane health day** + **convoy package day** — trade/escort health + convoy window  
- [x] **#2 Theater campaign day** + **production risk day** — readiness strip + factory risk  
- [x] **#3 Leader campaign day** + **basing repair day** — leader assign + dock repair  
- [x] **#4 Focus / naval / air-land / theater order days** — close campaign order loop  
- [x] **#5 GIS×753 + dual bar held** — map CI · next40 campaign pure gates  

### Next-40 campaign surface package catalogue (10)

- sealane health day · convoy package day · theater campaign day · production risk day · leader campaign day  
- basing repair day · focus order day · naval order day · air-land order day · theater order day  

## Next 48 hours (Top 5) — NEXT-30 THEATER SURFACE

- [x] **#1 War cabinet day** + **supply campaign day** — cabinet commit/focus + supply spine  
- [x] **#2 Force supply day** + **counter-ops day** — force×supply posture + agent counter  
- [x] **#3 Multi-province live day** + **order queue day** — live coastal tick + ranked queue  
- [x] **#4 Agent AI board / fleet order / fleet theater posture / campaign risk days** — close loop  
- [x] **#5 GIS×753 + dual bar held** — map CI · next30 theater pure gates  

### Next-30 theater surface package catalogue (10)

- war cabinet day · supply campaign day · force supply day · counter-ops day · multi-province live day  
- order queue day · agent ai board day · fleet order day · fleet theater posture day · campaign risk day  

## Next 48 hours (Top 5) — NEXT-20 PRIORITY DEPTH

- [x] **#1 Order panel UX day** + **multi-phase combat UI day** — panel surface + ribbon/card apply  
- [x] **#2 Fleet AI ops day** + **basing logistics day** — patrol/task/escort + fuel basing  
- [x] **#3 HH agenda package day** + **agent campaign depth day** — screen seed + missions/escalation  
- [x] **#4 Industry economy / save slot browser / assault follow-on / joint ops loop days** — close loop  
- [x] **#5 GIS×753 + dual bar held** — map CI · next20 priority pure gates  

### Next-20 priority package catalogue (10)

- order panel ux day · multi-phase combat ui day · fleet ai ops day · hh agenda package day · agent campaign depth day  
- industry economy day · save slot browser day · basing logistics day · assault follow-on day · joint ops loop day  

## Next 48 hours (Top 5) — NEXT-10 DEPTH

- [x] **#1 Multi-phase combat day** + **combat air-naval day** — phase estimate + joint air/naval apply queues  
- [x] **#2 Agent auto day** + **focus pick day** — seeded dispatch + focus rank → HH commit  
- [x] **#3 Production priority day** + **convoy escort day** — surge mutation + escort coverage  
- [x] **#4 Next-day feedback / map effect / theater brief / campaign decision days** — close loop  
- [x] **#5 GIS×753 + dual bar held** — map CI · next10 pure gates  

### Next-10 depth package catalogue (10)

- multi-phase combat day · combat air-naval day · agent auto day · focus pick day · production priority day  
- convoy escort day · next-day feedback day · map effect day · theater brief day · campaign decision day  

## Next 48 hours (Top 5) — WEEK-4 POLISH

- [x] **#1 GPU pan/zoom day** — soft advisory profile (load/icons/cull advice; **deferred hard gate**)  
- [x] **#2 Tooltip/SFX flair strip** — select · invest · assault contracts scannable strip  
- [x] **#3 Docs retrospective** — Week 1–4 map-first delivery landed in master docs  
- [x] **#4 Week-3 naval/HH held** — agenda screen day · fleet autonomy day · sealane visual  
- [x] **#5 GIS×753 + dual bar held** — map CI green  


## Next 48 hours (Top 5) — WEEK-3 NAVAL + HH DEPTH

- [x] **#1 HH agenda screen day** — product sections + player-path apply queue (commit/counterplay/dispatch)  
- [x] **#2 Fleet autonomy day** — multi-province station/supply queue beyond single autonomy tick  
- [x] **#3 Sealane contest visual** — map choke glyph tint_key (hostile/contested/friendly)  
- [x] **#4 Week-2 polish held** — day apply audit · save-slot flair · dual green  
- [x] **#5 GIS×753 held** — littoral pool regression bar  


## Next 48 hours (Top 5) — WEEK-1 MAP FINISHERS

- [x] **#1 GIS littoral pool fill** — stamp **≥753** coastal+littoral (full pool) id-stable, triangles=0 · **GIS×753**  
- [x] **#2 Inspector product-depth chip budget** — **inspector product-depth** budget max 8 chips (always naval skim + HH path + combat/fleet campaign)  
- [x] **#3 Resource/damage operational skim** — **resource/damage skim** at operational zoom (icons on ≥0.32, sabo/dmg urgency)  
- [x] **#4 Sealane contest skim** — **sealane contest skim** (zone · choke · escort · contest %)  
- [x] **#5 Prior UX Top 5 held** — order panel sections · naval skim · hh player path · medium-horizon equip · dual green  

### Prior Top 5 — MAP CREDIBILITY + UX LOAD (COMPLETE)

- [x] **#1 GIS littoral expand** — **720** then **753**  
- [x] **#2 Order panel / inspector cognitive load** — **order panel sections** collapsible  
- [x] **#3 Naval campaign readability** — **naval campaign skim**  
- [x] **#4 HH agenda player path** — **hh player path**  
- [x] **#5 Medium-horizon equip honesty** — **medium-horizon equip**  

### Prior Top 5 — CORE HONESTY + NAVAL FEEL (COMPLETE — do not re-open)

- [x] **#1 OOB production honesty** — dual @ 20d: **total_units=7 majors_grew=7/7**  
- [x] **#2 Residual name + region label polish**  
- [x] **#3 Naval map feel**  
- [x] **#4 City / capital stretch** — **900** anchors  
- [x] **#5 Pan/zoom polish on 2665**  

### Evidence (this delivery)

- Scratch: `/tmp/grok-goal-21e7aa1dbab9/implementer/`  
- Dual logs: `/tmp/grok-goal-21e7aa1dbab9/implementer/headless_world_full_{1,2}.log` · `DUAL_OK.txt`  
- Map CI: `/tmp/grok-goal-21e7aa1dbab9/implementer/map_ci.log` exit **0**  
- GIS×753 + inspector depth: `gis_753_write.log` · `inspector_depth_tests.log` · `EVIDENCE.md`  
- GIS stamp: **753** · inspector product-depth budget · resource/damage skim · sealane contest skim  

---

## Map-star Top 5 — COMPLETE (2026-07-11)

- [x] **Geometry stretch densify** — min=16, median **18** (organicize), triangles=0  
- [x] **Strategic region rebalance** — max share **11.1%**, min size 10, 34 regions  
- [x] **World name quality** — Sector/Basin-coord robotic_left=0; unique 2665  
- [x] **City layer expansion** — **600** nonempty city anchors  
- [x] **Naval chokepoint pack** — **56** chokepoints  

### Week-1 follow-on — COMPLETE

- [x] Coastal/hotspot organicize — 1065 reshaped  
- [x] Resource icon LOD — strategic ≥0.38 + icon budget 220  
- [x] Capital centroid spot-check pure gate  
- [x] HH dual map signals — `economic_pressure` + sabotage infra  
- [x] HH third map-visible class — **infiltration** (`loyalty_strain` / `loyalty_infiltration`)  
- [x] Chokepoint contest state — controlled / contested / unowned (inspector + glyph)  
- [x] Map action feedback polish — select / invest / capture / HH toast+sfx contracts  
- [x] World-board batched mesh fills (strategic+operational @ ≥2200)  
- [x] HH multi-month agenda trail (`hh_agenda_trail`, capacity 6) + **inspector surface**  
- [x] Sea-zone strategic modifiers (controlled/contested/unowned → supply/trade)  
- [x] World-board cull all tiers ≥2200  
- [x] Sea-zone theaters — 19 zones; inspector + select flair + control badge  
- [x] Strategic region relabel — 0 `Theater N` (Far East Theater 2 → China Heartland)  
- [x] Road/rail earlier zoom (0.10/0.14) + thicker arterials  
- [x] Docs retrospective — cities **900**, HH three classes, icon budget **180**, chokes **56**

---

## Full world map (status)

- [x] Scope: entire world · 2665 provinces · world_full default F5  
- [x] Ownership 1936 · factories · OOB stations · branch leaders  
- [x] Map CI green · dual headless SCRIPT ERROR 0 + industry/equip markers  
- [x] Geometry densify + organicize (median 18)  
- [x] Unique names (robotic Sector/Basin-coord cleared)  
- [x] Balanced strategic regions (max share ≤12%)  
- [x] City layer ≥600  
- [x] Naval chokepoints ≥30 (shipped 56)  
- [x] GIS coastline pilot — real dry-run metrics + guarded `--write --pilot`  
- [x] GIS coastline pilot **expand** — **240** → **564** → **720** coastal+littoral ids stamped, id_stable, triangles=0 (not full NE photoreal; pool 753)  
- [x] Weather combat/supply/move/production multipliers + inspector weather chip + storm interdiction  
- [x] Fleet **redeploy posture pilot** (HOLD_BASE/PATROL/CONVOY/PROJECTION/REFUEL)  
- [x] Fleet **theater posture plan** pilot (multi-province dominant posture)  
- [x] Fleet **redeploy route plan** pilot (origin→dest score beyond theater)  
- [x] Fleet **task-group composition** pilot (SCREEN/STRIKE/SUPPORT mix)  
- [x] HH **agenda pulse digest** + agent **network response** pilots  
- [x] HH **pulse+actions digest** + agent **network deploy plan** chips  
- [x] HH **monthly brief** + agent **coverage plan** pilots  
- [x] HH **quarterly rollup** (last ≤3 unique months; empty trail empty) + agent **escalation ladder** pilots  
- [x] Weather-aware assault estimate card + **weather phase ribbon** + **weather combat briefing**  
- [x] **Multi-front assault priority** pilot (rank targets by power+weather)  
- [x] Weather deepen — forecast stub · season daylight · extreme chip · sea×weather supply · storm convoy · air/naval pure live · mapmode legend hint  
- [x] Weather ops polish — pressure index · route wx rank · trade wx mult · naval tip · air alert · freeze/thaw · infra wear · fog gate · joint focus/agent · weather ops section  
- [x] Theater polish (next-20 items 10–19) — campaign day risk · convoy weather window · production weather alert · sea×naval ops · combat morale wx · depot weather capacity · daylight combat mod · choke×weather synergy · focus weather-aware pick · inspector ops dashboard  
- [ ] Full-world photoreal GIS coastlines / fjords (expand pilot only; full NE rewrite deferred)  
- [x] Residual Waters-N / Theater-2 label cleanup  
- [x] City stretch ≥750–900 (shipped **900**, far=0)  
- [x] Naval map feel (sea-zone tint mapmode + choke control glyph + coastal select)  
- [x] Sea-zone control readout (inspector) + supply/trade modifiers  
- [x] Sea-zone control **gameplay effect** — supply route delivery + trade flow mult from live control  
- [x] Naval basing **pilot** — none/anchorage/port/major_base + capacity; inspector badge  
- [x] Naval basing **capacity effect** — repair/refuel rates by tier on SupplyManager naval tick  
- [x] Fleet-ops **station preference pilot** — rank by basing tier (`get_preferred_fleet_station`)  
- [x] Fleet-ops **patrol/tasking pilot** — naval order preference by basing+zone (`rank_fleet_tasking`)  
- [x] Fleet-ops **convoy escort assignment pilot** (`plan_convoy_escort_for_path`)  
- [x] Full fleet AI / multi-phase naval combat **ops close** — posture/escort/strike live (`apply_naval_ops_close_live`)  

---

## Campaign continuity (keep green; do not block map)

- [x] Combat equip shortages + reinforce + write-off  
- [x] world_full assault capture / station / displace / follow-on / chain  
- [x] Factory transfer + seized production + design grant + fielding  
- [x] Post-load playability (can_assault + daily reinforce + combat stats; LeaderManager design_id)  
- [x] Post-load chain / second-province flip / slot save_game_detailed  
- [x] Conquest + map/stock/equip saveload tests in map CI  

---

## Core polish

- [x] Infra inspector UX · special site icons/effects · DebugOverlay Player/Dev split  
- [x] HH monthly map feedback + counterplay + dual map classes  
- [x] Damage visuals · select/invest flair · viewport culling  
- [x] OOB daily production growth under short evidence window (7/7 majors @ 20d)  
- [x] Slot save UI list (empty vs occupied; save/load via detailed APIs)  
- [x] Inspector top-line (name / owner / region / sea zone)  
- [x] Era-band infra density (1918 sparse vs 1936 baseline vs 2026 dense)  
- [x] Special-site completion pulse + sabotage/damage distinct map visual  
- [x] GIS coastline ingest design + **pilot** (real dry-run metrics; `--write --pilot` id-stable)  
- [x] Sea-zone control (majority/contested/unowned + inspector badge + supply/trade modifiers)  
- [x] HH agenda trail player surface (ProvinceInsight BBCode from GameData store) 

---

## Later (do not block map)

- [x] Combat multi-phase **estimate pilot** (`estimate_multi_phase_combat` approach/engage/disengage)  
- [x] Combat multi-phase **phase ribbon UI pilot** (`format_combat_phase_ribbon`)  
- [x] Combat **assault estimate card pilot** (power + ribbon + recommendation)  
- [x] Combat multi-phase UI/ops **close** — approach/engage/disengage live (`apply_combat_ops_close_live`)  
- [x] Agent **counterplay options pilot** (HH signal → ordered responses in inspector)  
- [x] Focus tree **pick priority pilot** (`rank_focus_picks`)  
- [x] Agent **mission priority pilot** (`rank_agent_missions`)  
- [ ] Agents / focus trees / deep AI (mission/pick/counterplay pilots only; deep AI deferred)  
- [ ] Designers (tank / ship / space) completion — **deferred non-goal** this phase  
- [ ] Multiplayer foundation — **deferred non-goal** this phase  
- [x] HH agenda **panel pilot** (`format_hh_agenda_panel` + inspector block)  
- [x] HH agenda **screen layout pilot** (Recent / By class / Actions; empty trail empty)  
- [x] HH agenda **action-pick pilot** (`pick_hh_agenda_actions_plain`; empty trail empty)  
- [x] Full multi-month HH agenda **surface close** — trail/brief/quarterly live (`apply_hh_agenda_close_live`)  
- [x] Play data dir **operator helper** (`resolve_play_data_dir` → world_full default)  
- [x] Gazetteer residual **pure gate** (robotic/placeholder=0 on world_full names)  
- [ ] Optional GPU pan/zoom profile · combat UI · fleet AI autonomy · agent AI — deferred (no hard gate)  

---

## Known deferred map issues

- Approximate gazetteer (residual Waters/District style names; ocean Basin names OK)  
- Most provinces still seed-poly character; GIS pilot expanded to **720** coastal+littoral rings (not full-world photoreal fjords; pool 753)  
- Inspector compact section collapse / slot flair / sealane chip / choke+basing synergy pilots landed  
- Capital centroid + Theater-N + soft gazetteer + icon budget + flair contract + OOB evidence parse pilots landed  
- Dual data dirs: `resolve_play_data_dir` clarifies world_full default vs secondary/legacy  
- Full fleet AI / multi-phase naval combat (station-pref + basing rates pilots; full AI deferred)  
- Full multi-month HH agenda screen (trail + panel pilots; full UI deferred)  

**Resolved (do not re-open as open gaps):** Far East Theater 2 → China Heartland; OOB daily production **majors_grew=7/7 @ 20d**.

---

## Commands

```bash
# Map CI (primary)
bash tools/run_map_ci.sh data/provinces_world_full

# Dual world_full smoke (markers; use OOB days for production evidence)
EOA_SCENARIO=world_full EOA_OOB_EVIDENCE_DAYS=20 \
  tools/run_godot.sh --headless --path . --quit-after 200 \
  res://scenes/TestScenario.tscn

# Stretch densify (already applied; re-run only if geometry regenerates)
python3 tools/map_generation/scripts/densify_province_geometry.py \
  --dir data/provinces_world_full --write --min-vertices 16 --max-vertices 72
```

- [x] Theater polish (next-20 items 10–19) — campaign day risk · convoy weather window · production weather alert · sea×naval ops · combat morale wx · depot weather capacity · daylight combat mod · choke×weather synergy · focus weather-aware pick · inspector ops dashboard
- [x] **Fleet+wx mission package** (task-group shifted by storm/spot) · **assault readiness compose** (multi-front+supply+morale) · **counter-ops board** (HH+escalation+coverage)
- [x] **HH agenda commitments** (empty trail empty) · **choke×sea×wx** · **trade chain health** · **factory risk** · **supply chain health** · **air ops package** · **war cabinet** · **campaign strip**
- [x] **#13 Theater readiness board** (fleet+wx + assault readiness + day risk; `theater_readiness_board` inspector) — **landed-pilot**
- [x] **#14 Convoy package compose** (escort need × convoy weather window; `convoy_package_for_province` live) — **landed-pilot**
- [x] **#19 Cross-system coherence gate** (pure: foul weather changes fleet/assault/trade multi-system scores; `cross_system_coherence_delta`) — **landed-pilot**
- [x] **Gameplay loops expand (next-20 beyond integration)** — GIS×**240** id-stable · **basing logistics** (fleet+fuel×wx) · **assault follow-on** · counter-ops execute order · **agenda execute** pick (empty trail empty) · move path ops · basing repair weather · sealane joint health · reinforced assault · war path urgency · OOB factory risk (sole mult) · force×supply posture · leader weather assign · **joint ops loop** strip · **sole-mult** integrity gate · dual OOB evidence
- [x] **#2 Basing logistics loop** — `basing_fleet_fuel_logistics` / `basing_fleet_fuel_logistics_for_province` — **landed-pilot**
- [x] **#3 Assault follow-on loop** — `assault_follow_on_loop` / `build_assault_follow_on_loop` — **landed-pilot**
- [x] **#7 Agenda execute pick** — `agenda_execute_pick_from_trail` / `format_hh_agenda_execute_pick_plain` (empty → `""`) — **landed-pilot**
- [x] **#18 Joint ops loop strip** — basing logistics + follow-on + agenda execute on inspector — **landed-pilot**
- [x] **#19 Sole-mult integrity** — pure compose equals single mult (no double-count on supply/trade/OOB) — **landed-pilot**

- [x] **Campaign cohesion expand (next-20 beyond gameplay loops)** — GIS×**564** · **fleet campaign** plan · combat campaign phase · agent campaign response · **HH campaign** board · theater campaign strip · production campaign risk · **supply campaign** spine · focus war path · force posture · leader campaign · naval campaign · air-land joint · **campaign decision** strip · **cohesion integrity** gate · dual OOB evidence

- [x] **Campaign execution expand (next-20 beyond cohesion)** — GIS×**564** · **fleet order** execute · combat order · agent dispatch · HH order commit · **map effect** resolve · **next-day feedback** · production/supply orders · naval/air-land orders · theater order board · focus order · **execution decision** strip · **execution integrity** gate · dual OOB evidence

- [x] **Live mutation expand (next-20 beyond execution)** — GIS×**564** · **fleet station mutation** (→ move_formation) · **assault stage** mutation · agent dispatch mutation · HH commit mutation · formation station apply · **production priority** apply · supply route mutation · **map effect store** · next-day mutation feedback · naval/air-land stage mutations · theater mutation board · mutation decision strip · **mutation integrity** gate · dual OOB evidence

- [x] **Theater command expand (next-20 beyond live mutation)** — GIS×**564** · **theater fleet** auto-command · theater combat auto · agent auto-dispatch · HH auto-commit · **player order surface** · theater daily brief · production/supply auto · apply-best station/assault · **order queue** · execute-one · **theater command** strip · **command integrity** gate · dual OOB evidence

- [x] **Daily command expand (next-20 beyond theater command)** — GIS×**564** · **daily theater** auto-apply on `game_day_advanced` · **command result log** (empty day → empty) · **day apply budget** · fleet/combat/prod/supply/HH/agent daily plans · apply-result feedback · multi-province day plan · **theater day report** · command log strip · **daily apply integrity** · dual OOB evidence

- [x] **Ops depth expand (next-20 beyond daily command)** — GIS×**564** · **multi-province live** coastal/station ids · multi-province day tick · **order panel** actions + OrderCommandPanel UI · combat phase depth · fleet patrol depth · panel apply routes · ops depth integrity · dual OOB evidence

**Day ops depth:** day ops integrated · HH agenda product · naval multi-phase · GIS×564

**Theater day depth:** theater day cabinet · joint combat timeline · convoy supply day · GIS×564

**War economy day depth:** war economy day · multi-front assault day · theater day command strip · GIS×564

**Logistics day depth:** logistics day · sealane choke · leader station day · GIS×564

**Air-forecast day depth:** air ops day · forecast planning day · reinforced assault day · GIS×564

**Joint command day depth:** naval interdiction day · intel counter day · joint command day · GIS×564

**Strategic continuity day depth:** order execute day · focus war path day · strategic continuity day · GIS×564

**Force readiness day depth:** force posture day · theater readiness day · force readiness day · GIS×564

**Industry surge day depth:** production surge day · depot capacity day · industry surge day · GIS×564

**Joint campaign day depth:** naval campaign day · air-land joint day · joint campaign day · GIS×564

**Weather crisis day depth:** ground transition day · fog/air crisis day · weather crisis day · GIS×564

**Agent campaign day depth:** agent response day · HH campaign day · agent campaign day · GIS×564

**Combat campaign day depth:** combat ops day · move path day · combat campaign day · GIS×564

**Fleet campaign day depth:** fleet redeploy day · fleet task group day · fleet campaign day · GIS×564

---

## Landed product-depth vocabulary (CI gates — do not strip)

**Integration / cohesion:** theater readiness board · convoy package compose · cross-system coherence · fleet campaign · combat campaign · agent campaign · HH campaign · supply campaign · campaign decision · cohesion integrity · sole-mult · basing logistics · follow-on · joint ops loop · agenda execute

**Execution / mutation / command:** fleet order · map effect · next-day feedback · execution decision · execution integrity · fleet station mutation · assault stage · production priority · map effect store · mutation integrity · theater fleet · player order surface · order queue · theater command · command integrity · daily theater · command result log · day apply budget · theater day report · daily apply integrity · multi-province live · order panel · combat phase depth · fleet patrol depth · ops depth integrity

**Day packages / product depth:** day ops integrated · HH agenda product · naval multi-phase · theater day · war economy · logistics · air-forecast · joint command · strategic continuity · force readiness · industry surge · joint campaign · weather crisis · agent campaign · combat campaign · fleet campaign · **next-10 depth** · **next-20 priority** · **next-30 theater** · **next-40 campaign** · **next-50 ops** (factory risk day · trade chain day · war path urgency day · combat morale day · choke sea day · redeploy route day · theater report day · best station day · best assault day · theater mutation day)

**Priorities 1–9 (open or pilot):** order panel ux · multi-phase combat UI · fleet ai ops · HH agenda screen · agent campaign depth · industry economy · save slot browser · gpu pan/zoom profile · combat ui · fleet ai autonomy · agent ai · combat air-naval · fleet multi-theater · agent auto-dispatch

**Inspector depth labels:** inspector product-depth · resource/damage skim · sealane contest skim · GIS×753

**UX + inspector labels (CI):** order panel sections · naval campaign skim · hh player path · medium-horizon equip · inspector product-depth · resource/damage skim · sealane contest skim · GIS×753

**Week-2 polish labels (CI):** day apply audit · save-slot flair · infra/site consistency · GIS×753

**Week-3 depth labels (CI):** hh agenda screen day · fleet autonomy day · sealane contest visual · GIS×753

**Week-4 polish labels (CI):** gpu pan/zoom day · tooltip/sfx flair strip · week-4 polish · GIS×753

## Top 5 priorities — next 48 hours (NEXT-200 INSPECTOR/INFRA/AUTO)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Panel / tooltip / budget / order surface / product chip** | Inspector product surface | **LANDED** — **panel surface ops day** · **tooltip chip ops day** · **insight budget ops day** · **order surface ops day** · **product chip ops day** |
| **2** | **Surface refresh + inspector surface close** | Surface close path | **LANDED** — **surface refresh ops day** · **inspector surface close day** |
| **3** | **Infra invest / special site / construction / project / status** | Infrastructure investment | **LANDED** — **infra invest ops day** · **special site ops day** · **construction ops day** · **infra project ops day** · **investment status ops day** |
| **4** | **Infra joint/close + daily auto / theater tick / multi-domain** | Daily theater auto | **LANDED** — **infra site joint day** · **infra invest close day** · **daily auto ops day** · **theater tick ops day** · **multi domain auto ops day** |
| **5** | **Daily apply / theater auto joint / close + dual** | Next-200 | **LANDED** — **next-200 inspector** |

## Top 5 priorities — next 48 hours (NEXT-190 SAVE/LEADER/TRADE)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Save slot / autosave / campaign / resume / checkpoint** | Save session continuity | **LANDED** — **save slot integrity ops day** · **autosave session ops day** · **campaign session ops day** · **save resume ops day** · **session checkpoint ops day** |
| **2** | **Save audit + session close** | Save close path | **LANDED** — **save audit ops day** · **save session close day** |
| **3** | **Leader assign / formation / OOB / command / station** | Leader formation command | **LANDED** — **leader assign ops day** · **formation ready ops day** · **oob assign ops day** · **leader command ops day** · **formation station ops day** |
| **4** | **Leader joint/close + trade chain/convoy/sealane** | Trade economy path | **LANDED** — **leader formation joint day** · **leader formation close day** · **trade chain ops day** · **convoy escort ops day** · **sealane economy ops day** |
| **5** | **Trade route / convoy joint / close + dual** | Next-190 | **LANDED** — **next-190 save** |

## Top 5 priorities — next 48 hours (NEXT-180 PRODUCTION/AIR/FOCUS)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Factory risk / equip / priority / OOB / line** | Production OOB continuity | **LANDED** — **prod factory risk ops day** · **medium equip horizon ops day** · **production priority ops day** · **oob equip continuity day** · **factory line ops day** |
| **2** | **Stockpile + production OOB close** | Production close path | **LANDED** — **stockpile growth ops day** · **production oob close day** |
| **3** | **Air sortie / multi-front / air-land / assault / forecast** | Air multi-front depth | **LANDED** — **air sortie front ops day** · **multi front rank ops day** · **air land joint ops day** · **assault front ops day** · **air forecast ops day** |
| **4** | **Multi-front supply / air close / focus path / cabinet / strip** | Focus strategic path | **LANDED** — **multi front supply ops day** · **air front close day** · **focus path ops day** · **war cabinet ops day** · **strategic strip ops day** |
| **5** | **Focus priority / strategic continuity / close + dual** | Next-180 | **LANDED** — **next-180 production** |

## Top 5 priorities — next 48 hours (NEXT-170 COMBAT/AGENT/JOINT)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Combat phase / assault / multi-phase / order / rank** | Combat multi-phase continuity | **LANDED** — **combat phase ops day** · **assault ready ops day** · **multi phase est ops day** · **combat order ops day** · **assault rank ops day** |
| **2** | **Phase ribbon + combat phase close** | Combat close path | **LANDED** — **phase ribbon ops day** · **combat phase close day** |
| **3** | **Agent mission / dispatch / HH / counterplay / agenda** | Agent HH campaign | **LANDED** — **agent mission campaign day** · **agent dispatch ops day** · **hh commit campaign day** · **counterplay campaign day** · **hh agenda ops day** |
| **4** | **Agent HH joint / close / theater+naval joint / focus** | Joint multi-domain | **LANDED** — **agent hh joint day** · **agent hh close day** · **joint theater combat day** · **joint naval combat day** · **focus joint ops day** |
| **5** | **Joint command / multi-domain strip / close + dual** | Next-170 | **LANDED** — **next-170 combat** |

## Top 5 priorities — next 48 hours (NEXT-160 THEATER/NAVAL/SESSION)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Multi-province / auto / daily / readiness / move path** | Theater campaign continuity | **LANDED** — **multi province campaign day** · **theater auto campaign day** · **daily command ops day** · **theater readiness ops day** · **move path campaign day** |
| **2** | **Theater order board + campaign close** | Theater close path | **LANDED** — **theater order board day** · **theater campaign close day** |
| **3** | **Basing / fleet wx / convoy / sealane / naval order** | Naval sealane sustain | **LANDED** — **basing fleet sustain day** · **fleet wx sustain day** · **convoy sustain ops day** · **sealane joint ops day** · **naval order ops day** |
| **4** | **Fleet station / sealane close / player / panel / mutation** | Naval + session path | **LANDED** — **fleet station sustain day** · **naval sealane close day** · **player surface session day** · **order panel session day** · **mutation feedback ops day** |
| **5** | **Audit / decision strip / close + dual** | Next-160 | **LANDED** — **next-160 theater** |

## Top 5 priorities — next 48 hours (NEXT-150 WEATHER/ECONOMY/INTEL)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Combat/prod/air/morale/convoy wx** | Weather–ops continuity | **LANDED** — **combat wx ops day** · **prod wx ops day** · **air sortie wx day** · **morale wx ops day** · **convoy wx ops day** |
| **2** | **Daylight + weather ops close** | Weather ops close path | **LANDED** — **daylight wx ops day** · **weather ops close day** |
| **3** | **War economy / focus / supply / depot** | Strategic war-economy | **LANDED** — **war economy ops day** · **prod campaign ops day** · **focus wx ops day** · **focus mut ops day** · **supply economy ops day** · **depot economy ops day** |
| **4** | **War economy close / intel / agent / HH** | Intel-counterplay | **LANDED** — **war economy close day** · **intel counter ops day** · **agent intel ops day** · **hh counter ops day** |
| **5** | **Map effect / coherence / close + dual** | Next-150 | **LANDED** — **next-150 weather** |

## Top 5 priorities — next 48 hours (NEXT-140 LOGISTICS/FORCE/PANEL)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Depot/supply/move/multi-province/theater tick** | Logistics/theater path | **LANDED** — **depot logistics day** · **supply route ops day** · **move path ops day** · **multi province ops day** · **theater auto tick day** |
| **2** | **Daily supply + logistics theater close** | Supply continuity | **LANDED** — **daily supply ops day** · **logistics theater close day** |
| **3** | **Force readiness / OOB factory / equip / naval skim / basing** | Force/OOB honesty | **LANDED** — **force readiness ops day** · **oob factory ops day** · **medium equip ops day** · **naval skim ops day** · **basing logistics ops day** |
| **4** | **Production force / OOB close / player surface / panel** | Force + panel surface | **LANDED** — **production force ops day** · **force oob close day** · **player surface ops day** · **order panel ops day** · **panel sections ops day** |
| **5** | **Tooltip flair / audit / close + dual** | Next-140 | **LANDED** — **next-140 logistics** |

## Top 5 priorities — next 48 hours (NEXT-130 FLEET/HH/COMBAT)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Fleet AI / wx / basing / naval phase / fog** | Fleet AI naval ops path | **LANDED** — **fleet ai task day** · **fleet wx ops day** · **basing fuel ops day** · **naval phase ops day** · **coastal fog ops day** |
| **2** | **Fleet station / naval task mutation** | Fleet mutation path | **LANDED** — **fleet station mut day** · **naval task mut day** |
| **3** | **HH agenda pick/actions/order/theater/trail** | HH agenda path | **LANDED** — **hh agenda pick day** · **hh agenda actions day** · **hh order path day** · **theater hh path day** · **hh trail ops day** |
| **4** | **Agent ops + combat inspect surface** | Agent + multi-phase inspector | **LANDED** — **agent mission ops day** · **agent campaign ops day** · **combat inspect stack day** · **phase ribbon inspect day** · **joint timeline inspect day** |
| **5** | **Assault rank / campaign ops / close + dual** | Next-130 | **LANDED** — **next-130 fleet** |

## Top 5 priorities — next 48 hours (NEXT-120 INDUSTRY/SAVE)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Prod/supply mut apply + execute + budget + audit** | Live apply path | **LANDED** — **prod mut apply day** · **supply mut apply day** · **execute prod live day** · **day budget apply day** · **apply audit live day** |
| **2** | **Live apply results + mutation gate apply** | Feedback + integrity | **LANDED** — **live apply results day** · **mutation gate apply day** |
| **3** | **Daily/theater prod + risk + wx + factory + depot** | Industry surface | **LANDED** — **daily prod auto live day** · **theater prod live day** · **prod campaign risk day** · **prod wx stack day** · **factory risk live day** · **depot prod stack day** |
| **4** | **Industry close + save surface/browser** | Close prod + save | **LANDED** — **industry close loop day** · **save slot surface day** · **save browser live day** |
| **5** | **Continuity / gate / industry-save close + dual** | Next-120 | **LANDED** — **next-120 industry** |

## Top 5 priorities — next 48 hours (NEXT-110 INCOMPLETE LOOPS)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Live mut board / feedback chain / close stack / dual mutate** | Mutation + apply feedback | **LANDED** — **live mut board day** · **feedback chain day** · **mut close stack day** · **dual domain mutate day** |
| **2** | **Assault / agent / supply mut feedback** | Mutation→feedback path | **LANDED** — **assault mut fb day** · **agent mut log day** · **supply mut fb day** |
| **3** | **Combat surface stack + multi-phase UI** | Estimate/card/ribbon/timeline | **LANDED** — **combat surface stack day** · **phase timeline stack day** · **assault rank card day** · **joint naval land day** · **multi front surface day** |
| **4** | **Depth strip / ribbon / fleet path / basing** | Combat UI + fleet path | **LANDED** — **combat depth strip day** · **phase estimate ribbon day** · **fleet path stack day** · **basing mission day** |
| **5** | **HH path / trail counter / agent mission / close + dual** | Close incomplete loops | **LANDED** — **next-110 incomplete** |

## Top 5 priorities — next 48 hours (NEXT-100 WORLD-CLASS)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Best assault/station + execute-one live** | Live theater packages | **LANDED** — **best assault live day** · **best station live day** · **execute one live day** |
| **2** | **Basing fuel / fleet wx / convoy window** | Logistics + fleet + trade | **LANDED** — **basing fuel loop day** · **fleet wx package day** · **convoy wx window day** |
| **3** | **Focus/morale/risk/depot wx** | Weather-aware campaign | **LANDED** — **focus wx score day** · **morale wx day** · **campaign risk live day** · **depot wx live day** |
| **4** | **Daily auto cabinet (4 domains)** | Fleet/combat/agent/supply auto | **LANDED** — **daily fleet auto day** · **daily combat auto day** · **daily agent auto day** · **daily supply auto day** |
| **5** | **Basing/sea/HH trail/agent + GIS×753 dual** | Close next-100 | **LANDED** — **next-100 world-class** |

## Top 5 priorities — next 48 hours (NEXT-90 LIVE COMMAND)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Mutation result / strip / close / gate** | Live mutation loop | **LANDED** — **mutation result day** · **mutation strip day** · **close mutation day** · **mutation gate day** |
| **2** | **Agenda / HH commit / theater HH / counterplay** | HH player path | **LANDED** — **agenda pick day** · **agenda actions day** · **hh commit order day** · **theater hh commit day** · **hh counterplay day** |
| **3** | **Task group / basing / multi-phase / fog** | Fleet depth | **LANDED** — **task group day** · **naval basing day** · **naval multi phase day** · **coastal fog gate day** |
| **4** | **Ribbon / assault rank / timeline / daylight** | Combat UI depth | **LANDED** — **phase ribbon day** · **assault rank day** · **joint timeline day** · **daylight combat day** |
| **5** | **Production auto / risk / results flair + GIS×753** | Close next-90 | **LANDED** — **next-90 live command** |

## Top 5 priorities — next 48 hours (NEXT-80 EXECUTION SURFACE)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Feedback / budget / HH auto / log** | Result surface + caps | **LANDED** — **result feedback day** · **day budget day** · **hh auto plan day** · **append log day** · **log strip day** |
| **2** | **Assault readiness / coherence / agent order** | Readiness + dispatch | **LANDED** — **assault readiness day** · **coherence delta day** · **agent order day** |
| **3** | **Integrity gates + execute order** | Gate stack | **LANDED** — **execution gate day** · **cohesion gate day** · **command gate day** · **execute order day** |
| **4** | **Sortie / brief / audit / map visible** | Estimate + audit | **LANDED** — **air sortie ready day** · **weather combat brief day** · **day audit day** · **map visible day** |
| **5** | **Card / save slots / multi-phase / campaign strip + GIS×753** | Close next-80 | **LANDED** — **next-80 execution** |

## Top 5 priorities — next 48 hours (NEXT-70 PLAYABILITY)

| # | Priority | Outcome | Status |
|---|----------|---------|--------|
| **1** | **Leader/OOB/move/fleet wx** | Core playability packages | **LANDED** — **leader weather day** · **oob factory day** · **move ops day** · **fleet wx mission day** |
| **2** | **Surface / multi-province / prod auto / focus** | Player surface + automation | **LANDED** — **player surface day** · **multi province plan day** · **theater prod auto day** · **focus mutation day** |
| **3** | **Feedback / HH quarterly / depot / patrol strip** | Feedback + logistics | **LANDED** — **mutation feedback day** · **hh quarterly day** · **depot weather day** · **fleet patrol strip day** |
| **4** | **Close loop / missions / supply / basing / dashboard** | Close command loop | **LANDED** — **close loop day** · **agent missions day** · **supply route mutation day** · **basing fuel day** · **ops dashboard day** |
| **5** | **Theater tick / command log / integrity + GIS×753** | Regression + next-70 playability | **LANDED** — **next-70 playability** |

