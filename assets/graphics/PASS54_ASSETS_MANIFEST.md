# Asset Pass 54 — Pin history · Library opacity · (lands 53 leave-offs)

Skills: `game-asset-core` · `game-ui-icons`

Pass 53 leave-offs (pulse ramp tint, bulk import, per-window dock, ramp strip) are included — see `PASS53_ASSETS_MANIFEST.md`.

## Pin focus history (back)

| UI | **Pin ◀** next to **Pin Foc** |
|----|-------------------------------|
| Stack | Up to 32 focuses (dedupe consecutive) |
| Zoom | Soft default · Ctrl tactical · Alt keep |

APIs:

- `push_pin_focus_history(entry)`
- `pop_pin_focus_history(zoom_mode)`
- `get_pin_focus_history_size()`

`focus_pack_pin_by_risk_info` auto-pushes; toast includes `history` count.

## Library panel opacity

| UI | **α** HSlider on layout row (0.35–1.0) |
|----|----------------------------------------|
| Effect | `panel.modulate.a` |
| Persist | `pack_library_opacity` (prefs v7) |

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Pulse ramp colors, bulk import, per-window dock, pin history, opacity, ramp strip |

## Limits / Pass 55 ideas

- Pin history is session-only (not in save).  
- Opacity is global (not per-window).  
- Pass 55 candidates: persist pin history, per-window opacity, bulk Imp file dialog, pulse sound cue.
