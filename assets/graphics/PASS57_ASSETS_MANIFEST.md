# Asset Pass 57 — Pin hist search · JSON pack select · SFX volume · Library themes

Skills: `game-asset-core` · `game-ui-icons`

## Pin history search filter

| UI | `pin…` LineEdit next to **Pin hist…** |
|----|----------------------------------------|
| Match | Substring on label · source · pid |
| Cap | Max 40 filtered rows (newest first) |

Rebuilds the OptionButton on each keystroke.

## Bulk JSON packs → Left select

On JSON bulk import (`epochs_pack_bulk` with `packs: []`):

1. Tags/groups still merge into shared bulk  
2. `resolve_route_pack_library_names` keeps existing `.eorp` stems  
3. Left list multi-selects matching packs after refresh  

Toast: `selected N packs` when any match the current list view.

API: `resolve_route_pack_library_names(names)`.

## Pin SFX volume

| UI | HSlider next to **Pin SFX** (−40 … 0 dB) |
|----|------------------------------------------|
| Persist | `pack_pin_focus_sfx_db` |
| Gate | Mute still via **Pin SFX**; volume applied in `_play_map_sfx("pin_focus")` |

APIs: `get/set_pin_focus_sfx_volume_db`.

## Library theme variants

| Id | Chrome |
|----|--------|
| `classic` | Neutral panel · cyan title |
| `mono` | Cool gray tint · silver title |
| `amber` | Warm tint · amber title |
| `magenta` | Magenta-leaning tint · magenta title |

| UI | **Theme** OptionButton on layout row |
|----|--------------------------------------|
| Persist | `pack_library_theme` |
| API | `get/set_library_theme`, `apply_library_theme_to_panel` |

Opacity (α) only adjusts modulate alpha so theme RGB is preserved.

## Prefs

`_map_prefs.json` **v10**.

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Search, pack select, SFX dB, themes |

## Limits / Pass 58 ideas

- Theme is global (not per-window).  
- Pack select only hits packs visible in current filter.  
- Pass 58 candidates: per-window theme, pack select scroll-into-view, SFX preview button, theme CSS-like presets file.
