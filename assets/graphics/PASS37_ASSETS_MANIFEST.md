# Asset Pass 37 — Tag cloud · Sort modes · Notes editor · Pin tooltips

Skills: `game-asset-core` · `game-ui-icons`

## Tag cloud chips

- **HFlowContainer** of toggle chips under search  
- Label `#tag ·count` from `list_all_pack_library_tags`  
- Click toggles `#tag` tokens in the filter field  
- Active chips re-highlighted after list refresh  

## Library sort modes

| Option | Order |
|--------|--------|
| Newest | mtime desc (default) |
| Name | A→Z |
| Size | bytes desc |
| Tags | tag count desc |

API: `sort_route_pack_library`, `list_route_pack_library(query, sort_mode)`

## Pack notes editor

- **TextEdit** notes panel in Lib popup  
- Selecting Left pack loads note + tags into editors  
- **Save** writes note with pack  
- **Tag+Note L** updates tags and note for Left selection  
- List rows show `✎` when a note exists  

API: `set_route_pack_library_note`

## Pin hover tooltips

- Each pack pin carries `tooltip` (slot, route letter, hops, risk, owner)  
- Minimap hover: pin hit first, then legend  
- Uses Control `tooltip_text` on the draw area  

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Sort, tag cloud, notes, pin tooltips, Lib UI |
| `MapMinimap.gd` | Pin + legend hover tooltips |

## Limits / Pass 38 ideas

- Tag cloud rebuilds on every filter keystroke (fine for small libraries).  
- Notes are plain text only (no markdown).  
- Pin tooltips share Control tooltip (no custom delayed panel).  
- Pass 38 candidates: library favorites/star, export library index, multi-tag AND chips UI polish, route pin risk color intensity. **Done — see PASS38_ASSETS_MANIFEST.md.**
