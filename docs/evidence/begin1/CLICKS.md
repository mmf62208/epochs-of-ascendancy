# BEGIN-1 Play recipe — 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl.
Headless / xvfb ≠ live Play.

**Tip:** `2f15698dec1f456b6ee339137873a83bc05b4ffb` (product `f18a341a`) BEGIN-1 FIX #2
(restamp clock after the Begin frame + poll-path `begin_press_pending`).
Update SHA after the push.

## Pre-step

```
timeout 1500 tools/run_godot.sh --headless --path . --import --quit
```

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**.

## Path (no Ctrl)

1. Title screen. Default **Germany · 1936**. Cursor on **Begin**.
2. Normal mouse click: press, hold **~80–150 ms**, release. Do **not**
   instant-click (0 ms press+release hides the race).
3. After Home framing, expect:
   - **no** province inspector
   - **no** unit card
   - **no** click-zoom (Home zoom must stay; leftover used to jump ~0.776 → 0.900)
   - Loir-et-Cher (under Begin at ~**(284, 580)** after Home) must **not** be selected
4. Then a **new** still-click on a GER land chip / hex must select normally
   (the leftover swallow is one-shot).
5. Lost leftover up (unfocused window / release never reaches Godot): after
   **~750 ms from the first frame after Begin**, or after a **fresh** left
   press that is not the poll-path Begin click itself, the first map click
   must pick. Keyboard Enter/Space Begin must **not** arm the swallow.

## 1280×740 Begin point

| Control | Client (approx) | Expected |
|---|---|---|
| **Begin** | button centre (left title column) | starts GER 1936; leftover release ignored |
| Home leftover land | **~(284, 580)** Loir-et-Cher | must stay unselected after Begin |
| Follow-up GER chip | Maginot / Home GER plate | opens Fill%/TOE card |

## Must keep

- Begin stays `ACTION_MODE_BUTTON_PRESS` (dead-Begin class).
- TipDismiss × swallow unedited.
- Camera / edge-pan / Home framing unedited.
- FacilityIconLayer / political labels / fleet stack / unit pick ranking unedited.

Draft until Ship squash-merges. Never claim live Play PASS from this harness.
