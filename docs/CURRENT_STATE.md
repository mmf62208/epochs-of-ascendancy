# Current State of Epochs of Ascendancy (May 28, 2026)

## Overview

The game has made significant progress on its core simulation loop and map systems. The central `TimeManager` now drives daily, monthly, and yearly ticks, with several systems reacting to it. Agent networks apply real daily pressure on provinces, and the first Technology tree (Support/Radio) produces measurable gameplay effects.

## Map Generation Pipeline (May 28, 2026)

**Status:** Active vertical slice — test scenario playable in Godot

Major progress on the Phase 1 Europe pipeline (`tools/map_generation/`):

- **Tooling:** `lib/naval_analysis.py` (coastal/chokepoint/bridge detection) and `lib/subdivision_utils.py` (PCA-based splitting with coastal edge preservation during cuts).
- **Merge:** `scripts/apply_phase1_merge.py` rebuilds adjacency, protects chokepoints during rewiring, and distributes resources, development, special features, and cities across child provinces.
- **Output:** Layered JSON under `output/phase1_europe/` plus merged bundles (`merged_test_map/`, `merged_improved_v2/`, `merged_v3_closest_wiring/`).
- **Godot test map:** Persistent **Phase 1 Europe Test** scenario (~180 provinces) via `data/provinces_phase1_test/` + `data/scenarios/phase1_europe_test.json`; load from Debug Overlay with camera framing and diagnostics.
- **Design:** Full pipeline spec in [MAP_GENERATION_PIPELINE_DESIGN.md](MAP_GENERATION_PIPELINE_DESIGN.md); Hidden Hand faction design captured in [HIDDEN_HAND_DESIGN.md](HIDDEN_HAND_DESIGN.md).

**Next:** Refine splitter coastal edges on cut lines; produce production-grade layered exports; scale toward the 350–450 province Europe target.

## Key Systems Status

### Time System

- **Status:** Strong
- `TimeManager` is the central clock.
- Daily, monthly, and yearly signals exist and are being used.
- Real-time advancement + pause/speed control works via `TopInfoBar`.

### Map & Overlays

- **Status:** Good / Improving
- Active overlay layers: `ConflictOverlayLayer` + `AgentNetworkLayer`.
- Multi-overlay visuals (contested + agent + supply) are functional.
- Daily agent pressure (supply disruption + infrastructure sabotage) is visible on the map: province tints, ⛟/⚙ glyphs, ambient ring pulse, infra/depot status bars under rings, repair/depot lines in tooltips and inspector.

### Technology

- **Status:** Partial but promising
- `TechnologyManager` is mature.
- Support/Radio tree is a functional vertical slice with real impact in Supply.
- Map integration via `MapTechnologyContext` (tooltips, legend, mode chips, inspector).

### Agent Networks

- **Status:** Good
- Update daily via `AgentManager.advance_networks_daily()`.
- Apply real province-level effects (national debuff, depot hits, infra chips).
- Visual and tooltip feedback improving.

### Repair / Counter-Play + Infrastructure Foundation

- **Status:** Strong passive simulation + daily duel (excellent foundation)
- Automatic slow infrastructure repair with full breakdown (`MapManager.get_infrastructure_repair_breakdown`): base + infra pride + stability + tech_focus + real engineer brigades from CombatPresenceRegistry.
- Agent sabotage creates visible "duel" (depot sabotage_level + infra_sabotage focus networks). Counter-intel clears effects.
- `ProvinceEffects` aggregator (base dev/infra + NationalSpiritManager + NationalModifierManager) is the canonical source for Supply, Combat, movement, and UI.
- Rich getters on `Province` (throughput, combat width, org recovery, interdiction resistance, etc.) and `MapManager` effective-value helpers.
- Build eligibility gates (`province_build_gates.json`) already respect development by era/domain/factory_type and drive production picker + tooltips.
- **Active development still missing**: No player/AI "Invest" action to raise levels. "Invest here" language exists in UI strings but has no backend. See new design: `docs/DESIGN_InfrastructureDevelopmentSystem.md`.

## Major Gaps

- **Province Infrastructure & Development (active player investment)** — now the highest-priority gap. Full design document created May 28. Passive effects + repair are mature; the construction/project loop is not.
- Save/Load is partial (provinces dev/infra + many managers are covered, but not yet active infra projects or full roundtrips for 500+ turn sessions).
- Map build eligibility is gated in data but has no live "raise dev to unlock" lever yet.
- Many systems still need deeper daily/monthly tick wiring.
- Testing infrastructure is weak (see [TESTING_PLAN.md](TESTING_PLAN.md)).
- Top bar / menu needs modernization.

## Related Docs

- [TESTING_PLAN.md](TESTING_PLAN.md) — manual and regression checklist
- [MAP_IMPLEMENTATION_PLAN.md](MAP_IMPLEMENTATION_PLAN.md) — province/map roadmap (Phase 1 complete)
- [MAP_GENERATION_PIPELINE_DESIGN.md](MAP_GENERATION_PIPELINE_DESIGN.md) — procedural Europe expansion pipeline (Phase 1)
- [HIDDEN_HAND_DESIGN.md](HIDDEN_HAND_DESIGN.md) — secret faction / three power centers design (May 28)
- [DESIGN_InfrastructureDevelopmentSystem.md](DESIGN_InfrastructureDevelopmentSystem.md) — **new (May 28)**: full active construction + development investment design, data model, integration points, code skeleton, phased plan
- [TECHNOLOGY_SYSTEM_DESIGN.md](TECHNOLOGY_SYSTEM_DESIGN.md) — tech system design
