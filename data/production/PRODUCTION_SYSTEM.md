# PRODUCTION SYSTEM — Epochs of Ascendancy

**Last Updated:** May 2026  
**Status:** Core systems implemented (Retooling, Multi-slot Factories, Resource Consumption, Production Progression, Port Shipyards, Shortage Penalties)

---

## 1. Current Architecture Overview

- **Factory** (`scripts/map/Factory.gd`)
  - Lives on provinces via `ProvinceFactoryComponent`
  - Has `factory_id` (province × 100 + slot encoding)
  - Tracks `current_production_design`, damage, efficiency, retooling state
  - Supports `max_production_lines` (for shipyards, aircraft factories, etc.)

- **ProductionLine**
  - Belongs to one Factory
  - Tracks `progress`, `design_production_cost`, `daily_resource_cost`
  - Applies factory efficiency + concentration bonus + retooling + shortage penalties

- **ProductionManager** (autoload)
  - Central coordinator for assignment, retooling, progression, and queries
  - `daily_production_tick()` / `advance_production(days)`
  - Concentration bonuses (national + per-factory slot rush)
  - Resource shortage handling

- **ProductionCostCalculator**
  - Calculates `production_cost` from category + modules + era + complexity

---

## 2. Retooling System

### Rules
- When changing what a factory produces, current progress on assigned lines **is lost**.
- Efficiency is **heavily debuffed** during retooling (never fully paused).
- Efficiency **slowly recovers** after the main retool period.
- Retooling time and recovery speed are **separately modifiable** by technology, focus trees, and industrial agents.
- Hardest switches start with a **20% efficiency floor** (can be raised by tech/focus).

### Future UI Requirements (Important Notes)
- When player attempts to reassign a factory, show a **confirmation popup/warning** that includes:
  - Old design → New design
  - Expected efficiency immediately after switching
  - Estimated days until factory returns to full efficiency
  - Clear warning: **"Current production progress on this line will be lost."**
- Add a **visual indicator** on the factory (icon, overlay, or color change) while it is in retooling state.

---

## 3. Shipyard / Multi-Level Production

### Current Implementation
- Factories have `max_production_lines` (default 1).
- Shipyards are created with `FactoryManager.create_shipyard_for_province(..., levels := 4)`.
- Multiple lines can be assigned to the **same design** inside one factory → **slot rush bonus** (+12% per extra line, capped at 1.6×).
- Player can choose to concentrate all levels on one capital ship or spread them for parallel construction.

### Port & Shipyard Rules (Enforced in Code)
- **Shipyards may only be built or converted in provinces with port access** (`Province.has_port` / `resolve_has_port()`).
- Port access is set explicitly in scenario data or inferred from coastal terrain, port features/tags, or adjacency to sea provinces (`ScenarioLoader._infer_port_access_for_all`).
- Inland factories **cannot** produce naval designs; only `factory_type == "shipyard"` at a port may build ships (`ProductionNavalRules`, `ProductionManager._naval_production_allowed`).
- **Build new shipyard:** `FactoryManager.create_shipyard_for_province(province_id, owner_tag, levels)`.
- **Convert existing factory:** `FactoryManager.convert_factory_to_shipyard(factory_id, levels)` (port province only).
- `data/production/factory_rules.json` includes a `shipyard` block with `build_cost` / `convert_days` for future timed/costed conversion UI.

---

## 4. Resource Consumption & Shortages

### Current State
- Designs carry `daily_resource_cost` (steel, aluminum, fuel, electronics, etc.).
- **Player-facing majors (8):** steel · aluminum · **energy** · fuel · rubber · electronics · **specials** · **fissiles** (see `docs/RESOURCE_PRODUCTION_STRATEGIC_DESIGN.md` and `production_cost_rules.json` → `major_resources`).
- Province deposits stay typed (coal, oil, uranium…) for plant icons; coal/gas/biomass feed **Energy**; oil feeds **Fuel** (+ Energy conversion); uranium → **Fissiles** (unlock).
- `get_design_resource_preview()` and updated info methods expose daily costs for UI.
- Shortages apply `resource_shortage_penalty` on the line (reduces production speed; floor ~55% in `production_cost_rules.json`).
- Production **continues** during shortages (does not halt completely).
- **Critical resources** (electronics, rubber, specials, fissiles, …) use stronger weighted fill ratios than common materials.
- Finished units under shortage carry a lower **`shortage_reliability_multiplier`** (logged on completion; hook for combat/readiness later).
- National stockpile is consumed proportionally when supply is partial (`ProductionManager.evaluate_line_resources`).
- **Ops triad** (separate from factory majors UI): manpower · supplies (food feeds this) · fuel.

