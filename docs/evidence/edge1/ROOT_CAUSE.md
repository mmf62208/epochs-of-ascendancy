# EDGE-1 root cause (proven vs hunches)

Window **1280×740**. Existing camera path only (`MapViewInput.edge_pan_direction_at`
+ `MapRenderer._handle_camera_input`). No new camera system.

## Proven

UI-1 set the true window rim to **6 screen px**. On a 1280-wide client that
makes the right strip `x >= 1280 − 6 = 1274`.

Play hover for the far-right is **≈x=1270** (10px inset), including the
top-right corner **(1270, 1)**. Helper math on trusted main `251d2628`:

| Client | 6px-only dir | Notes |
|---|---|---|
| (3, 370) | (−1, 0) | left OK |
| (1279, 370) | (1, 0) | last 6px OK |
| **(1270, 370)** | **(0, 0)** | **miss — 4px outside the strip** |
| (640, 1) top-bar | (0, −1) | UI-1 north OK |
| (640, 737) | (0, 1) | bottom OK |
| **(1270, 1)** top-bar | **(0, −1)** | north only — **no east** |

That is the far-right / corner miss. Speed on the rims that *did* fire was
already the same normalized `pan_speed` step; the right felt inconsistent
because the documented hover often returned ZERO.

Fix (existing helper only): keep left/top/bottom at **6px** (UI-1 rest
`(97, 731)` still does not pan) and add `EDGE_PAN_RIGHT_SCREEN_PX = 10`
so `x >= 1270` pans east. Corner **(1270, 1)** is then northeast, same
normalized speed as the cardinal rims.

## Hunches — not reproduced on this tip

| Hunch | Verdict |
|---|---|
| Right-edge toast pans before first drag | **Already blocked** (UI-1 `hovered_blocks`). Toast hover at x=1279 / strip stays ZERO. Do not loosen. |
| Large drags jump the camera south | **Not reproduced.** `_activate_left_drag_pan_from_slop` reseeds `_last_mouse_pos` from this press origin. No camera edit. |
| UI-1 one-off miss at (1270, 1) | **Same 6px-right miss** for the east component. North already worked when TopInfoBar-exempt. |

Home framing (`_apply_home_key` → `center_europe_in_world_view`) unedited.
CLOSE-1/1b north-strip suppress unedited. TipDismiss / ORDERS layout / chip
hit-rank unedited.
