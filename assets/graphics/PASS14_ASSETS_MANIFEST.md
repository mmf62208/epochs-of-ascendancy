# Asset Pass 14 — Damaged port · XP bar · Particle filter · Mapmode presets

Skills: `game-asset-core` · `game-ui-icons`

## Units — damaged port

| Stem | Role |
|------|------|
| `port_damaged` | Broken pier / crane + fire accents |

Used when province damage classifier hits port features (same path as fort_damaged).  
Paths: `units/retrowave/port_damaged_32/64.png` + `icons/hud/port_damaged_32.png`.

## OOB combat XP bar

Fourth mini-bar under formation chips:

| Bar | Color | Source |
|-----|-------|--------|
| Org | Cyan | `organization` |
| Strength | Magenta | `strength` |
| Readiness | Lime | `readiness` |
| **XP** | Gold | `combat_experience` (0–100 → 0–1) |

Tooltip: `Org · Str · Rdy · XP`.

## Weather particle filter sync

`WeatherOverlayLayer.particle_ground_filter` + `set_particle_ground_filter`:

- MapModeToolbar Wx chips → `MapRenderer.set_weather_ground_filter`  
- Fills dim **and** particle reseed only for the selected ground state  
- Filtered view densifies clusters for that state  

## Mapmode presets

Toolbar **Preset** row:

| Preset | Mode |
|--------|------|
| Overview | political |
| Logistics | supply |
| Theater | naval |
| Climate | weather |
| Build | infra |

One click applies mode + legend toast.

## Code

| File | Change |
|------|--------|
| `UnitIconLibrary.gd` | port_damaged stem |
| `MapRenderer.gd` | Port damaged path; particle filter sync |
| `WeatherOverlayLayer.gd` | `set_particle_ground_filter` |
| `ProvinceOOBStrip.gd` | XP mini-bar |
| `MapModeToolbar.gd` | Preset row + filter → particle sync |
| New PNG | port_damaged |

## Limits / Pass 15 ideas

- Presets are mode-only (no stacked overlays yet).  
- XP bar assumes 0–100 combat_experience (clamps if already normalized).  
- Damaged port is one glyph for all port tiers.  
- Pass 15 candidates: multi-mode preset stacks, airfield damage glyph, OOB fuel bar (naval), minimap weather dots. **Done — see PASS15_ASSETS_MANIFEST.md.**
