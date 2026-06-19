# Technology System Design — Epochs of Ascendancy

**Status:** Phase A–D implemented (research UI, production gates, graph/doctrine, agent espionage hooks)  
**Last updated:** May 2026  
**Goal:** A research experience comparable to Hearts of Iron IV in clarity and strategic weight, with deeper hooks into production and equipment than vanilla HOI4, plus a Terra Invicta–style future lane for post–Cold War and 21st-century strategic technologies.

This document defines the **data model**, **UI topology**, **content taxonomy**, **integration contracts**, and **phased build path**. Implementation should not begin as a flat JSON list (current `research_catalog.json` stub); it should begin as **schema + one vertical slice** (e.g. Industry + one land-equipment chain) wired end-to-end.

---

## 1. Design pillars

| Pillar | Meaning for Epochs |
|--------|------------------|
| **One template, many domains** | Every node—rifle, shipyard, doctrine, fusion grid—uses the same `TechnologyNode` schema with typed `unlocks` and `effects`. |
| **Surface simple, depth on demand** | Summary bar + research slots + color-coded graph; full modifier breakdown, prerequisites, and agent risk in tooltips / inspector. |
| **Time is first-class** | Nodes belong to **era bands** (1900–2050+). UI and availability gate on `game_year`, scenario start, and national modifiers. |
| **Production-native** | Tech unlocks **designs**, **factory types**, **buildings**, and **retooling rules**—not abstract “+5%” only. |
| **Agents are part of R&D** | Espionage accelerates, steals, delays, or compromises specific nodes (already stubbed in `AgentManager`). |
| **Doctrines are cousins, not duplicates** | Grand doctrines (HOI4-style) link to existing `doctrine_training_paths.json` and `ProductionManager` doctrine presets; avoid two conflicting doctrine systems. |

### 1.1 Doctrine progression (approved hybrid)

Three parallel tracks — each with a clear fantasy:

| Track | Who “does the work” | Player-facing |
|-------|---------------------|---------------|
| **Equipment / industry / support** | National R&D — **research slots** + unified **RP/day** pool | Technology screen, list/graph |
| **Grand doctrines (levels I–III)** | **Leaders** + **Doctrine XP** from combat, exercises, and training paths | Technology **Doctrine** tab for eligibility; **Leader → Training Paths** for spending XP |
| **Espionage on R&D** | **Agents** — steal progress, plant labs, sabotage enemy research, intel bonuses | Agent missions; inspector shows agent hooks per node |

**Rules:**

- Doctrine nodes use the same `TechnologyNode` template (`node_kind: doctrine` or `domain: *_doctrine`) but **do not consume main research slots** for level-ups once eligible.
- Tech **unlocks doctrine eligibility** (`doctrine_key` unlock); `TechnologyManager.is_doctrine_key_unlocked()` gates leader training.
- Agents **never** “research doctrines” directly — they shape equipment/support R&D and enemy delays.
- Doctrine XP pool (Phase C+) ticks from battles and leader activity; MVP stores keys only when support tech completes (e.g. `combined_arms` from Radio I).

---

## 2. Player experience (target UX)

### 2.1 Screen topology (HOI4++)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Technology — USA          [Slots: ●●○]  RP/day: 4.2   Year: 1939  [Close]   │
├──────────┬──────────────────────────────────────────────────┬───────────────┤
│ DOMAINS  │  [Pan/zoom research graph OR column list view]    │  INSPECTOR    │
│ Industry │                                                   │  Selected:    │
│ Land Eq  │     ○───○───●───○                                 │  Radio III    │
│ Naval    │         \   /                                     │  ─────────    │
│ Air      │          ●                                         │  Cost: 98d   │
│ Space    │                                                   │  Effects…     │
│ Support  │  Era band: ███ 1914–1938 ███ 1939–1955 …         │  Unlocks…     │
│ Future   │                                                   │  [Research]   │
│ Doctrine │                                                   │  [Queue]      │
├──────────┴──────────────────────────────────────────────────┴───────────────┤
│ [Search] [Available only] [Show future]     Agent: +12% tech from intel     │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Interaction modes (toggle):**

1. **Graph view** — Primary immersion mode; nodes as cards/icons with edges (prerequisites). Pan, zoom, snap to era band. HOI4 column layout can be generated automatically from `tree_id` + `column` + `row`.
2. **List view** — Accessible fallback; sort by era, cost, status; same data, faster to ship MVP.
3. **Doctrine view** — Sub-tree or linked panel using same node template with `domain: doctrine`.

**Always visible:**

- Active research slots (2–5, era/national spirit dependent).
- Daily research power (RP) and breakdown tooltip (base + education + industrial capacity + agents − penalties).
- Queue (optional slot 2+ queue like HOI4 with delay).
- **Impact preview** on hover: “Unlocks: M4 Sherman design, Tank Plant conversion.”

### 2.2 Feedback & immersion (match Agent / Leader UI quality)

