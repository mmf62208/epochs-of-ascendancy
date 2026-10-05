# ORDERS-1 Play recipe (exact clicks) — FIX #2 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl (xdotool modifier is intermittent).
Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**.

**Always Close the province inspector / National Spirits first** if it is up.
Its red Close is Absolute **~(670, 85)** (client ~670, 56). The inspector
covers the left dock so Open fight / Hold / Withdraw cannot be clicked.
Card-up now also hides the inspector (product), but Close first anyway.

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

Harness `PLAY_CLICKS` / `PLAY_CLICKS_OPENFIGHT` at viewport 1280×740
(card dock y=392, 340×338, bottom=730). Inspector Close is live Play.

| Button | Client | Screen @(0, 29) | Notes |
|---|---|---|---|
| **Inspector Close** | ~(670, 56) | **~(670, 85)** | Red × on National Spirits / province inspector. Do this first. |
| **Open fight** | **(90, 535)** | **(90, 564)** | On the unit card, above Halt. No Ctrl. |
| **Start battle** | **(205, 496)** | **(205, 525)** | OpenFightSheet. Must `opened` a fight (empty hex is not a fight). |
| **Hold** | **(159, 633)** | **(159, 662)** | Upper row. **Hold ●** + `Stance: Hold`. |
| **Withdraw** | **(246, 633)** | **(246, 662)** | Upper row. Not Halt. **Withdraw ●** / Withdrawing. |
| **Halt march** | **(92, 675)** fight+march / **(92, 633)** march-only | **(92, 704)** / **(92, 662)** | Lower-left. |
| **Assign** | **(245, 675)** | **(245, 704)** | Do not click. Same X as Withdraw. |

Assign sits under Withdraw at the same X — aim **y=662** for Hold/Withdraw.

## Halt only

1. GER land chip → own adjacent land (plain click) → **Halt march** @(92, 662) march-only.
   Expect toast `March halted · …`. Path gone. Unit stays.

Headless + xvfb ≠ live Play. Merge stays HOLD for Play + Scott.
