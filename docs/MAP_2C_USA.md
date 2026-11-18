# MAP-2C-USA

Real admin rings for the 88 USA-1936 land placeholders on `world_accurate`.

Measured on base `a34d23a76af751c1c72239bc680a780662998e26`: **88** USA-owned land placeholders (id < 950000), all 36-vertex circles. After this slice, **88** of those rings carry `gap_usa1` and **0** stay placeholders. Land placeholders on the board: **320 to 232**. Province ids stay **3596**. Non-USA rings are unchanged.

The 88 are not continental counties. The 800000-block states, Alaska, Hawaii, and the two playable Puerto Rico halves were already real rings and are outside the scope list. The scope is 86 Philippine provinces (`904634`–`904719`), Puerto Rico `902408`, and Guam `902485`.

## Unknown

None. `UNKNOWN_PLACEHOLDER_IDS` is empty. Every in-scope name matched a gbOpen polygon inside the distance limit.

## Source level

geoBoundaries gbOpen simplified geometry, cached in `~/mapusa/scratch/geoboundaries` (not committed).

| Place | Level | Why |
|-------|--------|-----|
| 86 Philippine provinces | PHL ADM2 | Province names are provinces. ADM1 is the 17 regions and does not match those names. |
| Puerto Rico `902408` | USA ADM1 | PRI ADM0 and ADM1 return 404. The USA ADM1 feature is the island. PRI ADM2 is municipios, including one named Isabela, so it is not used. |
| Guam `902485` | GUM ADM0 | The province is the island. GUM ADM1 returns 404. GUM ADM2 is villages. |

Names are matched after diacritics, a trailing "area", and the word County are stripped. A multipolygon keeps its main part: the largest part of at least 1 px whose centroid is within max(80 px, 1.5 radii) of the province. A nearer islet is not used, and unmatched islets do not become provinces. Alaska and Hawaii needed no new rings.

Projection is the same helper as the earlier slices: `apply_gap_ussr_west2._canvas_ring` via `ne_full_geometry_align.lonlat_to_canvas`.

