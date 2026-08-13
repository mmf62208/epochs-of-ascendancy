# Asset Pass 29 — User templates · Named pack slots · Filter save · Auto pack

Skills: `game-asset-core` · `game-ui-icons`

## User-saved counter templates

Diplomacy counter dialog:

- **Save template** — name + current guarantee / CRS / note  
- Stored in `user://alliance_counter_templates.json` (max 8)  
- User templates show ★ prefix; **Shift+click** deletes  
- Same label replaces existing user template  

## Named pack slot labels

Compare card:

- **Name** field applies when you **S1–S4** save  
- Load buttons show short label (`L:name`)  
- Labels persist in `map_ui.route_compare_slot_labels`  

## Munitions filter in save

`map_ui` now includes:

- `munitions_occupation_filter` (`all` | `occupied` | `mine`)  

Restored on load via `_on_munitions_occupation_filter_changed`.

## Auto pack from open routes

Compare card **Auto pack**:

- Ranks live `SupplyManager.get_all_routes()` by interdiction (then hops)  
- Builds A–D compare (2–4 routes) via `compare_supply_routes_multi`  
- Toast reports route count  

## Code

| File | Change |
|------|--------|
| `DiplomacyView.gd` | User template save/load/delete |
| `MapRenderer.gd` | Slot labels, auto pack, filter in save |

## Limits / Pass 30 ideas

- User templates are local-only (not in campaign save).  
- Auto pack ignores player ownership of routes.  
- Slot labels max ~8 chars on buttons.  
- Pass 30 candidates: campaign-shared templates, auto pack player routes only, slot pin to minimap, pack share codes. **Done — see PASS30_ASSETS_MANIFEST.md.**
