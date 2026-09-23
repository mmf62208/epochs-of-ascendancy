# FEED-7 — Flanders / Nord land uniformity (Mike bar #1, outside Maginot)

**Status:** FEED-7 theater proof on `world_accurate` (draft; **HOLD merge** for Scott/Play).  
**Tip lineage:** Fill%·TOE KEEP `8cae5f903dbcc5dce4cbbdfff2cbb3826636753b` (`8cae5f9`).  
**Scope:** Mike bar **#1 only** — land provinces more uniform on continents. Theater = Nord / Flanders / western BE (Channel approach west of Maginot).

This is a design note + one theater proof. It is **not** a whole-Europe/world remesh, **not** Maginot re-touch, **not** Ruhr/NRW grow, **not** seas/oceans, **not** Gibraltar/HK/Windward/Great Lakes redo, and **not** combat.

## Mike bar (unchanged)

1. **Land provinces more uniform on continents** — this FEED (outside Maginot)
2. Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale
3. Seas/oceans larger (fewer, bigger water cells)
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape geometry that keeps IDs, or **append-only** new IDs on split.
- FEED-7 **keeps** Nord parent **`710734`** on the coastal / Channel piece.
- Children append Europe-block IDs starting **`711521`** (next after Gibraltar `711520`).
- **Never reuse** Maginot `711514–711519` or Gibraltar `711520`.
- Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Maginot combat / Control Labels / duals / Godot bump / seas / Great Lakes / Ruhr/NRW are out of scope.

## Theater window

Label-anchor lon/lat **`2.5–4.8°E`, `50.3–51.6°N`** — Nord / Flanders / western BE arrondissements.

**Excludes** Maginot FEED-2 `6.0–8.8°E / 47.55–49.45°N` and Maginot Rhine/Pfalz residuals.  
Board: `data/provinces_world_accurate` only. **`world_full` never written / never renumbered.**

## Diagnosis (accurate board, pre-FEED)

Same canvas-shoelace / `theater_land_rows` path as FEED-2. Tight window, land only, **n=29** on tip `8cae5f9`:

| Band | Flanders/Nord (pre) | Maginot post–FEED-2 (ref) |
|------|---------------------|---------------------------|
| n | **29** | 46 |
| min | 13.6 (Bruxelles-Capitale) | — |
| p25 | 28.5 | — |
| median | **39.5** | ~56 |
| p75 | 60.2 | — |
| max | **497.2** (`710734` Nord, FR) | ~262 (Moselle keep) |
| max / median | **12.6** | ~4.7 |

Top outlier: **Nord `710734` ~497** (same giant-département class as pre-FEED Moselle ~511). Bottom cells in-window are BE arrondissements (~14–27) — not Maginot Stadtkreise. Neighboring FR giants **Pas-de-Calais `710735`**, **Somme `710738`**, **Aisne `710736`** sit **outside** this window (do not split). Ruhr/NRW is already max/median ~3.2 — **no grow-pass**.

## What FEED-7 writes

Pure product: `tools/map_generation/lib/flanders_nord_land_uniformity_product.py`  
Write: `tools/map_generation/scripts/apply_flanders_nord_land_uniformity.py`

1. **Split** giant Nord `710734` (axis-balanced line cut). Parent ID stays on the piece that preserves the coastal / Channel relationship (closer to English Channel sea `950001`). First child is append-only **`711521`**.

2. **Optional one secondary split** of the remaining in-window Nord keep if post-Nord max/median is still **> ~5**. Second child is append-only **`711522`**. Stop at Maginot-class (max/median ≤ ~5, max ≤ ~290) or document a Moselle-honest residual.

| Parent ID | Name (keep) | Child ID | Child name | Role |
|-----------|-------------|----------|------------|------|
| 710734 | Nord | 711521 | Nord East | Primary inland / south-east piece |
| 710734 | Nord | 711522 | Nord South | Secondary split of coastal keep (only if post-Nord max/median > ~5) |

`710734` remains the Channel-facing Nord piece.

3. Theater adjacency patched for the new children. Ownership / hierarchy / state / France region / terrain / city / economy / resources **cloned** from the parent (append-only keys). **No Ruhr grow.**

Board scale stays **~3520** (3532 + 2 = **3534**). `world_full` is not written.

## Theater metrics (after)

Same tight window, land only (includes new child cells whose centroids stay in-window). Nord East `711521` centroid is **50.257°N** (just south of the 50.3° window) so it does not count in-window; Nord keep `710734` and Nord South `711522` do.

| Band | Pre | Post (measured) |
|------|-----|-----------------|
| n | 29 | **30** |
| max | 497.2 | **130.2** (Nord South `711522`; keep `710734` ~125.5) |
| median | 39.5 | **41.1** |
| max / median | 12.6 | **3.17** |
| max / min | 36.6 | 9.6 |

Maginot-class target met: max/median **3.17 ≤ ~5** and max **130.2 ≤ 290**. Secondary split of the coastal Nord keep was required (post-Nord max/median was **6.48** with keep ~256 still in-window). No Moselle-honest residual.

## Later FEEDs (not this PR)

- Maginot / Gibraltar / Alboran / HK / Windward / Great Lakes stay as shipped.
- Optional later land pass: Pas-de-Calais / Somme / Aisne (outside this window); Ruhr/NRW only if Scott picks that corridor. Do not remesh whole Europe here.

## Play smoke (human — not this CA)

Home Europe / Flanders–Nord operational zoom: Nord should no longer read as a single giant hole vs neighboring BE arrondissements. Pick parent `710734` + child `711521` (and `711522` if written) — names and FRA ownership stay. Esc HARD PASS on the tip. Dig2 / G / Maginot combat / Taken / JOINING not in this FEED.

## Non-goals

Taken/JOINING · CombatResolver · Maginot re-touch · Dig2/G · Ruhr/NRW · dual-CA · Godot bump · `world_full` renumber · merge leftover draft PR #7 · Ink 175 · ping Mike · bounce Play
