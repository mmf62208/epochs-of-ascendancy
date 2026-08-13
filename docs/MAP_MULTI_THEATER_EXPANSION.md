# Multi-Theater Map Expansion — Architecture & Decisions

**Status:** Active (2026-07-09) — **FULL WORLD SCOPE LOCKED**  
**Owner decision:** The playable map must cover the **entire world** (all continents + global seas). Europe remains the densest starting theater; every other region must be present for multi-front campaigns.  
**Goal feel:** HOI4-scale **army fronts**, Terra Invicta **naval** room, Supreme Ruler **infra/resources** on a true world board.

---

## 1. Why this shape (not full world day one)

| Choice | Decision | Why |
|--------|----------|-----|
| Target end-state provinces | **~2,400–3,200** (quality pass) | HOI4 ~13k is too heavy for Godot + small team; ~2.5k supports multi-front wars with LOD |
| **Playable now (world_full)** | **~2,665** | All continents + oceans; wave-1 China/India/US/Brazil + wave-2 Africa/SE Asia/Pacific/Oceania/SA/Central Asia; city seeds; default F5 |
| Geometry space | **World equirectangular** (`geometry_space: world`) | Provinces align to world underlay; Europe reprojected from theater local |
| Geometry source | Hybrid densified Europe + seeded world cells + seas | GIS coastline re-author is the quality track, not the presence track |

---

## 2. Province budget by theater (targets)

Numbers are **design targets** (land / sea-ish / total). Adjust ±15% for balance.

| Theater | Land | Sea / lake / strait | Total | Priority |
|---------|------|--------------------|-------|----------|
| **Europe core** (UK–Urals edge, Balkans, Italy, Iberia, Nordics) | 420–500 | 60–80 | **500–560** | P0 — army main front |
| **MENA** (Levant, Anatolia depth, Arabia, Iran, Iraq, Egypt) | 120–160 | 30–40 | **160–200** | P0 — oil + Suez + war |
| **North & East Africa** (Maghreb, Sahel edge, Horn, East Africa coast) | 80–110 | 20–30 | **110–140** | P1 — desert war + naval |
| **Sub-Saharan strategic** (Nigeria, Congo basin edge, South Africa) | 40–60 | 10–15 | **55–75** | P2 — resources, not full Vic3 |
| **India & Indian Ocean** | 50–70 | 20–25 | **75–95** | P1 — Raj / 1940s / modern |
| **China & Korea & Japan** | 100–140 | 25–35 | **130–170** | P1 — Far East campaign |
| **SE Asia & Pacific** (Indochina, Indonesia, Philippines, island chains) | 80–110 | 50–70 | **140–180** | P1 — island hop + naval |
| **Americas (playable densify)** | 80–120 | 20–30 | **100–150** | P2 — after Old World |
| **Oceans (blue-water sea zones)** | 0 | 80–120 | **80–120** | P0–P1 — convoy/naval |

**Grand target sum:** ~**2,400–3,000**.  
**This milestone (Grand Theater v1):** keep **460 Europe densified** + add **sea zones + MENA/NA + Far East stubs** → **~700–850**.

### Army gameplay density (HOI4-like)

- Front width needs **multiple provinces per operational front** (not 1 tile France).  
- Europe core should support **~8–14 provinces** across a classic Franco-German front, not 2–3.  
- Current densified 460 is a **start**; further subdivision of core Europe parents remains on the pipeline roadmap.

---

## 3. Land / sea / lake / island balance

### Domain tags (province fields)

Every province must carry:

| Field | Values | Use |
|-------|--------|-----|
| `domain` | `land` \| `sea` \| `lake` \| `strait` \| `coastal_land` | Movement, naval rules |
| `island_class` | `mainland` \| `large` \| `medium` \| `small` \| `micro` \| `none` | Facilities + merge rules |
| `facility_tier` | `full` \| `limited` \| `anchor_only` \| `none` | Airfield/port/factory eligibility |
| `naval_importance` | 0–10 | Chokepoint / convoy value |

### Island viability (hard rules)

Aligned with `docs/ISLAND_PROVINCE_GUIDELINES.md` + **facility economics**:

