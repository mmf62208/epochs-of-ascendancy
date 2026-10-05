# ORDERS-1 Play recipe (exact clicks) — FIX #2 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl (xdotool modifier is intermittent).
Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**.

**Always Close the province inspector / National Spirits first** if it is up.
Its red Close is Absolute **~(670, 85)** (client ~670, 56). The inspector
covers the left dock so Open fight / Hold / Withdraw cannot be clicked.

## Path (no Ctrl)

1. Begin GER 1936. Tip × if shown (TipDismiss — do not change).
2. If National Spirits / province inspector is up: click red **Close @(670, 85)**.
3. Click a **GER land chip** (Division plate). Card docks bottom-left.
4. **Halt (optional):** own-land March → **Halt march** lower-left.
5. **Open fight** on the unit card (no Ctrl). Sheet: Attacker / Defender / **Start battle**.
6. **Start battle**. Card rebuilds with **Press ● | Hold | Withdraw** on the upper row.
7. **Hold** → **Hold ●** + toast `Stance: Hold`.
8. **Withdraw** → **Withdraw ●** / `Withdrawing · bounce tomorrow`.

## 1280×740 centers

Inspector Close (live Play):

| Button | Client | Screen @(0, 29) |
|---|---|---|
| **Inspector Close** | ~(670, 56) | **~(670, 85)** |

Fighting card after Start (harness `PLAY_CLICKS` / `PLAY_CLICKS_OPENFIGHT` — fill after run):

| Button | Client | Screen @(0, 29) | Notes |
|---|---|---|---|
| **Open fight** | harness | +29 y | On the unit card, above Halt. |
| **Start battle** | harness | +29 y | On OpenFightSheet, not Ctrl. |
| **Hold** | **(159, 633)** | **(159, 662)** | Upper row. **Hold ●** + `Stance: Hold`. |
| **Withdraw** | **(246, 633)** | **(246, 662)** | Upper row. Not Halt. |
| **Halt march** | **(93, 675)** fight+march / **(93, 633)** march-only | **(93, 704)** / **(93, 662)** | Lower-left. |
| **Assign** | **(245, 675)** | **(245, 704)** | Do not click. |

Assign sits under Withdraw at the same X — aim **y=662** for Hold/Withdraw.

## Halt only

1. GER land chip → own adjacent land (plain click) → **Halt march** @(93, 662) march-only.
   Expect toast `March halted · …`. Path gone. Unit stays.

Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.
