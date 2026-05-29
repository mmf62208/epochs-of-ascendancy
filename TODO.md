# Epochs of Ascendancy — TODO / Future Systems

**Current snapshot:** [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) · **Testing:** [docs/TESTING_PLAN.md](docs/TESTING_PLAN.md)

> **May 28, 2026 — Map pipeline milestone:** Phase 1 generation tooling is now end-to-end for a **persistent ~180-province test scenario** (PCA subdivision, coastal preservation, chokepoint-safe adjacency rebuild, rich attribute merge, Godot load + camera/overlays). See [docs/MAP_GENERATION_PIPELINE_DESIGN.md](docs/MAP_GENERATION_PIPELINE_DESIGN.md) and [docs/SESSION_NOTES/2026-05-28.md](docs/SESSION_NOTES/2026-05-28.md).

---

## Map Generation Pipeline (Phase 1 Europe)

- [x] Created `tools/map_generation/` structure with `lib/` modules
- [x] Implemented `naval_analysis.py` with coastal/chokepoint detection
- [x] Implemented `subdivision_utils.py` with PCA splitting + coastal preservation
- [x] Added chokepoint protection during adjacency rebuild (`apply_phase1_merge.py`)
- [x] Improved attribute distribution during merge (resources, development, specials, cities)
- [x] Created persistent Phase 1 Test Scenario (~180 provinces)
- [x] Added Godot-side polish for test scenario loading (camera, overlays, diagnostics via `DebugOverlay`)
- [ ] Further splitter refinements (coastal edge during cuts)
- [ ] Start producing real layered JSON output (beyond test scenario / hot-load bundles)
- [ ] Scale generation toward 350–450 province Europe target

---

## High Priority (Next 1–2 Weeks)

- [ ] **Province Infrastructure & Development System** — See new comprehensive design: `docs/DESIGN_InfrastructureDevelopmentSystem.md`
  - Active player/AI investment projects to raise infrastructure and development levels
  - Construction capacity, project daily ticks, sabotage interaction, tech gating payoff
  - This is the highest-leverage missing loop (makes build eligibility, factory scaling, supply, and long-term strategy real)
- [ ] Save / Load foundation (`TimeManager` + key province/agent/research state + now also active infra projects)
- [ ] Map Build Eligibility (real `MapTechnologyContext` functionality — now with live dev/infra investment as the lever)
- [ ] Wire more systems to daily/monthly ticks (Production refinement + new InfrastructureDevelopmentManager)
- [ ] Structured testing plan + basic test harness expansion (see `docs/TESTING_PLAN.md`)

## Medium Priority

- [ ] Expand Technology beyond Support/Radio (at least one more small tree)
- [ ] Modernize Top Bar + create basic pause/main menu
- [x] Improve daily agent pressure visuals and feedback (May 2026 — ongoing polish)
- [ ] Add more daily province-level effects or counters

## Recently Completed (May 25, 2026)

- Daily ticks now drive Supply + Agent Networks + Production + infra repair
- Agent networks apply real daily supply disruption + infrastructure sabotage
- Repair + counter-intel path (`clear_daily_sabotage_effects`) implemented
- Per-province depot `sabotage_level` for targeted supply disruption (decays / clearable)
- Multi-overlay map visuals improved (contested + agent + supply + pressure tints)
- Map tooltips/inspector: pressure headlines, TODAY activity, repair/depot recovery lines
- Support/Radio Technology tree delivers visible gameplay impact on routes
- `TimeManager` drives yearly/monthly/daily progression; `TopInfoBar` date/speed wired

---

## Leader & Training Systems

### Completed
- Leveled traits with XP spending (I–III, rarity, exclusivity in `data/leaders/traits.json`)
- Historical leaders (1918 + 1936 + 2026) with timeline gating and scenario loading
- Doctrine Training Paths (invest + switch, `TrainingPathScreen`)
- Officer Training backend (quality progression, cadet generation, trait inheritance risk)
- Training path combat & supply modifier helpers on `LeaderManager`
- Leader Detail Screen with trait levels, effects, and next-level preview
- Officer Training national position card with **Generate Cadet** button
- `RetirementOfferPopup` + `LeaderEventUI` news toasts (including training quality notices)
- Leader Replacement Picker (vacancy queue, auto-fallback scoring, `LeaderReplacementPickerPopup`)

