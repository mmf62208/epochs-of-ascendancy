# FEED-10 — Tyrrhenian Sea basin reshape (Mike bar #3)

**Status:** FEED-10 theater proof on `world_accurate` (draft; **HOLD merge** for Scott/Play).  
**Tip lineage:** SE England FEED-9 KEEP `b335344c4c9d0cba1aa6c1ae7f51733e9e249731` (`b335344c`, PR 53).  
**Scope:** Mike bar **#3 only** — seas/oceans larger (fewer, bigger water cells). Theater = **Tyrrhenian Sea**, the west-Italy / Corsica–Sardinia basin south of Cap Corse / Ligurian `950119`.

This is a design note + one theater proof. It is **not** a whole-Med remesh, **not** Ligurian / Alboran / strait redo (FEED-8 / FEED-4 / FEED-3), **not** Adriatic / Ionian / Levantine, **not** Maginot / Flanders / SE England land, **not** North Atlantic / Channel coarsen, **not** lakes (FEED-1), and **not** combat.

Pattern clone: [`MAP_SEAS_COARSEN_FEED8_LIGURIAN.md`](MAP_SEAS_COARSEN_FEED8_LIGURIAN.md) (Ligurian `950119`) / [`MAP_SEAS_COARSEN_FEED4.md`](MAP_SEAS_COARSEN_FEED4.md) (Alboran `950128`).

## Mike bar (unchanged)

1. Land provinces more uniform on continents — FEED-2 / FEED-7 / FEED-9
2. Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale — FEED-3 / FEED-5 / FEED-6
3. **Seas/oceans larger (fewer, bigger water cells)** — this FEED (Tyrrhenian only; Alboran already FEED-4; Ligurian already FEED-8)
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape that **keeps existing sea IDs**, or append-only new IDs.
- FEED-10 **reuses** sea `950120` (Tyrrhenian Sea). Moving the ring is not a renumber. No new sea ID.
- Land IDs unchanged: Maginot `710173` / `710739` / `711514–711519`, Flanders/Nord `710734` / `711521` / `711522`, Gibraltar `711520`, SE England `711438` / `711449` / `711523` / `711524`, west-Italy / Corsica / Sardinia NUTS (`710953` Grosseto, `710963` Roma, `710964` Latina, `710892` Napoli, `710801` Corse-du-Sud, `710802` Haute-Corse, `710917` Sassari, `710918` Nuoro, `710921` Sud Sardegna).
- Other seas **mesh-untouched:** Ligurian `950119`, Alboran `950128`, Gibraltar Strait `950019`, Adriatic `950121`, English Channel `950001`, Great Lakes `950333–950337`.
- Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Maginot combat / Control Labels / duals / Godot bump / second sea are out of scope.

## Theater window

Label-anchor lon/lat **`9.5–15.0°E`, `38.2–42.5°N`** — west-Italy / Corsica–Sardinia water (south of Cap Corse / Ligurian, west of the Italian peninsula).

**Explicitly out of scope:** Ligurian `950119` reshape · Alboran `950128` / strait `950019` · Adriatic / Ionian / Levantine · North Atlantic / Channel coarsen · Maginot / Flanders / SE England / Oxfordshire / Hampshire land · Greater London grow · `world_full` ID renumber · Dig2 pan · G polyline · combat · Godot bump · dual packages · second sea.

Board: `data/provinces_world_accurate` only. **`world_full` never written / never renumbered.**

## Diagnosis (accurate board, pre-FEED)

Named Tyrrhenian Sea existed, but it was a leftover `expand_grand_theater` seed hex bunched with Western/Central Med leftovers around 4–6°E / 36–37°N (**south of Spain**). The **real Tyrrhenian basin** was entirely **void**. West-Italy / Corsica–Sardinia coastal land in `9.5–15.5°E / 38.0–42.8°N` (area 20–2000) median **~202**.

| ID | Name | Domain | Pre canvas area | Pre centroid | Role |
|----|------|--------|-----------------|--------------|------|
| 950120 | Tyrrhenian Sea | sea | **344.35** | (5.48, 37.00) | leftover seed **south of Spain** (wrong basin) |
| 950003 | Western Mediterranean | sea | 580.26 | (4.15, 36.88) | leftover cluster; **not this basin** |
| 950004 | Central Mediterranean | sea | 133.56 | (5.77, 36.66) | leftover cluster; **not this basin** |
| 950119 | Ligurian Sea | sea | 1340.58 | (8.84, 43.70) | FEED-8 basin; **kept** |
| 950128 | Alboran Sea | sea | 1881.05 | (−3.11, 36.04) | FEED-4 basin; **kept** |
| 950121 | Adriatic Sea | sea | 393.06 | (6.29, 37.02) | leftover seed; **mesh not this FEED** |
| 710953 | Grosseto | land | 333.07 | (11.28, 42.75) | Tuscany coast comparator |
| 710963 | Roma | land | 401.73 | (12.68, 41.82) | Lazio coast |
| 710918 | Nuoro | land | 404.09 | (9.26, 40.14) | Sardinia east coast |

