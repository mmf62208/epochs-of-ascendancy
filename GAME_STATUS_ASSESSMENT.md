Catalogue labels: phase2 · phase3 · battle indicator · supply flow · map_phase23 · world_class_map

Catalogue labels: campaign alpha · primary strip · phase1_alpha · playability

Catalogue labels: map gap · occupation overlay · signal graph · map_gap_closure · phase1_gap · world_class_map · MapRenderer


Catalogue labels: major #56 · major #57 · major #58 · alliance · personality · revolt network · phase11_depth · world_class_gs · diplomacy · campaign_ai · occupation
# Epochs of Ascendancy — Full Game Status Assessment

> **2026-07-19:** Prefer **[`docs/GAME_STATUS_SNAPSHOT.md`](docs/GAME_STATUS_SNAPSHOT.md)** for live default-board truth and **[`docs/GAME_DIRECTOR_PLAN.md`](docs/GAME_DIRECTOR_PLAN.md)** for phased full-test work. This file remains the **long catalogue** of dual majors / residual history.
>
> **Updated 2026-07-17 Combat/production + reinforce + map logistics cycle** — CP0–CP6 · RF0–RF6 dual-green · EquipmentFlow map glyphs with LOD + KEY_I toggle · AI logistics doctrine in strategic AI daily apply · duals `map_flow_lod_primary_live` · `ai_logistics_day_primary_live`. **Playtest guide:** [`docs/PLAYTEST_AND_DECISION_GUIDE.md`](docs/PLAYTEST_AND_DECISION_GUIDE.md).  
>
> **Updated 2026-07-15 Campaign Alpha Phase 1: primary command strip** — top 8 live actions · recommended-next · dead audit · majors collapsed · dual `campaign_alpha_primary_live`. See `docs/COMPLETION_PLAN.md`.
>
> **Updated 2026-07-13 Phase 11 WORLD-CLASS GS DEPTH COMPLETE: Majors #56 Alliance guarantee network · #57 Faction personality AI · #58 Occupation revolt network + Next-470 (12). Dual marker: `phase11_depth_live`. Product majors **58**. PI through **163** (alpha strip). Deepens diplomacy, campaign AI personality, multi-province occupation.
>
> **Also Phase 10 WORLD-CLASS GS COMPLETE: Majors #53 Strategic war goals · #54 Multi-front campaign AI · #55 Grand strategy cycle + Next-460 (12). Dual marker: `phase10_gs_live`. Product majors **58**. PI through **162**. Campaign AI war-goal depth closed.

> **Prev Phase 9:**** Majors #50 Weather crisis · #51 Intel cell network · #52 Leader theater command + Next-450 (12). Dual marker: `phase9_cycle_live`. Product majors **52**. PI through **156**. Weather→intel→leaders ops cycle closed.

**Date:** 2026-07-17 (catalogue) · **Board snapshot:** 2026-07-19  
**Engine:** Godot 4.7.1 · **Default play board:** `world_accurate` **~3520** · **CI dual scaffold:** `world_full` **2665**  
**Quality bar (held):** dual world_full ×2 for SCRIPT 0 smoke · accurate map QC + unit tests · residual pure→live→dual honesty  
**Ground truth for landed duals:** root `TODO.md` (wins over older “deferred” language in this file when they conflict)

---

## 1. Executive summary

EOA has a **playable world-scale map spine** and a **vertical product catalogue** covering most grand-strategy domains at “first product slice” depth. Phase 2 ships live occupation resistance/compliance, manpower laws/training pipeline, and peace conference settlement with dual `phase2_conquest_live` proof.

**2026-07 combat/production cycle (landed):** identity-weighted production scale freeze · EquipmentFlow ledger (create/interdict/deliver) · stock→reinforce · non-instant logistics with hub/era/resource time · formation combat experience dilution · training policies · munitions/drone categories · combat munitions consume · map flow glyphs with zoom LOD and independent toggle · AI logistics doctrine on strategic AI daily apply · optional deep combat path. Design freezes: `docs/COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md`, `docs/REINFORCEMENT_EXPERIENCE_LOGISTICS_DESIGN_FREEZE.md`.

