# GAP-NLD-1

Real admin rings for the 1936 Dutch East Indies placeholders on `world_accurate`.

Measured on base `5d099346`: 99 NLD land placeholders (96 IDN ADM2, Sipaliwini `900317`, Brokopondo `900326`, Curaçao `902301`). After this slice, 98 of those rings carry `gap_nld1`. Land placeholders on the board: 484 to 386. Province ids stay 3596.

## Unknown

| id | name | reason |
|----|------|--------|
| 902301 | Curaçao | gbOpen has no CUW ADM1 or ADM2 (API 404) |

## How the rings were chosen

Source is geoBoundaries gbOpen simplified geometry (IDN ADM2, with ADM1 as fallback; SUR ADM1 for the two Suriname districts). Cache lives in `~/gapnld1/scratch/geoboundaries` and is not committed.

Names are matched after diacritics and a trailing "area" are stripped. Kabupaten and Kota stay in the name unless dropping them is the only unique hit, so Kota Sukabumi does not replace Sukabumi. A multipolygon keeps its main island: the largest part of at least 1 px whose centroid is within max(80 px, 1.5 radii) of the province. A nearer speck is not used.

New rings win overlapping land pixels. Real neighbours are notched and kept. Sea zones keep their pixels. Old placeholder pixels that cover no other province stay, so the slice does not open a hole. Placeholder circles outside this scope stay frozen, including the USA circles, so a later slice still sees a 36/72-vertex ring. A contour stair that left Ogan Komering Ilir `902859` and Banyu Asin `902799` sharing 2 px is shaved in this script; the lower id keeps the pixel.

## Adjacency

Pairs added: `902792`–`902820`, `902792`–`902838`, `902797`–`902851`, `902820`–`902838`.

Pairs removed: `900317`–`900319`, `900317`–`900326`. Those Suriname land rings no longer touch. Sea zone `950133` Labrador Approaches keeps the pixels along that edge.

## Re-run

```bash
python3 tools/map_generation/scripts/apply_gap_nld1.py
python3 tools/map_generation/scripts/apply_gap_nld1.py --apply
python3 -m unittest tools.map_generation.tests.test_gap_nld1 -v
```

Evidence (crops, rering table, garrison lists) is under `~/gapnld1/evidence/`.