- Retrowave panels, outcome-colored states: locked / available / in progress / completed / compromised (agent).
- Progress ring on active node; ETA in days/months.
- “Pinging” integration: when tech completes, toast + highlight affected factories/designs in Production screen.
- National Spirits / temporary modifiers show as chips on tech bar (reuse `NationalModifierManager` pattern).

---

## 3. Technology taxonomy

### 3.1 Top-level domains (`domain`)

| Domain ID | HOI4 analogue | Epochs scope |
|-----------|---------------|--------------|
| `industry` | Industry tree | Factories, shipyards, ports, airports, refineries, electronics, construction speed, retooling |
| `land_equipment` | Infantry / Support / Armor | Rifles, support gear, artillery, tanks, mechanized, modules |
| `naval_equipment` | Naval | Hulls, modules, ASW, carriers, submarines, port rules |
| `air_equipment` | Air | Fighters, CAS, bombers, helicopters, UAVs, airframes |
| `space_equipment` | (future HOI4 mods) | Launch, ISR satellites, ASAT, orbital logistics (2050 band); expanded 1945-1970 alt-history: V2/rocketry_foundations, sputnik_satellite, human_spaceflight, moon_landing, orbital_station, mars_probe, mech_prototype/dieselpunk_mech/mech_designer, secret vs public branches (secret_funding_space, public_space_program, rule_flag secret_funding), nuclear_thermal_engine, ai_research + ai_ethics |
| `land_doctrine` | Land doctrine | Plans, combat width, entrenchment—sync keys to `doctrine_training_paths` |
| `naval_doctrine` | Naval doctrine | Fleet in being, trade interdiction, carrier ops |
| `air_doctrine` | Air doctrine | Air superiority, ground support, strategic bombing |
| `space_doctrine` | — | Orbital denial, space lift, integrated space-ground |
| `support` | Electronics, radar, encryption | Radio, computing, recon, encryption (cross-cutting) |
| `strategic_future` | Terra Invicta–like | Fusion, AI command, bio-enhancement, climate geoengineering, quantum sensing |

### 3.2 Era bands (`epoch`)

Use **overlapping year ranges** on each node; UI groups nodes into swimlanes:

| Epoch key | Typical years | Character |
|-----------|---------------|-----------|
| `pre_war` | 1900–1918 | Early oil, bolt-action, dreadnoughts |
| `interwar` | 1919–1938 | Mechanization begins, radar proto |
| `industrial_war` | 1936–1955 | WWII peak (scenario 1936 anchor) |
| `cold_war` | 1946–1989 | Jets, missiles, early computing; 1945-1970 space race alt-history branch (V2 -> sputnik -> moon / secret space / dieselpunk mechs; public prestige vs black budget rule_flags + agent funding missions) |
| `modern` | 1970–2010 | Precision, NBC, network-centric |
| `information` | 1990–2030 | Stealth, drones, GPS-era |
| `near_future` | 2020–2040 | Hypersonics, AI-assisted C2 (2026 roster exists) |
| `far_future` | 2040–2050+ | Fusion grids, orbital industry, strategic AI |

Nodes can span multiple epochs via `era_min` / `era_max`; **availability** still checks `prerequisites` + `game_year`.

### 3.3 Node types (`node_kind`)

| Kind | Purpose |
|------|---------|
| `research` | Standard RP cost, unlocks content |
| `doctrine` | XP or RP, levels I–III, exclusive branches |
| `building` | Unlocks build/convert actions (shipyard, airfield, port upgrade) |
| `passive` | National modifier only (e.g. +5% factory output) |
| `project` | Long “megaproject” (Terra Invicta): multi-year, single slot, huge effects |
| `repeatable` | Diminishing returns (e.g. electronics mini-boosts) |

---

## 4. Canonical data template (`TechnologyNode`)

All content lives under `data/technology/`:

```
data/technology/
  SCHEMA.md                    # Field reference (generated from this doc)
  trees/
    industry.json
    land_equipment.json
    naval_equipment.json
    air_equipment.json
    space_equipment.json
    doctrines_land.json
    doctrines_naval.json
    doctrines_air.json
    doctrines_space.json
    support.json
    strategic_future.json
  national/
    USA_starting_tech.json       # Optional scenario overrides
    GER_starting_tech.json
  agents/
    tech_mission_hooks.json      # Which missions affect which domains
```

### 4.1 Single node shape (JSON)

