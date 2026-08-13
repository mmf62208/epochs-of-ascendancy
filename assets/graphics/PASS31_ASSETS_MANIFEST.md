# Asset Pass 31 — Share+history · Route owner · Multi-pin · QR export

Skills: `game-asset-core` · `game-ui-icons`

## Share codes with history (EORP2)

| Version | Contents |
|---------|----------|
| EORP1 | Paths A–D + risks + owners |
| EORP2 | EORP1 + day-history samples `ha`–`hd` |

- **Hist** checkbox on compare card (default on)  
- Import restores samples into `_route_risk_day_history["last"]`  

## Route owner field

- Auto pack **Owner** LineEdit filters `SupplyRoutePlan.owner_tag`  
- Metas carry `owner_tag`; card lines show `· USA` etc.  
- Share payload includes `oa`–`od`  

## Multi-pin per pack

- Each saved slot emits pins for routes A–D midpoints  
- Fan-out offset; primary (A) larger  
- Labels `name·A` …; click any pin loads the slot  

## QR export

- **QR** button → `qrencode` → `user://route_pack_qr.png`  
- Popup TextureRect preview  
- Falls back to EORP1 if EORP2 payload too large  

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | EORP2, owner filter, multi-pin, QR |
| `MapMinimap.gd` | Multi-pin draw |

## Limits / Pass 32 ideas

- QR needs system `qrencode`.  
- Owner filter exact match only.  
- Multi-pin fan is fixed world offset (not geodesic).  
- Pass 32 candidates: in-engine QR (no CLI), owner fuzzy match, pin polylines, pack merge tools. **Done — see PASS32_ASSETS_MANIFEST.md.**
