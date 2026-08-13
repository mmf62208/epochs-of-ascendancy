# Strategic Resources — Production & Combat Integration Design

> **Status:** Design freeze v2 (1900–2100) + soft-shortage integration slice  
> **Scope:** 1900–2100 campaigns; low-micro strategic stockpiles  
> **Does not claim:** full engine rewrite, trade UI, or Vic3 goods market

## 1. Design goals

| Goal | Implication |
|------|-------------|
| Resources **matter** | Shortages change production speed/reliability; fuel hits ops mobility |
| **No micro** | Province *sources* vary; player sees few stockpiles, not daily goods assignment |
| **Era honesty** | WWI/WWII players never see late unlocks (He-3, antimatter, etc.) |
| **Tech-driven** | Plastics = tech modifiers; energy plant *types* scale with tech/size, all feed Energy |

## 2. Player-facing majors (8 strategic inputs)

| # | Major | Player sees | Province / tech sources (hidden detail) | Production | Combat / ops | Scarcity lever |
|---|--------|-------------|------------------------------------------|------------|--------------|----------------|
| 1 | **Steel** | Always | Iron, steel industry | Hulls, armor, guns, ships, infantry eq | Repair / rebuild tempo | Mines + industry |
| 2 | **Aluminum** | Always (ramps interwar+) | Bauxite, light industry | Airframes, light structure | Air generation | Control + trade |
| 3 | **Energy** | Always (primary “power” meter) | Coal, natural gas, oil-as-power, biomass/wood (early), hydro, nuclear plants, fusion (late) | Industry throughput; conversion into Fuel | Home-front tempo | Sources + plant tech/size |
| 4 | **Fuel** | Always (mobility meter) | Oil fields, synthetics from Energy, gas-to-liquid (tech) | Motor/air/naval/rocket **lines** | **All vehicles burn Fuel**; jets & rockets burn more; ships/logistics | Oil + Energy→Fuel conversion |
| 5 | **Rubber** | Always | Tropical rubber, synthetics (tech; plastics age buffs efficiency) | Tires, seals, air/ground | Mobility readiness | Tropics + synthetics |
| 6 | **Electronics** | Always (critical weight) | Copper → radio → computers → semiconductors | Sensors, FC, high-end air/naval/space | Detection, accuracy, C3 | Advanced industry |
| 7 | **Specials** | Always (critical weight) | Chromium, tungsten, nickel, rare earths, explosives chain | High-end alloys, special ammo, quality modules | Quality edge | Sparse deposits |
| 8 | **Fissiles** | **Unlocked ~1940s+** | Uranium (map), enrichment projects | Reactors, nuclear propulsion, warhead programs | Strategic power / late navy | Sparse + tech gates |

**Aliases** fold map/province tags into these eight (see `production_cost_rules.json` → `major_resources`).

### Energy: many plants, one meter

- Province deposits stay **typed** (coal / oil / gas / uranium / etc.) for realism and plant icons.
- Each **energy plant** (or province extraction node) has a **type icon** (coal plant, oil burner, gas, hydro, fission, fusion…).
- All types contribute to national **Energy income** (and oil-class sources can also contribute to **Fuel** feedstock via refining).
- **Scale without micro:** plant output = base(province) × tech_efficiency × size_tier × doctrine. Player upgrades **size/tech/doctrine**, not daily fuel mix clicks.
- Wood/dung/biomass: early/low-dev **Energy** sources only; not separate majors.

### Fuel burn (ops + production)

| Consumer | Relative Fuel burn (design intent) |
|----------|-------------------------------------|
| Early trucks / armor | Baseline |
| Jets | Higher than prop |
| Rockets / missiles / space launch | Very high |
| Naval steaming | High continuous |
| Production lines (motor/air/naval/rocket) | Daily **Fuel** cost on the line |

Fuel is **one stockpile**, drawn by factories *and* operations.

## 3. Ops triad (force sustainment — not factory goods UI)

| Pool | Role |
|------|------|
| **Manpower** | Raise, reinforce, training |
| **Supplies** | Ground sustainment; food/logistics abstraction feeds this |
| **Fuel** | Shared with production; mobility/sorties |

