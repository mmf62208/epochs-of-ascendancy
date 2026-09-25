# IX-1 Road Spine — Layer 2 first interconnect vertical

**Status:** theater proof + Mandate front-door PASS + day-tick FIX (draft; **HOLD merge** for Scott/Play).  
**Slice name:** **IX-1 Road Spine** (not Dig2, not G polyline, not Maginot combat).  
**Layer:** Mike Layer 2 — player actions must **show** on the map and **change play**.

## Before / after

| | Before (tip `eb4371d`) | After (this slice) |
|--|------------------------|--------------------|
| Player order | Invest raises an infra **number** + construction ring. F10 Invest is debug. | Inspector **Build Road Spine** on the corridor starts a real Invest-style project (ETA / bar / ring). |
| Road edges | `Province.built_road_neighbors` + `MapManager.build_road_connection` existed but were not a front-door order. | Complete calls `build_road_connection` on the corridor edges. |
| Look | RoadLayer Line2D existed; political / F1 hid it; F10 / Infra mapmode only. | Three corridor states: **queued** faint dashed `_draw`, **construction** hatched/partial advancing with `%`, **built** existing RoadLayer at playable mid-zoom (`z > 0.10`) without F10. Preview is not Line2D and is not rebuilt on zoom. |
| Impact | `get_movement_cost()` used infra only. | Infra +1 **and** a `built_road_neighbors` discount. Spine move/supply cost is **strictly less** than pre-build and cheaper than off-spine Essen at the same starting infra. |

## Theater (one corridor)

Home Europe, GER-owned at 1918 / 1936 start. **Rhineland / west-German city spine**, not Maginot combat hexes.

| ID | Name | Role |
|----|------|------|
| **710417** | Köln, Kreisfreie Stadt | Hub — one order builds both edges |
| **710416** | Bonn, Kreisfreie Stadt | South endpoint |
| **710418** | Leverkusen, Kreisfreie Stadt | North endpoint |
| 710403 | Essen, Kreisfreie Stadt | Off-spine **control** (same starting infra, no road) |

Edges: `710417–710416`, `710417–710418`. Three adjacent owned plains cells. Spec: `data/infrastructure/ix1_road_spine.json`.

## Mandate front door (FIX)

Fresh **Begin · Germany · 1936** has Mandate **0** (`peace_state.mandate` map empty). Generic Köln Invest is still **73** and stays gated. The IX-1 order uses a **first-session starter grant** (`first_session_mandate_cost` **0** in `data/infrastructure/ix1_road_spine.json` / `get_ix1_road_spine_mandate_cost`). No F10 / debug cheat. Headless: `ix1_day0_mandate_can_start("GER")` and `HeadlessIx1RoadSpineMandateGateTest.gd`.

## Day-tick FIX (clock + spine progress)

An active spine used to stall the F5 clock (~7 Jan 20:00 @ 4× / ~9 Jan 20:00 @ 1×, spine ~17–20%) while Godot stayed hot. Cause: `advance_daily_projects` only runs the full-board `ai_consider_daily_invests` (3520×N) when **any** project is live, and each progress notify rebuilt the inspector. F5 already budgets 1 AI infra start/day — the continent consider is skipped under `is_interactive_light_sim` **and** any graphical DisplayServer (editor/export Play / softpipe). Budgeted AI pick is capital/neighbors only (never `get_provinces_by_owner`). Remote AI starts do not toast/notify. Day-emit no longer walks 3520 feature rings.

After that +2 fix held, live F5 still froze ~6–7 Jan (+5/+6d) at ~10GB RSS: calendar `save_game_detailed` on elapsed%7==0 plus a 3520 harvest walk on day +5. Live F5 / `is_live_f5_play_path()` now **skips** automatic 7d + quit autosave (Ctrl+S unchanged; autosave JSON is compact). Harvest is player-owned only (cap 96). Hierarchy dump and network pulse stay off on that path.

