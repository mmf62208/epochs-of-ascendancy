# Asset Pass 34 — Pack legend · Slot reorder · QR auto-size · Share file

Skills: `game-asset-core` · `game-ui-icons`

## Pack pin legend

| Surface | Behavior |
|---------|----------|
| Minimap | Bottom-left swatches: label·routeCount per filled slot |
| Compare card | “Pack pins (minimap)” row with color swatches |

- Colors match multi-pin slot palette (cyan / magenta / amber / green)  
- Updated on save / load / merge / reorder  

## Slot drag-reorder

- **Reorder** row on compare card: `◀N` / `N▶` per filled slot  
- Swaps adjacent slots (data + labels + day-history tracks)  
- Left = higher merge priority (slot-weighted score)  
- Minimap pins/legend refresh after move  

API: `swap_route_compare_slots`, `move_route_compare_slot`

## EORP3 QR auto module size

| Setting | Value |
|---------|-------|
| Target outer side | ~248 px |
| `module_px ≤ 0` | auto via `RoutePackQR.auto_module_px` |
| Clamp | 2–10 px/module |
| CLI fallback | scale 4–6 by payload length |

Larger packs (v11–20) stay scannable in the popup without blowing past the panel.

## Share to file

| Action | Path / behavior |
|--------|-----------------|
| **File** button | Write `user://route_pack_share.eorp` + clipboard |
| **Shift+Import** | Load that file into pack compare |

API: `export_route_pack_share_file`, `import_route_pack_share_file`

## Code

| File | Change |
|------|--------|
| `RoutePackQR.gd` | Auto module size |
| `MapRenderer.gd` | Legend, reorder, file share, QR auto |
| `MapMinimap.gd` | Legend draw + set_pack_legend |

## Limits / Pass 35 ideas

- Reorder is adjacent swap only (no free drag onto empty slot UI yet).  
- Legend labels truncate to 5 chars on minimap.  
- Share file is single fixed path (no multi-slot browser).  
- Pass 35 candidates: free-slot drag-drop, multi-file pack library, QR in share toast, legend click → load. **Done — see PASS35_ASSETS_MANIFEST.md.**
