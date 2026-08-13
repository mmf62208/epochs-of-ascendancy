
> **Implementation note (2026-07-17):** CP0–CP6 / RF0–RF6 dual residual packages are **shipped**. Prefer playtest + balance (`docs/PLAYTEST_AND_DECISION_GUIDE.md`) before opening new residual dual packages.
# Combat & Production Engine — Design Freeze (Direction)

> **Status:** Design freeze v1.0 · 2026-07 · **direction lock**, not full engine rewrite  
> **Scope:** Production scale, equipment stockpiles, reinforcement logistics, map flow symbols, combat coupling, phased rewrite  
> **Builds on:** `RESOURCE_PRODUCTION_STRATEGIC_DESIGN.md`, `PRODUCTION_ASSIGNMENT_SCREEN.md`, TradeFlow/SpaceFlow interdiction, designer suite  
> **Does not claim:** full CombatResolver rewrite, HOI 3D designers, every vehicle sprite on the map, Vic3 goods market  

---

## 0. Why this freeze exists

Production and combat are the **second-most important** EOA pillar after the strategic map spine. Players must feel:

1. **Designs matter** — modules and doctrine change what rolls off the line.  
2. **Industry matters** — factories, majors, shortages, and priorities change war outcomes.  
3. **Logistics tell a story** — equipment and supplies *travel*, can be raided, and arrive (or don’t) as reinforcements.  
4. **Depth is optional** — a low-micro path always works; deeper layers reward mastery without mandating daily goods clicks.

This document locks **scale rules**, **system connections**, and a **phased rewrite roadmap**. Later goals implement phases; they do not re-litigate the scale model without an explicit design amendment.

---

## 1. Peer-game comparison (adopt / reject / EOA twist)

| Reference | What they do | Adopt | Avoid | EOA twist |
|-----------|--------------|-------|--------|-----------|
| **HOI4** | Factories → **equipment stockpile** (guns, tanks, planes as counts); divisions draw for reinforce/upgrade; IC abstraction; convoys/raids for sea trade | Stockpile + reinforce pipeline; few strategic resources; soft shortages | Pure IC without designer identity; endless production-tab micro; invisible “why am I short?” | Every *named design* is a stockpile key; custom designs stay first-class |
| **HOI4 logistics** | Supply hubs, rail capacity, province attrition — not every truck sim | Capacity/chokepoint *feel*; rail/port tiers | Full rail micromanagement as default | **EquipmentFlows** use existing province graph + mode symbols |
| **Terra Invicta** | Ship = 1 hull; Mission Control soft cap; space resources feed industry; raids on logistics | 1:1 capital platforms; soft capacity caps | Faction-only politics; pure space minigame | Nation-state designers + Earth trade/space flows already seeded |
| **Stellaris** | Soft empire shortages; shipyards; reinforcement abstracted | Soft shortage production | POP micro | Majors already soft-shortage (`strategic_stockpile_soft_shortage`) |
| **Steel Division / op-scale wargames** | Tactical 1:1 vehicles; operational map moves battalions | Optional deep combat uses real equipment *types* | Default grand map is not RTS micro | Map shows **flow symbols**, not every tank counter |
| **Vic3 market** | Goods feel real | Flavor of scarcity | Full goods market UI | 8 majors only (`RESOURCE_PRODUCTION_STRATEGIC_DESIGN`) |
| **Sins / space trade routes** | Visible raidable trade | Visible interdictable routes | Free multi-star free-for-all early | TradeFlow + SpaceFlow + **EquipmentFlow** one interdict family |

**Rejected as core:** daily goods assignment · full Vic3 markets · hard production halt on empty stock · mandatory truck pathfinding for every crate · simulating every vehicle as a map unit at grand-strategy zoom.

**Locked model name:** `equipment_flow_compact_ledger`  
(Companion to `strategic_stockpile_soft_shortage` and `orbital_compact_ledger`.)

---

## 2. Inventory — what EOA already ships vs gaps

### 2.1 Keep and extend (do **not** throw away)

| System | State | Role going forward |
|--------|--------|-------------------|
| **8 strategic majors** + soft shortage | Shipped dual | Continues as industry input; never becomes Vic3 goods |
| **FactoryManager** lines / retooling / plants | Shipped | Assignment surface stays; add priority → EquipmentFlow hooks |
| **DesignManager** + designers | Partial depth | Design freeze → register → line seed remains the deep path |
| **ProductionManager** equipment stockpile (national + country) | Shipped API | **Canonical finished-goods store** |
| **EquipmentShortageTracker** → combat soft/hard/readiness | Partial | Deepen reliability stamps; formation demand signals |
| **CombatResolver / BattleManager** | Playable slice | Consume equipment stats + shortages; no full rewrite in early phases |
| **TradeManager TradeFlow** interdict (sub/air/raider/convoy) | Shipped | **Template** for EquipmentFlow interdiction |
| **SpaceFlow** interdict | Shipped | Same interdict family for space sustain |
| **SupplyManager** daily sustain | Shipped | Ops triad (manpower / supplies / fuel) stays separate from equipment stock |
| **Production assignment UI** | Spec + partial | Layered chrome; not the logistics sim |

