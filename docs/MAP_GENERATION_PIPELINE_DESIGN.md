# Map Generation Pipeline – Design Document

**Project:** Epochs of Ascendancy  
**Status:** Initial Design (May 2026)  
**Goal:** Move from current ~100 placeholder provinces to a high-quality 1200–1500 province world map in phases, with excellent support for naval play, Special Sites, infrastructure, and deep simulation.

## 1. Vision & Constraints

- **Target:** 1200–1500 provinces for the full world (phased).
- **Phase 1 Target:** 350–450 high-quality provinces focused on **Europe + immediate surrounding theater** (including key coastlines, straits, and islands).
- **Style:** Stylized but highly readable (HOI4-inspired political colors + functional overlays + meaningful terrain character). Not photorealistic.
- **Naval Priority:** High. Coastlines, straits (English Channel, Danish Straits, Gibraltar, Bosporus, etc.), islands, and sea zones must be first-class citizens from Phase 1 onward.
- **Data Philosophy:** Keep and evolve the existing layered JSON system (geometry, terrain, resources, economy, special features, states, special sites). The pipeline must output data compatible with current loaders (`MapScenarioData`, `Province`, `MapManager`, etc.).

## 2. High-Level Architecture

### 2.1 Pipeline Structure (tools/map_generation/)

```
tools/map_generation/
├── config/
│   ├── europe_phase1.yaml          # Region definitions, target density, rules
│   └── global_rules.yaml
├── data/
│   ├── base_geometry/              # Higher-res source data (future)
│   └── reference/                  # Current 840-province base catalog
├── scripts/
│   ├── generate_europe_phase1.py   # Main driver for Phase 1
│   ├── subdivide.py                # Intelligent province splitting logic
│   ├── assign_attributes.py        # Terrain, resources, development, VP, special features
│   ├── naval_zones.py              # Sea zone + strait + island handling
│   ├── validate_output.py          # Ensures output matches current schema
│   └── utils.py
├── output/
│   └── phase1_europe/              # Generated JSON layers ready for import
└── README.md
```

### 2.2 Core Data Flow

1. **Input**
   - Current geometry + data layers (as reference)
   - Higher-resolution base map (image or vector) when available
   - Rule files (density targets per region, terrain rules, resource distribution, strategic value, naval importance)

2. **Processing Stages**
   - Region definition & density planning (Europe first)
   - Smart subdivision (preserve important straits, islands, major rivers, historical borders where meaningful)
   - Attribute assignment (terrain from base data + rules, resources, development potential, victory points, special features)
   - Naval layer generation (sea zones, straits as special adjacency, island groups, port potential)
   - Special Site seeding (high-value locations get candidate sites based on terrain/resources)
   - Output validation + export to existing JSON format

3. **Output**
   - Updated `provinces_geometry.json` (or delta layers)
   - Updated `province_terrain_layer.json`, `province_resources_layer.json`, etc.
   - New or extended `province_naval_layer.json` (sea zones, straits, coastal importance)
   - Optional `special_site_candidates.json`

### 2.3 Key Challenges & Solutions

| Challenge                    | Approach                                      | Priority |
|-----------------------------|-----------------------------------------------|----------|
| Intelligent subdivision     | Rule-based + cost function (preserve straits, major rivers, historical density) | High |
| Naval / Coastal fidelity    | Dedicated naval layer + special adjacency rules for straits | Very High (naval play) |
| Data consistency            | Strong validation + schema enforcement        | High |
| Manual overrides            | Allow artist/ designer to lock certain provinces or regions | Medium |
| Performance at 1500 provinces | Batched rendering + LOD in MapRenderer (already partially planned) | Medium |

## 3. Phase 1 Focus (Europe + Theater)

**Geographic Scope (initial):**
- Europe (including British Isles, Scandinavia, Iberia, Italy, Balkans)
- Key surrounding areas: North Africa coast, Anatolia, Caucasus approaches, Western Russia edge
- Critical naval features: English Channel, North Sea, Baltic approaches, Mediterranean, Gibraltar, etc.

**Success Criteria for Phase 1:**
- Map feels dense and strategic in Europe.
- Major straits and islands are properly represented.
- Special Sites and infrastructure feel geographically meaningful.
- Naval movement and supply feel interesting.
- Performance remains good.

