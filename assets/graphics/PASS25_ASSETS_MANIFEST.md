# Asset Pass 25 — Alliance negotiation · Path-correlated risk · Controller pips · Day history

Skills: `game-asset-core` · `game-ui-icons`

## Alliance negotiation UI

`RelationsManager`:

| API | Role |
|-----|------|
| `propose_alliance` | Open pending offer (not instant treaty) |
| `accept_alliance` / `decline_alliance` | Resolve |
| `cancel_alliance_proposal` | Withdraw outgoing |
| `get_incoming/outgoing_alliance_proposals` | Lists |
| AI day tick | Non-player targets auto accept/decline by CRS |

Diplomacy View:

- **Propose Alliance** → pending negotiation
- Desk: status, **Accept / Decline / Withdraw**
- Live CRS · band · ALLIED readout
- Proposals persist in `relations` save

## Path-correlated hop risk

`estimate_path_hop_risks`:

- Marginal risk from prefix path estimates
- Residual survival amplifies later danger
- Friendly consecutive hops dampened
- Label: “Hop risk (path-correlated)”

## Controller-aware munitions pips

Player filter uses `controller_tag` when set, else `owner_tag` (occupation-aware).

## Multi-day compare risk history

- Tracks overall A/B risk for last compare + per saved slot
- Samples on day tick + compare open
- Second sparkline: “Risk over days (N samples)”
- Persists in `map_ui.route_risk_day_history` (max 16 samples)

## Code

| File | Change |
|------|--------|
| `RelationsManager.gd` | Proposals, AI resolve, save |
| `DiplomacyView.gd` | Negotiation desk UI |
| `MapRenderer.gd` | Path-correlated hops, day history |
| `MapMinimap.gd` | Controller-aware filter |
| `MunitionsDeskChip.gd` | Tooltip note |

## Limits / Pass 26 ideas

- AI alliance accept is CRS-heuristic (no full AI personality).
- Day history samples only when track exists (after first compare).
- Path correlation re-runs estimator per prefix (O(n²) hops; fine for short routes).
- Pass 26 candidates: alliance counter-offers, occupation munitions tint, risk history export, multi-route C track. **Done — see PASS26_ASSETS_MANIFEST.md.**
