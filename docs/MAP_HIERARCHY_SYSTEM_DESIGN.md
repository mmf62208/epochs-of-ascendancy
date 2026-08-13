# EOA Hierarchical Map Division System

**Status:** Phase 1–4 design + product schema (2026-07-13)  
**Game:** Epochs of Ascendancy (Godot 4)  
**North star:** County-scale maneuver at Tier 1; geographic theater strategy at Tier 3–4; border history **1900–2100+** without remeshing the world every year.

---

## Phase 1 — Overall hierarchy definition & global guidelines

### 1.1 Four-tier model (locked)

| Tier | Name | Real-world analog | Size rule | Game roles |
|------|------|-------------------|-----------|------------|
| **1** | **Province** | County / NUTS-3 / district / colonial district (merged when sparse) | Atomic playable cell | Movement, combat, pick, resources, pop, ownership flips, infrastructure sites |
| **2** | **State / Area** | US state, historical province, French département group, colony | **5–20 provinces** typical (3–30 hard bounds) | Production caps, recruitment pools, laws, state politics, VP clusters |
| **3** | **Region** | Midwest, Levant, West Africa, Western Europe… | **Multiple states** (~4–20) | Supply theaters, air/naval assignment, AI fronts, weather bands, major events |
| **4** | **Super-region / Theater** | Continent / grand theater | **Multiple regions** (~2–8) | WW UI, multiplayer zones, late-game blocs, strategic overview |

**Invariant:** Province IDs are the only **atomic** membership unit. States, regions, and super-regions are **groupings** of province IDs (plus metadata). A province always belongs to exactly one state, one region, and one super-region at a given moment (after full bind).

```
Super-Region (Theater)
  └── Region (strategic / geographic)
        └── State / Area
              └── Province  ← atomic for borders, combat, pathing
```

### 1.2 Count targets (global v1 → world-class)

| Scope | Provinces (land) | States | Regions | Super-regions |
|-------|------------------|--------|---------|---------------|
| **Current scaffold** (`world_full`) | ~2.3k land / 2.7k total | ~152 | ~34 | 5 |
| **Europe densify pilot** | ~1.8k land | ~196 | 10 | 1 |
| **Shippable v1 “good board”** | **~6k land** (band **5–7k**; ~5–8k total w/ sea) | **600–1,200** | **120–180** | **10–16** |
| **World-class stretch** | **8–12k** land | **1.5–2.5k** | **180–250** | **12–20** |

**Locked (2026-07-13):** Aim **~6k** provinces as the first performance/playability bar. Prove **60 fps** in that 5–7k band before pushing toward 8–12k. Do **not** target HOI4 ~13k as day-one default.

### Locked product decisions

| Decision | Choice |
|----------|--------|
| US Tier-3 regions | **8-band:** Northeast, Mid-Atlantic, Southeast, Midwest, Great Plains, Southwest, Mountain West, Pacific |
| Global province target | **~6k** within 5–7k; **60 fps first** |
| Membership eras (full snapshots) | **1910, 1918, 1936, 2026** (primary, `mode=full`) |
| Secondary membership | 1945 optional / thinner OK |

### 1.3 Density classes (global guidelines)

| Class | Where | Province grain | Vertex budget | State size |
|-------|-------|----------------|---------------|------------|
| **Dense** | Europe core, US East/Midwest, Japan, Korea, Levant, N. China plain, India core, UK | Real county/NUTS-3 | 32–72 | 5–12 provinces |
| **Medium** | US West, Brazil core, Mexico, Anatolia, SE Asia mainland, Maghreb | 2–5 county merges | 24–48 | 8–16 |
| **Sparse** | Siberia, Sahara, Amazon, Outback, Canadian North, Congo interior | Area+climate merges | 16–28 | 12–30 |

**Front-depth rule (Dense land borders):** operational cut across a contested frontier should cross **≥6–10** provinces (not 2–3 scaffold blobs).

**Sacred micro-provinces (always keep):** Gibraltar, Malta, Suez corridor cells, Hormuz littoral, Bosporus, Channel ports, Kiel, Panama, Singapore/Malacca land anchors — even if tiny.

### 1.4 Super-region catalog (recommended 12)