### Outstanding
- Wire training path bonuses into actual combat resolution (helpers exist; full battle loop)
- Improve Officer Training UI (quality bar, richer cadet-generation feedback)
- Tech/focus gating for Admiral and Air Marshal cadets (doctrine placeholders in place)
- Path switching cost preview in `TrainingPathScreen` before confirm
- Political Alignment + Hidden Traits system
- ~~Pending-replacement badge on Leader Assignment screen~~ (done)
- ~~Player-country filtering for replacement popups (AI auto-resolve)~~ (done)
- Full news feed panel (history beyond toasts)
- Earned trait triggers (terrain, campaigns)
- Field Marshal tier + multi-formation command
- Full integration of training bonuses into `SupplyManager` and attrition systems

---

## Leader System — Legacy Notes (May 18, 2026)

---

## Current Session State (Last Worked On)

**Date:** May 2026

**Recently Completed (Major Integration Push):**
- Officer Training Command (mentor, quality, Generate Cadet UI)
- Training path UI polish + combat/supply modifier wiring (helpers)
- Full NationalModifierManager with explicit `attrition_reduction` and `interdiction_resistance` keys
- Deep Agent System: variable effects by skill/outcome, critical successes with announcements, persistent province networks / operative rings foundation
- National modifier system wired into:
  - Production (solid — output, reliability, retooling)
  - Supply (strong — consumption, interdiction resistance, attrition reduction)
  - Combat (deeper — division base stats + interdiction/attrition side)
- Explicit first-class support for `attrition_reduction` and `interdiction_resistance` across spirits + temporary effects
- Daily simulation loop strengthened (TimeManager-driven): repair/counter-intel path via clear_daily_sabotage_effects now called from counter-intel mission outcomes; per-province supply disruption now uses persistent `sabotage_level` on ProvinceDepotState for targeted throughput reduction (decays daily, clearable); ProductionManager wired to game_day_advanced (unified daily consumers: Supply + Agents + Repair + Production); light const tuning + docs.
- Expanded Save/Load (SaveLoadManager): now also persists ProductionManager (lines progress/retooling/stockpiles), FactoryManager (full Factory resources + province mapping), LeaderManager (leaders + assignments + officer training + national positions + pending), and scenario metadata. Basic autosave on year change (to "autosave" slot). Code-driven Save Manager popup (F6 or via Save button) with list + Load/Delete actions using list_saves/delete_save/rename_save. Enhanced robustness (version migration stub, detailed save/load with errors, better guards). TopInfoBar Save button now quicksaves + opens manager; F5/F9 still fast paths. Full contract docs + updated header. Production/Leader/ScenarioLoader gained get/apply helpers.

**Good Place to Resume:**
- Combat resolver: apply training path bonuses in battle
- Leader replacement picker after death/retirement
- Wire `resolve_formation_destroyed()` into formation elimination code
- Continue Combat integration (more national effects on actual battle resolution)
- Rich province-based Agent Networks (recruitment, enemy pressure scaling, detection)

**Last Updated:** Late May 2026 (post major national modifier + agent effects integration)

## Recommended Next Priority Systems (May 2026 Assessment)

After the recent heavy investment in the National Modifier/Spirit system and Agent effects, here is the current recommended order for maximum game feel and integration:

1. **Deeper Combat Integration** (Highest immediate leverage)
   - Full wiring of national combat modifiers into actual battle resolution (soft/hard attack, org, width, casualties, etc.).
   - Make spirits and agent effects visibly change combat outcomes.

2. **Rich Agent / Espionage Networks** (High value, high fun)
   - Province-based persistent operative rings (as documented in the Agent section below).
   - Recruitment of locals, scaling with skill, detection risk from enemy units + enemy agents, real province-level effects.

3. **Technology System** (Foundation for mid-to-late game)
   - Already has good scaffold. Next is deeper agent interaction (tech theft/protection) and doctrine integration.

4. **Province Infrastructure & Development** (Enables many other systems)
   - Currently very placeholder. Needed for combat width, supply, factory efficiency, movement, etc.

5. **Diplomacy + National Focuses** (Big strategic layer)
   - Will naturally feed into the NationalModifierManager.

### Current Session State (Last Worked On)

### National Position Costs (Chiefs of Staff)
- Changing `chief_of_army`, `chief_of_navy`, `chief_of_air_force`, or `chief_of_space_force` should have a real cost (Stability, Prestige, Political Power, or cooldown).
- Must show clear cost preview to the player before confirming the change.
- Should support mitigation via Focuses, high leader Prestige, or national spirits.
- Currently only has a placeholder in `can_assign_national_position()`.

### Province Infrastructure System
- Provinces are still placeholders.
- `CombatWidthCalculator`, supply, factory repair, and logistics currently use temporary/default values.
- Needs full implementation and wiring into multiple systems.

