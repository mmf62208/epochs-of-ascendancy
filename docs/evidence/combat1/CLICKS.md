# COMBAT-1 Play recipe (exact clicks) — 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl (xdotool modifier is intermittent).
Headless fixture rects ≠ live Play. Centers are the live ORDERS-1 PLAY_CLICKS
(`333a1285` / main `b89a1679`). COMBAT-1 does not move those buttons.

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**.

**Always Close the province inspector / National Spirits first** if it is up.
Its red Close is Absolute **~(670, 85)** (client ~670, 56). The inspector
covers the left dock so Open fight / Start / Hold cannot be clicked.

## Path (no Ctrl)

1. Begin GER 1936. Tip × if shown (TipDismiss — do not change).
2. If National Spirits / province inspector is up: click red **Close @(670, 85)**.
3. Click a **GER land chip** next to FRA (Division plate). Card docks bottom-left.
4. **Open fight** on the unit card (no Ctrl). Sheet should name a **defended**
   neighbor (Bas-Rhin), not empty Haut-Rhin.
5. **Start battle** at **y≈548** (not 525 — that hits the Power line).
   Expect `opened=true` (not `empty hex · no Hold/Withdraw`).
6. Unpause / 4x a few days. Watch chips/card **strength / Fill%** change.
   Toast/log: `Took …` or `Held at …` (also printed `Fight resolved · …`).
7. Optional stance (same coords as ORDERS-1): **Hold ≈(157, 621)** /
   **Withdraw ≈(241, 621)**. Do not click y=662 (Assign). Halt march-only
   **(90–93, 662)** OK.

Flag any **new** button within ~40 px of Assign / Halt. COMBAT-1 added none.

## 1280×740 centers (live Play, inherited)

| Button | Client | Screen @(0, 29) | Notes |
|---|---|---|---|
| **Inspector Close** | ~(670, 56) | **~(670, 85)** | If inspector covers the dock. |
| **Open fight** | **(90, 535)** | **(90, 564)** | On the unit card. No Ctrl. |
| **Start battle** | **≈(205, 519)** | **≈(205, 548)** | Not 525 (Power line). |
| **Hold** | **≈(157, 592)** | **≈(157, 621)** | Fighting card. Not Assign. |
| **Withdraw** | **≈(241, 592)** | **≈(241, 621)** | Fighting card. |
| **Halt march** | **(90–93, 633)** march-only | **(90–93, 662)** | March-only. |
| **Assign** | — | **y=662** on the fighting card | Do not click. |

## Soft note (addressed here)

Open fight used to take the **first** adjacent enemy (Play: empty Haut-Rhin →
instant light capture). COMBAT-1 prefers the adjacent hex that already has
defending units when one exists. Empty remains the fallback.

Headless + xvfb ≠ live Play. Draft until Ship squash-merges.
