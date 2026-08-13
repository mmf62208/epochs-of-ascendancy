# Asset Pass 61 — QR image import · EOCS1 v2 · Theme autocomplete

Skills: `game-asset-core` · `game-ui-icons`

## Decode theme/chrome QR from image

| API | `decode_qr_payload_from_image(path)` |
|-----|--------------------------------------|
| Tool | `zbarimg -q --raw` (system CLI) |
| Prefer | Payload lines starting `EOTM1.` / `EOCS1.` / `EORP*` |
| Import | `import_library_share_from_qr_image(path, window_idx)` routes EOCS1/EOTM1 |
| UI | **QR↙** native file dialog (PNG/JPEG) → apply chrome import |

Fails gracefully with `{ok:false, error:"no_qr"}` if zbarimg missing or no code.

## EOCS1 v2 — layout + pin SFX

| Field | Source |
|-------|--------|
| `layout` | `get/set_library_layout` (standard/compact/wide/left) |
| `pin_sfx` | mute flag |
| `pin_sfx_db` | volume dB |
| `pin_sfx_bus` | AudioServer bus name |

Payload `v: 2`. Older snaps without keys keep current SFX prefs.

**Snap↗** still exports clipboard + Shift QR; import applies layout live via `apply_lib_layout_ref`.

## Theme name autocomplete

| API | `list_library_theme_id_matches(query, max_n=16)` |
|-----|--------------------------------------------------|
| UI | PopupMenu under theme id LineEdit on focus / text change |
| Pick | Fills name, selects Theme dropdown, applies chrome |

Built-ins first, then custom presets from `_library_themes.json`.

## Code

| File | Change |
|------|--------|
| `scripts/map/MapRenderer.gd` | QR decode/import, layout getters, EOCS1 v2, autocomplete, QR↙ UI |

## Limits / Pass 62 ideas

- Pure-GDScript QR decoder (no zbarimg).  
- Live pin SFX UI refresh when chrome import sets bus/volume.  
- Autocomplete keyboard nav (↑↓ Enter) beyond PopupMenu defaults.  
- Batch import multiple QR images.  
