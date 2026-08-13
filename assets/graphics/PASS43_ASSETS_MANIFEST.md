# Asset Pass 43 — Grp OR · Tree multi bulk · Minimap heat · Hist ★ pin

Skills: `game-asset-core` · `game-ui-icons`

## OR group chips

| UI | **Grp OR** checkbox on group chips row |
|----|---------------------------------------|
| Off | Multiple `@group:` tokens AND (match all) |
| On | Injects `@groupor`; match any selected group |
| Tree multi | Auto-enables Grp OR when ≥2 groups selected |

Filter API collects group keys separately and applies OR/AND.

## Tree multi-select bulk group

- Group tree: `SELECT_MULTI`  
- Multi-select groups → active chips (OR filter)  
- **Assign Sel** → move multi-selected Left packs into first selected tree group  
- Double-click still fills group field  

## Heatmap overlay on minimap

- Soft concentric heat discs under pack pins (risk → cool/hot)  
- Toggle API: `set_show_pack_risk_heat` / `get_show_pack_risk_heat`  
- Default **on** when pins present  
- Drawn under polylines/pins  

## History pin favorites

| UI | **★ Hist** pins current search |
|----|--------------------------------|
| History list | `★` prefix for pinned entries |
| Shift+History | Toggle pin on that entry |
| Clr Hist | Keeps pinned (Shift+Clr clears all) |
| Cap | Unpinned capped at 12; pinned never dropped |

History format v2: `{ queries: [{q, pinned}] }` (legacy strings still load).

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Group OR, tree multi, history pins |
| `MapMinimap.gd` | Risk heat overlay under pins |

## Limits / Pass 44 ideas

- Group OR does not apply to free-text tokens.  
- Minimap heat is pin-centered discs (not exported PNG).  
- Pass 44 candidates: minimap heat toggle on compare card, history search box, group chip counts live, tree drag multi-move. **Done — see PASS44_ASSETS_MANIFEST.md.**