| Class | Canvas area (approx) | Facilities | Design rule |
|-------|----------------------|------------|-------------|
| **Micro** | &lt; min_airfield area | **none** (or victory-point flag only) | Exclude from map **or** merge into cluster province |
| **Small** | ≥ airfield, &lt; port min | **limited**: small airstrip **or** anchorage, not both heavy | One special site max |
| **Medium** | ≥ port + airfield | **limited→full**: port + airfield; light infra | 1–3 provinces per island |
| **Large** | mainland-like | **full**: multi-slot factories, multi sites | Split 4–8 provinces |
| **Sea zone** | N/A | no land factories; naval presence only | Size for fleet room + chokepoints |

**Decision (locked):**  
Islands **too small for a short runway / tiny port** are **not** first-class provinces unless historically critical (Malta, Gibraltar rock, Midway). Critical micros stay as **single province + `facility_tier: limited`** with inflated click area (`MapCanvasConfig` island scale). Decorative rocks **merge** into nearest sea zone or island cluster.

### Sea / land ratio

- Roughly **15–25% sea provinces** of total set for global naval play.  
- Europe theater: denser coastal land, fewer pure ocean tiles.  
- Pacific: **higher sea fraction** (island hop).  
- Lakes (Great Lakes, Caspian): few large lake provinces, not pixel lakes.

---

## 4. Phased delivery (execution order)

| Phase | Scope | Exit criteria |
|-------|-------|---------------|
| **A — Foundations** | Design, island viability lib, theater config, CI hooks | This doc + tests green |
| **B — Grand Theater v1** | Europe densified + Mediterranean/North Sea/Baltic/Black sea zones + MENA/North Africa land seeds | `data/provinces_grand_theater/` loads; ≥700 provs; names + densify + regions pass |
| **C — Indian Ocean / India** | India grid + Red Sea / Arabian Sea zones | Campaign path UK–India–MENA |
| **D — Far East & Pacific** | China coast, Japan, SE Asia, Pacific island chains + sea zones | Island-hop viable |
| **E — Americas densify** | NA/SA theater density | Optional full-world campaigns |
| **F — Geometry quality** | Coastline re-author hotspots, naval straits art | World-class shapes |

---

## 5. Data directory strategy

| Dir | Role |
|-----|------|
| `data/provinces_world_full/` | **Primary full-world set (~1600)** — all continents + seas |
| `data/provinces_grand_theater/` | Intermediate Old-World expansion (~1133) |
| `data/provinces_full_europe/` | Europe densified **stable** (460) — regression baseline |
| `data/provinces_phase1_test/` | Legacy harness |
| `data/provinces/` | Legacy 840 catalog seeds only |

**Play recommendation:** `data/scenarios/world_full.json` → `use_province_data_dir: provinces_world_full`.

---

## 6. Pipeline tools

| Tool | Purpose |
|------|---------|
| `config/grand_theater.yaml` | Budgets, theater bboxes, island thresholds |
| `lib/island_viability.py` | Area → class → facility_tier |
| `scripts/expand_grand_theater_provinces.py` | Build expanded layered JSON |
| `scripts/densify_province_geometry.py` | Vertex quality |
| `scripts/assign_europe_province_names.py` | Naming (extend to global gazetteer later) |
| `scripts/rebuild_strategic_regions.py` | Theater regions |
| `tools/run_map_ci.sh` | Gates |

---

## 7. Naval & army first principles

1. **Straits are sacred** — Channel, Gibraltar, Bosporus, Suez, Hormuz, Malacca, Tsushima get explicit provinces / chokepoint flags.  
2. **Islands need room** — inflated click + facility_tier; no fake 3-pixel airbase.  
3. **Sea zones carry fleets** — enough blue tiles for engagement + supply interdiction without painting every square km of ocean.  
4. **Land fronts need depth** — multiple provinces from coast to capital so breakthroughs matter.  
5. **Far East is not a single blob** — China, Japan, Philippines, Indonesia chains get separate density rules.

---

## 8. Success metrics (Grand Theater v1)

- [ ] Province count ≥ 700 in `provinces_grand_theater`  
- [ ] Sea/strait share 12–30%  
- [ ] Zero triangles; median verts ≥ 10  
- [ ] Island micro rules applied (`facility_tier` present on all)  
- [ ] Strategic regions ≥ 12, no mega-bag &gt; 25%  
- [ ] Scenario can set `use_province_data_dir: provinces_grand_theater`  
- [ ] Map CI green  

---

*Decisions here override ad-hoc province sprawl. When in doubt: gameplay readability + naval agency + facility space.*
