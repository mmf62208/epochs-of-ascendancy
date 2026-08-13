# Asset Pass 64 — Clipboard-safe strips · Bitmap labels · RS toast · Mild unwarp

Skills: `game-asset-core` · `game-ui-icons`

## Clipboard-safe share export

| API | `export_library_theme_share_code(id, to_clipboard=true)` |
|-----|----------------------------------------------------------|
| API | `export_library_chrome_share_code(window, to_clipboard=true)` |
| Strip | Calls with `to_clipboard=false` so multi-QR strips don’t clobber clipboard |

Single Thr↗ / Snap↗ still copy as before.

## Bitmap labels on QR strips

| Font | 3×5 pixel glyphs a–z 0–9 `_` `-` `.` space |
|------|---------------------------------------------|
| API | `_blit_bitmap_label` / `_bitmap_glyph_3x5` |
| Theme strip | Cyan-ish labels under each cell |
| Chrome strip | Amber labels `winN theme` |

Truncates long ids with `…`.

## RS stats on noisy import

| API | `RoutePackQR.get_last_decode_stats()` · `get_last_qr_decode_stats()` |
|-----|----------------------------------------------------------------------|
| Fields | `blocks`, `blocks_clean`, `blocks_corrected`, `blocks_raw_fallback`, `ok`, `source` |
| Toast | On QR import when corrected or raw-fallback > 0: `QR RS · fixed N · raw M · blocks B` |

Attached to import result as `rs`.

## Mild sampling unwarp

| Anisotropic | Independent module px X/Y from content bbox |
|-------------|----------------|
| Shear | ±0.04 (and 0) trial shears for mild trapezoid |
| Prior | Adaptive threshold + phase 0.35/0.5/0.65 (Pass 63) |

## Pass 63 (already shipped)

Confirmed complete: RS correction, robust sample phases, AC hover sync, QR strip export.

## Code

| File | Change |
|------|--------|
| `scripts/map/MapRenderer.gd` | Clipboard flag, bitmap labels, RS toast wiring |
| `scripts/ui/RoutePackQR.gd` | Decode stats, anisotropic/shear sampling |

## Limits / Pass 65 ideas

- Full homography from finder corners.  
- Variable-scale strip labels (2× glyphs when cell is wide).  
- Optional RS stats always-on verbose mode.  
