# Asset Pass 45 — Debounced filter · Heat intensity · Hist export · Chip RMB assign

Skills: `game-asset-core` · `game-ui-icons`

## Debounced live counts / filter

- Library search `text_changed` waits **~180ms** before `fill_lists`  
- Enter / submit still refreshes **immediately**  
- Avoids double library scan on every keystroke  

## Heat intensity slider

| UI | HSlider next to **Heat** on compare card |
|----|------------------------------------------|
| Range | 0.0–2.0 (step 0.05) |
| Effect | Scales heat disc radius + alpha |
| API | `MapMinimap.set/get_pack_risk_heat_intensity` |

## History export

| UI | **Exp Hist** on library filter row |
|----|------------------------------------|
| JSON | `user://route_packs/_search_history_export.json` |
| CSV | `_search_history_export.csv` (query, pinned) |

API: `export_route_pack_search_history`

## Group chip right-click assign

- **Right-click** group chip → assign multi-selected Left packs into that group  
- Right-click **∅** → ungroup selected packs  
- Toast: `Chip assign · N → path`  

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Debounce, hist export, chip RMB, heat slider |
| `MapMinimap.gd` | Heat intensity |

## Limits / Pass 46 ideas

- Debounce timer is fire-and-forget (gen token cancels stale).  
- Heat slider not persisted across sessions.  
- Pass 46 candidates: persist heat prefs, history import, chip context menu, filter progress indicator.
