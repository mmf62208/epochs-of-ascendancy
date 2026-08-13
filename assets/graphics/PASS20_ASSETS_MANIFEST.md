# Asset Pass 20 — Factory assign · Site repair CTA · Compare card · Intensity sliders

Skills: `game-asset-core` · `game-ui-icons`

## Munitions factory assignment

`MunitionsDeskChip`:

- **Assign factory** creates/finds a munitions line (`munitions_bulk_line` or existing ammo/shell line)  
- Assigns via `ProductionManager.assign_line_to_factory` to a free player factory  
- Line status readout: unassigned / factory id  

## Site repair panel CTA

Special sites inspector rows when damaged:

- Styled **Repair (−1 dmg)** button (engineers still add +1)  
- Mini progress bar (restored / max damage)  
- Toast + live airfield ring refresh after repair  

## Route compare card

After Shift+click A/B compare:

- Top-right card: hops/risk for A (cyan) & B (magenta)  
- Prefer winner line  
- **Focus A / Focus B / Dismiss**  
- Auto-dismiss ~8s  

## Secondary intensity sliders

Toolbar **2nd** row:

- Toggle chip + **HSlider** 0.25–2.0 per secondary  
- `MapRenderer.secondary_tint_intensity` scales secondary blend  

## Code

| File | Change |
|------|--------|
| `MunitionsDeskChip.gd` | Assign factory line |
| `MapRenderer.gd` | Repair CTA, compare card, intensity API |
| `MapModeToolbar.gd` | Secondary intensity sliders |

## Limits / Pass 21 ideas

- Munitions line design_id may be a placeholder without full template.  
- Compare card is last-pair only.  
- Intensity applies to secondary blend only (not primary mapmode).  
- Pass 21 candidates: munitions stockpile graph, multi-site bulk repair, compare save slots, intensity presets. **Done — see PASS21_ASSETS_MANIFEST.md.**
