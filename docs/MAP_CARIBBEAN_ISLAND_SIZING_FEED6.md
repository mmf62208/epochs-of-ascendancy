# FEED-6 — Caribbean ordinary-island sizing (Mike bar #2 islands)

**Status:** FEED-6 theater proof on `world_accurate` (draft; HOLD merge for Scott/Play).  
**Tip lineage:** Hong Kong FEED-5 KEEP `8bd654c206a20833ce9d446061f93ed964d55d88`.  
**Scope:** Mike bar **#2 ordinary islands may be smaller** — one Caribbean strip only. Theater = **Windward Lesser Antilles** (Barbados / Saint Lucia / Saint Vincent / Grenada).

This is a design note + one theater proof. It is **not** a whole-Caribbean remesh, **not** Pacific / Japan, **not** Gibraltar / Hong Kong / Alboran / Maginot / Great Lakes rework, and **not** combat.

## Mike bar (unchanged)

1. Land provinces more uniform on continents — FEED-2
2. **Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale** — FEED-3 Gibraltar + FEED-5 Hong Kong; **this FEED is the ordinary-island half** (Caribbean strip)
3. Seas/oceans larger (fewer, bigger water cells) — FEED-4 (Alboran)
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape that keeps IDs, or **append-only** new land IDs.
- FEED-6 **keeps** Martinique `710804`, Guadeloupe `710803`, Dominica `902406`, Eastern Tobago `902405`, Trinidad `902398`, Saint Croix `902407`, and sea `950134` (Mid-Atlantic Waters).
- New land IDs are RoW-block **`905845–905848`** (next after Hong Kong `905844`). No merge-retire.
- Gibraltar `711520`, Hong Kong `905844`, Alboran `950128`, Maginot land, Great Lakes, Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Control Labels / duals / Godot bump / seas coarsening / whole-Caribbean remesh are out of scope.

## Diagnosis (accurate board, pre-FEED)

The Lesser Antilles / nearby strip already had **some** small dedicated island lands, clearly smaller than nearby mainland coasts. A short Windward chain between Martinique and Trinidad was **void** (not absorbed into a giant coastal blob — no land cell at all).

Existing dedicated islands in the window (kept):

| ID | Name | Canvas area | Role |
|----|------|-------------|------|
| 902405 | Eastern Tobago | **8.37** | dedicated island |
| 902302 | Aruba | **9.46** | dedicated island (ABC, nearby) |
| 902406 | Saint Andrew (Dominica) | **10.83** | dedicated island |
| 902407 | Saint Croix | **12.19** | dedicated island |
| 902301 | Curaçao | **24.12** | dedicated island (ABC, nearby) |
| 710804 | Martinique | **65.22** | dedicated French NUTS island |
| 710803 | Guadeloupe | **82.20** | dedicated French NUTS island |
| 902398 | Trinidad and Tobago South | **327.36** | dedicated island (larger) |

Nearby mainland coasts (kept):

| ID | Name | Canvas area |
|----|------|-------------|
| 900332 | Guyana North | **2123** |
| 800039 | Florida South | **5344** |
| 903797 | VEN East | **13170** |
| 903792 | VEN North | **16275** |

VOID samples (no land, no sea pip) before this FEED: Barbados Bridgetown, Saint Lucia Castries, Saint Vincent Kingstown, Grenada St George. Trinidad Port of Spain sat in sea `950134`, not a land absorb of those four.

## What FEED-6 writes

Pure product: `tools/map_generation/lib/caribbean_island_sizing_feed6_product.py`  
Write: `tools/map_generation/scripts/apply_caribbean_island_sizing_feed6.py`

1. **Append** land `905845` **Barbados**, `905846` **Saint Lucia**, `905847` **Saint Vincent**, `905848` **Grenada** — Malta/St Croix-scale hex rings (`island_class=island`), owner **ENG** (British Windwards / Barbados, 1936).
2. **Keep** Martinique / Guadeloupe / Dominica / Tobago / Trinidad / St Croix geometry and IDs (no clip). No seas remesh.
3. **Adjacency** (theater only): Martinique ↔ Saint Lucia ↔ Saint Vincent ↔ Grenada ↔ Trinidad; Saint Vincent ↔ Barbados; Grenada + Barbados ↔ `950134` Mid-Atlantic Waters.
4. Hierarchy / region 8 / Trinidad and Tobago state `414` (429 unique states reused, not +4) / city / economy / terrain filled for the new IDs only.

Board scale stays **~3520** (3528 + 4 = **3532**). Seas stay **340**. `world_full` is not written.

## Before / after (theater)

| Metric | Before | After |
|--------|--------|-------|
| Dedicated Windward cells (BB / SLU / SVG / GND) | **0** (VOID) | **4** (`905845–905848`) |
| Windward island canvas areas | — | Barbados **14.02** · Saint Lucia **15.04** · Saint Vincent **13.32** · Grenada **12.33** |
| Existing dedicated strip cells in window | **15** | **19** (append-only) |
| Martinique / Guadeloupe / Tobago / Dominica areas | 65.22 / 82.20 / 8.37 / 10.83 | unchanged |
| Nearby mainland (Guyana North / VEN North) | 2123 / 16275 | unchanged |
| Board n | **3528** | **3532** |
| Seas | 340 | 340 |
| Gibraltar `711520` / Hong Kong `905844` / Alboran `950128` / Maginot edge | kept | kept |

## Later FEEDs (not this PR)

- Other Caribbean / Pacific / Japan island strips — only if still missing after a later Scott GO.
- Do not remesh whole Caribbean, Greater Antilles, or mainland SA here.

## Gates (machine)

Slice green on this PR:

```bash
python3 -m unittest tools.map_generation.tests.test_caribbean_island_sizing_feed6_product -v
```

`map_accuracy_qc` on the written board: hard_ok, matched **3532**, orphans 0, NE land hit **0.9853**. Maginot FEED-2 + Gibraltar FEED-3 + Alboran FEED-4 + Hong Kong FEED-5 product tests still PASS. `world_accurate` hierarchy/ownership/choke tests PASS.

`--quick` living-unit wiring fails are **tip-pre-existing** on `8bd654c206a20833ce9d446061f93ed964d55d88`. This FEED does not touch those GD files.

## Play smoke (human)

Caribbean / Lesser Antilles operational zoom: pick Barbados, Castries, Kingstown, or St George — inspector should read the dedicated island land (`905845–905848`), not void and not Mid-Atlantic Waters. Martinique / Trinidad / Tobago picks unchanged. Esc HARD PASS on the tip. Dig2 / G / Maginot combat not in this FEED.
