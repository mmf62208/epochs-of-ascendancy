# EOA — World-Class Map Review (HOI4 / Victoria 3 structure)

**Date:** 2026-07-20 · **Scale refresh:** 2026-08-12 (live board **~3520**, not 8761/5670)  
**Role:** Source-of-truth **project + map analysis** for “map as living star” toward a full HOI4/Victoria 3–style province world.  
**Orchestration:** [`GAME_DIRECTOR_PLAN.md`](GAME_DIRECTOR_PLAN.md) · **Live status:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md)  
**Pipeline:** [`MAP_ACCURACY_BUILD.md`](MAP_ACCURACY_BUILD.md) · **Hierarchy design:** [`MAP_HIERARCHY_SYSTEM_DESIGN.md`](MAP_HIERARCHY_SYSTEM_DESIGN.md)

This is an **honest inventory + gap plan**, not a claim of commercial Paradox parity. Museum borders, 13k HOI provinces, and full V3 pop/market simulation are **out of scope** for full-test readiness.

---

## 1. What “HOI4 / Victoria 3 style map” means here

| Layer (Paradox analog) | Gameplay job | EOA equivalent on default board |
|------------------------|--------------|----------------------------------|
| **Province** | Movement, combat width, terrain, local ownership, pick target | `provinces_base` + `provinces_geometry` (~3520 cells; was ~8761 pre-sparse) |
| **State** | Construction slots, factories, population home, shared building pool | `province_states.json` (**429** states); membership **land-only** (8421/8421 land) |
| **Strategic region** | Air/naval theater scope, region control, AI focus | **31** unique region IDs · membership + `strategic_regions.json` aligned (**M0**) |
| **Super-region / theater** | Continent-scale UI, theater command | `super_regions.json` (**4**) + hierarchy scaffold |
| **Political mapmode** | Country colors, war readability | Default `political` + major color separation |
| **Resources mapmode** | Strategic goods (oil, rubber, steel…) | **Landed (M1)** — F9 + toolbar · tint from province.resources |
| **Supply / infra** | Throughput, hubs, corridors | Economy infra + KEY_I / supply overlay; hub floors |
| **Terrain** | Combat/move modifiers | `province_terrain_layer` (plains/jungle/desert/forest/mountains/sea…) |
| **Naval chokes** | Strait control, convoy stress | `naval_chokepoints.json` (**34** sea cells) |
| **Fronts** | Living war interaction | Multi-front edges + live border assault targets |

**Victoria 3 emphasis:** state-level economy and infrastructure hubs, readable political geography, population/development as first-class province stats.  
**HOI4 emphasis:** province combat topology, strategic resources, supply, air/naval regions, multi-front staging.

EOA already has the **data bones** of both on the default GIS board, plus **resources/states/terrain mapmodes (M1–M3)**, **supply corridor (M4)**, and **measured FPS samples (M5)**. Remaining gap is **human campaign notes (M6)** (+ optional graphical FPS re-sample), not “do we have a world map.”

---

## 2. Default board inventory (`world_accurate`)

### 2.1 Load path (star of F5)

| Item | Truth |
|------|-------|
| **Default scenario** | `world_accurate` (`TestRunner` / F5) |
| **Data dir** | `data/provinces_world_accurate/` |
| **Scale** | **~3520** provinces · land **~3180** · sea **340** (post US + full RoW sparse; historical **8761** then **5670**) |
| **Geometry quality** | `gis_hybrid_v1_7_row_geoboundaries_t3` |
| **Composition** | Europe NUTS-3 (710000+) · US TIGER (800000+) · RoW geoBoundaries densify (~3357 / 107 countries) · seas (950000+) |
| **Scaffold dual** | `EOA_SCENARIO=world_full` → ~2665; **IDs never renumbered** |
| **Guardrail** | No in-place renumber of `world_full` or accurate IDs |

### 2.2 Shipped layer files (read inventory)

