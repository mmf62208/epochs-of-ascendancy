# Asset Pass 23 — Munitions icon · Ally repair · Live compare risk · Minimap munitions pips

Skills: `game-asset-core` · `game-ui-icons` · `imagine`

## Dedicated munitions mapmode icon

| File | Size |
|------|------|
| `assets/graphics/icons/map_modes/munitions_32.png` | 32×32 |
| `assets/graphics/icons/map_modes/munitions_64.png` | 64×64 |

- Retrowave panel matching map-mode set (edit-chained from supply icon style)
- Artillery shell + ammo belt motif (no text)
- `HudIconLibrary.MODE_KEYS["munitions"]` → `munitions`

## Ally repair queue

`SiteRepairQueueChip`:

- **Player only** / **Player + allies** toggle
- Allies = RelationsManager band `partner` / `ally_ready` or CRS ≥ 55
- Ally rows marked ★; player sites sort first
- Batch repair respects current scope

## Compare risk recompute on load

`load_route_compare_slot`:

1. Match active `SupplyManager` route path → use live `interdiction_chance`
2. Else re-run `SupplyInterdictionEstimator` (+ storm bump)
3. Card shows **Live risk · was A% / B%**
4. Slot stores updated live risks

## Minimap munitions pips

When munitions mapmode (or stack has munitions):

- Up to 48 depot pips colored by munitions ratio (red empty → cyan full)
- Low fill (&lt;28%) vertical urgency tick
- Click → focus depot province + toast fill %
- Day-tick cache invalidate

## Code

| File | Change |
|------|--------|
| `munitions_32/64.png` | New mapmode icons |
| `HudIconLibrary.gd` | munitions key |
| `SiteRepairQueueChip.gd` | Ally scope toggle |
| `MapRenderer.gd` | Ally collect, estimate_path_interdiction, load recompute, munitions pip toggle |
| `MapMinimap.gd` | Munitions pips draw + hit-test |

## Limits / Pass 24 ideas

- Ally detection is CRS band only (not formal alliance treaties).
- Risk recompute is path-level estimate, not full multimodal re-route.
- Munitions pips ignore ownership filter (all depots).
- Pass 24 candidates: formal alliance treaty filter, munitions-only player depots, compare risk sparkline on card, dedicated munitions minimap LOD. **Done — see PASS24_ASSETS_MANIFEST.md.**
