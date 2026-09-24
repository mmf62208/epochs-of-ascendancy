# FEED-8 — Ligurian Sea basin reshape (Mike bar #3)

**Status:** FEED-8 theater proof on `world_accurate` (draft; **HOLD merge** for Scott/Play).  
**Tip lineage:** Flanders/Nord FEED-7 KEEP `665970c641baf10aed756e6354093b4fed250ae0` (`665970c`).  
**Scope:** Mike bar **#3 only** — seas/oceans larger (fewer, bigger water cells). Theater = **Ligurian Sea**, the Genoa-gulf basin between Liguria / Provence / N Italy and Cap Corse.

This is a design note + one theater proof. It is **not** a whole-Med remesh, **not** Tyrrhenian / Adriatic / Ionian / Levantine, **not** Alboran / Gibraltar strait redo (FEED-4 / FEED-3), **not** Maginot land (FEED-2), **not** Flanders/Nord land (FEED-7), **not** North Atlantic / Channel coarsen, **not** lakes (FEED-1), and **not** combat.

Pattern clone: [`MAP_SEAS_COARSEN_FEED4.md`](MAP_SEAS_COARSEN_FEED4.md) (Alboran `950128`).

## Mike bar (unchanged)

1. Land provinces more uniform on continents — FEED-2 / FEED-7
2. Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale — FEED-3 / FEED-5 / FEED-6
3. **Seas/oceans larger (fewer, bigger water cells)** — this FEED (Ligurian only; Alboran already FEED-4)
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape that **keeps existing sea IDs**, or append-only new IDs.
- FEED-8 **reuses** sea `950119` (Ligurian Sea). Moving the ring is not a renumber. No new sea ID.
- Land IDs unchanged: Maginot `710173` / `710739` / `711514–711519`, Flanders/Nord `710734` / `711521` / `711522`, Gibraltar `711520`, Liguria–Provence NUTS (`710797` Alpes-Maritimes, `710868` Imperia, `710869` Savona, `710870` Genova, `710871` La Spezia).
- Other seas **mesh-untouched:** Alboran `950128`, Gibraltar Strait `950019`, Tyrrhenian `950120`, Adriatic `950121`, English Channel `950001`, Great Lakes `950333–950337`.
- Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Maginot combat / Control Labels / duals / Godot bump / second sea are out of scope.

## Theater window

Label-anchor lon/lat **`7.5–10.5°E`, `43.0–44.6°N`** — Genoa gulf / Liguria–Provence–N Italy water.

**Explicitly out of scope:** Alboran `950128` / strait `950019` · Maginot land · Flanders/Nord land · Tyrrhenian `950120` / Adriatic `950121` / Ionian / Levantine reshape · North Atlantic / Channel coarsen · `world_full` ID renumber · Dig2 pan · G polyline · combat · Godot bump · dual packages · second sea.

Board: `data/provinces_world_accurate` only. **`world_full` never written / never renumbered.**

## Diagnosis (accurate board, pre-FEED)

Named Ligurian Sea existed, but it was a leftover `expand_grand_theater` seed hex bunched with Western/Central Med / Tyrrhenian leftovers around 4–6°E / 36–37°N (**south of Spain**). The **real Ligurian basin** was entirely **void**. Liguria–Provence coastal land in the basin window (area 20–2000) median **~121** (user bar ~130).

| ID | Name | Domain | Pre canvas area | Pre centroid | Role |
|----|------|--------|-----------------|--------------|------|
| 950119 | Ligurian Sea | sea | **705.08** | (5.08, 37.28) | leftover seed **south of Spain** (wrong basin) |
| 950003 | Western Mediterranean | sea | 580.26 | (4.15, 36.88) | leftover cluster; **not this basin** |
| 950004 | Central Mediterranean | sea | 133.56 | (5.77, 36.66) | leftover cluster; **not this basin** |
| 950120 | Tyrrhenian Sea | sea | 344.35 | (5.48, 37.00) | leftover seed; **mesh not this FEED** |
| 950128 | Alboran Sea | sea | 1881.05 | (−3.11, 36.04) | FEED-4 basin; **kept** |
| 710870 | Genova | land | 139.60 | (9.07, 44.47) | Liguria coast comparator |
| 710868 | Imperia | land | 82.71 | (7.81, 43.96) | Liguria coast |
| 710797 | Alpes-Maritimes | land | 311.42 | (7.22, 43.86) | Provence coast |

