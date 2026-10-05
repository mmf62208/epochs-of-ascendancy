# EDGE-1 Play recipe — 1280×740 · **no Ctrl**

Window **1280×740** Absolute **@(0, 29)** · GER 1936 · `world_accurate`.
Do **not** raise the window. Do **not** use Ctrl.
Headless / xvfb ≠ live Play.

Client = screen − window origin. Screen y = client y + **29**.
Screen x = client x + **0**.

## Path (no Ctrl)

1. Begin GER 1936. Tip × if shown at **≈(1029, 114)** (TipDismiss — do not change).
2. If National Spirits / province inspector is up: click red **Close @(670, 85)**.
3. Hover each rim below. Do **not** drag. Camera should slide at the same
   comfortable speed on every edge, including the far-right and the
   top-right corner.

## 1280×740 hover points (client + screen)

| Hover | Client | Screen @(0, 29) | Expected pan |
|---|---|---|---|
| **Left** | **(3, 370)** | **(3, 399)** | west (camera −x) |
| **Right** | **(1270, 370)** | **(1270, 399)** | east (camera +x) |
| **Top** (under TopInfoBar) | **(640, 1)** | **(640, 30)** | north (camera −y) |
| **Bottom** | **(640, 737)** | **(640, 766)** | south (camera +y) |
| **Top-right corner** | **(1270, 1)** | **(1270, 30)** | northeast (east + north) |
| Interior rest | (640, 370) | (640, 399) | no pan |
| UI-1 rest | (97, 731) | (97, 760) | no pan (9px above floor) |

## Close-held check

1. Open a unit card (GER land chip).
2. Click **inspector Close @(670, 85)** if the inspector is on the north strip,
   **or** a HUD Close that sits in the top 6px.
3. **Keep the mouse held** on that Close / on y=0–1.
4. Expect **no** edge pan while Close is held (CLOSE-1 / CLOSE-1b).
5. Release, then hover **(640, 1)** — first top-edge after a mid-panel Close
   must still pan north (CLOSE-1b + UI-1).

## Must keep

- Home / Shift+Home framing unchanged.
- Top-edge under TopInfoBar still pans (UI-1).
- A toast / panel on the right rim must **not** pan.
- TipDismiss handler unedited.

Draft until Ship squash-merges. Never claim live Play PASS from this harness.
