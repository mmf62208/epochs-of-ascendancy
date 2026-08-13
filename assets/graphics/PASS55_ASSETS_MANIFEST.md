# Asset Pass 55 — Pin history persist · Per-window opacity · Bulk file dialogs · Pulse SFX

Skills: `game-asset-core` · `game-ui-icons`

## Pin focus history persistence

| Path | `user://route_packs/_pin_focus_history.json` |
|------|-----------------------------------------------|
| Load | `load_pin_focus_history()` on minimap bind (`apply_stored_pack_risk_heat_prefs`) |
| Save | After every push / pop |

Schema: `{v:1, count, entries:[{pid,label,source,risk,zoom}]}`.

## Per-window library opacity

| Storage | `pack_library_opacities` map `{"1":0.9,"2":0.7}` |
|---------|--------------------------------------------------|
| API | `get/set_library_opacity_for_window(idx, opacity)` |
| UI | **α** slider applies to current window only |

Global `pack_library_opacity` still mirrors window 1.

## Bulk Imp / Exp file dialogs

| Control | Default | Ctrl/Alt/Meta |
|---------|---------|---------------|
| **Bulk Imp** | Clipboard | Native open `*.txt` / `*.json` |
| **Bulk Exp** | Clipboard | Native save `*.txt` |

Shift still = replace on import.

## Pin focus pulse SFX

`spawn_pin_focus_pulse` plays `_play_map_sfx("pin_focus")` → Map.wav soft ping.

## Prefs

`_map_prefs.json` **v8** adds `pack_library_opacities`.

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | History IO, per-window opacity, bulk file dialogs, pin_focus SFX |

## Limits / Pass 56 ideas

- Pin history does not re-validate province IDs after map reload.  
- Pulse SFX reuses Map.wav (no dedicated ping asset).  
- Pass 56 candidates: pin history UI list, opacity link-all windows, bulk JSON schema export, mute pin SFX toggle.
