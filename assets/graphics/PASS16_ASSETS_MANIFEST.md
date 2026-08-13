# Asset Pass 16 — Society stack · Convoy minimap · Ammo bar · Airfield repair rings

Skills: `game-asset-core` · `game-ui-icons`

## Multi-mode presets (stacked)

| Preset | Primary | Stack |
|--------|---------|-------|
| Society | vitality | +strain secondary tint |
| SeaLanes | supply | +convoy_minimap (+ naval note) |

Secondary tint via `MapRenderer.debug_tint_mode_secondary` + `_apply_secondary_debug_tint` (soft blend, does not replace primary).

## Convoy minimap pips

When supply mode / SeaLanes / logistics stacks are active:

- Midpoints of trade corridors (and at-risk supply routes) as amber→red pips  
- Red intensity tracks `interdiction_chance`  
- Cap 36 pips; strategic LOD slightly larger  

`MapMinimap.set_show_convoy_pips` / `_ensure_convoy_pips`.

## OOB ammo bar

Land formations (and any with `ammo_level` / `supply_level` / `munitions`):

| Bar | Color |
|-----|-------|
| Ammo | Slate-blue → grey-red when empty |

Fallback proxy: `readiness * 0.55 + strength * 0.45` when no dedicated field.

## Airfield repair progress ring

`FeatureProgressRing.gd` attached beside airfield map chips when:

- Site damaged → ring = remaining health / repair  
- SpecialSite build progress < 1 → construction ring  

Cyan/lime for repair, amber for construction.

## Code

| File | Change |
|------|--------|
| `FeatureProgressRing.gd` | New map progress ring glyph |
| `MapRenderer.gd` | Secondary tint, airfield rings, convoy minimap hook |
| `MapModeToolbar.gd` | Society + SeaLanes presets |
| `MapMinimap.gd` | Convoy pips |
| `ProvinceOOBStrip.gd` | Ammo mini-bar |

## Limits / Pass 17 ideas

- Secondary tint is only strain/vitality/dev/loyalty (not full dual mapmodes).  
- Ammo proxy is not a true munitions stockpile.  
- Repair rings rebuild with province nodes (not live-updating mid-month without refresh).  
- Pass 17 candidates: live ring refresh on day tick, ammo from depot stock, multi-secondary tints, minimap pip click-to-focus convoy. **Done — see PASS17_ASSETS_MANIFEST.md.**