| File | Role | Status |
|------|------|--------|
| `provinces_base.json` | Id, name, terrain/domain | Landed |
| `provinces_geometry.json` | Rings / pick polygons | Landed |
| `province_adjacency.json` | Neighbors | **shared_edge_near_vertex_plus_knn** · land shared coverage **~0.971** · 0 land orphans |
| `province_ownership_*.json` | Era paint (1910…2026) | 1936 full land owned; light era deltas |
| `province_states.json` | State list | **429** state rows |
| `strategic_regions.json` | Named strategic regions | **M0 done:** **31** rows / 31 names · multi-assign **0** · North America list **76** (from membership) |
| `super_regions.json` | Super theaters | **4** |
| `hierarchy_membership_*.json` | province→state/region/super | p2r **31** region IDs · all **8761** have a region; p2s **8421 land only**; p2sr all 8761 · **4** super IDs |
| `hierarchy_scaffold.json` | Four-tier scaffold | `four_tier=true` · **state_n 429** · **region_n 31** |
| `province_economy_layer.json` | pop, factories, infra, development | Present; hubs elevated |
| `province_city_layer.json` | City names / tiers | Capitals tier 3–4; hubs painted |
| `province_resources_layer.json` | coal/steel/oil/rubber/aluminum/chromium/tungsten | **HOI strategic paint v1** |
| `province_terrain_layer.json` | Terrain tags | plains-dominant + jungle/desert/forest/mountains/sea |
| `naval_chokepoints.json` | Strategic sea chokes | **34** IDs (Gibraltar, Suez, Malacca, Channel…) |
| `project_sites.json` | Special project stub | Present |
| `manifest_world_accurate.json` | Build truth | Present |

### 2.3 Scenario / play content on accurate IDs

| Content | Status |
|---------|--------|
| 8 major capitals (GER/FRA/ENG/USA/SOV/ITA/JAP/POL) | Land owned + city labels |
| `key_provinces` industrial hubs | 31 hubs · factories/infra elevated |
| Leaders / starting tech | Roster chain + 1936 pack alias |
| Starting OOB designs + stockpile | Landed; HOI station order capital→hubs→border |
| War loop | Headless GER→FRA + multi-front Maginot/Polish |
| Political colors | SOV ≠ GER (distinct paints) |

### 2.4 Player-facing mapmodes (runtime)

`MapRenderer.set_map_mode` currently wires:

| Mode | HOI/V3 analog | Landed? |
|------|---------------|---------|
| **political** (default) | Political | **Yes** |
| supply | Supply | **Yes** (overlay + mode) |
| development | Development | **Yes** |
| infra | Infrastructure | **Yes** |
| vitality / strain | Settlement / welfare tints | **Yes** (EOA-specific) |
| loyalty | Occupation/loyalty | **Yes** |
| weather | Weather | **Yes** |
| naval / chokepoints / occupation… | Naval/choke/occ | Partial (modes exist in renderer set) |
| **resources** (dedicated) | Resource mapmode | **Landed (M1)** — toolbar + F9 · tint from `province.resources` |
| **states** (dedicated) | State mapmode | **Landed (M2)** — toolbar + Shift+F9 · state_id fills |
| **terrain** (dedicated clean) | Terrain mapmode | **Landed (M3)** — toolbar + Ctrl+F9 · clean palette |

LOD: `MapZoomLOD.ACCURATE_BOARD_CULL_THRESHOLD` (≥7000) tightens glyphs/labels for ~8761.

### 2.5 Machine products (map / front / campaign)

| Product / harness | Proves |
|-------------------|--------|
| `test_world_accurate_board` | Orphans, NE land, ownership, capitals, TestRunner default |
| `world_accurate_capital_pick_product` + GD harness | 8 capital samples |
| `ownership_mapmode_readability_product` | Major colors + spheres |
| `map_perf_fps_harness` + M5 measured | Soft 30fps plan; **samples n=60** · p50 50.2ms · p95 53.0ms · soft 30 **FAIL** (proxy) |
| `world_accurate_multi_front_product` | Real Maginot/Polish/Alps/Baltic/CHI–JAP edges |
| `world_accurate_front_assault_product` | Ranked real border targets |
| `world_accurate_multi_front_execute_product` | Plan→weekly→assault queue on real IDs |
| `world_accurate_strategic_map_product` | Chokes + hub infra + oil floors + GER supply path |
| `world_accurate_20day` / `60day` campaign products | Machine campaign feel (not human notes) |
| `HeadlessWorldAccurateAssaultEntryTest` | GER 710173→FRA 710739 can+execute |
| `HeadlessWorldAccurateMultiFrontAssaultTest` | Maginot + Polish dual edge + live border collector |
| `MapManager.collect_live_border_assault_targets` | Live AI assaults enemy borders (not own stations) |

