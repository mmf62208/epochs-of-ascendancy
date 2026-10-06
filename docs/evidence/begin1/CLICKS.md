# BEGIN-1 Play recipe — 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl.
Headless / xvfb ≠ live Play.

**Code SHA:** `f18a341a02fc823c35e037cc8e8e61f951eac41b` (product frozen).
Later commits are **test / docs / gates only**. FIX #4 is gate wiring only
(`launch_begin1_title_release` in `tools/eoa_full_test_gates.sh`). Do not
treat a later docs SHA as the product.

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
