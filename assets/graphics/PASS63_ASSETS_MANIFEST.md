# Asset Pass 63 — RS correct · Robust sample · AC hover · QR strips

Skills: `game-asset-core` · `game-ui-icons`

## Reed-Solomon error correction

| Where | `RoutePackQR._rs_correct_block` after deinterleave |
|-------|-----------------------------------------------------|
| Algo | Syndromes → Berlekamp–Massey → Chien → Forney |
| Fallback | Raw data block if correction fails (clean PNGs) |

Noise cluster flip test: still decodes payload.

## Robust QR sampling

| Adaptive | Mean-luma threshold (`_adaptive_luma_thresh`) |
|----------|-----------------------------------------------|
| Phase | Module sample phase 0.35 / 0.5 / 0.65 |
| Early out | Stop when finder score ≥ 0.92 |

## Theme autocomplete hover ↔ keyboard

| Signal | `id_focused` updates highlight index |
|--------|--------------------------------------|
| Mouse | PopupMenu motion ≈ maps Y → item + `set_focused_item` |

↑↓ Enter still uses the same index.

## Batch QR strip export

| API | `export_library_theme_qr_strip_png` · `export_library_chrome_qr_strip_png` |
|-----|----------------------------------------------------------------------------|
| Paths | `user://library_theme_qr_strip.png` · `user://library_chrome_qr_strip.png` |
| UI | **Ctrl+Shift+Thr↗** theme strip · **Ctrl+Shift+Snap↗** chrome strip (win 1–2 + current) |

Strip is a dark panel of nearest-neighbor resized QRs (optional color key bar per theme).

## Code

| File | Change |
|------|--------|
| `scripts/ui/RoutePackQR.gd` | RS correct, adaptive sample phases |
| `scripts/map/MapRenderer.gd` | AC hover sync, QR strip export APIs/UI |

## Limits / Pass 64 ideas

- True perspective unwarp for camera photos.  
- Strip labels as real bitmap font glyphs.  
- Optional export strip without clipboard side-effects.  
- Per-block RS stats toast on noisy import.  