Theater seas for this proof = `{950119}`: **n=1**, area **705.08**. Sample water (8.9, 43.9) / (8.5, 43.7) / (9.3, 44.0) = VOID. Leftover point (5.08, 37.28) owned by `950119`.

## What FEED-8 writes

Pure product: `tools/map_generation/lib/seas_coarsen_feed8_ligurian_product.py`  
Write: `tools/map_generation/scripts/apply_seas_coarsen_feed8_ligurian.py`

1. **Reshape** `950119` Ligurian Sea onto a basin ring in the gulf void (south of Imperia / Savona / Genova / Spezia / Alpes-Maritimes hulls, north of Cap Corse ~42.96°N). ID / name / `domain=sea` stay.
2. **Adjacency** (theater only): `950119` ↔ coastal land that actually touches the new ring (Liguria / Provence / N Italy as measured, 8px). Stale leftover-cluster neighbors (`950003`, `950004`, `950120`) dropped from `950119` and from those seas' lists. No Alboran / strait / Adriatic / Channel edges.
3. **No land mesh writes.** No Tyrrhenian / Adriatic / Alboran / Channel / Maginot / Flanders / Great Lakes mesh writes. No `world_full` writes. Sea block stays **340** IDs. Board stays **3534**.

## Theater metrics (before → after)

| Metric | Before (leftover seed) | After (basin ring) |
|--------|------------------------|--------------------|
| Theater sea IDs | `950119` | same (reshape, not delete) |
| Theater sea n | **1** | **1** (same sea-block cardinality as FEED-4 pattern) |
| Ligurian canvas area | **705.08** | **1340.58** (Alboran-class ≳1000) |
| Theater median area | **705.08** | **1340.58** |
| vs Liguria–Provence coastal land median (~121 / bar ~130) | leftover in the **wrong** basin | Ligurian **11.10×** coastal median |
| Ligurian centroid / label-anchor | (5.08, 37.28) south of Spain | **(8.835, 43.695)** in-gulf window |
| Basin samples (8.9,43.9) etc. | VOID | inside `950119` |
| Leftover (5.08, 37.28) | owned by `950119` | vacated |

Board count stays **3534** (land ~3194 + sea block 340). Seas stay domain water.

Measured coastal neighbors (8px, coast window): Alpes-Maritimes `710797`, Imperia `710868`, Savona `710869`, Genova `710870`, La Spezia `710871`, plus N Italy hulls that actually touch (Massa-Carrara / Lucca / Livorno / Pisa as measured). Corsica / Cuneo / Var / leftover Med seas are not neighbors.

## Later FEEDs (not this PR)

- Tyrrhenian / Adriatic / Ionian / Levantine leftover seeds — only if Scott unlocks.
- North Atlantic / Channel coarsen — not this GO.
- Other keys — only if still missing after a later Scott GO.

## Gates (machine)

Slice green on this PR:

```bash
python3 -m unittest tools.map_generation.tests.test_seas_coarsen_feed8_ligurian_product -v
python3 -m unittest tools.map_generation.tests.test_seas_coarsen_feed4_product \
  tools.map_generation.tests.test_flanders_nord_land_uniformity_product \
  tools.map_generation.tests.test_maginot_land_uniformity_product \
  tools.map_generation.tests.test_great_lakes_water_province_product \
  tools.map_generation.tests.test_gibraltar_island_land_product \
  tools.map_generation.tests.test_hong_kong_island_land_product \
  tools.map_generation.tests.test_caribbean_island_sizing_feed6_product -v
```

`map_accuracy_qc` on the written board: hard_ok, matched **3534**, orphans 0, NE land hit **0.9853**. FEED-4 Alboran + FEED-7 Flanders + FEED-2 Maginot + FEED-1 Great Lakes + Gibraltar / HK / Windward product tests PASS.

`--quick` still fails `test_living_unit_order_loop_product` (wiring: `air_region_cas`, `peace_occupation`, `nation_era_next`, `map_country_select`, `playtest_clock`). **Same fails on tip** `665970c` — this FEED does not touch those GD files. Out of scope (not a seas-board issue). `map_qc` + HOI matrix steps **OK**.

## Play smoke (human)

Home Europe south-coast operational zoom: pick Genoa-gulf water south of Genova / Imperia — inspector should read **Ligurian Sea** (`950119`), not void and not a leftover south of Spain. Alboran pick still **Alboran Sea**. Maginot / Flanders land picks unchanged. Esc HARD PASS on the tip. Dig2 / G / Maginot combat not in this FEED.
