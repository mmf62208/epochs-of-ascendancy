# INPUT-1 Play recipe — 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl.
Headless / xvfb ≠ live Play.

**Code SHA:** LeaderEventUI FIX #4 on this branch (MapRenderer / MainMenu still `977c9a84`). Guard **PASS** failures=0. Pure main `61a80433` and FIX #3 tip `b64b98f3` **FAIL** T12a–c same-spot pid=-1. See `docs/CURRENT_STATE.md` INPUT-1 FIX #4.

## Pre-step

```
timeout 1500 tools/run_godot.sh --headless --path . --import --quit
```

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**.

## Path (no Ctrl)

1. Begin GER 1936. Tip × if shown (TipDismiss — do not change).
2. Wait for a **Notice** / toast (or trigger one: save, G corridor, capture).
3. Click the toast **×** (upper-right of the notice card). Expect:
   - notice closes
   - **no** province inspector
   - **no** unit card
   - the hex / counter **under** the × stays unselected
4. Then a **new** still-click on a GER land chip / hex must select normally.
5. Open **Command Center** (Esc when idle, or menu). Click panel **✕**.
   Expect the same: CC closes, map under ✕ does **not** pick. Next click
   selects normally.
5b. Wait for an **Infrastructure Complete** News card with a **Notice:
    Investment complete in …** card under it (same pair as
    `InfrastructureDevelopmentManager` 571–573). At **z0.9**, close the
    News **×**. Without moving the mouse, click the same spot at about
    **1 s**: the map under it must select. Then move the mouse away and
    back, and click the Notice **body**: nothing is selected. If two
    Notices are stacked, the same still-click after the top × must
    select (the survivor × must not poll-close).

## 1280×740 close points (approx)

| Control | Client (approx) | Expected |
|---|---|---|
| Notice × | toast upper-right (bottom-right stack) | closes notice; leftover ignored |
| Command Center ✕ | panel title-row right | closes CC; leftover ignored |
| Follow-up GER chip | Maginot / Home GER plate | opens Fill%/TOE card |

## Must keep

- TipDismiss × swallow unedited.
- BEGIN-1 title leftover swallow unedited.
- Camera / edge-pan / Home framing unedited.
- FacilityIconLayer / political labels / fleet stack / unit pick ranking unedited.
- No GameData rewrite. No `world_full` ID renumber. No Godot bump.

Draft until Ship squash-merges. Never claim live Play PASS from this harness.