### 2.2 Gaps (why it feels unfinished)

| Gap | Player pain | Rewrite / extend? |
|-----|-------------|-------------------|
| **Unclear production scale** | “Is this 1 tank or a battalion?” | **Extend + freeze scale table** (this doc) |
| **Factory complete → stockpile** path uneven across categories | Designs don’t always *feel* like they arm the front | **Extend** ProductionManager complete → country stockpile |
| **Stockpile → unit reinforce** not a first-class pipeline | Losses don’t create urgency on the production board | **New EquipmentFlow + reinforce tick** |
| **No map story for movement of gear** | Invisible logistics | **EquipmentFlow symbols** (not full unit sim) |
| **Missiles / drones / late platforms** weak category rules | Future eras feel like renamed tanks | **Scale table rows** + design categories |
| **Combat depth vs formation abstraction** | Want more realism without RTS micro | **Phased CombatResolver** hooks; keep formation resolve default |
| **Interdiction of *reinforcements*** | Only trade/space feel raidable | **EquipmentFlow interdict** reusing TradeFlow causes |

### 2.3 Concrete rewrite candidates (priority)

| Priority | Candidate | Keep? | Action |
|----------|-----------|-------|--------|
| P0 | Scale + category policy | N/A | **Freeze here** |
| P1 | EquipmentFlow ledger (factory→depot→front) | New | Ship after freeze |
| P2 | Reinforce tick from country stockpile to formation demand | Extend ProductionManager | Wire shortage tracker as demand |
| P3 | Map symbol layer for active EquipmentFlows | Extend map/UI | Trains/trucks/aircraft/ships icons |
| P4 | Production complete always lands in country stockpile + optional flow | Extend | No silent “void” output |
| P5 | Combat reliability + munitions consumption loops | Extend CombatResolver | Shells/missiles burn stock |
| P6 | Deep combat modes (optional) | Later | Not required for grand-strategy default |
| P7 | Full HOI-style IC rebalance / 3D designers | Later | Out of this freeze |

---

## 3. Production scale lock (the “1 tank or 20?” decision)

### 3.1 Principle: **identity-weighted hybrid scale**

| Class | Stockpile unit means | Rationale |
|-------|----------------------|-----------|
| **Infantry equipment / small arms / support kits** | Abstract “sets” (HOI-like). 1 unit ≈ gear for ~10–25 troops depending on era rules, **not** 1 rifle | Mass items must not explode UI or memory |
| **Light vehicles / trucks / APC batches** | **Platoon batch** default: 1 stock unit ≈ **4 vehicles** (configurable per design `batch_size`) | Trucks are logistics mass; optional 1:1 for elite designs |
| **Tanks / IFVs / AFVs (player-designed)** | **1 stock unit = 1 real vehicle** | Designer identity and prestige; losses hurt |
| **Artillery tubes / SPA** | **1 stock unit = 1 tube/system** for self-propelled/named; towed can use `batch_size` 2–4 | Named SPGs feel personal |
| **Aircraft (fighters, bombers, attack)** | **1 stock unit = 1 airframe** | Sorties abstract; airframes are the scarce object |
| **Helicopters** | **1 stock unit = 1 airframe** | Same as fixed-wing |
| **Drones (tactical/loitering)** | **System batch**: 1 stock unit ≈ **4–8 air vehicles** OR 1 large MALE/HALE UAV if design flags `singleton=true` | Swarm without 10k counters |
| **Missiles / rockets (tactical–strategic)** | **1 stock unit = 1 ready munition** for guided/strategic; artillery rockets may batch | Expenditure loops need clear counts |
| **Ships / submarines** | **1 stock unit = 1 hull** | Already capital identity |
| **Space platforms / craft** | **1 stock unit = 1 craft/module set** per design tier | Aligns with space designer + MC/command caps |
| **Ammunition / general supplies crates** | Abstract bulk (`supplies` ops triad + optional ammo categories later) | Not factory “gun” counts |

**Locked rule:** If the player **designed it** and it is a **named combat platform** (tank, plane, ship, major missile, singleton drone), default is **1:1**. If it is **mass infantry/logistics/swarm**, default is **batch abstraction** with explicit `batch_size` on the design.

### 3.2 Production times (how long until “one unit” completes)

Uses existing `production_cost_rules.json` as the **time spine**:

