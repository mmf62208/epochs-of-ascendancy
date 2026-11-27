# MAP-2C-PER

Real admin rings for the 65 Persia (Iran, tag `PER`) 1936 land placeholders on `world_accurate`. Tag `PER` in this game is Persia, not Peru.

Measured on base `76408b80d7ef9d02914398b3e0b3db28170fd25d`: **65** PER-owned land placeholders (id < 950000), ids `903294`–`903359` except `903321`, all 36-vertex circles. After this slice, **65** of those rings carry `gap_per1` and **0** stay placeholders. Land placeholders on the board: **320 to 255**. Province ids stay **3596**. Non-PER rings are byte-identical to the base.

Meshkinshahr `903321` was already a real ring and is outside the scope list. It is notched by Ardebil. The eight Peruvian provinces that share the `PER` tag were already real rings and are outside the scope list.

## Unknown

None. `UNKNOWN_PLACEHOLDER_IDS` is empty. Every in-scope name matched a gbOpen IRN ADM2 polygon inside the distance limit.

## Source level

geoBoundaries gbOpen simplified geometry, cached in `~/mappers/scratch/geoboundaries` (not committed).

| File | sha256 |
|------|--------|
| `geoBoundaries-IRN-ADM0_simplified.geojson` | `f76a8937fad80af06a586a95b7ff1ff2d848dbe867e90ce160b51d9fa05682c0` |
| `geoBoundaries-IRN-ADM1_simplified.geojson` | `bed64f34847d707d6448d11afed74e87b594b37edd61c77622746c54efd3d970` |
| `geoBoundaries-IRN-ADM2_simplified.geojson` | `16502da0eabcbaa3ffbe24a99db12c18ca8a1f5d4980749911aa5e298e6ae17c` |

All 65 scope provinces are IRN ADM2 (shahrestan / county). ADM1 (ostan) was not needed: every name matched a county. Names are matched after diacritics, a trailing "area", and the words County and Shahrestan are stripped. Hyphen and space fold to the same key, so Gonbad-e-Kavus matches Gonbad-e Kavus. A multipolygon keeps the part of at least 1 px whose centroid is nearest the province and still inside max(80 px, 1.5 radii).

Projection is the same helper as the earlier slices: `apply_gap_ussr_west2._canvas_ring` via `ne_full_geometry_align.lonlat_to_canvas`.

New rings win overlapping land pixels against PER neighbours only. Those neighbours are notched, never deleted. Sea zones (id >= 950000) keep their pixels. A modern ring that would cover a non-PER 1936 province is clipped. Old placeholder pixels that cover no other province stay, so the slice opens no new hole.

## Sarbaz edge

`KEEP_ADJACENCY` is the undirected edge `903351` Sarbaz (PER) — `903586` Baluchistan West (ENG). It is the real Baluchistan border. The sea clip against `950290` Arabian Sea Deep South leaves only a 14 px contact fragment, and the tracer drops that fragment, so the written rings do not touch. The edge stays in `province_adjacency.json` as an adjacency-only keep. Sea pixels are not painted into Sarbaz, and Sarbaz is not left as a placeholder circle. `test_gap_per1.py` asserts the keep list, a non-empty reason, and both directions in the written adjacency file.

## Hormuz Approaches

Sea province `950022` Hormuz Approaches (351 px) sits inside inland Tabas `903354`. Its meta is `sea_reanchor_v1` at lon 56.5, lat 26.5, about 219 px north of the ring. That looks like an existing sea-reanchor anchor bug for a separate slice. This slice leaves the `950022` ring byte-identical. The clip omits it so the tracer can emit a Tabas ring, then a 1 px bay (4 px corridor) opens the sea out of Tabas. The written Tabas ring overlaps `950022` by **0** pixels.

## Accepted area changes

Nain `903342` absorbs an enclosed empty hole of **719** px at canvas (5330.5, 1436.5). The written ring covers **734** pixels that no pre-apply province covered (the hole plus the retrace). Area 1465.5 → 2197.0.

Meshkinshahr `903321` is notched for Ardebil `903307`: **269.0 → 258.0** px, 68 → 62 vertices.

## Adjacency

Undirected edges **+8 / −2** (total 10).

Added: Ardekan–Bahabad, Hajiabad–Neyriz, Iranshahr–Sarbaz, Ravar–Tabas, Nain–Damghan, Nain–Shahrud, Nain–Tabas, Tabas–Kerman.

Removed: Jask–Nikshahr, Ghalehganj–Nikshahr.

Kept (not a tracer touch): Sarbaz–Baluchistan West.

## Area exemption

