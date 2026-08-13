# Asset Pass 17 — Live rings · Depot ammo · Multi-secondary · Convoy click

Skills: `game-asset-core` · `game-ui-icons`

## Live airfield ring refresh

On `TimeManager.game_day_advanced`:

- `MapRenderer._refresh_feature_progress_rings` walks existing `FeatureProgressRing` nodes  
- Recomputes repair/build progress from damage classifier / SpecialSite data  
- Rings pulse briefly on change; hide when fully repaired  

No full province node rebuild required.

## OOB ammo from depot stock

Ammo bar priority:

1. Explicit `ammo_level` / `munitions` / `supply_level` on formation  
2. **`SupplyManager.get_depot_state(stationed_province).fill_ratio()`** blended with readiness  
3. Land proxy `readiness×strength`  

Tooltip still shows Ammo %.

## Multi-secondary tints

`debug_tint_mode_secondaries: Array` holds all stacked secondary mapmode keys.

New presets:

| Preset | Primary | Stack |
|--------|---------|-------|
| HomeFront | vitality | strain + loyalty |
| EconPulse | development | strain + vitality |

Each secondary applies a soft `_apply_secondary_debug_tint` pass (order preserved).

## Convoy minimap click-to-focus

When convoy pips are visible:

- Left-click nearest pip (8px hit) focuses route **target province**  
- Toast: `Convoy focus · pid · risk %`  
- Pip stores `focus_pid` from `SupplyRoutePlan.target_province_id`  

Falls back to pan if no pip hit.

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Day-tick ring refresh; multi-secondary array |
| `FeatureProgressRing.gd` | Pulse on live update |
| `ProvinceOOBStrip.gd` | Depot fill_ratio ammo |
| `MapModeToolbar.gd` | HomeFront + EconPulse presets |
| `MapMinimap.gd` | Pip hit-test + focus |
| `SupplyMapLayer.gd` | Cache `focus_pid` |

## Limits / Pass 18 ideas

- Day-tick ring refresh is deferred (not mid-frame).  
- Depot ammo is province depot general stockpile, not munitions-specific cargo.  
- Multi-secondary still soft blends (not independent mapmode channels).  
- Pass 18 candidates: munitions cargo profile ammo, ring tooltips, double-click convoy route highlight, secondary tint legend chips. **Done — see PASS18_ASSETS_MANIFEST.md.**
