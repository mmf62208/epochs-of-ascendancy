# Space Strategic Layer — Solar System → Galaxy (Design Freeze)

> **Status:** Design freeze v1.3 · 2026-07 · S0–S7 shipped (survey · fog board · terraform · galaxy · duals)  
> **Scope:** Full Sol multi-site graph, tech gates, SpaceFlows, habitability, colony CRS, survey, layer fog, terraform, sparse galaxy bridge  
> **Does not claim:** full 3D solar sim, photoreal map chrome, or dedicated multiplayer server (N4)  
> **Model name:** `orbital_compact_ledger`  
> **Builds on:** Earth strategic compact ledger (trade/relations R0–R7), space race milestones, space designer stub, strategic_future tech

---

## 1. Honest current foundation (what we already have)

| Existing | State |
|----------|--------|
| **Tech gates** | `strategic_future` nodes: rocketry → sputnik → manned → moon → station → mars; flags `allow_satellites`, `allow_manned_space`, `allow_lunar_operations`, `allow_moon_base`, `allow_space_station`, secret/public branches |
| **Milestones / events** | `GameData.process_space_race_events` — 8 firsts, prestige, competition, secret fleet flavor |
| **Design surface** | `SpaceDesignPopup` — satellite / station / spacecraft modules (stub depth) |
| **Units / modules** | Rockets, sats, stations, shuttles, NTR tug, Starlink/Sputnik buses, etc. |
| **Earth logistics** | TradeFlows + basing graph + interdiction + tariff — **pattern to lift into space** |
| **Missing** | Solar body graph, orbit slots, colony sites, space routes, Mission Control budget, terraform, galaxy layer |

**Design rule:** space is not a disconnected minigame. Every space loop must **touch Earth** (boost/MC, politics, industry, intel, war) and later **touch other nations in space** the same way Earth trade can be raided.

---

## 2. Peer-game review (adopt / reject / EOA twist)

| Game | Adopt | Avoid | EOA twist |
|------|--------|--------|-----------|
| **Terra Invicta** | Body-centric map (Earth→Luna→Mars→asteroids→outer); **Boost** loft cost; **Mission Control** cap; probe→site→outpost→colony; space resources feed industry | Faction-only politics (EOA is nation-state grand strat); pure alien focus as only late game | Nations **compete and interdict each other** in orbits; public vs secret programs already seeded |
| **Sins of a Solar Empire II** | Visible trade routes between ports; **raidable** trade; multi-system scale; colonization of planets as logistics nodes | Full RTS fleet micro as default; free-for-all multi-star from day 1 | Routes start **cis-lunar**, then heliocentric corridors; same interdict API family as Earth TradeFlows |
| **Stellaris** | Survey → anomaly → special project; claims; starbases as chokepoints; mid/late expansion cadence | Pop micro / 1000+ systems early; hyperlane-only fantasy until gates | **Survey rings** on bodies; secrets of universe as **deep-time projects** not cookie-cutter anomalies |
| **The Expanse (TV / fan sims)** | Water/air as life-support logistics; Belter vs Earth politics; stealth fleets; epstein-drive logistics | Pure soft SF free travel | **Secret fleet** + **life support** majors already partially in tech; make **volatiles / propellant** space majors |
| **HOI4 + space mods** | Layered unlocks, designers, equipment | Space as pure modifier dump | Designers stay, but **map presence** required for real power |
| **Endless Space / Master of Orion** | Colony specialization, ship roles | Separate 4X detached from Earth history | Colonies **report to a nation-state** (or break away via dependency/trust vectors) |

**Rejected as core:** daily orbital mechanics micro · full N-body physics · galaxy-wide play before solar mastery · pure energy-credits space currency.

---

## 3. Layer architecture (what the player unlocks)

### 3.1 Map layers (UI / data)

| Layer id | Visible when | Contents |
|----------|--------------|----------|
| `earth_surface` | Always | Existing world_full grand strategy |
| `near_earth` | `allow_satellites` or first_satellite | LEO / MEO / GEO slots, polar orbits, early stations |
| `cis_lunar` | `allow_lunar_operations` | Earth–Moon transfer corridor, Luna sites, L1/L2 anchorages |
| `inner_system` | `allow_mars_ops` or mars probe milestone | Mars, Venus corridor (harsh), near-Earth asteroids |
| `outer_system` | Late tech (fusion / NTR / outer probes) | Jovian moons, ice giants, Kuiper outposts |
| `galaxy_bridge` | Post-solar mastery + deep FTL/relay tech (far future) | Sparse **stellar systems** as strategic nodes — not full Stellaris density at first |

**Gating honesty:** you do **not** open the solar map by year alone. You open rings of **access** via tech flags + milestones + optional secret programs. UI can show **fogged silhouettes** of locked layers (“classified / not yet reached”).