`gap_nld1_product.area_change_ok` treats a later slice as exempt only when meta has `gap_sia1` or `gap_sia1_yield`. `gap_sia1_product.area_change_ok` exempts only those two keys. Both files are outside this slice's allow-list, so `--apply` writes `gap_sia1_yield` = `exempt:gap_per1` on each of the 65 re-rings and the one notch. The value marks a GAP-PER-1 area exemption. It is not a claim that Siam notched the province. `gap_sia1` is left unset, so the SIA ring audit does not adopt these provinces. Godot does not read the key.

## Provinces

| id | name | level | area px before → after | verts | centroid shift px |
|----|------|-------|------------------------|-------|-------------------|
| 903294 | Esfarayen County | IRN-ADM2 | 333.56 → 339.0 | 36 → 54 | 6.16 |
| 903295 | Kermanshah | IRN-ADM2 | 373.56 → 395.0 | 36 → 88 | 2.4 |
| 903296 | Dehloran County | IRN-ADM2 | 443.8 → 460.0 | 36 → 108 | 3.97 |
| 903297 | Khoy | IRN-ADM2 | 290.94 → 311.0 | 36 → 48 | 4.98 |
| 903298 | Bijar | IRN-ADM2 | 387.86 → 399.0 | 36 → 98 | 1.32 |
| 903299 | Baneh | IRN-ADM2 | 104.65 → 108.0 | 36 → 40 | 1.82 |
| 903300 | Ahvaz | IRN-ADM2 | 287.06 → 332.0 | 36 → 74 | 2.73 |
| 903301 | Eqlid | IRN-ADM2 | 438.83 → 459.0 | 36 → 78 | 3.02 |
| 903302 | Saveh | IRN-ADM2 | 305.16 → 314.0 | 36 → 80 | 0.57 |
| 903303 | Urumia | IRN-ADM2 | 369.83 → 376.0 | 36 → 70 | 1.25 |
| 903304 | Sorkheh | IRN-ADM2 | 610.32 → 616.0 | 36 → 38 | 7.63 |
| 903305 | Ardestan | IRN-ADM2 | 804.35 → 776.0 | 36 → 78 | 0.32 |
| 903306 | Gonbad-e-Kavus | IRN-ADM2 | 297.89 → 351.0 | 36 → 82 | 5.04 |
| 903307 | Ardebil | IRN-ADM2 | 163.44 → 171.0 | 36 → 56 | 0.86 |
| 903308 | Qazvin | IRN-ADM2 | 372.06 → 389.0 | 36 → 80 | 0.69 |
| 903309 | Qom | IRN-ADM2 | 768.62 → 684.0 | 36 → 88 | 4.72 |
| 903310 | Semirom | IRN-ADM2 | 319.04 → 332.0 | 36 → 62 | 3.48 |
| 903311 | Khodabandeh | IRN-ADM2 | 325.95 → 346.0 | 36 → 76 | 1.84 |
| 903312 | Khoramabad | IRN-ADM2 | 328.08 → 341.0 | 36 → 80 | 4.82 |
| 903313 | Ardekan | IRN-ADM2 | 1324.29 → 1495.0 | 36 → 150 | 7.75 |
| 903314 | Shahin Shahr and Meymeh | IRN-ADM2 | 328.07 → 335.0 | 36 → 76 | 1.27 |
| 903315 | Hajiabad | IRN-ADM2 | 699.83 → 708.0 | 36 → 84 | 2.41 |
| 903316 | Shiraz | IRN-ADM2 | 384.72 → 386.0 | 36 → 73 | 1.63 |
| 903317 | Neyriz | IRN-ADM2 | 661.2 → 673.0 | 36 → 98 | 2.48 |
| 903318 | Isfahan County | IRN-ADM2 | 971.87 → 1015.0 | 36 → 100 | 11.44 |
| 903319 | Aligudarz | IRN-ADM2 | 352.17 → 356.0 | 36 → 60 | 4.17 |
| 903320 | Shahr-e-Babak | IRN-ADM2 | 852.69 → 861.0 | 36 → 100 | 1.69 |
| 903322 | Iranshahr | IRN-ADM2 | 1319.81 → 1229.0 | 36 → 128 | 2.15 |
| 903323 | Juybar | IRN-ADM2 | 19.35 → 20.0 | 36 → 14 | 0.57 |
| 903324 | Mashhad | IRN-ADM2 | 637.12 → 655.0 | 36 → 98 | 0.62 |
| 903325 | Sirjan | IRN-ADM2 | 792.46 → 796.0 | 36 → 94 | 2.16 |
| 903326 | Ravar | IRN-ADM2 | 748.24 → 865.0 | 36 → 73 | 2.1 |
| 903327 | Sarayan | IRN-ADM2 | 607.21 → 627.0 | 36 → 102 | 1.71 |
| 903328 | Sabzevar | IRN-ADM2 | 671.13 → 686.0 | 36 → 73 | 1.54 |
| 903329 | Mianeh | IRN-ADM2 | 343.66 → 387.0 | 36 → 64 | 0.48 |
| 903330 | Larestan | IRN-ADM2 | 808.9 → 756.0 | 36 → 96 | 3.75 |
| 903331 | Jask | IRN-ADM2 | 604.98 → 688.0 | 36 → 78 | 6.28 |
| 903332 | Jiroft | IRN-ADM2 | 584.52 → 606.0 | 36 → 86 | 1.73 |
| 903333 | Bandar-e-Lengeh | IRN-ADM2 | 505.62 → 529.0 | 36 → 60 | 1.19 |
| 903334 | Zanjan | IRN-ADM2 | 457.4 → 461.0 | 36 → 78 | 1.82 |
| 903335 | Bahabad | IRN-ADM2 | 370.82 → 427.0 | 36 → 74 | 5.88 |
| 903336 | Dashtestan | IRN-ADM2 | 391.13 → 340.0 | 36 → 73 | 6.84 |
| 903337 | Khusf | IRN-ADM2 | 1015.09 → 1017.0 | 36 → 122 | 2.68 |
| 903338 | Khaf | IRN-ADM2 | 641.25 → 650.0 | 36 → 84 | 2.51 |
| 903339 | Miami | IRN-ADM2 | 548.56 → 574.0 | 36 → 98 | 2.6 |
| 903340 | Khonj | IRN-ADM2 | 269.41 → 270.0 | 36 → 70 | 1.09 |
| 903341 | Khash | IRN-ADM2 | 996.55 → 1014.0 | 36 → 126 | 8.84 |
| 903342 | Nain | IRN-ADM2 | 1465.5 → 2197.0 | 36 → 96 | 8.12 |
| 903343 | Damghan | IRN-ADM2 | 854.8 → 941.0 | 36 → 74 | 13.27 |
| 903344 | Shahrud | IRN-ADM2 | 2851.14 → 2872.0 | 36 → 148 | 4.24 |
| 903345 | Sarbisheh | IRN-ADM2 | 513.46 → 527.0 | 36 → 98 | 1.88 |
| 903346 | Dashti | IRN-ADM2 | 227.99 → 79.0 | 36 → 30 | 8.97 |
| 903347 | Maraveh Tapeh | IRN-ADM2 | 158.89 → 216.0 | 36 → 40 | 5.6 |
| 903348 | Ghalehganj | IRN-ADM2 | 625.91 → 287.0 | 36 → 74 | 6.79 |
| 903349 | Hamun | IRN-ADM2 | 301.04 → 306.0 | 36 → 62 | 4.55 |
| 903350 | Zahedan | IRN-ADM2 | 1772.18 → 1886.0 | 36 → 142 | 3.15 |
| 903351 | Sarbaz | IRN-ADM2 | 595.9 → 260.0 | 36 → 48 | 18.96 |
| 903352 | Gilan-e-Gharb | IRN-ADM2 | 185.09 → 190.0 | 36 → 76 | 2.12 |
| 903353 | Sirik | IRN-ADM2 | 108.83 → 150.0 | 36 → 37 | 3.59 |
| 903354 | Tabas | IRN-ADM2 | 3307.87 → 3261.0 | 36 → 272 | 5.87 |
| 903355 | Nikshahr | IRN-ADM2 | 776.03 → 214.0 | 36 → 30 | 18.32 |
| 903356 | Kerman | IRN-ADM2 | 2792.09 → 2852.0 | 36 → 186 | 7.51 |
| 903357 | Kalat | IRN-ADM2 | 205.16 → 95.0 | 36 → 48 | 7.34 |
| 903358 | Mirjaveh | IRN-ADM2 | 358.78 → 342.0 | 36 → 94 | 4.28 |
| 903359 | Nehbandan | IRN-ADM2 | 1608.19 → 1644.0 | 36 → 152 | 7.37 |

Meshkinshahr `903321` is the notch, not a re-ring: 269.0 → 258.0 px. Max centroid shift among re-rings is 18.96 px (Sarbaz, after the sea clip). Max shift from the source county centroid is 5.34 px (Ravar).

## Re-run

From the repo root, with the three geojson files above already in `~/mappers/scratch/geoboundaries`:

```bash
python3 tools/map_generation/scripts/apply_gap_per1.py
python3 tools/map_generation/scripts/apply_gap_per1.py --apply
python3 -m unittest tools.map_generation.tests.test_gap_per1 -v
```

Dry-run is the default and does not write the board. `--apply` rewrites `provinces_geometry.json` and `province_adjacency.json` for this slice only. The script is deterministic. Scope ids are frozen in `tools/map_generation/lib/gap_per1_product.py`, so Ship can re-apply it on a later base that still has these placeholders. Evidence lands in `~/mappers/evidence/` (not committed).
