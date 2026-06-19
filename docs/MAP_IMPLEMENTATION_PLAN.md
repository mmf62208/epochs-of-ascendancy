# Map System Implementation Plan — Epochs of Ascendancy

**Status:** Actionable implementation roadmap (2026 update)  
**Last updated:** Late May 2026 (post ProvinceEffects + Supply/Combat Phase 1 wiring)  
**Audience:** Core dev team (GDScript + data)  
**Prerequisites / References:**
- `docs/MAP_SYSTEM_DESIGN.md` (vision, architecture diagrams, M0–M5 phases — this plan executes it)
- `data/provinces/SCHEMA.md`
- `scripts/data/Province.gd` (getters) + `scripts/map/ProvinceEffects.gd` (now with `for_country_province`)
- Recent Phase 1 work: Supply interdiction/reinforcement + Combat org/casualty now use real dev/infra + national modifiers
- `scripts/core/ScenarioLoader.gd`, `scripts/map/MapRenderer.gd`, `scripts/data/AdjacencySystem.gd`
- Current scale: ~100 provinces in `provinces_geometry.json` (Europe + majors focus; base catalog has 840), layered JSON pipeline

---

## 1. Overall Vision (HOI4-Style in Godot 4)

A world-class map in *Epochs of Ascendancy* is a **living strategic board**, not a pretty background.

