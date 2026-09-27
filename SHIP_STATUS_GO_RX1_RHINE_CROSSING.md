# SHIP STATUS — RX-1 Rhine Crossing

**HOLD for Play. Do not merge.**

| | |
|--|--|
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/57 (draft) |
| **Branch** | `cursor/rx1-rhine-crossing-e117` |
| **Base** | `1d092a14` IX-1 Road Spine |
| **Tip** | `21981465d8387b2846859b1d3f1f1eca8b4f69b2` |

## Tunable constants (single place: `data/map/rx1_rhine_crossings.json` + `Rx1RhineCrossing.gd`)

| Constant | Value |
|----------|-------|
| `RHINE_UNBRIDGED_MOVE_MULT` | **2.0** |
| `RHINE_BRIDGED_MOVE_MULT` | **1.15** |
| `RHINE_UNBRIDGED_ATTACK_MALUS` | **0.30** |
| `RHINE_BRIDGED_ATTACK_MALUS` | **0.10** |
| `first_session_mandate_cost` | **0** (IX-1-class starter grant) |

## Crossing edges (NUTS3, never renumbered)

| Edge | Names | 1936 |
|------|-------|------|
| 710413–710412 | Rhein-Kreis Neuss ↔ Mettmann | **UNBRIDGED** (Build Bridge target; ferry / no 1936 road bridge) |
| 710413–710401 | Neuss ↔ Düsseldorf | Bridged — Oberkasseler Brücke (1898) |
| 710417–710418 | Köln ↔ Leverkusen | Bridged — Deutz 1915 / Mülheim 1929 |
| 710417–710424 | Köln ↔ Rheinisch-Bergischer Kreis | Bridged — same Köln road bridges, east face |
| 710416–710425 | Bonn ↔ Rhein-Sieg | Bridged — Bonn Rhine bridge (1898) |
| 710402–710415 | Duisburg ↔ Wesel | Bridged — Friedrich-Ebert-Brücke (1907) |

Köln–Essen is **not** a crossing (not a GISCO shared Rhine border). Face-bank: Rhine flows north; cities use centroid bank.

## Alignment evidence

Stored `rivers_world.json` Rhine **id 321** is mercator-Y (Y ~1781–1864). NUTS3 is equirect `lonlat_to_canvas`. Invert + reproject. Canvas distances: Köln **0.051**, Bonn **0.446**, Düsseldorf **0.355**, Duisburg **1.361**, Essen **7.033** (off-river). Mid-zoom evidence (not live F5 Play): `/opt/cursor/artifacts/rx1_rhine_midzoom_bonn_koeln_duesseldorf_duisburg.png`. Inspector mocks: `rx1_inspector_no_bridge_neuss.png`, `rx1_inspector_bridged_koeln.png`.

## Guard results

| Guard | on `1d092a14` | on tip |
|-------|----------------|--------|
| `test_rx1_rhine_crossing_product` (5) | **FAIL** 4 fail + 1 error (no spec / no APIs) | **PASS** 5/5 |
| `HeadlessRx1RhineCrossingTest` | would fail (class / APIs missing) | **RESULT=PASS** · SCRIPT ERROR **0** |
| `HeadlessRx1RhineLiveStayAliveTickTest` | would fail (no RX-1 project) | **RESULT=PASS** · +6d 0% → COMPLETE via `advance_real_time` · SCRIPT ERROR **0** |
| `tools/eoa_rx1_bridge_live_progress_guard.sh` | not run (windowed F5 smoke) | **not run this session** — smoke harness is **not** the product |

IX-1: `test_ix1_road_spine_product` **15/15**; `HeadlessIx1RoadSpineLiveStayAliveTickTest` **RESULT=PASS**. Spine APIs unchanged.

`--quick` `unit_board_play_path` still has **pre-existing** `living_unit_order_loop_product` fails on **both** `1d092a14` and this tip (`air_region_cas`, `peace_occupation`, `nation_era_next`, `map_country_select`, `playtest_clock`). Not an RX-1 regression.

## Known gaps (honest)

- Windowed F5 `eoa_rx1_bridge_live_progress_guard.sh` was **not** executed here. Headless live stay-alive is the machine proof of FIX3 `advance_real_time`.
- Artifact PNGs are **alignment / inspector mocks**, not live Play screenshots.
- GISCO 20M rings are coarse; only the six GO candidates with opposite center-banks are listed.
- Blow/capture, rail/pontoon, other rivers, hills, road tiers: **OUT**.
- Smoke harness is **not** the product.
