
> **Implementation note (2026-07-17):** CP0–CP6 / RF0–RF6 dual residual packages are **shipped**. Prefer playtest + balance (`docs/PLAYTEST_AND_DECISION_GUIDE.md`) before opening new residual dual packages.
# Reinforcement, Experience & Training Logistics — Design Freeze

> **Status:** Design freeze v1.0 · 2026-07 · **direction lock** for non-instant reinforce + experience  
> **Scope:** Manpower/equipment reinforcement *time*, supply-hub distance, resource constraints, combat experience dilution, training/recruitment policies (1900–2100+), era mobility (rail → air → drone → space)  
> **Builds on:** `COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md` (EquipmentFlow), SupplyManager depots/hubs, manpower laws, Formation strength/org, CombatResolver  
> **Does not claim:** full HOI division designer XP UI, every historical draft law, real-time individual soldier sim  

---

## 0. Why this freeze exists

Players reported (and design agrees): **instant full-power replacements break the story of war**.

A meaningful campaign needs:

1. **Time** — replacements and gear take days/weeks to arrive; distance and mode matter.  
2. **Friction** — supply hubs, corridor risk, and resource shortages slow or starve reinforce.  
3. **Experience** — green drafts are not veterans; mass replacement dilutes combat effectiveness.  
4. **Asymmetry of skill** — trained troops re-equipping learn tools faster than recruits learn war.  
5. **Policy** — recruitment and training laws are strategic choices with trade-offs across eras.  
6. **Era leap** — 1916 rail vs 2025 airlift vs 2080 orbital cadre lift feel *different*.

**Locked model name:** `reinforce_experience_logistics_ledger`  
(Companion to `equipment_flow_compact_ledger` and `strategic_stockpile_soft_shortage`.)

---

## 1. Peer / real-world inspiration (adopt / avoid / EOA twist)

| Source | Adopt | Avoid | EOA twist |
|--------|-------|-------|-----------|
| **HOI4** | Reinforce rate, experience levels, training, conscription laws | Opaque “magic reinforce” without map story | EquipmentFlow + hub distance as visible transit |
| **Steel Division / Graviteam** | Experience bands matter in combat | RTS 1:1 always | Formation-level XP band, not individual soldiers |
| **WW1–WW2 history** | Green replacements after Somme/Verdun/Kursk; cadre retention | Pure fatalism | Cadre retention formula preserves some XP |
| **Cold War / US AVF** | All-volunteer quality vs mass draft quantity | Single best law | Law matrix with cohesion/IC/manpower trade-offs |
| **Modern air mobility** | Strategic airlift shortens weeks → days | Free teleport | Fuel + lift capacity soft caps |
| **TI / space fiction** | Orbital loft for critical cadres | Empire-wide free teleport early | Space support tech gate + command/lift cost |
| **Clone / VR fiction** | Fast fill options with quality or ethics costs | Free super-soldiers | Explicit policy rows with scars |

**Rejected as core:** instant full TOE + full veteran XP on the same day as a battle; ignoring hub distance; treating rearm and recruit refill as identical XP events.

---

## 2. Inventory — what already ships

| Piece | State | Role going forward |
|-------|--------|-------------------|
| EquipmentFlow transit + interdict | CP1–CP2 shipped | **Canonical gear movement** — never silent teleport for default path |
| Supply depots / hubs + route reinforce mod | Shipped | **Distance & hub access** feed transit mult |
| Formation `strength` / org / readiness | Shipped | Strength recovers only as replacements *arrive* |
| Formation `is_trained` / training_progress | Partial | Peacetime training path for XP floor |
| Manpower pools + conscription laws | Shipped | **Quantity** side of recruit fill |
| Officer training quality (LeaderManager) | Shipped | Complements unit XP; officers ≠ enlisted XP |
| Leader combat XP | Shipped | Separate from formation troop XP |
| CombatResolver strength mult | Shipped | Add **formation combat_experience** mult |

### Gaps this freeze closes

| Gap | Pain |
|-----|------|
| Default reinforce still too “same day full” in places | Battles feel disposable |
| No formation combat experience band | Greens fight like veterans |
| No explicit rearm-vs-recruit XP rules | New tanks ≠ new men |
| Era mobility under-modeled on reinforce time | 1914 and 2030 feel the same |
| Training policy shallow vs 1900–2100+ menu | Few meaningful draft/training decisions |

---

## 3. Two pipelines (never conflate)

### 3.1 Equipment rearm (tools to warriors)

```
Country equipment stockpile
  → EquipmentFlow(mode, path, hub-aware days)
  → Formation province / unit stock
  → Small XP hit (rearm friction) if design changes or mass re-equip
  → Veterans keep most combat_experience (cadre knows war; learns tool)
```

### 3.2 Manpower replacement (bodies into ranks)