- **Polygonal provinces** (vector, not tiles) with stable IDs across 1900–2050+ scenarios. Same geography; only owners, development, infrastructure, factories, and unlocked features change via scenario + era layers.
- **Realistic terrain & sea zones**: Land polygons drive movement cost, combat width, supply throughput, attrition, interdiction resistance, reinforcement speed, local supply gen. Sea zones (`is_sea`) + ports enable naval supply, amphibious, convoy raiding.
- **Gameplay density**: Every province answers “Can I fight here effectively? Supply here? Build here? Spy here?” via visible + effective modifiers.
- **Era coherence on one map**: 1918 low-infra rail map feels different from 2026 high-dev network-centric map without duplicating geometry.
- **Retrowave aesthetic**: Dark panels (#1e1e2e), cyan/magenta accents, subtle glows, clean typography. No realistic satellite clutter — stylized political + functional overlays.
- **Scale target (realistic for small team)**: MVP 250–400 provinces (playable Europe + key theaters + sea). Path to 800–1,500 with LOD before full-world 3k+ (HOI4 class requires dedicated map team).

The map is the **primary surface** for Supply (routes, depots, interdiction), Combat preview (width, org recovery, attrition), Agent networks (rings, detection), and Technology (build eligibility by province features).

**Success feel**: Player zooms from strategic (country colors + supply arteries) → operational (province names, hub badges, effective modifiers in tooltip) → tactical (battle preview vs adjacent, agent strength, construction slots) and every number is “real” (ProvinceEffects + national spirits/temp modifiers).

---

## 2. Current State Assessment (May 2026)

**Strengths (solid foundation — do not rewrite):**
- Layered JSON data (`provinces_geometry.json` + economy/terrain/city/adjacency/state/region/project layers). Stable IDs. Scenario overrides.
- `Province` Resource with rich computed getters (supply throughput, local gen, combat width, org recovery, attrition, interdiction resistance, reinforcement speed, logistics quality, movement cost).
- `ProvinceEffects` aggregator + new `static for_country_province(province, country_tag)` that pulls combined NationalSpiritManager + NationalModifierManager values (spirits + temp debuffs/buffs). Just wired.
- Map rendering: `MapRenderer` + per-province `Polygon2D` + `Area2D`/`CollisionPolygon2D` inside `ProvinceContainers`. Centroid calculation, hover scale, name labels (zoom-gated), feature icons (radial), capital stars, selection highlight.
- Picking + hover: `ProvinceHoverTooltip` + `ProvinceInsight.build_hover_tooltip` (already shows Dev/Infra, logistics summary, combat modifiers, depot state, battle preview vs selected).
- Info panel surfaces dev/infra/factories + logistics/combat blocks.
- Supply: `SupplyMapLayer` (polylines on centroids), `SupplyManager` now uses province resistance/reinforce + national totals (recent Phase 1).
- Combat: `CombatResolver.get_combat_width_for_battle` + `get_effective_combat_power` + `resolve_battle_aftermath` now accept/pass real province dev/infra and apply `ProvinceEffects` org/attrition/casualty scaling (recent Phase 1).
- AdjacencySystem with strait support.
- Camera: Dual (MapRenderer controls + CameraController on containers scale). Zoom bands partially gated.
- Overlays started (supply routes, L-key toggle).

**Gaps / Technical Debt:**
- No `MapManager` autoload — managers still do `find_child("ScenarioLoader")` or direct node walks (brittle).
- Picking = one `Area2D` per province → will degrade at 300–400+ (node count + input overhead).
- Rendering = one `Polygon2D` + `Area2D` per province (100 is fine; 400 will hurt draw calls + memory).
- `ProvinceEffects` is excellent but **not yet the default** everywhere (tooltips still mostly call Province getters directly; some national paths still manual).
- No sea zones in current geometry (limits naval play).
- Limited visual feedback for controller ≠ owner, high-dev hubs, agent networks, contested supply, construction eligibility.
- Camera/zoom logic duplicated between MapRenderer and CameraController.
- Data: ~100 geometry provinces (good starter), but base catalog 840 suggests authoring pipeline exists but not yet exercised at scale. Validation tool exists but can be stricter.
- No minimap, no persistent overlays (agent rings, front lines), no build-mode highlighting.

**Recent wins (leverage immediately):** The three Phase 1 items (Supply interdiction/reinforce via ProvinceEffects or getters + national, Combat battle paths with real dev, light ProvinceEffects wiring) prove the data model works. Map UI now has live numbers to expose.

---

## 3. Recommended Technical Architecture (Godot 4 Practical)

**Core principle:** Polygon-first (HOI4 model), data-driven, Province + ProvinceEffects as single source of truth. Rendering and picking evolve for scale; gameplay objects do not.

### 3.1 Layered Scene Graph (target)
```
WorldMap (MapRenderer or thin coordinator)
├── Background (Sprite2D — political or terrain texture, 4096×2048)
├── ProvinceContainers (Node2D, scaled by camera)
│   ├── ProvinceMeshLayer / CountryBatchedFills (future, M2)
│   ├── BorderLineLayer (LOD)
│   ├── FeatureIconLayer (or keep per-node for now)
│   ├── SupplyMapLayer (exists — polylines + nodes)
│   ├── AgentNetworkLayer (M3)
│   ├── ConflictOverlayLayer (M3)
│   └── InteractionLayer (or use pick grid)
├── MapCamera (Camera2D)
├── CameraInput / CameraController (existing)
└── UI (CanvasLayer)
    ├── HoverTooltip (ProvinceHoverTooltip)
    ├── InfoPanel (DraggablePanel pattern)
    ├── Minimap (M5)
    └── Overlay controls
```

### 3.2 Province Data & Effects (do not change core)
- Keep `Province` as lightweight runtime Resource (identity + politics + economy + special_features + computed getters).
- `ProvinceEffects.for_country_province(prov, tag)` is now the canonical “what does this province actually do right now?” query. Use it in **all** tooltip, preview, and modifier application paths.
- Geometry stays in `provinces_geometry.json` (pixel space relative to background). At load, ScenarioLoader builds Province instances + separate geometry dict passed to MapRenderer.

### 3.3 Performance Strategy (90 → 400+)
- **Now–M1 (≤150–200):** Current per-province Polygon2D + Area2D is acceptable. Keep.
- **M2 (250–400 target):** 
  - Replace per-province Area2D picking with `MapPickGrid` (simple 2D spatial hash or coarse grid of province IDs using centroids + rough AABB). Fall back to brute for debug.
  - Batched rendering: `ProvinceMeshLayer` (one or few `MeshInstance2D` or custom `_draw` per country/terrain bucket). Keep individual Polygon2D only for hover/selection feedback (or use a single highlight polygon moved on top).
- LOD: Below 0.4 zoom, simplify borders or hide names/icons (already partially gated).
- Memory: Store geometry as `Dictionary<int, PackedVector2Array>` or a packed `MapGeometry` Resource. Centroids precomputed.

### 3.4 Picking (critical upgrade)
Current Area2D works because 100 nodes is cheap. At 400 it becomes the bottleneck (input propagation, collision checks).

**Recommended:** `MapPickGrid` (new class in `scripts/map/`):
- On map init: build a grid (cell size ~48–80 px) or a hash of (centroid rounded to grid).
- On hover/click: query grid cells around mouse, then test only the 3–8 candidate provinces with cheap point-in-polygon (or even just “closest centroid + radius” first pass + exact for final).
- Still attach lightweight Area2D on high-zoom tactical view if desired (hybrid).
- Expose `MapManager.get_province_at_world_pos(pos)` or `get_province_at_screen_pos`.

This matches Godot patterns (many 4.x strategy games use custom pickers for thousands of objects).

---

## 4. Core Integration Points (ProvinceEffects Everywhere)

**Rule:** Tooltips, previews, and system calcs must show **effective** values (base + national spirits + temp modifiers from agents/foci/events). Never raw getters in player-facing text after M1.

| Domain | Current State | Target (use ProvinceEffects) | Owner |
|--------|---------------|------------------------------|-------|
| **Hover / InfoPanel** | ProvinceInsight calls raw getters + some CombatResolver | `ProvinceEffects.for_...` for all logistics/combat blocks. Add “Base / National / Effective” breakdown lines (cyan for buffs, magenta for debuffs). | Map + UI |
| **Combat** | get_combat_width_for_battle + power + aftermath now wired (Phase 1) | Pass province_id/dev to `get_effective_combat_power`. Tooltip shows effective width/org recovery/attrition with national delta. | CombatResolver |
| **Supply** | _plan_route + local gen + delivery now wired (Phase 1) | Route plans + depot tooltips show effective throughput + interdiction resistance + reinforcement. Depot heat tint driven by effective local supply gen. | SupplyManager + SupplyMapLayer |
| **Agents** | Province-targeted missions exist; AgentNetwork stub | Map shows ring strength/opacity per province. Effects (sabotage on infra, intel on interdiction resistance) flow through ProvinceEffects or direct NationalModifier + province debuff. Click province → open Agent screen filtered. | AgentManager + new AgentNetworkLayer |
| **Technology / Production** | National + some province feature checks | Build eligibility highlight on map (valid provinces glow cyan). Locked slots show padlock. Dev/infra affect build speed/cost via modifiers. | TechnologyManager + Production |
| **National Spirits / Temp Mods** | Managers exist, some Supply/Combat consumption | Map tooltip always shows active spirit/temp effects on the province (e.g. “+12% org recovery from ‘Mountain Warfare’ spirit”). | National* + Map |

**MapManager** (new autoload, highest priority) becomes the resolver:
```gdscript
var fx := MapManager.get_province_effects(province_id, player_tag)
# or
var p := MapManager.get_province(id)
var effective_width := p.get_combat_width_modifier() * (1.0 + MapManager.get_national_modifier(tag, "combat_width"))
```

---

## 5. Phased Implementation Roadmap (Actionable)

Build on the existing `docs/MAP_SYSTEM_DESIGN.md` M0–M5 skeleton. This plan **starts from the current post-Phase-1 state** and prioritizes **playable integration wins** before pure visuals.

### Phase 0.5 — Immediate Stabilization (1 week, parallel with other work)
**Update (post recent work):** Map now has strong playtest surface for systems (relocation/settlement, policies, Golden): multi-province real effects, Province settlement_level, inspector/hover exposure of bonuses, MapRenderer tint + refresh, F10 one-click demographic test tools. This makes the ~phase1 territories a viable board for testing demographic engineering + combat/supply/victory interactions at playable level. Continue with M1 data scale + sea while using the new debug/inspector paths.
**Goal:** Make the excellent recent ProvinceEffects + Supply/Combat wiring visible and robust on the current 100-province map.

- Introduce **MapManager** autoload (skeleton + signals: `province_hovered`, `province_selected`, `province_effects_changed`).
  - Holds active provinces/geometry/adjacency.
  - `get_province(id)`, `get_province_effects(id, country_tag)`, `get_effective_*` helpers.
  - Migrate SupplyManager / CombatResolver / ProvinceInsight calls away from `find_child("ScenarioLoader")`.
- Full audit: ensure **every** tooltip and preview path calls ProvinceEffects (or documents why not).
- Fix duplication: decide ownership of camera controls (CameraController should drive ProvinceContainers scale/pos; MapRenderer should observe or delegate).
- Extend `tools/validate_province_layers.py` for sea consistency + effect key coverage.
- Expose “effective” numbers in existing InfoPanel / hover (small win, huge perception).

**Exit:** 1936 scenario loads; hover on Berlin shows real org recovery from any active spirit + dev; no regressions in Supply/Combat tests.

**Parallel:** Continue Combat depth, Supply route AI, Agent mission effects.

### Phase M1 — Data Scale + Sea Zones + MapManager Polish (3–4 weeks)
**Goal:** Expand playable geography to 250–350 provinces while keeping IDs stable.

- Authoring pipeline: script or instructions for QGIS → `provinces_geometry.json` + adjacency auto + manual straits.
- Add sea zone polygons to geometry (Mediterranean, North Sea, Atlantic approaches, key Pacific/Indian for later). Set `is_sea`, naval adjacency.
- Complete `province_states.json` + `strategic_regions.json` for new IDs.
- Scenario overrides for 1918 / 1936 / 2026 on the larger set.
- MapManager fully featured (supply hub queries, era filtering, build eligibility).
- Basic sea rendering (different color or wave shader stub in SupplyMapLayer style).

**Exit:** Player can plan a naval-supported invasion or convoy route on the expanded map; pick still instant.

**Parallel:** Agent network backend (province rings), Technology unlocks that care about province features.

### Phase M2 — Rendering & Picking Upgrade (3–4 weeks, can start late M1)
**Goal:** Performance + maintainability headroom for 400 provinces.

- `MapPickGrid` (or `ProvincePickSystem`) — spatial hash + point-in-polygon on candidates. Remove or optional-ize per-province Area2D.
- `ProvinceMeshLayer` (or upgrade SupplyMapLayer pattern): batched country fills + borders as polylines or a single multi-mesh. Individual polygons only for hover/selection feedback.
- LOD system: zoom-band visibility for names, icons, fine borders, tooltips.
- Refactor MapRenderer into thin coordinator + layer nodes (keeps scene clean).
- Optional: hybrid TileMap underlay for very low zoom “strategic” view (political texture baked).

**Exit:** 350 provinces, all overlays, 60 FPS on mid-tier hardware (Ryzen 5 / GTX 1660 class or equivalent integrated).

**Parallel:** Any system that only needs province IDs (most backend).

### Phase M3 — Gameplay Overlays & Effects Visibility (4–5 weeks)
**Goal:** The map becomes the primary interface for the systems already wired.

- Supply: depot heat tint (color or shader on province fill or dedicated layer), hub tier badges (capital star already exists; add major/minor rings), interdiction risk icons on routes.
- Agent networks: `AgentNetworkLayer` — purple/cyan rings whose thickness/opacity = strength, contested hatching where enemy pressure high. Click → Agent screen with filter.
- Contested / controller ≠ owner: diagonal stripe or desat overlay (simple Polygon2D sibling or shader).
- ProvinceEffects breakdown in all tooltips (base value → + national spirit → + temp modifier → effective).
- Technology build mode: highlight valid provinces for current unlock (e.g., “can build shipyard here”).
- Conflict preview: simple front-line dots or arrows between adjacent hostile provinces.

**Exit:** A new player can look at the map, understand supply risk, where agents are strong, and where a battle will be bloody — without opening other screens.

**Parallel:** Full Agent network effects (sabotage on infra → temporary Province modifier or NationalModifier scoped to province), deeper Combat (weather, engineers, air support on map).

### Phase M4 — Infrastructure as Gameplay + Era Coherence (ongoing, 4+ weeks)
**Goal:** Dev and infra are levers the player pulls.

- Player actions: “Invest in Infrastructure” / “Develop Province” (Political Power + time + resources). Map shows progress + temporary “under construction” state.
- Project sites (`project_sites.json`) appear as buildable megaprojects on map.
- Reinforcement/interdiction fully respect effective province values (already close).
- Era tags on provinces → grey or desaturate anachronistic features (e.g., spaceport in 1936).
- Optional: dynamic border morph on owner change (cheap tween of a highlight polygon).

**Exit:** Changing Berlin’s infrastructure measurably changes a supply route’s interdiction chance and a battle’s org recovery in the tooltip and sim.

### Phase M5 — Polish, Minimap, Modding (ongoing)
- Minimap (simplified polygons or baked texture + click-to-jump).
- Province search / goto.
- Full legend, hotkeys, accessibility (colorblind palettes for country colors).
- Modding guide + example “add 12 provinces to Indochina” end-to-end.
- Performance budget + profiling harness for 800+ provinces.

---

## 6. Risks & Recommendations

### Major Risks
- **Authoring bottleneck:** 400 provinces by hand is a lot. **Mitigation:** Cap MVP at 250–300 high-value provinces; invest in QGIS + script pipeline early (M1); buy or contract clean vector data only with clear license.
- **Picking / perf cliff:** Area2D approach feels fine until it doesn’t. **Mitigation:** Build `MapPickGrid` in M2 before you feel pain; keep Area2D as debug fallback.
- **ID drift / data rot:** Scenarios and geometry get out of sync. **Mitigation:** Strict stable-ID policy + CI validator (extend existing tool) + `min_geometry_version` in scenarios.
- **Visual clutter vs retrowave clarity:** Too many overlays = unreadable. **Mitigation:** One primary overlay + zoom gating + strong defaults.
- **Scope creep to “full HOI4 map”:** 13k provinces kills the project. **Mitigation:** Explicit 400-province cap in this plan; document the “later with bigger team” path.

### Recommendations for World-Class Quality Without Over-Engineering
- **Data first, pixels second.** Get 250 solid provinces with correct dev/infra/terrain/sea adjacency before spending time on shaders or 4K textures.
- **Effects are the star.** The ProvinceEffects system + recent wiring is a genuine differentiator. Expose it ruthlessly in the map UI — this is what makes the map “feel alive.”
- **Retrowave discipline:** Limit palette to 6–8 colors. Use glow, scanlines, and clean lines. Avoid realistic terrain textures early.
- **Hybrid rendering is fine.** You do not need a full custom renderer in Godot 4 for 400 polys. Batched meshes + custom draw for overlays + a few highlight Polygon2Ds is enough for years.
- **Sea zones early.** Naval play is a huge differentiator from pure land games. Add them in M1 even if the first 50 sea provinces are coarse.
- **Validation > pretty tools.** A strict validator that catches broken polygons, asymmetric adjacency, missing economy entries, and effect key typos will save more time than a fancy editor.
- **Parallelism:** M0.5–M1 can (and should) run in parallel with Combat/Supply/Agent/Tech vertical slices. The map only needs to expose IDs + Effects; the systems do the interesting math.

---

## 7. Concrete Next Steps (Start This Week)

1. **Create `MapManager` autoload** (highest leverage single change).
   - Register in `project.godot`.
   - Expose `get_province(id)`, `get_province_effects(id, tag)`, `get_national_modifier(tag, key)`.
   - Migrate 3–4 call sites in Supply/Combat/Insight.
   - Emit `province_effects_changed` when NationalModifierManager ticks.

2. **Audit + convert one major tooltip path** to full ProvinceEffects + breakdown (e.g., hover logistics + combat block). Add tiny “(base +12% national)” lines.

3. **Fix camera ownership** — make CameraController authoritative for ProvinceContainers transform; MapRenderer observes zoom for detail gating.

4. **Extend validator** to warn on provinces missing `get_interdiction_resistance_modifier` coverage or economy layer entries.

5. **Prototype `MapPickGrid`** (even a naive 64 px grid using centroids) and A/B test hover latency on current map.

6. **Data task:** Add 30–50 new provinces in a high-value theater (e.g., North Africa or Pacific islands) using the existing pipeline + manual adjacency. Prove M1 authoring works.

7. **Update `TODO.md`** and link this plan from the Deeper Combat + Province Infrastructure section.

**Owner for Phase 0.5:** Whoever owns ScenarioLoader / MapRenderer today (or a dedicated “map systems” person for 2–3 weeks).

---

## Appendix — Key File Changes (M0.5–M2)

- New: `scripts/map/MapManager.gd` (autoload)
- New: `scripts/map/MapPickGrid.gd`
- New/expand: `scripts/map/ProvinceMeshLayer.gd`, `AgentNetworkLayer.gd`, `ConflictOverlayLayer.gd`
- Modify: `MapRenderer.gd` (slim down), `ProvinceInsight.gd` (Effects breakdown), `ScenarioLoader.gd` (expose more via MapManager)
- Modify: `SupplyMapLayer.gd` (heat tints), `CombatResolver.gd` (already good), `ProvinceEffects.gd` (minor polish)
- Data: Expand geometry + layers; update SCHEMA.md with new fields if needed (`supply_hub_kind`, `era_tags`)

**Success Metrics (MVP map, ~300 provinces)**
- Load time < 3 s
- Idle map 60 FPS, heavy overlay < 30 ms frame
- Hover/click < 30 ms
- Every player-facing province number traceable to ProvinceEffects
- A new player can explain why attacking through the Ruhr is better than through the Alps after 5 minutes with the map open

This plan is deliberately **conservative on visuals** and **aggressive on integration and data quality**. The recent ProvinceEffects + Supply/Combat wiring has already done the hardest part — proving the numbers are worth showing on the map.

Execute Phase 0.5 now. The map will start feeling like a world-class strategic instrument within 4–6 weeks. 

---

*End of Map System Implementation Plan*