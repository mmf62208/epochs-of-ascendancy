# Asset Pass 35 — Drag-drop · Pack library · Share+QR toast · Legend click

Skills: `game-asset-core` · `game-ui-icons`

## Free-slot drag-drop

- Drag filled **S#** or **Load** buttons onto another S#/Load target  
- Calls `move_route_compare_slot` (bubble-swap)  
- Empty Load targets accept drops (re-order into empty index)  
- ◀/▶ reorder row still available  

## Multi-file pack library

| API | Behavior |
|-----|----------|
| `list_route_pack_library` | `user://route_packs/*.eorp` by mtime |
| `save_route_pack_to_library(name)` | EORP3 write + mirror default share file |
| `load_route_pack_from_library` | By stem or path |
| `delete_route_pack_from_library` | Remove entry |

UI: **Lib** button → popup (name field, list, Save / Load / Delete / double-click load).

## QR preview in share toast

- **Share** copies EORP3 + opens compact **ShareQRToast** (code length + 140px QR)  
- Auto-dismiss ~6s; also writes `user://route_pack_qr.png`  
- Debug toast: `Share EORP3 · N chars + QR`  

## Legend click → load slot

| Surface | Action |
|---------|--------|
| Minimap legend | Click swatch/label row → `load_route_compare_slot` |
| Compare card | Clickable legend buttons (same) |

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Library, share+QR toast, drag-drop, Lib UI |
| `MapMinimap.gd` | Legend hit rects + click load |

## Limits / Pass 36 ideas

- Library is flat directory (no folders/tags).  
- Drag-drop requires mouse; no keyboard move.  
- Share toast QR uses same auto-size encoder as full QR.  
- Pass 36 candidates: library search/filter, pack tags, dual-pane compare of library packs, minimap legend tooltips. **Done — see PASS36_ASSETS_MANIFEST.md.**