---

## 3. Landed vs gap — “map as living star”

Honest matrix for player interaction quality. **Human campaign narrative (M6)** is **not** claimed done. **M5 FPS samples are landed** (proxy; soft 30fps FAIL honest).

| Capability | HOI/V3 need | Landed? | Evidence / gap |
|------------|-------------|---------|----------------|
| **Province → state → strategic region hierarchy** | Core structure | **Landed (M0)** | 429 land states · **31** regions (file=membership) · 4 super · multi-assign 0 |
| **GIS-accurate world default** | Trustworthy geography | **Landed** | Default F5 · NE land hit ≳0.99 · QC hard_ok |
| **Adjacency / path topology** | Combat movement | **Landed** | Coverage ~0.971 · residual KNN ~3% islands/cracks |
| **Political readability** | Major wars readable | **Landed (machine)** | Distinct major colors · ownership spheres |
| **Capitals pickable** | Click capitals | **Landed (machine)** | 8/8 exact harness · human click still recommended |
| **Industrial hubs** | V3/HOI power centers | **Landed** | key_provinces + economy/city polish |
| **Strategic resources** | HOI oil/rubber/steel | **Landed (data+mode)** | Paint v1 + **resources mapmode (F9 / toolbar)** |
| **Naval chokepoints** | Strait control | **Landed** | 34 sea chokes named families |
| **Supply / infra story** | Supply map | **Landed (M4 core)** | Infra + supply mode + **capital→front corridor (G / supply-click)** · deep HOI logistics still soft |
| **Terrain combat tags** | Terrain mapmode | **Landed (M3)** | Layer + dedicated terrain mapmode (Ctrl+F9 / toolbar) |
| **Multi-front real edges** | Living fronts | **Landed** | Named fronts + edge counts |
| **Live multi-front assault** | Interactable war | **Landed (machine)** | Border targets API + dual headless PASS |
| **HOI OOB station deploy** | Units on map | **Landed** | capital→hubs→border |
| **Leaders/OOB/tech on accurate** | Content on board | **Landed** | D1 machine gates |
| **Produce→equip→assault** | Vertical war loop | **Landed (machine)** | D2 headless |
| **20–60d machine campaign** | Long session structure | **Landed (machine)** | Pure products; **human notes open** |
| **Human 20–60d narrative** | “Great full test” feel | **Open** | Playtest checklist only |
| **Measured FPS @ ~3520** | Density UX | **Landed (M5 samples)** | Post-sparse n=60 · p50 ~35 · soft 30 **FAIL** honest · kind=map_tick_proxy_headless |
| **States mapmode** | V3 state browse | **Landed (M2)** | Shift+F9 + state names @ operational |
| **Resources mapmode** | HOI resource view | **Landed (M1)** | F9 + toolbar · pure tint helper |
| **HOI pillar matrix (full-test)** | Cross-pillar machine bar | **Landed** | [`HOI4_EOA_GAP_REVIEW.md`](HOI4_EOA_GAP_REVIEW.md) · open P0=0 |
| **Museum borders / 13k count** | Pixel HOI | **Out of scope** | Explicit non-goal |

### 3.1 Living character checklist (player feel)

A world-class interactive map for EOA means the player can:

1. **See** political spheres and fronts at a glance (political + multi-front) — **machine strong**.  
2. **Click** capitals, hubs, and border provinces with correct ownership/names — **machine strong**; human click still recommended.  
3. **Stage war** on real adjacent GIS edges — **machine proven** (Maginot + Polish).  
4. **Read economy** via hubs/factories/infra and strategic goods — **data strong**; **resources (M1) + states (M2) + terrain (M3) mapmodes landed**.
5. **Zoom** without freezing or unreadable clutter at 8k — **LOD present**; **FPS samples landed (proxy; soft 30 FAIL)**.  
6. **Play 20–60 days** with politics/production/combat staying readable — **machine products only**; **human open**.

---

## 4. Ordered plan toward world-class map interaction

Priority is **player-facing map star quality**, not new GIS densify (board is already default GIS hybrid).