Spine-pin CA `36485b9` then **regressed live clock vs `5732d34`**: Play stuck at **1 Jan 1936 00:00** (~272% CPU) while headless day-tick still PASS. Round-1 CA on `9f09db2` (DisplayServer live F5 + hour-force + Space) **still FAIL** on Play: 4x + pause/play left 1 Jan 00:00; log `Paused = true` and TestRunner “sim paused for playtest”. Round-2 cause: leftover pick-block + `gui_get_hovered_control()` miss swallowed TopInfoBar 4x/pause; `_ensure_game_interactive` still force-paused when `player_owns_clock` was unset. Fix: `_top_bar_owns_click()` rect early-out; `release_play_clock_input_blockers` + `mark_living_title_closed` on Begin; no deferred re-pause after title; speed `ACTION_MODE_BUTTON_PRESS`; windowed TimeManager hour fallback; `simulate_play_begin_clock_controls` FAILS if Begin+4x stays paused. Search Go + Build Road Spine chrome pin **kept**. Headless: `simulate_ix1_spine_days` + `simulate_live_f5_day_advance` + **play-begin 4x past hour +6**. Mandate front door unchanged.

Round-2 Play on `3648dc9` then **left 1 Jan** but **wedged at 6 Jan 20:00 (+5d)** with Map Mode open and stacked Province-captured toasts (past 7 Jan FAIL). Class A: day-+5 harvest/reinforce + day-6 agent-network pulse under llvmpipe. Class B: WorldMap UI CanvasLayer **20** (Map Mode overflow) and toast layer **90** sat above TopInfoBar UILayer **10**, so pause/speed clicks never reached TimeManager. Fix: skip live-F5 agent networks and factory/presence day rebuilds; player-cap reinforce; toast container `MOUSE_FILTER_IGNORE` + combat coalesce (news history kept); Map Mode IGNORE+clip; UILayer **110**; `simulate_live_f5_softpipe_past_plus6` FAILS if still on 6 Jan. R2 clock ownership + Search Go + spine pin kept.

Play on `d53ee05` then **HARD-failed Esc→CC and Begin** (scenario overlay stuck; DEBUG window exited on map click) while headless soak stayed green. Cause: UILayer **110** sat above living title **90** and Command Center **100**; TestRunner also smashed HUD to 20; title-map misses fell through to inspector/assault. Fix: keep UILayer **110** + toast/Map Mode IGNORE (4x still reachable); living title **120**; Command Center **130**; TestRunner keeps 110; Esc on title opens CC; title owns map clicks. R2 clock + Search Go + spine pin + past-+6 soak **kept**.

Play on `d18cbae` then **HARD-failed the same Esc→CC / Begin wall** after that layer-only gate went green. Cause: live DisplayServer ≠ headless layer probe — MapRenderer `_input` armed map pick / chip / assault before GUI (same `gui_get_hovered_control` miss class as Search Go / 4x); Begin `pressed` is release-default so a swallowed release never fires; Esc listened for `keycode == KEY_ESCAPE` only (physical / `ui_cancel` no-op). Fix: title owns `_input` (Esc keycode+physical+`ui_cancel`, Begin rect + `ACTION_MODE_BUTTON_PRESS`); MapRenderer rect-first `_living_title_owns_click` and will not open chips while the title is up; one-frame Esc guard so title+renderer cannot toggle-close CC. Layer 120/130 **kept**. Headless `HeadlessIx1LivingTitleEscBeginTest` now fails if that live routing is missing.

Play on `3d00182` then **HARD-failed Esc→CC again** (window **stayed** — MapRenderer early-out held). Headless LivingTitleEscBegin still PASS (single `_input` Esc). Cause: Play always presses Esc **×2** (dismiss-then-idle); first Esc opened CC, second Esc `MainMenu._input` / `_on_menu_pressed` **toggle-closed** it (overlay unchanged). One-frame guard cannot cover two presses. Also `_input` may never run for computerUse DisplayServer Esc. Fix: sticky **open-only** while title is up (`open_command_center_stay`; MainMenu will not `_force_close`; `eoa_opened_from_living_title` meta); title + TestRunner `_process` Input-singleton poll; `key_label` / unicode 27; `EOA_LIVE_ESC` who-saw-it logs. Gate now fails if two Esc close CC or the poll/open-only path is missing. Lean windowed X11 probe (no 3520 board) PASS. Window-stay / layers 110/120/130 / past-+6 / R2 / Search Go / spine **kept**.

