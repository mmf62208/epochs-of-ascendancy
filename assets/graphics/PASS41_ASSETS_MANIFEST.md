# Asset Pass 41 — Nested groups · Drag-to-group · Heatmap · Search history

Skills: `game-asset-core` · `game-ui-icons`

## Nested groups

- Group paths: `theater/east/coast` (allow `/`)  
- Depth-aware sort headers: `▸ east` under parent  
- Pack rows indented under group  
- Filter `@group:theater` matches nested children  
- API: `_group_depth`, `_group_parent_path`, `_group_is_under`  

## Drag pack between groups

- Drag selected pack(s) from Left list  
- Drop on group header (`group:path` metadata) or onto another pack (inherits group)  
- Uses `bulk_group_route_pack_library`  
- Toast: `Move → path · N pack(s)`  

## Risk heatmap export

| Button | **Heat** |
|--------|----------|
| Output | `user://route_risk_heatmap.png` (256² default) |
| Source | Current pack pin positions + risk  
| Preview | Reuses Pack QR popup shell  

API: `export_route_pack_risk_heatmap(path, side)`

## Library search history

| UI | **History…** OptionButton next to search |
|----|------------------------------------------|
| Store | `user://route_packs/_search_history.json` |
| Cap | 12 recent queries (deduped) |
| Trigger | Enter / submit on search field  

API: `load_route_pack_search_history`, `push_route_pack_search_history`

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Nested groups, drag, heatmap, history |

## Limits / Pass 42 ideas

- Drag requires Sort=Group for visible headers (drop on pack still works).  
- Heatmap is scatter blobs, not geo-projected.  
- History is local only.  
- Pass 42 candidates: group tree panel, heatmap geo bounds from MapManager, history clear, sync group chips. **Done — see PASS42_ASSETS_MANIFEST.md.**
