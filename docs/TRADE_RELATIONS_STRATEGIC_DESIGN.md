# Trade & Relations — Strategic Compact Ledger (Design Freeze)

> **Status:** Design freeze v1 · 1900–2100 · low-micro strategic  
> **Scope:** Dedicated dynamic trade, bilateral relations, AI concern flags, route-attackable flows  
> **Does not claim:** full Vic3 goods market, complete AI rewrite, or finished HOI-style trade screen chrome

## 1. Design goals

| Goal | Implication |
|------|-------------|
| **Trade and relations are equal pillars** | Every deal moves a bilateral ledger; AI never ignores opinion/trust |
| **Real-world options without micro** | Tariffs, subsidies, embargos, basing, tech, equipment, territory — few knobs, deep effects |
| **Routes matter** | Ongoing RESOURCE/EQUIPMENT/SUPPLY travels Supply routes; attackable/interceptable |
| **Era honesty** | 1910 deals ≠ 2026 (tariffs, tech IP, basing, sanctions evolve) |
| **Unique EOA identity** | Multi-vector relations + Strategic Utility Units (not civ-factory currency) |

## 2. Peer-game review (what we adopt / reject)

| Game | Adopt | Avoid |
|------|--------|--------|
| **HOI4** | Few strategic resources; trade influence from opinion/distance; export laws | Civ factories as universal currency; set-and-forget opacity |
| **Vic3** | Tariffs & subventions; economic **dependency** as diplomacy; trade policy laws | Full goods market / POP micro; daily goods assignment |
| **EU4** | Basing & access as diplomatic goods; embargo as tool; choke/node feel | Merchant/node micro micromanagement |
| **Stellaris** | Visible **acceptance** score; fair deals raise opinion | Energy-credits-only universe |
| **EOA (ours)** | Route-bound TradeFlows + interdiction + 8 majors + designs/tech/province already in backend | — |

**Rejected:** pure Vic3 market · pure HOI4 civ currency · pure EU4 merchant game.

**Model name:** `strategic_compact_ledger`

## 3. Bilateral Relations (as important as trade)

### 3.1 Vectors (−100 … +100 each; not a single “opinion”)

| Vector | Player-facing meaning | Typical movers |
|--------|----------------------|----------------|
| **public** | Popular goodwill / propaganda | Fair trade, aid, atrocities, black-market scandals |
| **elite** | Business/diplomatic corps | Tariffs, MFN, design licenses, resource dependency |
| **military** | Officer trust / access comfort | Basing, access, arms deals, joint ops |
| **alignment** | Strategic/ideological closeness | Alliances, war co-belligerence, rival blocs |
| **trust** | “Will they honor deals?” | Broken contracts, embargoes mid-flow, interdiction of their convoys |
| **dependency** | Asymmetric economic leverage | Share of majors imported from partner (Vic3-style) |

**Composite Relation Score (CRS)** for UI/AI thresholds:

```
CRS = 0.20·public + 0.20·elite + 0.20·military + 0.20·alignment + 0.20·trust
      ± dependency_tilt  (importer more captive; exporter more leverage)
```

### 3.2 Relation bands (AI deal thresholds)

| CRS band | Label | AI behavior |
|----------|-------|-------------|
| < −40 | Hostile | Gifts only / embargo preferred; refuse arms & basing |
| −40…−10 | Cold | Expensive deals; no basing; limited tech |
| −10…+25 | Neutral | Fair SUU deals OK; temporary docking maybe |
| +25…+55 | Cordial | Preferential tariffs; recurring majors; limited arms |
| +55…+80 | Partner | MFN, basing packages, tech share, joint production |
| > +80 | Ally-ready | Mutual defense packages unlock; deep basing |

### 3.3 AI Concern Flags (surfaced to player + AI)