Play on `2a4ed6b` then **HARD-failed Esc→CC a fourth time**. Live log had **zero** `EOA_LIVE_ESC` — computerUse Escape never reached title `_input`, `_process` poll, or the Input singleton. Headless two-Esc stay + window probe still PASS (not live F5 proof). MapRenderer also `set_input_as_handled` on every non-panel left-press while the title was up, so HUD **Menu** was dead. Fix: keep sticky-open + instrumentation; nudge window focus + `Window.window_input` + explicit `ui_cancel`; ship **Command Center · Esc** on the panel and an **Esc · Menu** chip (layer 120); **Begin starts without Esc first**; title-up `_input` lets `_top_bar_owns_click` through. If Play still sees zero `EOA_LIVE_ESC`, click Esc · Menu or Begin and continue past+6→Search→spine. Esc remains a product gate — do not drop it forever. Window-stay / layers / past-+6 / R2 / Search Go / spine **kept**.

Play on `f9f249c` then **HARD-failed Begin + mouse CC + Esc ×2** with **zero `EOA_LIVE_PTR`** and **zero `EOA_LIVE_ESC`**. Headless 5/5 and lean X11 **xdotool windowactivate + click** were PASS — that is not Play's driver. computerUse clicks the visible Begin pixel **without activating** the Godot window; click-to-focus eats the ButtonPress so `handle_live_pointer` / GUI `pressed` / Input-singleton poll never run. Fix: `_process` polls `DisplayServer.mouse_get_button_state()` (global OS pointer) and hit-tests DisplayServer coords; **`EOA_LIVE_RAW_PTR` / `EOA_LIVE_RAW_KEY`** log any title-up mouse/key (heartbeat + press); left-column fallback after panel miss; documented **Enter / Space / B** (`eoa_living_begin` + Window + MapRenderer); `tools/eoa_playlike_title_click_prove.sh` steals focus then screen-clicks **without** `windowactivate`. Sticky-open · window-stay · layers 110/120/130 · past-+6 · R2 · Search Go · spine **kept**.

Play on `6573d01` then **HARD-failed Begin + Enter/Space/B + mouse CC** with **`EOA_LIVE_RAW_PTR` = 1** (`who=title.ready` boot only, `focused=true` ds=X11) and **zero** post-boot `EOA_LIVE_RAW_PTR` / `RAW_KEY` / `PTR` / `ESC`. Plain: computerUse clicks and keys **never entered this Godot X11 window**. DisplayServer poll + Enter/Space/B + lean computerUse PASS on a tiny title window are not Play's F5 TestScenario driver. Product Begin/Esc stay **FAIL**. Softpipe hatch (opt-in, default OFF): **`EOA_SMOKE_AUTO_BEGIN=1`** or `tools/eoa_play_f5_smoke_auto_begin.sh` dismisses the living title via `handle_live_begin` so past-+6 / Search Go / spine can run. Do **not** score Begin/Esc as PASS because the hatch fired. Do not use `EOA_SKIP_TITLE` (skips clock/Search/spine arm). Sticky-open · window-stay · layers 110/120/130 · past-+6 · R2 · Search Go · spine · RAW logs **kept**.

