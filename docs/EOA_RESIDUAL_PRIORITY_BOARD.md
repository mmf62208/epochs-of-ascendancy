# EOA residual priority board (design loop)

**Date:** 2026-08-12  
**Roles:** Director (prioritize) · Implementer (close) · Skeptic (challenge)  
**Source truth:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md) · [`HOI4_EOA_GAP_REVIEW.md`](HOI4_EOA_GAP_REVIEW.md) · keep-going [`FORWARD_PROGRAM_2026_08_12.md`](FORWARD_PROGRAM_2026_08_12.md)  
**Constraints:** open HOI P0 = 0 · no dual spam · no `world_full` ID renumber · M6 human-only · no GameData split · no `origin/cursor/*` or `ceb60fdd-*` merge  

This board ranks **residual** open items after full-test machine close. Marks: **closed** · **deferred** · **human-only**.

---

## Ranked residuals (player value first)

| # | Item | Player value | Status | Evidence / pointer |
|---|------|--------------|--------|-------------------|
| 1 | **M6** human 20d + 60d narrative notes | Highest for *feel* | **human-only** | Not automated; PLAYTEST §0b checklist; items 3–15 still blank |
| 2 | **OrderCommandPanel play-strip clutter** (dual/harness buttons always visible) | High — panel reads as QA | **closed** (2026-08-03) | pure `order_panel_play_strip_product` · OrderCommandPanel play mode |
| 3 | **Assault Attack discoverability** (Ctrl+click / Attack hard to find) | High — war loop silent fail | **closed** (2026-08-03) | pure `first_session_assault_surface_product` · play strip Assault + MapRenderer hint |
| 4 | **Personality-weighted interactive multi-AI** | High — living campaign depth | **closed** (2026-08-03 · tag-scoped) | pure queue + `apply_production_for_tag` · `advance_days_for_country` · stock sim proves non-player tags |
| 5 | First-session hotkeys / F5–F9 save collision | High | **closed** (prior) | `first_session_hotkeys_product` · Ctrl+S/L · GER default |
| 6 | Supply hub fuel brief on **G** | Medium-high (HOI PARTIAL) | **closed** (prior) | `map_supply_hub_brief_product` fuel_score · MapRenderer toast |
| 7 | Interactive multi-AI light day (budgeted) | Medium-high | **closed** (prior) | `interactive_multi_ai_day_product` · `EOA_INTERACTIVE_MULTI_AI=0` |
| 8 | Mapmode icons states/terrain/resources/fronts/war_loop | Medium | **closed** (prior) | PASS65 assets · HudIconLibrary |
| 16 | **§0b first-session composer** | High — surfaces regress as a set | **closed** (PR 1 · `2b19597`) | `first_session_play_surface_product` · `eoa_full_test_gates.sh --quick` · **not M6** |
| 17 | **Assault hang-class** (execute inspector / full-fill / full-pin storm) | High — 3520-board freeze class | **closed** (PR 2 · `30910c2` greps green) | fill-pids · no `_update_unit_icons_for_test` · BM notify `target_pid` · success busy in `_assault_post_ui_light` |
| 18 | **Interactive multi-AI on official gates** | High — tag-scope honesty | **closed** (PR 3 · `7035837`) | `test_interactive_multi_ai_day_product` in `unit_board_play_path` |
| 9 | Soft 30fps map-tick proxy FAIL | Comfort | **deferred** | Honest FAIL ~29.4 fps; no invent PASS |
| 10 | Graphical `renderer_frame` FPS sample | Comfort | **deferred** | Optional post full-test |
| 11 | Deeper supply fuel *network* / economy | Medium | **deferred** | Soft beyond hub fuel_score |
| 12 | Designer commercial UX depth | Medium | **deferred** | Duals landed; HOI parity non-goal |
| 13 | Multi-month AI personality *full* depth | Medium | **deferred** | Personality weights on interactive day only |
| 14 | SE Asia micro-merge / densify | Low unless spam | **deferred** | Only if human reports density spam |
| 15 | Museum borders / 13k / multiplayer / V3 markets | — | **deferred** | Explicit non-goals |
| 19 | GameData mega-split (MASTER G0) | — | **deferred** | ~43k lines; not this cycle |
| 20 | DESIGN_LADDER_A corridor / transit / exclave sea | Play when G/F5 noisy | **deferred** | `ceb60fdd-pr-2` / `pr-3` stay parked; **do not merge** |

---

## This DAG machine closes (2026-08-12 · PR 1–3)

1. **§0b composer** — thin `first_session_play_surface_product` ANDs eight shipped builders; on `eoa_full_test_gates.sh --quick`. Not M6.  
2. **Assault hang-class** — greps green at `30910c2`: no `show_info_panel` / `force_border_update` on execute success; `refresh_after_capture_light` uses fill-pids (no `_refresh_province_fill_colors` / `_update_unit_icons_for_test`); BM notify uses `target_pid`; success-path busy clears in `_assault_post_ui_light` (failure still clears synchronously).  
3. **Multi-AI on official gates** — `test_interactive_multi_ai_day_product` in `--quick`; flush-site slice; GER-as-player excluded; `apply_supply` soft tick stays.

## 2026-08-03 machine closes (still closed)

1. **Play-strip declutter** — player mode shows Assault / Production / War path / Save / recommend-next; harness dual buttons only in debug or collapsed Extended.  
2. **Assault surface (discoverability)** — pure first-session assault steps + play-strip Assault enabled + toast when enemy adj selected. Hang-class integrity is row 17.  
3. **Personality rank on interactive multi-AI** — non-player majors ordered by aggression trait for daily production budget.

---

## Do not merge

- `origin/cursor/*` (this clone has `origin/cursor/fix-void-return-2453`)
- `feature/goals-forward-2026-06-18`
- any `execute-plan/ceb60fdd-*` / `ceb60fdd-stack-assembly`

Work this tree (`505d91d` + cad45c93 stack). GitHub push is **ops** (no SSH on the director machine). Dual board only via `EOA_SCENARIO=world_full`. Never renumber `world_full` IDs.

**Next human:** `tools/run_godot.sh --path . res://scenes/TestScenario.tscn` · PLAYTEST §0b items 3–15.  
**Next machine:** playtest-driven shipped-path fix only.

---

## Skeptic (see also `docs/EOA_SKEPTIC_PASS_2026_08_03.md`)

Over-claim risk: play-strip “closed” if GD still shows dual buttons in release; assault *discoverability* “closed” if only pure text with no player-visible wire; hang-class “closed” if greps are red; personality rank “closed” if not on the live day path / official gate. Each close requires wiring grep + unit test of **real** builder. Hang-class greps are green at `30910c2`. M6 remains human-only — do not invent complete.