| id | name | level | area px before → after | verts | centroid shift px |
|----|------|-------|------------------------|-------|-------------------|
| 902408 | Puerto Rico | USA-ADM1 | 495.07 → 503.0 | 36 → 76 | 1.99 |
| 902485 | Guam | GUM-ADM0 | 33.39 → 33.0 | 36 → 26 | 0.46 |
| 904634 | Abra | PHL-ADM2 | 221.79 → 226.0 | 36 → 46 | 1.35 |
| 904635 | Agusan del Norte | PHL-ADM2 | 132.87 → 150.0 | 36 → 34 | 0.26 |
| 904636 | Agusan del Sur | PHL-ADM2 | 450.95 → 464.0 | 36 → 68 | 0.41 |
| 904637 | Aklan | PHL-ADM2 | 91.65 → 91.0 | 36 → 42 | 0.49 |
| 904638 | Albay | PHL-ADM2 | 120.45 → 127.0 | 36 → 54 | 0.14 |
| 904639 | Antique | PHL-ADM2 | 138.82 → 152.0 | 36 → 64 | 0.21 |
| 904640 | Apayao | PHL-ADM2 | 222.71 → 227.0 | 36 → 52 | 0.32 |
| 904641 | Aurora | PHL-ADM2 | 124.7 → 184.0 | 36 → 84 | 0.15 |
| 904642 | Basilan | PHL-ADM2 | 56.91 → 57.0 | 36 → 30 | 0.05 |
| 904643 | Bataan | PHL-ADM2 | 69.75 → 68.0 | 36 → 30 | 0.31 |
| 904644 | Batanes | PHL-ADM2 | 4.47 → 4.9 | 36 → 105 | 0.61 |
| 904645 | Batangas | PHL-ADM2 | 172.85 → 181.0 | 36 → 60 | 0.07 |
| 904646 | Benguet | PHL-ADM2 | 151.25 → 158.0 | 36 → 30 | 1.74 |
| 904647 | Biliran | PHL-ADM2 | 26.75 → 28.0 | 36 → 16 | 0.29 |
| 904648 | Bohol | PHL-ADM2 | 202.5 → 210.0 | 36 → 52 | 0.27 |
| 904649 | Bukidnon | PHL-ADM2 | 499.46 → 514.0 | 36 → 64 | 0.54 |
| 904650 | Bulacan | PHL-ADM2 | 125.17 → 151.0 | 36 → 32 | 0.47 |
| 904651 | Cagayan | PHL-ADM2 | 448.48 → 474.0 | 36 → 100 | 0.64 |
| 904652 | Camarines Norte | PHL-ADM2 | 140.94 → 120.0 | 36 → 46 | 0.33 |
| 904653 | Camarines Sur | PHL-ADM2 | 285.91 → 316.0 | 36 → 92 | 2.23 |
| 904654 | Camiguin | PHL-ADM2 | 13.15 → 15.0 | 36 → 10 | 0.13 |
| 904655 | Capiz | PHL-ADM2 | 131.93 → 151.0 | 36 → 62 | 0.39 |
| 904656 | Catanduanes | PHL-ADM2 | 84.27 → 84.0 | 36 → 28 | 0.01 |
| 904657 | Cavite | PHL-ADM2 | 65.54 → 70.0 | 36 → 30 | 0.41 |
| 904658 | Cebu | PHL-ADM2 | 229.45 → 252.0 | 36 → 78 | 1.52 |
| 904659 | City of Isabela | PHL-ADM2 | 9.86 → 11.15 | 36 → 133 | 0.35 |
| 904660 | Compostela Valley | PHL-ADM2 | 236.49 → 236.0 | 36 → 60 | 0.22 |
| 904661 | Cotabato | PHL-ADM2 | 294.25 → 319.0 | 36 → 76 | 0.06 |
| 904662 | Cotabato City | PHL-ADM2 | 4.3 → 4.73 | 36 → 95 | 0.49 |
| 904663 | Davao del Norte | PHL-ADM2 | 140.83 → 164.0 | 36 → 46 | 0.19 |
| 904664 | Davao del Sur | PHL-ADM2 | 202.21 → 239.0 | 36 → 46 | 0.65 |
| 904665 | Davao Occidental | PHL-ADM2 | 104.61 → 103.0 | 36 → 46 | 0.9 |
| 904666 | Davao Oriental | PHL-ADM2 | 333.69 → 287.0 | 36 → 73 | 0.07 |
| 904667 | Dinagat Islands | PHL-ADM2 | 42.17 → 47.0 | 36 → 20 | 0.22 |
| 904668 | Eastern Samar | PHL-ADM2 | 168.02 → 231.0 | 36 → 80 | 3.48 |
| 904669 | Guimaras | PHL-ADM2 | 30.87 → 35.0 | 36 → 22 | 0.02 |
| 904670 | Ifugao | PHL-ADM2 | 80.68 → 145.0 | 36 → 34 | 1.37 |
| 904671 | Ilocos Norte | PHL-ADM2 | 188.96 → 189.0 | 36 → 32 | 0.07 |
| 904672 | Ilocos Sur | PHL-ADM2 | 135.11 → 109.0 | 36 → 32 | 0.12 |
| 904673 | Iloilo | PHL-ADM2 | 228.0 → 259.0 | 36 → 92 | 0.18 |
| 904674 | Isabela | PHL-ADM2 | 563.29 → 601.0 | 36 → 80 | 0.73 |
| 904675 | Kalinga | PHL-ADM2 | 159.06 → 158.0 | 36 → 44 | 0.45 |
| 904676 | La Union | PHL-ADM2 | 80.58 → 83.0 | 36 → 32 | 0.04 |
| 904677 | Laguna | PHL-ADM2 | 106.84 → 104.0 | 36 → 52 | 0.09 |
| 904678 | Lanao del Norte | PHL-ADM2 | 148.64 → 147.0 | 36 → 56 | 0.52 |
| 904679 | Lanao del Sur | PHL-ADM2 | 248.74 → 225.0 | 36 → 70 | 0.6 |
| 904680 | Leyte | PHL-ADM2 | 333.83 → 325.0 | 36 → 76 | 1.43 |
| 904681 | Maguindanao | PHL-ADM2 | 268.35 → 272.0 | 36 → 92 | 0.08 |
| 904682 | Marinduque | PHL-ADM2 | 48.54 → 53.0 | 36 → 20 | 0.08 |
| 904683 | Masbate | PHL-ADM2 | 172.39 → 188.0 | 36 → 66 | 0.29 |
| 904684 | Misamis Occidental | PHL-ADM2 | 101.97 → 99.0 | 36 → 16 | 0.26 |
| 904685 | Misamis Oriental | PHL-ADM2 | 182.92 → 189.0 | 36 → 52 | 0.08 |
| 904686 | Mountain Province | PHL-ADM2 | 110.43 → 122.0 | 36 → 38 | 0.58 |
| 904687 | NCR, Fourth District | PHL-ADM2 | 10.82 → 12.0 | 36 → 10 | 0.09 |
| 904688 | NCR, Second District | PHL-ADM2 | 12.04 → 12.0 | 36 → 10 | 0.24 |
| 904689 | NCR, Third District | PHL-ADM2 | 7.49 → 7.11 | 36 → 192 | 0.11 |
| 904690 | Negros Occidental | PHL-ADM2 | 406.17 → 435.0 | 36 → 92 | 4.95 |
| 904691 | Negros Oriental | PHL-ADM2 | 304.95 → 287.0 | 36 → 74 | 0.71 |
| 904692 | Northern Samar | PHL-ADM2 | 188.18 → 184.0 | 36 → 56 | 0.39 |
| 904693 | Nueva Ecija | PHL-ADM2 | 294.92 → 307.0 | 36 → 54 | 0.19 |
| 904694 | Nueva Vizcaya | PHL-ADM2 | 212.01 → 234.0 | 36 → 58 | 1.55 |
| 904695 | Occidental Mindoro | PHL-ADM2 | 268.38 → 317.0 | 36 → 66 | 0.24 |
| 904696 | Oriental Mindoro | PHL-ADM2 | 286.69 → 240.0 | 36 → 56 | 0.24 |
| 904697 | Palawan | PHL-ADM2 | 648.87 → 713.0 | 36 → 212 | 4.65 |
| 904698 | Pampanga | PHL-ADM2 | 114.78 → 121.0 | 36 → 40 | 0.09 |
| 904699 | Pangasinan | PHL-ADM2 | 225.78 → 298.0 | 36 → 78 | 0.95 |
| 904700 | Quezon | PHL-ADM2 | 380.36 → 425.0 | 36 → 164 | 0.74 |
| 904701 | Quirino | PHL-ADM2 | 149.81 → 154.0 | 36 → 64 | 0.19 |
| 904702 | Rizal | PHL-ADM2 | 64.07 → 69.0 | 36 → 28 | 0.26 |
| 904703 | Romblon | PHL-ADM2 | 35.68 → 39.0 | 36 → 26 | 0.25 |
| 904704 | Samar | PHL-ADM2 | 259.17 → 292.0 | 36 → 82 | 2.68 |
| 904705 | Sarangani | PHL-ADM2 | 133.67 → 139.0 | 36 → 48 | 0.27 |
| 904706 | Siquijor | PHL-ADM2 | 17.48 → 21.0 | 36 → 14 | 0.54 |
| 904707 | Sorsogon | PHL-ADM2 | 106.93 → 112.0 | 36 → 48 | 0.52 |
| 904708 | South Cotabato | PHL-ADM2 | 237.12 → 226.0 | 36 → 56 | 0.39 |
| 904709 | Southern Leyte | PHL-ADM2 | 73.26 → 84.0 | 36 → 40 | 0.18 |
| 904710 | Sultan Kudarat | PHL-ADM2 | 197.04 → 202.0 | 36 → 58 | 0.84 |
| 904711 | Sulu | PHL-ADM2 | 44.31 → 45.0 | 36 → 20 | 0.14 |
| 904712 | Surigao del Norte | PHL-ADM2 | 64.16 → 66.0 | 36 → 30 | 0.11 |
| 904713 | Surigao del Sur | PHL-ADM2 | 256.42 → 269.0 | 36 → 86 | 1.18 |
| 904714 | Tarlac | PHL-ADM2 | 166.86 → 169.0 | 36 → 40 | 0.27 |
| 904715 | Tawi-Tawi | PHL-ADM2 | 32.19 → 36.0 | 36 → 30 | 0.2 |
| 904716 | Zambales | PHL-ADM2 | 182.02 → 214.0 | 36 → 68 | 0.36 |
| 904717 | Zamboanga del Norte | PHL-ADM2 | 297.1 → 364.0 | 36 → 104 | 1.69 |
| 904718 | Zamboanga del Sur | PHL-ADM2 | 209.74 → 217.0 | 36 → 60 | 1.24 |
| 904719 | Zamboanga Sibugay | PHL-ADM2 | 100.24 → 138.0 | 36 → 64 | 1.85 |

