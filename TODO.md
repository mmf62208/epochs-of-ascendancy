# Epochs of Ascendancy — TODO

**Living snapshot:** [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) · **Doc index:** [docs/README.md](docs/README.md) · **Testing:** [docs/TESTING_PLAN.md](docs/TESTING_PLAN.md)

---

## Now (highest leverage for a self-contained playtest)

Goal: get from a powerful debug harness to a **50+ turn playable loop** where economy,
agents, technology, population, infrastructure, supply, production, and combat reinforce
each other without relying on F10-only flows.

1. **Main-loop combat and map campaigns**
   - ✅ Province assault exists via `BattleManager.execute_province_assault()` and `CombatResolver`.
   - ✅ Ctrl+click / Attack button path changes ownership and refreshes borders.
   - ✅ Simple AI battle initiation via `AIBattleDirector` (adjacent assaults + F10 AI Assault Pass).
   - [ ] Support multi-day and multi-province campaign resolution instead of isolated assaults.
   - [ ] AI formation movement toward fronts / operational war.
   - [ ] Integrate live air/naval/weather/loyalty/settlement/supply effects into battle aftermath.
   - [ ] Add visible combat intent/results outside DebugOverlay.
2. **Active infrastructure investment loop**
   - ✅ `InfrastructureDevelopmentManager` Phase B: PP ledger, Invest Infra/Dev, cancel/refund, progress/ETA UI, daily tick, sabotage duel, AI investment, passive factory→dev growth, hostile-capture cancel, save/load (projects + PP).
   - [ ] Overlay construction glyphs polish + richer effect preview.
   - [ ] Wire tech `construction_speed` / Industry Foundations into project rates and era caps.
   - [ ] Verify NMM, agent, engineer, population, sabotage, and settlement modifiers end-to-end.
3. **Save/load hardening for long sessions**
   - ✅ Broad persistence exists for time, tech, agents, supply, map, NMM, leaders, production, infrastructure projects, and PP.
   - [ ] Regression-test active infrastructure projects, formations, agent passive impacts, diffusion state, and scenario metadata.
   - [ ] Persist Ascendancy/peace state once those systems move beyond stubs.
   - [ ] Add autosave UX and recovery messaging for long campaigns.
   - [ ] Maintain migrations for population, infrastructure, formations, and future peace/Ascendancy sections.
4. **Headless and playtest regression**
   - ✅ Godot 4.6.2 headless smoke can bootstrap `TestScenario.tscn` after editor import.
   - [ ] Make `--quit-after 15` or an explicit test-runner exit mode reliable for CI.
   - [ ] Keep full leader roster reload behind `EOA_RUN_FULL_LEADER_TESTS=1` to avoid OOM.
   - [ ] Add focused headless checks for infra persistence, combat AI decisions, and agent passive impacts.

---

## Differentiator systems (build after the core loop is stable)

1. **1918 Armistice Peace + Ascendancy Initiatives / Golden path**
   - [ ] Flesh out initiative tree data: alternate political, cultural, economic, military, and technological branches.
   - [ ] Complete PeaceConferenceWindow resolution mechanics and multi-year follow-on decisions.
   - [ ] Implement initiative costs/effects through pillars, NMM, agents, technology unlocks, and national spirits.
   - [ ] Add Golden Age / Golden Initiative specials with visible payoff and strong constraints.
   - [ ] Make agents central as sponsors, negotiators, vision carriers, and project leaders.
2. **Agents as the player's will**
   - ✅ Skills, traits, missions, networks, record/honing, passive national impacts, and sponsor/lead hooks are in place.
   - [ ] Add direct "will directives" that assign agents to pillars, national projects, industrial pushes, or war aims.
   - [ ] Add milestones and feedback for passive agent impacts on production, research, resources, cohesion, and military readiness.
   - [ ] Expand timeline projects beyond the initial Guderian/Tukhachevsky-style starters.
   - [ ] Balance trait/record scaling so agents are powerful but not exploitable.
3. **Technology timeline and diffusion**
   - ✅ Early 1890s-1938 foundations, diffusion thresholds, agent early unlock hooks, and project unlocks exist.
   - [ ] Add more national/agent-led projects for 1918-1938 alt-history paths.
   - [ ] Improve UI explanations for diffusion catch-up, ahead penalties, agent early notes, and unlocked designs/modules.
   - [ ] Add balance tests for 3-nation / 5-nation diffusion thresholds and early unlock bonuses.

---

## Map & visuals