**Food:** not an 9th factory major. It feeds **Supplies** income and **stability/cohesion** (and can soft-gate manpower recovery). Visible as supply/stability levers, not a second industrial stockpile UI.

## 4. Tech modifiers & late unlocks (not always visible)

| Item | Treatment |
|------|-----------|
| **Plastics** | Tech modifier: improves **Rubber** and **Electronics** efficiency / shortage resilience (no separate stockpile) |
| **Helium-3** | Endgame/scenario unlock; feeds **Energy** or advanced Fuel conversion when visible |
| **Antimatter** | Endgame-only; not in WWI/WWII UI or resource browser |
| **Fissiles** | Major #8; hidden until nuclear-era unlock / scenario year |

**Visibility rule:** resource browser and mapmode only list majors with `unlocked_for_player` (era/tech/scenario). Locked icons never appear in 1918/1936 campaigns.

## 5. Peer-game review (unchanged recommendation)

| Game | Adopt | Avoid |
|------|--------|--------|
| **HOI4** | Few strategic resources; conquest/trade matter | Mandatory trade-click micro |
| **Stellaris** | Soft shortage empire-wide | — |
| **Vic3 market** | Goods *feel* real | POP/goods micro |

**Rejected:** full goods market · hard line halt · dozens of niche stocks · permanent He-3/antimatter majors.

**Model:** `strategic_stockpile_soft_shortage` — fill ratio, critical weighting, production continues slower/worse under shortage.

## 6. Shipped integration (first slice)

| Piece | Location |
|-------|----------|
| Major registry (8) | `data/production/production_cost_rules.json` → `major_resources` |
| Shortage math | `ProductionCostCalculator` (+ `ProductionManager` daily tick) |
| Pure product + tests | `tools/map_generation/lib/resource_production_shortage_product.py` |
| Dual package | `resource_production_primary` |

## 7. Shipped harvest / plants / tech (second slice)

| Piece | Location |
|-------|----------|
| Harvest rules | `data/production/resource_harvest_rules.json` |
| Calculator | `scripts/production/ResourceHarvestCalculator.gd` |
| Daily tick | `ProductionManager.daily_resource_harvest_tick` (before equipment lines) |
| Plant factory types | `factory_rules.json` + `FactoryManager.create_resource_plant_for_province` |
| Tech tree | `data/technology/trees/resource_industry.json` (+ uranium/fusion unlocks) |
| Pure + dual | `resource_harvest_economy_product` · `resource_harvest_primary_live` |

## 8. Shipped economy depth (third slice)

| Piece | Location |
|-------|----------|
| Food → supplies → cohesion | `compute_food_cohesion_delta` + harvest tick → `apply_pillar_shift` |
| Production reliability → combat | stamped on complete; scales formation soft/hard/readiness |
| Plant auto-seed / upgrade | `FactoryManager.auto_seed_resource_plants` · scenario spawner · size tiers |
| Fuel ops burn | jets/rockets > trucks; `ProductionManager.burn_ops_fuel` |
| Dual package | `resource_economy_depth_primary_live` |

## 9. Shipped open-items surface (fourth slice)

| Piece | Location |
|-------|----------|
| Plant place / upgrade surface | `FactoryManager.place_resource_plant` · `get_plant_browser_for_province` · upgrade |
| He-3 / antimatter year deposits | `apply_endgame_deposits` · ScenarioLoader after factory spawn |
| Majors trade | `TradeManager.create_major_resource_trade` · `build_major_resource_trade_board` |
| Browser visibility | `build_resource_browser` (fissiles/endgame gated) |
| Dual | `resource_open_items_primary_live` |

## 10. Later phases (still open)

- Full graphical plant **mapmode panel** (surface APIs live; rich editor chrome later)  
- Dedicated Trade **screen** chrome (board/offer APIs live)  
- He-3/antimatter **authored** world_full deposit maps (injector covers year-gated bootstrap)  



## 11. Balance notes

- **Energy + Fuel** split: industry can run on coal-heavy Energy while Fuel stays oil-short (historical Axis problem).  
- **Critical:** electronics, rubber, specials, fissiles (when unlocked).  
- Soft floor ~55% production speed under empty stockpile keeps agency mid-war.
