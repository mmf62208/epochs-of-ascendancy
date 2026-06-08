# Aircraft Range, Maintenance & Prototyping System — Design Document

**Status:** Design Complete — Initial Skeletons Ready  
**Date:** June 2026  
**Priority:** High — adds deep player agency, historical realism, and meaningful tech/decision trade-offs to air power  
**Related Systems:** 
- `scripts/production/` (ReliabilityCalculator, DesignManager, RefinementProject, DesignLineState — build directly on this)
- `scripts/technology/TechnologyManager.gd` (air_equipment domain, engine techs)
- `scripts/agents/AgentManager.gd` + missions (assign engineers to projects)
- `scripts/map/SpecialSiteManager.gd` + SpecialSite (R&D labs, test airfields, maintenance depots)
- `scripts/map/InfrastructureDevelopmentManager.gd` (airfield infra affects maintenance/range recovery)
- `scripts/data/UnitTemplate.gd` + air unit templates (base_type = "Air")
- `scripts/map/MapManager.gd` + Province (for basing, range modifiers from terrain/infra)
- Weather system (fuel consumption, range in storms)

---

## 1. Executive Summary & Philosophy

**Core Idea (from user):**  
Technology, design choices, and experience create real trade-offs and improvement curves, modeled after history:
- P-51 Mustang + Rolls-Royce Merlin transformation
- Early ME 262 (unreliable engines) vs. later refined versions
- Tiger I (powerful but maintenance nightmare) vs. Sherman (reliable workhorse)

**Player Agency Goals:**
- Real choices: Rush "wonder weapons" (high performance, low reliability) or invest in reliable mass-produced designs.
- Long-term payoff for iteration and experience.
- Integration with existing production/refinement, agents, special sites, tech, and map basing.

**Key Sub-Systems:**
1. **Aircraft Range System** (configuration, tech, mid-air refuel, mixed fleets)
2. **Maintenance & Reliability System** (per-unit reliability, field degradation, basing recovery)
3. **Prototyping & Iteration System** (prototypes start bad, improve via combat XP + agent assignment + resources)

This turns air units from static templates into living designs that evolve with player investment.

---

## 2. Aircraft Range System

### 2.1 Base Range
- Every air UnitTemplate (base_type="Air") has `base_range_km` (or in stats).
- Modified by:
  - `era_tech_multiplier` (from TechnologyManager air techs)
  - Engine family (e.g. "rolls_royce_merlin" gives +25-40% range)
  - Aircraft design family maturity (from Prototyping system)

### 2.2 Mission Configuration (Player Choice)
Before launching air missions (strategic bombing, escort, CAS, etc.), player selects a **Loadout Profile** for the squadron/wing:

- **Ferry / Long Range**: Drop tanks + extra fuel cells. 
  - Range: +60-120%
  - Payload / weapons: -40-70%
  - Speed/agility penalty minor.
  - Requires tech "drop_tanks" or "long_range_ferry".

- **Combat Load** (default for most missions):
  - Full weapons + ammo.
  - Normal range.

- **Escort Configuration**:
  - Balanced: some drop tanks + fighter weapons.
  - Good for accompanying bombers.

Stored per-formation or per-mission in `Formation` or new `AirMissionProfile`.

### 2.3 Tech & Design Modifiers
- Advanced piston engines (Merlin, DB 605 late) → major range + efficiency.
- Early jets (Jumo 004, etc.): high fuel consumption, short range, poor reliability.
- Jet improvements over time (better compressors, afterburners, fuel efficiency tech) dramatically increase range.
- Aerodynamic refinements from prototyping reduce drag → better range.

### 2.4 Mid-Air Refueling
- Unlocked via `air_refueling` tech tree + special "Tanker Aircraft" designs.
- Requires:
  - Dedicated tanker squadrons (or multi-role).
  - Special Sites: "aerial_refueling_base" or forward airfields with tanker support.
  - Infrastructure level at origin base.
- Effect: Dramatically extends strategic bombing range (e.g. UK to deep Germany/USSR, or carrier task forces).
- Cost: Tanker aircraft are vulnerable, consume their own fuel, and tie up production.

### 2.5 Mixed Fleets & Realism
- Not all aircraft in a squadron upgrade simultaneously.
- Average range / payload of a formation = weighted by number of each subtype.
- Old aircraft drag down new ones (historical "legacy fleet" problem).
- UI should show "Effective Mission Range" and "Average Reliability" for the formation.

---

## 3. Maintenance & Reliability System

### 3.1 Core Stats (extend existing)
Every air unit (and ground units for consistency) has:
- `reliability` (0-100, higher = fewer breakdowns)
- `maintenance_index` or `maintenance_cost` (resources per day/week in field)
- `field_breakdown_risk` (computed)

Existing `ReliabilityCalculator` + `ReliabilityProfile` already compute these from design maturity, tooling, refinement. **Extend this for aircraft-specific rules.**

### 3.2 Historical Examples to Model
- Early ME 262 / He 162: High performance, terrible engine life → high maintenance, many losses to mechanical failure.
- P-51D late war: Excellent range + good reliability after maturation.
- B-17: Rugged, high survivability, but high maintenance tempo.
- Tiger vs Sherman: Power vs. uptime.