The game is **not** HOI4-complete. Duals prove **hooks and integrity**, not campaign balance or first-session polish. Multiplayer is **no longer “none”**: N3 lockstep + N4 dedicated duals exist as a **netcode foothold** (not a finished multiplayer product). Space residual (colony→discovery/matchmaking) is a **first product slice**, not Terra Invicta depth.

What *is* shipped is a coherent recommend → execute → apply-queue → integrity loop across combat, fleet, economy, weather, intel, logistics, diplo, tech, AI, leaders, occupation, manpower laws, peace, **plus** a real production→flow→front story path.

**Rough maturity (honest) — 2026-07-17:**

| Layer | Maturity | Notes |
|-------|----------|--------|
| Map / GIS / world_accurate (default) | **High** | ~3520 GIS hybrid (post US+RoW sparse) · TestRunner default · QC dual-green |
| Map / GIS / world_full (scaffold) | **High** | 2665 dual SCRIPT 0 · pick harness samples · EquipmentFlow LOD + KEY_I |
| Day-package composition | **High** | next-10…next-470 waves |
| Product majors (UI spines) | **High** | 55+ vertical products, panel + PI |
| Live simulation depth | **Medium–High** | OOB + medium@100d + apply_queue + phase duals + CP/RF duals |
| Production / EquipmentFlow | **Medium–High** | Architecture dual-green; **play feel needs playtest cycle** |
| Reinforce / XP / training | **Medium** | RF0–RF6 duals; balance unproven over long campaigns |
| Designers / tech trees | **Medium–High** | Full designers #47–#49 (large module catalog) + research/branching |
| Air / naval theater | **Medium** | Multi-phase theater live on first-slice spines |
| Full gameplay cycle | **Medium–High** | Weather/intel/leaders + war goals/multi-front/GS cycle |
| Campaign AI | **Medium** | Multi-faction + daily board/budget/apply + **logistics doctrine leaf**; not HOI-class opponent |
| Space residual | **Medium-Low** | Orbital compact ledger ladder dual-green; keep as pressure layer |
| Multiplayer | **Low–Medium** | **N3/N4 dual foothold** · not product multiplayer · not “deferred forever” |
| Ship-ready “world class” | **In progress** | Strong foundation; **playtest + balance + visibility** is the next cycle |

---

## 2. What has been done (catalogue)


## 1.1 Combat / production / logistics residual (2026-07) — dual-landed

Design freezes (direction locked):

- `docs/COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md` — hybrid scale · EquipmentFlow · CP0–CP6  
- `docs/REINFORCEMENT_EXPERIENCE_LOGISTICS_DESIGN_FREEZE.md` — non-instant reinforce · XP · policy · RF0–RF6  

| Package | Dual marker (ok=true when green) |
|---------|-----------------------------------|
| CP1 EquipmentFlow | `equipment_flow_primary_live` |
| CP2 stock→reinforce | `equipment_stock_reinforce_primary_live` |
| RF1 time/XP/hub | `reinforcement_logistics_primary_live` |
| RF2–RF4 depth | `reinforcement_depth_primary_live` |
| RF5 story plains | `reinforce_story_primary_live` |
| RF6 AI training policy | `ai_training_policy_primary_live` |
| CP3 symbols / paint / LOD | `equipment_flow_symbols_primary_live` · `equipment_flow_paint_primary_live` · `map_flow_lod_primary_live` |
| CP4 munitions/drone | `munitions_drone_primary_live` |
| CP5 combat consume | `combat_consume_primary_live` |
| CP6 deep + logistics API | `combat_depth_primary_live` |
| AI logistics in daily AI | `ai_logistics_day_primary_live` |

**Honesty:** Dual green ≠ campaign-balanced. Use playtest guide for human criteria.

