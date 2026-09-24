# FEED-9 — SE England shire land uniformity (Mike bar #1, one theater)

**Status:** FEED-9 theater proof on `world_accurate` (draft; **HOLD merge** for Scott/Play).  
**Tip lineage:** Ligurian FEED-8 KEEP `1388a3ecae54635e57ea0e9a10b801ca895ddca2` (`1388a3e`).  
**Scope:** Mike bar **#1 only** — land provinces more uniform on continents. Theater = SE England **shires** (Oxfordshire / Hampshire corridor). **Do not merge.**

This is a design note + one theater proof. It is **not** a whole-Europe/world remesh, **not** Maginot re-touch, **not** Flanders/Nord re-touch, **not** Greater London grow, **not** Ruhr, **not** seas/oceans, and **not** combat.

Pattern clone: [`MAP_FLANDERS_NORD_LAND_UNIFORMITY.md`](MAP_FLANDERS_NORD_LAND_UNIFORMITY.md) (FEED-7) / [`MAP_MAGINOT_LAND_UNIFORMITY.md`](MAP_MAGINOT_LAND_UNIFORMITY.md) (FEED-2).

## Mike bar (unchanged)

1. **Land provinces more uniform on continents** — this FEED (SE England shire, after Maginot FEED-2 / Flanders FEED-7)
2. Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale
3. Seas/oceans larger (fewer, bigger water cells) — FEED-4 / FEED-8
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape geometry that keeps IDs, or **append-only** new IDs on split.
- FEED-9 **keeps** Oxfordshire parent **`711438`** on the inland historic-core piece.
- Children append Europe-block IDs starting **`711523`** (next after Flanders secondary `711522`).
- **Never reuse** Maginot `711514–711519`, Gibraltar `711520`, or Flanders `711521–711522`.
- Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Maginot combat / Control Labels / duals / Godot bump / seas / Great Lakes / Greater London grow / Ruhr are out of scope.

## Theater window

Label-anchor lon/lat **`-1.5–1.8°E`, `50.5–52.2°N`** — SE England shires (canvas→lonlat via existing Maginot helpers).

**Shire-only:** exclude Greater London urban pinpricks (name contains `London` **or** area < ~8 inside London box `−0.5–0.3°E / 51.3–51.7°N`). Do **not** grow-pass Greater London.

**Excludes** Maginot FEED-2 `6.0–8.8°E / 47.55–49.45°N` and Flanders FEED-7 `2.5–4.8°E / 50.3–51.6°N` land meshes.  
Board: `data/provinces_world_accurate` only. **`world_full` never written / never renumbered.**

## Diagnosis (accurate board, pre-FEED)

Same canvas-shoelace / `theater_land_rows` path as FEED-2 / FEED-7. Tight window, land only, **shire-only n=38** on tip `1388a3e`:

| Band | SE England shire (pre) | Flanders post–FEED-7 (ref) | Maginot post–FEED-2 (ref) |
|------|------------------------|----------------------------|---------------------------|
| n | **38** | 30 | 46 |
| min | 1.45 (Luton UA) | 13.6 | — |
| p25 | 11.38 | 29.5 | — |
| median | **33.35** (~33.4) | 41.1 | ~56 |
| p75 | 88.3 | 80.3 | — |
| max | **231.07** (`711438` Oxfordshire) | 130.2 (Nord South) | ~262 (Moselle keep) |
| max / median | **6.93** | 3.17 | ~4.7 |

Top outlier: **Oxfordshire `711438` ~231.1**. Second giant **Central Hampshire `711449` ~215.2** is **out of scope** for a primary split (second shire giant; only an Oxfordshire-keep secondary is allowed). Bottom cells in-window include UA pinpricks (Luton / Portsmouth / Southampton) — not grown. Greater London boroughs (Camden and City of London `711414` etc.) are excluded from the shire set and are **not** a grow-pass.

## Keep rule (inland shire)

Flanders FEED-7 keeps the piece closer to English Channel sea `950001`. Maginot FEED-2 default keeps the piece whose centroid is closer to the **original parent centroid**.

Oxfordshire is **inland**. There is no Channel-sea relationship to preserve. FEED-9 therefore uses Maginot's default:

**`original_centroid`** — parent ID `711438` stays on the piece whose centroid is closer to the pre-split Oxfordshire centroid (historic name-bearing shire core). The child is the complementary axis-balanced piece. The same original centroid is reused if a secondary keep-split fires, so the parent name stays on the core through both cuts.

## What FEED-9 writes

Pure product: `tools/map_generation/lib/se_england_shire_land_uniformity_product.py`  
Write: `tools/map_generation/scripts/apply_se_england_shire_land_uniformity.py`

1. **Split** giant Oxfordshire `711438` (axis-balanced line cut). Parent ID stays on the historic-core piece (`original_centroid` keep). First child is append-only **`711523`**.

2. **Optional one secondary split** of the remaining in-window Oxfordshire keep if post-primary max/median is still **> ~5**. Second child is append-only **`711524`**. Stop at Maginot-class (max/median ≤ ~5, max ≤ ~290) or document a Hampshire-honest residual. **No Hampshire split. No Greater London grow.**

| Parent ID | Name (keep) | Child ID | Child name | Role |
|-----------|-------------|----------|------------|------|
| 711438 | Oxfordshire | 711523 | Oxfordshire North | Primary complementary piece |
| 711438 | Oxfordshire | 711524 | Oxfordshire East | Secondary split of remaining keep (post-primary max/median was **5.70**) |

`711438` remains the historic-core Oxfordshire piece (~58.2; keep lon/lat ≈ −1.383°E / 51.572°N).

3. Theater adjacency patched for the new children. Ownership / hierarchy / state / British Isles region / terrain / city / economy / resources **cloned** from the parent (append-only keys). **No Greater London grow. No Maginot / Flanders mesh writes.**

Board scale: **3534 + 2 = 3536**. `world_full` is not written.

## Theater metrics (after)

Same tight window, **shire-only** land (includes new child cells whose centroids stay in-window). Greater London pinpricks stay excluded. Secondary of the Oxfordshire keep was required (post-primary max/median **5.70** with Hampshire still the in-window max).

| Band | Pre | Post (measured) |
|------|-----|-----------------|
| n | 38 | **40** |
| max | 231.1 (Oxfordshire `711438`) | **215.2** (Central Hampshire `711449`; keep `711438` ~58.2) |
| median | 33.4 | **48.0** |
| max / median | 6.93 | **4.48** |
| max / min | 159.0 | 148.1 |

Maginot-class target met: max/median **4.48 ≤ ~5** and max **215.2 ≤ 290**. Honest residual: Central Hampshire `711449` remains the theater max and is **unsplit** (second shire giant; out of scope). Secondary only cut the Oxfordshire keep.

## Later FEEDs (not this PR)

- Maginot / Flanders / Gibraltar / Alboran / Ligurian / HK / Windward / Great Lakes stay as shipped.
- Optional later land pass: Central Hampshire `711449` (second shire giant); Greater London grow is **not** this bar. Do not remesh whole Europe here.

## Gates

```bash
python3 -m unittest tools.map_generation.tests.test_se_england_shire_land_uniformity_product -v
```

`map_accuracy_qc` on the written board: hard_ok, matched **3536**, orphans 0, NE land hit **0.9853**. Maginot / Flanders / Ligurian / Gibraltar / Alboran / HK / Windward / Great Lakes product tests still PASS. Fill%·TOE + pale-map residual marker in `MapRenderer.gd` stay untouched. `world_full` git-clean (no 711523/711524 IDs written).

`--quick` living-unit wiring fails that already exist on tip `1388a3e` are OK — this FEED does not touch those GD files.

## Play smoke (human — not this CA)

Home Europe / SE England operational zoom: Oxfordshire should no longer read as a single giant hole vs neighboring shires. Pick parent `711438` + child `711523` (and `711524` if written) — names and ENG ownership stay. Esc HARD PASS on the tip. Dig2 / G / Maginot combat / Taken / JOINING / Fill%·TOE not in this FEED.

## Non-goals

Taken/JOINING · CombatResolver · Maginot re-touch · Flanders re-touch · Ligurian re-touch · Dig2/G · Greater London grow · Ruhr · Central Hampshire split · dual-CA · Godot bump · `world_full` renumber · pale-map residual · Fill%·TOE · merge leftover drafts · ping Mike · bounce Play
