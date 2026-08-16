# Epochs of Ascendancy — Master Completion Plan (No Permanent Deferrals)

**Date:** 2026-07-16 · **Map/default snapshot refreshed:** 2026-08-12 (live board **~3520**, not 8761)  
**Audience:** Producer, implementers, Cursor agents  
**Rule:** Nothing is “deferred forever.” Everything below has a **phase**, **exit criteria**, and **Cursor prompt**. High-cost items are **later phases**, not abandoned.

**Full-test orchestration (preferred for next sessions):** [`GAME_DIRECTOR_PLAN.md`](GAME_DIRECTOR_PLAN.md) · status [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md)  
**Launch bars (L0–L3):** [`LAUNCH_READINESS_PLAN.md`](LAUNCH_READINESS_PLAN.md) — this MASTER file is the multi-month catalogue; launch sequencing starts from human L0 proof, not Phase G0

---

## 0. How to use this document

1. Work **one workstream at a time** (or parallel streams only if they don’t thrash `GameData.gd` / `ScenarioLoader.gd`).
2. Every slice must ship: **pure product or real GD API → pure test → map CI hook when new pure file → dual SCRIPT 0** (or headless domain test).
3. After each phase: update `TODO.md` (checkboxes), `Project_State_Summary.md` (status line), this file (progress table), and `docs/CURRENT_STATE.md` only with a short dated entry.
4. Feed Cursor the **prompt packs in §8** (copy one pack per session; don’t paste the entire doc).
5. For **full-test / world-class play push**, use director phases D1–D4 first; this MASTER file remains the multi-month pillar inventory.

### Quality bar (non-negotiable)

| Bar | Requirement |
|-----|-------------|
| Pure | Tests call shipped product/API paths; no test theater |
| Live | GameData / MapManager / UI apply routes, not formatter-only |
| Dual | `EOA_SCENARIO=world_full` (or relevant pilot) SCRIPT ERROR **0** ×2; `EOA_HEADLESS_EVIDENCE` unset — *CI dual still uses scaffold for speed* |
| Default play | TestRunner default **`world_accurate`** (~3520 GIS post US+RoW sparse); fallback `EOA_SCENARIO=world_full` |
| Honesty | TODO + this plan mark **phase done** vs **phase next**, never “won’t do” |

---

## 1. Current state snapshot

### 1.0 Map / default board (2026-07-19)

| Item | State |
|------|--------|
| **Default TestRunner / F5** | **`world_accurate`** → `provinces_world_accurate` **~3520** (NUTS-3 + US 130 playable + RoW sparse + seas). Historical pre-merge was ~8761 / ~5670. |
| **Scaffold dual board** | `world_full` **2665** via `EOA_SCENARIO=world_full` — IDs never renumbered in place |
| **Map machine gates** | Accurate QC hard_ok · unit tests OK · scaffold pick harnesses green |
| **Content hole** | No `historical_leaders_world_accurate.json` yet (director phase D1) |
| **Director next** | D1 leaders/OOB → D2 vertical war loop on accurate board |

### 1.1 Strengths (landed foundation)

| Pillar | State |
|--------|--------|
| **Map / world_accurate (default)** | ~3520 GIS hybrid (post US+RoW sparse) · shared-edge adj · 100% land ownership 1936 · eras · choke sea/strait |
| **Map / world_full (scaffold)** | ~2665 provinces, NE coastline stamp, ownership eras 1910–2026, hierarchy 4-tier, dual SCRIPT 0 path |
| **Map pilots** | Europe densify 700k · NUTS-3 GIS 710k (1514) · US TIGER 800k · geoBoundaries densify 900k block |
| **Combat / naval / air** | Multi-phase products, close-live ops, air/naval theater products, dual phase evidence |
| **Production** | DesignManager lifecycle + custom templates, factories, OOB, medium-tank honesty + next20 routing to real OOB APIs |
| **Designers** | DomainDesignPopup, module catalog ~1084, multi-domain campaign, register_custom_design |
| **Leaders / HH / agents** | Leader system, HH agenda products, agent missions, dual markers |
| **AI** | Multi-faction strategic AI, daily campaign, SessionPlayers hotseat hinge |
| **Peace / occupation / economy / weather / tech / focus** | Large phase 2–11 product stack + ScenarioLoader dual evidence cascade |
| **Next-20 package** | 20 live steps across OPEN majors #1–#5 with dual `next20_completion_live` |
| **Campaign Alpha primary strip** | Phase 1 playability: 8 live actions · recommended-next · dead_n=0 · dual `campaign_alpha_primary_live` · see `docs/COMPLETION_PLAN.md` |