### 3.3 Degradation & Recovery
- **In the field / on operations**: Reliability slowly degrades (faster in bad weather, low supply, long missions, poor basing).
- **Recovery**: Happens at:
  - Home airfields with sufficient `infrastructure` level.
  - Special Sites: "aircraft_repair_depot", "advanced_maintenance_facility", "engine_rebuild_shop".
  - Supply throughput affects speed of recovery.
- Low supply → accelerated degradation + higher breakdown chance during missions.

### 3.4 Impact on Gameplay
- Low reliability formations have higher chance of:
  - Mission aborts
  - Aircraft lost to "mechanical failure" (not just enemy action)
  - Reduced effective sortie rate (fewer planes available each day)
- High maintenance drains resources (aluminum, skilled ground crew, parts) and competes with production.

---

## 4. Prototyping & Iteration System (The Heart of Player Agency)

### 4.1 Prototype Lifecycle
When a new aircraft design is unlocked (via tech) or created (future "design new plane" UI):

1. It enters production as a **Prototype** batch.
2. Initial stats:
   - High performance numbers (if the design is "advanced")
   - **Poor reliability** (e.g. 35-55)
   - **High maintenance cost**
   - High production cost / slow rate
   - "New Design Penalty" visible in UI

### 4.2 Improvement Loop (Active Player Investment)
Designs improve through real use and directed effort:

- **Combat / Operational Experience**:
  - Every sortie, every mission flown by the type generates "Design XP" or "Maturity Points".
  - Higher XP → gradual reliability and refinement bonus (ties into existing `design_maturity` and `RefinementProject`).

- **Assign Agents / Engineers**:
  - Use `AgentManager.assign_agent_to_project(design_id, agent_id, "engineering" or "test_pilot")`.
  - Talented agents (high skill in relevant traits) accelerate maturity gain significantly.
  - Risk: Agents can be lost in test flights / prototype crashes.

- **Political Power + Resource Investment**:
  - Spend Political Power (or a new "R&D Budget" resource) to fund dedicated test programs.
  - Special Sites (R&D centers, wind tunnels, test ranges) multiply the effect.

- **Over Time**:
  - Reliability ↑
  - Maintenance ↓
  - Minor performance tweaks (range, speed, payload) via "refinement" choices
  - Eventual "Mature Production" state (no more penalties, full stats)

### 4.3 Strategic Choices
- **Rush to Combat**: Deploy early prototypes for their raw power (risky but can turn battles).
- **Patient Iteration**: Keep them in testing / limited use until reliable (better long-term).
- **Parallel Programs**: Invest in multiple designs with different philosophies (one high-tech wonder, one reliable mass-production workhorse).
- **Legacy Drag**: Even after a design matures, older production batches in inventory still have worse stats unless "upgraded" or retired.

### 4.4 Data & Persistence
- Track per-design `design_maturity` (0.0–1.0) and refinement history.
- Persisted in SaveLoadManager.
- Historical scenarios can start designs at different maturity levels (e.g. 1944 ME 262 is more mature than 1942 version).

---

## 5. Integration Points

| System              | Integration |
|---------------------|-------------|
| **Technology**      | Air techs unlock engine families, refueling, new airframes, and "prototyping acceleration" bonuses. |
| **Agents**          | New/expanded mission types: "Test Pilot", "Lead Engineer on Project X". Agents assigned to specific designs. |
| **Special Sites**   | "Prototype Test Airfield", "Jet Engine Research Lab", "Aircraft Repair Complex". Provide multipliers and unlock advanced iteration options. |
| **Infrastructure**  | Airfield level + development directly affect basing range recovery and maintenance speed. |
| **Production**      | Reuse/extend `DesignLineState`, `RefinementProject`, `ReliabilityCalculator`. Prototypes are special production lines with high cost / low output initially. |
| **Supply**          | Fuel consumption modified by design state + range config. Maintenance parts are a supply demand. |
| **Weather**         | Bad weather increases fuel burn and breakdown risk, especially for immature designs. |
| **Map / Basing**    | Province air_range_modifier (from terrain, infra, special sites). Long-range missions require forward basing or refueling. |
| **Combat / Missions**| Air mission effectiveness (sortie success, payload delivered, losses to enemy + mechanical) uses effective range + reliability. |

---

## 6. Implementation Phases & Skeletons

**Phase 1 (This Task):** Design docs + basic manager skeletons + hooks into existing Reliability/Production/Tech/Agents.

**Phase 2:** UI (mission config picker, design maturity tracker in production screen, agent assignment to R&D projects).

**Phase 3:** Full gameplay loops (range calc in air missions, degradation over time, special site bonuses).

**Phase 4:** Historical scenario data (early vs late variants of famous aircraft).

See `scripts/air/` (to be created) and extensions to `production/`.

---

## 7. Open Questions / Future Polish
- Should there be a "Design New Aircraft" player-driven system (beyond tech unlocks)?
- How visible should "this squadron has 30% legacy ME-262s dragging reliability down" be?
- Carrier air groups have extra constraints (deck space, launch/recovery limits affecting effective range).
- Nuclear/strategic bombers get special long-range + refueling rules.

This system will make air power feel alive and historical in a way few grand strategy games achieve.

---

*End of Aircraft Range, Maintenance & Prototyping Design Document*