```
National manpower / training pipeline (policy XP of recruits)
  → Replacement draft batch (green…regular depending on law/training days)
  → Transit / depot stage (same hub distance story)
  → Strength recovery on formation
  → **Blend** combat_experience toward recruit XP (can drop hard after slaughter)
```

**Locked asymmetry:**  
`rearm_xp_penalty << manpower_refill_xp_penalty` for the same fraction of TOE.

Plain language: *It is easier for hardened troops to learn a new rifle than for fresh draftees to become hardened troops.*

---

## 4. Time model (non-instant by default)

### 4.1 Transit days

```
transit_days = max(min_days,
    base_mode_days × hops × distance_factor
    ÷ (era_mobility × hub_access × resource_fill × training_throughput)
)
```

| Factor | Meaning |
|--------|---------|
| `base_mode_days` | rail/road/airlift/helicopter/sealift/drone_logistics/orbital |
| `hops` | Path nodes / theater legs |
| `distance_factor` | Normalized distance from **nearest friendly supply hub/depot** (and factory for pure gear) |
| `era_mobility` | Year/tech band mult (see §5) |
| `hub_access` | Depot fill + control of corridor (0.55–1.25) |
| `resource_fill` | Fuel/supplies/electronics soft shortage mult (0.5–1.0) |
| `training_throughput` | National training policy mult for *manpower* batches only |

**Default gameplay path:** EquipmentFlow + manpower drafts advance daily; **no force_deliver** except tests/debug.

### 4.2 Partial daily caps

Even after arrival, a formation can only absorb:

- Equipment: limited by flow amount + org (disrupted units re-equip slower).  
- Strength: limited daily recover (e.g. 2–8% TOE/day after arrival, modified by policy/hub).  

**No same-tick jump from 40% → 100% strength with full XP** under default rules.

---

## 5. Era mobility (1900–2100+)

| Era band | Years (guide) | Dominant reinforce modes | Typical theater transit |
|----------|---------------|--------------------------|-------------------------|
| `rail_age` | 1900–1935 | rail, road, sealift | Weeks across continent |
| `motor_air_dawn` | 1936–1955 | rail + motor + limited airlift | Days–weeks |
| `airlift_age` | 1956–1995 | strategic airlift, helo, sealift | Days for priority |
| `network_drone` | 1996–2040 | airlift + drone logistics/recon of corridors | Hours–days priority |
| `orbital_support` | 2041–2100+ | airlift + limited orbital cadre loft | Hours critical; still costly |

Tech / focus unlocks **shift era_mobility** and unlock modes (`drone_logistics`, `orbital`).  
Space support never becomes free infinite teleport for whole armies in this freeze.

---

## 6. Combat experience (formation band)

### 6.1 Scale

| Band | XP (0–100) | Combat mult (soft/hard/org feel) |
|------|------------|----------------------------------|
| Green | 0–20 | ~0.78–0.88 |
| Trained | 21–40 | ~0.90–0.98 |
| Regular | 41–60 | ~1.00 |
| Seasoned | 61–80 | ~1.05–1.12 |
| Veteran / elite | 81–100 | ~1.12–1.22 (soft cap) |

Stored on Formation as `combat_experience` (float 0–100).  
Default spawn ~40–50 (trained/regular). Training raises floor; combat raises slowly; slaughter + green refill drops.

### 6.2 Blend on manpower refill

```
fraction = strength_added / strength_after   # 0–1 of TOE just filled by recruits
recruit_xp = policy_recruit_xp(training_law, training_days)
new_xp = (1 − fraction) × old_xp + fraction × recruit_xp
new_xp += cadre_bonus × (1 − fraction)      # surviving cadre mentors (small)
```

Heavy losses → large `fraction` → XP collapses toward green.  
Light top-ups preserve veterans.

### 6.3 Blend on equipment rearm only

```
rearm_fraction = equipment_added / toe_equipment_need
new_xp = old_xp − rearm_penalty × rearm_fraction × novelty
```

`novelty` high when design generation jumps (WW1 rifle → assault rifle); low for same-gen resupply.  
`rearm_penalty` ≪ manpower blend impact.

### 6.4 Combat gain

Surviving combat raises XP slowly (intensity × outcome).  
Leader XP remains separate (already shipped).

---

## 7. Training & recruitment policy matrix (player decisions)

National policy set (extends demographic/manpower laws). Each row is a **selectable law or investment**, not free stacking of all bonuses.