### 1.2 Structural risks (address in plan, not ignore)

| Risk | Why it matters | Plan phase |
|------|----------------|------------|
| **`GameData.gd` mega-file** (~25k+ lines) | Merge conflicts, hard review, accidental regressions | Phase G0 |
| **Product/day-wave density** | Many “days” vs few playable loops | All phases: prefer vertical play loops |
| **Doc sprawl / staleness** | CURRENT_STATE huge append log; TODO mixes landed + stale “deferred” | Phase G0 + continuous |
| **UI vs dual gap** | Dual proves state machines; HOI-depth UI still thin | Phases C, D, F |
| **Map truth vs playability** | Accurate default live; content/OOB/leaders lag board density | Director D1–D2 · Phase M residual |
| **Netcode / multiplayer** | Hotseat only | Phase N |
| **Perf at ~6k** | Density pilot exists; 60 fps not proven | Phase M |

### 1.3 Pillar health matrix

| Pillar | Playable now | Vertical depth needed | Phase |
|--------|--------------|----------------------|-------|
| Map / GIS | Yes (**world_accurate default** + world_full scaffold + pilots) | Leaders/OOB on accurate · 60 fps @ 8k · residual adj | Director D1–D4 · M3–M5 |
| Combat land | Yes (ops + dual) | Full UI ribbon, AAR, multi-front human control | C1–C3 |
| Naval / fleet | Yes (ops + products) | Multi-day AI autonomy in theater UI | C2, A2 |
| Air | Products + dual | Theater command UI, range/sortie player loop | C3 |
| Production / OOB | Strong | Player OOB screen honesty 60–100d always | P1–P2 |
| Designers | Domain + modules | Chassis/module UX parity land/naval/air/space | D1–D3 |
| Technology / focus | Trees + branching products | Era UX, branch visibility, player research loop | T1–T2 |
| Leaders / HH | Strong data + products | Agenda primary UI, faction filter always-on | L1–L2 |
| Agents / intel | Missions + dual | Campaign AI + counterplay UI | I1–I2 |
| Diplomacy / peace | Conference + multi-party products | Multi-party human conference flow | Di1–Di2 |
| Occupation / manpower | Products + dual | Mapmode + laws UX integrated | O1 |
| Economy / trade | Products | Civilian↔war conversion player loop | E1 |
| Weather / supply | Products + overlays | Always-on impact readability | W1 |
| Save / session | Browser APIs | Primary campaign continuity UX | S1 |
| AI (strategic) | Daily multi-faction | Campaign personality + war goals in UI | A1–A3 |
| Multiplayer | Hotseat foundation | Lobby → sync → netcode → dedicated | N1–N4 |
| Tutorial / UX | Products + **Campaign Alpha primary strip** | First-session mandatory path · 100d dual | U1–U2 |
| Content (OOB/focus/events) | Large data | Era completeness + portrait/event gaps | X1–X2 |
| Graphics / audio | Icons + mapmodes | Asset QA, missing packs, SFX | G1–G2 |
| Engineering / CI | Pure + dual | Split GameData, doc sync, perf budgets | G0, Q1 |

---

## 2. North-star definition of “complete”

A **complete** EOA session (any era 1910–2026):