**Map keys:** **U** supply/sealane flow · **I** EquipmentFlow glyphs (LOD-aware).

**Next cycle:** freeze new residual packages; play · balance · visibility. See playtest guide §0 and §8.

---

### 2.1 Map & data
- [x] Full-world province set **2665** (`data/provinces_world_full`)
- [x] Natural Earth GIS full stamp (id-stable; map CI geometry gates)
- [x] Scenario load, adjacency, MapPickGrid, MapManager live map
- [x] Industry bootstrap + formation equip on scenario load
- [x] Daily production stockpile evidence (`EOA_OOB_EVIDENCE_DAYS=20`) → majors_grew=7/7

### 2.2 Product majors (52 vertical spines)
Each: pure Python → MapPolishFormatters → MapManager live/apply → GameData routes → OrderCommandPanel → ProvinceInsight chips (priority/always-on for top products) → unit tests → CI hooks → dual evidence.

Phase 10 tops: **#53 Strategic war goals (157)** · **#54 Multi-front campaign AI (158)** · **#55 Grand strategy cycle (159)** · dual `phase10_gs_live`.  
Phase 9 still green: **#50–#52** · dual `phase9_cycle_live`. Phases 1–8 dual markers green.

Catalogue banners (skeptic/plain-text): major #53 · major #54 · major #55 · strategic war · multi-front · grand strategy · phase10_gs · world_class_gs · war_goal · campaign_ai · major #50 · major #51 · major #52 · weather crisis · intel cell · leader theater · phase9_cycle · full gameplay cycle · weather · intel · leader · major #47 · major #48 · major #49 · designer module editor · designer stats · full designers · full designers complete · real catalog 1084 · phase8_designers · multi-domain · modules · field · major #44 · major #45 · major #46 · air multi-phase theater · naval search · war economy conversion · phase7_depth · air · naval · economy · major #41 · major #42 · major #43 · tutorial first-session · focus tree content · balance combat · phase6_depth · tutorial · focus · supply · major #38 · major #39 · major #40 · historical oob · tech tree branching · save/resume · continuity · content · branch · phase5_depth · major #35 · major #36 · major #37 · phase4_depth · major #27 · major #28 · medium-tank production honesty · medium honesty · medium_tank_complete · apply-queue live managers · apply queue live · apply_queue_live · phase1_honesty

| # | Product | Spine |
|---|---------|--------|
| 1 | Multi-phase combat | approach → engage → disengage |
| 2 | Fleet multi-day autonomy | posture → station/escort → follow-through |
| 3 | Medium-tank OOB | 60/80/100d equip horizons |
| 4 | Save browser campaign | resume → checkpoint |
| 5 | HH multi-month agenda | trail → brief → counterplay |
| 6 | Agent campaign | board → dispatch → counterplay |
| 7 | Inspector decision | primary → collapse → apply |
| 8 | Theater command | scan → rank → execute |
| 9 | Multi-faction strategic AI | scan → rank → execute |
| 10 | Designer suite | catalog → pick → seed |
| 11 | Strategic AI daily | board → budget → apply |
| 12 | Play session campaign | brief → execute → resolve |
| 13 | Air ops campaign | sortie → weather gate → air-land |
| 14 | Focus war path | pick → path → commit |
| 15 | Naval multi-phase | posture → escort → strike |
| 16 | Diplomacy peace | board → leverage → settle |
| 17 | Tech research | catalog → priority → field |
| 18 | Logistics supply theater | route → sustain → readiness |
| 19 | Intelligence network | coverage → counterintel → counterplay |
| 20 | World-class campaign command | scan domains → rank → execute top |
| 21 | War economy mobilization | board → allocate → sustain |
| 22 | Weather theater ops | pressure → gate → crisis |
| 23 | Front continuity | combat → assault → sustain |
| 24 | Occupation control | control → garrison → integrate |
| 25 | Manpower reinforcement | draft → reinforce → field |
| 26 | Leader command | assign → station → command |

