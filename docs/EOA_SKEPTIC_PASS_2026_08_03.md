# Skeptic pass — residual closes (2026-08-03)

**Role:** Adversarial reviewer of “closed” claims on the residual priority board.  
**Board:** [`EOA_RESIDUAL_PRIORITY_BOARD.md`](EOA_RESIDUAL_PRIORITY_BOARD.md)

---

## Challenge 1 — Play-strip “closed” while duals still exist in debug

**Risk:** Claim “OrderCommandPanel decluttered” while debug builds still show Stream α / dead-audit / phase ribbons — playtesters often use debug Godot and see harness again.

**Resolution:** Intentional. Play mode is always first (`_rebuild_play_mode_strip`). Harness is **gated** on `OS.is_debug_build()` via `_rebuild_harness_debug_strip`. Release/export path is clean. Documented on board as closed for **player mode**, not “zero dual code deleted.”

**Still open (defer):** Further collapse Extended packages for non-debug if export still bundles confusion — not this goal.

---

## Challenge 2 — Assault surface is toast-only, not a guaranteed Attack button win

**Risk:** `toast_assault_surface` after **B** does not create a persistent Attack control on the map; Ctrl+click still requires formation staging. Over-claim if we say “assault is always obvious.”

**Resolution:** Close is **discoverability**, not combat AI. Evidence: pure product steps + play-strip Assault + toast after Fronts + existing Ctrl+click `_try_execute_province_attack`. Honest partial if no friendly formation.

**Defer:** Persistent province OOB Attack chip when enemy adj + formation (next polish if human notes demand).

---

## Challenge 3 — Personality rank is soft weights, not living doctrine AI

**Risk:** Aggression constants in GameData / pure product are static floats, not event-driven multi-month personality primary. Claiming “multi-month AI personality depth closed” would over-claim.

**Resolution:** Board marks **full** multi-month personality as **deferred**. This goal only closed **personality-weighted interactive multi-AI day queue** (budget still 3+1). Tests prove GER ranks above FRA for production slots.

---

## Challenge 3b — Live multi-AI applied player production (CRITICAL, fixed)

**Risk (confirmed by adversarial panel):** `apply_interactive_multi_ai_day_live` ranked AI majors then called `apply_order_panel_action("apply_production")`, which always mutates the **player** stockpile via `LeaderManager` tag. Queue `tag` was telemetry only; F5 days could triple player production.

**Fix:**
- `ProductionManager.advance_days_for_country(tag)`
- `GameData.apply_production_for_tag(tag)`
- Multi-AI loop calls **only** `apply_production_for_tag` for production items
- Pure `resolve_tag_scoped_apply_ops` + `simulate_tag_stockpile_applies` prove prod_tags drive per-tag stock deltas and player stock stays 0
- Live wiring test fails if multi-AI body still calls order-panel `apply_production`

---

## Challenge 4 — M6 still human-only

**Risk:** Closing three machine items does not make the game “100% play-proven.”

**Resolution:** Explicit **human-only** on board for M6. No invented narrative notes.

---

## Bottom line

Three machine closes are real on shipped paths with unit tests of real builders. Over-claims above are either scoped down or deferred on the priority board — not silent.