1. **Choose nation + scenario** → load without SCRIPT ERROR.  
2. **See readable map** (ownership, supply, fronts, occupation) at target density with acceptable FPS.  
3. **Produce equipment** via designers → factories → OOB → fielded units.  
4. **Command land/naval/air** with multi-phase ops the player can understand and reverse.  
5. **Run politics**: HH agenda, leaders, agents, focus, tech for months.  
6. **Fight and settle**: combat → occupation → peace conference with multi-party outcomes.  
7. **AI opponents** act daily across factions without player babysitting.  
8. **Save/resume** mid-campaign cleanly.  
9. **Optional multiplayer**: hotseat first, then networked same rules.  
10. **Docs match reality** (this plan + TODO + summary).

---

## 3. Program roadmap (phased — nothing abandoned)

### Phase G0 — Engineering & documentation hygiene (1–2 weeks)

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| G0.1 | Split `GameData.gd` into domain autoloads or partials (combat/production/designers/ai/map hooks) | Build + dual SCRIPT 0; no behavior drop |
| G0.2 | Single **source-of-truth** status: this file + slim `Project_State_Summary.md` | CURRENT_STATE becomes archive pointer only |
| G0.3 | TODO rewrite: remove contradictory “deferred NUTS” where pilot exists | Grep clean for stale claims |
| G0.4 | CI: pure map suite + dual smoke job documented in TESTING_PLAN | One command path for agents |

### Phase M — Map / GIS / perf (ongoing, parallel)

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| M1 | **NUTS-3 Europe promote path**: id-stable remap table pilot → world_full *or* dual-board load | Documented remap; dual both boards SCRIPT 0 |
| M2 | **US TIGER / admin-2 GIS pilot** (mirror NUTS product pattern) | Pilot dir + scenario + dual |
| M3 | **60 fps measure harness** on density pilot (~4650) and NUTS (~1514) | Logged frame budgets in dual/headless perf mode |
| M4 | **Higher-res coastline / fjord pass** (NE 10m+ or regional meshes) | QC stats; optional overlay; no full renumber |
| M5 | **Membership eras + AI borders** on all pilots | Full eras; mutation dual PASS |

### Phase C — Combat / naval / air play loops

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| C1 | **Combat multi-phase primary UI** (ribbon always in combat context, not F10-only) | Player can approach→engage→disengage without day buttons |
| C2 | **Fleet multi-day autonomy** visible in naval panel (posture→escort→follow) | AI fleets advance without player; player can override |
| C3 | **Air theater player loop** (sortie plan, range, CAS/intercept) | Dual + UI apply; range/fuel honesty |
| C4 | **AAR / battle log** linked to combat outcomes | Readable post-battle; save-friendly |

### Phase P — Production / OOB / industry

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| P1 | **Medium (and general) OOB screen**: 60/100d completion always shown | Uses real OOB APIs (already next20-routed) |
| P2 | **Factory risk + retool UI** on assignment screen | Player-visible retool days/similarity |
| P3 | **Civilian ↔ war economy conversion** player controls | Stockpile + conversion live |
| P4 | **Layered production per line** (mass/auto/additive/nano) full UI | Per-line state persist + trades |

### Phase D — Designers (all domains to HOI-class usability)

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| D1 | Land chassis/module designer parity with DomainDesignPopup depth | Freeze→register→seed always |
| D2 | Naval + air designer slots from full catalog | Real modules, stats, icons |
| D3 | Space designer non-sim stats (use DesignManager/doctrine) | Live compute not fake numbers |
| D4 | Design picker: obsolete/used/foreign full UX | DesignManager API only |

### Phase T — Technology / focus

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| T1 | Research queue UI with branch locks + resource gates | Player loop for 12+ months |
| T2 | Focus tree playable for majors (GER/FRA/ENG/USA/SOV/JAP + era stubs filled) | No empty major trees in 1936/1918 |
| T3 | Ethics/backlash events for risky tech fully UI-driven | Dialogue + cohesion effects |