### Civilian vs Military Factories
- Separate civilian production from military production.
- Different ideologies should have different consumer goods / stability requirements.
- Allow conversion of civilian factories to military factories (with time and cost — especially important for democratic countries).
- Focuses and agents should be able to influence conversion speed.

### Production Licensing & Diplomatic Factory Use
- Allow nations to license production templates from other countries.
- Use factories as part of diplomatic/trade deals.
- **Trade System foundation complete** (see scripts/national/TradeManager.gd):
  - Full offer/evaluation/accept backend with PUBLIC vs BLACK visibility.
  - Fairness weighting (extensible), quality_modifier on designs, direct integration with DesignManager.grant_acquired_design.
  - Comprehensive architecture docs + extension points for intel/tech/province/black-market events.
  - Trade UI fully functional: TradeMarketView (Public/Black/My Offers tabs, search/sort), Offer Details + rich counter editor (per-item editing, color-coded diffs, bulk scales, presets with save/load custom templates, tooltips, expanded SENT/RECEIVED My Offers with badges, stronger new-counter highlighting).
  - Audit of prior "claimed but incomplete" items closed with the above nice-to-haves (May 2026).

### Smart Production Advisor
- Tool that suggests which factories to assign when trying to build equipment for a new division/unit, with time-to-completion estimates.

## Leader System

- Proper per-country/culture name lists for generated leaders (USA/GER/ENG pools started).
- Replacement picker UI after death/retirement.
- Earned trait triggers (terrain time, encirclements, etc.).
- Promotion paths and Field Marshal multi-formation command.

## Combat System

- Expand `CombatResolver` with terrain, weather, air support, shore bombardment, engineers, night penalties, recon, etc.
- Implement proper **Combat Width** using infrastructure + terrain modifiers.
- Add reserve/reinforcement mechanics during battles.
- Effects of being surrounded and attacking from multiple directions.
- How supply interdiction affects combat over time.
- Wire more leader and equipment modifiers into actual combat calculations.

## National Spirits & Technology (Scaffold — May 2026)

### Completed (scaffold)
- `NationalSpiritManager` + `data/national/spirit_definitions.json` (per-country spirits)
- `NationalSpiritsScreen` (permanent spirits + temporary effects from `NationalModifierManager`)
- `NationalModifierDisplay` — modifier tooltips and formatted value rows
- National Spirits UI: view/category filters, search, duration bars, detail panel, hover tooltips
- Agent screen **National Effects** chips + tooltips on roster, targets, intel, operations, missions
- Visibility polish: feedback hint bar, title attention states, mission progress bars, outcome badges, View Agent from ops log, detection risk labels
- National Spirits: filter status line, debuff count in summary, agent-operation source tally
- **Technology:** Phase A + B — research UI, `support_radio` + `industry_foundations` trees, production gates, research toasts
- `TechnologyScreen` list + domain filter + inspector + start/cancel research
- Design picker padlocks (`Requires: Medium Tank II`); `ProductionManager` / shipyard conversion gated
- TopInfoBar **Technology** button opens research screen
- Doctrine model: research slots for equipment/support; leaders + Doctrine XP for levels; agents on R&D only

### Outstanding
- Wire spirit modifiers more deeply into Combat (full battle resolution) and leader systems
- National focus / event sources for temporary effects
- Diplomacy screen (foundation stub created: DiplomacyView + TopInfoBar wiring + bilateral Trade integration via new hooks)
- Rich persistent province-based Agent Networks (see "Agent & Espionage System" section below)

### Recently Completed (Major)
- Solid Supply integration: `calculate_daily_supply_consumption` now respects both permanent spirits and temporary national modifiers (including stability effects on consumption).
- Added convenient `get_total_supply_consumption_modifier()`, `get_total_attrition_reduction_modifier()`, and `get_total_interdiction_resistance_modifier()` on NationalSpiritManager.
- Deeper Combat integration:
  - National combat modifiers now applied at division/base stats level inside CombatResolver (before leader bonuses).
  - Interdiction chance on supply routes reduced by national logistics/attrition modifiers.
  - Attrition cargo demand on routes lightly reduced by national modifiers.
- Added explicit first-class support for `attrition_reduction` and `interdiction_resistance` keys across NationalModifierManager and NationalSpiritManager.
- These keys are now properly read from both permanent spirits and temporary effects and applied in Supply (interdiction chance + attrition cargo demand).
- NationalModifierManager fully implemented with clean querying and ticking.

## Technology System (planned — see docs/TECHNOLOGY_SYSTEM_DESIGN.md)