- [x] Grand theater underlay + terrain toggle + map visual editor (Debug → Map Visual Editor)
- [x] Dynamic `BorderLayer` + F10 border demo / test combat / owner cycle
- [x] Phase 1 test scenario (~180 provinces) + generation tooling in `tools/map_generation/`
- [ ] Replace placeholder `ultra_high.jpg` with final art master
- [ ] Scale generation toward 350–450 province Europe target
- [x] Unit icons on map (NATO archetypes + nation tint in playtest)
- [ ] Continue settlement/population visual feedback for dense cities, attrition, supply, and organization effects

---

## Systems backlog (medium)

| Area | Next step |
|------|-----------|
| Combat | Multi-day campaigns, AI movement to fronts, live air/naval/weather/settlement effects |
| Leaders | Training bonuses in live battles, doctrine-gated paths, news feed panel |
| Technology | More 1918-1938 project content, diffusion UI, construction_speed wiring |
| Agents | Will directives, passive impact UI, project sponsorship, persistent province rings |
| Diplomacy | Flesh out `DiplomacyView`, peace/continuation hooks, AI offers |
| Production | Assignment UX polish, stock/OOB feedback, AI production priorities |
| Trade | Balance, AI offers, strategic resource pressure |
| Policy/Pillars | Surface Ascendancy/Cohesion/Mandate effects in regular screens |
| Weather | Move beyond overlay stub into battle/supply/air/naval consequences |
| AI | Expand invest/produce/attack logic using doctrines, pillars, and agents |

---

## Recently completed

- **Aug 9:** Merged June 15 playtest UX branch (PR #1) onto continuation work; Infra Phase B (PP ledger, Invest Dev, cancel/refund, passive dev growth, hostile capture cancel, AI investment); `AIBattleDirector` + F10 AI Assault Pass.
- **Jun 15:** Top-bar player country selector; ESC closes topmost UI first; safer F9 load path; weather daily tick wiring; ScenarioLoader lookup fixes; draggable panel clamping; interactive time enabled by default with `EOA_FREEZE_TIME=1` smoke mode; missing Godot script UID added. Headless Godot 4.6.2 production/combat PASS.
- **Jun 6:** Debug overlay layout (full-width buttons, vertical scroll only, draggable + **⤡ resize**); WorldMap InfoPanel scroll; TopInfoBar/MainMenu HUD sync; phased combat headless test; `SpecialSiteManager` autoload + site ID fixes.
- **Jun 5:** Grand theater auto-load, terrain toggle, map editor export/load, weather on high-res bg.
- **Jun 4–5:** BorderLayer, F10 combat capture demo, TestRunner map-first bootstrap, leader roster fallback for `phase1_europe_test`.

---

## Deep reference (do not duplicate here)

Long-form status, leader/combat/agent notes, and historical session bullets were **condensed into** [CURRENT_STATE.md](docs/CURRENT_STATE.md) and [docs/README.md](docs/README.md). Use these design docs when implementing:

- Infrastructure: [DESIGN_InfrastructureDevelopmentSystem.md](docs/DESIGN_InfrastructureDevelopmentSystem.md)
- Map sequencing: [MAP_IMPLEMENTATION_PLAN.md](docs/MAP_IMPLEMENTATION_PLAN.md)
- Leaders: [LEADER_SYSTEM_DESIGN.md](docs/LEADER_SYSTEM_DESIGN.md)
- Technology: [TECHNOLOGY_SYSTEM_DESIGN.md](docs/TECHNOLOGY_SYSTEM_DESIGN.md)
- UI patterns: [UI_DESIGN_REFERENCE.md](docs/UI_DESIGN_REFERENCE.md)
- Weather/environment: [WEATHER_AND_ENVIRONMENT_SYSTEM_DESIGN.md](docs/WEATHER_AND_ENVIRONMENT_SYSTEM_DESIGN.md)
- Hidden hand / agents: [HIDDEN_HAND_DESIGN.md](docs/HIDDEN_HAND_DESIGN.md)

---

## Suggested implementation order

1. AI formation movement + multi-province campaign loop (assault AI exists; operational war next).
2. Save/load hardening: active infra/PP, formations, agent impacts, diffusion, scenario metadata, autosave UX.
3. Tech construction bonuses + Industry Foundations slice; overlay/effect preview polish.
4. 1918 Peace + Ascendancy Initiatives: initiative tree, peace resolution, agent sponsorship, Golden specials.
5. Agent will directives and timeline projects: direct assignments, milestones, passive-impact feedback, balance tests.
6. Main UI polish: make production/tech/agent/diplomacy/inspector flows usable without F10.
7. AI/content/balance: invest, produce, attack, trade, agent power, diffusion, population, and scenario flavor.