### Phase L — Leaders / Hidden Hand

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| L1 | **HH multi-month agenda as primary screen** (faction filter, commit, counterplay) | Not dual-only |
| L2 | Leader assignment + theater command integrated map markers | Station/OOB link |
| L3 | Mortality/timeline events content complete for 1918/1936 | Data + portraits gaps closed |

### Phase I — Agents / intel

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| I1 | Agent network map + mission board primary UI | Dispatch→resolve→toast |
| I2 | Pre-battle intel impact always in combat estimate | Sabotage/recon bias visible |
| I3 | Counter-intel / sweep campaign AI for non-player tags | Dual + AI daily |

### Phase Di — Diplomacy / peace

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| Di1 | Multi-party peace conference **human** flow | Claim/cede/puppet live |
| Di2 | Alliance / guarantee / war goal UI from strategic products | Player can justify & declare |
| Di3 | 1918 / modern treaty spirits persist & display | NationalSpirit UI |

### Phase O / E / W — Occupation, economy, weather

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| O1 | Occupation mapmode + laws + garrison player controls | Resistance/compliance readable |
| O2 | Manpower cohorts / laws / training full UI | Draft→train→reinforce loop |
| E1 | Trade / sealane / convoy player interventions | Interdict + escort choices |
| W1 | Weather forecast chip always on theater ops | Move cost + combat mult shown |

### Phase S — Save / session / tutorial

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| S1 | Save browser primary UX (list/resume/checkpoint) | Uses existing live APIs |
| S2 | Autosave policy + crash recovery | Documented + tested |
| U1 | Tutorial first session forced for new profiles | Checkpoint trail |
| U2 | Hotkeys / command polish complete | UX product close |

### Phase A — Strategic AI (full campaign, not board-only)

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| A1 | Daily AI for all non-human tags (production/supply/focus/war) | SessionPlayers + dual |
| A2 | Fleet + land multi-day autonomy under war goals | Observable behavior |
| A3 | Personality + alliance AI drive events | Faction products live |
| A4 | Difficulty / historical vs sandbox AI presets | Data-driven |

### Phase N — Multiplayer (full path — not “deferred”)

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| N1 | Hotseat polish (UI turn banner, lock non-active) | SessionPlayers complete |
| N2 | Same-machine async slots + command journal replay | Deterministic sim seed |
| N3 | **Networked multiplayer** (ENet/WebRTC or custom): lobby, join, lockstep or state sync | 2-player scenario dual/smoke |
| N4 | Dedicated server headless + reconnect | Document ops; CI smoke optional |

### Phase X — Content completeness

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| X1 | Historical OOB 1910/1918/1936/2026 for all majors | Load + equip dual |
| X2 | Event chains per era (crisis, peace follow-on, biotech/space ethics) | Fire in 50T sims |
| X3 | Leader portraits remaining gaps closed | Manifest 100% wired |
| X4 | Unit templates / modules icons complete for referenced IDs | fill tool + audit |

### Phase G — Graphics / audio / feel

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| G1 | Mapmode pack polish (occupation, supply, battle, naval/air) | Player-visible keys |
| G2 | SFX pack integration (combat, UI, events) | Optional mute; no spam |
| G3 | Unit counters / NATO LOD consistency | Zoom budgets |

### Phase Q — Quality / balance / release

| ID | Deliverable | Exit criteria |
|----|-------------|----------------|
| Q1 | 50T integrated sim PASS validators modernized | tools/validate_* green |
| Q2 | Balance pass (combat/supply/economy/tech) | Documented patches |
| Q3 | Release candidate: README play path + known issues | Version tag |

---

## 4. Suggested sequencing (critical path)

