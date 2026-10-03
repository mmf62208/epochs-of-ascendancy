# FLEET-2 FIX #6 live-scale clicks (xvfb 1280×740, GER, Europe Home, world_accurate)

xvfb ≠ live Play. Tip and table filled after the live-scale run.

## Topmost-painted rule

Below z0.65, a land/air click that lands on a painted counter body — NationPlate, StatBars, or Designation/TypeLetter/StrNum — selects that counter. **Topmost** means the actual CanvasItem draw order: higher absolute `z_index` first, then later in the scene tree (`Node.is_greater_than`). Not nearest centre.

The player-land ownership block (a foreign chip stationed elsewhere cannot win on GER land) applies **only in the halo / fallback zone** — when no painted body contains the click. That halo is what keeps Cuxhaven `710374` / Heidekreis `710380` on own GER or the province.

If an own counter already draws on top, own-bars-beat-foreign falls out of topmost. Otherwise the existing own-StatBars priority is kept so Berlin AW3 +46 still beats a foreign plate that paints over the bars.

Same-nation overlapping piles are not specially retargeted; they follow the same topmost-painted rule.

## Guard probes (intended)

| click | z0.318 | z0.400 |
|---|---|---|
| Emden NLD east +20 px | `NLD_formation_1` | `NLD_formation_1` |
| DNK AW3 bars +44 px | `DNK_formation_3` | `DNK_formation_3` |
| coast `710374` / `710380` halo | own GER / province (never NLD) | same |
| GER AW3 bars +46 / corner | `GER_formation_3` own | same |

Emden painted-rect grid: every cell inside the NLD Div 1 painted rect must open `NLD_formation_1` unless a different counter is drawn on top there (that counter is named in the live-scale log).
