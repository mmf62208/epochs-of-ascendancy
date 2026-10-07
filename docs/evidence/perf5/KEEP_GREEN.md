# PERF-5 keep-green

Tip `ae88fea5` off main `61a80433`. Draft PR **#90**. Merge **HOLD**.

## Headless legend (`HeadlessPerf5LegendDayTickTest`)

Hard gate is **op counts**. Main headless already measures under 60 ms p95.

| | main `61a80433` product | tip `ae88fea5` |
|---|---|---|
| listener p50 / p95 / worst | 31.13 / **37.18** / **85.90** ms | 16.88 / **17.11** / **32.03** ms |
| StyleBox `changed` | **40** FAIL | **0** PASS |
| PanelContainer `theme_changed` | **40** FAIL | **0** PASS |
| CompareHintLabel `theme_changed` | **40** FAIL | **0** PASS |
| board walks / 20 days | n/a (no getter) | **20** (≤1/day) |
| text writes / 20 days | n/a | **1** |
| expiry walks | 0 (no cache) | **0** |
| pulse modulate active vs expired | **unchanged** (0,0,0,0) FAIL | **differs** PASS |
| contested after controller flip | PASS (full walk) | PASS |
| RESULT | **FAIL** failures=4 | **PASS** failures=0 |

Live before (brief §3, identical MapRenderer on main / #88): L-on mouse-off 389–431 ms, mouse-over 483–713 ms; StyleBox 227–284 ms. Live Xvfb not re-timed on this tip.

## Headless overlay (`HeadlessPerf5SupplyOverlayFreshTest`)

| | main product | tip |
|---|---|---|
| B1 L-on `drawn_routes` vs `sm_routes` | **0 vs 6** FAIL | identity PASS |
| B1 depot / capture / annex / recapture / remove | stale rings + `drawn=0` FAIL | PASS |
| B1 off-route infra pressure | FAIL (no dirty mark) | PASS engineers_recommended → empty |
| B2 silent `_routes` / depot (no signal) | dest stays `engineers_recommended` FAIL | dest=`route`, depot=`hub` PASS |
| B3 30 idle frames | 0 full (never reconciles) | 0 full + 0 patches PASS |
| B3 L off/on cache hit | roles=1 | roles=1 PASS |
| reconcile | n/a | **0.01–0.20 ms** (limit 5) |
| first L-on / L-off→capture→on | 52.0 / 45.9 ms | 55.8 / 7.6 ms |
| RESULT | **FAIL** failures=20 | **PASS** failures=0 |

## PERF-3 (`HeadlessPerf3SupplyToggleTest` unedited)

| | tip Home z0.318 | tip z0.760 |
|---|---|---|
| L-on / L-off / 2nd L-on | 172.6 / 5.6 / 365.8 ms | 46.8 / 4.1 / 45.8 ms |
| second L-on role compute | **unchanged (roles=1)** | **unchanged (roles=1)** |

#87 second-L-on invariant **green**.

## Mutants (each FAIL by selection on the tip)

| id | mutation | exit | failing assertion |
|---|---|---|---|
| A1 | pulse StyleBox written every call | 1 | StyleBox `changed=40`, panel `theme_changed=40` |
| A2 | count cache always dirty | 1 | walks 80/20 days; expiry walked 86→87 |
| A3 | count cache never refreshes (`if false`) | 1 | legend text did not show new contested |
| A4 | hint `add_theme_color_override` unconditional | 1 | CompareHintLabel `theme_changed=40` |
| A5 | expiry full legend+hint rebuild | 1 | expiry walked the board 22→23 |
| A6 | pulse modulate never changes | 1 | pulse modulate unchanged active vs expired |
| B1 | L-on reuses cache, no fingerprint / no L-on reconcile | 1 | L-off→capture→on captured pid **still has role route** |
| B2 | fingerprint poll removed (signals only) | 1 | B2 silent mutation `drawn_routes=7 sm_routes=4` |
| B3 | `province_data_changed` dirty mark disconnected | 1 | infra raise still `engineers_recommended` |
| B4 | `set_routes` skipped in reconcile | 1 | `drawn_routes=0 sm_routes=6` |
| B5 | incremental patch adds, never removes | 1 | infra raise still `engineers_recommended`; cache != fresh |
| B6 | always full recompute | 1 | B3 full recomputes 36→66; PERF-3 second L-on **FAIL** |
| B7 | always clean, reconcile never patches | 1 | every B1 ring check `drawn_routes=0` |
| B8 | per-pid skips trade_transit / infra | 1 | infra-pressure role `''` want `engineers_recommended` |

## Fail-on-main (new tests vs main product)

Both tests **FAIL by behaviour**, not missing methods: StyleBox/theme 40; pulse modulate 0; overlay `drawn_routes=0`; B2 dest stays `engineers_recommended`.

## #88 local test-merge (never pushed)

Onto `cursor/perf-4-daily-sim-tick-f390` @ `34d76f21`. Conflict: **`docs/CURRENT_STATE.md` only**. SNAPSHOT / TESTING_PLAN / gates / MapRenderer auto-merged. Overlay **PASS** (B2 silent mutation still green). Legend **PASS**. PERF-3 **PASS** (Home 155.0/1.2/167.5 ms, second L-on roles=1).

## #89 local test-merge (never pushed)

Onto `b64b98f3`. Conflict: **`docs/CURRENT_STATE.md` only**. MapRenderer auto-merged (`_tick_ui_close_release_swallow` kept in `_process`; PERF-5 helpers intact).

## Other

- `tools/eoa_full_test_gates.sh --quick` — exactly the 14 known `unit_board_play_path` reds.
- Seed 193601 infra picks unchanged (no SupplyManager / GameData / infra-AI edits): JAP 903951 / FRA 710739 / ITA 710859 / ENG 711481 / POL 711054 / SOV none / JAP 902474.
- File fence: MapRenderer listed functions + SupplyOutlineBatchLayer + new tests + gates after `launch_perf3_supply_toggle` + docs. No SupplyManager.gd.