```
G0 (split GameData + docs) ──┬──► M1–M3 (map promote + FPS)
                             ├──► C1 + P1 + S1 + L1 (player-visible majors)
                             ├──► D1–D2 (designers usable)
                             └──► A1–A2 (AI daily + fleet)
                                      │
                                      ▼
                         Di1 + O1 + E1 + T1 (politics/war economy)
                                      │
                                      ▼
                         N1 → N2 → N3 → N4 (multiplayer ladder)
                                      │
                                      ▼
                         X* + G* + Q* (content, polish, RC)
```

**Parallelism:** Map (M) and Content (X) can run beside combat/UI. Multiplayer (N) starts after sim seed determinism (N2 depends on pure command journal).

---

## 5. Workstream packages (what “done” looks like per stream)

### Stream α — Player command loop
C1, C2, C3, P1, P2, L1, S1, U1  
**Done when:** New player can produce a medium tank, design a variant, field it, fight multi-phase, save/resume without F10.

### Stream β — Living campaign
A1–A3, Di1–Di2, O1–O2, I1–I2, T1–T2, W1, E1  
**Done when:** 12 in-game months AI war with occupation, peace, tech/focus, weather mattering.

### Stream γ — World map truth
M1–M5, G1, Q1  
**Done when:** Europe NUTS path promotable; FPS measured; membership eras solid.

### Stream δ — Multiplayer
N1–N4  
**Done when:** 2 humans on LAN complete a short scenario with same rules as SP.

### Stream ε — Designers & industry depth
D1–D4, P3–P4, X4  
**Done when:** All four domains design→produce→field without dual-only stubs.

---

## 6. Documentation update plan

| Document | Action |
|----------|--------|
| **docs/MASTER_COMPLETION_PLAN.md** | **This file** — keep as program plan; update phase tables when done |
| **TODO.md** | Strip stale “NUTS deferred”; add phase IDs; check off next20; link here |
| **Project_State_Summary.md** | Replace long historical dump with: Current pillars table + link to this plan + last dual date |
| **Next_30_Days_Roadmap.md** | Rewrite as rolling 30-day slice of phases G0+α (not parallel old next-280 lists) |
| **docs/CURRENT_STATE.md** | Add banner: *Archive / session log. Do not use as roadmap.* Point to Master Plan |
| **README.md** | Play path, Cursor open path, dual/CI one-liners, link Master Plan |
| **docs/TESTING_PLAN.md** | Canonical dual + pure + 50T commands; next20 + nuts3 + quality markers |
| **docs/MAP_HIERARCHY_AND_GIS_ROADMAP.md** | Mark NUTS pilot **landed**; next = promote + FPS + US GIS |
| **docs/DESIGN_LIFECYCLE_SYSTEM.md** | Sync with register_custom_design + runtime templates |
| **GAME_STATUS_ASSESSMENT.md** | One-page traffic light aligned to pillar matrix §1.3 |
| **.cursorrules** | Point agents at Master Plan + dual bar + no permanent deferrals |

---

## 7. Metrics dashboard (track weekly)

| Metric | Target |
|--------|--------|
| Dual world_full SCRIPT ERROR | 0 |
| Dual pilot SCRIPT ERROR (NUTS / density) | 0 |
| Pure map CI | green |
| OPEN major UI reachable without F10 | 5/5 |
| Mean FPS at density pilot (measured) | ≥30 (stretch 60) |
| Custom design → production without Unknown template | 100% |
| Multiplayer: hotseat turns / networked match | N1 then N3 |
| Doc freshness (Master Plan + TODO + Summary same week) | yes |

---

## 8. Cursor prompt packs (feed these to Cursor)

Copy **one pack per Cursor chat**. Replace `{SCRATCH}` with a real path if needed.

### Pack A — Always prepend

```
You are working on Epochs of Ascendancy (Godot 4.7) at /home/mikef/Projects/epochs-of-ascendancy.

Rules:
- Read docs/MASTER_COMPLETION_PLAN.md for program context.
- Prefer vertical playable slices over new day-catalogue stubs.
- Ship: pure product and/or real GameData/MapManager/UI APIs + pure tests + map CI hook if new pure file.
- Dual: EOA_SCENARIO=world_full tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 90 with EOA_HEADLESS_EVIDENCE unset; SCRIPT ERROR 0 twice.
- Do not renumber world_full province IDs.
- Do not claim complete without tests driving shipped code (no test theater).
- Update TODO.md honesty for what you closed.
```

