# Asset Pass 46 — Heat prefs · Hist import · Chip menu · Filter progress

Skills: `game-asset-core` · `game-ui-icons`

## Persisted heat preferences

| Key | Storage |
|-----|---------|
| `pack_risk_heat_show` | `user://route_packs/_map_prefs.json` + save `map_ui` |
| `pack_risk_heat_intensity` | same |

| API | Role |
|-----|------|
| `load_pack_risk_heat_prefs` | Read prefs file |
| `save_pack_risk_heat_prefs` | Write prefs file |
| `_apply_pack_risk_heat_prefs` | Push to minimap |
| `apply_stored_pack_risk_heat_prefs` | Deferred after minimap bind |

Heat checkbox + intensity slider save on change; save/load restores via `get/apply_save_data`.

## History import

| UI | **Imp Hist** next to **Exp Hist** |
|----|-----------------------------------|
| Default | Union merge from `_search_history_export.json` |
| Shift+click | Replace mode |
| API | `import_route_pack_search_history(path, merge_mode)` |

Returns `{ok, imported, skipped, path, mode, total}`. Pins preserved on union conflict.

## Chip context menu

Right-click **tag** or **group** chips → `PopupMenu`:

| Item | Action |
|------|--------|
| **Filter** | Toggle chip in active filter set |
| **Assign** | Group packs (group chip) or bulk-tag (tag chip) from Left selection |
| **Copy** | Clipboard `#tag` or `@group:path` |
| **Clear** | Remove this chip (or clear all of kind if inactive) |

Replaces Pass 45 immediate RMB assign with a full menu (Assign still available).

## Filter progress indicator

| UI | Label on filter row |
|----|---------------------|
| Pending | `Updating…` (gold) while debounce timer runs |
| Done | Cleared when `fill_lists` finishes |

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Prefs, import UI, chip PopupMenu, filter status |
| `MapMinimap.gd` | (unchanged APIs from Pass 45) |

## Limits / Pass 47 ideas

- Chip menu does not support multi-chip batch clear from one click (Clear on inactive clears kind).  
- Imp Hist only reads default export path (no file dialog).  
- Pass 47 candidates: file dialog for hist import/export, chip menu keyboard shortcuts, heat legend opacity, filter cancel token UI.
