# EDGE-2 left-rim root cause

`MapViewInput.edge_pan_direction_at` is symmetric: `x <= EDGE_PAN_SCREEN_PX` (6)
returns west. The live left rim still returned ZERO because two GUI gates
fired before that math:

1. `MapRenderer._handle_camera_input` bails when
   `MapViewInput.edge_pan_blocked_by_gui` is true.
   `control_or_ancestor_blocks_edge_pan` returns true for `MapModeToolbar`,
   `InfoPanel`, `Minimap` / `StrategicMinimap`. `_mouse_over_map_chrome_blocks_edge_pan`
   also returns true when the left-docked InfoPanel rect contains the mouse
   (it already skipped only the **north** 6px strip, not the left).
2. `edge_pan_direction_screen` then sets `hovered_blocks` from
   `hovered_ui_blocks_edge_pan` / `non_topbar_overlay_contains_mouse`. Any
   hovered Control that is not WorldMap/MapRenderer/Province blocks. The
   TopInfoBar exemption (`top_bar_only` + `in_north_strip`) does not apply
   on the left.

Play layout: MapModeToolbar at `offset_left = 8`, InfoPanel at `cx = 12`,
minimap at `offset_left = 12`. Hit rects / children / `gui_get_hovered_control()`
at `x <= 6` still report that chrome (or the pointer leaves the window before
`x <= 6` and `mouse_inside_window` zeros the dir). Debug log (env
`EOA_EDGE2_DEBUG=1`) prints hovered name + window mouse x at `x <= 6`.

Fix (same shape as UI-1 north TopInfoBar): `hovered_is_left_hud_only` +
`left_strip_hud_exempt` only when `x` is in `0..EDGE_PAN_SCREEN_PX`. Toasts /
unit cards / Leaders still block on that strip. Chrome-rect skip also ignores
the left 6px.

Separately, rim feel: contact clock on raw screen-edge occupancy (WHEELDRIFT-1
gate still zeros applied dir during 350+150). Dwell 250 ms, ramp 600 ms,
Home-zoom world-speed floor 0.33.
