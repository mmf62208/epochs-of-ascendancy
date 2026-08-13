# Asset Pass 28 — Counter templates · History legend · Ammo pack presets · 4 pack slots

Skills: `game-asset-core` · `game-ui-icons`

## Alliance counter templates

Counter dialog **Templates** row:

| Template | Guarantee | Min CRS | Intent |
|----------|-----------|---------|--------|
| Soft | no | 25 | Light welcome |
| Standard | yes | 40 | Mutual + guarantee |
| Hard | yes | 60 | High trust |
| Guarantee | yes | 0 | Guarantee-only condition |
| CRS gate | no | 55 | Deepen relations first |

Templates fill the free-form fields; player can still edit before **Send counter**.

## Risk history legend

Compare card under hop risk + day history:

- Color swatches **A** cyan · **B** magenta · **C** amber · **D** green (when present)

## Munitions pack presets

| Preset | Mode | Stack |
|--------|------|--------|
| AmmoOcc | munitions | supply + munitions_occupied |
| AmmoMine | munitions | supply + munitions_mine |
| AmmoPack | munitions | supply + convoy_minimap + munitions_all |

`apply_mapmode_preset_stack` applies occupation filter + syncs munitions desk chips.

## 4-route pack save slots

- 4 save/load slots on compare card (was 3)
- Load restores A–D paths via `compare_supply_routes_multi`
- Tooltips show route count
- Persists in `map_ui.route_compare_slots`

## Code

| File | Change |
|------|--------|
| `DiplomacyView.gd` | Counter templates |
| `MapModeToolbar.gd` | AmmoOcc / AmmoMine / AmmoPack |
| `MapRenderer.gd` | 4 slots, load pack, legend, preset stack filters |

## Limits / Pass 29 ideas

- Templates are static (not user-saved).  
- Pack slots share space with A/B-only saves.  
- Preset stack filter sync may not persist desk state on load.  
- Pass 29 candidates: user counter templates, pack slot labels, munitions filter in save, auto-pack from open routes. **Done — see PASS29_ASSETS_MANIFEST.md.**