### 3.2 Graph model (data)

```
SpaceBody  → sites[] (surface hex-abstract slots)
OrbitSlot  → body_id, band (leo/meo/geo/transfer/lagrange), capacity
SpaceHabitat → host (body site | orbit slot), tier, modules, owner_tag
SpaceRoute   → from_node, to_node, corridor_type, interdiction_risk
```

Mirror Earth:

| Earth | Space |
|-------|--------|
| Province / port | Site / orbit slot |
| TradeFlow | SpaceFlow (cargo: propellant, metals, food, people, intel) |
| `interdict_trade_flow` | `interdict_space_flow` (ASAT, patrol, mine, piracy, solar storm) |
| Basing grant | Docking/refuel rights at foreign station (already conceptual on Earth basing graph) |
| CRS vectors | Same RelationsManager — basing_sovereignty becomes **orbital sovereignty** |

---

## 4. Resources & economy (space majors)

Keep low-micro: **few strategic majors**, not full Vic3 goods.

| Space major | Role | Earth link |
|-------------|------|------------|
| **boost** | Launch capacity from Earth (virtual “lift budget”) | Factories + spaceports + policy |
| **mission_control** (MC) | Soft cap on habitats + fleets you can run | Bureaucracy / electronics / trained staff |
| **propellant** | Moves everything; shortages strand fleets | Fuel industry + ice mining offworld |
| **structural_metals** | Hab expansion / ships | Steel/aluminum/specials export to orbit |
| **volatiles** | Life support (H₂O, N₂, O₂ abstracted) | Food/cohesion if colonies starve |
| **fissiles / antimatter** (late) | High-Δv drives, strategic weapons | Existing fissiles unlock path |
| **rare_samples** | Survey discoveries → tech RP / events | Intel + Ascendancy |

**Critical design:** early game is **Earth-subsidized** (Boost + MC from home). Mid game **in-situ** mining reduces Boost dependence (TI lesson). Late game **space industry** can out-produce Earth for certain specials — creating **dependency vectors** on Earth politics (who owns the Belter mines?).

---

## 5. Expansion loop (player-facing stages)

```
1. Reach   → unlock layer (satellite / manned / lunar)
2. Survey  → probe body/orbit (fog → known sites + hazards)
3. Claim   → plant flag / soft claim (relations flags if contested)
4. Build   → outpost → settlement → colony (or platform → orbital → ring)
5. Sustain → SpaceFlows of propellant/food/parts; MC upkeep
6. Specialize → mine / shipyard / science / bastion / garden (terraform track)
7. Project power → interdict corridors, support Earth wars, secret fleets
8. Bridge  → galaxy nodes (sparse) only after solar industrial base
```

### 5.1 Survey & secrets of the universe

Not spam anomalies. **Few high-value discoveries** per body class:

| Discovery class | Example payoff |
|-----------------|----------------|
| Resource assay | Opens high-yield site |
| Hazard map | Permanent route risk modifier (radiation belt, debris) |
| Deep-time relic | Multi-year project → tech branch or crisis |
| Biosignature / terraforming candidate | Unlocks garden path |
| First-contact signal (optional alt) | Grand narrative — **not** required for solar play |

**Survey clarity** reuses spy intel pattern: mission success + network + satellite constellation clarity.

### 5.2 Terraform (late, rare)

Terraform is a **multi-decade megaproject**, not a button:

1. **Candidate** (survey)  
2. **Seed atmosphere / ice import** (SpaceFlows — raidable)  
3. **Stability crises** (events: storm loss, ethics of ecology, rival sabotage)  
4. **Garden colony** unlocks food surplus export **to Earth** (reverses early dependency — huge political story)

Only 0–2 garden worlds per campaign should feel realistic; Mars is the default candidate, not every rock.

---

## 6. Space trade & supply (interdictable)

### 6.1 SpaceFlow (mirror TradeFlow)

- Created when habitats import/export or when Earth loft packages.  
- Path = ordered nodes: `earth_surface_port → LEO depot → transfer → Luna L1 → Luna site`.  
- Monthly advance: delivery × (1 − corridor risk) × weather/solar storm mult.  
- **Interdiction causes:** `asat`, `patrol_cutter`, `minefield`, `piracy`, `solar_storm`, `debris_cascade`.  
- Attribution plain text: *“ASAT strike in LEO corridor near node X sank 40% of propellant convoy.”*  
- Relations: `convoy_hostility` / new `orbital_hostility` flag; military vector hit.

### 6.2 Why this is fun (vs passive modifiers)

- Player can **starve** a rival moon base without invading Earth.  
- Escort fleets / treaty basing at stations (extend Earth basing graph into orbit).  
- Solar storms = “weather” for space (reuse weather chain compose idea).  
- Secret fleets get interdict bonus but scandal if exposed (existing secret path).

