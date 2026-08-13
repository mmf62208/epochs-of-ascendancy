# Asset Pass 27 — Counter terms UI · C/D history · Occupation filter · Four-route pack

Skills: `game-asset-core` · `game-ui-icons`

## Free-form counter terms UI

Diplomacy **Counter…** opens a dialog:

| Control | Field |
|---------|--------|
| Checkbox | Require independence guarantee |
| SpinBox | Min CRS (0–100, step 5) |
| LineEdit | Free-form note |

Submits via `RelationsManager.counter_alliance_offer` with player terms.

## Route C/D in history + export

Day-history tracks:

- `samples_a`–`samples_d`, paths A–D  
- Sparkline draws amber C / green D when present  
- CSV columns: `risk_c`, `risk_d`, hop counts for C/D  

## Munitions occupation filter chip

Desk **Focus: all / occupied / mine**:

- Dims non-matching provinces in munitions mapmode  
- Filters minimap munitions pips  
- Syncs with Map pips mine/all  

## Four-route D pack

Shift+click convoy pips:

1. A cyan  
2. B magenta → A/B compare  
3. C amber → A/B/C  
4. D green → A/B/C/D pack, then clear  

`SupplyMapLayer.compare_route_points_abcd` · card Focus D.

## Code

| File | Change |
|------|--------|
| `DiplomacyView.gd` | Counter terms dialog |
| `SupplyMapLayer.gd` | Route D draw + ABCD API |
| `MapRenderer.gd` | 4-route compare, C/D history/export, occupation filter tint |
| `MapMinimap.gd` | A–D Shift flow, occupation filter |
| `MunitionsDeskChip.gd` | Focus chip |

## Limits / Pass 28 ideas

- Counter dialog is Window (not in-place form).  
- History sparkline overplots 4 series (dense at small height).  
- No dedicated pack preset button (only Shift+click).  
- Pass 28 candidates: counter templates, history legend, munitions pack preset, compare pack save slots for 4 routes. **Done — see PASS28_ASSETS_MANIFEST.md.**
