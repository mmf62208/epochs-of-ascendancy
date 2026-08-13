# Asset Pass 24 — Formal treaties · Player munitions pips · Risk sparkline · Munitions LOD

Skills: `game-asset-core` · `game-ui-icons`

## Formal alliance treaty filter

`RelationsManager` policy:

- `alliance` mutual treaty via `set_alliance` / `is_allied`
- Independence `set_guarantee` / `has_guarantee` / `is_formal_ally_or_guaranteed`
- Persists in relations save (`pairs` policy)

Diplomacy View:

- **Propose Alliance** → formal treaty + CRS bump
- **Guarantee Independence** → directed guarantee

Repair queue scope cycle:

| Label | Scope |
|-------|--------|
| Player only | Player provinces |
| Formal allies | Treaty / guarantee only |
| Partners+ | CRS partner/ally_ready + treaties |

Treaty rows marked ⚔; CRS partners ★.

## Player-only munitions minimap pips

- Default: **player depots only**
- Munitions desk **Map pips: mine / all** toggles filter
- Ownership from province `owner_tag`

## Compare risk sparkline

Route compare card:

- Dual hop-risk polylines (A cyan / B magenta)
- Built from `estimate_path_hop_risks` (per-hop `SupplyInterdictionEstimator` + storm)

## Munitions minimap LOD

`MapZoomLOD`:

| Tier | Max pips | Radius | Detail |
|------|----------|--------|--------|
| Strategic | 16 | 2.4 | critical core only |
| Operational | 28 | 1.9 | ring + urgency ticks |
| Tactical | 48 | 1.55 | full detail |

Strategic prefers lowest-fill (critical ammo) depots first. LOD change rebuilds pip cache.

## Code

| File | Change |
|------|--------|
| `RelationsManager.gd` | Alliance / guarantee API |
| `DiplomacyView.gd` | Wire formal treaties |
| `SiteRepairQueueChip.gd` | Scope cycle treaty/partner |
| `MapRenderer.gd` | Classify ally, hop risks, sparkline draw |
| `MapMinimap.gd` | Player filter + LOD density |
| `MapZoomLOD.gd` | Munitions pip helpers |
| `MunitionsDeskChip.gd` | Map pips mine/all |

## Limits / Pass 25 ideas

- Alliance “propose” currently accepts immediately (no multi-turn negotiation).
- Hop risk is per-province independent estimate (not path-correlated).
- Munitions player filter uses owner_tag only (not controller).
- Pass 25 candidates: alliance negotiation UI, path-correlated risk, controller-aware pips, compare sparkline history over days. **Done — see PASS25_ASSETS_MANIFEST.md.**
