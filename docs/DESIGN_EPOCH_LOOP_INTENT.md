# EOA — Epoch loop intent (designer · lift · plans · deals)

**Date:** 2026-09-11  
**Status:** Director intent / design freeze. **Not landed.** Does not change live truth.  
**Live truth:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md) always wins. Maginot F5 + human §0b / M6 stay the next *play* work. This file is what we build **toward** when a playtest-driven slice opens Technology, Spycraft, Diplomacy, Military, Production, or Planning.  
**Do not:** new residual dual packages · GameData mega-split · densify / 13k · treat this as a gate.

**Session origin:** 2026-09-10/11 director notes after Rise of Nations (HOI4) comparison — reject Rifle 1/2/3 and locked peace; keep chips on the map; decisions must show in fights.

---

## 0. Player fantasy (locked)

The fun is **components, factories, kits, and deals** — then watching **armies, air, and navy execute a plan**. Not hex-by-hex plot armor. Not unlocking a new named hull every two years.

- **Create** chassis + components (fit is physics).  
- **Choose** quality vs quantity, guns vs engines vs lift, specialize vs outsource.  
- **Staff** generals / admirals / agents and **brief** them.  
- **See** the war on the map (chips, bubbles, AAR).  
- **Learn** — next playthrough change the mix. Multiple right answers. You may lose.

Limits that always bite: **resources, factories, manpower, time.** Empty stock invents nothing.

---

## 1. What is already the seed (do not rebuild)

| Seed | Where |
|------|--------|
| Living chips (org/str/rdy), march hops, multi-day `start_land_battle`, AAR, NEXT | SNAPSHOT L1 |
| Composition recipe (inf bns, trucks, tanks, guns), fuel, width, slowest element | `unit_composition_combat_product` |
| Fielded land **refit** 7d (org/rdy/str dip) | organize queue |
| Named design = stockpile key; 1:1 hulls vs batch rifles | [`COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md`](COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md) |
| Modules, `power_output`, air slot `drop_tanks` | `EquipmentModule.gd` · `DomainDesignPopup` |
| Leader +0–25% in land fight; Press/Hold/Withdraw | SNAPSHOT · [`LEADER_SYSTEM_DESIGN.md`](LEADER_SYSTEM_DESIGN.md) |
| CAS if wing assigned to Maginot region | Beta B4 |
| 31 strategic regions · 34 naval chokes | map machine |
| Occupier harvest, capture AAR economy | L1 |
| Capture → field foreign design (July 2026 notes) | `SESSION_NOTES/2026-07-11_post_capture_*` |
| Trade/relations compact ledger | [`TRADE_RELATIONS_STRATEGIC_DESIGN.md`](TRADE_RELATIONS_STRATEGIC_DESIGN.md) |
| Space volatiles / MC / boost (abstract life support) | [`SPACE_STRATEGIC_LAYER_DESIGN.md`](SPACE_STRATEGIC_LAYER_DESIGN.md) |
| Agents on tech (steal, compromise, projects) | [`TECHNOLOGY_SYSTEM_DESIGN.md`](TECHNOLOGY_SYSTEM_DESIGN.md) §14 |

This file **extends** those. It does not replace Maginot as the proof loop.

---

## 2. Rejected HOI / Rise of Nations patterns

| Reject | Replace with |
|--------|----------------|
| Rifle I / II / III and a new named ship every two years | Few **chassis**, **components** that miniaturize, **class variants** |
| Must re-pick the new model on the production line | Standing order: new builds of this class take the accepted fit |
| Storage tab (keep / sell / navy-only refit) | All 1:1 platforms: keep / **refit program** / replace / mothball / transfer / scrap |
| Peace locked because warscore / no talk while surrounded | Always-open channel; **leverage** decides yes / stall / no |
| Airpower that exists only as a tech modifier | Wing/region assignment that shows in the fight |
| Plot armor | AAR names the bet (no trucks → late; no radar → no intercept) |

---

## 3. Fit: mass + envelope + power (not CAD)

### 3.1 Three budgets

| Budget | Rule | Player sees |
|--------|------|-------------|
| **Mass (t)** | Sum of components ≤ chassis mass limit. Over → speed, range, reliability (ships: stability). | “+4.2 t. Speed −12%.” |
| **Envelope (class)** | Discrete: `facility` → `capital` → `cruiser` → `destroyer` → `vehicle` → `aircraft` → `manpack`. Mount only if `component.envelope ≤ chassis.envelope`. Miniaturization **lowers envelope**. | “Radar Mk I: capital. Mk III: destroyer. Airborne: project.” |
| **Power** | Engine `power_output` − Σ `power_draw` ≥ 0. Short → brown-out (set duty, speed, reliability), not a silent fudge. | “Draw 510 / plant 420. Bigger mill or drop the set.” |

