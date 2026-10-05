# ORDERS-1 Play recipe (exact clicks) — FIX #1 1280×740

Window **1280×740** at screen **(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Stance + cmd stay on-screen at this height.
Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.

Client = screen − window origin. Screen y = client y + **29**.
Card docks bottom-left at x=18; fighting card is raised so the bottom
stays ≤ 732 (8px margin).

**Rows (FIX #1):**
- **Upper fight row** (`UnitCardStanceRow`): **Press** | **Hold** | **Withdraw**
- **Lower cmd row** (`UnitCardCmdRow`): **Halt march** (if marching) | **Assign**

Withdraw is **never** next to Halt. Press/Hold sit **above** Halt, not below
the fold. Close the province inspector (National Spirits) if it is open —
its Assign tooltip can cover the cmd row; stance is above that now.

## 1280×740 client centers (harness `PLAY_CLICKS`; screen = +29 y)

| Button | Client (card) | Screen @ (0, 29) | Notes |
|---|---|---|---|
| **Hold** | ~(134, 620) | ~(134, 649) | Upper row, middle. Expect **Hold ●** + toast `Stance: Hold`. |
| **Withdraw** | ~(210, 620) | ~(210, 649) | Upper row, right of Hold. Expect **Withdraw ●** / `Withdrawing · bounce tomorrow`. |
| **Halt march** | ~(73, 652) | ~(73, 681) | Lower row, **left**. Not Assign. Toast `March halted · …`. |
| **Assign** | ~(239, 652) | ~(239, 681) | Lower row, right of Halt. Do not click for ORDERS-1. |
| **Press** | ~(63, 620) | ~(63, 649) | Upper row, left. Toast `Stance: Press`. |

Live Halt on tip `138a1f8a` was screen **(85, 744)** — that was the old
low dock (clipped stance). After FIX #1 Halt sits **higher** (~681).

Re-read harness log line `PLAY_CLICKS 1280x740` after a local guard run
if the card grew; click the **labeled** button, not a memorized pixel if
the row shifted a few px.

## Halt

1. F5 / TestScenario. Living title → **Begin** (GER 1936). Do not use Esc to start.
2. Europe Home if the camera is not on Germany.
3. Click a **GER land chip** (Division / Garrison plate+label). Not an Air Wing.
4. With the unit card up, click **own adjacent land** (plain left click) to March.
   Amber `MarchPathLine` + card shows **Halt march** on the **lower** row.
5. Click **Halt march** (lower-left). Do **not** click Assign.
   Expect: Halt gone, path gone, unit still on the current hex, toast
   `March halted · …`.

## Hold

6. Select the same (or another) GER land unit.
7. **Ctrl+click** adjacent enemy land (Maginot FRA) so an open fight starts
   (not empty-hex instant). Card shows Fight + **Press ●** / **Hold** / **Withdraw**
   on the **upper** row.
8. Click **Hold** (upper row, between Press and Withdraw). Not Halt.
   Expect: button becomes **Hold ●**, Press loses the dot, toast
   **`Stance: Hold`** (not `Unpause to fight · Press or Hold`), bubble may
   read `HOLD`.

## Withdraw

9. Same fighting card. Click **Withdraw** on the **upper** row (right of Hold).
   Do **not** click Halt on the lower row.
   Expect: body line **Withdrawing · bounce tomorrow**, button **Withdraw ●**,
   toast `Withdrawing · bounce tomorrow`, bubble ` WD`.
   Same-day does not instantly delete the fight; next day bounces.

Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.