| Flag id | Triggers | AI response |
|---------|----------|-------------|
| `resource_dependency_critical` | >40% of a major from one partner | Diversify / seize / force MFN |
| `enemy_arming` | Arms to rival of self | Protest, embargo, counter-arms |
| `tech_leak_risk` | Advanced design/tech to untrusted | Refuse / demand guarantees |
| `basing_sovereignty` | Foreign basing on core/home | Hard refuse unless ally band |
| `embargo_evasion` | BLACK deals with embargoed | Scandal, trust hit, agents |
| `tariff_war` | Escalating bilateral tariffs | Retaliate or seek third market |
| `convoy_hostility` | Interdicted their TradeFlow | Military vector crash; possible war goal |
| `black_market_scandal` | Exposed BLACK deal | Public vector hit for both |
| `territory_humiliation` | Forced province cession | Long trust/public scar |
| `sanction_web` | Multilateral embargo (late era) | Isolation economic penalty |

Flags decay or escalate monthly; AI personality (existing faction products) weights which flags dominate.

## 4. Strategic Utility Units (SUU) — unified valuation

Everything in a deal converts to **SUU** for fairness/AI (player still sees natural units).

### 4.1 Base tables (data-driven, era-scaled)

| Category | Base SUU idea | Era note |
|----------|---------------|----------|
| **Major resource** (steel…fissiles) | unit rate × scarcity × critical weight | Fissiles invisible pre-unlock |
| **Supplies / food** | lower unit rate; cohesion soft value | Ops triad link |
| **Equipment** | production_cost × reliability × scarcity | Jets/rockets fuel ops external |
| **Design / license** | cost × tech_gap_premium × quality_mod | Export downgrades (0.85) |
| **Tech share** | RP-days value × sensitivity | Nuclear/space higher gates |
| **Intel** | recon gap × threat | Temporary modifier already |
| **Province / territory** | permanent asset: pop + dev + infra + ports + resources + choke + factories × **3.5× durable premium** | Highest permanent SUU |
| **Docking / basing rights** | months × port tier × range_gain × sovereignty_cost | Military vector sensitive |
| **Military access** | duration × border_length proxy | War-only premium |
| **Alliance / guarantee** | multi-year strategic package | Alignment + military |
| **Tariff concession / subsidy** | annual flow value × rate | Policy, not goods |

### 4.2 Comparative rules of thumb (design intent)

| Item | ≈ Relative SUU scale (order of magnitude) |
|------|-------------------------------------------|
| 100 steel (ample stock) | ~100–140 |
| 1 medium tank (full cost) | ~80–150 |
| 1 modern fighter | ~120–250 |
| 1 capital ship | thousands |
| 12 months docking at major port | hundreds–thousands (location) |
| Peripheral province | thousands |
| Core/capital/port/choke province | **orders of magnitude above** a tank batch |
| Cutting-edge design license | often > peripheral province if tech gap large |

**Player lesson:** territory and basing are **state power**, not inventory. Arms are renewable; cores are not.

### 4.3 Fairness acceptance (Stellaris-like)

```
acceptance = value_received / max(value_given, ε)   # from AI evaluator POV
× relation_mult(CRS)
× risk_mult(route interdiction, black exposure)
× policy_mult(embargo, tariff_war flags)
```

- `acceptance < 0.85` → refuse  
- `0.85–1.05` → accept if no hard flags  
- `> 1.05` → accept + temporary public/elite boost  

## 5. Dedicated Dynamic Trade Screen (IA)

### Tabs / modes

1. **Bilateral Desk** — pick partner; CRS vectors; concern flags; active flows map strip  
2. **Compose Deal** — multi-slot offer/request: majors, equipment, designs, tech, intel, basing, access, territory, policy clauses  
3. **Live Convoys** — TradeFlows with route risk, weather, interdict history (reuse existing list)  
4. **Policy** — tariffs (import/export % bands), subsidies, embargo list, export controls (tech/arms)  
5. **Market** — public/black generators (existing TradeMarketView folded in)  
6. **Impact Preview** — SUU fairness, CRS predicted deltas, flag risk, dependency forecast  

### Deal impact preview (always shown before accept)

- Stockpile / production soft-shortage effect  
- CRS vector deltas  
- New/cleared AI flags  
- Dependency % change  
- Route risk summary  
- Prestige/hand_influence (black)  

## 6. Tariffs, subsidies, embargos (policy layer)

