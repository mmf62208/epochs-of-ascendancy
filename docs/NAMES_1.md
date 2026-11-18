# NAMES-1 — 1936 board province names

Land names on `data/provinces_world_accurate/provinces_base.json` (id &lt; 950000).
Only the `name` string changes. Ids and every other field stay byte-for-byte
with base `5d099346`. Sea zones (id ≥ 950000) are not renamed.

The pure rules live in `tools/map_generation/lib/names1_product.py`.
`tools/map_generation/scripts/apply_names1.py` is a dry-run unless `--apply`
is passed. Admin polygons are read from `~/names1/scratch/geoboundaries`
(geoBoundaries ADM1, plus Philippines and Qatar ADM2). That scratch is not
committed. Evidence is `~/names1/evidence/rename_table.csv` (1120 rows) and
`~/names1/evidence/rename_sample_200.csv` (200-row sample, seed 19360101).

## Counts

Ship measured the base file as 366 `<TAG> <Direction>`, 630 names ending in
` area`, 128 non-Latin, and 4 tag oddities. This pass measured the same file
with the classifiers in the lib:

| Bucket | Base (this pass) | After | Notes |
|---|---:|---:|---|
| `<TAG> <Direction>` | 366 | 23 | The 23 that remain are pinned (22 `CHN` cardinals + `903492` `RUS West`). |
| trailing ` area` | 633 | 0 | Ship's 630 omits 3 CJK names that also end in ` area`. |
| non-Latin letters | 119 | 0 | Greek, Cyrillic, CJK. Ship's 128 also counts Latin names that are not pure ASCII. |
| oddities | 4 | 0 | `ATA region`, three `NCR, … District`. |
| renamed | | 1120 | |
| pinned ids | | 49 | |
| UNKNOWN | | 0 | |

Seven land names use only typographic punctuation on otherwise Latin text
(`L'Aquila`, `Val-d'Oise`, `Reggio nell'Emilia`, `'s-Gravenhage`, two Verviers
em dashes, `North and West Norfolk` with a no-break space). They stay.
Ordinary Latin diacritics (`München`, `Côte-d'Or`, `Cádiz`) stay. `unidecode`
is not used. CJK without an English exonym would be left unchanged; the four
Taiwan townships on this board have Hanyu Pinyin exonyms (`通霄鎮` Tongxiao,
`泰安鄉` Tai'an, `金湖鎮` Jinhu, `芳苑鄉` Fangyuan).

## Rules

- ` area` drops the suffix (`Gayo Lues area` → `Gayo Lues`). A bare number
  (`78 area`) is not a place: the name comes from the geoBoundaries ADM1
  that contains the centroid (`Al Shamal`, `Doha` municipalities). Qatar ADM2
  zones are themselves numbers, so they are ignored.
- Non-Latin names use an English exonym when one is on the closed table
  (Bulgarian oblasts, Greek NUTS, Macedonian regions, Serbian districts,
  `Црна Гора` → Montenegro, the four townships). Other Cyrillic uses BGN/PCGN
  (Bulgarian х→h, щ→sht, ъ→a). Other Greek uses the same letter table.
- `<TAG> <Direction>` takes the geoBoundaries ADM1 English name at the
  province centroid (vertex-mean of the canvas ring, equirectangular
  `WORLD_BBOX=(-180,-56,180,83)` / canvas 8192×4096). Berlin `710300` is
  checked before any write (about 13.4°E, 52.5°N). The name tag is not
  trusted: `BRA South` `902989` sits in Uruguay and becomes `Cerro Largo`.
- A modern ADM1 that is a well-known 1936 region is replaced before the
  name is stored. India and Pakistan: United Provinces, Central Provinces,
  Rajputana, Orissa, Bengal (also every Bangladesh hit), Madras, Hyderabad,
  Mysore, Travancore, Bombay, Punjab, Bihar, Sind, North-West Frontier,
  Baluchistan, Gilgit, Kashmir (including Ladakh). Arunachal Pradesh becomes
  North-East Frontier. Manchukuo boxes, applied when the ADM1 name is
  Liaoning, Jilin, Heilongjiang, or a Hebei / Inner Mongolia point inside
  116–135°E, 40–53.5°N: Jinzhou, Andong, Fengtian, Jiandao, Binjiang, Jilin,
  Heihe, Sanjiang, Longjiang, Rehe, Xing'an. The 22 pinned `CHN` cardinal
  provinces are the ones that cover that country on this board, so those
  stored names stay `CHN North` / `East` / `South` / `West`. The Fengtian
  path is covered by `test_names1` with a synthetic Liaoning hit.
- `902134` `ATA region` → `Graham Land`. The three Metro Manila districts
  are 1936 Rizal municipalities, not the congressional labels and not
  Quezon City (chartered 1939): `904687` Parañaque, `904688` Marikina,
  `904689` Novaliches.
- Duplicate names within one 1936 owner get a compass suffix (`Bombay` /
  `Bombay South`, `Alaska West` / `Alaska West East`). The suffix never
  contains `#id`. A group whose members are all pinned is left alone (the
  repeated `CHN West` blobs). A pinned member, otherwise the lowest id,
  keeps the bare name.

## Pinned

`PINNED_NAME_IDS` records the file and line that quote the stored name.
Renaming any of these fails a test or the `RUS West` display contract.

- `903492` `RUS West` — `scripts/map/MapPolishFormatters.gd:663` rewrites
  that pid and that exact string to `Western Russia`. `903493` is the other
  `RUS West` and is renamed, so the string match does not label it too.
- `902487`–`902646` the 22 `CHN` cardinal ids in
  `tools/map_generation/tests/test_nation_tags1.py` lines 183–204.
- Land ids whose tests assert the exact name: Nord `710734`, Pas-de-Calais
  `710735`, Baden-Baden `710173`, Bas-Rhin `710739`, Cádiz `710671`, Ceuta
  `710679`, Martinique `710804`, Genova `710870`, Roma `710963`, Oxfordshire
  `711438`, Central Hampshire `711449`, Gibraltar `711520`, District of
  Columbia `800792`, Trinidad `902398`, Yuen Long `902486`, Hong Kong
  `905844`, Barbados `905845`, Saint Lucia `905846`, Saint Vincent `905847`,
  Grenada `905848`, and the kept China cities Chongqing `906013`, Guangzhou
  `906014`, Chengdu `906015`, Fuzhou `906016`, Taiyuan `906018`, Guiyang
  `906019`.

`test_nation_tags1` also requires the first province with each GAP-CHINA-2 /
Ukraine-block name to be the 906100+ id. A lower id that would take that
exact string gets a ` District` suffix instead.

## Tests

`python3 -m unittest tools.map_generation.tests.test_names1` on the base
file (before `--apply`):

```
AssertionError: 343 != 0 : tag-dir left 343 e.g. [(902660, 'IND West'), (902663, 'IND North'), (902669, 'IND West')]
AssertionError: 633 != 0 : area left 633 e.g. [(902785, 'Gayo Lues area'), (902786, 'Aceh Selatan area'), (902787, 'Nias Utara area')]
AssertionError: 119 != 0 : nonlatin left 119 e.g. [(710091, 'Видин'), (710092, 'Монтана'), (710093, 'Враца')]
```

On the tip, the same module: `Ran 7 tests` / `OK`. (a) allows pinned and
UNKNOWN tag-direction names. (e) allows a duplicate only when every id in
the group is pinned. (d) compares every non-name field to
`git show 5d099346:data/provinces_world_accurate/provinces_base.json`.

The test is not wired into `tools/eoa_full_test_gates.sh`.
