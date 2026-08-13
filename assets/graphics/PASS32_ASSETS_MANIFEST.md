# Asset Pass 32 — In-engine QR · Fuzzy owner · Pin polylines · Pack merge

Skills: `game-asset-core` · `game-ui-icons`

## In-engine QR (no CLI required)

| Source | Behavior |
|--------|----------|
| `RoutePackQR.gd` | Pure GDScript byte-mode QR, ECC M, versions 1–10 |
| Export | Prefer engine PNG → `user://route_pack_qr.png` |
| Fallback | System `qrencode` if engine fails / payload oversized |
| Retry | EORP2 → EORP1 if still too large |

## Owner fuzzy match

Auto pack **Owner** filter matches:

- Exact tag (`USA` = `USA`)
- Substring / contains (`US` ↔ `USA`)
- Prefix
- ≤1 Levenshtein edit for tags length ≤5 (`GER` ↔ `GE`)

## Pin polylines

- Each pack pin carries `polyline` (world centroids, decimated ≤12 pts)
- Minimap draws faint colored segments under multi-pins
- Primary routes slightly thicker / more opaque

## Pack merge tools

- **Merge** button on compare card
- Collects unique paths from all filled slots (+ current live pack)
- Ranks by live risk then hops; packs top 4 into A–D compare
- Dedupes via path signature (`pid|pid|…`)

## Code

| File | Change |
|------|--------|
| `scripts/ui/RoutePackQR.gd` | Pure GDScript QR encoder |
| `MapRenderer.gd` | Engine QR, fuzzy owner, polylines, merge |
| `MapMinimap.gd` | Draw pack pin polylines |

## Limits / Pass 33 ideas

- QR max ~213 data bytes (v10 M); very long EORP2 history may fall back to EORP1 / CLI.
- Polylines use centroid hops (not road geometry).
- Merge always takes lowest-risk global set (no slot-priority weights).
- Pass 33 candidates: QR version 11–20, merge weight by slot order, polyline hit-test load, share-code compress. **Done — see PASS33_ASSETS_MANIFEST.md.**
