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

## FIX r1 (map-select performance)

Ship box gate: 164 real rings (98 NLD + 66 SIA) slowed HeadlessOrdersPerf1Test case b (warm add_child → first refresh) and case d (`_on_map_province_selected`). OP fence (17 Nov 2026): MapRenderer map-select / warm-refresh only.

`MapRenderer` now builds an AABB + cell index at province-create time (`_pick_cache_add` from `_create_province_node`, rebuilt by `gap_nld1_rebuild_pick_index` for the standalone harness). Spatial hover / click (`_resolve_map_pick_pid`, `_resolve_hex_pick_pid`) query that index instead of walking every ring. The draw loop is untouched.

Standalone (not on `--quick`):

```bash
XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessGapNld1PerfTest.gd
```

The test picks ≥2000 fixed world points (global grid, dense Europe / NLD / SIA, borders, sea). Index picks must match the same-run brute-force walk. Index wall time must be ≤ brute + 10%.

Measured this sitting (Godot 4.7.1 via `tools/run_godot.sh`, fresh `XDG_DATA_HOME`):

- Identity: **2205** points, **0** mismatches. Index **16.87 ms** vs brute **6416.63 ms** (cap brute+10% = 7058.30 ms). MapManager pick on the same points: **7567.73 ms**.
- HeadlessOrdersPerf1Test case **b** (warm add_child→first refresh): **147 / 126 / 129 ms** (every pass ≤450). `--quick` also **133 ms**.
- Case **d** (`_on_map_province_selected`): **137 / 169 / 156 ms**. `--quick` also **185 ms**.
- `--quick`: **493 s**, ALL PASSED. NE **0.9871 (3213/3255)**. Garrison **576**, ENG **188**. Seed `20fe9063`. Identity `d22b87cf` / twin `7abd07c2` / `5fda7a57`. Mutants `4a9c21e5` / `43e14082`. 0 SCRIPT ERROR.

NE land-hit pin in this PR: `tools/eoa_full_test_gates.sh` `map_qc --min-land-hit` **0.9871** (3213/3255). Seed `20fe9063de285f19d4f9b8a105abfd31` unchanged. MERGE HOLD.