### Pack B — GameData split (G0.1)

```
{Pack A}

Task: Split scripts/autoload/GameData.gd into maintainable domain modules without behavior regression.
- Extract cohesive regions (e.g. designer_duties, next20, completion_playability, membership, occupation) into scripts/autoload/ partials or new Node autoloads registered in project.godot.
- Keep public method names stable so ScenarioLoader/UI keep working.
- Prove: pure tests that grepped those APIs still pass; dual world_full SCRIPT 0.
```

### Pack C — Combat UI primary (C1)

```
{Pack A}

Task: Make multi-phase combat the primary player path (not dual-only / F10-only).
- Wire OrderCommandPanel / combat UI to apply_combat_ops_close_live and multi-phase products with visible ribbon approach→engage→disengage.
- Ensure keyboard/mouse path from selected province to phase advance.
- Dual marker still PASS; add pure test if new product helpers land.
```

### Pack D — Fleet multi-day autonomy UI (C2 / A2)

```
{Pack A}

Task: Surface fleet multi-day autonomy (posture→station/escort→follow-through) in naval UI and AI daily path.
- Reuse fleet_multi_day_autonomy_product and naval ops close live.
- Non-human SessionPlayers tags should advance fleet steps on daily tick.
- Dual SCRIPT 0; document marker if new.
```

### Pack E — OOB honesty UI (P1)

```
{Pack A}

Task: Production/OOB UI must show 60d/100d medium (and general) completion using apply_oob_horizon_60d / apply_oob_horizon_100d / apply_medium_tank_oob_product — never fake numbers.
- ProductionAssignmentScreen or dedicated OOB panel.
- Dual medium_tank / next20 markers remain green.
```

### Pack F — HH agenda primary screen (L1)

```
{Pack A}

Task: HH multi-month agenda as a primary TopInfoBar/screen: faction filter, monthly commit, quarterly counterplay.
- Use apply_hh_agenda_close_live / hh products; persist trail in peace_state.
- Dual completion + next20 still PASS.
```

### Pack G — Save browser primary (S1)

```
{Pack A}

Task: Save browser list/resume/checkpoint as primary UX via save_browser_campaign_product_live, apply_save_browser_resume, apply_save_browser_checkpoint only.
- No apply_focus for save steps.
- Dual next20 save routing tests remain green.
```

### Pack H — NUTS promote (M1)

```
{Pack A}

Task: Design and implement id-stable promote/remap from provinces_pilot_europe_nuts3 (710000+) toward playable Europe on world_full OR seamless dual-board scenario switch.
- Never renumber existing world_full IDs without remap table.
- Dual nuts3 + world_full SCRIPT 0.
- Update MAP_HIERARCHY_AND_GIS_ROADMAP.md.
```

### Pack I — 60 fps measure (M3)

```
{Pack A}

Task: Implement measurable FPS/frame-time harness for density pilot and NUTS pilot (EOA_MAP_PERF or similar).
- Log budgets under SCRATCH; document in MAP_RENDERER_PERF.md.
- Dual or headless perf run without SCRIPT ERROR.
```

### Pack J — Designers HOI depth (D1–D3)

```
{Pack A}

Task: Deepen DomainDesignPopup + DesignManager for land/naval/air/space: real module catalog stats, doctrine, freeze→register_custom_design→seed production.
- No simulated-only stats for space if DesignManager can compute.
- Dual full_designer_duties + quality_gap_close PASS.
```

### Pack K — Strategic AI campaign (A1–A3)

```
{Pack A}

Task: Expand multi_faction / strategic_ai_daily so every non-human tag runs meaningful daily packages (prod, supply, focus, war goal, fleet).
- Integrate SessionPlayers.
- Dual strategic_ai_multi_faction_daily + next20 PASS.
```

