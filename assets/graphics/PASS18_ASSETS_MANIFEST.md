# Asset Pass 18 — Munitions ammo · Ring tooltips · Route highlight · Secondary chips

Skills: `game-asset-core` · `game-ui-icons`

## Munitions cargo profile ammo

`SupplyCargoProfile`:

- `cargo_kind` (`general` | `munitions` | `fuel` | `mixed`)  
- `munitions_fraction` (default 0.35 general, 0.9 munitions)  
- `munitions()` factory + `munitions_tons()`  

`ProvinceDepotState`:

- `munitions_stockpile` + `munitions_ratio()` / `apply_munitions_inflow()`  

`SupplyManager` delivery deposits munitions share into depots;  
`get_depot_munitions_ratio(pid)` feeds OOB ammo bar.

## Ring tooltips

`FeatureProgressRing` hover (Area2D):

- Label: `Airfield repair/construction · province · %`  
- Refreshed on day-tick progress update  

## Double-click convoy route highlight

Minimap convoy pips:

- Single-click: focus target province (Pass 17)  
- **Double-click**: `MapRenderer.highlight_supply_route_path` →  
  `SupplyMapLayer.highlight_route_points` amber pulse polyline (~4.5s)  

## Secondary tint legend chips

Toolbar **2nd** row after stacked presets:

- Colored chips for active secondaries (strain / vitality / loyalty / development)  
- Built from stack + live `debug_tint_mode_secondaries`  

## Code

| File | Change |
|------|--------|
| `SupplyCargoProfile.gd` | Munitions kind/fraction |
| `ProvinceDepotState.gd` | Munitions stockpile APIs |
| `SupplyManager.gd` | Munitions delivery + query |
| `ProvinceOOBStrip.gd` | Depot munitions_ratio ammo |
| `FeatureProgressRing.gd` | Hover tooltip |
| `MapRenderer.gd` | Ring tooltip text; route highlight API |
| `SupplyMapLayer.gd` | Route highlight draw |
| `MapMinimap.gd` | Double-click highlight |
| `MapModeToolbar.gd` | Secondary tint chips |

## Limits / Pass 19 ideas

- Munitions are a stockpile share, not separate warehouse buildings.  
- Ring hover needs Area2D pick under camera (may miss at extreme zoom).  
- Route highlight needs supply layer visible.  
- Pass 19 candidates: munitions production line UI, ring click open site panel, multi-route compare, secondary chip click-to-toggle. **Done — see PASS19_ASSETS_MANIFEST.md.**
