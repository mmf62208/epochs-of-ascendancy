# Playtest & Decision Guide — Epochs of Ascendancy

> **Purpose:** How to launch, what to test, how often, and how to choose the next build cycle.  
> **Audience:** You (designer/player) + implementers.  
> **Status truth:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md) · director [`GAME_DIRECTOR_PLAN.md`](GAME_DIRECTOR_PLAN.md) · dual markers `TODO.md`.  
> **Date:** 2026-07-31 (post US+RoW sparse world_accurate ~3520 · WarLoop surface · map machine closed)  

---

## 0b. Post-merge human playtest checklist (collaborative — use this first)

**Board:** default F5 = `world_accurate` **~3520** provinces (US playable 130; not 3221 counties; was ~5670 / ~8761 pre-sparse).  
**M6 note:** This checklist is for **session smoke + findings**. It does **not** complete 20d/60d human narrative notes — those stay open and are **not** an automated gate.

### Launch

```bash
cd /home/mikef/Projects/epochs-of-ascendancy
tools/run_godot.sh --path . res://scenes/TestScenario.tscn
# or F5 on scenes/TestScenario.tscn in Godot 4.7.1+
```

### Numbered checklist (report ✓ / ✗ + note)

| # | What to do | Expect | Pass? |
|---|------------|--------|-------|
| 1 | Map loads without SCRIPT ERROR; see political world | ~3520 polys, Europe focus or **Home** | |
| 2 | **Home** = Europe · **End** = Asia · **Shift+Home** = full world | No void-hex stuck camera | |
| 3 | Click **8 majors capitals** (GER Berlin, FRA Paris, ENG London, USA DC, SOV, ITA, JAP, POL) | Names + ownership correct | |
| 4 | **F1** political · **F2** strain · **F3** vitality · **F4** development | Visible mapmode gradients | |
| 5 | **F9** resources · **Shift+F9** states · **Ctrl+F9** terrain | Fills change | |
| 6 | States mode + **operational zoom** | **State names** visible in Europe (Alsace/Baden/Rhineland class) | |
| 7 | Toolbar **Fronts** or **B** | Toast + enemy border target; cycle with B | |
| 8 | Toolbar **WarLoop** or **Shift+I** | Flow ON + fronts + war-path toast | |
| 9 | **I** alone | Toggles EquipmentFlow glyphs (toast tier/max) | |
| 10 | Select front province · **G** | Supply corridor capital→front polyline | |
| 11 | Friendly province w/ formation · **Ctrl+click** enemy adj **or** inspector **Attack** | Preview / assault attempt (may fail if no units — note) | |
| 12 | Toolbar **Corridor** / supply mode | Readable logistics story | |
| 13 | **Ctrl+S** quicksave · mutate · **Ctrl+L** quickload | State survives (settlement/owner if changed). Bare F5/F9 are mapmodes. | |
| 14 | Advance **~5–10 days** (time controls) | No freeze; toasts readable | |
| 15 | Optional: open OrderCommandPanel assault/flow actions | Not required if map path works | |

### What to write back (short)

```
Date:
Items failed (#):
Worst UX confusion:
Best moment:
Next fix priority (1–3):
```

---

## 0. What “freeze new residual packages for one cycle” means

### Short answer

**Stop inventing new pure→live→dual residual packages** (new `*_primary_live` markers, new 5-step domains) for a fixed period. Use that period for **play, balance notes, UI language, and fixing what duals already proved**.

### Why

Dual residual packages prove **hooks work** (`ok=true`, SCRIPT 0×2). They do **not** prove:

- Fun or clarity over a 20–100 day session  
- Balance of XP dilution, munitions burn, soft shortage, AI logistics  
- That players *see* EquipmentFlows without F10 / OrderCommandPanel  

If we keep adding duals, the board grows while the **player loop stays thin**.

### What a “cycle” is (recommended)

| Mode | Length | Allowed work | Disallowed work |
|------|--------|--------------|-----------------|
| **Playtest cycle** | **7–14 days** real calendar time, or **until you finish the checklist below** | Playtests, bugfixes on existing paths, balance scalars, copy/toasts, small UI, doc refresh | New residual dual packages, new design freezes, new space/net pillars |
| **Mini-cycle** | One long weekend (2–3 sessions) | Same, smaller checklist | Same |