### Approved direction
- HOI4++ UX: domains, research slots, graph + list views, era bands 1900–2050+
- Single `TechnologyNode` JSON template; unlock registry into production/units/factories/doctrines
- `strategic_future` domain (Terra Invicta–style megaprojects)
- Agent missions steal/accelerate/protect specific tech nodes

### Implementation phases (summary)
- Phase A: schema + TechnologyManager + list UI + one tree slice — **done**
- Phase B: production/design unlock wiring — **done**
- Phase C: graph view + doctrine tab + era slider — **done**
- Phase D: agent tech theft, compromised UI, Technology ↔ Agents links — **done**
- Phase D: agent integration on tech screen
- Phase E: scenario starting tech + era trees (`land/air/naval_equipment`, `strategic_future`) — **done**
- Phase F: polish (compare tool, queue UI, …)

---

## UI & Screen Systems

### Screen Data Caching
- `ProductionScreenData` and `LeaderScreenData` are currently computed on demand.
- Implement simple caching with proper invalidation when relevant state changes (factory reassignment, leader assignment, daily tick, etc.).

### Production Assignment Screen
- Detailed spec: `docs/PRODUCTION_ASSIGNMENT_SCREEN.md` (layout, filters, interaction flow, data requirements).
- Implement UI against `ProductionScreenData` when visuals are prioritized.

### Leader Assignment Screen
- Detailed spec: `docs/LEADER_ASSIGNMENT_SCREEN.md` (national positions, two-column layout, data requirements).
- Implement UI against `LeaderScreenData` when visuals are prioritized.

## Production & Economy

- Improve long-term usage of real scenario data in `ScenarioFactorySpawner`.

---

## Agent & Espionage System

### Outstanding
- Visuals & UX for sabotage effects: special icons, distinct alert styling, and prominent critical success toasts in the news feed (currently on hold — graphics work deferred).

### Rich Operative Ring / Resistance Network Vision (Deferred — High Value, Recommended Next Big System)
- Move beyond one-off timed missions toward persistent province-based "rings" or "cells".
- Agents can be assigned to provinces to **establish and run networks** that recruit local operatives over time.
- Networks have levels/strength that grow with activity and can be given focuses:
  - Intelligence Gathering (low risk, generates localized intel)
  - Supply Disruption (harass convoys, reduce throughput in province)
  - Infrastructure Sabotage (damage rails/bridges, increase movement costs)
  - Influence / Partisan Recruitment
- Effectiveness scaled down by:
  - Number and quality of enemy divisions in/adjacent to the province
  - Enemy counter-intelligence agents operating in the region
- Networks can be detected and rolled up (strength loss, operative casualties, lead agent compromised/captured).
- Goal: Meaningful asymmetric impact and intelligence without being stronger than actual combat formations.
- Should feel like real WWII resistance / SOE / OSS operations (Free French style rings, etc.).
- Both the current timed-mission system and this richer persistent network system should coexist.

**Status:** Backend foundation started (AgentNetwork class + basic ticking in AgentManager). Needs enemy pressure wiring + real province-level effects. High priority recommendation after deeper Combat.

---

## Deeper Combat + Province Infrastructure — Concrete Phased Plan

**See the dedicated actionable plan:** `docs/MAP_IMPLEMENTATION_PLAN.md` (2026 update, post-ProvinceEffects + Phase 1 Supply/Combat wiring). It refines and sequences the older `docs/MAP_SYSTEM_DESIGN.md` M-phases with concrete next steps, MapManager as #1 priority, and parallelism notes.

### Phase 1: Province as a First-Class Gameplay Object (Current Focus)
- [x] Add rich computed getters on Province (`get_supply_throughput_modifier`, `get_local_supply_generation_modifier`, `get_combat_width_modifier`, `get_organization_recovery_modifier`, `get_attrition_modifier`, `get_logistics_quality`, etc.)
- [x] Wire development_level into Supply for local supply generation (basic implementation done)
- [x] Make infrastructure + development strongly affect depot throughput capacity (combined infra + dev scaling in SupplyNetworkBuilder and SupplyManager)
- [x] Make infrastructure + development affect interdiction resistance and reinforcement speed (SupplyManager + ProvinceEffects + explicit national totals)
- [x] Apply province development to organization and readiness in CombatResolver (initial implementation + full province_id/dev/infra path + casualty scaling)
- [x] Created ProvinceEffects aggregator for clean layering of base province stats + national modifiers
- [x] Expose these values clearly in province tooltips and supply map (hover tooltip + info panel)
- [x] Wire ProvinceEffects into more Supply and Combat calculations (for_country_province helper + calls in _plan_route, local gen, power calc, casualty)