Play on `ae78507` then **hatch PASS** and **softpipe past-+6 FAIL** — clock stuck **1 Jan 1936 00:00** after 4x / pause-play / day. Product Begin/Esc still FAIL (post-boot RAW_KEY/ESC=0). Cause: after `handle_live_begin` the clock stays start-paused (R2 Begin ownership); Play F5 never delivers 4x/day. Smoke-only companion **`EOA_SMOKE_ADVANCE_PAST_PLUS6`** (default OFF; implied by `EOA_SMOKE_AUTO_BEGIN=1` unless `=0`) calls TopInfoBar `_set_game_speed(4)` then `TimeManager.apply_smoke_advance_past_plus6` (`advance_real_time` past 7 Jan). Wrapper sets both. Do **not** score product clock / Begin / Esc PASS or Play-F5 delivery fixed. Search / spine stay for Play computerUse after the date leaves 1 Jan.

Play on `838487a` then **hatch PASS** and **smoke past-+6 FAIL / incomplete live** — TopInfoBar 4x armed, live log never `tm.apply_smoke_advance_past_plus6 … past7=true`, on-screen clock stuck **1 Jan 1936 00:00**, Godot GUI **died** mid-advance. Headless DayTick past7 stayed green (not live softpipe). Cause: sync `advance_real_time` ×48 + combat flush under Play F5 load. Fix: live windowed path **chunks 1 tick/frame** (`step_smoke_advance_chunk`), defers AI land-battle starts / open-battle ticks, TestRunner polls until `past7=true` + `window_stay=1`. Headless `-s` keeps the sync prove plus a force-chunk pump. Do **not** score product Begin/Esc/4x/clock PASS or Play-F5 delivery fixed. Search / Spine / RoadLayer / Essen stay for Play after the date leaves 1 Jan.

Play on `8129648` then **hatch PASS** and **chunked past-+6 FAIL live** — armed `chunked start window_stay=1` + `after_hatch chunked pending`; live log **never** `past7=true`; on-screen clock stuck **1 Jan 1936 16:00**; Godot hung high-CPU then exited. Softpipe Search/Spine/RoadLayer/Essen NOT RUN. Cause: **idle-frame starvation** — 1 tick/`_process` never ran after TestRunner deferred grand visuals. Fix: live arm **softpipe catch-up** (`nudge_smoke_advance_chunk`) pumps the existing chunked stepper when frames are scarce (no combat flush). Do **not** score product Begin/Esc/4x/clock PASS or Play-F5 delivery fixed.

Play on `9625020` then **hatch + catch-up past-+6 PASS** (`past7=true` `catchup=1` `window_stay=1`; on-screen 8 Jan) and **stay-alive FAIL** — Godot exited before Search (attempt1) / during first Search-area click (attempt2). Logs ended at `[DEFERRED GRAND VISUALS]` + `Unit icons placed=252` after AI battles + air sorties; no clean quit. Cause: after catch-up, combat re-armed and 4x self-drove while TestRunner placed 252 icons (softpipe OOM class; DayTick family EXIT 137 post-PASS). Fix: live **stay-alive** after past7 — drop queued sim events, keep combat deferred, pause after the ok/past7 dict, gate front-chip flood, log `EOA_SMOKE_STAYALIVE` `no_quit=1` `window_alive=1`. Catch-up / no sync ×48 **kept**. Do **not** score product Begin/Esc/4x/clock PASS or Play-F5 delivery fixed.

Play on `8f89145` then **stay-alive PASS** (window held, heartbeats, deferred visuals) but **Search chrome FAIL** — live `SearchLineEdit` / `SearchGoButton` were not visible or focusable on the map world view (`relaunch_current.webp`: TopInfoBar + fully expanded Map Mode, no Search/Go). Softpipe Köln → Go → spine **NOT RUN**. Cause: Search lived on WorldMap UI CanvasLayer **20** with `PRESET_TOP_RIGHT` (CanvasLayer parent size 0 → x=-320 off-screen) and LineEdit min height **0**, under the full-width Map Mode wall. Fix: host Search on **UILayer 110** with an explicit TOP_LEFT pixel rect just under TopInfoBar, 28px LineEdit + styled field, `ensure_live_search_chrome` after hatch / stay-alive. Stay-alive / catch-up / hatch **kept**. Do **not** score product Begin/Esc/4x/clock PASS or Play-F5 delivery fixed.

