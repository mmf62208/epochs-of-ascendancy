# FEED-3 — Gibraltar island-scale land key (Mike bar #2)

**Status:** FEED-3 theater proof on `world_accurate` (draft; HOLD merge for Scott/Play).  
**Tip lineage:** Maginot land FEED-2 KEEP `caa3c8e78e263be2f9029e27eb1332e80019cdac`.  
**Scope:** Mike bar **#2 only** — key chokepoints treated like island-scale provinces. Theater = **Gibraltar rock only**.

This is a design note + one theater proof. It is **not** Hong Kong, **not** other keys, **not** seas/oceans coarsening, **not** Maginot/Great Lakes rework, and **not** combat.

## Mike bar (unchanged)

1. Land provinces more uniform on continents — FEED-2
2. **Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale** — this FEED (Gibraltar only)
3. Seas/oceans larger (fewer, bigger water cells) — later FEED
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape geometry that keeps IDs, or **append-only** new IDs on carve.
- FEED-3 **keeps** Cadiz `710671`, Ceuta `710679`, and sea/strait `950019` (Gibraltar Strait Zone).
- New land ID is Europe-block **`711520`** (next after Maginot append `711519`). No merge-retire.
- Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Maginot combat / Control Labels / duals / Godot bump / seas coarsening / HK / whole-world remesh are out of scope.

## Diagnosis (accurate board, pre-FEED)

`naval_chokepoints.json` maps the named choke to sea/strait `950019` (`domain=strait`). That cell is water. No land province was named Gibraltar.

| ID | Name | Domain | Canvas area | Role |
|----|------|--------|-------------|------|
| 950019 | Gibraltar Strait Zone | strait (sea) | ~89 | naval choke; **not** the rock |
| 710671 | Cádiz | land / mainland | ~502 | Spanish NUTS-3; isthmus tip ~0.35 px north of the rock |
| 710679 | Ceuta | land / mainland | ~0.65 | North-African enclave; not the rock |

The WGS84 rock (−5.3536, 36.1408) sat in a **void** between Cadiz's southern vertices and the strait ring — not inside Cadiz, Ceuta, or `950019`. Play could not pick a dedicated Gibraltar land key.

Island-scale comparators on this canvas: Gozo ~5.4, Malta ~13.0, Ibiza ~40, Cadiz ~502. Ceuta ~0.65 is a speck, not a readable key.

## What FEED-3 writes

Pure product: `tools/map_generation/lib/gibraltar_island_land_product.py`  
Write: `tools/map_generation/scripts/apply_gibraltar_island_land.py`

1. **Append** land `711520` **Gibraltar** — Malta-like island-key ring (**13.67** canvas area) covering the rock and the Cadiz isthmus tip. `island_class=island`, terrain mountains, owner **ENG** (1713–present; not a SPA clone).
2. **Clip** Cadiz's isthmus spike (shared north shore). Cadiz ID / name / SPA owner stay. Cadiz remains mainland-scale (502 → **470**).
3. **Adjacency** (theater only): `711520` ↔ `710671` (isthmus) and `711520` ↔ `950019` (strait). Ceuta is **not** land-bridged.
4. Hierarchy / Iberia region / Cadiz's state bucket / city / economy / terrain cloned or filled for the new ID only.

Board scale stays **~3520** (3526 + 1 = **3527**). Seas stay **340**. `world_full` is not written. `950019` remains the naval choke.

## Later FEEDs (not this PR)

- **Seas/oceans coarsen** (bar #3) — separate GO.
- **Hong Kong** or other keys — only if still missing after a later Scott GO.
- Do not remesh whole Iberia / Africa here.

## Gates (machine)

Slice green on this PR:

```bash
python3 -m unittest tools.map_generation.tests.test_gibraltar_island_land_product -v
```

`map_accuracy_qc` on the written board: hard_ok, matched **3527**, orphans 0, NE land hit **0.985**. Maginot FEED-2 QC still green. `world_accurate` hierarchy/ownership/choke tests green.

`--quick` still fails `test_living_unit_order_loop_product` (wiring: `air_region_cas`, `peace_occupation`, `nation_era_next`, `map_country_select`, `playtest_clock`). **Same fails on tip** `caa3c8e7` — this FEED does not touch those GD files. Out of scope (not a Gibraltar board issue).

## Play smoke (human)

Home Iberia / Gibraltar operational zoom: pick the rock — inspector should read **Gibraltar** (land `711520`), not Cadiz and not "Gibraltar Strait Zone". Strait pick still reads the sea choke. Esc HARD PASS on the tip. Dig2 / G / Maginot combat not in this FEED.