## 4. Immediate Visual Improvements (While Pipeline is Built)

While the generation pipeline is being developed, we will improve the current map in parallel:

1. **Roads & Infrastructure Visualization** (already started in `InfrastructureOverlayLayer.gd`)
2. **Resource Icons** on provinces (already started)
3. **Stronger Terrain Differentiation** (enhance existing tone system + add more distinct coastal/mountain rendering)
4. **Better Province Labeling & Importance Scaling**
5. **Enhanced Special Site & Naval Feature Visibility**

## 5. Next Actions (Recommended Order)

1. **Create this design document** (done).
2. **Start implementing basic road + resource icon improvements** on the current map (high visual impact, low risk).
3. **Build the first version of the pipeline scripts** focused on Europe subdivision rules + naval layer.
4. **Iterate on Phase 1 Europe data** using the pipeline + manual polish.
5. **Expand pipeline** to handle global generation in later phases.

## 6. Open Questions

- How much manual artistic control do we want to retain vs. procedural generation?
- Should sea zones be first-class provinces or a separate layer on top of ocean provinces?
- How important is historical accuracy vs. gameplay-driven borders in Phase 1?

---

**Status:** This document will be updated as we build the pipeline. All generated data must remain compatible with the existing `MapManager`, `Province`, `SpecialSiteManager`, and overlay systems.
## Progress Log (May 28 2026)

**Major vertical slice delivered:**
- Geometric subdivision engine completely overhauled (`subdivision_utils.py`):
  - Boundary densification for the current coarse 6-point seed provinces
  - Robust radial arc-ownership + repeated bisection fallback
  - Children now own real contiguous perimeter segments (5–7 points, sensible areas)
- Full rich layered output produced:
  - `proposed_children_geometry.json` (120 children from 40 parents)
  - `generated_terrain_phase1.json`, `generated_resources_phase1.json`, `generated_economy_phase1.json`
  - `special_site_candidates_phase1.json` (heuristic naval/air/fortress hints)
  - `merge_instructions_phase1.json` (clear integration guidance)
- Naval analysis upgraded:
  - Cheap but effective articulation/bridge detection in `find_potential_chokepoints`
  - Automatic narrow-bridge discovery in `get_major_strait_connections` (3 curated → 63 protected bridges/chokepoints)
  - Higher naval importance scores now reflect real graph topology
- Additional high-value naval Special Sites added (Iceland air station, Skagerrak fortress, Faroes patrol, Kiel Canal control)

**Current state:** The pipeline now produces *playable-grade* child proposals with attribute inheritance and strategic site hints from the real 840-province reference catalog. Next required step is Godot-side visualization (proposed split overlay) before any actual map merge work.

**Next priorities (ranked):**
1. Godot debug visualization of proposed children (InfrastructureOverlayLayer or dedicated layer)
2. Adjacency + state/region repair logic for merged output
3. Higher-resolution source geometry ingestion (future Phase 1.5)
4. More Special Site content + early AI scaffolding for site selection

## Progress Log (May 28, 2026 — session 2)

**Splitter & merge hardening:**
- `subdivision_utils.py`: PCA-based cuts with **coastal edge preservation** so child provinces retain sensible shoreline segments instead of arbitrary interior splits.
- `naval_analysis.py`: Expanded chokepoint/bridge detection feeds protected connections during merge.
- `apply_phase1_merge.py`: Adjacency rebuild with chokepoint protection; improved inheritance/distribution for **resources, development, special features, and cities** across children.

**Playable test scenario:**
- Persistent **Phase 1 Europe Test** (~180 provinces): `data/provinces_phase1_test/` + `data/scenarios/phase1_europe_test.json`.
- Godot: Debug Overlay one-click load, camera framing for the expanded theater, overlay/diagnostic hooks for validation.

**Design collateral:**
- [HIDDEN_HAND_DESIGN.md](HIDDEN_HAND_DESIGN.md) — compiled faction design (three power centers, discovery stages, alternate play mode).

**Still open:** Finer coastal fidelity on cut boundaries; promote merged output into production `data/provinces/` layers; scale subdivision density toward the **350–450** Europe target.

