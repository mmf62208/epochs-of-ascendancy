# FEED-4 — Mediterranean seas coarsen (Mike bar #3)

**Status:** FEED-4 theater proof on `world_accurate` (draft; HOLD merge for Scott/Play).  
**Tip lineage:** Gibraltar FEED-3 KEEP `8340c05db164e8017126fbad61c6a8c4115b44ef`.  
**Scope:** Mike bar **#3 only** — seas/oceans larger (fewer, bigger water cells). Theater = **Alboran Sea**, the Med basin abutting Gibraltar / Cadiz / strait `950019` / land `711520`.

This is a design note + one theater proof. It is **not** a whole-world or whole-ocean remesh, **not** North Atlantic, **not** lakes (FEED-1), **not** Maginot land (FEED-2), **not** a Gibraltar/HK land redo, and **not** combat.

## Mike bar (unchanged)

1. Land provinces more uniform on continents — FEED-2
2. Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale — FEED-3
3. **Seas/oceans larger (fewer, bigger water cells)** — this FEED (Alboran only)
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape that **keeps existing sea IDs**, or append-only new IDs.
- FEED-4 **reuses** sea `950128` (Alboran Sea). Moving the ring is not a renumber.
- Strait `950019` (Gibraltar Strait Zone) **kept** as naval choke (`domain=strait`, still in `naval_chokepoints.json`).
- Land IDs unchanged: Gibraltar `711520`, Cadiz `710671`, Ceuta `710679`, Maginot `710173`/`710739`/`711514–711519`. Great Lakes `950333–950337` stay lakes.
- Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Maginot combat / Control Labels / duals / Godot bump / Hong Kong / whole-ocean remesh are out of scope.

## Diagnosis (accurate board, pre-FEED)

Named Med seas existed, but the west-Med cluster was leftover `expand_grand_theater` seed hexes bunched around 3–7°E. The **real Alboran basin** (Spain–Morocco water, lon ≈ −5.2 to −1.0) was almost entirely **void**. Typical Iberian coastal land (NUTS, area 20–2000) median **~471**.

| ID | Name | Domain | Pre canvas area | Pre centroid | Role |
|----|------|--------|-----------------|--------------|------|
| 950019 | Gibraltar Strait Zone | strait | **88.95** | (−5.52, 36.29) | naval choke; **kept** |
| 950128 | Alboran Sea | sea | **240.82** | (2.95, 36.52) | leftover seed **east of** the basin (smaller than Cadiz 470) |
| 950003 | Western Mediterranean | sea | 580.26 | (4.15, 36.88) | leftover seed; **not this basin** |
| 711520 | Gibraltar | land | 13.67 | (−5.36, 36.14) | FEED-3 rock key |
| 710671 | Cádiz | land | 470.06 | (−5.72, 36.70) | typical coastal land comparator |

Theater seas for this proof = `{950019, 950128}`: **n=2**, median **164.88**. Sample water (−4.0, 36.0) / (−2.5, 36.2) = VOID.

NAtl strip west of Iberia already has larger water cells than coastal land (median ~963 vs ~170) — not this FEED.

## What FEED-4 writes

Pure product: `tools/map_generation/lib/seas_coarsen_feed4_product.py`  
Write: `tools/map_generation/scripts/apply_seas_coarsen_feed4.py`

1. **Reshape** `950128` Alboran Sea onto a basin ring in the void corridor (east of the strait, south of Málaga/Granada/Almería hulls, north of Maghreb RoW hulls). ID / name / `domain=sea` stay.
2. **Adjacency** (theater only): `950128` ↔ `950019` plus coastal land that actually touches the new ring. Stale leftover neighbors (`950003`, `904135`) dropped from `950128`. Gibraltar / Ceuta land-neighbor lists are not given new sea edges (FEED-3 choke/isthmus stays).
3. **No land mesh writes.** No Great Lakes / Maginot / `world_full` writes. Sea block stays **340** IDs. Board stays **3527**.

## Theater metrics (before → after)

| Metric | Before (leftover seed) | After (basin ring) |
|--------|------------------------|--------------------|
| Theater sea IDs | `950019`, `950128` | same (reshape, not delete) |
| Theater sea n | **2** | **2** (fewer leftover east-Med seeds occupying this basin: 950128 left that cluster) |
| Alboran canvas area | **240.82** | **1881.05** |
| Strait canvas area | 88.95 | 88.95 (unchanged) |
| Theater median area | **164.88** | **985.00** |
| vs Iberian coastal land median (~475) | Alboran **0.51×** (smaller than land) | Alboran **3.96×** (clearly larger) |
| Alboran centroid | (2.95, 36.52) leftover | (−3.11, 36.04) in-basin |
| Basin samples (−4.0,36.0) etc. | VOID | inside `950128` |

Board count stays **3527** (land ~3187 + sea block 340). Seas stay domain water.

## Later FEEDs (not this PR)

- Other Med basins (Balearic / Ligurian / Tyrrhenian leftover seeds) — only if Scott unlocks.
- North Atlantic strip coarsen — already readable vs Iberian land; not this GO.
- Hong Kong or other keys — only if still missing after a later Scott GO.

## Gates (machine)

Slice green on this PR:

```bash
python3 -m unittest tools.map_generation.tests.test_seas_coarsen_feed4_product -v
python3 -m unittest tools.map_generation.tests.test_gibraltar_island_land_product \
  tools.map_generation.tests.test_maginot_land_uniformity_product \
  tools.map_generation.tests.test_great_lakes_water_province_product \
  tools.map_generation.tests.test_world_accurate_board -v
```

`map_accuracy_qc` must stay hard_ok. Hierarchy / ownership / choke tests stay PASS.

## Play smoke (human)

Home Iberia / Gibraltar operational zoom: pick Alboran water east of the strait — inspector should read **Alboran Sea** (`950128`), not void and not Cadiz. Strait pick still reads **Gibraltar Strait Zone**. Rock pick still **Gibraltar** land `711520`. Esc HARD PASS on the tip. Dig2 / G / Maginot combat not in this FEED.
