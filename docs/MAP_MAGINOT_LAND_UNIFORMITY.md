# FEED-2 — Maginot corridor land uniformity (Mike bar #1)

**Status:** FEED-2 theater proof on `world_accurate` (draft; HOLD merge for Scott/Play).  
**Tip lineage:** Great Lakes KEEP `3b2b7dc65dd49aacab5e923843c56cbba57c7d57`.  
**Scope:** Mike bar **#1 only** — land provinces more uniform on continents. Theater = Maginot corridor (Alsace / Lorraine / Rhineland / Baden family + immediate neighbors).

This is a design note + one theater proof. It is **not** a whole-Europe/world remesh, **not** seas/oceans coarsening, **not** Gibraltar/HK, **not** a Great Lakes rework, and **not** combat.

## Mike bar (unchanged)

1. **Land provinces more uniform on continents** — this FEED
2. Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale
3. Seas/oceans larger (fewer, bigger water cells) — later FEED
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape geometry that keeps IDs, or **append-only** new IDs on split.
- FEED-2 **keeps** every pre-existing Maginot land ID, including the combat edge `710173` (Baden-Baden) ↔ `710739` (Bas-Rhin).
- French département splits append Europe-block IDs **`711514–711519`** (next after existing NUTS max `711513`). No merge-retire.
- Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Maginot combat / Control Labels / duals / Godot bump / seas / Great Lakes are out of scope.

## Diagnosis (accurate board, pre-FEED)

State *names* Alsace / Lorraine / Rhineland / Baden are geographically scrambled (NUTS IDs live in the wrong named buckets). Theater membership is therefore **geographic**, not those state labels.

Tight operational window (label-anchor lon/lat **6.0–8.8°E, 47.55–49.45°N**), land only, **n=44** on tip `3b2b7dc`:

| Band | Canvas shoelace area |
|------|----------------------|
| min | **1.5** (Basel-Stadt; Swiss residual) |
| p25 | 22.2 |
| median | **57.3** (German Landkreis scale) |
| p75 | 86.4 |
| max | **511.3** (Moselle) |
| max / median | **8.9** |
| max / min | 337 |

Outliers in this corridor:

| Kind | Examples | Area |
|------|----------|------|
| Giant FR départements | Moselle, Vosges, Haute-Saône, Meurthe-et-Moselle, Bas-Rhin, Haut-Rhin | 286–511 |
| Typical DE Landkreis | Rastatt, Ortenaukreis, Emmendingen, … | ~35–155 |
| Tiny DE Stadtkreise on the front | Baden-Baden `710173` (9.6), Freiburg (6.9), Pirmasens (5.4) | 5–12 |

At operational zoom the French cells read as giant holes next to Rhine pinpricks. City-kreise are **not** treated as island-scale chokepoints (bar #2).

## What FEED-2 writes

Pure product: `tools/map_generation/lib/maginot_land_uniformity_product.py`  
Write: `tools/map_generation/scripts/apply_maginot_land_uniformity.py`

1. **Split** the six giant French cells (axis-balanced line cut). Parent ID stays on the piece that preserves the Rhine/combat relationship; child is append-only.

| Parent ID | Name | Child ID | Child name |
|-----------|------|----------|------------|
| 710747 | Moselle | 711514 | Moselle West |
| 710748 | Vosges | 711515 | Vosges East |
| 710727 | Haute-Saône | 711516 | Haute-Saône East |
| 710745 | Meurthe-et-Moselle | 711517 | Meurthe-et-Moselle South |
| 710739 | Bas-Rhin | 711518 | Bas-Rhin South |
| 710740 | Haut-Rhin | 711519 | Haut-Rhin North |

`710739` remains the Rhine-facing Bas-Rhin piece adjacent to `710173`.

2. **Grow** three Maginot-front German Stadtkreise into their **own-country** Landkreis (no FRA bite; Rhine border not moved):

| Tiny ID | Name | Donor | Before → after (area) |
|---------|------|-------|------------------------|
| 710173 | Baden-Baden, Stadtkreis | Rastatt `710176` | 9.6 → ~48 |
| 710185 | Freiburg im Breisgau, Stadtkreis | Breisgau-Hochschwarzwald `710186` | 6.9 → ~53 |
| 710476 | Pirmasens, Kreisfreie Stadt | Südwestpfalz `710489` | 5.4 → ~43 |

3. Theater adjacency patched for the six new children. Ownership / hierarchy / state / France region / terrain / city / economy / resources **cloned** from the parent (append-only keys).

Board scale stays **~3520** (3520 + 6 = **3526**). `world_full` is not written.

## Theater metrics (after)

Same tight window, land only (includes the new child cells whose centroids stay in-window):

| Band | Pre | Post (target) |
|------|-----|----------------|
| n | 44 | ~46 |
| max | 511.3 | **≤ 290** (measured ~262, Moselle keep) |
| median | 57.3 | ~56 |
| max / median | 8.9 | **~4.7** |
| Front Stadtkreise (3 grown) | 5–10 | **≥ 20** (measured ~43–53) |

Residual tinies **not** in this FEED (documented, not a fail): Basel-Stadt, Speyer, Zweibrücken, Pforzheim, Landau, Heidelberg, other off-front Palatinate city-kreise. A later Europe pass can grow those; this proof is Maginot family + immediate front.

## Later FEEDs (not this PR)

- **FEED-3:** Gibraltar island-scale land key (bar #2) — see [`MAP_GIBRALTAR_ISLAND_LAND.md`](MAP_GIBRALTAR_ISLAND_LAND.md).
- **FEED-4:** seas/oceans coarsen (bar #3) — see [`MAP_SEAS_COARSEN_FEED4.md`](MAP_SEAS_COARSEN_FEED4.md) (Alboran basin; HOLD merge).
- **Later:** Hong Kong / other keys only if still missing.
- Optional later land pass: remaining Rhine/Pfalz Stadtkreise; do not remesh whole Europe here.

## Play smoke (human)

Home Europe / Maginot operational zoom: Moselle / Vosges / Bas-Rhin / Haut-Rhin should no longer dominate as single giant départements; Baden-Baden / Freiburg / Pirmasens should not read as specks. Pick `710173` / `710739` — names and GER↔FRA edge stay. Esc HARD PASS on the tip. Dig2 / G / Maginot combat not in this FEED.