| Policy id | Era | Manpower qty | Recruit XP | Training days | Cohesion / IC cost | Notes |
|-----------|-----|--------------|------------|---------------|--------------------|-------|
| `volunteer_cadre` | all | low | high | long | low strain | Professional core |
| `short_conscript` | 1900–1950 | high | low–mid | short | strain | Mass armies |
| `two_year_service` | 1900–1990 | mid–high | mid | mid | moderate | Classic continental |
| `wartime_crash` | war | very high | very low | minimal | high strain | Emergency drafts |
| `selective_service` | 1940–1975 | mid | mid | mid | political risk | US-style selective |
| `all_volunteer_force` | 1973+ | lower peak | higher | long | wage/IC pressure | Quality focus |
| `reserve_recall` | cold war+ | surge | mixed | recall delay | family/cohesion hit | Trained reserves |
| `national_service` | cold war+ | mid | mid | fixed term | domestic politics | Broad baseline |
| `nco_academy_focus` | all | — | +cadre_bonus | — | IC/officers | Mentorship mult |
| `live_fire_centers` | 1950+ | — | +recruit_xp | −days | fuel/ammo | Realistic training |
| `drone_sim_school` | 2000+ | — | +tech arms XP | −days | electronics | Operators |
| `vr_holodeck_pipeline` | fiction/future | mid | mid–high | short | ethics/energy | Fast but uncanny valley risk |
| `clone_batch_fill` | fiction | extreme | very low | near-zero | ethics/scandal | Quantity crisis tool |
| `cyber_conscript` | 2030+ | specialist | high (cyber) | mid | privacy unrest | Not front-line infantry |
| `space_cadre_loft` | 2040+ | tiny elite | high | long + loft | lift/command | Orbital insertion of cadres only |

**Key decisions (player-visible):**

1. Law: quantity vs quality.  
2. Training investment: time and resources before deploy.  
3. Reserve vs active balance.  
4. Emergency crash mobilization (short-term strength, long-term XP scar).  
5. Future options unlock only with tech — never all free in 1914.

---

## 8. Resource & hub coupling

| Input | Effect on reinforce |
|-------|---------------------|
| Fuel | Airlift/helo/drone modes starve without it |
| Supplies | Daily absorb rate & hub_access |
| Electronics | Drone logistics / network modes |
| Manpower pool | Hard gate on strength fill |
| Depot stock at hub | If empty, flows wait or divert |
| Corridor control | Interdict + hub_access |

Soft shortage slows; hard empty stock **blocks** that mode (fallback to slower mode if available).

---

## 9. Combat connection

CombatResolver (and previews):

```
power *= strength
power *= experience_combat_mult(combat_experience)
org/readiness friction if green under fire (already partial via strength)
```

Shortages and EquipmentFlow remains as shipped.  
Green mass armies can still win by weight — but pay org collapse and higher losses (future CP5 munitions loop optional).

---

## 10. Layered micro

| Layer | Behavior |
|-------|----------|
| **Default** | Auto EquipmentFlow + auto manpower draft; XP blend automatic; transit from hub |
| **Intermediate** | Priority reinforce, mode choice (rail vs airlift), training law change |
| **Deep** | Escort flows, training centers, reserve recall timing, future loft cadres |

---

## 11. Phased roadmap

| Phase | Deliverable | Exit |
|-------|-------------|------|
| **RF0** | This freeze + audit dual | **Shipped** doc locked |
| **RF1** | Pure transit/XP math + Formation XP + blend on reinforce + hub/era factors | **Shipped** dual: time_ok · exp_ok · hub_ok |
| **RF2** | Default non-instant daily path (flows, absorb caps); combat mult from XP | **Shipped** dual: non_instant_ok · combat_xp_ok |
| **RF3** | Training policy matrix live (subset of laws) | **Shipped** dual: policy_ok |
| **RF4** | Era tech unlocks drone/orbital modes wired | **Shipped** dual: era_mode_ok |
| **RF5** | UI plain stories (“greens diluted 3rd Army XP”) | **Shipped** dual: xp_plain_ok · transit_ok · story_ok |
| **RF6** | AI doctrine for crash vs cadre | **Shipped** dual: peace_ok · war_ok · ai_policy_ok |

**Honesty:** Full “meaningful reinforce forever” is RF1–RF6. RF0 freezes direction; RF1 ships math + first dual.

---

## 12. Decision summary

1. **Never instant full veteran restore** on default path.  
2. **Gear and men are different pipelines** with different XP rules.  
3. **Hub distance + resources + era mobility** set clock.  
4. **Experience is a formation band** that combat reads.  
5. **Training/recruit laws** are strategic choices across 1900–2100+ and fiction.  
6. **Extend** EquipmentFlow + manpower + Formation — do not delete stockpile systems.

---

## 13. Dual / residual package

- Pure: `reinforcement_logistics_product`  
- Live dual: `reinforcement_logistics_primary_live=1` … `time_ok` · `exp_ok` · `hub_ok` · `ok=true`  
- Model: `reinforce_experience_logistics_ledger`

---

## 14. Amendment rule

Changing §3 pipelines, §6 XP blend asymmetry, or §5 era bands requires an explicit amendment entry. Implementation goals may fill RF1–RF6 without reopening those locks unless playtests force a documented change.
