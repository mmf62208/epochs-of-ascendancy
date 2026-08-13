# Asset Pass 33 — QR v11–20 · Slot-weighted merge · Polyline hit · EORP3 compress

Skills: `game-asset-core` · `game-ui-icons`

## QR versions 11–20

| Item | Detail |
|------|--------|
| Capacity | ECC M up to **666 data bytes** (v20) |
| Tables | ISO block structure via Nayuki (g1 short / g2 long) |
| Alignment | Formula-driven centers (v2–20) |
| Version info | Drawn for versions ≥ 7 |

Long EORP2 history packs no longer force EORP1 solely for size (within 666 B).

## Merge weight by slot order

Score = `risk + slot_index × 0.04 + route_index × 0.01`

- Lower score wins  
- Slot 1 (index 0) preferred when risks are close  
- Live pack weighted as half-slot between 0 and 1  

## Polyline hit-test → load slot

- Click within **5.5 px** of a pack route segment on minimap  
- Loads that pin’s pack slot (same as pin click)  
- Toast distinguishes `pin` vs `polyline`  

## Share-code compression (EORP3)

| Prefix | Contents |
|--------|----------|
| EORP1 | Paths only (JSON + base64) |
| EORP2 | Paths + history samples |
| **EORP3** | Deflate(compact JSON) + base64 — **default Share** |

Compact payload:

- Paths as **delta sequences** `[start, Δ, Δ, …]`  
- Risks as **percent ints** 0–100  
- History samples as percent ints  
- Import accepts EORP1/2/3  

## Code

| File | Change |
|------|--------|
| `RoutePackQR.gd` | v11–20, version info, capacity table |
| `MapRenderer.gd` | EORP3, merge weight, helpers |
| `MapMinimap.gd` | Polyline hit-test load |

## Limits / Pass 34 ideas

- QR still max v20 (~666 B); huge packs fall back to CLI / drop history.  
- Delta paths assume integer province IDs (always true here).  
- Polyline hit uses centroid skeleton, not road geometry.  
- Pass 34 candidates: pack pin legend, slot drag-reorder, EORP3 QR auto-size module px, share to file. **Done — see PASS34_ASSETS_MANIFEST.md.**