### Phase 2: Combat Deepening
- [x] Combat Width already uses infrastructure (enhanced with development)
- [x] National combat modifiers applied at division base stats level in CombatResolver
- [x] Apply province development/infrastructure directly to:
  - Organization recovery during combat (get_effective_combat_power + ProvinceEffects)
  - Casualty / attrition rates in battle (resolve_battle_aftermath + _get_province_casualty_multiplier)
  - Reinforcement effectiveness (Supply route + delivery)
  - Supply consumption while fighting in the province (via org/readiness + attrition_mod)
- [ ] Make high-development provinces give small defensive bonuses (entrenchment, readiness)

### Phase 3: Full National Modifier + Province Synergy
- Make temporary national modifiers (especially from agents) able to temporarily degrade or boost province infrastructure/development.
- Allow spirits to give province-type bonuses (e.g., "Mountain Warfare Spirit" improves combat in mountains).

### Phase 4: Feedback & Polish
- Province tooltip shows current effective modifiers (infra/dev + national spirits + temporary effects).
- Combat preview and supply route tooltips show province contributions.
- Agent sabotage networks can target and degrade province infrastructure over time.

**Current Progress:** Phase 1 COMPLETE (all three items: Supply interdiction/reinforce via ProvinceEffects+national, CombatResolver battle/power paths now take real province dev for org/casualty, ProvinceEffects lightly wired in Supply+Combat national points). Phase 2 well advanced. Highest leverage area done for "map feels alive".

### Completed (Recent)
- Variable sabotage effect strength and duration based on mission outcome + agent sabotage skill.
- Rare critical success chance on sabotage missions that causes significantly stronger + longer-lasting debuffs.
- Critical sabotage success now generates a player-facing news announcement.
- Create proper Supply production system from provinces (capital as main source + limited local production in large cities).

## Notes

- Map, graphics, province visuals, and unit models are intentionally deprioritized for now.
- Focus remains on building solid backend systems and data structures first.
- Keep complexity layered: surface information should be simple and clear; deeper math and modifiers should be accessible but not forced on the player.

---

## Overall Progress Summary & Next System Recommendation (Late May 2026)

### Major Systems Status

**Strong / Mature:**
- Leader System (including Officer Training + national positions)
- Agent / Espionage System (timed missions + foundation for rich persistent networks)
- National Modifier / Spirit System (full backend + explicit keys + solid wiring)

**Good Integration:**
- Production (national modifiers fully active)
- Supply (consumption + interdiction + attrition)
- Combat (light-to-medium: national bonuses, division stats, interdiction/attrition)

**Still Early / High Leverage:**
- Province Infrastructure & Development
- Full Combat resolution (terrain, weather, width, actual battle math)
- Technology System (good scaffold, needs deeper gameplay loops)
- Diplomacy + National Focuses

### Recommended Next Major Focus (Updated May 28, 2026)

**Primary Recommendation: Province Infrastructure & Development System** (full design now available)

**See:** `docs/DESIGN_InfrastructureDevelopmentSystem.md` — complete data model, ProvincialProject, construction capacity, daily tick integration, agent sabotage duel extension, Phase A–D roadmap, and ready-to-implement GDScript skeleton.

**Why this is now the single highest-leverage next system:**
- The passive effects (Province getters + ProvinceEffects + daily repair + sabotage) + build gates are already excellent and wired into Supply/Combat/Production/UI.
- The missing piece is the **active lever**: players and AI must be able to deliberately develop provinces over time. Without it, "Invest here" tooltips are lies, tech-based build eligibility is a dead end, and long-term economic snowballing doesn't exist.
- Closing this loop makes every other recent investment (agents, national modifiers, Support/Radio tech, leader engineering bonuses, production assignment) *visibly matter* on the map for weeks of play.
- It is the classic "build once, benefits everywhere" foundation (supply, combat width, factory efficiency, movement, future factory slot unlocks).

**Implementation order after design lock:**
1. Phase A skeleton (InfrastructureDevelopmentManager + basic project start + daily tick)
2. InfoPanel + tooltip feedback (make the existing strings real)
3. Save/Load + agent sabotage wiring
4. Tech + passive factory-driven dev growth
5. Visual construction state on map

Secondary options (strong but lower foundational impact right now):
1. Full Combat resolution (terrain, width math, actual casualties/org from all the modifiers we already calculate).
2. Rich persistent Agent Networks (province rings + detection).
3. Push Technology trees beyond the current slice + doctrine integration.

**Current recommendation:** Execute the new `DESIGN_InfrastructureDevelopmentSystem.md` as the next major coordinated push. It will feel like the game "leveled up" in strategic depth.