Also: **crew** vs bunks; **hardpoint count** (quantity is a chassis property).

Weight **and** size: size is **envelope class**, not cubic metres in the UI. Mass is tonnes. Power is hp / kW / thrust.

### 3.2 Engines are the plant

Engine **count and type** scale `power_output`, mass, fuel, and often envelope.

| Plant | Typical | What it buys |
|-------|---------|----------------|
| 1× fighter | Tight watts | Gun + radio; early radar usually no |
| 2× medium | More draw + fuel | Light bomb load; later a shrunk set |
| 4× heavy | Real electrical + lift | Early airborne radar *if* envelope has shrunk *and* watts exist |
| 6× / special | Still more | Payload and sensors — also more mass and factories |

A 4-engine bomber is not “Radar II unlocked.” It is a **bigger plant**. The same radar generation still needs envelope ≤ `aircraft`.

### 3.3 Miniaturization

Electronics / radar / computers / seekers are **one capability** with generations that change envelope, mass, and draw — not SKU years. Research or an electronics agent **shrinks** the set so it can climb down capital → cruiser → vehicle → aircraft.

If it does not fit: **don’t mount / refit a larger chassis / wait for shrink / replace the class.**

### 3.4 Refit vs replace (all 1:1 platforms)

Tanks, IFVs, aircraft, ships, spacecraft — same menu as ships in HOI, not rifles.

| Option | When |
|--------|------|
| Keep | Chassis still good |
| **Refit program** | Hull has years left; component fits. Yard/depot time, reliability dip. Variant of **same class**. |
| **Replace** | Chassis is the bottleneck | New-build; old hulls mothball / transfer / scrap |
| Mothball | Maybe later |
| Transfer / scrap | Deal or steel back |

**New-build standing order** (chief/agent): auto-fit accepted freeze on hulls **not yet laid down**. **Fielded** kit needs an explicit program. Land 7d fielded refit is the seed.

Mass infantry kits stay **families** (`rifles`, truck batches). You do not refit rifle #4182.

---

## 4. Drop tanks, jettison, tankers, wings

**Hung drop tanks (transit):** +fuel +range, **−speed**, **−agility**, extra mass, extra cost. Heavier-duty wings (chassis upgrade) may be required to hang large tanks — mass, cost, and a factory line.

**Fight:** default **jettison on merge** for fighters (and optional for other types). Agility/speed return to clean-wing; tanks are **gone** (you paid for them). Escort/long-range mission can **keep tanks** (stay slow, keep range).

**Later:** **mid-air refueling** — tanker aircraft + boom/drogue as a system. Range without hanging tanks into the merge; costs tankers, training, and a doctrine. Not 1936 Maginot.

Designer strip must show hung vs jettisoned as two columns or a toggle: “In fight (tanks gone): agility 0.”

---

## 5. Lift vs mass → **movement the player reads**

Internal math: formation **mass** vs **organic lift** (trucks, half-tracks, horses, helicopters, landing craft).

Player-facing is **how fast this chip moves**:

- Lift ≥ mass → full hops/day for that chassis and fuel.  
- Lift < mass → **shuttle**: extra days per hop (column runs twice). Not a hard stop.  
- No fuel for trucks → lift collapses; foot still crawls.

Unit card line (example):

`Move 2 hops/day · lift 70% · +1 day per 2 hexes (not enough trucks)`

Transports (truck, plane, helicopter, ship) have **payload**. Division weight is the recipe sum. That is sealift / airlift / rail without RTS micro.

Less mass in components frees **speed, range (fuel volume), armor, weapons, or payload**. One pie.

---

## 6. Designer live strip (easy to understand)

Adding/removing a component shows **plain deltas**. Red = envelope/power/mass break. Amber = shuttle-lift or brown-out. Green = still valid.

Drop-tanks example (2-engine bomber, hung):

| | Now | With tanks hung | After jettison |
|--|-----|-----------------|----------------|
| Mass | 12.1 t | 13.4 t | 12.1 t |
| Range | 1 800 km | **2 400 km** | 1 800 |
| Speed | 380 | **355** | 380 |
| Agility | 1.0 | **0.82** | 1.0 |
| Bomb load | 2.0 t | 1.4 t | 2.0 |

