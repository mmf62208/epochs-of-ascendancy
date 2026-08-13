# Asset Pass 58 — Per-window theme · Scroll select · SFX preview · Theme presets file

Skills: `game-asset-core` · `game-ui-icons`

## Per-window library theme

| Storage | `pack_library_themes` map `{"1":"amber","2":"mono"}` |
|---------|-----------------------------------------------------|
| API | `get/set_library_theme_for_window(idx, theme)` |
| UI | Theme OptionButton saves for current Lib window |

Global `pack_library_theme` still mirrors window 1.

## Scroll-into-view on pack select

After JSON bulk import selects packs in Left list:

- First match becomes current  
- `ensure_current_is_visible()` scrolls it into view  

## Pin SFX preview

| UI | **▶** next to SFX volume on compare card |
|----|------------------------------------------|
| API | `preview_pin_focus_sfx()` |
| Behavior | Plays Map.wav at current dB **even if Pin SFX muted** |

## Theme preset file

| Path | `user://route_packs/_library_themes.json` |
|------|-------------------------------------------|
| Format | `epochs_library_themes` v1 |
| Export | **Theme File** writes built-ins |
| Import | **Ctrl/Alt+Theme File** open dialog → copies into default path |

Custom theme ids in the file appear in the Theme dropdown.

Schema:

```json
{
  "v": 1,
  "format": "epochs_library_themes",
  "themes": {
    "classic": {"modulate": "ffffff", "title": "33e6ff"},
    "my_teal": {"modulate": "ccfff5", "title": "00ccaa"}
  }
}
```

APIs: `get_library_theme_presets`, `save_library_theme_presets_file`, `load_library_theme_presets_file`.

## Prefs

`_map_prefs.json` **v11** adds `pack_library_themes`.

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Per-window theme, presets file, scroll select, SFX preview |

## Limits / Pass 59 ideas

- Custom themes need a presets file (no in-UI color editor yet).  
- `ensure_current_is_visible` may vary slightly by Godot 4.x build.  
- Pass 59 candidates: theme color pickers, pack select highlight pulse, SFX bus routing, theme share code.