| Policy | Effect |
|--------|--------|
| **Import tariff** 0 / 12.5 / 25 / 50% | Raises partner export SUU needed; treasury skim on landing flow |
| **Export tariff** | Same on outgoing; can anger dependent partners |
| **Import subsidy** | Lowers cost of critical majors; treasury burn |
| **Export subsidy** | Dump surplus; dependency weapon |
| **Embargo** | Blocks PUBLIC deals & flows; BLACK still possible with scandal risk |
| **Export control** | Blocks DESIGN/TECH above era/sensitivity without license |
| **MFN clause** | Locks preferential tariff band while CRS ≥ Partner |

Tariffs use **base SUU**, not floating Vic3 prices (keep low-micro).

## 7. Ongoing trade = logistics war

Already partially shipped; design freezes requirements:

1. Accept RESOURCE/EQUIPMENT/SUPPLY → **TradeFlow** + `SupplyManager.find_route_for_trade`  
2. Monthly delivery scaled by sea-zone × weather × (1 − route risk)  
3. **Interdiction** (subs, surface, air, agents) calls `interdict_trade_flow` — automatic tick phase (not demo-only)  
4. Successful interdiction → cargo loss + **CRS military/trust hit** on interdictor–owner pair + `convoy_hostility` flag  
5. Escort / convoy efficiency (regional control) reduces loss  

## 8. Era progression (1900–2100)

| Era | Trade flavor |
|-----|----------------|
| 1900–1918 | Coal/steel/food, colonial resources, port basing, few tariffs bands |
| Interwar–1945 | Oil/rubber critical, arms export controls, blockade culture |
| Cold War | Fissiles gates, tech share sensitivity, sanction webs |
| 1990–2100 | Electronics/specials, dual-use export control, space-adjacent tech, fusion He-3 late |

## 9. Implementation phases

| Phase | Deliverable | Status |
|-------|-------------|--------|
| **R0** | Design freeze (this doc) | **Now** |
| **R1** | `RelationsManager` + vectors + flags pure/GD | **Shipped** |
| **R2** | `StrategicValueCalculator` SUU tables; fairness uses CRS | **Shipped** |
| **R2b** | National power + nuclear danger + hopeless matchup + AI placate | **Shipped** |
| **R2c** | Transit loss attribution (sub/air/province plain text) + delivery % | **Shipped** |
| **R2d** | Spy/diplomatic intel on relations + third-party trade; relation discounts | **Shipped** |
| **R3** | Tariff skim on flow delivery + treasury | **Shipped** (`_apply_import_tariff_skim` · `get_tariff_treasury`) |
| **R4** | Auto interdiction monthly from presence estimator | **Shipped** (`process_monthly_trade_risks` on month tick) |
| **R5** | Trade Desk UI (compose + impact + transit issues + power warning) | **Shipped** (`build_trade_desk_board` · TradeMarketView DESK mode) |
| **R6** | AI monthly: propose/accept using acceptance + flags + placate | **Shipped** (`process_monthly_ai_trade` · `ai_decide_accept`) |
| **R7** | Full basing graph write on DOCKING_RIGHTS | **Shipped** (`grant_basing_rights` · monthly expire · desk basing) |

## 10. Honesty

- Backend: TradeManager, TradeFlows, routes, interdict API, market UI shells already exist.  
- **Shipped R1–R7 + fleet follow-on:** basing graph on DOCKING_RIGHTS consumed by `get_preferred_fleet_station` / treaty score premium.  
- Still later: richer desk compose chrome, denser AI surplus logic, deeper fleet AI tasking from basing grants.

## 11. Dual evidence package

`trade_relations_primary` — catalog · value · relations · flags · close  
`trade_power_intel_primary` — catalog · power · transit · spy · close  
`trade_desk_primary` — catalog · interdict · tariff · desk · close (R3–R5)  
`trade_ai_primary` — catalog · propose · accept · refuse · close (R6)  
`trade_basing_primary` — catalog · grant · query · expire · close (R7)  
`basing_fleet_station_primary` — catalog · score · grant · prefer · close (fleet consumes basing graph)  
Model: `strategic_compact_ledger`
