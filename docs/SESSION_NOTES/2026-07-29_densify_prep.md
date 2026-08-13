# Sparse-board densify prep (next data phase — not executed this goal)

## Intent
Larger playable provinces in low-density / sparse areas (US-merge pattern), while keeping enough for grand-strategy flexibility.

## Candidate regions (priority order)
1. **Africa** — merge geoBoundaries densify where state/region scale is over-fragmented
2. **Central America / South America** — same
3. **Australia** — few large playable states/territories
4. **India** — playable state-scale aggregates (not every admin unit)
5. **Siberia / Mongolia / sparse interior China** — large empty-land playables

## Constraints (never)
- Do **not** renumber `world_full` IDs in place
- Keep dual board: `world_accurate` play vs `world_full` scaffold
- Preserve adjacency coverage floor (~0.97 land shared) and chokepoints (Gibraltar, Suez, etc.)
- Sea zones: similar size; narrow straits stay small/key

## Pipeline reuse
- US pattern: `merge_us_counties_to_state_provinces.py` + remap JSON
- Product stub candidate (later): `us_state_province_density_product`-style pure gate for “target province count band + ownership continuity”
- Pure landmass helper already supports label placement after densify (`map_nation_label_landmass_product`)

## Exit criteria for a densify PR (future)
- Pure product: target counts + no land orphans
- Headless load `world_accurate` green
- Human: Maginot density unchanged; RoW pan still readable

## Status update (same day)
**Tranche 1 board merge landed** — see `2026-07-29_row_sparse_merge_t1.md`.
Africa / Australia / Oceania islands merged via `merge_row_sparse_to_playable.py --write`.
Board ~5670 → ~4683 · adj cov ~0.971 · orphans 0.