### What you *may* still do during freeze

- Fix SCRIPT ERROR / dual regressions  
- Change numbers (transit days, XP blend, munitions consume, AI urgency)  
- Improve plain strings, toasts, OrderCommandPanel labels  
- Document findings in this guide / GAME_STATUS  
- Run pure tests + duals **as regression**, not as “new product”

### When freeze ends

When you have:

1. Written notes for the **core war loop** (production → flow → front → XP → combat)  
2. At least one **20-day** and one **60-day** session note  
3. A short **priority list** of the next 3 engineering jobs driven by play, not dual inventory  

Then open the next residual/build only if a playtest gap requires it.

---

## 1. Launch commands

### 1.1 Graphical play (primary — accurate GIS board)

From repo root:

```bash
cd /home/mikef/Projects/epochs-of-ascendancy

# Default F5 / TestRunner: world_accurate (~3520 post US+RoW sparse; was ~5670 / ~8761)
tools/run_godot.sh --path . res://scenes/TestScenario.tscn
# equivalent explicit:
EOA_SCENARIO=world_accurate tools/run_godot.sh --path . res://scenes/TestScenario.tscn
```

Scaffold dual board (legacy 2665 — CI duals / faster smoke):

```bash
EOA_SCENARIO=world_full tools/run_godot.sh --path . res://scenes/TestScenario.tscn
```

Other scenarios (if present): `1936`, `1918`, `phase1_europe_test`, pilots via `EOA_SCENARIO=…`.

Godot binary is resolved by `tools/run_godot.sh` (project expects **Godot 4.7.1+**).

### 1.2 Headless dual / evidence (regression, not playtest)

```bash
# Dual-style run still uses world_full for SCRIPT 0 smoke (faster/lighter)
# Do NOT set EOA_HEADLESS_EVIDENCE=1 for dual proof
export EOA_SCENARIO=world_full
export EOA_OOB_EVIDENCE_DAYS=12
tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 120
```

Watch console for markers such as:

- `equipment_flow_primary_live=1 … ok=true`
- `reinforcement_logistics_primary_live=1 … ok=true`
- `map_flow_lod_primary_live=1 … ok=true`
- `ai_logistics_day_primary_live=1 … ok=true`
- `SCRIPT ERROR` count should be **0**

### 1.3 Pure unit tests (fast gate)

```bash
cd /home/mikef/Projects/epochs-of-ascendancy
python3 -m unittest tools.map_generation.tests.test_equipment_flow_product \
  tools.map_generation.tests.test_reinforcement_logistics_product \
  tools.map_generation.tests.test_reinforcement_depth_product \
  tools.map_generation.tests.test_map_flow_lod_product \
  tools.map_generation.tests.test_ai_logistics_day_product \
  tools.map_generation.tests.test_combat_consume_product \
  tools.map_generation.tests.test_munitions_drone_product \
  -v
```

### 1.4 Optional long OOB production evidence

```bash
EOA_SCENARIO=world_full EOA_OOB_EVIDENCE_DAYS=20 \
  tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 180
# Look for majors_grew stockpile evidence in console
```

---

## 2. Map / UI controls you will use in playtests

| Key | What it does |
|-----|----------------|
| **U** | Supply / sealane **strategic flow** overlay master |
| **I** | **EquipmentFlow glyphs** only (independent of U; LOD still applies) |
| **Shift+I** | **WarLoop** first-session path: flow ON + Fronts + assault brief |
| **B** | Live **border fronts** (cycle assault targets) |
| **G** | Supply **corridor** capital/hub → selected province |
| **Home / End / Shift+Home** | Europe / Asia / full world camera |
| **Shift+F9** | **States** mapmode (state names @ operational zoom) |
| **O** | Occupation overlay |
| **J** | Battle indicators |
| **K** | Naval/air domain ops overlay |
| **F10** | Debug overlay (stockpile, equip, recruit, force tools) |
| **F11** | Signal graph harness (dev) |
| Toolbar **WarLoop / Fronts / Corridor / States** | Same as hotkeys above |
| OrderCommandPanel | Day packages, reinforce story (RF5), strategic AI daily apply |
| Inspector **Attack** | Stage/assault from selected friendly vs adjacent enemy |

