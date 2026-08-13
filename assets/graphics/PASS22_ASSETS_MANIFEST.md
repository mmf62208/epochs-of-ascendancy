# Asset Pass 22 — Munitions mapmode · Theater repair queue · Persistent slots · Primary intensity

Skills: `game-asset-core` · `game-ui-icons`

## Per-depot munitions mapmode

New primary map mode **Munitions**:

- Province fill from live `SupplyManager.get_depot_munitions_ratio`
- Full stockpile → cyan-blue; empty → red; no depot → dim cool gray
- Intensity-scaled (Soft/Med/Hard/Max)
- Toolbar button + **Ammo** preset (munitions + supply overlay)
- Munitions desk + repair queue chip visible

## Theater-wide repair queue

`SiteRepairQueueChip` (bottom-left, supply / munitions / infra):

- Lists worst player-owned damaged special sites (top 8)
- **Go** focus · **Fix** single site
- **Repair 5** / **Repair all** (cap 40/pass)
- Day-tick refresh

## Persistent compare slots

`MapRenderer.get_save_data` / `apply_save_data`:

- 3 route compare slots
- Secondary + primary intensity maps
- Last mapmode

Hooked via `SaveLoadManager` key `map_ui`.

## Intensity linked to primary

- Primary modes strain / vitality / development / loyalty / munitions scale by intensity
- `primary_mapmode_intensity` remembered per mode on switch
- **Ix** S/M/H/X applies to secondaries **and** current primary
- Ix row shows even when no secondary chips (primary-only)

## Code

| File | Change |
|------|--------|
| `MapModeToolbar.gd` | Munitions mode, Ammo/RepairOps presets, primary Ix |
| `MapRenderer.gd` | Munitions tint, intensity link, queue, save API |
| `SiteRepairQueueChip.gd` | New repair queue UI |
| `SaveLoadManager.gd` | `map_ui` serialize/apply |
| `HudIconLibrary.gd` | munitions → supply icon fallback |

## Limits / Pass 23 ideas

- Munitions mode reuses supply icon (no dedicated art yet).
- Repair queue is player-owned only (not allies).
- Compare slots store paths only (no live risk recompute on load beyond saved meta).
- Pass 23 candidates: dedicated munitions icon, ally repair queue, compare risk recompute, minimap munitions pips. **Done — see PASS23_ASSETS_MANIFEST.md.**