### Pack L — Multiplayer ladder (N1–N3)

```
{Pack A}

Task: (1) Hotseat UI turn lock. (2) Command journal determinism. (3) Prototype networked 2-player lobby using Godot multiplayer API with same command journal.
- Start N1 if network not ready; do not stop at "deferred forever".
- Tests for journal replay pure; dual SP still SCRIPT 0.
```

### Pack M — Docs sync (G0.2 / G0.3)

```
{Pack A}

Task: Sync documentation to MASTER_COMPLETION_PLAN.md:
- TODO.md: remove stale deferred lines that contradict landed work (NUTS pilot, designers slices).
- Project_State_Summary.md: slim pillar table + link Master Plan.
- README.md: play + dual + Cursor open instructions.
- CURRENT_STATE.md: archive banner at top.
Do not invent features; only align docs to code.
```

### Pack N — Content / events (X1–X2)

```
{Pack A}

Task: Fill era content gaps for 1910/1918/1936: focus trees for majors, OOB seeds, crisis events with player dialogue.
- Exercise in headless 50T or dual evidence prints.
- No silent stubs for major tags in primary scenarios.
```

---

## 8b. Super-prompt (paste if you want Cursor to self-drive a whole phase)

```
Read docs/MASTER_COMPLETION_PLAN.md. Execute the highest incomplete phase on the critical path (prefer G0 if GameData still monolith, else Stream α items C1/P1/S1/L1). Ship vertical slices with pure tests + dual SCRIPT 0. Update TODO.md and the progress table in MASTER_COMPLETION_PLAN.md. Do not permanently defer any pillar—if blocked, leave a phased sub-task with concrete next API names.
```

---

## 9. Progress table (update as phases complete)

