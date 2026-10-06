# Chip draw-order Play recipe — 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl.
Measured by `WindowedFleet2LiveScaleCheck` on `DISPLAY=:0` (live15, RESULT=PASS).
Zoom step 0.40 → 0.318 spent **3.33 ms** on counter paint (`icons=253`).

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**. The table's client column is what the harness logged.

Begin GER. If the province inspector is up, Close it first (**~(670, 85)**).
Tip × is TipDismiss — do not change that button. These clicks are map chips.

A chip wins only where its own ink is the top painted piece (NATO symbol,
colored bar fill, or glyph). Empty label boxes do not count. Player symbols
draw above foreign symbols. Sea plates stay above land.

## Frames

| Frame | Zoom | Camera world |
|---|---|---|
| Channel cluster | 0.318 | 7134.5, 1622.3 |
| Overlap province **710977** | 0.318 | 7316.8, 1691.4 |
| Airfield L4 **710451** | 0.760 | 7398.8, 1632.6 |
| Europe Home (Emden rim) | 0.318 | home fit |

## Clicks (that frame, then this client point)

| Click | Client | Screen @(0, 29) | Opens |
|---|---|---|---|
| **BEL Div 1** face (Channel, z0.318) | **(684, 355)** | **(684, 384)** | `BEL_formation_1` (read-only) |
| **GER Div 6** face (710977, z0.318) | **(667, 378)** | **(667, 407)** | `GER_formation_6` own card |
| **GER Garrison 4** face (710977, z0.318) | **(685, 356)** | **(685, 385)** | `GER_formation_4` own card |
| **GER Div 7** face (710977, z0.318) | **(660, 393)** | **(660, 422)** | `GER_formation_7` own card |
| **Emden NLD** rim (Home, z0.318) | **(648, 286)** | **(648, 315)** | `NLD_formation_1` (read-only) |
| **Airfield L4** cluster (z0.760) | **(648, 369)** | **(648, 398)** | nothing — not `GER_formation_4` |

Each German face opens that formation, not the neighbor stacked on the same view.
The airfield cluster icon does not spill into the German garrison.