| ID | Super-region | Dense cores | Sparse bulk |
|----|--------------|-------------|-------------|
| 1 | Europe | West/Central/East Europe, Balkans, British Isles, Nordics | European Russia steppe edge |
| 2 | MENA | Levant, Anatolia, Egypt, Gulf | Sahara, Arabia empty quarter |
| 3 | Africa (sub-Saharan) | Coastal hubs, Nile south, SA | Sahel, Congo basin, Kalahari |
| 4 | South Asia | India/Pakistan belt | Himalaya/Thar sparse |
| 5 | East Asia | China coast, Korea, Japan | Tibet, inland Mongolia |
| 6 | SE Asia–Pacific | Vietnam/Thai/Malaya cores | Archipelago merges |
| 7 | North America | US East/Midwest, S. Canada belt | Arctic, deserts |
| 8 | Latin America | Mexico, Brazil coast, Andes spine | Amazon, Patagonia |
| 9 | Central Asia–Siberia | — | Steppe + Siberia bulk |
| 10 | Oceania | SE Australia, NZ | Outback |
| 11 | Global Seas | Strait/choke sea zones | Open ocean large cells |
| 12 | Arctic / High North (opt.) | — | Ice/land edge |

### 1.5 Data principles for 1900–2100+

| Principle | Rule |
|-----------|------|
| **Mesh stability** | Province polygons rarely change. History is **tags + membership**, not new meshes per year. |
| **Ownership eras** | `province_ownership_{year}.json` — seed once at scenario `start_date`; **never** reapply on year tick. |
| **Membership eras (optional)** | `hierarchy_membership_{year}.json` can rebind province→state/region for empire reorgs without changing geometry. |
| **Player agency** | After load, conquest/events/peace own live owners; tables do not clobber. |
| **ID stability** | Never renumber shipped province IDs. Split = new child IDs + parent inheritance. Merge = supersedes list. |
| **Namespaces** | world_full existing IDs; Europe pilot `700000+`; US pilot `800000+`; future GIS Europe may map onto pilot or new block with remap table. |

### 1.6 Dynamic border / membership model

| Change type | What moves | Example |
|-------------|------------|---------|
| **Annexation / peace** | Province `owner_tag` / `controller_tag` | 1938 Sudetenland |
| **Occupation** | Controller without full ownership | Wartime France |
| **State reassignment** | Province leaves State A → State B | Post-partition admin reform |
| **New state** | New state ID + province list | 1947 India/Pakistan; player formable |
| **Decolonization** | Owner tags + optional new states | 1960s Africa |
| **Secession 2100** | New country tag + state split event | Scripted formable |
| **Rare split province** | Geometry event + inheritance | Late-game mega-province only |

**Clean vs gory borders:** both are province-set diffs. “Clean” = whole states transfer. “Gory” = cherry-pick provinces; states recompute remaining members.

### 1.7 Systems implications

| System | Reads tier | Notes |
|--------|------------|-------|
| Pathfinding / combat | Province adjacency | Shared-edge graph preferred over KNN |
| Supply | Region + province infra | Hubs at state capitals / region depots |
| Production / recruitment | State | IC/manpower rolled from member provinces |
| AI fronts / theaters | Region + super-region | Fronts span regions; grand AI at super |
| Events / focus | Any tier by ID | Prefer region/state keys over raw province lists when possible |
| Mapmodes | Owner @ province; tint by state/region | LOD: state fill at mid zoom, region at far |

---

## Phase 2 — Continent / theater guidelines (summary)

### United States
- **Tier 1:** TIGER counties (merge sparse West / Alaska by area).
- **Tier 2:** Real US states (+ DC, territories as states or special).
- **Tier 3 regions (locked 8-band):** Northeast, Mid-Atlantic, Southeast, Midwest, Great Plains, Southwest, Mountain West, Pacific.
- **Tier 4:** North America (with Canada/Mexico as separate regions under same super or split supers).

### Europe
- **Tier 1:** NUTS-3 / national districts; islands per island viability rules.
- **Tier 2:** Historical provinces + modern admin (Bavaria, Flanders, Île-de-France, Catalonia…).
- **Tier 3:** British Isles, Iberia, France, Low Countries, Germany, Italy, Nordics, Balkans, Central Europe, Eastern Frontiers, Western Mediterranean (aligns with pilot).
- **Tier 4:** Europe.

