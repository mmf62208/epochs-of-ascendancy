# Province sizing bar (Mike) — FEED-1 Great Lakes

**Status:** FEED-1 theater proof on `world_accurate` (draft; HOLD merge for Scott/Play).  
**Tip lineage:** Maginot state-label KEEP `cf568664e59d621d2291295213b9211c726942d8`.  
**Scope:** Mike bar **#4 only** — large lakes get their own water provinces. Theater = North American Great Lakes.

This is a design note + one theater proof. It is **not** a whole-world remesh, **not** Maginot land uniformity (FEED-2), **not** seas/oceans coarsening, and **not** a Gibraltar/HK chokepoint carve.

## Mike bar (unchanged)

1. Land provinces more uniform on continents
2. Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale
3. Seas/oceans larger (fewer, bigger water cells) — later FEED
4. **Large lakes get their own water provinces** — this FEED

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer append-only new water IDs **or** geometry/adjacency edits that keep existing IDs.
- FEED-1 **reuses** the already-allocated accurate-board lake IDs `950333–950337` (Superior, Michigan, Huron, Erie, Ontario). Moving rings is not a renumber and does not invent a second set of Great Lakes names.
- Theater land IDs (US `800000+` / RoW Canada `900000+` in the basin window) stay. Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Maginot combat / Control Labels / duals / Godot bump are out of scope.

## Diagnosis (accurate board, pre-FEED)

Named lake rows already existed (`domain=lake`, terrain sea, unowned, region 10 World Oceans):

| ID | Name |
|----|------|
| 950333 | Lake Superior |
| 950334 | Lake Michigan |
| 950335 | Lake Huron |
| 950336 | Lake Erie |
| 950337 | Lake Ontario |

Their geometry was leftover `expand_world_provinces` seed cells (half≈40, NE-snapped) sitting over **Quebec / James Bay** (~50–53°N), not the basins. Adjacency was KNN among those dummy cells plus a few Québec land IDs — not Michigan / Wisconsin / Ontario coasts. Sample points in the real basins were mostly **void** (no water cell); a few US hulls nibbled edges (Minnesota North, Michigan North, New York West). Underlay rivers painted lakes; the play mesh did not own them.

`world_full` already has the same five names on scaffold IDs `40460–40464`. This FEED does **not** touch `world_full`.

## What FEED-1 writes

Pure product: `tools/map_generation/lib/great_lakes_water_province_product.py`  
Write: `tools/map_generation/scripts/apply_great_lakes_water_provinces.py`

1. Replace the five lake rings with simplified WGS84 basin outlines projected on the accurate canvas (`WORLD_BBOX` / `8192×4096`).
2. Dent land vertices that fall inside those rings onto the shore (IDs unchanged).
3. Patch theater adjacency only: hydrologic lake–lake graph (Superior–Michigan/Huron, Michigan–Huron, Huron–Erie, Erie–Ontario) plus coastal land that touches a basin. Stale Quebec-KNN lake edges dropped.
4. QC: centroids in-basin, min bbox area, design centroid is water-not-land, each lake has ≥1 land neighbor.

Board scale stays **~3520**. No new IDs. Caspian / Victoria leftover seed cells are unchanged (not this theater).

## Later FEEDs (not this PR)

- **FEED-2:** Maginot / Europe land-area uniformity (split/reshape; no retire without Scott).
- **FEED-3+:** seas/oceans coarsen (bar #3); island-scale chokepoints (bar #2) only if still missing.

## Play smoke (human)

Pick Superior / Michigan / Huron / Erie / Ontario interiors — inspector should read those water names, not a US/Canada land absorb and not empty void. Esc HARD PASS on the tip. Dig2 / G / Maginot combat not in this FEED.
