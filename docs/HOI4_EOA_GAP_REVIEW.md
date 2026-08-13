# EOA ↔ HOI4 gap review (full-test machine bar)

**Date:** 2026-07-31  
**Audience:** Director, implementers, playtesters  
**Companion map inventory:** [`WORLD_CLASS_MAP_REVIEW.md`](WORLD_CLASS_MAP_REVIEW.md)  
**Live board truth:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md)  

This is an **honest pillar map**, not a claim of commercial Paradox parity. Museum borders, ~13k HOI provinces, multiplayer product, and full V3 markets/pops are **non-goals**.

**Default board:** `world_accurate` **~3520** (post US + full RoW sparse; Europe NUTS dense; US 1–4/state playable). Map machine densify is **closed**.

---

## 1. HOI4 defining pillars → EOA truth

Status key:

| Mark | Meaning |
|------|---------|
| **LANDED** | Machine gate exists on shipped API/product; pure and/or headless green |
| **PARTIAL** | Core path works; depth below HOI commercial bar (acceptable for full-test) |
| **OPEN** | Blocks full-test feel and is machine-closable (P0) |
| **DEFER** | Human-only, non-goal, or post full-test depth |

### 1.1 Industry / production

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| Factories / production lines | Production honesty, factory retool, war economy primaries | **LANDED** | `production_honesty_primary_command_product`, `factory_retool_primary_command_product`, `war_economy_primary_command_product` |
| Equipment stockpile → units | EquipmentFlow map + produce path | **LANDED** | `equipment_flow_product` · MapRenderer **I** / WarLoop |
| Strategic resources | Resources layer + F9 mapmode | **LANDED** | `map_resources_mapmode_product` · F9 + toolbar |
| Division designer depth | Module designers present; not HOI full designer suite | **PARTIAL / DEFER** | Designers duals landed; full HOI designer UX out of full-test scope |

### 1.2 Research

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| Research queue | Research queue primary | **LANDED** | `research_queue_primary_command_product` |
| Tech tree / branches | Tech + focus tree primaries | **LANDED** | `tech_research_primary_command_product`, `focus_tree_primary_command_product` |
| National focuses as war path | Focus war path | **LANDED** | `focus_war_path_product` / primary |

### 1.3 Politics / diplomacy

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| War goals / alliances | War goal + alliance primary | **LANDED** | `war_goal_alliance_primary_command_product` |
| Peace conferences | Peace conference primary | **LANDED** | `peace_conference_primary_command_product` |
| Occupation / resistance | Occupation primary + resistance products | **LANDED** | `occupation_primary_command_product` |
| Manpower laws | Manpower laws primary | **LANDED** | `manpower_laws_primary_command_product` |
| Ideology/party depth HOI-scale | Cultural/hidden-hand present; not full HOI politics UI | **PARTIAL / DEFER** | Post full-test polish |

### 1.4 Land multi-front war planning

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| Multi-front edges on real map | Maginot, Polish, Alps, Baltic, CHI–JAP | **LANDED** | `world_accurate_multi_front_product` |
| Live border assault targets | Enemy borders (not own stations) | **LANDED** | `MapManager.collect_live_border_assault_targets` · Fronts / **B** |
| First-session war surface | WarLoop + flow + assault brief | **LANDED** | `map_war_path_surface_product` · toolbar WarLoop · **Shift+I** |
| Multi-front execute | Headless Maginot+Polish | **LANDED** | `HeadlessWorldAccurateMultiFrontAssaultTest` |
| Front continuity campaign | Front continuity primary | **LANDED** | `front_continuity_primary_command_product` |

### 1.5 Supply / logistics

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| Supply map / corridor | Capital→front BFS corridor | **LANDED** | `map_supply_corridor_product` · **G** |
| Logistics theater day | Logistics supply primary | **LANDED** | `logistics_supply_primary_command_product` |
| Deep HOI supply hubs / fuel economy | Corridor + hub rank + soft fuel_score on G toast · LOG primary | **PARTIAL** | Fuel brief landed 2026-08-03; full fuel economy still soft |

### 1.6 Air / naval theaters

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| Air theater ops | Air theater + multi-phase primaries | **LANDED** | `air_theater_primary_command_product` |
| Fleet autonomy / naval ops | Fleet autonomy + naval multi-phase | **LANDED** | `fleet_autonomy_primary_command_product`, `naval_multi_phase_primary_command_product` |
| Convoy / sealane | Convoy sealane primary | **LANDED** | `convoy_sealane_primary_command_product` |
| Naval chokepoints on map | 34 chokes painted | **LANDED** | board data + SNAPSHOT |
| Full HOI naval designer / TF micro | Present but not commercial depth | **PARTIAL / DEFER** | Non-goal for full-test |