```json
{
  "id": "usa_tank_medium_ii",
  "name": "Medium Tank Chassis II",
  "domain": "land_equipment",
  "tree_id": "land_armor_usa",
  "node_kind": "research",
  "column": 2,
  "row": 4,
  "tier": 2,
  "era_min": 1938,
  "era_max": 1955,
  "epoch": "industrial_war",
  "historical_only": false,
  "tags": ["armor", "usa_flavor"],

  "prerequisites": ["usa_tank_medium_i"],
  "mutually_exclusive_with": [],
  "hidden_until": { "year": 1936, "requires_any": [] },

  "research": {
    "base_cost_days": 120,
    "category": "armor",
    "ahead_of_time_penalty_per_year": 0.15,
    "repeatable": false
  },

  "unlocks": [
    { "type": "unit_design", "template_ids": ["m4_sherman_medium"] },
    { "type": "production_category", "category": "armor", "min_factory_type": "tank_plant" },
    { "type": "division_capability", "capability": "mechanized_division" },
    { "type": "modifier", "stat": "armor_production_speed", "value": 0.05 }
  ],

  "effects": {
    "national_modifiers": {},
    "doctrine_keys_unlocked": []
  },

  "agent": {
    "theft_target": true,
    "sabotage_delay_days": 30,
    "intel_domain": "technology",
    "counter_intel_node": "secure_research_facility"
  },

  "ui": {
    "icon": "res://assets/tech/icons/tank_medium_ii.png",
    "short_effect": "Unlocks M4 Sherman production",
    "flavor": "Welded hulls and improved powertrains…",
    "tooltip_stats": ["armor_production_speed +5%"]
  }
}
```

### 4.2 Unlock types (integration contract)

Every unlock `type` maps to one backend handler in `TechnologyUnlockRegistry`:

| `type` | Consumer system |
|--------|-----------------|
| `unit_design` | `UnitTemplate` / design picker in Production |
| `production_category` | `ProductionManager.assign_design` validation |
| `factory_type` | `FactoryManager` create/convert (`shipyard`, `aircraft_factory`, `tank_plant`) |
| `building` | Province buildings: port, airfield, naval yard, rocket site |
| `division_template` | `division_templates.json` template id or capability flag |
| `division_capability` | Mechanized, marine, airborne, special forces, space infantry |
| `equipment_module` | Tank/air/ship module slot |
| `doctrine_key` | `doctrine_training_paths` + `ProductionManager.apply_doctrine` |
| `leader_gate` | `LeaderManager` naval/air cadet gates (replace TODO placeholders) |
| `modifier` | `NationalModifierManager` or combat/production stat bus |
| `rule_flag` | Rules JSON toggles (e.g. `allow_carrier_conversion`) |
| `agent_mission` | Unlocks advanced agent missions vs targets with tech |

**Rule:** No unlock may be “display only”—each must fire a signal `technology_unlocked(country, tech_id, unlock_entry)` that subscribers handle.

---

## 5. Research economy

### 5.1 Research power (RP)

HOI4 uses one pool; Epochs can use **one unified pool** with category efficiency (simpler for players):

```
effective_rp_day = base_rp
  × (1 + industrial_tech_bonus + education + national_spirits)
  × (1 + agent_tech_bonus - enemy_sabotage)
  / (1 + ahead_of_time_penalty)
```

