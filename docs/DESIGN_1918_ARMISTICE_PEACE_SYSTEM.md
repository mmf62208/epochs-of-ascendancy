# DESIGN: 1918 Armistice Peace Conference & Follow-on Influence System
**Epochs of Ascendancy**

**Status:** Design Complete — Phased Implementation ADVANCED (Phase 0/1/2 + 4/5 key pieces + save + harness + ripples + TestRunner sim; 2026-06-18 subagent work). Data, agents, resolution (spirits live), follow-ons, tech integration, save/load, UI harnesses, Diplomacy surfacing done via precise edits. Ready for 50+ turn integrated playtest. Map/AI/full later.
**Date:** 2026-06-11 (updated 2026-06-18)  
**Scope:** Opening 1918 Armistice negotiation sequence + multi-year follow-on decision/influence points (1919–1925 window). Deep integration with Agents (new diplomacy missions + "influence" skill leverage), Leaders, National Spirits, future Focus Trees, Technology availability, agent/leader pools, Diplomacy/Relations, and events. Strong support for historical fidelity with clear alt-history divergence, especially Central Powers gaining a seat at the table.

**User Drivers (direct from query):**
- Choices must ripple: events, technology trees, availability of agents/leaders, focus options.
- Agents are **key** for diplomacy — new missions with dedicated values/skills. Central Powers players must be able to exert "great effort" (bribes, concessions, honeypots influencing ministers, espionage on negotiations) to force inclusion and better terms.
- Full peace deal design for the Armistice.
- Real-life parallel: A few influence/decision points over the ensuing few years after the initial treaty.
- Systems first (events, focus/tech ripples, agents, diplomacy, peace mechanics). Map polish and AI deferred.
- Historical paths clearly marked; alt-history divergence rewarded with real mechanical weight but risk.

**Related Systems (leverage these patterns):**
- `scripts/core/ScenarioLoader.gd` (scenario_loaded signal, 1918-11-11 start_date already perfect).
- `scripts/autoload/TimeManager.gd` (game_year_advanced, game_day_advanced, game_month_advanced — primary hook for follow-on points).
- `scripts/agents/AgentManager.gd` + `Agent.gd` (influence skill already exists 0-10; assign_agent_to_mission; mission_definitions.json; signals; networks).
- `scripts/national/NationalSpiritManager.gd` + `spirit_definitions.json` + NationalModifierManager (permanent + temporary effects).
- `scripts/ui/DiplomacyView.gd` (explicit future extension points for opinion, diplomatic events, packages, relations — "Pulse" etc.).
- `scripts/ui/LeaderEventUI.gd` (toasts, popups — reuse for conference outcomes and follow-on news).
- `scripts/technology/TechnologyManager.gd` (unlocks, hidden_until, agent hooks — peace can gate or discount nodes).
- Leader traits/skills from `data/leaders/` and LeaderManager (Planning, Initiative, Charismatic, Political General, etc. for negotiation weight).
- `data/national/spirit_definitions.json` (model for new peace spirits).
- Existing mission outcome/impact helpers (`AgentMissionImpact.gd`).
- Hidden Hand design (can react to treaty instability or use the chaos).

**Non-Goals (per user):** Full AI opponent logic for conference choices (weights only for later); deep map changes during initial implementation (systems first); full focus tree implementation yet (but design hooks and placeholder gating for when we build it).

---

## 1. Design Principles (Anti-HOI4 "Flip" Lessons + User Vision)

1. **Player Agency & Counterplay Everywhere**: No sudden "the treaty just happened this way." Every major outcome has visible levers (agent missions before/during, delegation selection, term choices, follow-on responses). Prevention, mitigation, and exploitation are first-class.
2. **Transparency + Visibility**: Tooltips, inspectors, "Pulse"/relations summaries, mission previews, and outcome logs always explain *why* a result occurred and what influenced it (delegation skills, prior agent ops, chosen terms, hidden intel the player may or may not have).
3. **Historical Clearly Marked, Alt-History Real & Costly**: Every term, branch, and follow-on decision has an explicit "HISTORICAL" badge or flag. Historical path is the "default gravity" (especially useful for AI "historical experience" mode). Alt-history requires real investment (agents, leaders, prestige/stability costs, risk of backlash) and produces different downstream content (different focus branches, tech availability, agent/leader pools, event chains).
4. **Ripple Effects Are First-Class**: Conference + follow-on choices directly affect:
   - National Spirits (permanent or long-duration treaty spirits).
   - Technology tree availability/gating/costs (e.g. military tech restrictions or early unlocks).
   - Future Focus Tree options (when built: revanchism vs. reconciliation branches, "Weimar stabilization" vs. "radical path", Turkish "Kemalist success" variants).
   - Agent recruitment pools and leader availability (disillusioned officers, rising radicals, moderate diplomats, purged figures return or are removed).
   - Relations, opinion, trade access, Hidden Hand influence.
   - Event triggers and weighting for the next 5–7 years.
5. **Central Powers Agency**: A player (or influenced AI) playing GER, TUR, or successor states can invest heavily pre-conference and during to force a seat, soften terms, or create post-treaty leverage. Cost is high (risk of exposure, prestige loss if failed spectacularly, possible Entente hardening). Success feels earned and changes the game.
6. **Symmetric Core + Tunable Historical Weight**: Core rules (mission success, term effects, follow-on triggers) are the same for player and AI. Historical bias is an explicit tunable weight (global or per-nation "adherence" scalar) rather than invisible cheats.
7. **Multi-Year Narrative Arc**: The initial conference is only the opening. 4–7 meaningful influence/decision points over the ensuing years keep the peace settlement alive as a living constraint or opportunity rather than a one-time event.

---

## 2. High-Level Flow

**1918 Start (Armistice Day, 1918-11-11 or a few days prior)**:
- Scenario loads normally (ScenarioLoader already sets the date).
- For 1918 scenarios: Trigger "Armistice & Peace Conference" sequence (can be a special full-screen or large popup window, or integrated into a new "Diplomacy / Peace" tab).
- Optional **Pre-Conference Phase** (especially valuable for Central Powers players): Short window (days/weeks simulated via one or two TimeManager advances or a dedicated "conference prep" mode) where agents can run high-stakes diplomacy/influence missions against target ministers, delegations, or public opinion. Success grants "leverage" tokens or direct modifiers to the main conference.

**Main Conference (Player-Facing Choice Moment)**:
- **Delegation Selection**: Choose 3–5 representatives from your current leaders + available agents. Each contributes based on skills (heavy weight on **influence** for agents; Planning/Initiative/Charismatic/Political traits for leaders) and specific role fit.
- **Term Selection**: Structured choices across 6–8 major buckets. Every option shows "HISTORICAL" badge where applicable. Mechanical preview of likely effects.
- **Resolution**: Modifiers from delegation quality + pre-conference leverage + any secret intel the player gathered + a visible but influenced roll. Player sees breakdown. Outcomes applied immediately.
- **Summary & Ripples**: Big outcome screen + toasts. Apply spirits, adjust relations, fire tech/focus hooks, possibly spawn immediate follow-on events or change agent/leader pools. Game then proceeds normally.

**Follow-on Influence & Decision Points (1919–1925 window)**:
- Driven primarily by `TimeManager.game_year_advanced` (and some monthly/day checks for urgency).
- Each point is a combination of:
  - Automatic "the situation is deteriorating" event with context from prior peace state.
  - Player (and AI) response options via: National Focus (future), Agent missions (ongoing influence/sabotage of enforcement), Leader assignments (special envoys or domestic crisis managers), direct policy choices in a Diplomacy or National Overview screen, or trade/economic deals.
- Outcomes continue to ripple (new or modified spirits, tech gates lifted or imposed, focus branches, agent events, possible limited map claims or stability shocks).
- Historical baseline always labeled; alt-history paths branch from prior choices (e.g. "because you secured a seat + lenient terms, the 1923 crisis is milder and opens a 'Democratic Consolidation' focus path instead of radical revanchism").

**State Tracking**:
- Lightweight `PeaceState` (or stored in GameData / per-country in NationalModifierManager or a new small `PeaceConferenceManager` autoload).
- Key fields: `conference_outcome_id` (or set of term choices), `central_powers_inclusion_level` (0=historical exclusion, 1=observers, 2=limited voice, 3=full participants), `reparations_severity`, `league_strength`, accumulated "leverage" or "grievance" counters, list of applied treaty spirits.
- This state is the primary gate/weight for future events, focus nodes, and tech hidden_until.

---

## 3. The Peace Conference — Detailed Terms & Mechanics

### 3.1 Delegation Selection (Agents + Leaders)
UI modeled after LeaderAssignmentScreen + AgentAssignmentScreen + MissionPickerPopup.

- Pool: All available (not on mission, not captured) agents for the country + relevant leaders (statesmen, diplomats, high-Planning generals/admirals who can be pulled from field commands at a cost).
- Each slot has a role (Lead Negotiator, Economic Terms, Military Restrictions, Political/Legal, Public Narrative).
- Scoring (visible in tooltip or preview):
  - Agents: Primary = `influence` skill. Secondary bonuses from `intelligence` (for reading the room), level, specific traits, prior successful influence missions.
  - Leaders: High Planning / Initiative / Charismatic / "Political General" / "Visionary" give strong bonuses. Some negative traits (Arrogant, Political Liability) penalize or add risk.
  - Synergies: Certain leader + agent pairs give extra "trusted team" bonus.
- Cost: Committing top people has opportunity cost (they are unavailable for other assignments during the short conference window). Prestige/stability hit if you send weak delegation and fail badly.
- Central Powers special: Limited high-quality agents/leaders at start (many discredited or in exile); success in pre-conference missions can "unlock" or improve specific negotiators.

**New/Extended Agent Skill Use**: "influence" is now explicitly a diplomacy powerhouse (already present in Agent.gd). Conference missions and term negotiations weight it heavily.

### 3.2 Term Buckets (with Historical Markers & Effects)

Present as cards or a clean list with "Apply Historical Preset" button (clearly labeled) for players who want the classic experience.

**Bucket 1: Treatment of Central Powers at the Table (The Big Divergence)**
- HISTORICAL — Full Exclusion (Germany, Austria-Hungary, Ottoman Empire dictated to; no substantive voice): High grievance for defeated. Strong revanchism seeds. Lower immediate stability hit for Entente winners.
- Limited Observers: Small voice on non-core issues. Medium reduction in long-term grievance.
- Full Participants (hard alt-history): Real negotiation. Much lower revanchism, possible earlier reconciliation paths, but Entente domestic backlash ("we won the war but lost the peace") and possible Hidden Hand exploitation of the "weakness."
- **How Central Powers force this**: Pre-conference agent missions ("Secure Inclusion", "Bribe Influential Minister", "Honeypot Operation" on key Entente figure, "Leak Negotiating Red Lines" to create public pressure). Success builds "Inclusion Leverage" that shifts the available options or adds heavy modifiers to the resolution roll. Failure can harden Entente positions or trigger scandals.

**Bucket 2: Reparations (Germany-centric)**
- HISTORICAL — Harsh (full liability, high annual payments, in-kind coal/iron deliveries): Classic Versailles. High German grievance, economic pain, seeds for hyperinflation crisis later.
- Moderate: Reduced total + longer timeline.
- Lenient / Reconstruction-Focused: Low total or tied to productive investment. Much better for long-term German stability and Entente trade, but winner backlash.

**Bucket 3: Territorial & Colonial Adjustments**
- HISTORICAL maps (Alsace-Lorraine, Polish Corridor, mandates in Middle East/Africa, etc.).
- Alt variants: More generous to losers on some frontiers (reduces cores/claims), or harsher (more instability).

**Bucket 4: Military Restrictions & Disarmament**
- HISTORICAL strict limits on German army/navy/air, demilitarized zones, etc.
- Softer limits or inspection regimes.
- Effect: Directly gates or discounts early interwar military tech nodes and unit templates for affected nations. Can be renegotiated in follow-on crises.

**Bucket 5: League of Nations / International Order**
- HISTORICAL — Weak League (US non-participation modeled, limited enforcement): Low effectiveness.
- Stronger Structure: Higher "international order" modifier, more tools for later crises (or more ways for players to subvert it).
- Alt: Regional security pacts instead (or in addition).

**Bucket 6–8**: Economic integration clauses, War guilt language (symbolic but affects prestige and domestic events), Treatment of Austria-Hungary / Ottoman partition details (successor state stability, oil concessions, mandate harshness).

**Resolution Modifiers** (transparent):
- Delegation quality (sum of relevant skills + role fit + level).
- Pre-conference leverage from agents.
- Player term choices (harsh terms give bonus "victory" prestige/stability for winners but massive grievance for losers).
- Any secret negotiations or compromised ministers discovered via prior missions.
- Base historical gravity (can be overcome with high investment).
- Outcome = visible success tiers (Crushing Victory for winners / Humiliating Diktat for losers, Compromise, etc.).

**Immediate Application**:
- Add/override national spirits (e.g. "versailles_humiliation", "winners_burden", "inclusion_at_table", "fragile_peace").
- Adjust relations/opinion (DiplomacyView surfaces this).
- Fire TechnologyManager hooks (lock certain nodes behind "treaty_restrictions" or unlock "rearmament_focus" paths earlier for aggrieved powers).
- Modify agent/leader pools (new recruitment events or retirements).
- Set PeaceState flags that future events and (future) focus nodes read.
- Possible small map effects (cores, claims, or special site control) for high-drama divergence.

