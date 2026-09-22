# FEED-5 — Hong Kong island-scale land key (Mike bar #2)

**Status:** FEED-5 theater proof on `world_accurate` (draft; HOLD merge for Scott/Play).  
**Tip lineage:** Alboran FEED-4 KEEP `ce8d7c2021a5bf01eeb841edfd9f379ad82847b5`.  
**Scope:** Mike bar **#2 only** — key chokepoints treated like island-scale provinces. Theater = **Hong Kong rock/island only**.

This is a design note + one theater proof. It is **not** other keys, **not** seas/oceans coarsening, **not** Gibraltar / Alboran / Maginot / Great Lakes rework, and **not** combat.

## Mike bar (unchanged)

1. Land provinces more uniform on continents — FEED-2
2. **Islands may be smaller; key chokepoints (Gibraltar, HK, …) island-scale** — this FEED (Hong Kong only; Gibraltar already FEED-3)
3. Seas/oceans larger (fewer, bigger water cells) — FEED-4 (Alboran)
4. Large lakes get their own water provinces — FEED-1

## ID stability (HARD)

- Never renumber `world_full` or play-board province IDs.
- Prefer reshape geometry that keeps IDs, or **append-only** new IDs on carve.
- FEED-5 **keeps** Yuen Long `902486`, CHN South `902598` / `902633`, and sea `950011` (South China Sea Zone).
- New land ID is RoW/Asia-block **`905844`** (next after max RoW `905843`). Pattern matches Gibraltar Europe append `711520` after Maginot `711519`. No merge-retire.
- Gibraltar `711520`, Alboran `950128`, Maginot land, Great Lakes, Esc / Command Center / Dig2 / G / CombatResolver / TOE / PlayLane / Control Labels / duals / Godot bump / seas coarsening / whole-world remesh are out of scope.

## Diagnosis (accurate board, pre-FEED)

`naval_chokepoints.json` has no named Hong Kong choke (34 sea/strait cells; nearest water is `950011` South China Sea Zone). The only HKG land cell was **Yuen Long**, not the island.

| ID | Name | Domain | Canvas area | Role |
|----|------|--------|-------------|------|
| 902486 | Yuen Long | land / NT | **10.14** | ENG HKG leftover district; bbox ~113.94–114.14 E, 22.38–22.52 N |
| 902598 / 902633 | CHN South | land / mainland | 27240 / 4702 | Guangdong / Pearl River Delta; IDs kept |
| 950011 | South China Sea Zone | sea | ~1712 | nearest water; **not** the rock |
| — | Hong Kong Island / Kowloon / Victoria Harbor | **VOID** | — | Play cannot pick the key |

Island-scale comparators on this canvas: Gibraltar `711520` **13.67**, Malta `710993` **13.03**, Yuen Long **10.14**, Cadiz **470**. Yuen Long is already island-scale **but it is the New Territories**, not the harbor rock. Sample WGS84 on HK Island / Kowloon / harbor = void.

## What FEED-5 writes

Pure product: `tools/map_generation/lib/hong_kong_island_land_product.py`  
Write: `tools/map_generation/scripts/apply_hong_kong_island_land.py`

1. **Append** land `905844` **Hong Kong** — Malta/Gibraltar-like island-key ring covering HK Island + Kowloon + Victoria Harbor. `island_class=island`, terrain mountains, owner **ENG** (1841–1997; same convention as Yuen Long + Gibraltar).
2. **Keep** Yuen Long geometry / name / ENG owner (no clip — rings do not overlap). CHN South IDs / names stay. No seas remesh.
3. **Adjacency** (theater only): `905844` ↔ `902486` (NT land) and `905844` ↔ `950011` (South China Sea). Mainland China remains reachable via Yuen Long → CHN South.
4. Hierarchy / Southeast Asia & Pacific region / Hong Kong S.A.R. state bucket / city / economy / terrain cloned or filled for the new ID only.

Board scale stays **~3520** (3527 + 1 = **3528**). Seas stay **340**. `world_full` is not written.

## Before / after (theater)

| Metric | Before | After |
|--------|--------|-------|
| Land named "Hong Kong" | none (Yuen Long only) | `905844` Hong Kong |
| HK Island / Kowloon / harbor pick | VOID | inside `905844` |
| Yuen Long `902486` area | 10.14 | 10.14 (ID/name kept) |
| Hong Kong canvas area | — | **11.74** (Malta 13.03 / Gibraltar 13.67) |
| Board n | **3527** | **3528** |
| Seas | 340 | 340 |
| Gibraltar `711520` / Alboran `950128` / Maginot edge | kept | kept |

## Later FEEDs (not this PR)

- Other island keys — only if still missing after a later Scott GO.
- Do not remesh whole South China / Pearl River here.

## Gates (machine)

Slice green on this PR:

```bash
python3 -m unittest tools.map_generation.tests.test_hong_kong_island_land_product -v
```

`map_accuracy_qc` on the written board: hard_ok, matched **3528**, orphans 0, NE land hit **0.9853**. Maginot FEED-2 + Gibraltar FEED-3 + Alboran FEED-4 product tests still PASS. `world_accurate` hierarchy/ownership/choke tests PASS.

`--quick` living-unit wiring fails are **tip-pre-existing** on `ce8d7c2021a5bf01eeb841edfd9f379ad82847b5`. This FEED does not touch those GD files.

## Play smoke (human)

Asia / Pearl River operational zoom: pick HK Island or Kowloon — inspector should read **Hong Kong** (land `905844`), not Yuen Long and not "South China Sea Zone". Yuen Long NT pick still reads Yuen Long. Esc HARD PASS on the tip. Dig2 / G / Maginot combat not in this FEED.