### Harvest & plants (implemented)
- **`ResourceHarvestCalculator`** + `resource_harvest_rules.json`: province deposits auto-fold into the 8 majors (aliases).
- **Daily tick:** `ProductionManager.daily_resource_harvest_tick` runs before equipment lines consume stockpile.
- **Plant types:** coal/oil/gas/hydro/biomass/nuclear/fusion energy plants; steel mill, aluminum smelter, refinery, rubber works, electronics fab, specials refinery, enrichment plant — size_tier 1–5 scales output; no equipment lines.
- **Tech:** plastics_industry buffs rubber/electronics; synthetic_fuel converts Energy→Fuel; nuclear_fuel unlocks Fissiles + nuclear/enrichment plants; fusion_power_industry unlocks fusion plants / He-3 harvest visibility.
- **Ops:** food/grain deposits feed **supplies** (not a factory major).

### Recommended Future Behavior
- Connect consumption to **provincial stockpiles** / `ProvinceDepotState` and supply lines instead of national pool only.
- Map UI for plant placement/upgrade (icons already type-keyed in harvest rules).
- Food→supplies **stability** cohesion; surface shortage severity on Production Assignment UI.
- Optional: **partial production** variants (lower-quality unit when specific inputs are missing).

### Design Intent
- Missing critical resources should hurt more than missing steel/energy.
- Shortages should motivate exploration, synthetics, trade, and conquest of resource-rich areas.
- Soft shortage model: `strategic_stockpile_soft_shortage`.

---

## 5. Future UI / Player-Facing Notes

### Retooling Warning Popup (High Priority)
- Must clearly communicate trade-offs before allowing the change.
- Should show both immediate effect and long-term recovery time.

### Factory Visual State
- Factories in retooling should have a distinct visual state (icon, progress bar, color tint, or animation).

### Production Assignment Screen (Planned)
- Show per-factory: current design, efficiency, daily output, resource cost, retooling status, slot usage.
- Allow player to assign / reassign lines and see concentration bonuses in real time.
- Show equipment shortages for active units (see Option 4).

---

## 6. Equipment Shortages & Unit Readiness

### Current Implementation
- **`EquipmentShortageTracker`**: `calculate_shortages`, readiness multiplier (max ~70% penalty, floor 0.3), organization multiplier.
- **`DivisionTemplate.required_equipment`** / **`UnitTemplate.required_equipment`**; divisions fall back to `equipment[]` counts when explicit dict is empty.
- **`ProductionManager`**: per-unit stock (`set_unit_equipment_stock`), `get_unit_shortages`, `get_shortage_report`, `apply_equipment_shortage_modifiers` (combat hook).
- Example formation: `us_infantry_division_1943` in `data/formations/division_templates.json`.

### National equipment stockpile (wired)
- Finished production adds to `national_equipment_stockpile` via `production_completed` → `_on_production_completed`.
- APIs: `add_to_national_stockpile`, `take_from_national_stockpile`, `get_national_stockpile_amount` (equipment ints; raw materials remain in `national_stockpile` floats).
- Units pull gear with `request_equipment_for_unit` and `auto_reinforce_unit_from_stockpile`.
- `get_unit_shortages` counts **unit stock + national pool**; true gaps only when both are insufficient.
- `get_unit_shortage_report_with_national` adds `national_stockpile_available` per equipment type for UI.
- **Reinforcement:** `auto_reinforce_unit_from_stockpile`, `reinforce_all_units`, `daily_reinforcement_tick`; priority units served first via `set_unit_priority_reinforcement`; `unit_reinforced` signal on fulfillment.
- **Combat stats:** `get_combined_combat_modifiers()` and `get_final_combat_stats(shortages)` on divisions; `ProductionManager.get_division_final_combat_stats(division_id, unit_id)` is the single hook for combat (infantry + sustainment + shortage penalties).

### Equipment taxonomy (design)
- **Infantry Equipment**: produced small arms (rifle/SMG/LMG by type + generation).
- **Sustainment Equipment**: abstracted bulk gear (uniforms, helmets, grenades, basic ammo, entrenching tools).

