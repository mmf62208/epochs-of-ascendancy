# Current State of Epochs of Ascendancy (May 25, 2026)

## Overview

The game has made significant progress on its core simulation loop and map systems. The central `TimeManager` now drives daily, monthly, and yearly ticks, with several systems reacting to it. Agent networks apply real daily pressure on provinces, and the first Technology tree (Support/Radio) produces measurable gameplay effects.

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
- [DESIGN_InfrastructureDevelopmentSystem.md](DESIGN_InfrastructureDevelopmentSystem.md) — **new (May 28)**: full active construction + development investment design, data model, integration points, code skeleton, phased plan
- [TECHNOLOGY_SYSTEM_DESIGN.md](TECHNOLOGY_SYSTEM_DESIGN.md) — tech system design