Same strip for radar, armor, gun, extra engine.

---

## 7. Smart weapons, standoff, “effectiveness”

For years **tonnage on target × range** is the honest model (dumb bombs, shells, V1/V2).

When **smart / standoff** unlocks (late / 2026 band):

`effect ≈ payload × precision × Pk  against target hardness`

- Smaller mass can beat a larger dumb load if precision is high (less collateral — political + leverage, not just damage).  
- **Standoff range** is on the **munition**. Engagement envelope = **platform range + standoff**.  
  - Railroad siege gun / V1 / V2: munition range, low precision, no stealth.  
  - B-21 + 500 nmi standoff: aircraft reach + weapon reach.  
- Missiles and drones use the same effectiveness number. Player-facing: **Effect vs this target** (one bar), plus range ring — not ten formulas.

Dumb era does not show a fake “smart” bar.

---

## 8. Map: war evidence + air/naval regions

Forces **on the map** are the proof: chips, march, bubble, AAR, unrest, harvest, thinned str%.

**Air:** keep HOI-like **regions** (we already have 31 strategic regions). Assign a **wing to a region**; CAS/intercept only if assigned (Maginot B4 seed). One wing → one region as the default simple rule; stack only with doctrine/C2.

**Navy:** sea zones already exist (340). **Patrol assignment:** a fleet may cover **up to 3 adjacent sea zones** (HOI-like), thinner if stretched. Chokes (34) stay special.

No assigned wing/fleet → no air/naval line in the land/sea tick. Tech-only airpower is rejected.

**Nuclear:** rare. Multiplies **leverage** on the deal sheet (“harder to ignore this message”). Not an I-win combat button. Use/threat has cohesion and alliance cost.

---

## 9. Plans, leaders, doctrines

Player **briefs**; leaders **run ticks**. Override a fight if you want; you should not have to.

**You set:** theater objective, assigned chips, stance (Press / Hold / Probe / Withdraw — already on the card), constraints (wait for lift; no nukes).

**They execute** with doctrine + traits + kit + fuel. They **suggest** via NEXT (“wait 3 days, trucks catch up” vs “press, they break tomorrow”).

Mismatch is an AAR line: “doctrine wants speed; lift 70%.” Unassigned leader = 1.0 (already). Bad general + great tanks still fumbles.

---

## 10. Ally planner (ask, don’t puppet)

A **request** is a deal, not a cheat.

1. Pick **ally**.  
2. Pick **mission:** garrison this pid, take this city, defend this line, build more planes/tanks/ships, hold a choke.  
3. Optional **offer:** land, supplies, equipment, basing, cash.  
4. Three honest numbers (player-visible):

| Score | Meaning |
|-------|---------|
| **Leverage** | Will they *say* yes? Relative force **in the domain they care about**, trade dependence (and partners), equipment pipeline, industry, political influence, **who signs**, surround/blockade as pressure, nuclear if relevant, agent plays (bribe, kompromat, **remove blocker**). |
| **Capacity** | Can they *do* it? Factories, manpower, lift, distance, already at war. |
| **Follow-through** | Do they *keep* doing it? Doctrine, leader, cohesion, competing fronts. Incentives (the offer) raise this. |

Always allowed to **open** the ask. Surrounded enemy: leverage up, screen still exists (Rise of Nations failure). Suggestion vs committed: they can accept as **intent** (soft) or **order** (costs more leverage / more offer).

Sun Tzu: win without fighting; break alliances; fight last. Deal frame: BATNA, who signs, what they want more than pride.

---

## 11. Capture and reverse engineering

Owned-land wreck / captured stock is **more than loot**.

1. **Existence:** you now **know** they have a capability (airborne radar, wet stowage). Unlocks agent targeting and a tech inspector line.  
2. **Use:** field the captured kit (July 2026 capture→design path) until it breaks / no spares.  
3. **Learn:** assign a **reverse-engineer team** (scientists + optional agent). Time, labs, risk. Success → component or shrink progress, not a free chassis. Failure / sabotage possible.  
4. **Fit still applies:** their set on *your* hulls may fail envelope/power until you shrink or change plant.

This is why capturing gear matters in the loop, not only Fill%.

---

## 12. Space (when the era has the plant)

Not Maginot. When space is a map layer, habitats are chassis with the same budgets **plus life-support majors** (extend space `volatiles`, don’t invent a grocery sim):