### Declaring infantry equipment on divisions
- **Division default:** `infantry_equipment_template` (e.g. `infantry_k98_bolt_action`).
- **Equipment block:** `{"type": "infantry", "count": 12000, "infantry_equipment_override": null}` uses the division default unless override is set.
- **Subunit overrides:** each subunit in `subunits[]` may set its own `infantry_equipment_template`.
- **API:** `DivisionTemplate.resolve_subunits()` → `get_aggregated_infantry_stats()`; `ProductionManager.get_division_infantry_stats(id)`.

### Infantry equipment templates (`data/unit_templates/infantry_equipment/`)
- Fields: `infantry_equipment_type`, `infantry_equipment_generation`, combat stats, `infantry_equipment_per_soldier`, `sustainment_equipment_per_soldier`, `description`.
- Examples: K98k (gen 1), M1 Garand (gen 2), StG 44 (gen 3), M2 Browning HMG, M16A1 (gen 4).
- **Sustainment Equipment** (`data/unit_templates/sustainment_equipment/`) = abstracted bulk gear (uniforms, helmets, grenades, ammo, tools); affects supply consumption, readiness, and reliability—not combat stats. Templates: `basic_sustainment`, `improved_sustainment`, `engineer_sustainment`, `marine_amphibious_sustainment`. Divisions set `sustainment_equipment_template`; subunits may override. Included in `get_required_equipment()` for stockpile/reinforcement flow.

### Future
- Infantry equipment type/generation JSON stats and sustainment costs per soldier.
- Surface `get_shortage_report` on the Production Assignment UI.

---

## 7. Next Development Priorities (Current Order)

1. ~~**Equipment Shortage & Unit Readiness** (Option 4)~~ (foundation done)
2. ~~Scenario loading + automatic factory spawning from 1918/1936 data~~ (`ScenarioFactorySpawner` on load)
3. Connect resource consumption to actual provincial stockpiles / Supply system
4. ~~Enforce shipyard port location rules~~ (done)
5. Add technology & focus modifiers for retooling time + recovery speed
6. Build the actual Production Assignment UI screen
7. Timed/costed shipyard **build** and **convert** flows using `factory_rules.json` shipyard costs

---

## 8. Open Design Questions

- ~~Should we allow building **new shipyards** in port provinces, or only converting existing factories?~~ **Both are supported** (build via `create_shipyard_for_province`, convert via `convert_factory_to_shipyard`).
- How harsh should resource shortages become on **reliability** of finished units? (Current floor ~72%; tune in `production_cost_rules.json` → `resource_shortage`.)
- Do we want a "partial production" system where missing resources produce a lower-quality variant?

---

## Future Work – Phase B (Infantry Equipment)

- Make `infantry_equipment_per_soldier` and `sustainment_equipment_per_soldier` dynamic based on `infantry_equipment_generation` and `infantry_equipment_type`.
- Adjust production cost and retooling time when switching between different generations of infantry weapons.
- Allow divisions to show "Infantry Equipment Quality" in the UI based on the generation they are using.
- Consider adding a small combat bonus/penalty when mixing generations inside the same division.

---

## Future UI / Quality of Life Features (High Priority)

### Unit Information & Reinforcement Panel
- Show current **Infantry Equipment** and **Sustainment Equipment** counts on every unit.
- When a unit has taken losses or is understrength, clearly display:
  - What equipment is missing to return to full strength.
  - How much is available in the National Stockpile.
  - Estimated time to produce the missing equipment at current production rates.
- This information should be easily viewable on a **Unit Info Panel**.

### Division Design Screen
- When designing a new division, clearly show:
  - Total equipment required across all categories (Infantry Equipment, Sustainment Equipment, tanks, artillery, trucks, etc.).
  - Whether the player currently has enough equipment in the National Stockpile to field the unit immediately.
  - If not enough equipment exists: show estimated time until production can fulfill the requirement.
- Training should only begin once the required equipment is available (or partially available with penalties).

### Smart Production Advisor (Future Feature)
- When the player wants to field a new division (or reinforce an army), offer a **"Smart Assign"** button.
- The advisor should:
  - Analyze current factory assignments.
  - Suggest which factories/lines to reassign or prioritize to meet the equipment goal fastest.
  - Provide a time-to-completion estimate.
- This should feel helpful and transparent, not opaque.

These features will make production feel connected to actual fielded forces and reduce player frustration when trying to rebuild or reinforce units.

---

**This document should be updated as we implement new systems.**
