# EOA residual priority board (design loop)

**Date:** 2026-08-03  
**Roles:** Director (prioritize) · Implementer (close) · Skeptic (challenge)  
**Source truth:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md) · [`HOI4_EOA_GAP_REVIEW.md`](HOI4_EOA_GAP_REVIEW.md)  
**Constraints:** open HOI P0 = 0 · no dual spam · no `world_full` ID renumber · M6 human-only  

This board ranks **residual** open items after full-test machine close. Marks: **closed** · **deferred** · **human-only**.

---

## Ranked residuals (player value first)

| # | Item | Player value | Status | Evidence / pointer |
|---|------|--------------|--------|-------------------|
| 1 | **M6** human 20d + 60d narrative notes | Highest for *feel* | **human-only** | Not automated; PLAYTEST §0b checklist |
| 2 | **OrderCommandPanel play-strip clutter** (dual/harness buttons always visible) | High — panel reads as QA | **closed** (this goal) | pure `order_panel_play_strip_product` · OrderCommandPanel play mode |
| 3 | **Assault Attack discoverability** (Ctrl+click / Attack hard to find) | High — war loop silent fail | **closed** (this goal) | pure `first_session_assault_surface_product` · play strip Assault + MapRenderer hint |
| 4 | **Personality-weighted interactive multi-AI** | High — living campaign depth | **closed** (this goal · tag-scoped fix) | pure queue + `apply_production_for_tag` · `advance_days_for_country` · stock sim proves non-player tags |
| 5 | First-session hotkeys / F5–F9 save collision | High | **closed** (prior) | `first_session_hotkeys_product` · Ctrl+S/L · GER default |
| 6 | Supply hub fuel brief on **G** | Medium-high (HOI PARTIAL) | **closed** (prior) | `map_supply_hub_brief_product` fuel_score · MapRenderer toast |
| 7 | Interactive multi-AI light day (budgeted) | Medium-high | **closed** (prior) | `interactive_multi_ai_day_product` · `EOA_INTERACTIVE_MULTI_AI=0` |
| 8 | Mapmode icons states/terrain/resources/fronts/war_loop | Medium | **closed** (prior) | PASS65 assets · HudIconLibrary |
| 9 | Soft 30fps map-tick proxy FAIL | Comfort | **deferred** | Honest FAIL ~29.4 fps; no invent PASS |
| 10 | Graphical `renderer_frame` FPS sample | Comfort | **deferred** | Optional post full-test |
| 11 | Deeper supply fuel *network* / economy | Medium | **deferred** | Soft beyond hub fuel_score |
| 12 | Designer commercial UX depth | Medium | **deferred** | Duals landed; HOI parity non-goal |
| 13 | Multi-month AI personality *full* depth | Medium | **deferred** | Personality weights on interactive day only |
| 14 | SE Asia micro-merge | Low unless spam | **deferred** | Only if human reports density spam |
| 15 | Museum borders / 13k / multiplayer / V3 markets | — | **deferred** | Explicit non-goals |

---

## This goal machine closes (≥3)

1. **Play-strip declutter** — player mode shows Assault / Production / War path / Save / recommend-next; harness dual buttons only in debug or collapsed Extended.  
2. **Assault surface** — pure first-session assault steps + play-strip Assault enabled + toast when enemy adj selected.  
3. **Personality rank on interactive multi-AI** — non-player majors ordered by aggression trait for daily production budget.

---

## Skeptic (see also `docs/EOA_SKEPTIC_PASS_2026_08_03.md`)

Over-claim risk: play-strip “closed” if GD still shows dual buttons in release; assault surface “closed” if only pure text with no player-visible wire; personality rank “closed” if not called from live day path. Each close requires wiring grep + unit test of **real** builder.
