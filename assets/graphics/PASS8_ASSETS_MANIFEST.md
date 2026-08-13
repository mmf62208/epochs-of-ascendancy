# Asset Pass 8 — Coastal · Fort/Port · OOB strip · Stack pulse

Skills: `game-asset-core` · `game-ui-icons` · `game-tilesets`

## Terrain — `assets/graphics/tiles/coastal_seamless.png`

Shallow coastal water/sand mottling (+ 2×2 preview).  
Tint + edge mix for coastal/harbor fronts.

## Units / HUD chips

| Stem | Path |
|------|------|
| fort | `units/retrowave/fort_32/64.png` + `icons/hud/fort_32.png` |
| port | `units/retrowave/port_32/64.png` + `icons/hud/port_32.png` |

`UnitIconLibrary` keywords: fort/bunker, port/harbor/dock.

## Province OOB strip — `scripts/ui/ProvinceOOBStrip.gd`

When inspector opens on a province with **2+ formations**:

- Bottom-left framed strip lists each unit with chip icon + name + Focus  
- Focus re-centers province and toasts formation id  

Hidden when stack ≤ 1 or inspector closes.

## Animated stack pulse

Stack badges pulse scale + alpha every frame (`_pulse_stack_badges`), including while sim paused.

## Files

| File | Change |
|------|--------|
| `ProvinceOOBStrip.gd` | New multi-formation strip |
| `MapRenderer.gd` | Strip wiring, pulse, fort/port paths, coastal edges |
| `TerrainTileLibrary.gd` | Coastal keys |
| `UnitIconLibrary.gd` | Fort/port stems |
| New PNGs | coastal, fort, port |

## Limits / Pass 9 ideas

- OOB strip uses all formations at province (not filtered by player).  
- Pulse is simple sin — not particle FX.  
- Coastal tile is terrain tint only.  
- Pass 9: player-only OOB filter, fort map marker on special_features, convoy chip, weather icons. **Done — see PASS9_ASSETS_MANIFEST.md.**