| System | Role | Limited by |
|--------|------|------------|
| Air / water / food stores | Crew-days | Envelope + mass + resupply |
| Waste recycle | Cuts resupply | Power + mass |
| Radiation shielding | Crew survival / reliability | Mass (lots) |
| Docking / resupply ports | SpaceFlow attach | Envelope, MC |
| Crew volume | Headcount | Envelope |

All draw **power** and **size of ship/station**. Brown-out life support is a crisis, not a flavor toast. Earth boost / MC stay the cap ([`SPACE_STRATEGIC_LAYER_DESIGN.md`](SPACE_STRATEGIC_LAYER_DESIGN.md)).

---

## 13. Pillars — how this lands in the loop

| Pillar | Intent in this freeze | First honest slice (after Maginot human notes) |
|--------|----------------------|-----------------------------------------------|
| **Technology** | Capabilities + shrink, not SKU years. Projects + agents. Smart/standoff era-gated. | Envelope/mass/draw on modules; refuse illegal mounts |
| **Spycraft** | Steal fits, bribe, remove blockers, reverse-engineer teams | Known-tech from wreck → agent target |
| **Diplomacy** | Leverage sheet; ally planner; nuclear as “take the call” | Always-open peace/ask; no brick wall |
| **Military** | Chips + regions + plans + leaders. Lift → move. Fight evidence. | Truck lift → hop days on living land units |
| **Production** | Factory pie; standing order; refit yards | Live designer strip on existing DomainDesignPopup |
| **Resources** | Soft shortage; outsource = trade risk | Unchanged majors; embargo bites lift/fuel |
| **Infrastructure** | Yards, labs, airfields, spaceports as **capacity** for refit/RE/tankers | Don’t new-sim; use existing infra projects |
| **Planning** | Brief theater; NEXT suggestions; ally asks | Extend Press/Hold + NEXT; don’t HOI front-draw v1 |
| **Building** | Factories vs rifles vs trucks vs 4-engine plants | Player sees the pie on the living production board |

---

## 14. What to build (ordered, not a dual factory)

**Do not start this list until** SNAPSHOT next human work is in play (§0b remaining + 20d notes) **or** a playtest names a hole these rules fix.

| # | Slice | Proof | Explicitly later |
|---|--------|-------|------------------|
| **0** | Maginot living loop stays green | `--quick` + human notes | — |
| **1** | **Designer live strip** on current land/air popup (add/remove truck, gun, drop tanks → deltas) | Unit test of real strip helper; F5 can see it | Full CAD |
| **2** | **Lift → march days** from existing composition trucks vs recipe mass | Headless: low-truck formation extra hop days | Helicopter/airlift era |
| **3** | **Envelope + mass + power_draw** on `EquipmentModule`; chassis plant (`engine_count`) | Illegal radar-on-fighter fails; 4-engine can feed a set the fighter cannot | Miniaturization tree content dump |
| **4** | **Jettison** drop tanks on air merge (agility back; tanks consumed) | Headless air tick | Mid-air refuel, heavy wings |
| **5** | **Wreck → known tech → RE team** (extend capture fielding) | Capture plane in owned land sets `known_capability`; team ticks progress | Instant steal-all |
| **6** | **Region assign** already seeded (CAS); document 1 wing / region, fleet ≤3 sea zones | Maginot CAS still PASS | HOI air-war UI clone |
| **7** | **Ally ask** on leverage (garrison / take / produce) | One request path + visible leverage/capacity | Puppet AI |
| **8** | Theater **brief** (objective + stance) to assigned leader | NEXT uses it | Full battle-plan drawing |
| **9** | Smart/standoff **effectiveness** + standoff range | 2026 munition vs dumb bomb | 1936 fake smart |
| **10** | Space life-support as habitat modules | Only when space map layer is play | Grocery micro |

Soft 30fps, densify, museum 13k, MP, V3 markets stay non-goals. Full globe is already `world_accurate` ~3520; coarsen backwaters only if a human names soup.

---

## 15. Communication (anti-plot-armor)

AAR / NEXT name the decision:

- “Airborne radar still capital-only. Fitted cruisers. No intercept.”  
- “Drop tanks jettisoned. Agility restored. Range gone.”  
- “Lift 70%. Arrived a day late.”  
- “Ally accepted garrison **intent**; capacity 40% — they sent a brigade, not a corps.”  
- “Wreck: they have an airborne set. RE team 12d or send agents.”

If the player cannot see why the chip was slow or the deal failed, the system is unfinished.
