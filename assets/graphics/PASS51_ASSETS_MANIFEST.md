# Asset Pass 51 — Dock · Soft pin zoom · Shared bulk · Swatch cycle

Skills: `game-asset-core` · `game-ui-icons`

## Dockable library

| Mode | Placement |
|------|-----------|
| `float` | Centered free window (default) |
| `left` / `right` | Center-left / center-right strip |
| `bottom` | Center-bottom strip |

| UI | **Dock** OptionButton on layout row |
|----|--------------------------------------|
| Drag | Drag title bar to move (undocks to float) |
| Snap | Drop near left / right / bottom edge → dock |
| Persist | `pack_library_dock` in prefs `v: 6` |

API: `_apply_library_dock_layout(control, dock, w, h, shift)`

## Pin focus zoom modes

| Modifier | Zoom |
|----------|------|
| (none) | **soft** — half-lerp toward tactical |
| **Ctrl** | **tactical** — full close zoom |
| **Alt** | **keep** — pan only, keep current zoom |
| **Shift** | Lowest risk first (unchanged) |

`focus_province_by_id(id, zoom_mode)` and `focus_pack_pin_by_risk_info(..., zoom_mode)`.

## Shared bulk across library windows

| API | Role |
|-----|------|
| `get/set_route_pack_bulk_selection` | Shared `[{kind,value}]` |
| `toggle_route_pack_bulk_chip` | Toggle + notify |
| `clear_route_pack_bulk_selection` | Clear all windows |
| `register/unregister_route_pack_bulk_watcher` | Live sync |

Ctrl+click bulk in any `PackLibraryPopup` / `_N` updates all open libraries.

## Click heat swatch → cycle ramp

| Where | Minimap top-right swatch |
|-------|--------------------------|
| Click | Next ramp (`classic→inferno→viridis→mono→custom→…`) |
| Shift+click | Previous ramp |
| Label | Shows ramp id + `click ↻` |

API: `MapRenderer.cycle_pack_heat_ramp(dir)` (persists prefs).

## Code

| File | Change |
|------|--------|
| `MapMinimap.gd` | Swatch hit-test + cycle |
| `MapRenderer.gd` | Dock, shared bulk, zoom modes, cycle API |

## Limits / Pass 52 ideas

- Float drag uses top-left anchors; size restore after undock is approximate.  
- Shared bulk does not share Left list multi-selection.  
- Pass 52 candidates: dock keyboard chords, pin focus pulse marker, bulk export clipboard, ramp cycle from compare card.