---

## 4. Follow-on Decision & Influence Points (Ensuing Years)

These keep the peace settlement as a living system. Triggered mostly on `game_year_advanced`. Each has:
- Context derived from prior peace state (e.g. high grievance + harsh reparations makes crisis more likely/severe).
- Player response levers (agents, leaders, policy choice, future focus).
- HISTORICAL baseline + 2–3 alt branches.
- Ripples to spirits, tech, agents/leaders, events.

**Point 1: 1919 — Treaty Ratification & Initial Enforcement**
- Historical: Bitter debates, some Entente hesitation, early German non-compliance signals.
- Player levers: Agent influence on ratification votes or domestic opinion in key capitals; leader assignments to "enforcement commissions."
- Branches: Smooth ratification (historical-ish) vs. delayed/weak enforcement (opens early revisionist opportunities) vs. aggressive early enforcement (higher short-term stability for winners, higher long-term grievance).

**Point 2: 1920–1921 — First Reparations Schedule & Compliance Crisis**
- Historical: Germany struggles, payments in kind, early political radicalization.
- Levers: Agent economic sabotage or support networks; trade deals that ease or weaponize the burden; leader economic advisors.
- Alt: Successful restructuring (if prior terms were moderate + good delegation) → earlier recovery, different focus options. Or radical non-payment + Entente occupation threats.

**Point 3: 1923 — Ruhr / Sanctions / Occupation Crisis (The Big One)**
- Historical: French/Belgian occupation of Ruhr after default; German passive resistance; hyperinflation spike.
- Levers: Heavy agent activity (support resistance networks, international propaganda, honeypots on occupation commanders, economic intelligence to time responses). Leader "crisis manager" assignments. Prior peace choices dramatically change severity (lenient terms or inclusion → much milder or different crisis).
- Branches:
  - Historical harsh path → hyperinflation, political chaos, "stab in the back" myth strengthening, radical leaders/agents become more available or dangerous.
  - Successful negotiation/stabilization (high prior investment) → Dawes-like plan earlier, democratic consolidation path opens in focus trees.
  - Escalation to broader conflict risk (if players push hard).

**Point 4: 1924 — Economic Stabilization / Foreign Loan Package (Dawes Analog)**
- Decision point on accepting international loans/aid with strings (or alt: radical autarky, or Soviet-style alternatives if relations allow).
- Ripples: Tech/industrial recovery speed, future focus availability ("internationalist" vs "autarkic" branches), agent opportunities in finance (black market or legitimate).

**Point 5: Ottoman / Middle East Settlement Follow-ups (1919–1923 window)**
- Turkish National Movement success level, different mandate outcomes, oil politics.
- Central Powers (Turkish) player who fought for a seat or better terms has real advantages here. Agent ops in Anatolia, Syria, etc. Agent "influence" missions on local leaders or Entente commissioners.
- Alt-history: Stronger Turkish republic earlier, different borders, or prolonged partition chaos.

**Point 6: League Credibility Test or Alternative Pacts (mid-1920s)**
- A crisis (disarmament violation, border incident, or manufactured) tests whether the League (or whatever structure the peace created) can act.
- Player can use agents to shape the narrative, leak intel, or sabotage enforcement.

**Point 7: Domestic Political Realignment in Defeated / Victor Powers (ongoing but spikes on anniversaries or crises)**
- Germany: Rise of revanchist figures or moderate consolidation (heavily weighted by prior inclusion + reparations severity).
- Similar for other powers.
- Effect: Changes available leaders for recruitment, agent loyalty/events, focus tree weighting.

**Implementation Note for Follow-ons**: Store a small `peace_influence_state` dict per relevant country. Events check prior term choices + current agent networks + leader assignments + national modifier state. Use the same mission completion + TimeManager signals pattern already proven for agents/tech.

---

## 5. Data Models & Extensions

### 5.1 New/Extended Agent Missions (Add to `data/agents/mission_definitions.json`)
New category: `"diplomacy"` (or `"conference_influence"` for 1918-specific).

Examples to add (full JSON entries in implementation):
- `secure_inclusion`: High-stakes, targets key Entente capitals. Heavy `influence` req. Success builds "Inclusion Leverage". High detection risk. Honeypot flavor in description.
- `bribe_influential_minister`: Direct corruption. `influence` primary. Temporary or one-shot bonus to term resolution.
- `honeypot_operation`: Target specific historical or plausible minister/delegate. High reward if successful, scandal/backlash on failure or detection.
- `shape_public_narrative`: Propaganda/influence on home front or international press re: "fair peace" or "harsh diktat".
- `leak_negotiating_position`: Intelligence + influence hybrid. Creates pressure or bargaining chips.
- `counter_conference_influence`: Defensive mission (counter-intel flavor) when you suspect enemy agents are working the same targets.
- `economic_leverage_negotiations`: Tie trade/black market ops into conference (links to existing TradeManager).
- `long_term_treaty_intel`: Embed for follow-on points (multi-year passive bonus).

Missions can be "conference_window" only (time-limited) or permanent-style. Use existing `assign_agent_to_mission` + outcome handling. Extend `AgentMissionImpact.gd` for new effect labels (e.g. "inclusion_leverage", "grievance_reduction", "minister_compromised").

Agent `influence` skill becomes a star for these (as user requested "give each their own values").

### 5.2 Peace Terms & Outcomes Data
Recommend `data/peace/1918_peace_terms.json` (or a section in a broader events/peace file).

Structure sketch:
```json
{
  "conference_id": "1918_armistice",
  "term_buckets": {
    "central_powers_seating": {
      "historical": { "id": "full_exclusion", "label": "HISTORICAL — Full Exclusion", "grievance": { "GER": 45, ... }, "entente_prestige": 15, ... },
      "alt_full_participants": { ... }
    },
    ...
  },
  "resolution_modifiers": { ... },
  "outcome_templates": [ ... ]
}
```

### 5.3 National Spirits / Modifiers
Extend `data/national/spirit_definitions.json` (or add a `peace_treaty_spirits.json` loaded similarly) with new entries like:
- `versailles_humiliation` (GER, high grievance, production/stability penalties, revanchism event weighting).
- `inclusion_at_the_table` (for Central Powers who succeeded — positive stability + different focus access, but possible winner resentment).
- `winners_burden`, `fragile_victory`, `league_optimism`, `reparations_strain`, etc.

Dynamic application: Extend `NationalSpiritManager` with `apply_peace_spirit(country, spirit_id, duration_months_or_permanent)` or route major ones through NationalModifierManager (already supports temporary effects with source tracking). PeaceState records which ones are active so they can be referenced for follow-on logic.

### 5.4 Peace State & Ripple Hooks
Lightweight manager or data in GameData:
- Current conference outcome summary.
- Term choice record (for weighting future events).
- Accumulated grievance / leverage counters.
- "Treaty revision progress" or similar for alt-history paths.

Hooks:
- TechnologyManager: New unlock type or `hidden_until: { "requires_peace_outcome": "inclusion_or_lenient" }` style (or simple function checks).
- Future FocusTree: Nodes can have `requires_peace_decision` or `blocked_by_peace_decision`.
- Agent/Leader generation: Peace outcomes can bias the generator (e.g. more "revanchist" traited leaders available after harsh treaty).
- Event system (when built): PeaceState is a first-class condition.

---

## 6. UI & Player Experience

- New `PeaceConferenceScreen.gd` / .tscn (or large Window). Follow Retrowave patterns from TechnologyScreen, DiplomacyView, LeaderAssignmentScreen.
- Sections: Pre-Conference Ops (if any active), Delegation Picker (multi-select with scoring preview), Term Chooser (cards with HISTORICAL badges + mechanical preview), Resolution (animated or clear breakdown), Outcome Summary (spirits gained, ripples, news feed).
- Surface ongoing treaty status in DiplomacyView (new "Treaty Status" or "Post-Armistice" section with Pulse, active grievances, upcoming decision points).
- Toasts via LeaderEventUI for major follow-on events ("Reparations Crisis Deepens", "Agent Network Influences Key Minister").
- Tooltips everywhere explaining historical vs. your divergence.

**Accessibility for Historical Players**: Big "Apply Full Historical Preset" button at conference + later "Follow Historical Path" options on follow-on decisions (with warning that this reduces your agency for replay value).

---

## 7. Phased Implementation Order (Build in Sequence)

**Implementation Progress Note (June 2026 subagent, read-write autonomous, parallel focus on peace):** 
Phases 0 (data models: 1918_peace_terms.json expanded to 7 buckets with historical markers + effects; spirits already 6+ core; missions pre-added ~8 diplomacy), 1 (Agent & Outcome: full handlers in AgentManager for all new effects + conference_window_only respect in get_eligible; AgentMissionImpact updated; pre-conference leverage sim via GameData/handlers), 2 (Conference Trigger & Basic UI: largely pre-complete + advanced: PeaceConferenceWindow with new buckets/pre-sim button + dialogue; harness in DebugOverlay + TestRunner; ScenarioLoader hook; applicator now calls real NSM spirits), 3-4 (pre + follow-on: expanded process_peace_follow_ons with 1920/21/24 + more context from prior terms/leverage; 1923 crisis already wired to dialogue), 5 (ripples: new NSM apply_treaty_spirit + remove for dynamic; TechnologyManager can_research gates + cost multipliers based on peace_state seating/grievance/leverage for historical costly vs alt-history discounts; DiplomacyView now surfaces live treaty status). 
Critical: full core peace_state (conference, leverage, grievance, terms, notes, modifiers, crisis, pillars) now in save/load + clear_for_load for 50+ turn. 
Harness/demo: preconf leverage button (Debug + PeaceWin), full 1918 sim cycle in TestRunner (seed Central Powers leverage, resolve alt terms, trigger followons 19/23/24, check spirits/NSM, logs). 
Validation prep: headless will emit PEACE SIM, FOLLOW-ON, "Applied treaty spirit", "PeaceState:", tech gate logs etc. No crashes on paths. 
Docs updated (CURRENT, TODO, this). Precise edits only. 
See CURRENT_STATE for full table.

**Phase 0 — Design & Data Foundation (Now)**
- This document.
- Create `data/peace/` dir + starter `1918_peace_terms.json` (minimal viable buckets + one full outcome set).
- Extend `data/agents/mission_definitions.json` with 5–7 new diplomacy missions (full entries with outcomes, skill reqs on "influence").
- Extend `spirit_definitions.json` with 6–8 core peace treaty spirits.
- Update any schemas/docs if needed.

**Phase 1 — Agent & Outcome Core (Low Risk, High Leverage)**
- Extend `AgentManager.gd` minimally: Support new "diplomacy" category in `get_mission_categories()`, special handling or generic outcome application for new effects (`inclusion_leverage`, `grievance_modifier`, `minister_compromised`, `narrative_shift`).
- Update `AgentMissionImpact.gd` with new formatters.
- Create lightweight `PeaceOutcomeApplicator` (or methods on NationalSpiritManager + NationalModifierManager) that can apply spirits, set PeaceState, fire Technology hooks, adjust relations (via TradeManager/DiplomacyView patterns).
- Basic PeaceState storage (dictionary on GameData or new autoload stub).
- Test via debug commands or headless: recruit agent, run new mission, apply sample outcome.

**Phase 2 — Conference Trigger & Basic UI** (largely complete)
- Hook in `ScenarioLoader.gd` (after `scenario_loaded.emit()`) for 1918 scenarios — primes peace systems and prints guidance. Auto-open of the full window is available via F10 or manual instantiation for testing.
- PeaceConferenceWindow (code-built, `scripts/ui/PeaceConferenceWindow.gd`): Shows player + real-time agent leverage, term buckets with HISTORICAL badges, and a prominent "Use Real Dialogue for Central Powers Seating (Dialogue Manager sample)" button.
- Real wired samples:
  - `data/peace/1918_central_powers_seating.dialogue` (conference term choice, launched from PeaceConferenceWindow).
  - `data/peace/1923_crisis.dialogue` (major follow-on crisis). When the phases demo advances to 1923 (or follow-on processor hits it), `GameData.start_1923_crisis_dialogue(...)` is called. The dialogue reads previous_terms and leverage, offers HISTORICAL harsh repression vs. negotiate/stabilize vs. exploit vs. agent leverage paths, and uses `do GameData.record_crisis_response(...)` + `add_grievance(...)` to drive state. The phases demo then reflects the chosen response in the "current phase" label and can lead to continuation triggers.
- Both use the example_balloon from the installed Dialogue Manager plugin and pass GameData + context so do-lines mutate the authoritative peace_state.
- Resolve button calls the full applicator (spirits/modifiers via NMM, grievance, pending_continuation for historical empire paths like Ottoman).
- After resolution, a button opens the phases demo directly.
- Treaty status can be surfaced in DiplomacyView (extension point already documented).

**Phase 3 — Pre-Conference Levers & Polish**
- Wire short pre-conference window (one or two TimeManager day advances or a dedicated "prep mode" flag).
- Make high-stakes diplomacy missions available and impactful on the main conference modifiers.
- Add previews, tooltips, HISTORICAL badges, cost warnings.
- Leader delegation costs/opportunity (temporary unavailability or prestige hit).

