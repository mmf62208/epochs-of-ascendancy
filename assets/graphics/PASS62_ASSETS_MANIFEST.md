# Asset Pass 62 — Engine QR decode · Pin SFX refresh · AC keys · Batch QR

Skills: `game-asset-core` · `game-ui-icons`

## Pure-GDScript QR decoder

| API | `RoutePackQR.decode_from_image` / `decode_from_path` / `decode_from_matrix` |
|-----|----------------------------------------------------------------------------|
| Scope | Byte mode, ECC M, versions 1–20 (matches encoder) |
| Flow | Sample modules → unmask → deinterleave data → parse UTF-8 |
| Map | `decode_qr_payload_from_image` tries **engine first**, then `zbarimg` |

Optimized for clean engine PNGs (high contrast, quiet zone). Roundtrip verified for EOTM1/short/EOCS1-ish payloads.

## Pin SFX UI refresh

| API | `register_pin_sfx_ui_watcher` / `notify_pin_sfx_ui_refresh` |
|-----|--------------------------------------------------------------|
| Wire | Compare-card mute / volume / bus re-sync on EOCS1 import |
| When | `import_library_chrome_share_code` touches pin_sfx* keys |

Uses `set_pressed_no_signal` / `set_value_no_signal` to avoid feedback loops.

## Theme autocomplete keyboard

| Keys | ↓ / ↑ cycle · Enter apply · Esc hide |
|------|--------------------------------------|
| State | Highlight index + last match list |

## Batch QR import

| API | `import_library_shares_from_qr_images(paths, window_idx)` |
|-----|-----------------------------------------------------------|
| UI | **Shift+QR↙** multi-file dialog · last success applies chrome |
| Toast | `QR batch · ok/total` |

## Code

| File | Change |
|------|--------|
| `scripts/ui/RoutePackQR.gd` | Pass 62 pure decoder |
| `scripts/map/MapRenderer.gd` | Engine-first decode, SFX watchers, AC keys, batch QR |

## Limits / Pass 63 ideas

- RS error correction on damaged QR scans.  
- Perspective/warped photo sampling.  
- Autocomplete mouse hover sync with keyboard index.  
- Export batch QR strip sheet.  