### 2.3 Day-package depth waves
- **next-10 … next-350** pure modules (~35 wave files) composing multi-system days
- Pattern: advanced steps + joint days + close gates (20 packages / wave for recent majors)

### 2.4 UI / player surfaces
- OrderCommandPanel multi-section apply (orders, combat, fleet, HH, agent, industry, saves, day sections)
- ProvinceInsight chip budget with product priority band (majors up to priority **159**)
- Save/load managers, time, production autoloads

### 2.5 Verification discipline (held)
- Pure unit tests on real helpers (no fake theaters)
- Dual headless world_full ×2 without `EOA_HEADLESS_EVIDENCE=1`
- Evidence trails under `/tmp/eoa-major*` SCRATCH dirs

---

## 3. What still needs to be completed

### 3.1 Still deferred (high cost / thin foundation)
| Item | Why open | First next slice (when opened) |
|------|----------|--------------------------------|
| **Multiplayer** | N3/N4 dual foothold (lockstep/dedicated) | Product lobby/playable co-op session still open |
| **Full HOI4 designers suite** | #47–#49 live · real **1084** module catalog · domain option boards · module icons | Richer per-module UI polish + more historical skin variants |
| **Full tech trees** | Product #17 first slice | Branching trees + year/scenario gates |
| **Full campaign AI** | Depth #53–#55 + **#57 personality AI** live | Broader multi-faction event chains / personality content |
| **Full multi-phase naval/air** | Depth products #44–#45 live; full carrier/ASW sim later | Carrier air packages · multi-sea-zone campaigns |
| **Deep occupation simulation** | major #29 + #35 + **#58 revolt network** live | Event-driven revolt campaigns / occupation law depth |
| **Deep manpower/conscription** | major #30 + #36 cohort/reserve live | Multi-nation pool sync / age mortality |
| **Peace conference settlement** | major #31 + #37 multi-party live | Full interactive multi-party conference UX |
| **Space domain** | Design hooks only | Orbital projects product |
| **GPU pan/zoom world-class** | Profile hooks only | LOD + chunk streaming polish |

### 3.2 Open quality / depth work (not deferred, high value)
1. **Medium-tank multi-month honesty** — **DONE** major #27 · medium_tank_complete@100d dual
2. **Product UX polish** — **DONE** major #32 (compact board · top-8 chips · hotkeys 1–8)
3. **Live mutation depth** — **DONE** major #28 apply_queue_live=6/6
4. **Save/resume campaign continuity** — **DONE** major #40 checkpoint/save/resume
5. **Tutorial / first-session path** — **DONE** major #41 brief/guide/checkpoint · dual phase6_depth_live
6. **Content** — historical OOBs **DONE** #38; focus tables **DONE** #42; leader portraits ongoing
7. **Performance** — world_full graphical LOD, overlay budgets, headless vs graphical parity checks
8. **Balance pass** — **DONE** major #43 estimate/sample/variance band · dual phase6_depth_live

