# RoW sparse merge — tranche 1 (Africa / Australia / Oceania)

**Date:** 2026-07-29  
**Board:** `data/provinces_world_accurate/`  
**Backup:** `data/provinces_world_accurate.bak_pre_row_merge_*`

## Intent
Larger playable provinces in over-fragmented RoW ADM2 cells (same spirit as US county→1–4/state merge).

## Tranche 1 scopes
| Region | Before | After | Band |
|--------|--------|-------|------|
| africa | 1057 | **171** | 80–220 |
| australia | 73 | **18** | 12–40 |
| oceania_islands | 73 | **27** | 8–40 |
| **cells merged** | **1203** | **216** survivors · **987** dead | |

## Board totals
| Metric | Pre | Post |
|--------|-----|------|
| provinces | ~5670 | **~4683** |
| land | ~5330 | **~4343** |
| RoW 900k | ~3686 | **~2699** |
| land_shared_coverage | ~0.975 | **~0.971** |
| land orphans | 0 | **0** |
| NE land hit | ≳0.90 | **0.988** |

## Artifacts
- Pure plan: `tools/map_generation/lib/row_sparse_density_product.py`
- Write: `tools/map_generation/scripts/merge_row_sparse_to_playable.py`
- Remap: `data/provinces_world_accurate/row_sparse_to_playable_remap.json`
- Tests: `test_row_sparse_density_product.py` · board floors updated
- LOD: `MapZoomLOD.ACCURATE_BOARD_CULL_THRESHOLD` **4000** (was 5000)

## Commands
```bash
# Dry-run
python3 tools/map_generation/scripts/merge_row_sparse_to_playable.py

# Write (backup + adj rebuild)
python3 tools/map_generation/scripts/merge_row_sparse_to_playable.py --write

# Tranche 2 later
python3 tools/map_generation/scripts/merge_row_sparse_to_playable.py --write \
  --scopes central_america,south_america,india,siberia_mongolia_sparse_china
```

## Constraints kept
- Did **not** renumber `world_full`
- Europe NUTS / US playable / seas untouched
- Dual board intact

## Tranche 2 (same day — landed)
Scopes: `central_america,south_america,india,siberia_mongolia_sparse_china`  
**1405 → 242** · dead **1163** · board **~4683 → ~3520** · land_shared **~0.974** · Moscow/Leningrad protected as singletons.

## Next
- M6 human 20d/60d notes (not automated)
- Optional FPS re-sample on ~3520 board
- Optional SE Asia (THA/PHL/IDN…) micro-merge if still noisy
