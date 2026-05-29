# Infrastructure & Development Data

This folder holds the data-driven tables for the Province Infrastructure & Development System (see `docs/DESIGN_InfrastructureDevelopmentSystem.md`).

## Files

- `infra_levels.json` — Breakpoints, names, and core modifier values for infrastructure levels 1–25+. Used for supply, movement, combat width, repair pride, and era caps.
- `development_levels.json` — Parallel table for development (economic maturity). Drives factory eligibility, local supply generation, build speed, and max production lines.

## Usage

`InfrastructureDevelopmentManager` (skeleton at `scripts/map/InfrastructureDevelopmentManager.gd`) loads these on `_ready`. Province getters and `ProvinceEffects` will be updated in Phase B/C to optionally read from these tables instead of (or in addition to) the current hardcoded formulas in `Province.gd`.

## Editing

Keep keys stable across saves. When adding a new breakpoint, also update:
- `province_build_gates.json` (if it changes dev thresholds for factory types)
- Relevant technology node effects (construction_speed, max_infra, etc.)
- UI strings in `MapTechnologyContext.gd` and `ProvinceInsight.gd`

Version the JSON when making breaking changes.
