# Asset Pass 21 — Munitions graph · Bulk repair · Compare slots · Intensity presets

Skills: `game-asset-core` · `game-ui-icons`

## Munitions stockpile graph

`MunitionsDeskChip`:

- Rolling sparkline of depot munitions avg (last 24 samples)
- Samples on open + each game day tick
- Trend arrow in status (↑ / ↓ / →)
- Area + line tint by fill level (green → red)

## Multi-site bulk repair

Special sites inspector when **2+** damaged sites in province:

- **Repair all (N sites)** CTA
- Same −1 dmg (+1 with engineers) per site
- Toast summary + live feature ring refresh

## Route compare save slots

Compare card (after Shift+click A/B):

- **Save 1 / 2 / 3** stores hops, risk, paths, focus
- **Load N** re-highlights that pair (● when filled)
- Gen-guarded auto-dismiss (~12s); save rebuild keeps card alive

## Secondary intensity presets

Toolbar **2nd** row **Ix** cell:

| Key | Intensity |
|-----|-----------|
| S Soft | 0.50 |
| M Med | 1.00 |
| H Hard | 1.50 |
| X Max | 2.00 |

Applies to all active secondaries; sliders rebuild to match.

## Code

| File | Change |
|------|--------|
| `MunitionsDeskChip.gd` | Sparkline history + day sample |
| `MapRenderer.gd` | Bulk repair, compare slots, intensity preset API |
| `MapModeToolbar.gd` | Ix Soft/Med/Hard/Max chips |

## Limits / Pass 22 ideas

- Sparkline is avg across depots only (not per-hub).
- Compare slots are session-only (not saved to disk).
- Bulk repair is per-province, not global theater.
- Pass 22 candidates: per-depot munitions mapmode, theater-wide repair queue, persistent compare slots in save, intensity linked to primary mapmode. **Done — see PASS22_ASSETS_MANIFEST.md.**
