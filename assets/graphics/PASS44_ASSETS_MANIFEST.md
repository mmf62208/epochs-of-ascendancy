# Asset Pass 44 — Heat toggle · Hist search · Live chip counts · Tree drop multi-move

Skills: `game-asset-core` · `game-ui-icons`

## Minimap heat toggle on compare card

| UI | **Heat map** checkbox on route compare card (name row) |
|----|--------------------------------------------------------|
| Action | `MapMinimap.set_show_pack_risk_heat` |
| Default | Reads current minimap state (default on) |

## History search box

| UI | **hist…** LineEdit before History… |
|----|------------------------------------|
| Action | Filters history dropdown by substring (live) |
| Pinned | ★ entries still listed when matching |

## Live group chip counts

- Chip counts use **base filter** (text + tags + ★) **without** group tokens  
- Shows how many packs would remain under each group path in current search  
- Zero-count chips dimmed  
- Tooltips include “in current view (live)”  

## Tree drag multi-move

- Drag selected Left packs onto **Groups** tree node  
- Drops reassign all dragged packs into that group (or ungrouped on All)  
- Tree can also start drag from selected packs  
- Complements list header drop (Pass 41)  

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Heat chk, hist search, live counts, tree drop |
| `MapMinimap.gd` | (existing heat API; no new API this pass) |

## Limits / Pass 45 ideas

- Live counts re-list library twice per filter keystroke.  
- Tree drop uses `get_item_at_position` (padding sensitivity).  
- Pass 45 candidates: debounced live counts, heat intensity slider, history export, group chip right-click assign. **Done — see PASS45_ASSETS_MANIFEST.md.**
