# Asset Pass 48 — Native dialogs · Heat ramp · Layout presets · Bulk chips

Skills: `game-asset-core` · `game-ui-icons`

## Native OS file dialogs

| Control | Modifier | Behavior |
|---------|----------|----------|
| **Exp Hist** | Ctrl/Alt/Meta | `FileDialog` with `use_native_dialog` + `ACCESS_FILESYSTEM` |
| **Imp Hist** | Ctrl/Alt/Meta | Native open dialog (Shift still = replace) |

Default clicks still use `user://route_packs/_search_history_export.json`.

## Heat color ramp

| UI | OptionButton on compare card (after legend slider) |
|----|----------------------------------------------------|
| Presets | `classic` · `inferno` · `viridis` · `mono` |
| API | `MapMinimap.set/get_pack_heat_ramp`, `get_pack_heat_ramp_colors` |

Persisted in `_map_prefs.json` (`v: 3`) as `pack_heat_ramp` + save key.

## Library layout presets

| Id | Panel | Panes |
|----|-------|-------|
| `standard` | 600×560 | tree + left + right |
| `compact` | 480×440 | hide tree, shorter lists |
| `wide` | 840×600 | all panes, tall lists |
| `left` | 640×560 | hide right pane |

UI: **Layout** OptionButton at top of library. Persisted as `pack_library_layout`.

## Bulk chip multi-select

| Action | How |
|--------|-----|
| Add/remove | **Ctrl/Meta+click** tag or group chip (orange highlight) |
| Menu | Context **Bulk (B)** |
| **Bulk Filt** | Push bulk set into active filters |
| **Bulk Asg** | Tag Left packs with all bulk tags; group to first bulk group |
| **Bulk Clr** | Clear bulk set (Shift also strips from active filters) |

Counter: `Bulk · N` on tag cloud header.

## Code

| File | Change |
|------|--------|
| `MapMinimap.gd` | Heat ramp colors in draw |
| `MapRenderer.gd` | Prefs v3, native dialogs, layout, bulk UI |

## Limits / Pass 49 ideas

- Native dialogs may fall back when headless / no display.  
- Bulk Asg uses first group only when multiple groups bulk-selected.  
- Pass 49 candidates: heat ramp custom cool/hot colors, library layout keyboard chords, bulk OR/AND mode, pin-focus from bulk.
