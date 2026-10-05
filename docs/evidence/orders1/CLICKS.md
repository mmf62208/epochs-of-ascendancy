# ORDERS-1 Play recipe (exact clicks) — FIX #1 1280×740

Window **1280×740** at screen **(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Stance + cmd stay on-screen at this height.
Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.

Client = screen − window origin. Screen y = client y + **29**.
Harness `PLAY_CLICKS 1280x740` (viewport 1280×740, card dock y=392,
size 340×338, bottom=730).

**Rows (FIX #1):**
- **Upper fight row** (`UnitCardStanceRow`): **Press** | **Hold** | **Withdraw**
- **Lower cmd row** (`UnitCardCmdRow`): **Halt march** (if marching) | **Assign**

Withdraw is **never** next to Halt. Press/Hold sit **above** Halt, not below
the fold. Close the province inspector (National Spirits) if it is open —
its Assign tooltip can cover the cmd row; stance is above that now.

## 1280×740 centers (harness; screen = client + (0, 29))

Fighting + marching card (the live Hold/Withdraw case):

| Button | Client | Screen @ (0, 29) | Notes |
|---|---|---|---|
| **Press** | **(80, 633)** | **(80, 662)** | Upper row, left. Toast `Stance: Press`. |
| **Hold** | **(159, 633)** | **(159, 662)** | Upper row, middle. Expect **Hold ●** + toast `Stance: Hold`. |
| **Withdraw** | **(246, 633)** | **(246, 662)** | Upper row, right of Hold. Expect **Withdraw ●** / `Withdrawing · bounce tomorrow`. |
| **Halt march** | **(93, 675)** | **(93, 704)** | Lower row, **left**. Not Assign. Toast `March halted · …`. |
| **Assign** | **(245, 675)** | **(245, 704)** | Lower row, under Withdraw. Do not click for ORDERS-1. |

March-only card (no fight): Halt **(93, 633)** client / **(93, 662)** screen;
Assign **(245, 633)** / **(245, 662)**. Same left-of-Assign rule.

Live Halt on tip `138a1f8a` was screen **(85, 744)** — that was the old
low dock (clipped stance). After FIX #1 Halt sits **higher** (704 if also
fighting, 662 if march-only).

Click the **labeled** button. Assign sits under Withdraw at the same X —
aim at **y=662** for Withdraw, **y=704** for Halt/Assign.

## Halt

1. F5 / TestScenario. Living title → **Begin** (GER 1936). Do not use Esc to start.
2. Europe Home if the camera is not on Germany.
3. Click a **GER land chip** (Division / Garrison plate+label). Not an Air Wing.
4. With the unit card up, click **own adjacent land** (plain left click) to March.
   Amber `MarchPathLine` + card shows **Halt march** on the **lower** row.
5. Click **Halt march** at screen **(93, 662)** (march-only) or **(93, 704)**
   (also fighting). Do **not** click Assign.
   Expect: Halt gone, path gone, unit still on the current hex, toast
   `March halted · …`.

## Hold

6. Select the same (or another) GER land unit.
7. **Ctrl+click** adjacent enemy land (Maginot FRA) so an open fight starts
   (not empty-hex instant). Card shows Fight + **Press ●** / **Hold** / **Withdraw**
   on the **upper** row at y≈633 client.
8. Click **Hold** at screen **(159, 662)**. Not Halt (lower row).
   Expect: button becomes **Hold ●**, Press loses the dot, toast
   **`Stance: Hold`** (not `Unpause to fight · Press or Hold`), bubble may
   read `HOLD`.

## Withdraw

9. Same fighting card. Click **Withdraw** at screen **(246, 662)** (upper row).
   Do **not** click Halt at (93, 704) or Assign at (245, 704).
   Expect: body line **Withdrawing · bounce tomorrow**, button **Withdraw ●**,
   toast `Withdrawing · bounce tomorrow`, bubble ` WD`.
   Same-day does not instantly delete the fight; next day bounces.

Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.