### 3.3 Recommended next build targets (priority order)
| Priority | Target | Outcome |
|----------|--------|---------|
| ~~P0~~ | Medium OOB 60–100d evidence | **DONE** medium_tank_complete=5 @100d |
| ~~P0~~ | Apply-queue → live managers audit | **DONE** apply_queue_live=6/6 |
| ~~P1~~ | Occupation depth (resistance/compliance) | **DONE** major #29 + phase2_conquest_live |
| ~~P1~~ | Manpower laws + training pipeline | **DONE** major #30 live ticks |
| ~~P1~~ | Peace conference settlement | **DONE** major #31 live settle |
| ~~P0~~ | Product UX polish (collapse day overload) | **DONE** major #32 + phase3_depth_live |
| ~~P1~~ | Designer suite domain UIs | **DONE** major #33 live seed |
| ~~P1~~ | Campaign AI multi-month | **DONE** major #34 weekly live |
| ~~P1~~ | Deeper revolt / cohort sim | **DONE** majors #35–#36 + phase4_depth_live |
| ~~P1~~ | Full multi-party peace conference UX | **DONE** major #37 multi-party settle |
| ~~P1~~ | Tutorial / first-session path | **DONE** major #41 + phase6_depth_live |
| ~~P1~~ | Focus tree content tables | **DONE** major #42 live commit |
| ~~P1~~ | Balance combat/supply honesty | **DONE** major #43 variance band |
| ~~P0~~ | Content / historical OOBs + focus tables | **DONE** major #38 + phase5_depth_live |
| ~~P1~~ | Tech tree branching depth | **DONE** major #39 year-gated branches |
| ~~P1~~ | Save/resume campaign continuity | **DONE** major #40 checkpoint/save/resume |
| ~~P1~~ | Air multi-phase theater depth | **DONE** major #44 + phase7_depth_live |
| ~~P1~~ | Naval search/strike depth | **DONE** major #45 live ASW/carrier |
| ~~P1~~ | War economy conversion depth | **DONE** major #46 stockpile sustain |
| ~~P0~~ | World-class full designers | **DONE** majors #47–#49 + phase8_designers_live |
| ~~P1~~ | Weather theater ops depth | **DONE** major #50 weather crisis + phase9_cycle_live |
| ~~P1~~ | Intelligence network depth | **DONE** major #51 multi-province cells |
| ~~P1~~ | Leader theater command depth | **DONE** major #52 HQ/station/ops live |
| P1 | Leader portraits content | Historical portrait assets ongoing |
| ~~P1~~ | Campaign AI war-goal depth | **DONE** majors #53–#55 + phase10_gs_live |
| ~~P0~~ | Campaign Alpha primary strip | **DONE** `campaign_alpha_primary_live` · dead_n=0 · PI 163 |
| P0 | 100d player-path dual | Extend completion_playability with primary-strip path |
| P2 | Performance / LOD world_full | Graphical + headless parity |
| P3 | Multiplayer **product** (after playtest cycle) | Netcode residual landed; productize one scenario later |

---

## 4. Architecture snapshot

```
pure (tools/map_generation/lib/*_product.py, next*.py)
  → MapPolishFormatters.gd (static mirrors)
  → MapManager.gd (*_live / apply_*)
  → GameData.gd (apply_order_panel_action routes + format_*_plain)
  → OrderCommandPanel.gd (sections + apply buttons)
  → ProvinceInsight.gd (chips + priority/always-on)
  → tests + tools/run_map_ci.sh + dual world_full evidence
```

**Scale (approx lines):** Formatters ~25k · GameData ~19k · ProvinceInsight ~15k · MapManager ~10k · OrderCommandPanel ~3.5k

---

## 5. Document index (authoritative)

| Doc | Role |
|------|------|
| `GAME_STATUS_ASSESSMENT.md` | **This file** — full done vs remaining |
| `Project_State_Summary.md` | Rolling major catalogue + state |
| `Next_30_Days_Roadmap.md` | Near-term build targets |
| `TODO.md` | Checklist mirror of majors |
| `docs/CURRENT_STATE.md` | Session log (append-only) |
| `docs/TESTING_PLAN.md` | Test/harness plans |
| `README.md` | Vision + setup |
| `/tmp/eoa-major*/EVIDENCE.md` | Dual run evidence per wave |

---

## 6. Bottom line

**Done enough to keep building product depth with confidence** on a green dual world_full bar.  
**Not done enough to call the game “world class complete.”** The gap is no longer empty domains — it is **depth, live state, content, and polish** on the spines already landed. Multiplayer has a **netcode residual foothold** (N3/N4 duals); full multiplayer *product* remains later. **Immediate recommendation:** playtest cycle per `docs/PLAYTEST_AND_DECISION_GUIDE.md` — freeze new residual dual packages until notes exist.

*Assessment generated 2026-07-13 after Phase 5 majors #38–#40 + next-410 dual green (`phase5_depth_live`).*
