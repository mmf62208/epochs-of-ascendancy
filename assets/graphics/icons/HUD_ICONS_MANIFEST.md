# HUD / Map Mode / Resource Icons Manifest

Generated for **Epochs of Ascendancy** using bundled skills:
`game-asset-core`, `game-ui-icons`, `game-tilesets`.

## Style contract

- Retrowave grand-strategy UI: deep navy `#0f0f1e`, neon cyan `#33e6ff`, magenta accents `#ff33cc`
- Flat / neon-outline icons, no lettering, centered, high contrast
- Uniform padding; readable at 32px (HUD) / 24px (resources)

## HUD navigation — `assets/graphics/icons/hud/`

| File | Use |
|------|-----|
| `production_64.png` / `_32.png` | Production |
| `leaders_64.png` / `_32.png` | Leaders |
| `technology_64.png` / `_32.png` | Technology |
| `diplomacy_64.png` / `_32.png` | Diplomacy |
| `agents_64.png` / `_32.png` | Agents |
| `trade_64.png` / `_32.png` | Trade |
| `space_64.png` / `_32.png` | Space |
| `map_64.png` / `_32.png` | Map |

Wired in: `TopInfoBar.gd` via `HudIconLibrary`.

## Map modes — `assets/graphics/icons/map_modes/`

| File | Mode |
|------|------|
| `political_*.png` | Political |
| `strain_*.png` | Strain |
| `vitality_*.png` | Vitality |
| `development_*.png` | Development |
| `supply_*.png` | Supply |
| `loyalty_*.png` | Loyalty |
| `infra_*.png` | Infra |
| `naval_*.png` | Naval |

Wired in: `MapModeToolbar.gd`.

## Resources — `assets/graphics/icons/resources/`

| File | Resource |
|------|----------|
| `steel_64.png` / `_24.png` | Steel |
| `aluminum_64.png` / `_24.png` | Aluminum |
| `fuel_64.png` / `_24.png` | Fuel / Energy / Oil |
| `rubber_64.png` / `_24.png` | Rubber |

## Tiles — `assets/graphics/tiles/`

| File | Notes |
|------|--------|
| `ocean_seamless.png` | 256² deep navy water; tileable (see `ocean_seamless_2x2_preview.png`) |
| `ocean_seamless_2x2_preview.png` | Verification composite |

## Code

- `scripts/ui/HudIconLibrary.gd` — load + apply helpers
- Icons fail soft if missing (`ResourceLoader.exists`).

## Known limits

- Ocean tile has soft wave motifs that can show light periodicity under squint (acceptable for overlay fill; not photoreal).
- Icons are JPG-sourced then resized to PNG; slight softness at 24px is normal.
- Hover/pressed states: brightness-matched variants (see `WORLD_CLASS_ASSETS_MANIFEST.md` for full pack).

## See also

`assets/graphics/WORLD_CLASS_ASSETS_MANIFEST.md` — panel chrome, progress bars, terrain tiles, speed/pause icons.
