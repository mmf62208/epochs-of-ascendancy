# Asset Pass 26 — Counter-offers · Occupation munitions · Risk export · Route C

Skills: `game-asset-core` · `game-ui-icons`

## Alliance counter-offers

`RelationsManager.counter_alliance_offer(responder, original_proposer, terms)`:

- Replaces incoming pending offer with a counter from responder  
- Terms: `require_guarantee`, `min_crs`, `note`  
- Accept honors guarantee + min CRS  
- AI mid-band may counter instead of accept  

Diplomacy: **Counter** button next to Accept/Decline.

## Occupation munitions map tint

Munitions mapmode:

- When `controller_tag ≠ owner_tag` → amber occupation cast on province fill  

Minimap munitions pips:

- Occupied depots get amber outer ring  

## Risk history export

Compare card **Export**:

- CSV to clipboard (if available)  
- Writes `user://route_risk_history.csv`  
- Columns: sample, risk_a, risk_b, hops, track  

## Multi-route C track

Minimap Shift+click:

1. A (cyan)  
2. B (magenta) → A/B compare immediately  
3. Optional C (amber) → A/B/C triple compare  

`SupplyMapLayer.compare_route_points_abc` · `MapRenderer.compare_supply_routes_multi`  
Compare card shows C hops/risk + Focus C.

## Code

| File | Change |
|------|--------|
| `RelationsManager.gd` | Counter-offer API + AI counter |
| `DiplomacyView.gd` | Counter button |
| `SupplyMapLayer.gd` | Route C draw |
| `MapRenderer.gd` | Multi compare, occupation tint, export |
| `MapMinimap.gd` | A/B/C Shift flow, occupation rings |

## Limits / Pass 27 ideas

- Counter terms are fixed UI defaults (no free-form negotiation panel).  
- Route C not stored in day-history track yet.  
- Export is A/B only (no C column).  
- Pass 27 candidates: free-form counter terms UI, C in history/export, munitions occupation mapmode filter, four-route pack. **Done — see PASS27_ASSETS_MANIFEST.md.**