---

## 7. Colony control & maintenance (the hard part done interestingly)

### 7.1 Control is not ownership alone

Each habitat tracks:

| Field | Meaning |
|-------|---------|
| **owner_tag** | Legal nation (or corp charter under nation) |
| **admin_mode** | `direct` · `charter` · `military_gov` · `open_port` |
| **loyalty** | Soft 0–100 (public vector proxy for colony pop) |
| **autonomy** | How much local AI decides builds |
| **supply_buffer** | Months of volatiles/propellant on hand |
| **mc_cost** | Mission Control drain |
| **strain** | Overextension from distance × under-supply |

### 7.2 How control fails (interesting failure modes)

| Failure | Trigger | Outcome |
|---------|---------|---------|
| **Starvation cascade** | Volatiles SpaceFlow cut > N months | Loyalty crash → riot event → possible charter revolt |
| **MC overload** | Too many habitats | Global soft malus to all space ops (not hard delete) |
| **Distance strain** | Outer system without local propellant | Autonomy auto-rises; Earth orders delayed |
| **Identity fracture** | High autonomy + low Earth CRS | New “colonial faction” pressure (not instant new country; event chain) |
| **Corporate charter capture** | Agent / elite vector | Habitat legally yours but elite vector favors foreign capital |
| **Rival claim war** | Contested site | Limited space war without full Earth war (or with it) |

### 7.3 Maintaining colonies (player levers)

1. **Sustain routes** — protect SpaceFlows (escorts, basing, diplomacy).  
2. **Local ISRU** — invest mine modules to cut Boost/propellant imports.  
3. **Admin laws** — military gov (control↑ loyalty↓), open port (trade↑ spy risk↑).  
4. **Leaders** — assign colonial governor (reuse LeaderManager traits: logistician, explorer, hardliner).  
5. **Agents** — counterintel on stations; fund/suppress independence.  
6. **Political narrative** — public space prestige vs secret bases (existing branch).  
7. **Earth cohesion link** — colonial atrocities or miracles swing home public vector.

**Fun principle:** maintenance is a **logistics + legitimacy** puzzle, not a tax slider. Cutting a single corridor should feel like cutting Suez — not like missing a city tax.

---

## 8. Combat & power projection (light at first)

| Phase | Space combat depth |
|-------|-------------------|
| S1–S2 | Presence + interdict only (no full 3D combat) |
| S3 | Fleet engagement resolve using existing CombatResolver space flags (shields/phaser/ASAT already flavored) |
| S4 | Doctrine: orbital denial, convoy escort, planetary assault (drop troops to sites) |

Link to Earth: destroying a rival’s LEO ISR constellation should **hurt their Earth recon** (existing space_recon_bonus path).

---

## 9. Galaxy layer (later, deliberately sparse)

Only after **inner-system industrial self-sufficiency** (rule flag `solar_industrial_base`):

- 5–15 **stellar systems** as nodes (not 400).  
- Each system has 1–3 bodies worth of abstract sites.  
- **Relay routes** between systems = long SpaceFlows with high interdict / isolation risk.  
- Discovery of “secrets of the universe” lives here as **campaign-defining** projects (1–3 max).

Avoid Stellaris sprawl until the solar game is already deep.

---

## 10. What makes EOA space *different*

1. **Nation-state continuity** — same tags, CRS, agents, HH, pillars from 1918→2100.  
2. **Earth always matters** — Boost/MC, politics, industry; colonies can reverse the dependency.  
3. **Interdict culture** — we already built route attack honesty on Earth; space is the same language.  
4. **Public vs secret** — Expanse-style hidden fleets vs Apollo prestige.  
5. **Designers** — player-built sats/stations/ships with module truth.  
6. **Alt-history** — steampunk/mech/secret branches can reach space on weird paths.  
7. **Ascendancy fantasy** — garden worlds and deep-time secrets are endgame *meaning*, not only DPS.

---

## 11. Implementation phases

| Phase | Deliverable | Status |
|-------|-------------|--------|
| **S0** | Design freeze + pure gate/graph/route model + dual evidence | **Shipped** (`space_layer_primary` dual green) |
| **S1** | Full Sol multi-site + habitability + orbital command + space power threat + independence math | **Shipped** (`space_depth_primary` dual) |
| **S1b / S2** | SpaceLayerManager autoload + SpaceFlow interdict/monthly | **Shipped** (`space_ops_primary` dual) |
| **S3** | Parent CRS · range interact · independence tick · landing/bombard · save/load | **Shipped** (`space_colony_primary` dual) |
| **S4** | Survey missions + discovery events | **Shipped** (`space_survey_primary` dual) |
| **S5** | Map layer fog board + view toggle | **Shipped** (`space_fog_primary` dual) |
| **S6** | Terraform megaproject track | **Shipped** (`space_terraform_primary` dual) |
| **S7** | Galaxy bridge sparse nodes | **Shipped** (`space_galaxy_primary` dual) |

