# Asset Pass 59 — Theme color pickers · Pack-select pulse · SFX bus · Theme share (EOTM1)

Skills: `game-asset-core` · `game-ui-icons`

## Theme color pickers + save

| UI | Library **Chrome** / **Title** `ColorPickerButton`s under Theme row |
|----|---------------------------------------------------------------------|
| Live | Edits apply immediately to panel modulate + title accent (α preserved) |
| **Save Theme** | Writes colors to current theme id via `upsert_library_theme_preset` |
| **Shift+Save Theme** | New preset `custom_<rrggbb>` and selects it |

Pickers resync when Theme dropdown or Theme File import changes.

## Pack-select highlight pulse

| API | `pulse_item_list_selection(list, duration)` |
|-----|-----------------------------------------------|
| Bulk | `select_packs` → pulse Left list 0.9s + scroll into view |
| Click | Left/Right list `item_selected` → pulse 0.45s |

Uses `ItemList.set_item_custom_bg_color` cyan flash; generation meta cancels stale timers.

## Pin SFX bus routing

| Pref | `pack_pin_focus_sfx_bus` (default `Master`) in `_map_prefs.json` **v12** |
|------|------------------------------------------------------------------------|
| API | `get/set_pin_focus_sfx_bus`, `list_audio_bus_names` |
| UI | OptionButton next to Pin SFX volume / ▶ on compare card |
| Playback | `_play_map_sfx` / `preview_pin_focus_sfx` assign `AudioStreamPlayer.bus` |

Unknown bus names fall back to `Master`.

## Theme share code (EOTM1)

| Format | `EOTM1.<base64url(json)>` |
|--------|---------------------------|
| Payload | `{v, format: epochs_library_theme, id, modulate, title}` hex colors |
| Export | ** thr↗** → clipboard via `export_library_theme_share_code` |
| Import | **Ctrl/Alt+Thr↗** → `import_library_theme_share_code` upserts preset + selects |

## Prefs

`_map_prefs.json` **v12** includes `pack_pin_focus_sfx_bus` (added with Pass 59 APIs).

Theme colors live in `user://route_packs/_library_themes.json` (`epochs_library_themes`).

## Code

| File | Change |
|------|--------|
| `scripts/map/MapRenderer.gd` | Color pickers, Save Theme, Thr↗ share, bus OptionButton, select pulse UI wiring; prior APIs (EOTM1, bus, pulse, upsert) |

## Limits / Pass 60 ideas

- Theme name LineEdit (typed custom ids beyond Shift-save hex).  
- Per-window share of full chrome snapshot (opacity + dock + theme).  
- Multi-select pulse stagger / different colors per list side.  
- SFX bus mute group or UI bus auto-create.  
- Theme share QR (reuse RoutePackQR pipeline).  