### Colonial / post-colonial
- Mesh from colonial districts where known; **ownership eras** carry 1910 empires → 1960 independence → 2026 modern.
- Prefer **stable districts**; do not rebuild mesh for every independence year.

### Sparse continents
- Merge until front depth and supply still make sense; never equal-density densify deserts.

---

## Phase 3 — Sample data structures

See live schema in:

- `tools/map_generation/lib/hierarchy_system_product.py`
- `data/hierarchy_samples/us_midwest_sample/`
- `data/hierarchy_samples/europe_core_sample/`
- `docs/MAP_HIERARCHY_JSON_SCHEMA.md`

### Canonical fields

**Province (existing `provinces_base` + layers)**  
`id`, `name`, `domain`, `theater`, `terrain`, resources, pop…

**State (`province_states.json`)**
```json
{
  "id": 101,
  "name": "Ohio",
  "province_ids": [800001, 800002],
  "capital_province_id": 800001,
  "region_id": 12,
  "owner_hint": "USA",
  "tags": ["us_state"]
}
```

**Region (`strategic_regions.json`)**
```json
{
  "id": 12,
  "name": "Midwest",
  "province_ids": [800001, 800002],
  "state_ids": [101, 102],
  "super_region_id": 7,
  "theater": "north_america"
}
```

**Super-region (`super_regions.json`)**
```json
{
  "id": 7,
  "name": "North America",
  "region_ids": [12, 13, 14],
  "theaters": ["north_america"]
}
```

**Bindings (`hierarchy_scaffold.json`)**
```json
{
  "province_to_state": {"800001": 101},
  "province_to_region": {"800001": 12},
  "province_to_super_region": {"800001": 7},
  "four_tier": true
}
```

**Optional membership era (`hierarchy_membership_1910.json`)**  
Only province→state/region diffs vs default scaffold for historical admin reorgs.

---

## Phase 4 — Implementation recommendations (EOA)

### Already landed
- Four-tier load in `ScenarioLoader` (`get_hierarchy_for_province` includes super_region).
- Gazetteer state names (no `Area N` placeholders).
- Ownership eras seed-only 1910–2026.
- Europe densify pilot + world_full scaffold hierarchy.
- Pure gates + map CI hooks.

### Build next (ordered)
1. **Shared-edge adjacency** for pilot + world_full (combat/supply truth).
2. **US pilot dir** `provinces_pilot_us` IDs `800000+` (TIGER or densify interim).
3. **Hierarchy membership API** in GameData: reassign province↔state at runtime for peace/events.
4. **NUTS-3 Europe replace** of densify geometry (id-stable or remap table).
5. **Sparse global fill** to 4–7k; then optional push toward 8–12k.
6. Mapmodes: state / region borders at appropriate LOD.

### Performance budget
- Province mesh batching + LOD already partially present.
- Region/super queries must be O(1) via `province_to_*` maps (not scan arrays each frame).
- Inspector chips may show hierarchy; never rebuild full graph in `_process`.

### Dev discipline
- Dual SCRIPT 0; never `EOA_HEADLESS_EVIDENCE=1` for dual proof.
- Pure tests for name hygiene, bind integrity, 5–20 province/state bounds, four-tier coverage.
- Pilot remains opt-in; `world_full` stays F5 default until GIS QC.

---

## Success criteria checklist

| Criterion | Measure |
|-----------|---------|
| Natural GS feel | Playtest: recognize Midwest / France / Levant as regions |
| Divisional maneuver | Dense fronts ≥6 provinces deep |
| Strategic value of regions | AI + supply + events key off region IDs |
| Historical flexibility | Ownership + membership eras; no mesh rewrite per year |
| Dynamic borders | Province atomic flips; state recompute |
| Performance | Dual green at chosen N; LOD holds |

---

## Related docs

- `docs/MAP_HIERARCHY_AND_GIS_ROADMAP.md` — GIS path + honesty status  
- `docs/MAP_HIERARCHY_JSON_SCHEMA.md` — field reference  
- `docs/WORLD_CLASS_MAP_ROADMAP_AND_DELIVERABLES.md` — broader map program  