**Phase 4 — Follow-on Points (Multi-Year)**
- Add listener in a new small `PeaceEventCoordinator` (or directly in a future EventManager, or even a section in AgentManager/Technology for now) to `TimeManager.game_year_advanced`.
- Implement 3–4 concrete points first (e.g. 1919 ratification, 1921 reparations, 1923 Ruhr crisis, 1924 stabilization).
- Each point: Condition check against PeaceState, generate event popup or notification with choices, agent mission eligibility spikes, leader assignment opportunities, outcome application (spirits, tech gates, pool changes).
- Make at least one point dramatically different based on whether Central Powers gained a seat.

**Phase 5 — Ripple Integration & Future-Proofing**
- TechnologyManager: Add concrete gates or discounts based on peace state (e.g. certain 1919–1925 German aviation/armor nodes locked or more expensive unless alt-history path taken).
- Prepare clean interfaces for when Focus Trees are implemented (`requires_peace_decision`, `historical_weight` on nodes).
- Extend DiplomacyView with "Treaty" tab/section showing active terms, upcoming decision windows, and quick-launch for relevant agent missions.
- Add to save/load (PeaceState must persist).
- Historical preset buttons + "this is the historical path" labeling everywhere.
- Basic telemetry/logging of divergence for playtest review.

**Phase 6 — Content Expansion & Balance**
- Fill all term buckets with rich historical/alt options.
- Add more follow-on points and cross-links (e.g. Middle East settlement interacts with reparations willingness).
- Agent/leader pool mutation events.
- Hidden Hand reactions.
- UI polish, sound hooks (later), more flavor text.

**Later (after systems solid)**: AI decision-making for conference/follow-ons (use the same levers the player has, with historical bias scalar). Map consequences from major divergences. Full focus tree realization of the branches.

---

## 8. Open Questions & Risks (for Discussion)

- Exact number of delegation slots and how "roles" map to term buckets (can be lightweight at first — just overall delegation quality score).
- How visible should the resolution "roll" be? (Recommended: fully visible breakdown with a small random element the player can see and have influenced.)
- Duration of conference window (MVP: effectively one decision point on load or first pause; later can stretch over simulated days with ongoing agent actions).
- Should Central Powers players get a parallel "shadow conference" or resistance planning screen while the main one happens?
- Storage of full term history vs. summary flags (prefer summary + key scalars for performance/readability).
- Interaction with 1936/2026 starts (no-op or very light "legacy grievances" for flavor).

---

## 9. Testing & Validation Path (Systems-First, Map Later)

- Headless + manual on 1918 scenario load.
- Play as USA/ENG/FRA: Choose historical preset → observe spirits, tech restrictions, later 1923 crisis severity.
- Play as GER: Heavy pre-conference agent investment (multiple influence agents on key targets) → attempt to force observers or full seat → measure difference in grievance, available leaders/agents post-conference, milder or transformed 1923 point.
- Verify no "flip": Every major outcome has at least two clear player-controllable vectors (delegation + at least one agent mission or prior choice).
- Ripple checks: After harsh historical treaty, confirm certain tech nodes are gated or more expensive; after successful inclusion, confirm alt focus seeds or agent recruitment events fire.
- Save/load roundtrip of PeaceState and applied spirits.
- Multiple playthroughs with different term mixes to validate branching.

---

**This design directly implements your request**: Full peace deal with initial conference choice (agents + leaders as negotiators, term selection with historical marking), Central Powers "great effort" via agents (bribes, honeypots, concessions, influence ops), ripples to events/tech/focus/agent-leader availability, and several real multi-year decision points modeled on history but fully branchable.

**Next immediate actions (in order)**:
1. (Done in prior + this subagent pass) Data, core agent/UI/resolution, save, followon, ripples, harness, TestRunner 1918 sim, doc notes.
2. Playtest: run headless TestScenario (will exercise 1918 cycle + peace prints); F5 graphical + F10 "Sim Pre-Conference..." then "Open 1918 Peace..." + resolve with pre btn or dialogue; advance time years (time speed) to fire 1919/23/24; check spirits in National Spirits screen, tech costs/gates for GER, Diplomacy treaty panel, grievances.
3. Polish gaps: load full terms from 1918_peace_terms.json in window (instead of hardcoded), more successor/empire handling, agent pool bias on harsh (new leaders/agents), Hidden Hand reactions to treaty instability, save roundtrip explicit test.
4. Parallel integration: wire more to econ (reparations on production), combat if fits, Ascendancy Initiatives branches conditional on peace_state.
5. User: choose next sub focus or full 50+ run feedback.

Ready when you are. Let's build this system properly before circling back to the map. This will make the 1918 start feel like a real, consequential campaign opener with years of meaningful aftermath.

---

## 10. Ascendancy Initiatives Tree, Golden Age Specials, Macro Culture & Immigration Sandbox (June 2026 Deep Dive)

**User decision (verbatim context)**: "Do we consider leaving off allocation and just label it National Vision when you go in and see something like a national skill tree players will know that they are allocating points to it. Ascendancy initiatives is a strong contender and i'm open to it, lets go with Ascendancy Initiatives do you think this could cause confusion with the other ascendancy tracker? that is one concern I have. I'm open still lets do a little further deep dive i just feel like not all of the focus items will necessarily lead directly to a golden age but they can contribute to it. Many of the options can be for alternate history, or for special events, big decisions, culture, where you want to take your nation. Lets start to discuss the big overarching dynamic choices that will live in this tree of Ascendancy initiatives or whatever we name it. Lets look at all other grand strategies and look at our principles and find between fun and games how we can create a fun and powerful system sandbox for player agency that will work. Maybe there can be special focus's available when your nation is in a golden age named Golden age initiatives, highly specialized items only available when certain levels of ascendancy are unlocked, perhaps this is a part of the fun of the resource, industry, etc game fun with culture, cohesion etc. Also should we model large differences in culture i dont mean every culture in the world but African culture, muslim, western civilization etc... perhaps we model just larger cultures, something to consider as it causes cohesion problems bringing in foreign workers helps you get cheap goods quick cheap labor but hurts in jobs for citizens lowers cohesion increases crime and undermines your nation, how do we model this? Continue with your next best items lets continue growing and building and discussing and updating"

**Adopted name**: Ascendancy Initiatives (user: "lets go with").

**Naming confusion concern (with Ascendancy pillar/tracker)**: Real but manageable and thematically strong.
- The pillar "Ascendancy" (momentum/prestige/political capital, 0-100, drives agent quality perks + Golden trigger) is the *resource/stat*.
- The tree/panel is "Ascendancy Initiatives" — proactive national direction projects and policy branches you *launch/spend/allocate Ascendancy into*.
- UI mitigation (recommended exact language):
  - Meter/header: "Ascendancy: 78/100 (Momentum & National Will)"
  - Tree title: "Ascendancy Initiatives — Shape Your Nation's Future"
  - Subtitle/tooltip on first open or hover: "Spend or allocate Ascendancy points to launch major initiatives. These are your national skill-tree / focus choices. High Ascendancy (90+) and Golden Age unlock highly specialized powerful options. Not every initiative is a straight line to Golden Age — many exist for alt-history divergence, cultural identity, economic models, crisis response, and long-term character."
  - In allocation preview (when we have the tree UI): "This initiative costs 12 Ascendancy (current 78 → 66). Agent Vision sponsorship can reduce cost or raise success."
  - Golden lock callout: "Golden Age Initiative — Requires Ascendancy 90+ or active Golden Age (triggered by sustained high Ascendancy + supporting economy/culture choices)."
- Why the name wins despite minor overlap: It makes the stat *feel* like a resource you actively use (like Stellaris Influence or EU4 Monarch Points spent on ideas/missions) rather than a passive score. Players opening a "national skill tree" will immediately understand they are directing points. "National Vision" was considered but felt too generic and lost the direct pillar synergy. "Ascendancy Directives" or "National Initiatives (Ascendancy)" are fallbacks if playtest shows persistent confusion.

**Core principles for the system (drawn from our pillars + anti-HOI4 lessons + user drivers)**:
- Player agency to break history/norms (Sun Tzu spirit): Post-1918 Central Powers player (or any underdog) can pursue reconciliation + cultural revival, rapid guest-labor industrialization, pan-identity experiments, or revanchist industrial centralization — and have the mechanics *respect* the choice with visible short/long effects instead of railroading back to 1939/1945.
- No sudden flips or unfair AI: Every major branch has levers (prior pillar state, agent Vision allocation, peace term history, current Cohesion groups). Historical path is always clearly marked and AI-weighted, but player investment can overcome it at real cost/risk.
- Ebb and flow, no death spirals: Floors exist. Low Ascendancy + low public Cohesion opens "crisis welfare" or "foreign model adoption" paths (failed state pressure). High investment in culture/industry initiatives + agent wins can recover (France 1918-1929 or 1940-1955 fantasy).
- Trade-offs are first-class and visible: Cheap labor today (industrial_base + short public happiness from goods) = citizen job pressure + crime + cultural friction tomorrow = public Cohesion drain + Hidden Hand opportunity + higher separatism risk. Elite Cohesion may rise (profits) while public falls — this split is deliberate for narrative/Hidden Hand depth.
- Agents are central fuel: Allocate agents to "Vision" category to sponsor/speed/secretly unlock hidden alt-history versions of initiatives. Trade-offs with Tech/Intel/Diplomacy/Trade assignments are real.
- Pillars integration is the fun: Initiatives shift Ascendancy (primary cost), Cohesion groups (public/elite/institutional differentially), Mandate, industrial_base, and military_allocation %. Golden Age (maxing Ascendancy) is the visible "I built something" payoff with surges + exclusive specials.
- Dynamic availability over rigid trees: What you see depends on current pillars, prior peace choices (harsh 1918 exclusion surfaces "alt_history_reconciliation"), low public Cohesion (crisis/assimilation options), high Ascendancy (projection + Golden previews), culture situation. Replayability explodes.
- Golden Age Initiatives as the "resource game" reward: Highly specialized, only at 90+ or during Golden. Not "more of the same" — these feel like rare civilizational peaks (renaissance, tech vanguard, hegemonic soft power, productivity miracle). They can convert prior painful choices (e.g. open immigration + later Golden renaissance turns the demographic wave into a strength).

**Inspirations from other grand strategies + how we differentiate for fun**:
- HOI4 national focuses: Branching alt-history, timed/requirement gates, national spirits as effects. We keep the spirit but add pillar costs, agent sponsorship, dynamic (not just date/tech) availability, and explicit Golden gated tier. No "just click the tree in isolation".
- EU4 mission trees + idea groups + estates: Culture/religion/estates drive internal power (our Cohesion groups map beautifully to estates with public = lower strata + loyalty, elite = upper + burghers, institutional = clergy + military). Expansion has overextension/cohesion costs. We make immigration a first-class "idea + mission" hybrid.
- Victoria 3 laws + interest groups + migration/pops: The gold standard for culture/immigration trade-offs (standard of living, qualifications, radicalization, mortality, migration attraction/attrition). We simplify to macro spheres + 3 Cohesion groups + explicit short/long + Hidden Hand exploitation so it stays playable in a grand strategy with agents/war rather than pure pop sim. Laws can be modeled as specific Initiatives that also gate other options.
- Stellaris traditions + ascension perks + ethics/civics: "High level" (Ascendancy) unlocks powerful unique perks. Golden Age Initiatives are our ascension tier — rare, transformative, thematic. Ethics clashes = our cultural distance/affinity.
- Overall synthesis for our game: The Initiatives tree is the place where resource/industry/culture/cohesion fun collides with big narrative choices. It is the primary long-term "what kind of nation are you building?" lever that interacts with every other pillar and the peace/victory systems.

**Big overarching dynamic choice categories (the actual content that will live in the tree)**:
These are not exhaustive linear progress. They are thematic branches. Combinations matter. Some are cheap early, some gated, some only make sense after a harsh peace or during a Golden. Many contribute to Golden eligibility indirectly (by growing Ascendancy or protecting Cohesion so you can sustain high levels) without being "Golden progress bars".

1. **Cultural & Demographic Direction (core to user request — immigration/identity)**  
   - Open Western / Skilled Sinic / African guest wave / Islamic guest worker (different scales, different affinity penalties, different elite vs public splits).  
   - Assimilation focus (spends Ascendancy, recovers public/institutional, partial conversion — "we turn them into us").  
   - Homogeneous restriction (protect public Cohesion and jobs, slower industrial growth — good for high-trust Golden pushes or nations recovering from riots/food/rights low public).  
   - Pan-identity or "melting pot experiment" alt-history (post-1918 only or high Mandate cost).  
   - Effects: industrial_base swing, public Cohesion (main pain), elite (often gain), institutional (crime load), Hidden Hand public erosion, future separatism risk, Golden culture specials eligibility, integration resistance in victory (cultural_distance already in calc uses this).

2. **Industrial & Economic Models**  
   - Fordism / mass production standardization (industrial_base +, military alloc flexibility, short public Cohesion cost from labor discipline).  
   - Autarky vs global trade openness (Mandate vs self-reliance; interacts with cheap exports deal).  
   - Planned heavy industry vs consumer/light (different allocation, Cohesion group reactions).  
   - Post-crisis reconstruction priority (unlocks after 1923 harsh path).

