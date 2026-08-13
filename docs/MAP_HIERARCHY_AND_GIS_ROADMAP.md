# Map hierarchy & real-world boundaries roadmap (EOA)

> **Pack H update 2026-07-15:** NUTS-3 promote remap product landed — `tools/map_generation/lib/nuts3_promote_remap_product.py` writes `data/provinces_pilot_europe_nuts3/nuts3_to_world_full_overlap.json` via nearest-centroid overlap. **Never renumbers world_full IDs** (`renumber_world_full: false`). Dual-board play: keep `EOA_SCENARIO=world_pilot_europe_nuts3` as Europe GIS board; world_full remains id-stable.

# Map hierarchy & real-world boundaries roadmap (EOA)

**Honest status (2026-07-13):** You *are* on the correct play map (`world_full`, **2665** provinces). It is **not** a finished HOI4/Vic/EU-grade board. Geometry is seed + Natural Earth *hint* stamp, not real counties. Ownership is approximate major-power spheres. States/regions layers exist but are thin placeholders. Product systems (orders, war goals, AI, designers) are far ahead of the **map board quality**.

That mismatch is why the screenshot looks “random blobs” and why county/region design is the right next strategic investment.

---

## What you are seeing (screenshot)

| Symptom | Cause |
|---------|--------|
| Scattered red/blue/green land blobs | Political fill by owner tag; ENG alone owns ~1100 land tiles (colonial sphere paint) — not historical 1936 borders |
| No clear Germany/France shapes | Only ~55 GER / ~186 FRA provinces; shapes are procedural, not admin GIS |
| Dark hex-like ocean tiles | Water provinces + sea-zone coloring (low-vertex cells read as geometric) |
| Labels floating mid-sea | Province/nation labels without good name data (many `name: null`) |
| Polys vs “map art” feel wrong | World underlay + poly canvas are loosely aligned (`gis_align_method: hint`, often `gis_ne_snapped_verts: 0`) |
| Click / zoom / scroll dead | Often **LoadingScreen input blocker** still STOP if hide is delayed; dual camera paths (MapRenderer + CameraController) |

**There is not a second “finished” secret map** you are missing. Optional denser Europe slices (`provinces_full_europe` ~460, phase1 test) exist for tooling, but the default play path is `world_full`.

---

## Recommended hierarchy (aligns with your 4-tier thinking)

| Tier | In-game name | Real-world base | Count target (global) | Game role |
|------|----------------|-----------------|------------------------|-----------|
| **1** | **Province** | County / district / NUTS-3 / colonial district (merged in sparse areas) | **6k–12k** land (start ~4–6k) | Movement, combat, pop, resources, border flips |
| **2** | **State / Area** | US state, French région, historical province, colony | **800–2.5k** | Production, recruitment, laws, local politics |
| **3** | **Strategic region** | Midwest, Levant, West Africa, European Russia… | **120–250** | Supply theaters, air/naval, AI fronts, weather |
| **4** | **Super-region / Theater** | Continents / grand theaters | **10–20** | WW-scale UI, late game, multiplayer zones |

### Density rules (your Siberia/Africa idea — correct)

- **Dense:** Europe, Japan, Korea, Levant, India core, US East/Midwest, China coast — prefer real counties/districts (or NUTS-3).
- **Medium:** US West, Brazil core, Mexico, Turkey, SE Asia — counties or 2–5 county merges.
- **Sparse merge:** Siberia, Sahara, Amazon, Australian outback, Canadian north, Sahara, Congo basin — **merge** admin units until province area is playable (~HoI4 large state size), but keep **province IDs stable** for history.

Never renumber IDs casually once content ships — use add/split with inheritance.

---

## Best data sources (build, don’t freehand)