| Phase | Status | Last dual / note |
|-------|--------|------------------|
| G0 Engineering/docs | **Partial + primary-package domains dual green** | Residual depth + continue: PackNContent · HoiFullscreen · Q1RcChecklist · CombatEngineDepth · prior narrative/screen/preflight; full engine rewrite still open |
| M Map/GIS/FPS | **Partial + M3 measured + density pilot dual green** | world_full measured path + **`map_perf_density_pilot_live=1 pilot=density measured≥1 measured_ok=true source=performance_monitor`** on global density board dual×2 |
| C Combat/naval/air UI | **Partial + α/C2/C3/C4 + front + air multi-phase + fleet multi-day dual green** | C1–C4 · **C3 air theater (AirTheaterDomain)** · FC domain · **`air_multi_phase_primary_live=1`** (AirMultiPhaseDomain) · **`fleet_multi_day_primary_live=1 majors_ok=5`** (FleetMultiDayDomain) product·posture·escort·follow·sequence |
| P Production/OOB UI | **Partial + resource stack + trade/relations ledger dual green** | resource packages · **`trade_relations_primary_live`** (SUU valuation · RelationsManager CRS · AI flags · tariff policy hooks; Trade Desk UI R5 next) |
| D Designers | **Partial + D1 + designer depth dual green** | D1 suite (DesignerSuiteDomain) · **`designer_depth_primary_live=1 majors_ok=5`** (DesignerDepthDomain) module·board·stats·multi·close |
| T Tech/focus | **Partial + T1 + T2 + TRC + FWP dual green** | T1 research queue · T2 FocusTreeDomain · **`tech_research_primary_live=1`** (TechResearchDomain) · **`focus_war_path_primary_live=1`** (FocusWarPathDomain) |
| L Leaders/HH UI | **Partial + L1 + L2 + HH multi-month dual green** | Stream α L1 HH (**StreamAlphaDomain**) · **L2 `leader_theater_primary_live=1 majors_ok=5`** · **`hh_multi_month_primary_live=1 majors_ok=5`** (HhMultiMonthDomain) product·trail·brief·sequence·close |
| I Agents/intel UI | **Partial + I1 + I2 + I2b + I3 dual green** | I1 agent · I2 network (via **IntelNetworkDomain**) · I2b estimate impact · **I3 `intel_counter_primary_live=1 majors_ok=5`** counterintel·sweep·counterplay·close |
| Di Diplomacy/peace UI | **Partial + Di1 + Di2 dual green** | Di1 peace conference · **Di2 `war_goal_alliance_primary_live=1 majors_ok=5`** board·justify·execute·guarantee·close |
| O/E/W Occupation/econ/weather UI | **Partial + O1 + O2 + E1 + E2 + W1 dual green** | O1 occupation · O2 manpower · E1 war economy · **E2 `convoy_sealane_primary_live=1 majors_ok=5`** · logistics supply · W1 weather |
| S Save/tutorial UI | **Partial + S1 + S2 + U1 + U2 + inspector + HOI panel/screen/fullscreen dual green** | S1/S2 · UX · inspector · hoi_panel/screen · **`hoi_fullscreen_primary_live=1 majors_ok=5`** (HoiFullscreenDomain) compact·inspector·apply·polish·close |
| A Strategic AI | **Partial + A3 + A4 + multi-front + CAM + AID dual green** | A3 multi-faction AI · A4 personality · multi_front · CAM · **`ai_difficulty_primary_live=1 majors_ok=5`** (AiDifficultyDomain) catalog·easy·normal·hard·close |
| N Multiplayer | **N1–N4 dual green** | Hotseat · journal · N3 lockstep · **`n4_dedicated_primary_live=1 dedicated_server_ready=true`** (host·client·reconnect) · ops doc |
| X Content | **Partial + X1 + Pack N era/events/narrative/content dual green** | X1 · era · events · narrative · **`pack_n_content_primary_live=1 majors_ok=5`** (PackNContentDomain) event_day·catalog·war_step·ops·close |
| G Graphics/audio | **Partial** | icons/mapmodes |
| Q Release | **Partial + balance + Q1 validator + checklist + RC dual green** | balance · q1_validator · q1_checklist · **`q1_rc_checklist_primary_live=1 majors_ok=5`** (Q1RcChecklistDomain) balance·sample·prove100·variance·close · full ship checklist still open |

**Launch dual markers (SCRIPT ERROR 0 on world_full):** prior set + **`balance_combat_supply_primary_live=1`** · **`fleet_multi_day_primary_live=1`** · AMP/INS + prior  
**Sprint 2026-07-16 dual proofs (BAL/FMD/G0):** `/tmp/grok-goal-sprint-af/implementer/dual/dual1.log` + `dual2.log`  
**Still open:** deeper combat/production **implementation** phases CP1–CP6 (`docs/COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md` CP0 direction dual green · `combat_production_design_primary_live`) · full 3D/HOI suite redesign · Pack N narrative content fill beyond packages · full Q1/RC ship checklist modernization

---

## 10. Immediate 14-day sprint (recommended start)

| Day | Focus | Pack |
|-----|--------|------|
| 1–2 | G0.2–G0.3 docs sync + TODO cleanup | M |
| 3–5 | C1 combat ribbon primary UI | C |
| 6–7 | P1 OOB 60/100d panel | E |
| 8–9 | L1 HH agenda screen | F |
| 10–11 | S1 save browser primary | G |
| 12–13 | M3 FPS harness on density pilot | I |
| 14 | Dual world_full + density + docs checkpoint | A + M |

---

## 11. What you should give Cursor every session

1. **Pack A** (always).  
2. **One task pack** (B–N).  
3. Optional: `git status` + “do not renumber world_full”.  
4. After Cursor finishes: run dual yourself or ask Cursor to run dual and paste SCRIPT ERROR count + new markers.

---

*This plan supersedes “permanent deferral” language for multiplayer, full designers, and full GIS. Those are Phases N, D, and M—not “won’t do.”*