3. **Political & Social Contract**  
   - Welfare / rights reforms (+public Cohesion, Mandate cost, long stability + Golden path; better for Western/Latin affinity).  
   - Centralization / emergency powers (easier military_allocation shifts, -public, +institutional control).  
   - Elite bargain vs broad legitimacy (different group weightings).

4. **Military & Security Doctrine** (ties directly to unified industry allocation)  
   - Professional / small high-quality force (lower allocation needed for same strength, Ascendancy/agent quality synergy).  
   - Mass / conscript + industrial mobilization (higher allocation, good with large industrial_base from immigration).  
   - Hidden Hand counter-subversion focus (protects Cohesion groups, costs Mandate).

5. **Foreign Policy & Projection / Imperial or Post-Imperial**  
   - Sphere of influence (Mandate +, industrial access, public Cohesion - from overreach, international Ascendancy backlash).  
   - Annex/puppet/core style defaults (heavy vs hearts-and-minds vs hybrid; interacts with victory_integration costs/resistance/claims).  
   - Decolonize for soft power or double down on extraction (Mandate vs long-term grievance/Hidden Hand in colonies).

6. **Alt-History / Crisis Response Branches (peace-tied)**  
   - Post-1918 harsh exclusion: "Reconciliation & stabilization" (cohesion +, Ascendancy -, opens democratic or Dawes-like paths) vs "Revanchist rearmament" (Ascendancy/Mandate short, grievance reduction, future radical leaders/agents).  
   - 1923 crisis responses already wired in dialogue; tree can have follow-on nodes that only appear because of prior choice.

7. **Scientific / Educational Supremacy**  
   - Agent-tech sponsorship focus (boosts get_agent_quality_bonus effectiveness, industrial R&D feel).  
   - Literacy / technical education push (long Mandate + Cohesion, interacts with immigration skilled policy).

**Golden Age Initiatives (the special high-tier, highly specialized layer — part of the fun of the Ascendancy resource game)**:
Only available when Ascendancy >= 90 or trigger_golden_age() has fired (sustained high + supporting initiatives/economy/agents). These are the "you built the stat, now feel it" moments. They are powerful but not free — some have overextension risk if Cohesion groups are mismanaged.

Examples (already stubbed + expanded in GameData.gd):
- Golden Economic Miracle: industrial_base * ~1.55 + Mandate surge + temporary civilian allocation priority (flexibility reward). Feels like the 1920s boom or Marshall-era growth.
- Golden Civilizational Renaissance: +22 all Cohesion groups (public/elite/institutional), primary sphere affinity bonuses (immigration and integration become net strengths), cultural export prestige, temporary separatism immunity. "The world looks to our model."
- Golden Technological Vanguard: industrial efficiency + Mandate + ahead-of-time tech momentum (simulated; future hook to TechnologyManager). Pairs with high Ascendancy agent quality.
- Golden Hegemonic Mandate / Soft Power: +35 Mandate, international reactions softened (observers less likely to disapprove your integration/spheres), easier puppet/core acceptance (prosperity pull on low-Cohesion neighbors — directly supports the "failed states look to high Ascendancy systems" fantasy).
- Future ideas: "Agent Golden Network" (massive temporary quality + new special mission categories), "National Mythos Unification" (public/elite/institutional all pushed very high, Hidden Hand subversion resistance), "World's Fair / Cultural Exhibition" (short prestige + long affinity gains).

These are *not* required to "win" — many campaigns will do great with strong normal initiatives + good agent allocation + favorable peace terms. But when you hit Golden, the specials make it memorable and different.

**Detailed immigration / macro culture model (how we actually implement the "foreign workers cheap labor vs citizen jobs/cohesion/crime/undermine" concern)**:
- Macro spheres only (7): Western, Islamic, African, Sinic, Indic, Orthodox, Latin. Each nation has primary_culture (in peace_state) + accepted minorities array. Affinity matrix (0-1) between every pair (Western high to Latin, lower to Islamic/African in many hosts, Islamic internal very high, Sinic high internal + decent to Indic, etc.). Affinity is the main "large civilizational difference" knob.
- Immigration as Initiative (or policy unlocked by tree node): unlock_ascendancy_initiative calls apply_immigration_policy(tag, source_culture, scale 0-1, policy).
- Short-term (immediate in apply): industrial_base + (bigger with high affinity), Mandate +, public Cohesion small + (people love cheap goods/lower prices).
- Long-term / friction (applied for visibility, will have TimeManager monthly erosion component later): 
  - Public: - (jobs competition + wage pressure + "undermines your nation" narrative). Scaled by scale + (1-affinity) distance_penalty. This is the main "hurts in jobs for citizens lowers cohesion increases crime" vector.
  - Elite: often + (business profits from cheap labor). This creates the group split that Hidden Hand can exploit (elites push open, public suffers, division grows).
  - Institutional: - (crime rise, integration/services load on police/schools/hospitals). Worse on open + low affinity.
- Policy variants (the player agency):
  - open: max short industrial/Mandate, max long public/institutional drain + max Hidden Hand on public.
  - guest_worker: high short, reduced long public hit and less permanent settlement (historical guest worker programs). Elite still happy.
  - skilled_only: lower volume, talent/Mandate/tech side bonus, smaller public backlash.
  - assimilation_focus: spend Ascendancy (the "cost" of doing it right), recovers public + institutional, partial affinity conversion toward host primary (future immigration from that source is less painful). This is how you "fix" a prior open wave or turn demographic change into strength before Golden.