| Source | Use |
|--------|-----|
| **Natural Earth 10m / 50m admin 1** | Countries + first-level (states) for Tier 2 scaffold |
| **GADM / geoBoundaries** | Finer admin (counties) for Tier 1 in dense theaters |
| **US Census TIGER counties** | US Tier 1 |
| **Eurostat NUTS-3 / national open data** | Europe Tier 1 |
| **Historical shapefiles** (CShapes, historical borders projects) | 1910/1919/1936/1945/1991 overlays for *ownership* eras, not necessarily mesh rewrite |
| **Existing EOA NE pipeline** | `tools/map_generation/scripts/*gis*`, `ne_full` stamp — extend to **admin polygons**, not land-only hint |

**Pipeline (recommended order):**

1. **Ingest** admin polygons → normalize CRS → project to EOA world canvas (same equirectangular as `geometry_space: world`).
2. **Simplify** (Visvalingam / Douglas–Peucker) with theater-specific vertex budgets (dense 40–80 verts, sparse 16–28).
3. **Merge** sparse provinces by area + pop density rules.
4. **Build adjacency** from shared edges (not centroid KNN alone).
5. **Assign hierarchy:** province → state → strategic region (static tables + editable JSON).
6. **Ownership eras:** 1900 / 1914 / 1936 / 1945 / 1991 / 2026 as *data layers*, same IDs.
7. **QC dual:** SCRIPT 0, pick-grid, no orphan land, coast alignment screenshots.

---

## How this enables 1900–2100 borders

- **Mesh stays mostly fixed** at province level (with rare split/merge events).
- **Ownership, state membership, and region membership** change via data/events (decolonization, partition, Anschluss, Soviet collapse, hypothetical 2050 secessions).
- Dynamic **province split** is advanced (later): only when a county is too large for a late-game theater — not required day one.

---

## What is already in the repo vs gaps

| Layer | Now | Gap |
|-------|-----|-----|
| Province geometry | 2665 world canvas, NE land *hint* | Real admin coasts/borders |
| Ownership | Approximate 1936 spheres | Real historical tags + minors |
| Strategic regions | ~34 K-means-ish labeled regions | Curated 150–250 theaters |
| States | 9 placeholders (`State 1`…) | Real states 800+ |
| Names | Mostly missing | Localized names |
| Map UX | Modes, overlays, perf hooks | Input reliability + geometry alignment |
| Product systems | Deep (58 majors) | Wait for board — or play Europe-dense slice |

---

## Recommended proceed order (practical)

### Phase A — Stop the bleeding (1–2 days)
1. **Hard-dismiss LoadingScreen** + never leave `MOUSE_FILTER_STOP` on after load.
2. **Single camera owner** (CameraController authoritative for pan/zoom).
3. **Visual QC mode:** political only, hide water fill noise, show province outlines on land only.
4. Document “scaffold board” in UI so testers know this isn’t final art.

### Phase B — Europe + US pilot (2–4 weeks) — **highest value**
1. Ingest **Europe NUTS-3** (or national counties) + **US TIGER counties**.
2. Merge tiny islands/enclaves; keep ~1.5k–2.5k provinces for Europe+US pilot.
3. Build states + strategic regions for those theaters only.
4. Ship dual on a `world_pilot_eu_us` data dir while rest of world stays scaffold.

### Phase C — Global fill (months)
1. Sparse-merge GADM for Africa, Siberia, SA, Australia.
2. Colonial 1900/1936 ownership tables.
3. Sea zones as real ocean provinces (fewer, larger).
4. Full 8k–12k only if performance budget holds (LOD already started).

### Phase D — Historical eras & dynamic politics
1. Multi-year ownership snapshots.
2. State creation/destruction decisions.
3. Optional province split toolkit for late-game.

---

## Counts to aim for (first shippable “good” board)

| Theater | Provinces | States | Strat regions |
|---------|-----------|--------|----------------|
| Europe dense | 1,200–2,000 | 80–150 | 25–40 |
| US+Canada | 800–1,200 | 60–80 | 12–20 |
| Rest of world (merged) | 2,000–4,000 | 400–800 | 80–120 |
| **Total v1** | **~4,000–7,000** | **~600–1,000** | **~120–180** |

Only later push toward 10k+ if needed.

---

## Answers to your questions

