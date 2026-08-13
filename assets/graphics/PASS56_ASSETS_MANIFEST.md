# Asset Pass 56 — Pin hist list · Link opacity · Bulk JSON · Pin SFX mute

Skills: `game-asset-core` · `game-ui-icons`

## Pin history UI list

| Control | Role |
|---------|------|
| **Pin hist…** OptionButton | Newest-first list; select jumps (truncates newer entries) |
| **Clr Pin** | Clears memory + `_pin_focus_history.json` |
| **Pin ◀ / Pin Foc** | Refresh list after change |

APIs: `get_pin_focus_history`, `jump_pin_focus_history(index)`, `clear_pin_focus_history`.

Zoom modifiers still apply on jump (soft / Ctrl tactical / Alt keep).

## Link-all library opacity

| UI | **Link α** checkbox next to opacity slider |
|----|--------------------------------------------|
| Effect | Opacity writes to all window keys + live-updates open `PackLibraryPopup*` panels |
| Persist | `pack_library_opacity_link` |

APIs: `set/get_library_opacity_link_all`, `_apply_library_opacity_to_open_windows`.

## Bulk JSON schema

| Export | **Shift+Bulk Exp** → JSON `epochs_pack_bulk` v1 on clipboard |
|--------|---------------------------------------------------------------|
| File | Ctrl/Alt+Shift+Bulk Exp → save `.json` |
| Import | **Bulk Imp** auto-detects `{...}` JSON (also text format) |

Schema:

```json
{
  "v": 1,
  "format": "epochs_pack_bulk",
  "generated": "...",
  "tags": ["east", "safe"],
  "groups": ["theater/east"],
  "packs": ["optional", "matching", "names"]
}
```

API: `export_route_pack_bulk_json(include_matching_packs, path)`.

## Pin focus SFX mute

| UI | **Pin SFX** checkbox on compare card |
|----|--------------------------------------|
| Persist | `pack_pin_focus_sfx` (default true) |
| Gate | `spawn_pin_focus_pulse` skips `_play_map_sfx` when off |

APIs: `get/set_pin_focus_sfx_enabled`.

## Prefs

`_map_prefs.json` **v9**.

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Hist list, link α, bulk JSON, SFX mute |

## Limits / Pass 57 ideas

- Pin hist list truncates on jump (by design).  
- Link α stamps windows 1–4 even if unused.  
- Pass 57 candidates: pin hist search filter, bulk JSON packs as bulk assign, SFX volume slider, library theme variants.
