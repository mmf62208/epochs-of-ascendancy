# Asset Pass 15 — Airfield damage · Fuel bar · Stacked presets · Minimap weather

Skills: `game-asset-core` · `game-ui-icons`

## Units — airfield damage

| Stem | Role |
|------|------|
| `airfield_damaged` | Cratered runway / damaged tower + fire accents |

Map markers swap when province damage classifier hits airfield features.  
Paths: `units/retrowave/airfield_damaged_32/64.png` + `icons/hud/airfield_damaged_32.png`.

## OOB fuel bar (naval / air)

Fifth mini-bar when formation is naval/air/space (or has `fuel_level`):

| Bar | Color | Source |
|-----|-------|--------|
| Org | Cyan | `organization` |
| Strength | Magenta | `strength` |
| Readiness | Lime | `readiness` |
| XP | Gold | `combat_experience` |
| **Fuel** | Amber→red when low | `fuel_level` 0–1 |

Tooltip appends `Fuel %`.

## Multi-mode preset stacks

New stacked presets on toolbar:

| Preset | Primary | Stack |
|--------|---------|-------|
| Warpath | naval | +supply |
| StormOps | weather | +supply |
| BuildNet | infra | +supply |

`MapRenderer.apply_mapmode_preset_stack` forces supply overlay and/or weather particles on top of the primary mapmode.

## Minimap weather dots

When weather mapmode (or Climate / StormOps) is active:

- Sampled province dots colored by dry / mud / snow / storm  
- Respects `weather_ground_filter`  
- Strategic LOD slightly larger dots  

## Code

| File | Change |
|------|--------|
| `UnitIconLibrary.gd` | airfield_damaged stem |
| `MapRenderer.gd` | Airfield damage path; preset stack API; minimap weather toggle |
| `ProvinceOOBStrip.gd` | Fuel mini-bar for naval/air |
| `MapModeToolbar.gd` | Stacked presets Warpath/StormOps/BuildNet |
| `MapMinimap.gd` | Weather dots layer |
| New PNG | airfield_damaged |

## Limits / Pass 16 ideas

- Stacked presets only support supply + weather overlays (not multi-tint fills).  
- Minimap weather dots are sampled (not every province on world_full).  
- Fuel bar hidden for pure land formations.  
- Pass 16 candidates: stacked vitality+strain, convoy minimap pips, OOB ammo bar, airfield repair progress ring. **Done — see PASS16_ASSETS_MANIFEST.md.**