**“Can you create real counties and match regions?”**  
Yes — as a **GIS pipeline project**, not a one-session polish. Data sources above + EOA’s existing map_generation tools are the right path. AI can implement scripts and QC; art underlay alignment is separate.

**“Merge counties in Siberia/Africa?”**  
Yes — mandatory for playability. Use area + population + climate zone merges, preserve coast/river edges where possible.

**“Am I not seeing the correct map?”**  
You are on the correct **default** map. It is an **incomplete** strategic scaffold. The long way is real: **product depth ≠ map board finished**.

**“Best proceed?”**  
1. Fix input + camera so you can test.  
2. Commit to **Europe+US real-admin pilot** as the quality bar.  
3. Keep sparse world as merged scaffold.  
4. Wire hierarchy JSON (province→state→region) as first-class data before more cosmetic overlays.

---

## Guardrails (EOA discipline)

- No silent province ID renumbering of shipped IDs.  
- Dual `world_full` / pilot dir green.  
- Pure geometry/adjacency tests in map CI.  
- Ownership/history as data layers, not hard-coded meshes per year.

---

## Status update (2026-07-13) — pilot dual green

| Board | Role | Count | Dual |
|-------|------|------:|------|
| `provinces_world_full` | **Default** F5 scaffold | 2665 | SCRIPT ERROR **0** · ownership seed · hierarchy live |
| `provinces_pilot_europe` | **Opt-in densify pilot** (IDs `700000+`) | **1840** land (~4× europe_core) | SCRIPT ERROR **0** · `states=196` `regions=10` `super=1` |
| Scenario | `data/scenarios/world_pilot_europe.json` | — | `EOA_SCENARIO=world_pilot_europe` |

**What this is / is not**

- **Is:** Parallel density lab + 4-tier hierarchy wiring + start_date ownership eras (incl. **2026**) seed-only (`reapply_on_year_tick=false`).
- **Is not:** NUTS-3/GADM cartography. Procedural median-split densify — label **PILOT**, not final Europe.

### Consensus path (Producer + Designer + Skeptic)

1. Keep `world_full` default; pilot never silent-default without banner.
2. Next tickets: **(1)** shared-edge adjacency QC · **(2)** US pilot (new ID block) · **(3)** Europe NUTS-3 replace.
3. Global v1 target **~5–7k** total provinces, not HOI 13k; sparse theaters **merge**, never densify deserts.
4. No world_full ID renumber; no dual with `EOA_HEADLESS_EVIDENCE=1`; SCRIPT 0 sacred.
5. World-class bar = GIS coasts + shared-edge adj + named hierarchy + dual green — not blob count alone.

Full decision package: `{SCRATCH}/map_goal_decision_summary.txt` · dual proof: `{SCRATCH}/map_goal_dual_proof.txt`.

### Shared-edge adjacency (landed 2026-07-15)

| Board | Method | Land shared coverage | Orphans | Dual |
|-------|--------|---------------------:|--------:|------|
| `provinces_pilot_europe` | `shared_edge_plus_knn_fallback` | ~0.99 | 0 | SCRIPT 0 |
| `provinces_world_full` | `shared_edge_plus_knn_fallback` | ~0.98 | 0 | SCRIPT 0 |

- Product: `tools/map_generation/lib/shared_edge_adjacency_product.py`
- Loader: `ScenarioLoader` loads dir adjacency into `AdjacencySystem` (`adjacency_live=1`)
- Honest: residual KNN only for cracked/orphan rings; not pure centroid-KNN

### US 8-band pilot (landed 2026-07-15)

| Item | Value |
|------|-------|
| Data dir | `data/provinces_pilot_us` |
| Scenario | `EOA_SCENARIO=world_pilot_us` |
| Province n | **~1488** land (from 186 NA scaffold × densify) |
| ID block | **800000+** (no world_full renumber) |
| Tier-3 | Locked **8-band**: Northeast, Mid-Atlantic, Southeast, Midwest, Great Plains, Southwest, Mountain West, Pacific |
| Super | North America |
| Adjacency | `shared_edge_plus_knn_fallback` · orphans 0 · coverage ~0.90 |
| Membership | Full 1910/1918/1936/2026 |
| Honesty | `geometry_quality: procedural_interim` — not TIGER GIS |

