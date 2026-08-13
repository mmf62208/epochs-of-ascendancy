# Asset Pass 38 — Favorites · Library index · AND chips · Risk pin color

Skills: `game-asset-core` · `game-ui-icons`

## Library favorites / star

| UI | Behavior |
|----|----------|
| **★ Fav L** | Toggle favorite on Left selection |
| List rows | `★ ` prefix when favorited |
| Sort **★ Fav** | Favorites first, then mtime |
| Preview | Shows `★ favorite` when selected |

Stored in `_tags.json` per stem: `{ tags, note, favorite }`.

API: `set/is/toggle_route_pack_library_favorite`

## Export library index

| Button | **Index** |
|--------|-----------|
| JSON | `user://route_packs/_index.json` (v1, packs array) |
| CSV | `_index.csv` — name,bytes,mtime,favorite,tags,note |

API: `export_route_pack_library_index`

## Multi-tag AND chips polish

- Header: “Tag cloud · multi = AND”  
- **Clear tags** clears all active chips  
- AND hint line: `AND: #a ∩ #b` when ≥2 chips  
- Multi-active chips gold-modulated; tooltips explain AND  
- Filter still AND-matches all `#tag` tokens  

## Route pin risk color intensity

- Pin color lerps toward hot red by interdiction risk  
- Minimap: larger radius, hotter ring, core flash when risk ≥ 55%  
- Polylines use same risk-tinted color  
- Pin data includes `risk`, `base_color`, `color`  

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Favorites, index export, chip polish, risk pin color |
| `MapMinimap.gd` | Risk-intensity pin draw |

## Limits / Pass 39 ideas

- Favorites are local to tags sidecar (not in share codes).  
- Index export is full snapshot (no incremental).  
- Risk intensity uses stored pack risk (live recompute only after load).  
- Pass 39 candidates: favorites-only filter chip, import index merge, risk legend scale, pack bulk tag. **Done — see PASS39_ASSETS_MANIFEST.md.**
