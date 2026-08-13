# GIS Coastline Ingest — Pipeline Design + Pilot

**Status:** **Natural Earth full geometry COMPLETE (2026-07-12)** — all **2665** world_full provinces stamped via NE 10m land mask snap (`align_ne_full_geometry.py --write --full`); id-stable · triangles=0 · `gis_ne_full` + `gis_pilot`. Photoreal raster underlays remain separate (see REAL_WORLD_MAP_LAYERS.md); province rings are NE-aligned.


---

## 1. Purpose

Define how real-world coastline / GIS sources enter the Epochs map pipeline so province **ids stay stable**, Europe/world layers remain composable, and full-world GIS remains an **opt-in later phase** rather than a surprise rewrite.

---

## 2. Pipeline entry

| Stage | Role |
|-------|------|
| **0. Source pack** | External GIS (Natural Earth, OSM coastline extracts) as GeoJSON in cache, **or** shipped offline fixture `tools/map_generation/fixtures/gis_coastline_pilot_rings.json` (coastal pilot rings). |
| **1. Project & clip** | Future: project to world_full canvas. Pilot uses existing map-space rings. |
| **2. Align to existing seeds** | Match GIS rings to **existing** `provinces_geometry.json` province ids via province_id hint → centroid-in-polygon → nearest centroid — **never renumber** play ids. |
| **3. Densify** | Pilot write ensures min vertices (default 16) on updated rings only. |
| **4. Layer refresh** | Full adjacency/terrain rebuild deferred until multi-region GIS write. |
| **5. CI gates** | Pure tests + `tools/run_map_ci.sh`: id count 2665, triangles=0, min verts, unique names. |

**Shipped script:**  
`tools/map_generation/scripts/ingest_gis_coastlines.py`  
```bash
# Dry-run (default) — real matched / unmatched / orphan / id_stable metrics
python3 tools/map_generation/scripts/ingest_gis_coastlines.py --dir data/provinces_world_full

# Guarded pilot write (requires --pilot); prefer --out for scratch first
python3 tools/map_generation/scripts/ingest_gis_coastlines.py \
  --dir data/provinces_world_full --write --pilot --pilot-limit 12 \
  --out /tmp/pilot_geometry.json

# Littoral expand (land adjacent to water beyond domain=coastal_land)
python3 tools/map_generation/scripts/ingest_gis_coastlines.py \
  --dir data/provinces_world_full \
  --include-littoral --rebuild-features --pilot-limit 720 \
  --write --pilot --backup
```

- `--write` **without** `--pilot` → **REFUSED** (exit 2)  
- `--write --pilot` → mutates matched coastal/littoral points only; id set unchanged  
- `--include-littoral` → expand pool with land-near-water adjacency (beyond `domain=coastal_land`)  

---

## 3. Outputs

| Artifact | Notes |
|----------|--------|
| `provinces_geometry.json` | Updated `points` / `label_anchor` for pilot-matched coastal provinces when `--write --pilot` |
| `meta.gis_feature_id` on province | Optional audit field after pilot write |
| Offline fixture | `tools/map_generation/fixtures/gis_coastline_pilot_rings.json` |
| Migration log | Match table in dry-run stdout (`matched_ids_sample`) |

**Must not change without migration plan:** province `id` set, scenario capital ids, OOB stations, ownership keys.

---

## 4. Id stability rules

1. **Primary key is province id** (integer), not name.  
2. GIS features attach via `meta.gis_feature_id` optional field — never replace id.  
3. New islands/coast cells require **new ids** from the world id allocator — never reuse retired ids.  
4. Dry-run prints: `matched`, `unmatched_existing`, `orphan_gis`, `id_stable=true|false` (real counts, not stub zeros).

---

## 5. Non-goals (still deferred)

- ~~Full world GIS coastline rewrite~~ **LANDED** via NE full align  
- Photoreal fjord meshes / heightfields  
- Changing the 2665 play count without an explicit product decision  
- Multiplayer / cloud map packs  
- Replacing procedural ocean basins with nautical chart precision  

---

## 6. Acceptance (pilot phase — landed)

- Dry-run on world_full: `id_stable=true`, `matched ≥ 1` (fixture/pilot), not stub-zero text  
- `--write --pilot` can change ≥1 coastal province points without changing id set; triangles=0  
- Map CI green; dual headless SCRIPT ERROR 0 + industry/equip markers  
- Docs do **not** claim full-world photoreal fjords done  

---

## 7. References

- `tools/map_generation/lib/gis_coastline_ingest.py`  
- `tools/map_generation/scripts/ingest_gis_coastlines.py`  
- `tools/map_generation/tests/test_gis_coastline_ingest.py`  
- `tools/map_generation/scripts/densify_province_geometry.py`  
- `docs/MAP_GENERATION_PIPELINE_DESIGN.md`

## 8. Littoral depth-2 expand (landed)


**GIS×1343 bar:** depth-2 near-coast inland expand stamps **1343** id-stable rings (depth1 pool 753 + 590 inland).

Catalogue: GIS×1343 · littoral depth · near-coast inland · gis pilot

## 9. Natural Earth full align (COMPLETE)

```bash
# Dry-run
python3 tools/map_generation/scripts/align_ne_full_geometry.py --dir data/provinces_world_full

# Full write (all 2665)
python3 tools/map_generation/scripts/align_ne_full_geometry.py \
  --dir data/provinces_world_full --write --full --backup
```

- Source: cached `ne_10m_land.geojson` (Natural Earth public domain)
- Method: raster land mask → snap province vertices onto land/water · densify · stamp `gis_ne_full`
- Gates: 2665 stamps · id_stable · triangles=0 · min verts ≥16
- Catalogue: Natural Earth · NE full · gis_ne_full · ne_10m_land · 2665
