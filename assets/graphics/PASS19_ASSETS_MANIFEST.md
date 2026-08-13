# Asset Pass 19 — Munitions desk · Ring site open · Route compare · Chip toggle

Skills: `game-asset-core` · `game-ui-icons`

## Munitions production desk

`MunitionsDeskChip.gd` (bottom-right, supply mode):

- Average depot munitions fill bar  
- Active cargo kind / munitions fraction  
- **Ship munitions** → `SupplyCargoProfile.munitions(500)` as active cargo  
- **Production** → opens ProductionAssignmentScreen when available  

## Ring click → site panel

`FeatureProgressRing.ring_clicked(province_id)`:

- Focuses province  
- Opens inspector (`show_info_panel`) with special sites section  
- Toast: airfield site  

## Multi-route compare

Minimap convoy pips:

- **Shift+click** route A, then Shift+click B  
- `MapRenderer.compare_supply_routes` → cyan A / magenta B polylines (~6s)  
- Toast: hops + risk % + preferred route  

## Secondary chip click-to-toggle

Toolbar **2nd** chips are toggle buttons:

- Click off removes that secondary tint  
- Click rebuilds from live `debug_tint_mode_secondaries`  

## Code

| File | Change |
|------|--------|
| `MunitionsDeskChip.gd` | New munitions logistics desk |
| `MapRenderer.gd` | Desk wiring, ring click, compare API, tint toggle |
| `FeatureProgressRing.gd` | Click signal |
| `SupplyMapLayer.gd` | Dual-route compare draw |
| `MapMinimap.gd` | Shift+click compare select |
| `MapModeToolbar.gd` | Secondary chip toggles |

## Limits / Pass 20 ideas

- Munitions desk is a status chip, not a full factory queue editor.  
- Ring click needs Area2D pick under camera.  
- Compare holds only one A pending until B.  
- Pass 20 candidates: munitions factory assignment, site repair button in panel, compare panel card, secondary intensity sliders. **Done — see PASS20_ASSETS_MANIFEST.md.**