Largest centroid shift is Negros Occidental `904690` at 4.95 px. Catanduanes `904656` is 0.01 px.

## Notches

Puerto Rico `902408` wins the pixels it shares with the two playable USA halves. Those neighbours are notched and kept. Sea pixels stay. No non-USA province is notched.

| id | name | area px | verts |
|----|------|---------|-------|
| 800625 | Puerto Rico West | 311.17 → 10.0 | 19 → 6 |
| 800696 | Puerto Rico East | 340.23 → 93.0 | 24 → 34 |

Both stay above 1 px and carry `gap_usa1_yield` = `notch`. Their mutual adjacency is removed because the rings no longer touch.

## Adjacency

Undirected edges **+8 / −2** (10 total).

Added:

- `904641` Aurora – `904674` Isabela
- `904646` Benguet – `904686` Mountain Province
- `904646` Benguet – `904699` Pangasinan
- `904649` Bukidnon – `904664` Davao del Sur
- `904650` Bulacan – `904700` Quezon
- `904653` Camarines Sur – `904700` Quezon
- `904668` Eastern Samar – `904692` Northern Samar
- `904694` Nueva Vizcaya – `904699` Pangasinan

Removed:

- `800625` Puerto Rico West – `800696` Puerto Rico East
- `904671` Ilocos Norte – `904672` Ilocos Sur

## Area exemption

`gap_nld1_product.area_change_ok` treats a later slice as exempt only when meta has `gap_sia1` or `gap_sia1_yield`. `gap_sia1_product.area_change_ok` exempts only those two keys. Both files are outside this slice's allow-list, so `--apply` writes `gap_sia1_yield` = `exempt:gap_usa1` on each of the 88 re-rings and the two notches. The value marks a GAP-USA-1 area exemption. It is not a claim that Siam notched the province. `gap_sia1` is left unset, so the SIA ring audit does not adopt these provinces. Godot does not read the key.

## Re-run

From a clean `a34d23a7` geometry:

```bash
python3 tools/map_generation/scripts/apply_gap_usa1.py
python3 tools/map_generation/scripts/apply_gap_usa1.py --apply
python3 -m unittest tools.map_generation.tests.test_gap_usa1 -v
```

Dry-run writes nothing. `--apply` splices the new rings, the adjacency edits, and the exemption mark. A second `--apply` on a tree that already has `gap_usa1` matches nothing and only refreshes a missing exemption mark. Evidence (crops, rering table, garrison lists) is under `~/mapusa/evidence/`.