### 1.7 Espionage / intel

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| Intel network | Intel network primary | **LANDED** | `intel_network_primary_command_product` |
| Agent missions | Agent mission board primary | **LANDED** | `agent_mission_board_primary_command_product` |
| Counterintel | Intel counter primary | **LANDED** | `intel_counter_primary_command_product` |
| Combat intel estimate | Combat intel estimate primary | **LANDED** | `combat_intel_estimate_primary_command_product` |

### 1.8 OOB / deploy / map star

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| Historical OOB | Historical OOB primary | **LANDED** | `historical_oob_primary_command_product` |
| Station deploy capital→hub→border | HOI deploy path | **LANDED** | multi-front deploy tests + spawner |
| Political map readability | HOI-style international borders + fills | **LANDED** | `ownership_mapmode_readability_product` · MapRenderer |
| Capitals pickable | 8 majors land+owned | **LANDED** | `world_accurate_capital_pick_product` · pick harness |
| Unit counters LOD | Strategic hide + Shift+U | **LANDED** | `map_unit_counter_lod_product` |
| Playable density (not 3k US counties / ADM2 soup) | US merge + RoW sparse | **LANDED** | US 130 · RoW sparse bands · board ~3520 |
| Nation / state labels | Capital landmass + state labels @ operational | **LANDED** | `map_nation_label_landmass_product`, `map_state_labels_surface_product` |

### 1.9 Session / save (HOI campaign continuity)

| HOI need | EOA | Status | Evidence |
|----------|-----|--------|----------|
| Save / load mid-campaign | Command Center + SaveLoadManager | **LANDED** | `save_resume_primary_command_product`, `save_browser_campaign_product`, MainMenu CC |
| Autosave | Autosave session primary | **LANDED** | `autosave_session_primary_command_product` |

---

## 2. P0 machine-closable list (this goal)

**Open P0 count: 0.**

All pillars required for a full-test HOI-like session have **LANDED** machine gates on shipped products/APIs as of 2026-07-31. Remaining gaps are **PARTIAL** depth or **DEFER** (human M6, soft FPS hard-pass, designer/museum/multiplayer non-goals).

### Proof gates (re-run for closure)

| Gate | Entry |
|------|-------|
| Board integrity | `test_world_accurate_board` · map accuracy QC |
| Density | `test_row_sparse_density_product` · `test_us_state_province_density_product` |
| Capitals | `test_world_accurate_capital_pick_product` · `map_manager_pick_harness_accurate.gd` |
| Multi-front / assault | `test_world_accurate_strategic_and_assault` · `test_world_accurate_multi_front_and_deploy` · `HeadlessWorldAccurateMultiFrontAssaultTest` |
| WarLoop / Fronts / supply | `test_map_war_path_surface_product` · `test_map_live_border_fronts_surface_product` · `test_map_supply_corridor_product` |
| Political readability | `test_ownership_mapmode_readability_product` |
| Pillar matrix (this review) | `test_hoi_full_test_gap_matrix_product` · pure `hoi_full_test_gap_matrix_product` |
| Save / resume | `test_save_browser_campaign_product` · `test_save_resume_primary_command_product` · campaign feel D3 |
| Industry / research / diplo / air / naval / intel / OOB primaries | respective `*_primary_command_product` unit tests (dual-green history in TODO.md) |

### Explicit non-P0 (do not invent as gates)

- **M6** human 20d/60d narrative notes — human-only  
- Soft 30fps hard-pass on map-tick proxy — honest FAIL allowed  
- Museum borders / 13k provinces / multiplayer / full V3 markets  
- HOI division designer commercial depth  
- SE Asia micro-merge unless integrity fails  

---

## 3. Opportunities (post full-test, not P0)

Ordered by player value after M6 human notes:

1. Graphical `renderer_frame` FPS sample (honest) if soft 30 still fails on proxy  
2. ~~Supply depth (hubs) beyond corridor polyline~~ — **partially landed 2026-07-31**: pure `map_supply_hub_brief_product` ranks capital + `key_provinces` by land hops; MapRenderer **G** picks best hub → front + toast. Fuel/network depth still soft.  
3. SE Asia density tune if playtest reports spam  
4. Designer UX polish (not new dual spam)  
5. Multi-month AI personality depth  

---

## 4. Matrix product

Machine mirror of §1–2: `tools/map_generation/lib/hoi_full_test_gap_matrix_product.py`  
Calls **real** shipped product builders and fails if any P0 pillar is not OK.

```bash
python3 -m unittest tools.map_generation.tests.test_hoi_full_test_gap_matrix_product -v
```

---

## 5. Bottom line

EOA’s full-test path already covers HOI’s **defining machine pillars** on a finished GIS board (~3520). World-class *feel* still needs **human M6** notes and optional depth polish—not another densify wave or dual-package factory.
