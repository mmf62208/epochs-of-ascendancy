# ORDERS-1 Play recipe (exact clicks) — Play PASS `333a1285` · 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl (xdotool modifier is intermittent).
Headless fixture rects ≠ live Play. These centers are **live-proven** on tip
`333a1285` (Play PASS). Merge stays draft until Ship squash-merges.

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**.

**Always Close the province inspector / National Spirits first** if it is up.
Its red Close is Absolute **~(670, 85)** (client ~670, 56). The inspector
covers the left dock so Open fight / Hold / Withdraw cannot be clicked.
Card-up also hides the inspector. This Play run did not need Close.

## Path (no Ctrl)

1. Begin GER 1936. Tip × if shown (TipDismiss — do not change).
2. If National Spirits / province inspector is up: click red **Close @(670, 85)**.
3. Click a **GER land chip** (Division plate). Card docks bottom-left.
4. **Halt (optional):** own-land March → **Halt march** lower-left.
5. **Open fight** on the unit card (no Ctrl). Sheet: Attacker / Defender / **Start battle**.
6. **Start battle** at **y≈548** (not 525 — that hits the Power line).
   If toast is `empty hex · no Hold/Withdraw`, pick another GER chip next to a
   **defended** neighbor and Open fight again (Haut-Rhin empty was soft OK).
7. **Hold** at **y≈621** (not 662 — that is Assign) → **Hold ●** + `Stance: Hold`.
8. **Withdraw** at **y≈621** → **Withdraw ●** / `Withdrawing · bounce tomorrow`.

## 1280×740 centers (live Play)

| Button | Client | Screen @(0, 29) | Notes |
|---|---|---|---|
| **Inspector Close** | ~(670, 56) | **~(670, 85)** | Keep. This Play run did not need it. |
| **Open fight** | **(90, 535)** | **(90, 564)** | Live OK. On the unit card. No Ctrl. |
| **Start battle** | **≈(205, 519)** | **≈(205, 548)** | Live. Harness 525 hits the Power line. |
| **Hold** | **≈(157, 592)** | **≈(157, 621)** | Live fighting card. **Hold ●** + `Stance: Hold`. |
| **Withdraw** | **≈(241, 592)** | **≈(241, 621)** | Live fighting card. Not Halt. |
| **Halt march** | **(90–93, 633)** march-only | **(90–93, 662)** | Live OK (march-only). |
| **Assign** | — | **y=662** on the fighting card | Do not click. Old Hold/Withdraw y=662 hits Assign. |

Harness nuts3 `PLAY_CLICKS` / `PLAY_CLICKS_OPENFIGHT` still print fixture
client centers (OpenFight=90,535 Start=205,496 Hold=159,633 Withdraw=246,633).
Those are **not** the live Play recipe — use this table.

## Soft OK (COMBAT-1)

Open fight used to pick an **empty** adjacent enemy (Play: Div7 → Haut-Rhin,
`opened=false` instant capture). COMBAT-1 prefers a **defended** neighbor
when one exists. Empty remains the fallback.

Headless + xvfb ≠ live Play. Draft until Ship squash-merges.
