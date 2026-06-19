# 1918 Peace / Armistice Data

This folder holds data for the Armistice & Peace Conference system (see `docs/DESIGN_1918_ARMISTICE_PEACE_SYSTEM.md`).

## Files
- `1918_peace_terms.json` — Term buckets, historical markers, and mechanical effects for the opening conference (and reference for follow-on points). Historical options are explicitly flagged.
- Future: outcome templates, follow-on event definitions, dynamic spirit overrides, etc.

## Usage
Loaded/used by the future `PeaceOutcomeApplicator` / `PeaceConferenceManager` (or equivalent) and read by events, focus nodes, TechnologyManager gates, and agent mission outcome handlers.

## Extension Rules
- Every term option that matches real 1919 history must carry `"historical": true`.
- All effects must be consumable by NationalSpiritManager / NationalModifierManager, Technology unlocks, or the future focus/event systems.
- New diplomacy missions that affect the conference live in `data/agents/mission_definitions.json` (category "diplomacy") with `conference_window_only` where appropriate.

Data changes here should be reflected in the design doc and any outcome applicator code.