- Line completes when accumulated factory points ≥ design cost.  
- **One complete event** adds `batch_size` (default 1 for 1:1 classes) to **country equipment stockpile** under `equipment_id` = design id.  
- Era multipliers already exist (`ww1` … `future`); drones/missiles/space use category rows + module costs.  
- Soft shortage slows points (already shipped); never hard-stops mid-war by default.

**Player-facing estimate:** “~X days per tank / per airframe / per missile” on the assignment screen — always in **stock units**, never silent internal IC.

### 3.3 Advanced platforms (drones, advanced tanks, missiles)

| Platform | Production | Combat consume | Notes |
|----------|------------|----------------|-------|
| Advanced tanks | 1:1; high steel/electronics/specials | Durability losses remove 1 stock when destroyed | Reliability stamp from production |
| Drones (swarm) | Batch; cheap electronics/fuel | Sortie attrition burns fractional stock | Elite recon UAV = singleton |
| Tactical missiles | 1:1 munitions | Fire mission burns 1+ | Reload from stock via EquipmentFlow |
| Strategic missiles | 1:1; fissiles/specials gated | Strategic resolution separate | Secret program paths stay |
| Space craft | 1:1 + orbital_command soft cap | Space combat / loft costs | Already partially gated |

---

## 4. Resource wiring (majors → lines → designs)

Already frozen in resource design; restated for combat/production coupling:

| Input | Feeds |
|-------|--------|
| Steel / Aluminum / Rubber / Electronics / Specials / Fuel / Energy / Fissiles | Line daily costs + shortage mult |
| Design modules | Cost + resource draw + combat stats |
| Production reliability stamp | Combat soft/hard/readiness when equipped |
| Food | Supplies + cohesion (not a 9th factory major) |

**New requirement (P4):** When a line completes, always:

1. Credit **country equipment stockpile** (`design_id` → +batch).  
2. Optionally spawn an **EquipmentFlow** from factory province → depot/front if demand exists.  
3. Emit player-visible plain: *“3× Mk IV Medium completed at [province]; 2 rail-bound to 3rd Army.”*

---

## 5. Reinforcement path (factory → combat) + interdiction

### 5.1 Pipeline (locked)

```
Designer freeze → Production line → COMPLETE
        → Country equipment stockpile
        → (optional) EquipmentFlow(mode, path, amount)
        → Depot / formation province
        → reinforce_unit(formation_id) fills TOE gaps
        → CombatResolver uses on-hand equipment + shortages
```

### 5.2 EquipmentFlow (new ledger family)

Mirror **TradeFlow** / **SpaceFlow**:

| Field | Meaning |
|-------|---------|
| `flow_id` | Unique |
| `equipment_id` | Design / template |
| `amount` | Stock units (already scaled) |
| `from_province` / `to_province` or `to_unit_id` | Path endpoints |
| `mode` | `rail` · `road` · `airlift` · `sealift` · `river` · `helicopter` |
| `corridor_risk` | Base interdict chance |
| `escort` | Optional convoy/fighter escort flag |
| `active` / `delivered` / `lost` | State |

**Interdict causes** (reuse trade vocabulary where possible):  
`air_strike`, `partisan`, `artillery_interdiction`, `submarine`, `surface_raider`, `air_interdiction`, `storm`, `bridge_out`.

**Attribution plain (player story):**  
*“Partisans hit a rail EquipmentFlow near [node]; 40% of Mk IV Mediums en route to 3rd Army lost.”*

### 5.3 Demand signal

- Formations expose **TOE deficit** (template need − on-hand).  
- Auto reinforce (default): highest priority units first (`priority_reinforcement_units` already stubbed).  
- Deep path: player pins priority, escorts flows, chooses rail vs airlift (faster, riskier, Fuel cost).

### 5.4 Supplies vs equipment

| Pool | What it is | Interdict? |
|------|------------|------------|
| **Supplies** (ops triad) | Food/ammo/general sustain abstraction | Via supply network / TradeFlow-like sustain |
| **Fuel** | Shared mobility + production | Ops burn + line burn |
| **Equipment stock** | Named designs / batches | **EquipmentFlow** |

Do **not** merge ammo crates into tank counts. Munitions for artillery/missiles may later be separate equipment ids.

---

## 6. Map symbol policy (trains, trucks, planes, ships)

### 6.1 Locked policy

- **Not every unit is represented.** Map symbols are **story glyphs** for **active EquipmentFlows** (and optionally TradeFlows/SpaceFlows).  
- One glyph can represent a whole flow of 50 trucks or 12 tanks.  
- Zoom LOD: strategic zoom → aggregated corridor arrows; theater zoom → discrete train/truck/ship icons on path nodes.  
- Combat units on the grand map remain **formations** (HOI-like), not every vehicle.

### 6.2 Mode → symbol

