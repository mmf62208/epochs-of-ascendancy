# Asset Pass 49 — Custom heat · Layout hotkeys · Tag/Bulk OR · Pin focus

Skills: `game-asset-core` · `game-ui-icons`

## Custom heat cool/hot colors

| UI | ColorPickerButtons next to heat ramp on compare card |
|----|------------------------------------------------------|
| Ramp | New preset **`custom`** |
| Behavior | Editing a picker auto-selects `custom` ramp |
| API | `MapMinimap.set/get_pack_heat_cool`, `set/get_pack_heat_hot` |

Persisted in `_map_prefs.json` (`v: 4`) as `pack_heat_cool` / `pack_heat_hot` (hex) + save keys.

## Library layout keyboard chords

| Chord | Layout |
|-------|--------|
| **Ctrl+1** | standard |
| **Ctrl+2** | compact |
| **Ctrl+3** | wide |
| **Ctrl+4** | left |

Hidden shortcut buttons on the layout row (works while library has focus).

## Tag OR + Bulk OR

| Control | Effect |
|---------|--------|
| **Tag OR** | Multi `#tag` chips match **any** (`@tagor` token) |
| **Bulk OR** | **Bulk Filt** replaces active chips; enables Tag OR / Grp OR when ≥2 of that kind |

Filter engine: `filter_route_pack_library` collects `#tags` like groups; AND default, OR with `@tagor`/`@tor`.

## Pin focus cycle

| UI | **Pin Foc** on bulk bar |
|----|-------------------------|
| Default | Focus highest-risk pack pin, then cycle |
| Shift | Lowest-risk first |
| API | `focus_pack_pin_by_risk(cycle_index, highest_first)` |

Uses `get_pack_slot_pins()` → `focus_province_by_id`.

## Code

| File | Change |
|------|--------|
| `MapMinimap.gd` | Custom cool/hot colors |
| `MapRenderer.gd` | Prefs v4, Tag OR, Bulk OR, Pin Foc, layout chords, color pickers |

## Limits / Pass 50 ideas

- Pin Foc only cycles currently loaded pack slots (not library-only packs).  
- Color pickers open full ColorPicker popup (dense on small cards).  
- Pass 50 candidates: pin focus filter by bulk tags, heat ramp swatch legend, layout drag-resize, library multi-window.