Zoom the map through **strategic → operational → tactical** while EquipmentFlow glyphs are **ON** to feel LOD density (fewer aggregated glyphs at strategic zoom).

---

## 3. Core loop to learn (what duals built for)

```
Design / line seed
  → Production complete → country equipment stockpile (batch scale)
  → EquipmentFlow (rail/road/air/sea/drone/orbital) — non-instant by default
  → Interdict possible
  → Deliver to unit / depot
  → Manpower reinforce dilutes combat_experience (greens ≠ veterans)
  → CombatResolver uses strength · XP · reliability · munitions burn
  → AI day can pick training policy + logistics doctrine
```

If any step is invisible in a session, **that is a playtest finding**, not a dual failure.

---

## 4. Playtest sessions — schedule and frequency

### 4.1 Cadence (recommended)

| Cadence | Duration | Goal |
|---------|----------|------|
| **Daily smoke** (when coding) | 10–15 min | Load default **world_accurate**, zoom, click capitals, advance a few days, no crash |
| **Core loop session** | 45–90 min | Follow checklist §5.1 once through |
| **Medium campaign** | 2–3 hours or multi-evening | 20–60 in-game days; production + front + AI |
| **Long honesty** | Weekend or multi-session | 60–100 days; stockpile, XP bands, soft shortage |
| **Regression dual** | After any code change to CP/RF/map/AI | Headless dual or pure tests |

### 4.2 How often to re-run each checklist

| Checklist | When to run |
|-----------|-------------|
| §5.1 Core war logistics | **Every playtest cycle** (at least once) |
| §5.2 Map LOD / glyphs | Every cycle + after any map overlay change |
| §5.3 Manpower / XP | After RF balance tweaks; else every other session |
| §5.4 Combat / munitions | After CP5 balance; else every medium session |
| §5.5 AI logistics / training | Once per cycle + after AI daily path changes |
| §5.6 Space (optional) | Once per month or when touching space |
| §5.7 Multiplayer (optional) | Only if testing net; not required for solo polish cycle |
| Pure tests | Before dual; after every local change |
| Dual headless | After CP/RF/map/AI code change; end of cycle |

### 4.3 Note-taking template (copy per session)

```
Date:
Scenario / EOA_SCENARIO:
In-game start date / years advanced:
Focus checklist(s):

What felt good:
What was confusing / invisible:
Bugs (repro steps):
Balance notes (too slow / too harsh / too free):
Screenshot / console markers (if any):
Priority for next engineering day (1–3 bullets only):
```

---

## 5. Detailed test checklists

### 5.0 Full-test board (world_accurate) — do first each cycle

**Strategic map smoke (HOI feel, ~5 min):**
1. Political mapmode — majors distinct (SOV dark, GER red, ENG bright red).  
2. Development / infra feel — capitals + hubs (Berlin, Hamburg, NYC, Osaka) denser.  
3. Resources layer if available — USA oil belt / SOV Baku-ish / ENG colonial rubber/oil.  
4. Naval chokes — zoom Gibraltar, Suez, Malacca, English Channel sea cells.  
5. Front stations — GER units not only on Berlin (hubs + west/east border).  

Aligned with director phases **D1–D3** ([`GAME_DIRECTOR_PLAN.md`](GAME_DIRECTOR_PLAN.md)).

1. Launch **default** (no `EOA_SCENARIO`, or `world_accurate`).  
2. Confirm console: `provinces_world_accurate` · **~3520** provinces in MapManager (not pre-sparse ~5670/8761).  
3. Capitals click: Berlin · Paris · London · DC · Moscow · Rome · Tokyo · Warsaw — correct names/owners.  
4. Land vs sea pick: France land vs Channel; open Atlantic sea.  
5. RoW density: Africa/LATAM/Aus playable-scale (sparse merge); SE Asia may still be denser.  
6. Leaders: expect historical roster for majors (D1 landed — not zero).  
7. Advance 3–5 days: no freeze; optional F10 production smoke.  
8. Optional scaffold compare: `EOA_SCENARIO=world_full` still loads ~2665.

**Pass:** Accurate board is the default test world and is navigable for a human session.

### 5.1 Core war logistics (must-do each cycle)