Play on `c82233c8` then **stay-alive PASS** and harness `EOA_SMOKE_SEARCH_CHROME` `live=1`, but **Search pixels FAIL** — full-window + top-left shots show no LineEdit/Go; clicks + `Koln` produced no focus. Softpipe Köln → Go → spine **NOT RUN**. Cause: `live=1` was flag-only (visible/focus_mode/min-size); Search parented to a 0-size CanvasLayer so drawn height collapsed, and the field sat under the expanded Map Mode wall. Fix: host Search on **TopInfoBar** (UILayer 110 Control with real size) at **TOP_RIGHT of the 52px strip**; force LineEdit/Go geometry; `search_chrome_pixel_report` / `EOA_SMOKE_SEARCH_CHROME_PIXEL` fail `live=0` when rect is zero / off-screen / covered. Stay-alive / catch-up / hatch **kept**. Do **not** score product Begin/Esc/4x/clock PASS or Play-F5 delivery fixed.

Play on `48e4fe20` then **first-paint Search PASS** (LineEdit+Go on TopInfoBar right; PIXEL area=6924 host=TopInfoBar) but **sticky FAIL** — after More+/Steel:12000/Al reflow the chrome was gone (`search_chrome_top_right_missing.webp`); click at prior locus no focus; heartbeat PIXEL still live=1. Softpipe Köln → Go → spine **NOT RUN**. Cause: overlay `PRESET_TOP_RIGHT` on TopInfoBar is first-paint only; resource-strip settle ate TOP_RIGHT space. Fix: host Search **in-flow** on TopInfoBar RightContainer (Resources → Search+Go → Menu); `_keep_search_chrome_sticky` after layout/resources; PIXEL `in_bar` + Steel/Al/More cover; TestRunner `layout_settle` sticky check. Stay-alive / catch-up / hatch / first-paint host **kept**. Do **not** score product Begin/Esc/4x/clock PASS or Play-F5 delivery fixed.

Play on `9ebd17f` then **Search→Köln→Go + start LOGIC PASS** but **UX + stay-alive FAIL** — no toast / Building…; clock frozen 14 Jan; identical frames; no `EOA_ZOOM_BEGIN/END`; kernel **OOM 9.9 GB** (not a crash / harness quit). Headless 5/5 PASS. Cause: windowed `_draw` of `Ix1SpinePreviewDraw` at absolute GIS cents (Köln ~4254,944; edges 3–8u) with antialiased `draw_line` plus a light RoadLayer/sites rebuild on start. Fix: hub-local preview, finite/min-step/max-seg caps, no AA, toast/Building… this frame then deferred panel/soft-pan, no RoadLayer rebuild while queued/construction, xvfb `EOA_SMOKE_FRAME_GUARD` (frames advance, RSS < 2 GB / 60 s). Three-state / CompleteTest / hatch / stay-alive / Search / SPINE_START **kept**. Do **not** score product Begin/Esc/4x/clock PASS.

Play on `002df244` then **Search→Köln→Go + spine visible PASS** and **spine start LOGIC PASS** (`started IX-1 road spine on province 710417` + `EOA_SMOKE_SPINE_START visible=1 armed=1`) but **UX + stay-alive FAIL** — no toast / Building… / progress on screen; clock ran to 21 Feb 1936 at 1x; Godot then **exited silently** after a map zoom (log ended at SPINE_START, no SCRIPT ERROR, no quit line; RoadLayer / Essen blocked). Cause: `_on_build_road_spine_pressed` called `focus_province_by_id(pid)` with default **tactical 2.4** (same class as Search after +6d); toast and button state ran after that zoom; `build_road_connection` scheduled a **full** city/sites infra rebuild that raced the zoom/RoadLayer redraw; RoadLayer painted **all** major-owner hexes (120 cap unused); stdout was not flushed so the death had no bracket. Headless CompleteTest hung at 91% because `show_toast` skipped `_should_skip_toast_ui`. Fix: toast + **Building…** disabled **before** camera; `focus_province_by_id` default **soft** and tactical is redirected; `EOA_ZOOM_BEGIN` / `EOA_ZOOM_END` flushed; road writes use **light** + capped RoadLayer rebuild; Köln panel `LabelSpineProgress` + `EOA_SMOKE_SPINE_PROGRESS` / `COMPLETE`; three corridor visuals **queued → construction → built** (`EOA_SMOKE_SPINE_STATE`; `Ix1SpinePreviewDraw` `_draw` only — zoom does not rebuild RoadLayer); `HeadlessIx1RoadSpineCompleteTest` start→complete + state order + Bonn–Köln–Leverkusen RoadLayer + Essen off-spine; harness `EOA_HARNESS_QUIT` with a reason; headless toast no-op. Sticky Search / stay-alive / catch-up / hatch / `EOA_SMOKE_SPINE_START` **kept**. Do **not** score product Begin/Esc/4x/clock PASS or Play-F5 delivery fixed.