| Priority | Work | Exit | Owner |
|----------|------|------|-------|
| **M0** | **strategic_regions dedupe + membership integrity** | **DONE** — 31 rows, multi=0, North America filled from membership | MapAgent |
| **M1** | Dedicated **resources** mapmode (tint from `province_resources_layer`) | **DONE** — F9 + toolbar Resources · pure tint helper | UIUX + MapAgent |
| **M2** | Dedicated **states** mapmode (state id fill + name at operational zoom) | **DONE** — Shift+F9 + toolbar · golden-angle state fills | UIUX |
| **M3** | Terrain mapmode polish (clean terrain fills without killing political default) | **DONE** — Ctrl+F9 + toolbar · plains/forest/mtn/desert distinct | UIUX |
| **M4** | Supply corridor readability on dense board (depot→front path highlight using adjacency + infra) | **DONE** — G + supply preview polyline · land BFS/infra · GER capital→Baden-Baden gated | Production + UIUX |
| **M5** | Measured FPS capture @ 8761 (`EOA_MAP_PERF=1` graphical or careful headless) | **DONE (samples)** — p50 50.2 · p95 53.0 · soft 30 **FAIL** honest · artifact JSON | PerfCI |
| **M6** | Human 20d + 60d playtest notes on accurate (PLAYTEST §5.0) | Notes filed; freezes/pick bugs filed as director tasks | Human + Director |
| **M7** | Residual adjacency islands (optional near_vertex/quant only if playtest pathing fails) | Coverage stay ≥0.95; no false long edges | MapAgent |
| **M8** | Optional densify microstates / coast names only if playtest names thin | Named thin coasts | MapAgent |

**Do not** start: world_full renumber, full V3 market/pops, multiplayer map sync, HOI designer depth, museum border rebuild.

Director phases already closed (machine): **D0–D5.5** map/content/war/front (see GAME_DIRECTOR_PLAN). **M0–M5 done** (M5 soft 30fps FAIL on proxy — honest). Remaining full-test blockers are mostly **human feel (D2.4/D3.4 / M6)**.

---

## 5. Doc reconciliation notes

| Doc | Update from this review |
|------|-------------------------|
| `GAME_STATUS_SNAPSHOT.md` | Reflect hierarchy + M0–M5 done + next M6; keep human open; FPS samples table |
| `GAME_DIRECTOR_PLAN.md` | Point north star at map review; list mapmode priority after D5.5 |
| `MAP_ACCURACY_BUILD.md` | Link this review as “what world-class means now” |
| `CURRENT_STATE.md` | Session entry for review goal |
| `WORLD_CLASS_MAP_ROADMAP_AND_DELIVERABLES.md` | Historical Europe-460 focus; **superseded for default board** by this file + SNAPSHOT (do not treat as live default) |
| `PLAYTEST_AND_DECISION_GUIDE.md` | Already has world_accurate + strategic smoke; keep human notes open |

---

## 6. Verification (machine baseline)

```bash
python3 -m unittest tools.map_generation.tests.test_world_accurate_board -v
python3 -m unittest tools.map_generation.tests.test_world_accurate_strategic_and_assault -v
python3 -m unittest tools.map_generation.tests.test_world_accurate_multi_front_and_deploy -v
python3 tools/map_generation/scripts/map_accuracy_qc.py \
  --dir data/provinces_world_accurate --min-land-hit 0.90
```

Optional:  
`tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMultiFrontAssaultTest.gd`

---

## 7. Bottom line

**EOA already has a playable, GIS-default world board** with a **working** province→state→region→super membership path (**31 live regions**, 429 land states, 4 super), ownership eras, resources paint, chokes, multi-front edges, and a machine-proven war/assault loop on accurate IDs.

**M0–M5 landed (2026-07-21):** strategic_regions (**31**, multi=0); resources/states/terrain mapmodes; supply corridor (**G**); FPS samples n=60 p50/p95 in SNAPSHOT (soft 30 **FAIL** on map-tick proxy).

**World-class “living map star” is not finished** until:

1. A human can run 20–60 days and still *love* looking at the map (M6),  
2. Optional graphical renderer_frame sample if soft 30fps is required for ship gate.

This review freezes that truth so agents stop thrashing GIS renumber and prioritize **integrity + interaction on the board we already ship**.