1. Load **default world_accurate** graphical (or `world_full` if debugging scaffold-only duals).  
2. Pick a major (e.g. GER/USA) you can observe easily.  
3. **F10:** note country equipment stockpile for a design (infantry or tank).  
4. Advance time until **Production complete** messages appear (or force demo lines if F10 provides).  
5. Confirm stockpile **increased** (batch: trucks should jump more than tanks).  
6. Create or observe an **EquipmentFlow** (debug/ship API or AI logistics seed after AI day).  
7. Toggle **U** then **I** — glyphs appear only when I is on (and overlay path allows).  
8. Zoom out (strategic) then in (tactical) — glyph **count/density** should change (aggregate at far zoom).  
9. If possible, force or wait for **interdict** and read plain attribution.  
10. Reinforce a damaged formation (or use F10 equip/reinforce).  
11. Note **combat_experience** / strength before and after green refill — veterans should not stay full XP after mass greens.  
12. Fight or advance through a combat; note shortages / power feel.  
13. Write notes: *Could a new player understand steps 4–11 without this doc?*

**Pass criteria (human):** You can tell a story: “gear left the factory, moved, maybe got hit, arrived weaker/stronger unit.”

### 5.2 Map LOD / flow glyphs

| Step | How | Expected |
|------|-----|----------|
| Master overlay | Press **U** | Supply/sealane flow layer on/off |
| Glyph toggle | Press **I** | Equipment glyphs on/off; toast with tier + max |
| Strategic zoom | Zoom out far | Fewer glyphs; corridors/aggregate feel |
| Operational | Mid zoom | More discrete icons |
| Tactical | Zoom in | Densest discrete; corridors may thin |
| Independence | U off, I on | Glyphs may need flow overlay path — if glyphs require U layer, note as UX gap |
| Query (dev) | Dual or code path `get_equipment_flow_glyph_query` | `equipment_flow_glyphs_enabled` flips |

**Pass:** You can control clutter without turning off all logistics story.

### 5.3 Manpower, training policy, XP

| Step | How | Expected |
|------|-----|----------|
| Policy board | OrderCommandPanel / manpower products | See conscription / training-related actions |
| AI training | Dual or live `ai_select_training_policy` | War + high strain → crash; peace elite → cadre |
| Dilution | Heavily damaged unit + green reinforce | XP band drops; combat mult weaker |
| Rearm only | Equipment top-up without mass bodies | Smaller XP hit than green fill |
| Story plains | Order panel “Reinforce logistics story (RF5)” | Readable plain text |

**Pass:** Green armies feel different from veterans after attrition.

### 5.4 Combat & munitions

| Step | How | Expected |
|------|-----|----------|
| Shortage | Fight with empty stockpile | Soft/hard / readiness worse |
| Reliability | Production under shortage then equip | Lower reliability stamp hurts combat |
| Munitions | Stock missiles/drones; resolve battle | Stockpile decreases after combat |
| Deep combat | Dev/debug or dual path `resolve_deep_combat` | Outcome + equipment weights (optional) |
| AAR / console | Read battle factors if available | XP / shortages mentioned |

**Pass:** Production and stockpiles matter in a fight, not only org dice.

### 5.5 Strategic AI daily + logistics doctrine

| Step | How | Expected |
|------|-----|----------|
| Board | OrderCommandPanel: strategic AI daily board | Factions listed; player skip |
| Budget | Budget AI day | Queue of non-player actions |
| Apply | Apply budgeted AI day | `logistics` outcomes for AI tags |
| Flows | Check EquipmentFlow board / map after apply | Optional seeded flows for AI |
| Doctrine variety | Multiple nations / urgency | Modes/escort differ (rail vs airlift, escorted high threat) |

**Pass:** AI day does more than assault spam — logistics doctrine is visible in results.

### 5.6 Space residual (optional monthly)

| Step | How | Expected |
|------|-----|----------|
| Space board | Space product panel / dual markers in headless | SpaceFlow / sites exist |
| Lift / command | Soft caps | Soft shortage, not hard brick |
| Discovery | Survey / discovery UI if available | Choices without dual hang |

**Pass:** Space feels like pressure/prestige, not a full second game this cycle.

### 5.7 Multiplayer residual (optional; not required for polish cycle)

| Step | How | Expected |
|------|-----|----------|
| N3/N4 duals | Headless dual markers only | `n3_network_primary_live` / `n4_dedicated_primary_live` ok historically |
| Human MP | **Out of scope for freeze cycle** | Netcode foothold ≠ product multiplayer |