### Live membership mutation (landed 2026-07-15)

| API | Role |
|-----|------|
| `ScenarioLoader.reassign_province_membership` | Gory border: province → new state |
| `ScenarioLoader.create_state_membership` | New state from province set |
| `ScenarioLoader.transfer_state_membership` | Clean merge of whole state |
| `GameData.*_live` wrappers | Product/UI entry |

- Seed-only eras still apply once at load; **never** reapply on year tick (`reapply_on_year_tick=0`).
- Dual: `membership_live_mut=1 reassign=true create=true transfer=true`.
- **Save/load:** `hierarchy_membership_live` in GameData save blob → ScenarioLoader.apply_membership_save_data.
- **Peace annex:** `apply_peace_conference_settlement_live` creates `{WINNER} Occupied Zone` state for annexed province.
- Dual: `membership_peace_saveload=1` · peace+saveload live PASS.

### Global density pilot (landed 2026-07-15)

| Item | Value |
|------|-------|
| Dir | `data/provinces_pilot_global_density` |
| Scenario | `EOA_SCENARIO=world_pilot_global_density` |
| Land | **4650** (from 2325 scaffold ×2 densify) |
| IDs | **900000+** |
| Honesty | procedural_interim — not NUTS GIS |

### Deferred playability closed (same session)

Combat multi-phase ops · Naval multi-phase ops · HH multi-month agenda — live close APIs + dual `completion_playability_live=1`.

*Still deferred:* multiplayer · full designer suite · full-world photoreal GIS remesh · graphical 60 fps measure.

*Next:* NUTS-3 Europe fidelity; then 60 fps on density pilot.

### Full hierarchy system design (2026-07-13)

Canonical design: **`docs/MAP_HIERARCHY_SYSTEM_DESIGN.md`** · JSON schema: **`docs/MAP_HIERARCHY_JSON_SCHEMA.md`**

| Artifact | Path |
|----------|------|
| Product lib | `tools/map_generation/lib/hierarchy_system_product.py` |
| US Midwest sample | `data/hierarchy_samples/us_midwest_sample/` (IDs `800000+`) |
| Europe core sample | `data/hierarchy_samples/europe_core_sample/` (IDs `700900+`) |
| Super-region catalog | `data/hierarchy_samples/catalog.json` (12 supers) |
| Pure tests | `tools/map_generation/tests/test_hierarchy_system_product.py` |

**Contract:** Province atomic · State 5–20 provinces · Region geographic theater · Super-region grand bloc · mesh fixed · ownership + membership eras seed-only · 1900–2100 via data layers.


## Ownership era tables (implemented)

| Era | File | Role |
|-----|------|------|
| 1910 | `province_ownership_1910.json` | Pre-WWI colonial spheres |
| 1918 | `province_ownership_1918.json` | Armistice map |
| 1936 | `province_ownership_1936.json` | Interwar (default world_full) |
| 1945 | `province_ownership_1945.json` | Postwar spheres |
| **2026** | `province_ownership_2026.json` | Decolonized / modern spheres |

- Index: `ownership_era_index.json`
- Scenario load: `start_date` → `resolve_ownership_era` → seed owners once (`ScenarioLoader._apply_era_ownership_seed`)
- **Player agency:** tables are **seed only**. No reapply on year tick. Conquest/diplomacy/events own live state.
- Policy pure helper: `tools/map_generation/lib/ownership_era_product.py`

## Hierarchy scaffold (implemented)

- `province_states.json` — ~150 named states (theater+owner chunks; sparse theaters larger)
- `hierarchy_scaffold.json` — province→state/region bindings
- `strategic_regions_scaffold.json` — theater-split regions
- Rebuild: `python3 tools/map_generation/scripts/build_hierarchy_scaffold.py --write`