- Hidden Hand: gains on public (and sometimes elite) proportional to scale * distance. Low public + high immigration = check_subversion_risk and check_separatism_risk fire more easily (riots, unrest, breakaway pressure like Alberta/Greenland examples, or openness to a high-Ascendancy neighbor's model).
- Victory / integration tie-in: calculate_occupation_resistance already takes cultural_distance. We will feed primary vs territory primary + current immigration state into it. High immigration without assimilation makes integrating culturally distant territory harder.
- Failed state pressure: simulate_failed_state_pressure + low public from prior immigration pain can accelerate collapse or make the population "look to" a prosperous high-Ascendancy neighbor (or your own model if you are the high one exporting via Golden renaissance).
- Fun play patterns this enables:
  - Post-harsh-Versailles Germany (or Turkey) takes large African/Islamic guest labor for rapid industrial rebuild → short growth, public Cohesion tanks, Hidden Hand grows → later player must choose assimilation initiative (spend hard-earned Ascendancy) or homogeneous correction or ride it into a risky Golden.
  - USA or France does skilled Western + limited Sinic for quality without too much friction → steady Mandate + industrial, public stays healthy → easier to hit Golden and take renaissance/hegemonic specials.
  - Homogeneous focus nation keeps high public trust → slower growth but very stable Cohesion groups → Golden arrives earlier and the renaissance special is extremely strong (your model is "pure" and attractive).
  - Over-open player with low Ascendancy gets the "undermines your nation" spiral (public drops, crime, Hidden Hand, separatism risk) — but recovery is possible via agents, welfare initiative, or accepting a high-Ascendancy patron.

**How this creates a fun and powerful sandbox for player agency**:
- Meaningful, legible trade-offs that feel historical and real without requiring pop-by-pop simulation.
- Combinations > single choices: open immigration + later assimilation + Golden renaissance = net civilizational win with character. Open + no mitigation + low Ascendancy = memorable disaster or "we became something else" alt-history.
- Visible in every other system: industrial_base (unified, so immigration directly enlarges your military potential at same %), military_allocation (low public Cohesion forces higher % for control), Cohesion groups (Hidden Hand target, separatism, event resistance), Mandate (soft power for integration/pacts), Ascendancy (the fuel + the Golden gate), victory costs (cultural distance), agent quality (high Ascendancy from successful culture initiatives feeds back).
- Alt-history weight: Central Powers player who fought for inclusion in 1918 has milder 1923 and can pursue "reconciliation + skilled immigration + welfare" for an early Golden renaissance that makes them the 1930s soft-power or industrial surprise. Harsh path player has grievance but also "necessity" options (guest labor boom, centralization) that can produce a different, harsher but powerful Germany or Turkey.
- Ebb/flow drama: Low periods unlock crisis initiatives that are cheaper or more effective. High periods unlock Golden specials that feel like the payoff for the resource game.
- Not everything is Golden-chasing: You can deliberately stay mid-Ascendancy, focus on homogeneous stability + sphere projection, or use immigration aggressively for a "quantity over cohesion" conquest path. Multiple viable national characters.

**Current implementation status (as of this update)**:
- Stubs + rich logic live in GameData.gd: culture_groups with affinity matrix (11 macro incl. Persianate/IndigenousAmerican/Oceanic), primary_culture per tag, apply_immigration_policy (full short/long, group splits, policy variants, distance penalty, Hidden Hand, downstream risk checks), unlock_ascendancy_initiative + get_available_initiatives (dynamic, 10+ concrete examples across categories + 4 Golden specials already wired with real pillar/industrial effects), trigger_golden_age, check_subversion/separatism, cheap exports/aid, agent allocation hooks.
- **Hybrid Ascendancy Initiatives tree (world-class flexible)**: get_ascendancy_initiative_tree now returns fixed-core branches (Economic/Military/Diplomatic/Covert/Ascendancy) + rich dynamic/map-contextual nodes (uses MapManager.get_owned_river_provinces / get_owned_coastal_or_port_provinces / get_border_provinces_with / get_adjacent_countries to detect owned on rivers/lakes/oceans/borders/neighbors; nodes carry target_type, requires_player_choice, player_choice_feature="river|coastal|border", geo_feature, effect dicts). E.g. "River Hub Development" (player choice on owned river pid), "Pressure Border Province on Rhine/FRA", "Coastal Fort on Baltic" (integrates apply_ascendancy_initiative_player_province_choice which applies geo-aware settlement/infra/mandate, notifies map for combat/supply visuals). 
- **Full in-game edit mode**: add_custom_initiative_node(tag, branch, node_data), move_node, retool_node (edit target/effect), remove_node; persisted in peace_state["custom_initiative_nodes"] (runtime + SaveLoad via get/apply_save_data). Customs merged live into get_tree(). Ties to 4 LS concepts (globe/map, agents, pillars, epochs).
- **Epoch shifts expanded**: process_epoch_shifts supports dynamic 20yr cadence (not fixed list), >=6 choices per (econ off-gold+follow inflation_risk/erosion, military posture provoking neighbors + adds geo border tree node, tech priority causing lag/unlock waves, colonial with unrest, political with rev risk, cultural with coh hit). Wired follow-ups/thresholds after apply: if coh<35 fire "social unrest" or "hidden hand exploit" (via check_subversion_risk + news + pillar hit, mitigated by agent_mit from get_agent_quality_bonus); if >70 "golden age momentum" (trigger_golden + unlock tree golden + pillar+). Agent influence mitigates. Epoch choices integrate tree (add geo custom nodes, complete progress). Persisted in epoch_decisions.
- Player geo choice: map clicks -> apply_..._player_province_choice extended for river/coastal/border (feature detection via MapManager.has_river_border + Province resolve_has_port/has_feature/terrain/adj).
- Tech symmetry: TechnologyManager.gd has get_editable_tech_tree (core+custom+progress), add_custom_tech, edit_tech_progress, retool_tech_node, remove_custom_tech; works with country_state + persisted.
- Demo (PeaceTreatyPhasesDemo.gd): ... (prior)
- State chart / ScenarioLoader: Wired to prime trees post-map/tech (get_... + get_editable).
- DESIGN: This section + prior... Updated with hybrid tree/edit/epoch/geo details + ties to key loops (map clicks for choice, agent missions mitigate/sponsor, pillars for costs/effects, combat via border/coastal fort bonuses on Province modifiers + BattleManager).
- Next high-value: tree UI panel consuming the rich dicts, data-drive nodes from JSON, more.

**Open questions for continued discussion**:
- Exact policy surface: Are immigration choices "Initiatives" in the tree, or a top-level Policy/Law screen that Initiatives can unlock or modify? (Both can coexist — tree for big directional pushes, policy for fine tuning.)
- Erosion timing: How much of the long-term public/institutional drain should be immediate (for demo feedback) vs spread over 6-24 simulated months via TimeManager? Hidden Hand exploitation can be front-loaded or event-driven.
- Number of macro groups: 7 feels right for now. Add Turkic/Persian or keep subsumed?
- Victory cultural claims: Should ancestral + population claims also interact with "cultural sphere overlap" for lower resistance when annexing same-sphere territory?
- Balance knobs: Current numbers in apply_immigration_policy and Golden specials are tuned for visible demo effect. We will need playtest passes once the tree has a real UI and TimeManager erosion is live.
- Hidden Hand "sponsorship": Rival or internal Hidden Hand can push negative versions of immigration (or block assimilation) as subversion missions — very on-theme.

This directly continues the conversation. The Initiatives tree + macro culture/immigration model + Golden specials are now live as playable stubs in the phases demo (launch it, click the new culture/immigration/Golden buttons, watch pillar logs and launch the dialogue). The system gives exactly the sandbox agency requested: big, understandable, trade-off-heavy choices for where you want to take your nation, with culture/foreign workers as a first-class painful-but-powerful lever, Golden as the aspirational payoff, and full integration with the pillars, peace follow-ons, agents, and victory costs.

Let's keep growing — next could be the data-driven initiatives JSON, a simple tree UI sketch in the demo, or wiring one more Golden special into the state chart with a dedicated transition. Your call. Ready to iterate.

---

## 11. Policy/Law Screen, Pro-Natal & Restriction Options, Two-Tier Justice, Foreign Military Consequences, Erosion Timing, Whole-World Macro Cultures (June 2026 Follow-up)

**User feedback (paraphrased/verbatim key points)**: Love the Ascendancy Initiatives and explanation. Want options so we are not prioritizing migration as the only lever — incentives for pop growth (no taxes for families with more kids, homes for families with 5+ kids, other policies encouraging native growth). These take longer than open immigration. Choices like "build the wall" or ways to make immigration difficult (you have to really want it). Two-tiered justice is often status quo in many kingdoms (royals get special treatment). Top-level policy/law screen: initiatives that can be adjusted, unlocked, and modified by the player. Erosion timing — user will take the recommendation. Macro groups must encompass the largest groups in the world and still give flavor (whole world game). Persian vs Sinic vs Islamic clarification. Further balancing once gameplay loop is developed for real testing of fun/trade-offs/interactions. High levels of non-citizens or large foreign portions in the military should have consequences (analogous to coming off the gold standard → inflation; major government expansion and printing of money). Keep building and running further. Ask any further questions or design ideas.

**Response philosophy**: We are treating the Ascendancy Initiatives tree as the "big visionary / directional pushes + Golden specials" layer and adding a complementary **top-level Policy/Law screen** (tunable, adjustable ongoing laws) that the tree can unlock, modify, or gate. This gives exactly the "not just migration" depth requested while keeping migration as one powerful but risky tool among many. All new mechanics feed the existing pillars (especially public/elite/institutional Cohesion splits, Mandate, industrial_base, non_citizen_ratio as a first-class tracked value), Hidden Hand, separatism, and the "social inflation" debasement concept.

### 11.1 Top-Level Policy/Law Screen Concept
- Separate but synergistic with the Initiatives tree.
- Always or contextually accessible (future UI tab or panel in National Overview / Diplomacy / Domestic screen).
- Player can adjust, unlock (via tree nodes, tech/era, high Ascendancy, agent success, or events), and change policies over time.
- Changing costs political capital (Mandate or Ascendancy spend) + possible immediate Cohesion backlash or gain depending on direction and current public sentiment.
- Persistence: Policies stay until changed (unlike one-shot tree Initiatives). Tree nodes can "lock in" favorable policies or unlock higher levels (e.g. a Golden culture special massively buffs pro-natal effectiveness).
- Examples of tunable policies (all now stubbed in GameData with real pillar/industrial/non-citizen effects):
  - Pro-natal level (0–3): none → tax breaks for families with kids → housing priority for 5+ kids families → full cultural + economic campaign.
  - Border policy: open / guest_worker / skilled_only / restricted / fortified ("build the wall" — high barriers, you have to really want to come in).
  - Justice mode: egalitarian / two_tier (elite/royal special treatment).
  - Military integration / foreign troops % (0–40%+): direct slider or stepped choices with scaling consequences.
- Future: More (economic orthodoxy vs fiat expansion with explicit inflation mechanics, religious establishment level, land reform, conscription rules, etc.). Agents get new "Policy Influence" or "Domestic Ops" missions to shift these without direct player spend.

### 11.2 Pro-Natal / Native Pop Growth Incentives (the main "not just migration" lever)
- Concrete examples implemented: tax relief for families with children, priority housing or subsidies for large families (5+ kids), broader family allowances or cultural/religious encouragement campaigns.
- Mechanical profile: Slower payoff than open immigration (no immediate industrial_base spike). Over months/years via erosion processor: gradual reduction in non_citizen_ratio pressure, +public Cohesion (families feel the state supports them and the nation has a future), +long-term "manpower" / industrial sustainability feel, lower Hidden Hand / separatism vulnerability.
- Costs: Mandate (direct subsidies) + small Ascendancy (mobilizing national narrative). Can be paired with skilled-only immigration for hybrid quality growth.
- Why it feels different and powerful: Immigration is "import growth now, cohesion bill later." Pro-natal is "invest in our own people — slower, more expensive upfront in capital, but builds the kind of high-trust public cohesion that makes Golden Age specials (renaissance especially) much stronger and more stable."
- Tree integration: "Pro-Natal Family Incentives" initiative (already wired) directly calls the policy at a strong level. Future nodes can upgrade the level or reduce the Mandate cost.

### 11.3 Restriction / "Build the Wall" / High-Barrier Options
- Policies: "restricted" and "fortified".
- Effects: Caps or heavily reduces new immigration scale. Strong +public Cohesion (citizen jobs protected, cultural familiarity preserved). Slower industrial_base growth (no cheap labor surge). Ongoing Mandate cost for enforcement (or player can assign agents to "Border Security" missions for better efficiency / lower cost).
- Narrative: "You have to really want it" — creates a clear "difficult to immigrate" choice. Excellent counter when player has already taken a big open wave and is suffering the long public drain.
- Pairs beautifully with pro-natal: Use restriction + native incentives to deliberately shift the demographic balance back toward citizens over a decade of play.

### 11.4 Two-Tiered Justice (Historical Status Quo)
- Mode: "two_tier" vs "egalitarian".
- Effects: +elite Cohesion and short Mandate (upper strata feel secure and rewarded — the historical norm in kingdoms, empires, many non-Western polities). -public Cohesion (resentment, "the rules don't apply to them"). Hidden Hand gains exploitation on the public group ("injustice" narrative is powerful fuel).
- Flavor: Perfect for playing traditional monarchies, aristocratic republics, or empires that haven't gone through a broad legitimacy revolution. Risky for players trying to maintain high public cohesion for Golden or stability.
- Tree or Policy screen: Easy to toggle; some cultures/government types start biased toward two-tier (or unlock it more cheaply).

### 11.5 Non-Citizen Ratios + Foreigners in the Military — Explicit "Inflation" Consequences
- Tracked values now in peace_state: `non_citizen_ratio` (overall foreign-born or non-citizen population pressure) and `foreign_military_pct` (portion of forces that are non-citizens/foreign legions).
- Immigration (especially open/high-scale) increases non_citizen_ratio.
- Pro-natal + assimilation + strict borders decrease or buffer it.
- Foreign military integration directly sets the military % (with immediate bonuses + risks).
- Consequences (modeled after user's gold standard / printing money analogy):
  - "Social inflation / debasement": High non_citizen or foreign_military % causes gradual Mandate loss, slight industrial_base / efficiency drag, and public happiness decay (trust in the system erodes the same way excessive money printing erodes currency value).
  - Military-specific: Cheap/fast army growth and lower upkeep (big bonus for rapid expansion or recovery after harsh peace). But institutional Cohesion hit (command loyalty doubts, integration friction), public resentment ("our boys replaced"), and crisis fragility (higher desertion/separatism risk if public Cohesion is already low or during a Hidden Hand push).
  - Hidden Hand / separatism synergy: High foreign presence + low public = much higher subversion success and breakaway pressure.
- This makes the choice *real*: "Do I take the quick cheap legions and foreign workers to survive the 1920s, knowing it will slowly undermine cohesion and efficiency like Weimar printing, or do I pay the harder native/pro-natal + restriction price for a cleaner, more resilient long game?"

### 11.6 Erosion Timing Recommendation (Implemented)
- Hook: `TimeManager.game_month_advanced` (already exists and is reliable — emitted on every month cross in advance_days).
- Implementation (in `process_monthly_demographic_erosion`):
  - Small monthly ticks: e.g. public Cohesion erosion = f(non_citizen_ratio, foreign_military_pct, current border/pro_natal policy, affinity factors). 0.1–2.0 points per month depending on severity — feels organic over 1–3 simulated years.
  - Threshold events: At 15–25%+ non-citizen or foreign military, periodic (every 3–4 months) extra Hidden Hand + on public, possible crime/unrest toasts or future dialogue triggers, extra institutional drag.
  - Mitigation: Pro-natal level 2+ multiplies erosion by ~0.6. Fortified/restricted borders multiply by ~0.5. Assimilation policies give direct recovery hits.
  - "Social inflation" drag: Above ~15% thresholds, monthly small Mandate and industrial efficiency losses (exactly the debasement parallel).
  - Demo vs simulation: The apply_ methods still do immediate visible pillar/industrial shifts for player feedback and "I just changed policy" satisfaction. The monthly processor is the quiet ongoing reality between big decisions.
- This matches the "gradual but visible" feel you want without requiring full pop simulation yet. We can tune the numbers heavily once the broader economy/manpower/combat loops exist for real playtesting of fun and trade-off weight.

### 11.7 Whole-World Macro Culture Groups — Coverage + Flavor + Persian Clarification
Current expanded set (now in code): Western, Latin, Orthodox, Islamic (broad), **Persianate**, Turkic, African (Sub-Saharan), Indic, Sinic, Southeast Asian.

- **Coverage**: This hits the largest historical and modern population centers extremely well:
  - Western + Latin + Orthodox ≈ Europe + European settler societies + Russia/Eastern Europe.
  - Islamic + Persianate + Turkic ≈ Middle East, North Africa, Central Asia, significant parts of South Asia and the Balkans, historical Ottoman/Persian/Turkic spheres.
  - African ≈ Sub-Saharan populations (largest growth region long-term).
  - Indic ≈ Indian subcontinent (huge).
  - Sinic ≈ China + historical East Asian Confucian sphere (by far the largest single civilizational bloc).
  - Southeast Asian ≈ Indonesia, Malaysia, Philippines, Thailand, Vietnam, etc. (very populous, distinct from both Sinic and broad Islamic even where overlapping).
- **Flavor without micro**: Each has distinct baseline Cohesion tendencies and affinity profiles. Golden Age culture specials and immigration/integration resistance feel different depending on your primary vs source. Internal diversity (Arab vs non-Arab within Islamic/Persianate, Han vs other within Sinic, Protestant vs Catholic within Western/Latin, Sunni vs Shia with Persianate flavor, etc.) is handled by events, leader traits, specific Initiatives/policies, and later optional sub-layers. This keeps the sandbox powerful and understandable while the game scales to the whole world.
- **Persian vs Sinic vs Islamic answer**: 
  - **Persians (Persianate) are NOT Sinic.** Sinic is the East Asian (primarily Sinitic/Chinese) Confucian cultural sphere — different language family, philosophical base (Confucianism, Taoism, Mahayana influences), imperial exam bureaucracy model, aesthetics, and historical trajectory.
  - Persianate is a distinct Iranian civilizational layer (Achaemenid, Parthian, Sassanid roots; rich epic and administrative tradition — Ferdowsi, court poetry, sophisticated governance). It has very high affinity to the broader Islamic world (many Persians are Muslim, often Shia, and Persianate culture heavily influenced Islamic administration, science, and arts), but it is not the same as core Arab Islamic or Turkic steppe-influenced Islamic. It carries pre-Islamic continuity and a different "flavor" of high culture and resilience.
  - In the model: Persianate has strong internal affinity and good affinity to Islamic/Turkic, medium to Orthodox/Indic, lower to Western/Sinic. Golden renaissance for a Persianate primary feels different (administrative prestige, literary/courtly export) than a Sinic one (technocratic order, scale, philosophical depth) or a broad Islamic one (religious cohesion + trade networks).
- This set should feel flavorful and "right" when we reach China, India, Iran, Turkey, Indonesia, Japan/Korea edges, various African states, Latin America, etc. We can always add one more (e.g. a distinct "Japanese" offshoot under Sinic or a "Mesoamerican/Andean" for New World flavor) if playtest shows a hole.

### 11.8 Current Implementation Status (Built in This Session)
- peace_state now carries demographic_policies, non_citizen_ratio, foreign_military_pct.
- culture_groups expanded with Persianate, Turkic, SoutheastAsian + full cross-affinities.
- New methods: apply_pro_natal_incentives (levels with housing/tax examples), apply_border_policy (fortified/"build the wall" supported), apply_military_integration (with explicit cheap bonus + loyalty/social inflation risks), apply_justice_policy (two_tier), process_monthly_demographic_erosion (hooked to game_month_advanced, with mitigation, thresholds, inflation drag).
- Initiatives tree updated: new unlock options for pro_natal_family_incentives, fortified_borders_build_the_wall, foreign_legions_military, two_tier_justice_privilege. get_available now surfaces them dynamically based on cohesion, non-citizen pressure, culture primary, Ascendancy, etc.
- PeaceTreatyPhasesDemo: Full new section with 5 policy buttons + "Simulate 6 Months Erosion" + launch button for the new population_policies.dialogue. Logs explain the exact trade-offs and inflation analogy.
- New dialogue: data/peace/population_policies.dialogue (branching choices with direct do-calls to the apply methods + narrative on timing, social inflation, and tree vs policy screen distinction).
- State chart / controller: Ready for future "PolicyShift" or "DemographicLaw" states (erosion already runs globally via TimeManager).
- DESIGN: This section + prior ones.

All of this is immediately testable in the phases demo (click the new policy buttons, launch the dialogue, hit "Simulate 6 Months Erosion", watch the logs for public strain, Mandate/industrial drag, Hidden Hand, and mitigation from pro-natal/fortified choices).

### 11.9 Open Questions & Design Ideas for Next Iteration (Please Answer / Direct)
1. **Policy/Law screen surface**: Separate always-visible or contextually available tab/panel (like Victoria laws or EU4 government reforms)? Or primarily launched/modified from the Ascendancy Initiatives tree nodes + occasional event/leader-driven changes? How "expensive" should mid-game changes feel (big Mandate hit + temporary public backlash, or lighter with agent help)?
2. **Pro-natal specifics**: Which incentives feel most important to you first (tax breaks, housing/subsidies for large families, education/childcare support, explicit cultural/religious "have babies for the nation" campaigns, land grants)? Any built-in downsides (e.g. elite resistance if too redistributive toward lower classes, or short-term Mandate strain that hurts military readiness)?
3. **Foreign military consequences depth**: Specific mechanical hooks you want soon (e.g. a "loyalty" or "reliability" multiplier that reduces effective combat power in low-cohesion or high-Hidden-Hand situations; higher desertion in civil wars; special "foreign general" leaders with mixed traits)? Hard caps (never >35% without a special Initiative) or soft scaling risk?
4. **Social inflation / debasement naming and effects**: "Social Currency Debasement", "Cohesion Inflation", "Trust Erosion"? Should it also affect Ascendancy (prestige hit from visible disorder) or industrial growth rate more aggressively once the production loop is live? Any interaction with actual economic "printing money" mechanics we will add later?
5. **Two-tier justice**: How deep do you want the flavor/mechanics (special event outcomes biased toward elite, leader recruitment perks for aristocrats, lower public resistance to certain harsh decisions because "that's how it is," or Hidden Hand getting easier "reform the system" missions against you)?
6. **Whole world cultures — prioritization**: Any specific regions or sub-flavors you want strong early differentiation for (e.g. Japanese as a high-cohesion distinct flavor under or beside Sinic, various African regional strengths, strong Persianate admin bonuses for Iran/Central Asia, SE Asian maritime/trade flavor, Latin American syncretic specifics)? Should we add one more macro (e.g. "Indigenous American" or "Oceanian") now or wait for map/scenario work?
7. **Erosion & monthly processor tuning**: Monthly small ticks + threshold events good? Or heavier event-driven with only passive decay between big policy changes? How visible should the "social inflation" drag be in the UI (a small ongoing "Demographic Strain" modifier tooltip, or mostly hidden until it spikes events)?
8. **Agent integration**: New mission categories for "Demographic Warfare / Policy Ops" (promote pro-natal propaganda, sabotage border enforcement, recruit foreign military talent, foment resentment via two-tier justice narratives)? Should Vision-allocation agents be able to directly sponsor or cheapen specific policy changes?
9. **Golden Age synergies**: Special "Demographic Golden Age" or culture-specific renaissance effects when you have high Ascendancy + strong pro-natal + low non-citizen (massive native growth surge + cohesion floor + industrial sustainability multiplier)? Or "Imperial Cosmopolitan" Golden for high-foreign-military players who lean into it (different bonuses, different risks)?
10. **Balancing & testing loop**: You mentioned further balancing once the gameplay loop is more developed. What systems do you want online next before we do a focused "play 10–20 years as GER/FRA/USA/TUR/JAP and feel the demographic policy trade-offs" pass (e.g. basic manpower/recruitment, actual combat effectiveness modifiers, production efficiency, event system for crime/unrest, save/load of the new state)?

This keeps the momentum exactly where you want it — concrete, buildable expansions to the Ascendancy Initiatives + pillars sandbox that give real choices (migration is powerful but no longer the only or even the default path), proper historical flavor (two-tier justice, Persianate distinction), and the inflation-style consequences for high non-citizen/foreign military mixes.

I'm ready to keep building whatever you prioritize next (more policy types, agent missions for demographics, a first visual Policy screen stub in the demo, data-driven policy definitions, erosion event wiring, specific culture Golden specials, or anything else). Fire away with answers, new ideas, or "do X next." Let's keep growing and running further.

---

## 12. Policy/Law Architecture, Loyalty Multipliers, Trust Erosion/Printing Mechanics, World Cultures + Relocation, Visibility, Agent Integration, and Path to 10-Year Testable Scenario (Direct Response to User Points + Builds)

**User direct answers (numbered to previous questions) + my recommendations after reviewing other grand strategy titles (Victoria 3 Laws + Interest Groups, EU4 Government Reforms + Estates + Missions, HOI4 Focuses/Laws in expansions, Stellaris Policies/Edicts/Traditions, CK3 Laws/Culture/Agents/Councillors, etc.) and aligning to our pillars (Ascendancy/Cohesion groups/Mandate), agent centrality (trade-offs), Initiatives tree (big pushes), Hidden Hand, TimeManager erosion, whole-world scope, and "fun powerful sandbox with real choices" principle.**

### 1. Policies and Laws — Separate Panel? Agent Involvement? Big Deal Mechanics?
**Recommendation (world-class without overcomplication):** 
- **Yes, make it its own thing: a dedicated Policy/Law panel** (modeled on Victoria 3 Laws tab — clean, categorized list with current setting, before/after effects preview, change button showing Mandate/Ascendancy cost + Cohesion reaction + time/agent options). It feels weighty and "real" like passing laws in parliament or decrees from a king. Not buried in the Initiatives tree (tree = big visionary/Golden direction; Policy screen = ongoing tunable steering of the nation).
- **Agent pressure as the primary, most interesting way to change most laws for most players**: New long-duration "Domestic Influence" or "Law Lobby" missions (examples now in mission_definitions.json: "Lobby / Campaign for Policy or Law Change", "Build or Expand Secret Police"). These tie up 1+ influence-skilled agents for 6-12+ months. Success reduces the direct player cost in the panel or directly enacts the change with less backlash.
  - Trade-off is explicit and painful: Those agents are *not* doing Tech development, Intel ops, Trade deals, Vision (Initiatives sponsorship), or Diplomacy. "Is changing this law *that* important right now?"
  - Player can still direct-change in the panel (pay full political capital cost + possible immediate public/elite reaction). High Ascendancy or strong elite/public support (Cohesion groups) makes direct change cheaper/faster.
  - Hidden Hand can run counter-missions (fund opposition, expose bribes, run "reform the corrupt system" narratives).
- Why this works for our game: Policies become another major activity loop and source of replay/agency. It leverages our existing Cohesion groups (elites often oppose pro-natal or support cheap foreign labor; public reacts to conscription or secret police). It makes agents feel central (as originally designed). Changing laws feels like a *big deal* (time, opportunity cost, risk of exposure/backlash) rather than a free click.
- Other games leveraged:
  - Vic3: Laws are simulation core; interest groups (our public/elite/institutional) support/oppose; enactment takes political capital + time; unhappy groups radicalize.
  - EU4: Reforms cost "progress" (time + monarch points); estates (our groups) influence success.
  - Stellaris: Policies/edicts cost influence and have ethics attraction over time.
  - CK3: Councillor (agent) actions + hooks to push laws/culture changes; long-term consequences.
- Implementation note: The panel can be a future Godot scene or code-built Window like the phases demo. For now the apply_* methods + demo buttons + agent stub give immediate play.

### 2. More Pro-Natal Options, Conscription, Women Policies, Police Types + Natural Downsides
**Built and ready:**
- Multiple pro-natal options at comparable power to immigration but longer effect (tax breaks, housing for 5+ kids, full campaign). Time commitment is the biggest downside (as you said).
- Elite opposition is the next biggest (elites often prefer cheap foreign labor for profits — this creates the Cohesion group split and Hidden Hand opportunity we already model).
- Added: Conscription laws (0-2 levels — directly affects military_allocation % and public Cohesion; very relevant when manpower is low and you start reaching for foreign troops).
- Women in workforce/war/military ("restricted/encouraged/full") — industrial or military capacity boost with culture-dependent cohesion effects (different flavor by primary sphere).
- Police types (local / secret / foreign-controlled) — control vs. public trust vs. Hidden Hand resistance trade-offs. Secret police expansion is now an agent mission too.
- All wired into demographic_policies, monthly erosion, and the Policy screen concept.

### 3. Loyalty/Reliability Multiplier for Foreign Military (History-Based Recommendation)
**Implemented `get_military_loyalty_multiplier(tag)` + effects in apply_military_integration and monthly processor.**
- **Recommendation (history + playability):** Foreign % gives the numbers/cheap troops bonus you want when manpower is tight, but applies a scaling "Loyalty Multiplier" (starts ~1.0, drops to ~0.84 at 25% foreign, down to 0.6+ at high %) that reduces effective organization and morale in future combat simulation (foreigners less likely to fight as hard or as long, less creative/initiative like many historical mercenary or auxiliary forces).
- Higher attrition (desertion rate) built into the model.
- Significantly more susceptible to Hidden Hand subversion (foreign units are natural vectors).
- Historical grounding (as you requested I study):
  - Roman model (strong recommendation): Auxiliaries and foederati worked well when there was a clear path to citizenship after service (integration carrot reduced long-term risks and built loyal citizens). We already have the pro-natal + assimilation + military service path that can convert foreign troops to citizens over years — this improves the multiplier and reduces HH risk. Offer the carrot like Rome.
  - Mercenaries: Swiss Guards and some condottieri had high success due to discipline and separate corporate identity; many others were unreliable (switched sides for better pay — the loyalty multiplier captures this).
  - Ottoman Janissaries: Initially devastatingly effective, later became a political liability (Hidden Hand-style internal power).
  - British Empire: Gurkhas and certain Indian units showed high loyalty when well-treated and with clear status; 1857 shows the risk when trust erodes.
  - French Foreign Legion: Excellent unit cohesion and fighting power, but deliberately kept somewhat separate from the nation (loyalty is to the Legion, not always the flag).
- When manpower gets low (real pressure), the player *will* reach for foreigners — the multiplier + attrition + HH susceptibility + social inflation (from point 4) make it a tense, meaningful choice with clear trade-offs. Citizenship path is the long-term mitigator.

### 4. Trust Erosion / Currency Trust Erosion / Inflation — Effects + Printing + Hidden Hand Narrative
**Fully implemented ("Trust Erosion" + "fiat_strain" tracked values, monthly effects, printing mechanics, sovereign wealth/gold counters).**
- Name: "Trust Erosion" or "Currency Trust Erosion" (inflation is well-known but we can surface it as "social/currency trust erosion" in tooltips for flavor). Hits Ascendancy (prestige loss from visible national weakness) + production efficiency (workers less motivated, capital flight feel, "prices rising" drag on output) + public Cohesion.
- Weimar 1920s / 1920s crashes reference: Hyperinflation destroyed the middle class (public Cohesion collapse), fueled radicalization (perfect Hidden Hand win — "the system is broken"), economic ruin, then recovery paths via new currency + strong leadership/direction (exactly the ebb/flow + player agency we want). Our system has the fall (erosion → Ascendancy/production/public hits → radical events) *and* recovery levers (pro-natal + sound money policies + Golden direction).
- Printing money / expanded fiat: Short-term Mandate + industrial stimulus (war finance, stimulus, "solving" problems by expanding supply). Long-term debasement exactly as you described.
- Sovereign wealth funds, asset-based backing, gold reserves (Gaddafi gold dinar style): Powerful counters to erosion (boost Mandate, reduce trust_erosion). These are *major* Hidden Hand flags — they are against stable/real-asset money and have long-term aims to debase currencies globally to enable one-world control. Expect special ops, narratives, or events targeting nations that go hard on gold/asset backing. In 1918 most nations were still on or near gold; the long game is the debasement push.
- All wired: apply_money_supply_policy, apply_sovereign_wealth, monthly erosion processor applies Ascendancy/production/public hits when trust/fiat high, with Weimar-style threshold notes.

### 5. Two-Tier Justice
**User taking recommendation — kept as clean abstracted toggle (elite + / public - / Hidden Hand fuel).**
- Changing it is explicitly another Hidden Hand flag (elites are used to preferential treatment and will defend it; public resentment is the vector). Abstracted enough for fun/decision weight without micro (clear before/after in the Policy screen, visible Cohesion group reactions).

### 6. Whole-World Cultures + Relocation/Settlement/Conversion/Repopulation
**Added "IndigenousAmerican" and "Oceanic" to culture_groups with affinities.**
- Full set now supports world-scale simulation.
- New `apply_encourage_relocation(tag, target, scale)`: Directly models moving large groups of your primary (or compatible) culture into new lands, repopulation, settlement, and layered "conversion" (via assimilation policies or cultural/religious Initiatives on top). Reduces non-citizen pressure in destination, builds long-term cohesion ("our people have land and future"), affects future integration/victory resistance. Perfect for the mechanics you described.

### 7. Visibility — Player Knows Direction and Has Clear Levers to Alter Path (World-Class, Clean, Simple)
**Recommendation + implemented in demo refresh:**
- **Simple, high-level "National Direction" summary** (shown in phases demo grievance/pillars line, will go to TopInfoBar or a compact "Demographics" button in real UI): "Trust Erosion: 42 | Non-citizen: 28% | Mil Loyalty: 0.81"
- Tooltip / Policy screen drill-down: "Current trajectory: Rising Trust Erosion from high non-citizens + foreign troops + fiat. Projected +X in 24 months. Levers: Pro-Natal (slowing), Fortified Borders (reversing), Citizenship Integration path (converting), Gold/Sovereign Wealth (strong stabilizer). Click to open full Policy screen."
- Events/toasts at thresholds ("Public discontent over foreign labor rising — policy change available").
- Policies panel (future) shows clear before/after, time-to-effect, and "which way am I heading" summary with 2-3 prominent levers.
- World-class without overcomplicating: One glance (icons or small bars for Immigration Pressure / Native Growth / Trust Erosion / Military Loyalty) + one click to the categorized Policy screen with previews and costs. Like Vic3's clean law list + interest group approval, but lighter. Player always knows the current vector and has obvious, actionable ways to stay the course or change it. No hidden death spirals — erosion is visible and reversible with the tools we've built.

### 8. Agent Integration for Policy/Law Change
**Built:** `allocate_agent_to_policy_influence(...)` stub + two new long-duration missions in mission_definitions.json ("Lobby / Campaign for Policy or Law Change", "Build or Expand Secret Police").
- This is the heart of making policy change feel important and agent-driven. Agents committed for extended periods = real trade-off vs every other system. Hidden Hand counters add the cat-and-mouse. Player direct change in panel remains as the "I have the political capital right now" option.
- "Sounds good lets build this" — done for this iteration; can expand outcomes to directly call the apply_* methods with bonuses.

### 9. Golden Synergies
**Affirmed and noted:** The Demographic Golden Age / culture-specific renaissance effects when high Ascendancy + strong pro-natal + low non-citizen (or the "Imperial Cosmopolitan" path for high-foreign players) are exactly the kind of payoff you want. Can be wired as soon as we have more Golden triggers live.

### 10. Path Forward — Other Systems + Map to 10-Year Testable Scenario
**Agreed and actioned:** We will keep building the demographic/policy/erosion/Trust Erosion/printing/sovereign/relocation/agent pieces while pushing the map and core loops (manpower/recruitment ties to foreign % + loyalty, basic combat effectiveness modifiers from Cohesion/loyalty/erosion, production efficiency from inflation, event system for thresholds, save/load of the new state) to the point where a solid 10-year scenario (1918-1928 or equivalent) is playable and the trade-offs can be felt in real time.
- Immediate next high-value from this: More agent mission outcomes wired, basic printing + sovereign wealth events, loyalty multiplier feeding a stub combat or supply effect, relocation affecting territory integration, visibility polish in real UI elements, and map progress for testing.

**Builds performed in this session (continuing the run):**
- Expanded peace_state with trust_erosion + fiat_strain.
- culture_groups + IndigenousAmerican + Oceanic + relocation support.
- Full new apply_ methods (conscription, women_workforce, police_type, money_supply_policy with Weimar-style notes, sovereign_wealth, encourage_relocation, get_military_loyalty_multiplier with historical grounding + citizenship path, allocate_agent_to_policy_influence).
- Monthly erosion processor extended with Trust Erosion / fiat effects on Ascendancy + production + public.
- Demo: Many new buttons (conscription, women, secret police, fiat/print, sovereign wealth, relocation, agent lobby for law, loyalty multiplier check) + live Trust Erosion / non-citizen / loyalty display in the info line for immediate direction visibility.
- Agents: Two new long-duration policy influence missions in mission_definitions.json.
- All tied back to existing pillars, Hidden Hand, Initiatives, erosion timing, and the "big deal with agent trade-offs" vision.
- DESIGN updated with this full point-by-point + recommendations.

The systems now directly support everything you outlined: pro-natal as time-delayed peer to immigration (with elite downside), conscription/women/police as additional levers, foreign military with historical loyalty/org/morale/attrition/HH risks + citizenship integration path, Trust Erosion (hits Ascendancy + production, Weimar fall/recovery, printing vs gold/sovereign as Hidden Hand flashpoint), relocation for world-scale migration/repopulation/conversion, clean visibility of direction + levers, agent long-commitment as the main way to change big policies (trade-off explicit), separate Policy/Law concept that feels weighty, and Indigenous/Oceanic + full flavor.

**Progress on next biggest items (continued after "continue building")**:
- **Persistent/non-modal Policy panel extracted to reusable .tscn + manager (top remaining item completed)**: [as before]
- **Combat refinement + new controversial social policies (high-value per user feedback, June 2026)**: Refined settlement defender in BattleManager/Resolver to ~2.5% per settlement_level (capped 25% total uplift), conditional on public cohesion + culture match for flavorful "Homeland Resolve / Repopulation Resilience". GS best practices (HOI4 terrain/forts situational 15-50% defender favor, Vic3 gradual state dev 5-15%, EU4/CK3 optimized holdings ~20-40% but counterable) guided smart, fun, non-OP level – player feels policy investment in map territories without breaking attacker agency. Opposites: foreign-heavy settlement gives less bonus.
  New abstract "social_services" / welfare health policy (demographic_policies + apply_social_services_policy): modes "traditional", "elite_optimization" (pop control/cost savings – abstract elite family planning/abortion-like to eliminate types), "compassionate_end_of_life" (assisted suicide as welfare), "expansive_burden" (gender/equity + overextended healthcare creating large unsustainable load). Short-term Mandate/elite + or "savings"; long-term welfare_burden (new tracked like fiat/trust – public -, HH fuel, Mandate bleed, erosion amp, Golden risk/"decadent" variant). Crazy/disastrous policies modeled abstractly for clean implementation. Toasts first (LeaderEventUI) for awareness, then branching dialogue with clean interactive fun: clear opposites (control now vs revolt later), payoffs (elite support vs public/HH disaster), balance via restraint vs overreach. Integrated to monthly erosion, PolicyLawScreen (new row with dynamic previews), get_policy_* helpers, initiatives list, Golden trigger (disastrous blocks or twists), map via erosion (local supply feel), agents (lobby counter). Dialogue extended with ~welfare_burden_crisis (toasts-first style). Expands "crazy policies" flavor user requested while keeping abstract and trade-off heavy.
- **Full map territory for relocation/settlement (key integration — completed in this pass)**: apply_encourage_relocation now does real multi-province mutation (prefers owned provinces via MapManager.get_provinces_by_owner, falls back to demo set of phase1 ids; distributes dev + infra + new explicit `settlement_level` on Province). Province getters (org recovery, attrition, local supply generation, combat width, logistics) automatically reward higher dev/infra; we also added direct settlement_level terms for flavor. MapManager update paths + signals used where available. settled_areas continues to drive victory resistance (calculate_occupation_resistance) + Golden synergies. Demo relocate button now documents the multi-province + supply/combat/victory effects. This makes relocation a first-class map + military + supply lever (repopulated "our lands" are more defensible, productive, resilient). Supply tie-in via get_local_supply_generation_modifier; combat via org/attrition/width.
- **More events/dialogues (secret police backlash branch)**: Added trigger in monthly for secret police (public hit + HH), with launch of new ~ secret_police_backlash in population_policies.dialogue (choices: double down, reform, agent mitigate). Extended for conscription risk. Builds on Golden pro-natal synergies (manpower surge in trigger_golden_age if high pro_natal/settled).
- **Combat deeper (loyalty in Resolver + Province tie, BattleManager note)**: CombatResolver already applies explicit loyalty/foreign penalty to power/org/readiness/attacks (on top of Province mods which include loyalty). BattleManager execute now has context for mixed armies; resolver call uses it for formation effectiveness in mixed forces. Testable in assault (loyalty from foreign policy degrades power if high foreign %).
- **Policy screen polish (dynamic previews in demo + TopInfoBar)**: Rows use the new helpers for coh_impact + time_est (e.g., "+Public long-term, -Elite short if opposed", "est. 6-18 months..."). Header includes recruits. TopInfoBar persistent window now uses helpers too.
- **Agent end-to-end + TopInfoBar wiring**: Demo button uses real API; TopInfoBar "Policies" opens the view with previews. Note on real missions (agent unavailable during advance).
- **Docs**: DESIGN updated with these + refreshed remaining (reusable .tscn, full multi-province map mutation, more dialogue triggers, combat full test, save edges).

All continue the high-value: policies have persistent/global UI with dynamic previews, relocation has real Province/map effects (dev/infra/org/supply), events add backlash choices, combat feels the loyalty (power penalty), agent trade-offs visible. Player agency in direction (TopInfoBar + panel) with clear levers and time estimates.

**Remaining high-value / next natural steps** (prioritized):
- ~~Extract policy UI to reusable .tscn/global manager~~ **DONE**.
- ~~Full map territory (multi-province relocation/settlement + Province hooks + supply/combat/victory integration)~~ **DONE** (see progress: real owned/low-dev provinces mutated with dev/infra/settlement_level via MapManager; getters auto-reward + explicit bonuses; resistance + supply + org/attrition/combat width wired; ProvinceInsight now surfaces settlement in tooltips/inspector; MapRenderer adds subtle vitality tint for high-settlement provinces; F10 DebugOverlay now has "Demographic Map Test" buttons for instant playtest application + logging. This elevates the map to a much better playable level for testing demographic/policy systems on real territories — click/assault/inspect to feel the effects. Generation pipeline (tools/map_generation) remains the path for "full territories" expansion; current phase1 data is now far more interactive for playtest.).
- More events/dialogues (add conscription riot branch; trigger Golden pro-natal event for manpower surge/loyalty bonus; extend for other policies).
- Combat deeper test (loyalty multiplier into full BattleManager/Resolver flows + mixed armies; Logistics + Province in assaults).
- Combat test (apply loyalty to division/formation power in BattleManager execute or resolver; test full flow with Logistics + Province in assault; mixed army penalties).
- Save/load edges (roundtrip after high erosion/fiat/settlement + missions; add NMM interactions for policy effects; ensure re-apply refreshes map/UI).
- AgentManager full polish (complete policy mission JSON with duration/magnitude; test real assign + multi-month advance without demo, verify unavailable + auto apply; add to agent UI).
- Polish (add Cohesion previews in persistent panel, better visuals, save/load for policy state).

The system is maturing into a rich, interconnected sandbox for demographic/policy strategy with agent weight, historical flavor, Hidden Hand risks, Golden payoffs, and clear player direction/levers. Ready for broader integration.

**Continue?** Pick the next (e.g., reusable policy .tscn, multi-province map mutation, conscription dialogue, combat test, save test, or new like conscription specifics). Let's keep building the next items.
- **More events in monthly erosion (secret police backlash, conscription unrest)**: Added logic in process_monthly_demographic_erosion for secret police (public hit + HH gain on "secret" policy) and conscription (public cohesion hit/riot risk if high level + low cohesion). Includes logs for event-like feedback; can trigger dialogues in future.
- **Map/Province real integration for relocation/settlement**: Enhanced apply_encourage_relocation with MapManager/Province stubs that explicitly boost dev/infra for settled areas (feeds Province getters for org, attrition, supply, combat width). calculate_occupation_resistance now uses settled_areas for resistance reduction.
- **AgentManager + demo polish (end-to-end time advance works with real API)**: The agent policy mission button uses valid TimeManager methods (advance_one_month exists and triggers signals). Added note on real missions using AgentManager + TimeManager for commitment/trade-off. TopInfoBar now has "Policies" button + improved Dir for opening policy view.
- **Policy screen polish (more estimates, Cohesion tooltips in rows)**: Rows in _open_policy_law_screen now include detailed coh_impact and time_est (e.g., "est. 6-18 months for pop growth payoff", "+Public long-term, -Elite short if opposed").
- **Golden synergies already extended** (pro-natal/settlement during Golden grants manpower + cohesion).
- **Docs**: DESIGN updated with these builds + refreshed remaining list.

All keep building the high-value: policies now affect combat power, events add narrative punch, relocation has Province/map weight, UI has better direction/policy access, agent end-to-end more real.

**Remaining high-value / next natural steps** (prioritized for 10-year test scenario):
- ~~Persistent/non-modal Policy panel~~ **DONE**.
- ~~Full map territory~~ **DONE** (multi-province real effects + Province settlement_level + automatic supply/org/attrition/combat/victory ties).
- More events/dialogues (add secret police backlash or conscription riot as full dialogue branches; trigger from monthly or policy change; add Golden Age pro-natal event for manpower surge).
- Combat deeper (in BattleManager or CombatResolver, apply loyalty to division power or formation effectiveness; test with real assault).
- Save/load edge cases (add unit tests or demo save after high erosion/fiat/settlement; ensure NMM/peace_state clear and re-apply works; integrate with Leader/Production if policies affect them).
- AgentManager full polish (ensure new policy missions have full JSON entries with duration/magnitude; test real assign_agent_to_mission + multi-month advance without demo button, verifying agent unavailable during mission).
- Polish Policy screen (add actual dynamic time-to-effect calc based on current Asc/agents/Cohesion; Cohesion group reaction previews in tooltips; better visuals).

The system is maturing into a powerful, interconnected sandbox for demographic strategy, policy trade-offs, agent influence, and long-term consequences (with Golden payoffs and Hidden Hand risks). Ready for broader integration/testing.

Keep going? Specify focus (e.g., persistent panel code, map Province boost, combat battle hook, new dialogue, or save test). Let's build the next items.

**Remaining high-value / next natural steps**:
- Combat deeper (pull Province loyalty modifiers into actual battle calcs or unit deployment in combat scripts; test with Logistics readiness).
- More events (add secret police backlash or conscription riot to monthly processor or new small dialogue; trigger on policy changes).
- Full AgentManager polish (ensure policy missions are properly in definitions with duration, and test real assign + multi-month advance without demo button).
- Save/load edge cases (test roundtrip with high erosion/fiat/manpower/settled; add any NMM interactions or clear hooks).
- Map territory real test (when MapManager/Provinces exercised, explicitly boost dev/infra or add settlement component to Province for relocation bonuses; integrate settled_areas into more victory paths).
- Persistent Policy panel (make _open_policy_law_screen or a new UI element non-modal, add to main game screens, wire TopInfoBar click to actually open it).

The build is progressing well toward the 10-year testable scenario with rich demographic/policy simulation.

Keep going? Specify the next item(s) from the list or new focus (e.g., specific combat file, more dialogues, map integration code). Let's build.

**Remaining high-value / next natural steps** (keep the list going):
- Polish Policy screen further (add actual time-to-effect estimates, Cohesion group tooltips, better visuals or separate persistent panel).
- First real map territory test (link settled_areas + relocation to actual Province development/attrition or MapManager when provinces are active; bonus to local supply or integration).
- Deeper combat integration (use Province loyalty modifiers in battle calcs, LogisticsCalculator combat stats, or unit deployment).
- AgentManager full end-to-end test (assign real policy mission + advance time via TimeManager to trigger signal resolution).
- More events (e.g., secret police backlash dialogue, conscription riot events) or Golden Age synergies for pro-natal/settlement paths.
- Full save/load roundtrip testing in a 10-year sim + any NMM/peace_state side effects.

The system is growing into a robust, interconnected sandbox for demographic strategy, agent influence, economic trust, and military trade-offs.

Keep going? Pick the next (dialogue polish, map hook, combat deeper, or something new). Let's build.

**Remaining high-value / next natural steps** (prioritized for playability and 10-year test):
- ~~More events/dialogues (conscription riot + Golden pro-natal surge)~~ **Advanced** (full branches with do-calls + monthly/Golden triggers).
- ~~Combat deeper + map integration~~ **Advanced** (loyalty + settlement explicit in BattleManager preview/assault + Resolver org/readiness/aftermath; mixed armies + defender settlement bonus; full flow testable via F10 + inspector + assaults on settled provinces).
- ~~Save/load edges~~ **Advanced** (settlement re-apply on map load; roundtrips for policy/erosion/settlement + map mutations).
- AgentManager full polish (real assign + duration for lobby missions; unavailable agents during; add to agent UI).
- Polish + balancing (Cohesion previews in panel, visuals, playtest 10-year scenarios with map + systems).

See new "Questions for Next Iterations" section at the end of this document for structured design input (multiple iterations). User can answer any subset to guide the next build pass.
- Combat/recruitment deeper (use Province modifiers in actual battle calcs or ProductionLine for unit reliability when foreign heavy).
- Full save/load testing + any clear hooks in other managers.
- AgentManager full callback polish if needed (current signal wiring is solid).

We're making strong progress on the high-value list. The systems are becoming a living, savable, effectful part of the grand strategy sandbox.

Continue? Pick the next (e.g. dialogue for fiat crisis, map hook, combat tie-in) or new ideas. Let's keep going.

We're advancing the high-value list toward the 10-year testable scenario. The Policy/Law + agent + loyalty + erosion + visibility layer is now deeply integrated and demo-playable.

**Next natural steps (high value list continuation)**:
- Wiring loyalty multiplier into a concrete combat/recruitment stub (e.g. Province organization modifier or simple combat effectiveness in scripts/combat).
- More printing/sovereign-specific events or a dedicated "fiat_crisis" / "sound_money_recovery" dialogue (extend population_policies or new file; trigger from monthly when trust high).
- Basic manpower/recruitment ties (e.g. foreign % + loyalty affects available "recruits" or production of units).
- Full save/load for demographic_policies, trust_erosion, settled_areas, etc. (via existing SaveLoadManager patterns).
- Polish the Policy screen (make it more persistent or add previews for time-to-effect, Cohesion group reactions).
- Map territory testing hooks (link settled_areas to actual province data or integration resistance when map systems are further along).

Let's keep building and improving. What specific item from this list (or new one) do you want to tackle next? Fire the priority.

---

## Questions for Next Iterations (Multiple Rounds — User Input Requested)

I have continued with the next high-value items from the running list (combat deeper wiring with settlement/loyalty in full assault + resolver flows for mixed armies; extended population_policies.dialogue with conscription_riot_branch + golden_pro_natal_surge + triggers from monthly/Golden; save/load re-apply for settlement_level on map load + roundtrip notes). Map is now a much stronger playtest surface.

Below is a structured, iterated list of questions. Answer any/all (or "none, just keep building X"), and we can iterate in follow-ups. This helps prioritize, add historical flavor, ensure trade-offs/agency, and keep the sandbox fun/powerful without overcomplicating.

### Iteration 1: Priorities & Overall Direction (High-Level)
1. Of the remaining (AgentManager polish, more events/dialogues polish, combat full test with Logistics/aftermath/mixed armies on settled provinces, general polish/balancing, map data scale via generation tools), what 1-2 should we tackle immediately after this pass? Or should we interleave (e.g., one combat + one dialogue per "continue")?
2. For the 10-year testable scenario (1918-1928-ish), what core loop feels most important to "feel" first: combat/assaults with policy effects, supply/logistics on settled map, agent missions actually running + policy shifts, or event chains + Golden triggers?
3. Any new "big integration" you want elevated to critical (e.g., agents on map rings affecting settled provinces, technology unlocks gated by settlement/pro-natal success, or national spirits that directly mutate province settlement_level)?

### Iteration 2: Combat Mechanics & Playability (Deeper Loyalty/Settlement/Mixed Armies)
4. For loyalty/foreign military + settlement in assaults: Should high settlement give a *stronger* defender bonus in the target province (e.g., +org/readiness for local militia or "defending our land")? How visible should the mixed army penalty be in the assault preview (current preview power scaling + resolver org/readiness)? Any specific numbers or historical flavor (e.g., "Roman foederati with citizenship path" vs "Weimar-era foreign legions")?
5. Mixed armies: Currently attacker loyalty scales power; defender can benefit from settlement. Should we model *composition* (e.g., % foreign in the specific formation/division) more explicitly, or keep it national (GameData foreign_military_pct)? How should it interact with Province settlement (e.g., foreign troops in a high-settlement province get extra penalty or assimilation bonus)?
6. Full flow test: With the F10 "Demographic Map Test" + inspector now live, what additional debug/combat test hooks would make playtesting assaults on settled vs non-settled provinces satisfying (e.g., casualty differences, post-battle org recovery, supply interdiction on settled land)?
7. Balancing: High settlement should make provinces "worth defending" and harder to take — but not invincible. Any hard caps or diminishing returns (e.g., max +30-40% effective defense)? How should it interact with existing loyalty (foreign troops hurt settlement bonus)?

### Iteration 3: Events, Dialogues & Narrative (Conscription, Golden, Fiat, etc.)
8. For the new conscription_riot_branch and golden_pro_natal_surge: Do the branches feel right (double-down/exploit vs reform/pivot vs balanced)? Any specific historical alt-history paths to add (e.g., for GER post-1918 harsh peace, or USA/ENG with different cultures)?
9. Triggering: Monthly erosion + Golden now launch dialogues. Should some be "news toasts" first (via LeaderEventUI) with "respond now" button, or always full branching dialogues? How frequent (e.g., conscription only on level 2 + low coh, Golden only once per high Ascendancy)?
10. More content: Want a dedicated "conscription_riot" or "Golden demographic dividend" .dialogue file, or keep extending population_policies? Any other policy events (e.g., women_workforce cultural clash, two-tier justice scandal, sovereign wealth Hidden Hand sabotage attempt)?

### Iteration 4: Agents, Save/Load, Polish, Map Scale & Playtest
11. AgentManager polish: The "lobby_domestic_law" mission exists with duration/policy_shift. Should we add more specific ones (e.g., "promote_pro_natal_campaign", "fortify_border_network")? Real assign test: How important is showing agents "unavailable" in AgentAssignmentScreen during the 6-12mo lobby (with progress bar or ETA)?
12. Save/load: Current roundtrips cover policies/erosion/settlement + map dev/infra. Any specific edge cases to harden first (e.g., reload mid-Golden, after high Trust Erosion + relocation, with active agent missions on policy)?
13. Polish: Cohesion previews in PolicyLawScreen (already dynamic via helpers), better visuals (settlement tint is subtle — want icon or overlay layer?), or TopInfoBar Dir showing "Settled strength: X provinces"?
14. Map scale / full territories: The generation tools (Python phase1 for 350-450 naval-aware provinces) exist. For playtest, should we prioritize running/merging a richer data set into the test scenario now, or keep phase1 small while we test systems? Any specific "full territories" features (sea zones for naval, strategic regions affecting settlement bonuses, more varied dev baselines for relocation targets)?
15. Playtest scenarios: Ready for a 10-year run as e.g. GER (harsh peace + guest labor + later pro-natal pivot) vs USA (pro-natal + skilled + Golden)? What metrics or "fun test" would tell us the sandbox is working (visible trade-offs in one playthrough)?

### Iteration 5: Open Design Ideas (Beyond the List)
16. Any new pillars/systems connections you want prototyped soon (e.g., Mandate directly funding "settlement projects" on map like infra investment, Ascendancy unlocking special "Golden Age provinces" with unique bonuses, or Hidden Hand running "demographic subversion" missions on high-settlement areas)?
17. Historical flavor vs alt-history agency: We're marking HISTORICAL in dialogues and having costly but powerful divergences. Any specific 1918-1930s examples (Weimar hyperinflation, Dawes plan, Turkish National Movement, French pro-natal laws, etc.) to model more deeply in the next events or policies?
18. Anything to de-prioritize or simplify (e.g., "settlement_level on every province is too much — just use dev/infra + settled_areas for now")?

These questions are designed for several iterations — answer what resonates, ignore the rest, or add your own. This keeps us aligned on "fun powerful agency sandbox" while advancing concrete buildable items.

Fire away with answers, new ideas, or "just build combat + one more dialogue next." Let's keep growing and building.

**Iteration 6 (Incorporating your latest feedback – June 2026 continue pass)**:
- Settlement defender: Refined to 2.5% per level (capped 25%), conditional on cohesion/culture per GS best practices (HOI4 situational terrain/fort 15-50% defender favor, Vic3 gradual dev 5-15%, etc.). Fun/flavorful without power creep. Further tweaks?
- New welfare/social policies: Added as requested (abstract elite_optimization for pop control/costs, compassionate_end_of_life for assisted suicide/welfare, expansive_burden for gender/health services creating load). Toasts first + dialogue with clean interactive balance, opposites (savings now vs disaster later), payoffs. Abstract for implementation sanity. Good? More modes or specifics?
- Toasts first: Implemented for welfare crisis (and extensible to others). Clean/fun way: Toast alerts player ("Welfare burden straining..."), then optional full dialogue for choices. How to expand (e.g. always toast + "respond" button leading to branch)?
- Continue remaining + high-value: Agent polish, map scale (fuller territories via gen tools for new policy interactions), polish (welfare in visuals/inspector), expand integrations (welfare hits Province supply, Golden twists, more agent lobbying). Your "yes expand new integrations, refreshing, building" – what next big one (e.g. explicit welfare in Golden "decadent" path, map province burden tint, or something else)?
- Overall: Fine with my decisions? Any de-prioritize (e.g. less abstract, more named policies)?

These questions are designed for several iterations — answer what resonates, ignore the rest, or add your own. This keeps us aligned on "fun powerful agency sandbox" while advancing concrete buildable items.

Fire away with answers, new ideas, or "just build agent polish + one more integration next." Let's keep growing and building.

**Updated Iteration 6 (your feedback June 2026)**: See above detailed incorporation – settlement 2.5% approved, welfare enhanced with exact cultural war / abortion-as-lie / Q-Guidestones / pandemic control / traditional vs woke flavor + tempting trade-offs, toasts with dismiss/respond, agent polish + map full territories setup (all owned provinces, gen tools for 350+), expanded integrations. Playtest Europe loops sooner. Your vision driving the abstraction to show "reality how far we have fallen". 

Next priorities from list: More map gen for full territories (I can run/enhance Python scripts or spool subagents if needed), agent UI polish for welfare lobbies, visuals (burden tint), or specific playtest scenarios. Answer questions below or say "build map gen + agent next".

**Space Race Milestones + 1918 Variations (2026-06-18):** Added per specialist subagent task. process_peace_follow_ons extended with "Versailles Treaty 1919: reparations crisis" (modeled loosely history: harsh exclusion/low leverage -> high grievance/reparations strain/cohesion hit/Hand amp + future radical; alt: high inclusion_leverage or participant seating -> lenient alt with moderated effects + prestige buffer). Uses existing term_choices, get_inclusion_leverage, add_grievance, apply_pillar, post_news. Ties to space as late alt-history extension (1918 ripples affect 1957+ space powers). See GameData.gd process_peace_follow_ons (1919 block) + process_space_race_events (8+ space: milestones firsts via tech Map Leader checks, protest/ethics/secret fleet/exposure/competition/sabotage tied to low coh/Hand/research ethics/secret programs). Updated CURRENT_STATE.md + TestRunner 50T forces (1957+ y/m + tech + calls) + EOA_TEST_SAVE_LOAD + godot sims. All integrated/persisted/evidence logged.