---

## 6. Regression gates (engineering, not fun)

Run when you change CP/RF/map/AI code:

```bash
# Pure
python3 -m unittest discover -s tools/map_generation/tests -p 'test_*equipment*' -v
python3 -m unittest discover -s tools/map_generation/tests -p 'test_*reinforce*' -v
python3 -m unittest discover -s tools/map_generation/tests -p 'test_*map_flow*' -v
python3 -m unittest discover -s tools/map_generation/tests -p 'test_*ai_logistics*' -v

# Dual (world_full)
EOA_SCENARIO=world_full EOA_OOB_EVIDENCE_DAYS=12 \
  tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 120
```

**Pass:** SCRIPT ERROR 0; relevant `*_primary_live=1 … ok=true`.

---

## 7. How to refresh status docs (your ongoing habit)

| Doc | Update when | Rule |
|-----|-------------|------|
| **`TODO.md`** | Every landed dual/feature | Checklist with dual marker strings |
| **`GAME_STATUS_ASSESSMENT.md`** | End of each playtest cycle | Maturity table + “what duals don’t prove” |
| **`Project_State_Summary.md`** | Phase landings | Don’t claim multiplayer “none” if N3/N4 duals exist |
| **`README.md` status block** | After major cycles | Point to assessment + playtest guide |
| **`docs/PLAYTEST_AND_DECISION_GUIDE.md`** (this file) | After each play cycle | Append session notes link or “Last playtest: DATE” |
| Design freezes | Only on design amendments | Do not rewrite freezes for polish |

**Conflict rule:** If docs disagree, **`TODO.md` dual markers win** for “landed,” playtest notes win for “fun,” design freezes win for “rules.”

---

## 8. Decision framework for next work

After a playtest cycle, pick **at most 3** jobs from the matrix:

| If you felt… | Next engineering | Not yet |
|--------------|------------------|---------|
| Couldn’t see logistics | Map toast/AAR/plain on default path | New dual package |
| Greens felt same as veterans | Tune XP blend + combat mult numbers | New RF phase |
| Munitions invisible | UI stockpile burn feedback | New munitions economy |
| AI braindead on supply | Deepen daily logistics leaf + debug plain | Full AI rewrite |
| Map clutter | LOD defaults / toggle defaults | New overlay systems |
| Bored at 20d | Scenario scripted war / OOB content | More space residual |
| Want multiplayer friends | One lockstep scenario product | Full N4 lobby chrome |

### Suggested next cycle priorities (default)

1. **Playtest + notes** (this guide) — no new residual packages.  
2. **Visibility:** reinforce/flow plains on map path + AI logistics day plain in panel.  
3. **Balance pass** on transit days, XP dilution, munitions burn.  
4. Only then: content scenario or AI personality wiring.

---

## 9. Session log (append newest at top)

### Template entry

```
### YYYY-MM-DD — session N
- Days advanced:
- Checklist:
- Wins:
- Friction:
- Bugs:
- Next 3 jobs:
```

### Last updated

- **2026-07-17** — Guide created after CP0–CP6 / RF0–RF6 / map LOD / AI logistics day duals. Freeze residual packages for one playtest cycle recommended.

---

## 10. Quick reference — key dual markers (regression)

| Marker | Meaning |
|--------|---------|
| `equipment_flow_primary_live` | Create / interdict / deliver |
| `equipment_stock_reinforce_primary_live` | Stock + reinforce |
| `reinforcement_logistics_primary_live` | Time / XP / hub |
| `reinforcement_depth_primary_live` | Non-instant / combat XP / policy / era |
| `map_flow_lod_primary_live` | LOD + toggle + renderer wire |
| `ai_logistics_day_primary_live` | Doctrine in AI daily apply |
| `combat_consume_primary_live` | Munitions + reliability + troop XP |
| `munitions_drone_primary_live` | Missile/drone scale + consume API |
| `equipment_flow_paint_primary_live` | Map glyph paint |
| `combat_depth_primary_live` | Deep combat + AI logistics doctrine API |

---

## 11. Closing note

You already proved the **machine**. This guide is how you prove the **game**.  

One cycle of play → notes → 3 jobs → small fixes → re-play will grow EOA faster than another dual package right now.