Later gameplay numbers (movement / export / supply / fuel) are **proposal only** in `SHIP_STATUS_FIX_IX1_SPINE_UX_CRASH_002DF244.md` § Road effects — no effect code in this slice.

## Player path (smoke)

1. Default F5 GER, Home Europe. Type **Köln** / **Cologne** / **Koln** / **Koeln** in the live Search **LineEdit** and click **Go** (or press Enter) — the button `pressed` / `text_submitted` signals call `open_province_inspector_from_search` (not a dead control after living title / +6d). Province inspector opens with **Build Road Spine** pinned on the chrome next to Settle (and as the first facility Build row) — not buried under Heavy Water / Kiel Canal construction rows, not Garrison, not silent. Miss toasts if resolve fails. Soft pan only (no tactical 2.4). Alt-click or empty-terrain on **Infra / Build** is the backup path. Esc / Close on Garrison restores the inspector; idle Esc still opens Command Center (Search focus is released, not a swallow).
2. Inspector **Build Road Spine** (not F10). Day-0 Mandate **0** is enough. Construction ring + ETA bar while the project ticks.
3. While the project runs the corridor shows **queued** (faint dashed) then **construction** (hatched / percent). On complete: toast / news **Road spine complete**; **built** RoadLayer paints the brown spine at Home zoom; inspector refresh.
4. Move / supply on the corridor is cheaper than the same province pre-build and cheaper than Essen control.

## Shipped APIs (reused, not reinvented)

- `Province.built_road_neighbors` + `MapManager.build_road_connection`
- `InfrastructureOverlayLayer` RoadLayer Line2D
- `InfrastructureDevelopmentManager` Invest projects / construction rings
- `Province.get_movement_cost()` + `SupplyPathfinder` (already consumes movement cost)
- `FormationMovement._infra_unit` uses the same road bonus so hops on-spine are cheaper

New front door: `InfrastructureDevelopmentManager.try_start_road_spine` / `link_ix1_road_spine_edges`.

## PASS criteria

1. SCRIPT_ERROR **0**. Esc → Command Center **HARD PASS** unchanged.
2. **Look:** readable road line on Bonn–Köln–Leverkusen at playable zoom (not F10-only).
3. **Impact:** spine `get_movement_cost` **strictly less** than pre-build; cheaper than off-spine Essen control.
4. Thin unittest `test_ix1_road_spine_product` green (edges present + cost delta + GER 1936 day-0 Mandate gate).
5. Tyrrhenian / Ligurian / Flanders / SE England / pale-map / Fill%·TOE **untouched**.

## PARKED (do not open from this PR)

- Dig2 pan / old G polyline dig / Maginot combat — IX-1 is a **new** named slice
- Rail network vertical (IX-2)
- Industry placement vertical (IX-3)
- Hampshire land residual
- Continent-wide road mesh
- Channel / Italy / SE England land rewrite
- Godot version bump
- `world_full` / play-board ID renumber
- Dual packages

## HOLD merge

Draft PR only. Do **not** merge until Scott unlocks a Play SHA.
