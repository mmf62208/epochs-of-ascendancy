# Asset Pass 60 — Theme name · Theme/Chrome QR · Pulse L/R · EOCS1 chrome snap

Skills: `game-asset-core` · `game-ui-icons`

## Typed theme name

| UI | LineEdit **theme id** next to Save Theme |
|----|------------------------------------------|
| Sanitize | `_sanitize_library_theme_id` — a–z 0–9 `_` `-`, max 32 |
| Save | Uses typed id when non-empty; else current theme |
| Shift+Save | `custom_<rrggbb>` only when name field empty |

Dropdown select and imports fill the name field.

## Theme share QR

| API | `export_library_theme_share_qr_png(theme_id)` |
|-----|-----------------------------------------------|
| Path | `user://library_theme_qr.png` via `RoutePackQR` |
| UI | **Shift+Thr↗** → QR popup titled "Theme QR" |

Payload remains **EOTM1** theme share code.

## Pack-select pulse L/R + stagger

| API | `pulse_item_list_selection(list, duration, pulse_col, stagger)` |
|-----|----------------------------------------------------------------|
| Left | Cyan `(0.35, 0.95, 1.0, 0.55)` |
| Right | Magenta `(1.0, 0.45, 0.85, 0.55)` |
| Multi | `stagger` 0.035–0.04s cascades selected rows |

## Full chrome snapshot (EOCS1)

| Format | `EOCS1.<base64url(json)>` |
|--------|---------------------------|
| Payload | theme, modulate, title, dock, opacity (+ window hint) |
| API | `export/import_library_chrome_share_code`, `export_library_chrome_share_qr_png` |
| UI | **Snap↗** copy · **Ctrl/Alt+Snap↗** import · **Shift+Snap↗** chrome QR |
| Import | Upserts theme colors, sets per-window theme/dock/α, applies live |

Import also accepts **EOTM1** (theme-only fallback).

QR path: `user://library_chrome_qr.png`.

## Code

| File | Change |
|------|--------|
| `scripts/map/MapRenderer.gd` | Name field, QR export, EOCS1 chrome, pulse color/stagger, QR popup title |
| `scripts/ui/RoutePackQR.gd` | Reused (no API change) |

## Limits / Pass 61 ideas

- Scan/decode theme QR from image file.  
- Layout preset in EOCS1 snapshot.  
- Pin SFX prefs in chrome snap.  
- Theme name autocomplete from presets.  