Theater seas for this proof = `{950120}`: **n=1**, area **344.35**. Sample water (12.0, 40.5) / (11.5, 41.5) / (13.0, 41.0) / (10.5, 40.0) / (14.0, 40.5) = VOID. Leftover point (5.48, 37.00) owned by `950120`.

## What FEED-10 writes

Pure product: `tools/map_generation/lib/seas_coarsen_feed10_tyrrhenian_product.py`  
Write: `tools/map_generation/scripts/apply_seas_coarsen_feed10_tyrrhenian.py`

1. **Reshape** `950120` Tyrrhenian Sea onto a basin ring in the Tyrrhenian void (west of Italian peninsula, east of Corsica/Sardinia as measured, south of Cap Corse / Ligurian `950119`). ID / name / `domain=sea` stay.
2. **Adjacency** (theater only): `950120` ↔ coastal land that actually touches the new ring (west-Italy / Corsica / Sardinia as measured, 8px). Stale leftover-cluster neighbors (`950003`, `950004`, `950121`) dropped from `950120` and from those seas' lists. No Ligurian / Alboran / strait / Adriatic / Channel **new** edges.
3. **No land mesh writes.** No Ligurian / Alboran / Adriatic / Channel / Maginot / Flanders / SE England / Great Lakes mesh writes. No `world_full` writes. Sea block stays **340** IDs. Board stays **3536**.

## Theater metrics (before → after)

| Metric | Before (leftover seed) | After (basin ring) |
|--------|------------------------|--------------------|
| Theater sea IDs | `950120` | same (reshape, not delete) |
| Theater sea n | **1** | **1** (same sea-block cardinality as FEED-8 / FEED-4 pattern) |
| Tyrrhenian canvas area | **344.35** | **7908.24** (Alboran/Ligurian-class ≳1000; basin void allows) |
| Theater median area | **344.35** | **7908.24** |
| vs west-Italy coastal land median (~202) | leftover in the **wrong** basin | Tyrrhenian **~39.1×** coastal median |
| Tyrrhenian centroid / label-anchor | (5.48, 37.00) south of Spain | **(11.590, 40.605)** in-basin window |
| Basin samples (12.0,40.5) etc. | VOID | inside `950120` |
| Leftover (5.48, 37.00) | owned by `950120` | vacated |

Board count stays **3536** (land ~3196 + sea block 340). Seas stay domain water.

Measured coastal neighbors (8px, coast window): Corse-du-Sud `710801`, Haute-Corse `710802`, Napoli `710892`, Sassari `710917`, Nuoro `710918`, Sud Sardegna `710921`, Grosseto `710953`, Viterbo `710961`, Roma `710963`, Latina `710964`. Sicily / Ligurian / leftover Med seas are not neighbors.

## Later FEEDs (not this PR)

- Adriatic / Ionian / Levantine leftover seeds — only if Scott unlocks.
- North Atlantic / Channel coarsen — not this GO.
- Other keys — only if still missing after a later Scott GO.

## Gates (machine)

Slice green on this PR:

```bash
python3 -m unittest tools.map_generation.tests.test_seas_coarsen_feed10_tyrrhenian_product -v
python3 -m unittest tools.map_generation.tests.test_seas_coarsen_feed8_ligurian_product \
  tools.map_generation.tests.test_seas_coarsen_feed4_product \
  tools.map_generation.tests.test_se_england_shire_land_uniformity_product \
  tools.map_generation.tests.test_flanders_nord_land_uniformity_product \
  tools.map_generation.tests.test_maginot_land_uniformity_product \
  tools.map_generation.tests.test_great_lakes_water_province_product \
  tools.map_generation.tests.test_gibraltar_island_land_product \
  tools.map_generation.tests.test_hong_kong_island_land_product \
  tools.map_generation.tests.test_caribbean_island_sizing_feed6_product -v
```

`map_accuracy_qc` on the written board is optional this slice (product unittest is the gate). FEED-8 Ligurian + FEED-4 Alboran + FEED-9 SE England + FEED-7 Flanders + FEED-2 Maginot + FEED-1 Great Lakes + Gibraltar / HK / Windward product tests stay green. FEED-8's leftover-area pin on `950120` is retired: FEED-10 owns that mesh; Ligurian ID/name/domain stay.

`--quick` living-unit wiring fails (if any) are **tip-pre-existing** on `b335344c4c9d0cba1aa6c1ae7f51733e9e249731`. This FEED does not touch those GD files. Out of scope (not a seas-board issue).

## Play smoke (human)

Home Europe south-coast operational zoom: pick Tyrrhenian water west of Roma / Napoli and east of Corsica / Sardinia — inspector should read **Tyrrhenian Sea** (`950120`), not void and not a leftover south of Spain. Ligurian pick still **Ligurian Sea**. Alboran pick still **Alboran Sea**. Maginot / Flanders / SE England land picks unchanged. Esc HARD PASS on the tip. Dig2 / G / Maginot combat not in this FEED.
