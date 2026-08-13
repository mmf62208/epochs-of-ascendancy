# Asset Pass 36 — Library search · Tags · Dual-pane compare · Legend tooltips

Skills: `game-asset-core` · `game-ui-icons`

## Library search / filter

- Search field filters by **name**, **note**, or **tag** tokens  
- `#safe` matches tags only; bare `east` matches name/note/tags  
- Multiple space-separated tokens are AND  

API: `list_route_pack_library(query)`, `filter_route_pack_library`

## Pack tags

| Store | `user://route_packs/_tags.json` |
|-------|----------------------------------|
| Shape | `{ stem: { tags: [], note: "" } }` |
| Save | Optional tags field on library Save |
| Tag L | Apply tags field to Left selection |
| Delete | Removes tags entry with pack file |

API: `set/get_route_pack_library_tags`, `_parse_pack_tags`

## Dual-pane library compare

| Pane | Role |
|------|------|
| Left | Routes → compare **A/B** |
| Right | Routes → compare **C/D** |

- Peek line shows risk%/hops for selected L and R  
- **Compare L|R** builds multi-route pack without serial load  
- **Load L** / double-click still loads single pack  

API: `peek_route_pack_library`, `compare_library_packs`, `_decode_route_pack_share_payload`

## Minimap legend tooltips

- Hover legend row → Control tooltip with slot risks/hops  
- Legend entries carry `tooltip` from `get_pack_slot_legend`  
- Click still loads slot (Pass 35)  

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Tags, filter, peek, dual compare, Lib UI |
| `MapMinimap.gd` | Legend hover tooltips |

## Limits / Pass 37 ideas

- Tags are flat strings (no hierarchy).  
- Dual compare uses only path A/B from each pack (not C/D of source packs).  
- Legend tooltips need mouse over minimap (no delayed rich panel).  
- Pass 37 candidates: tag cloud chips, library sort modes, pack notes editor, pin hover tooltips. **Done — see PASS37_ASSETS_MANIFEST.md.**
