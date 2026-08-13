# Asset Pass 52 — Dock chords · Pin pulse · Bulk export · Ramp cycle UI

Skills: `game-asset-core` · `game-ui-icons`

## Dock keyboard chords

| Chord | Dock |
|-------|------|
| **Ctrl+Shift+←** | left |
| **Ctrl+Shift+→** | right |
| **Ctrl+Shift+↓** | bottom |
| **Ctrl+Shift+↑** | float |

Hidden shortcut buttons on the library layout row (same pattern as Ctrl+1..4 layouts).

## Pin focus pulse marker

| Trigger | **Pin Foc** / `focus_pack_pin_by_risk_info` |
|---------|---------------------------------------------|
| Visual | 3 expanding cyan/amber `Line2D` rings + center pip |
| Life | ~1.55s fade + scale (works while sim paused) |
| API | `spawn_pin_focus_pulse(world_pos)`, `_update_pin_focus_pulse` |

Drawn on map `container` at province centroid after pin focus.

## Bulk export clipboard

| UI | **Bulk Exp** on tag cloud bulk bar |
|----|------------------------------------|
| Content | Header, tags=, groups=, packs= list matching bulk query |
| OR | Adds `@tagor` / `@groupor` when ≥2 of a kind |
| API | `export_route_pack_bulk_clipboard(include_matching_packs)` |

Copies multi-line text via `DisplayServer.clipboard_set`.

## Ramp cycle on compare card

| Control | Action |
|---------|--------|
| **↻** | `cycle_pack_heat_ramp(+1)` |
| **↺** | `cycle_pack_heat_ramp(-1)` |

Syncs OptionButton selection with minimap swatch cycle; prefs persist.

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Pulse, bulk export, dock chords, ramp ↻/↺ |

## Limits / Pass 53 ideas

- Pulse is world-space rings (not GPU bloom).  
- Bulk export always uses tag/group OR when ≥2 (not Bulk OR checkbox).  
- Pass 53 candidates: pulse color from heat ramp, bulk import from clipboard, dock save per-window, ramp preview strip on card.