---

## 12. Dual evidence packages

- `space_layer_primary` — catalog · gates · graph · routes · close (S0)  
- `space_depth_primary` — catalog · sites · capacity · power · close (S1)  
- `space_ops_primary` — catalog · claim · habitat · flow · close (S2)  
- `space_colony_primary` — catalog · relations · independence · combat · close (S3)  
- `space_survey_primary` — catalog · launch · advance · discover · close (S4)  
- `space_fog_primary` — catalog · fog · reveal · view · close (S5)  
- `space_terraform_primary` — catalog · start · advance · garden · close (S6)  
- `space_galaxy_primary` — catalog · unlock · claim · board · close (S7)  
- `space_supply_primary` — catalog · lift · flow · board · close (commercial lift + sustain)  
- `space_supply_ai_primary` — monthly AI sustain flows + optional lift buy  
- `space_survey_events_primary` — discovery → campaign event chains (no re-fire)  
- `space_board_ui_primary` — `SpaceLayerBoardView` player chrome  
- `space_open_path_primary` — TopInfoBar + Diplomacy open board  
- `space_rival_survey_primary` — AI rival survey competition  
- `space_discovery_choice_primary` — discovery player choices (one-shot resolve)  
- `space_discovery_ui_primary` — board surface list + resolve + re-resolve blocked  
- `matchmaking_lobby_primary` — `MatchmakingLobbyView` player lobby (not NAT/WebRTC)  
- Related: `n3_network_primary` / `n4_dedicated_primary` / `matchmaking_primary` — multiplayer ladder (+ thin queue matchmaking)

Model: `orbital_compact_ledger`

---

## 13. Open design questions (for playtest)

1. Soft vs hard MC caps? (recommend soft strain first)  
2. Can non-space powers buy lift on foreign boost (charter)?  
3. How fast can independence fire? (recommend multi-year event chain)  
4. Are asteroids individual sites or “belts” as one body with many sites? (recommend belt body + N sites)

---

## 14. Capacity naming (not “Mission Control”)

| Name | Role | Player-facing |
|------|------|----------------|
| **Lift capacity** | How much mass you can send from Earth (spaceports, boost industry, reusable fleets) | “Launch budget” |
| **Orbital command** | How many concurrent habitats/fleets you can run (stations, electronics, trained crews) | Replaces TI “Mission Control” label |
| **Expansion strain** | Soft **mandate/cohesion** drag when command or distance overextends | Not a hard block — mismanagement hurts politics |

Hard-cap only industrial truth (no lift → cannot stage); soft-cap politics for overreach.

## 15. Space power in diplomacy & threat

- Space fleets + orbital weapons + bombardment-capable hulls raise **space_power_index**.  
- Integrated into `NationalPowerCalculator.effective_threat`.  
- **Undefended surface** (bombardment-capable attacker, defender orbital_defenses ≈ 0) multiplies space threat — soft cousin of nuclear asymmetry.  
- AI placate / hard bargain when hopeless vs space-capable peer.

## 16. Combat (naval analogy)

- Engagements **not guaranteed** — spotting via radar/ISR, range falloff, stealth fleets.  
- Then resolve like fleet combat (existing ship combat vein).  
- Surface strike requires bombardment loadout + orbital window.  
- Planetary assault needs **landers / dropships / shuttles** (landing_craft_required list).

## 17. Habitability & life support

Axes: pressure, temp, radiation, gravity, local volatiles/metals.  
Bands: garden / harsh / hostile / orbital / cryogenic.  
Life-support majors: **food, water, oxygen, propellant, energy** (not only abstract “volatiles”).  
Larger bodies = many **capture_sites** (Luna 8, Mars 10, Ceres 6); tiny asteroids = 1 site, low pop/building caps, rolled resources.

## 18. Colony relations & independence

- Parent–colony CRS-like vectors (public, elite, military, trust, dependency).  
- Third parties only if **range/comms** allow.  
- Independence: **generational** (~25y), min ~20y, slow autonomy drift if neglected; mitigations (ISRU, governors, charter, culture).  
- Not instant secession.

## 19. Commercial lift & tech access

Non-space powers **may buy surplus lift** and must acquire tech via research, trade, or theft before founding advanced colonies.

## 20. Summary for builders

**Space is a gated, layered logistics civilization game sitting on top of our Earth grand strategy.**  
Unlock by tech/milestones → survey multi-site bodies → stage via stations/Moon → sustain with **raidable SpaceFlows** → space power shapes Earth diplomacy → colonies drift over a generation if neglected.