| Mode | Symbol family |
|------|----------------|
| `rail` | Train / rail convoy |
| `road` | Truck column |
| `airlift` | Transport plane |
| `helicopter` | Helicopter icon (short hops) |
| `sealift` | Merchant / LST silhouette |
| `river` | Barge |

### 6.3 Player understanding loop

1. Production board shows complete.  
2. Map flashes a rail glyph toward the front.  
3. Interdict event explains loss.  
4. Formation shortage icon ticks up if flow fails.  
5. Player re-prioritizes lines or escorts.

---

## 7. Layered fun / micro policy (replayability without pain)

### 7.1 Default (low micro) — always valid

| Layer | Behavior |
|-------|----------|
| Auto lines | Scenario / AI seeds critical templates |
| Auto reinforce | Stock → highest priority formations |
| Auto mode | Prefer rail inland, sealift overseas |
| Soft shortage | Slow production; never brick the game |

### 7.2 Intermediate

| Layer | Behavior |
|-------|----------|
| Production assignment | Reassign factories; retool deliberately |
| Priority reinforce | Pin elite armor / air wings |
| Escort toggle | Protect high-value EquipmentFlows |

### 7.3 Deep (optional mastery)

| Layer | Behavior |
|-------|----------|
| Full designers | Module trade-offs → stats + cost + reliability |
| Line doctrines | Mass / auto / additive / nano (already aspirational) |
| Flow routing | Choose mode, path risk, depot staging |
| Munitions economy | Missiles/shells as expendable stock |
| Secret programs | Parallel lines with scandal risk |

**Replayability** comes from design trees, theater logistics chokepoints, and interdict stories — not from daily clicking 40 goods.

---

## 8. Combat connection (how production changes battles)

| Hook | Effect |
|------|--------|
| On-hand equipment counts | Soft/hard attack, breakthrough, defense |
| Shortages | `has_shortages` power mult (already partial) |
| Reliability stamp | Breakdown / loss amplification |
| Munitions stock | Sustained fire missions, missile volleys |
| Fuel | Sorties, operational movement |
| Arriving EquipmentFlows | Mid-campaign reinforce events (optional delayed power bump) |

**Default resolve** stays formation-level (not vehicle-by-vehicle RTS). Optional later modes may zoom into equipment-rich resolution without changing stockpile scale.

---

## 9. Phased rewrite roadmap (execution goals after this freeze)

| Phase | Deliverable | Exit criteria |
|-------|-------------|----------------|
| **CP0** | This design freeze + pure design-audit dual | Doc locked; dual green |
| **CP1** | EquipmentFlow pure math + manager (create/advance/interdict) | **Shipped** dual: create_ok · interdict_ok · deliver_ok |
| **CP2** | Line complete → country stockpile always; demand reinforce tick | **Shipped** dual: stock_ok · reinforce_ok |
| **CP2+** | Non-instant reinforce + experience dilution + hub/era time | See `REINFORCEMENT_EXPERIENCE_LOGISTICS_DESIGN_FREEZE.md` (RF0–RF6) |
| **CP3** | Map symbol strip / theater glyphs for EquipmentFlows | **Shipped** board symbols + **map paint** dual: symbols_ok · board_ok · paint_ok |
| **CP4** | Munitions + drone batch categories wired to designers | **Shipped** dual: missile_ok · drone_ok · consume_ok |
| **CP5** | CombatResolver deeper consume/reliability loops | **Shipped** dual: combat_consume_ok · reliability_ok · xp_ok |
| **CP6** | Optional deep combat modes / AI logistics doctrine | **Shipped** dual: deep_ok · logistics_ok · joint_ok |

**Honesty:** Full “combat/production engine rewrite” is **CP1–CP6**, multi-goal. CP0 only freezes direction.

---

## 10. Decision summary (quick reference)

1. **Scale:** Hybrid identity-weighted — 1:1 for named platforms; batch for mass/swarm; abstract for infantry kits.  
2. **Times:** Existing cost rules; one complete = +batch to stockpile.  
3. **Resources:** Keep 8 majors + soft shortage; wire every complete into stock + optional flow.  
4. **Reinforce:** Stockpile → EquipmentFlow → formation; interdictable like trade.  
5. **Map:** Flow symbols (train/truck/air/sea), not every vehicle.  
6. **Fun:** Auto default; deep designer/priority/escort optional.  
7. **Rewrite:** Extend stockpile + TradeFlow patterns; phase CP1–CP6; no big-bang delete.

---

## 11. Dual / residual package name

- Pure: `combat_production_design_audit`  
- Live dual marker: `combat_production_design_primary_live=1` … `ok=true`  
- Model: `equipment_flow_compact_ledger`

---

## 12. Amendment rule

Changing §3 scale table or §5 pipeline requires an explicit design amendment entry (date + rationale). Implementation goals may fill phases without reopening scale unless playtests force a documented change.
