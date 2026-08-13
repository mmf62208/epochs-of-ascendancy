# Asset Pass 53 — Pulse ramp tint · Bulk import · Per-window dock · Ramp strip

Skills: `game-asset-core` · `game-ui-icons`

> Note: Implemented with Pass 54 in the same landing (user requested Pass 54 after 52).

## Pulse tint from heat ramp

Pin focus rings use `MapMinimap.get_pack_heat_ramp_colors()` cool→hot instead of fixed cyan/amber.

## Bulk import from clipboard

| UI | **Bulk Imp** |
|----|--------------|
| Default | Union merge into shared bulk |
| Shift | Replace bulk |
| Parses | `tags=`, `groups=`, free `#tag` / `@group:` tokens |

API: `import_route_pack_bulk_clipboard(text, merge_mode)` → `{ok, tags, groups, total, mode}`.

## Per-window dock

| Storage | `pack_library_docks` map `{"1":"left","2":"right"}` |
|---------|-----------------------------------------------------|
| API | `get/set_library_dock_for_window(idx, dock)` |
| Open | Secondary **Shift+Lib** windows restore their own dock |

## Ramp preview strip

Compare card cool→hot gradient control next to ↻/↺; click cycles ramp (Shift = prev).

## Prefs

`_map_prefs.json` **v7** adds `pack_library_docks`, `pack_library_opacity`.