- **Base RP** from industrial capacity (# factories, literacy proxy, population tier).
- **Category focus** (optional): allocate % to Industry / Land / Naval / Air / Future—HOI4-style specialization without five separate pools initially.

### 5.2 Research slots

| Slot | Default unlock | Notes |
|------|----------------|-------|
| Slot 1 | Start | Always available |
| Slot 2 | Industry tech | |
| Slot 3 | Electronics / support | |
| Slot 4+ | National spirits, focuses, late eras | |

Doctrine research can occupy a slot OR run in parallel on slower “doctrine XP” from combat (design choice: **parallel doctrine XP** reduces slot competition).

### 5.3 Ahead-of-time & backlog

- Researching before `era_min`: apply `ahead_of_time_penalty_per_year` to effective cost (HOI4 model).
- **Captured tech**: Copy enemy completed nodes as “reverse engineered” (50–80% cost reduction)—agent missions can grant partial progress.
- **Queue**: Second choice waits; UI shows queue order.

---

## 6. Agent ↔ technology integration

Existing missions (`steal_research`, `infiltrate_research_lab`, `secure_research_facility`) become **first-class**:

| Mission outcome | Technology effect |
|-----------------|-------------------|
| `research_progress` | Add % days to active node OR grant progress on specific `target_tech_id` |
| `long_term_tech_intel` | Passive RP bonus vs target nation’s domain for N years |
| `tech_theft_protection` | Reduce theft chance; flag node `compromised` false |
| Sabotage (future) | Add `sabotage_delay_days` to enemy active research |

**UI:**

- Technology inspector shows “Foreign intel: +8% progress on Radio Networks (from agent in GER).”
- Compromised nodes (enemy detected theft) appear with warning border; must run counter-intel mission to clear.

**Data:** `data/technology/agents/tech_mission_hooks.json` maps `mission_id` → `domain`, `progress_magnitude`, `valid_targets`.

---

## 7. Content scope (1900–2050)

### 7.1 Industry tree (examples)

- **Foundations:** basic machine tools, chemical industry, standard gauge railways.
- **WWII:** dispersed industry, construction V, advanced machining.
- **Factories:** civilian/military conversion, tank plant, aircraft factory, **shipyard at port** (ties to `factory_rules.shipyard`).
- **Ports & logistics:** port expansion, deep-water port, containerization (modern).
- **Future:** automated fabs, rare-earth refining, orbital assembly (strategic_future crossover).

### 7.2 Land equipment chains

Parallel columns (HOI4 style):

1. **Infantry weapons** — bolt → semi-auto → assault → future caseless.
2. **Support equipment** — radios, flamethrower, night vision, drones.
3. **Artillery** — towed → SP → MLRS → hypersonic artillery (future band).
4. **Armor** — light → medium → heavy → MBT → next-gen platform (link `usa_mbt_2026` templates).
5. **Mechanized / motorized** — unlocks division capabilities + truck templates.

Each step unlocks specific `template_ids` already in `data/unit_templates/`.

### 7.3 Naval & air

- **Naval:** DD → CL → BB → CV hulls; submarine branches; module slots (sonar, radar, ASW).
- **Air:** biplane → mono → jet → stealth → UCAV; tie to `usa_fighter_*` era files.
- **Space (2050 band):** launch capacity, ISR sat, ASAT—gated behind `strategic_future` prerequisites.

### 7.4 Doctrines (land / air / sea / space)

- Reuse **keys** from `doctrine_training_paths.json` (`infiltration`, `mobile_warfare`, `network_centric`, etc.).
- Tech tree **unlocks** doctrine eligibility; `LeaderManager` training path invests XP for levels.
- Naval/air/space doctrine trees unlock carrier ops, trade interdiction, orbital denial modifiers for `CombatResolver` (when wired).

### 7.5 Special forces & division types

Unlock via **capability flags**, not duplicate templates everywhere:

- `special_forces`, `marines`, `airborne`, `mountaineers`, `mechanized`, `armored_division_1944`, `space_marines` (far future gag or serious).

`division_templates.json` references capabilities; tech gates template visibility in OOB designer (future UI).

### 7.6 Terra Invicta–style strategic future (`strategic_future` domain)

Megaproject nodes (long cost, single slot):

| Example node | Era | Game impact |
|--------------|-----|-------------|
| Practical fusion | 2045+ | Energy modifier, factory output, special building |
| AGI-assisted C2 | 2035+ | Planning speed, agent counter-intel, air/naval doctrine |
| Orbital manufacturing | 2040+ | Space equipment cost −30% |
| Advanced bioenhancement | 2030+ | Special forces cap, stability risk |
| Climate adaptation grid | 2040+ | Supply resilience, coastal province bonuses |

These should feel **optional and risky** (stability / prestige tradeoffs via `NationalModifierManager`).

---

## 8. Backend architecture

### 8.1 Autoload: `TechnologyManager` (replace stub)

Responsibilities:

- Load all `trees/*.json` into `TechnologyNode` resources or dictionaries.
- Per-country state: `completed`, `active_slot`, `progress_days`, `queued`, `stolen_progress`.
- `get_screen_data(country)` → `TechnologyScreenData` (graph layout + inspector).
- `can_research(country, tech_id)`, `start_research`, `tick_research(days)`.
- Emit signals: `research_started`, `research_completed`, `technology_unlocked`.

### 8.2 `TechnologyUnlockRegistry`

Static or autoload registry:

```gdscript
func apply_unlock(country_tag: String, unlock: Dictionary) -> void
```

Dispatches to `ProductionManager`, `FactoryManager`, `LeaderManager`, etc.

### 8.3 `TechnologyScreenData` (UI resource)

- `domains[]` with node summaries for graph/list.
- `active_projects[]`, `rp_breakdown`, `era_bands[]`.
- `agent_tech_summary` (from `AgentManager` + intel cache).
- Precomputed edges for graph renderer.

### 8.4 Year tick

Hook `LeaderManager.game_year_advanced` (already used by agents) to:

- Refresh availability (`hidden_until.year`).
- Apply ahead-of-time penalties.
- Expire time-limited stolen tech bonuses.

---

## 9. UI implementation plan (Cursor-friendly phases)

### Phase A — Foundation (2–3 weeks)

- [x] Finalize `TechnologyNode` schema (`data/technology/SCHEMA.md` + tree JSON).
- [x] Replace `TechnologyManager` stub with tree load + per-country state + year tick.
- [x] **List view** `TechnologyScreen` (domain filter, inspector, start/cancel research).
- [x] Wire vertical slice: **Support → Radio** (`data/technology/trees/support_radio.json`).
- [x] `TechnologyUnlockRegistry` — modifier, doctrine_key, capability, agent_mission stubs.
- [ ] TopInfoBar RP/slots chip (screen summary bar done; bar chip optional).

### Phase B — Production integration (2–3 weeks)

- [x] `unit_design` + `factory_type` + `production_category` + `rule_flag` unlock handlers.
- [x] Design picker + production screen padlock (`Requires: Medium Tank II`).
- [x] Industry tree slice: `industry_foundations.json` (tank plant, M4 Sherman, port shipyard).
- [x] Research complete → `LeaderEventUI` toast (player country).
- [x] `ProductionManager` / `FactoryManager` enforce tech gates on assign and shipyard conversion.

### Phase C — Graph view & doctrines (3–4 weeks)

- [x] Pan/zoom graph (`TechnologyGraphView`); column/row layout + prerequisite edges.
- [x] Doctrine tab: `land_doctrine.json` + training path eligibility panel + link to `TrainingPathScreen`.
- [x] Era swimlane slider (`ERA_SWIMLANES`) filters list/graph by `epoch`.
- [x] `LeaderManager._country_has_doctrine` wired to `TechnologyManager.is_doctrine_key_unlocked`.

### Phase D — Agents & espionage (1–2 weeks)

- [x] Mission hooks apply progress to targeted `tech_id` (`apply_research_theft_from_mission`, stolen progress bank).
- [x] Inspector agent lines; compromised status; summary bar + graph styling.
- [x] Technology ↔ Agents cross-links; `TechnologyMissionTargetPopup` for steal missions.
- [x] Long-term tech intel (+RP/day), theft protection, victim progress loss on detection.

### Phase E — Content scale (ongoing)

- [x] Author trees per era; align template ids in `unit_templates/` (`land_equipment`, `air_equipment`, `naval_equipment`).
- [x] National starting tech files per scenario (`data/technology/starting/1918.json`, `1936.json`, `2026.json`).
- [x] `strategic_future` megaprojects for 2040+ scenarios (`strategic_future.json`; applied on 2026 start for majors).
- [x] `ScenarioLoader` → `TechnologyManager.apply_scenario_starting_tech()` on load.
- Early space race milestones (GameData 1957+ first_satellite etc) check TM.is_tech_completed (ids like sputnik_program, lunar_landing_program; support edit_tech for tests). Research ethics space militarization from signal/pending. See CURRENT_STATE + GameData process_space_race_events.

### Phase F — Polish (HOI4++)

- [ ] Compare tool (hover enemy tech in diplomacy—future).
- [ ] Research queue, focus specialization UI.
- [ ] Sound/haptics optional; achievement pings.

---

## 10. HOI4 comparison — what we do better

| HOI4 | Epochs target |
|------|----------------|
| Static columns, little factory linkage | Every major unlock names **concrete designs** and **factory types** |
| DLC siloed trees | Unified template; mods add JSON trees |
| Agents barely exist | **Espionage R&D** is visible on tech screen |
| Doctrines separate from equipment | Explicit bridge to **Leader training paths** |
| No 2050 vision | **strategic_future** lane + existing 2026 unit roster |
| Retooling invisible | Tech modifies **retooling days/efficiency** via `factory_rules` |

---

## 11. Consistency checklist for content authors

When adding a node, verify:

1. `id` is globally unique across all trees.
2. At least one `unlock` references real `template_id` or `factory_type` in codebase.
3. `era_min` / `era_max` align with template `production_era`.
4. `prerequisites` form a DAG (no cycles).
5. `ui.short_effect` is player-readable in one line.
6. If `agent.theft_target`, enemy should have matching mission eligibility.
7. Doctrine nodes include `doctrine_keys_unlocked` matching `doctrine_training_paths.json`.

---

## 12. Open decisions (product calls)

1. **Graph first vs list first?** Recommend **list first** for MVP, graph in Phase C.
2. **Separate doctrine screen?** Recommend **tab inside Technology** + deep link from Leader training.
3. **National focuses:** Tree of focuses grants `research_bonus` and `tech_discount`—out of scope here but reserve `hidden_until.requires_focus`.
4. **Multiplayer:** Design IDs are deterministic; state is per `country_tag` only.

---

## 13. Immediate next steps (recommended)

1. Review and approve this document (adjust domain list / era bands).
2. Add `data/technology/SCHEMA.md` + one full example tree `support_radio.json` (5–8 nodes).
3. Implement Phase A in Cursor while Grok Build wires combat/production consumers for unlock types.
4. Expand Agent UI “Technology impact” line when active research exists (read from `TechnologyManager`).

## 14. 2026 Evolution — Agent-Centric Project Layer (post user query June 2026)

User feedback (June 2026): Early "radio" nodes corrected to accurate telegraphy → voice progression (1895 Wireless Telegraphy is Morse/radio waves, not voice "radio"; voice nets 1930s; radar is separate). Agents must be *central* to technology (not just passive theft). Doctrines tie in. Modules depend on tech. Avoid "exactly HOI4". Tradeoffs must matter with real consequences. Maximize replay via choices + agent outcomes.

**Current base tree (implemented)**: Authored nodes (columns/rows for graph, prereqs + mutually_exclusive_with for alts, era_min for 1890s-1938 grounding, concrete unlocks to modules/designs/doctrine_keys/buildings). 53 nodes across industry/land/naval/air/support/land_doctrine + new national_projects prototype. UI already has domain/era filters, list+graph views, agent bar (intel bonus, compromised count, active tech missions, theft protection), inspector showing exact effects + agent risk, doctrine panel. RP unified with stolen bank/compromised halting + intel bonus. Strong existing agent integration (steal_research adds progress or alternatives, infiltrate gives long-term RP bonus, secure for counter, compromise halts research).

**Example current path + tradeoffs**: GER rushes early_radio_telegraphy_1895 (telegraphy, +recon + radio module) + chemical/synthetic_1917 → chooses synthetic_fuel_focus_1935 (mut excl with import path; unlocks refinery cat + more supply mods + synthetic_tires). This gives logistics independence (great vs blockade) but creates high "detection_signature" for agents (enemy can target the plants or steal the exact module tech, handing them your sustainment edge). Simultaneously take carrier_aviation_program project instead of BB supremacy for CVs + carrier_task_force key. Tradeoff: strong projection, but if you skip ASW tech (or agent failed to steal it for you) subs counter your carriers hard. Changing service doctrine (blitz to something else) now applies org loss to your panzer divisions + design penalties (as requested — no stability hit). Modules (mg08, bofors, ap50_bomb, radios, synthetics) are gated behind these choices.

**Tradeoffs & consequences baked in**:
- Mutually exclusive branches force real style commitment (mobile armor vs infantry support tanks; carrier vs battleship; CAS/tactical air vs early strategic bombing; synthetic autarky vs import security).
- Agent surface: High-value nodes have theft_target + sabotage_delay + detection_signature. Successful enemy steal = they get progress/bank or the unlock; you may get "compromised" (research halted) + intel leak (enemy knows your exact capabilities for counter-design).
- Doctrine evolution: Tech unlocks keys for training paths + service doctrines (on chiefs). Full power comes from leader XP + agent "reform" missions. Changing mid-campaign has targeted org hits on formations (divs/ships/wings) + prototype re-eval penalties.
- Modules & designs: Depend on tech (or projects). Designer still allows micro, but service doctrine + tech bias the available archetypes and suggested modules.
- Replay: Different branch choices + which agent missions succeed/fail + chief assignments create different equipment mixes, vulnerabilities, and counters every game. Alts are plausible (early German synthetic or heavy program, French mobile alt to Maginot, UK radar network priority).

**Proposed evolution options (reviewed against other games + user priorities)**:

1. **Incremental Authored Tree Polish (light evolution, closest to current)**: Keep rich authored grid + mut excl. Add "R&D Focus" assignment (player assigns a tech-skilled agent or chief to a domain for bonus RP or small chance of "breakthrough" that spawns a hidden alt module or reduces cost on a mut-excl branch). Expand existing agent missions slightly (more targeted steal on specific high modules). Tradeoffs via existing mut excl + ahead penalties + compromise. Replay from branch choice + occasional breakthroughs.

   Pros: Low dev cost, preserves historical control players like. Cons: Agents still somewhat secondary (not "key").

2. **Card/Draw + Invention Layer (Stellaris-inspired choice + Vic3 organic feel)**: After completing key prereqs or era bands, instead of one fixed next node you "draw" 2-4 development options (different tradeoff profiles: e.g. "reliable mass medium tank" vs "experimental heavy with new module" vs "export-quality light for allies"). Draws biased by current service doctrine, captured enemy equipment (from combat/agents), agent-gathered "foreign theories". Inventions pop from conditions (like Vic3). Agents can "plant theory" or "steal blueprint" to add/remove cards or bias draws.

   Pros: Feels fresh vs pure tree, high variance/replay, choices have immediate visible consequences in the draw. Cons: Loses some "I planned this exact 1890-1938 path" predictability; harder to author tight historical + alt branches.

3. **Diffusion + Agent-Primary Advancement (most outside-the-box, Vic3 + Shadow Empire + Distant Worlds emergent)**: Reduce rigid authored prereq tree. Have domain "knowledge levels" or broad tech areas that advance via passive RP + direct agent investment (send agent team on "industrial espionage" or "prototype recovery" missions that give direct progress or captured modules/designs into your catalog). Combat XP + captured enemy units can "diffuse" tech (reverse engineer). Doctrines evolve from accumulated leader/agent/combat data rather than pure research. Tradeoffs via "adoption penalties" (jumping ahead without supporting industry/infra causes readiness/org issues or module incompatibility until fixed).

   Pros: Agents become the primary driver of your tech edge (exactly as requested). Extremely high replay and "outside HOI4". Emergent stories (your agents steal the enemy's new tank gun, you field it before they do). Cons: Loses strong authored historical grounding and player sense of "planning the exact tree"; can feel less directed for new players.

4. **Authored Core Tree + Agent-Driven National Projects Layer (Terra Invicta + Stellaris hybrid — RECOMMENDED BEST)**: Keep the rich authored tree we built (for 1890-1938 historical fidelity, concrete module/design/doctrine unlocks, alt-history branches with mut excl, era gating, player planning). On top, add a "National Projects" layer (node_kind: "project", long base_cost_days, often single or limited "R&D capacity" slots). These are the high-stakes "developments" (Synthetic Fuel Initiative, Carrier Aviation Program, Radar Defense Network, Heavy Breakthrough Armor, Combined Arms Reform). 

   - Projects unlock powerful or alt modules + designs + doctrine evolution.
   - **Agents are key**: Tech-skilled agents (or chiefs) can be assigned to lead/sponsor a project for speed bonuses or special outcomes. Enemy agents run steal_project (get the project unlocked for *their* country to start, plus some progress), sabotage (add massive delay + possible "leaked weakness" that gives enemy a counter mod or doctrine exploit), or plant mole (long-term hidden bonus or future compromise).
   - Doctrines tie in: Many doctrine evolution keys come from or are boosted by projects (e.g. combined_arms_reform_project). Service doctrine choice affects project costs/success (blitz nation gets bonus on mobile armor projects).
   - Modules depend on tech *and* projects (core tree gives basics; projects give the signature powerful/alt ones).
   - Tradeoffs & consequences are explicit and multi-layered (see the JSON prototype for "tradeoffs" object per project: benefits, costs, consequences like "successful enemy theft flips the advantage + exposes your plants"). Projects can fail or be compromised with real in-game effects (fuel crisis events, bigger org loss on doctrine change, detectable signatures for bombing).
   - Replayability: Core branches give structure, but which projects you prioritize + which agent ops succeed/fail + order of thefts create wildly different 1938-39 force mixes and weaknesses even on identical nations. Different factions/nations have natural affinities (cost reductions or bonuses on certain projects).

   Why this is best (and why not pure HOI4):
   - Directly addresses "agents are key and ... play a role in technology and developments", "doctrines tie in", "modules depend on technology".
   - Incorporates feedback from Stellaris (espionage steal tech with risk/reward + leader assignment) and especially Terra Invicta (private projects driven by councilors/agents, shared elements for competition, explicit component tradeoffs, theft of projects is core gameplay and creates consequences).
   - Not exactly HOI4: The project layer + heavy agent agency + explicit "tradeoffs object" + consequence hooks (leaks, crises, exploitation) make development feel like real R&D with spies, not just clicking a grid.
   - Tradeoffs matter: Every major choice (branch or project) has visible stats, agent exposure, lock-in costs (via doctrine change penalties), and exploitable surfaces. Choices have downstream consequences (your synthetic plants become prime agent/bomber targets; stolen carrier program lets enemy build CVs that counter your BB-heavy navy).
   - Replay + player agency: Authored tree gives reliable historical/alt-history scaffolding (players can still "I will do early synthetics then carrier alt"). Agent + project outcomes add the chaos and personal story that makes each campaign unique without feeling random. Greater than HOI4 because espionage success/failure is now a major variable in who has the tech edge.
   - Fits existing systems: We already have steal_research, compromised, stolen bank, agent_tech_summary in the UI, project-kind support in the schema, node unlocks. The new national_projects_1890_1938.json prototype (5 projects) auto-loads and demonstrates.

**Recommendation**: Go with Option 4 (Authored Tree + Projects). It is the sweet spot for this project: grounds the 1890-1938 era and alt-history the user wants, makes agents the active driver of "developments" (as emphasized), creates deep meaningful tradeoffs with consequences, boosts replay without losing player control, and is evolutionary (builds on the excellent current tree/UI/agent integration) rather than a full rewrite. We can iterate by expanding the project JSON, adding dedicated project slots or leader/agent assignment mechanics in TechnologyManager + UI, and wiring more agent mission outcomes (e.g. "steal_project" that grants the node to the actor).

Prototype data added: `data/technology/trees/national_projects_1890_1938.json` (synthetic, carrier, radar, heavy armor, combined arms reform — all with agent theft/sabotage hooks, explicit tradeoffs, and ties to modules/doctrines/designs). These will appear in the tech screen (as project nodes). Next steps if approved: wire project-specific ticking/assignment in manager, add "assign agent to project" in UI, expand steal_research or add steal_project outcome, update inspector to call out project risks.

This evolves us in the direction the user loves while staying true to "not exactly like HOI4" and making agents/doctrines/modules feel integrated with real stakes. 

Radio fix applied (names/flavors now clearly distinguish telegraphy vs voice radio vs radar). 

**In-game edit mode (added 2026-06):** `get_editable_tech_tree(country_tag)` returns core_nodes + custom_nodes + merged + country_progress (for UI/debug panels). `add_custom_tech(tech_id, node_data, for_country?)` injects alt-history/runtime nodes into technology_nodes/custom_tech_nodes (merged in editable view; research hooks via existing _apply). `edit_tech_progress(tag, id, delta, set_completed)`, `retool_tech_node(id, changes)`, `remove_custom_tech`. Customs + progress persist via SaveLoadManager (country_state + custom_tech_nodes in get/apply_save_data). Enables easy in-game tweaks without JSON edit. Ties to GameData epoch shifts (tech priority choice can trigger lag/unlock waves + edit hooks), agents (espionage on custom), Map (some future techs geo-gated via context). Hybrid with initiatives tree pattern.
Recent expansions (additive_manuf, consumer_electronics/vr, sonic/cb/bio, cloning/cyber/genetic, drones/scanners/shields/tele/phasers) now minimally wired (2026-06 subagent): see NMM/CombatResolver/GameData/Supply/TechManager for manpower_replacement, prod_flex, weapon flags in combat, recon/interdict, space bonuses, ethics amp. Balance via existing tradeoffs (ethics_risk, power draw, coh hits). No broad doc overhaul.

Ready for review and next implementation pass.

---

## Related docs

- [PRODUCTION_SYSTEM.md](../data/production/PRODUCTION_SYSTEM.md) — factories, shipyards, retooling.
- [UI_DESIGN_REFERENCE.md](UI_DESIGN_REFERENCE.md) — layered complexity, Retrowave.
- [LEADER_SYSTEM_DESIGN.md](LEADER_SYSTEM_DESIGN.md) — training paths / doctrine keys.
- Agent missions: `data/agents/mission_definitions.json` (technology category).

## Future: Ascendancy/tech geo impacts on world map combat (stub)
Per task: tie more to ascendancy tree geo (rivers/chunks/elev/coarse continents) for combat modifiers (e.g. tech "Naval Choke" boosts straits in BM naval; tree node gives non-Eur mtn assault bonus when holding elev chunk).
Implement via shared geo_mod in ProvinceInsight/BM context + NMM. AI target scoring can include geo-tech value. Stubs ready for parallel tree work. See MAP_SYSTEM_DESIGN, CURRENT_STATE, WORLD_CLASS_MAP_ROADMAP.

## 1945-1970 Early Space Race & Mech Expansion (added 2026-06)
- research_catalog.json: 26+ entries (v2_rocket, sputnik_satellite, human_spaceflight, moon_landing, moon_base, orbital_station, mars_probe, mars_base, mech_prototype, dieselpunk_mech, secret_space_program, ai_research, satellite_network, expanse_rocket, nuclear_thermal_engine, rocketry_foundations, mech_designer, ai_ethics, public_space_program, secret_funding_space + more). Areas: space/strategic/land. Costs 1.5-7 years.
- Trees: Extended strategic_future.json (now includes rocketry_foundations @1938 linking aircraft_industry_ii_1935; 15+ space/mech nodes era 1943-1970 with prereqs, unlocks for modifiers/recon/ascendancy/rule_flags like allow_satellites/secret_funding/allow_dieselpunk_mechs/mech_division; public_space_program vs secret_funding_space mutually_exclusive with secret_funding rule_flag + agent theft hooks). Appended covert_orbital_initiative to national_projects_1890_1938.json (secret_funding, 1945 era, black budget flavor).
- Units: Updated a4_v2_rocket.json, r7_sputnik.json, redstone_jupiter, saturn_v_apollo, gemini_spacecraft, gps_satellite, falcon9 etc unlock_tech to new ids (v2_rocket, sputnik_satellite, moon_landing, human_spaceflight, satellite_network). Added mech_division_proto + orbital_recon_asset to division_templates.json (referenced via division_template unlock).
- TM/Registry: Extended has_tech_unlock for "division_template" (checks deferred + new unlocked_division_templates), populate in registry, grant_temporary_rule_flag, state init/migrate. Diffusion/ethics via ai_ethics node + space_equipment domain. GameData.gd updated techs_for_ms + rule checks to honor our nodes (e.g. secret_funding, moon_landing etc) for space_race_competition/peace.
- Agents: Added fund_secret_space_program + steal_space_intel to mission_definitions.json. Wired in AgentManager.gd: filter availability on secret_funding rule_flag / v2/sputnik techs; _apply_secret_space_funding effect (boosts via apply_tech_intel_bonus scaled for secret, temp flag, scandal on detect). Ties black market / secret space to tech rule_flags.
- Assets: Coordinated res://assets/graphics/icons/space_race/* (steampunk_rocket.png, secret_space.png, moon_landing.png, mars_landing.png, space_station.png, moon_base.png, first_spaceflight.png) added as ui.icon to key nodes (v2, sputnik, secret, moon, orbital_station, mars etc).
- Save/load: Relies on existing country_state (rule_flags, deferred_unlocks, permanent_mods, unlocked_*), custom tech support; 50T tests use later (tech count now includes ~20 space/mech nodes).
- Usage: Research v2_rocket (post 1930s air) -> sputnik -> branches public (ascendancy/prestige) or secret (hidden recon, agent fund missions) -> moon_landing / mech_designer / ai etc. Unlocks space units (rockets/sats), mech divs, rule_flags for production/clandestine, recon/ascendancy mods. Secret paths synergize Agent black ops for funding; public for morale/Ascendancy.

Dieselpunk/steampunk alt branches via mech_designer + rocketry_foundations. Era_min 1938+ for precursors, 1945+ core. 10+ linked nodes completed.
