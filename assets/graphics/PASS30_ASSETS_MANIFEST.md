# Asset Pass 30 — Campaign templates · Player auto pack · Pack pins · Share codes

Skills: `game-asset-core` · `game-ui-icons`

## Campaign-shared counter templates

- **Save campaign** in Counter dialog → `RelationsManager.campaign_counter_templates`  
- Persists in save key `relations.campaign_counter_templates`  
- ◆ prefix chips; Shift+click deletes  
- Parallel to local ★ user templates (`user://`)  

## Auto pack · player only

Compare card **Mine** checkbox on **Auto pack**:

- Keeps routes where ≥50% of provinces are player-controlled (controller else owner)  

## Pack slot pins on minimap

- Filled pack slots draw labeled pins at route-A midpoint  
- Click pin → `load_route_compare_slot`  
- Refreshed on save/load/auto/import  

## Pack share codes

| Action | Format |
|--------|--------|
| **Share** | `EORP1.` + base64 JSON of A–D paths + risks → clipboard |
| **Import** | Parse clipboard code → multi-route compare |

## Code

| File | Change |
|------|--------|
| `RelationsManager.gd` | Campaign templates API + save |
| `DiplomacyView.gd` | Save local / Save campaign |
| `MapRenderer.gd` | Auto pack filter, share codes, pin data |
| `MapMinimap.gd` | Draw + click pack pins |

## Limits / Pass 31 ideas

- Share codes omit day-history samples (paths + risks only).  
- Player-only path filter is majority control, not route owner tag.  
- Pins use route A midpoint only.  
- Pass 31 candidates: share with history, route owner field, multi-pin per pack, QR export. **Done — see PASS31_ASSETS_MANIFEST.md.**
