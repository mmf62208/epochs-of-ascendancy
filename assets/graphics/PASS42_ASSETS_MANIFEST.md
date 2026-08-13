# Asset Pass 42 — Group tree · Geo heatmap · Clear history · Group chips

Skills: `game-asset-core` · `game-ui-icons`

## Group tree panel

- Left column **Tree** in Lib popup: nested groups + counts  
- Click: filter `@group:path` (single-select focus)  
- **All packs** clears group filters  
- **∅ ungrouped** filters empty group  
- Double-click: copies path into group field  

## Heatmap geo bounds (MapManager)

| Priority | Bounds source |
|----------|----------------|
| 1 | `MapManager.get_world_bounds()` |
| 2 | `MapCanvasConfig.WORLD_CANONICAL_BOUNDS` |
| 3 | Pin hull + pad |

Pins map into full world rect so heatmap aligns with map space.

API: `_heatmap_world_bounds`, updated `export_route_pack_risk_heatmap`

## History clear

| UI | **Clr Hist** next to History… |
|----|-------------------------------|
| API | `clear_route_pack_search_history()` |
| File | Resets `_search_history.json` to empty list |

## Sync group chips

- **Group chips** row under tag cloud  
- Toggle chips for each group path (+ **∅** ungrouped)  
- Active chips inject `@group:path` into filter (AND with tags/★)  
- **Clear tags** also clears group chips  
- Tree click keeps chips in sync via same active list  

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Tree, group chips, clear history, geo heatmap |

## Limits / Pass 43 ideas

- Tree rebuild is O(groups × packs) (fine for small libraries).  
- Multiple group chips AND (pack must match every selected group path).  
- Pass 43 candidates: OR group chips, tree multi-select bulk group, heatmap overlay on minimap, history pin favorites. **Done — see PASS43_ASSETS_MANIFEST.md.**
