# COMBAT PHILOSOPHY — Epochs of Ascendancy

**Last Updated:** May 2026

## Core Principles
- Grand strategy first. Combat should feel meaningful and layered without becoming a tactical wargame.
- Equipment quality (Infantry + Sustainment) matters.
- **Readiness** and **Organization** are the two primary "health" stats.
- Logistics, preparation, terrain, and leadership should matter more than raw numbers.
- Prevent pure doomstacking through meaningful limits.

## Key Stats
- **Manpower / Crew**: Actual soldiers present.
- **Infantry Equipment**: Rifles, SMGs, assault rifles, machine guns.
- **Sustainment Equipment**: Uniforms, basic ammo, grenades, tools, medical supplies.
- **Readiness**: How combat-ready the unit currently is.
- **Organization (Org)**: Cohesion and ability to stay in combat / maneuver.
- **Soft Attack**: Damage vs infantry and soft targets.
- **Hard Attack**: Damage vs vehicles, tanks, fortifications, gun crews.

## Supply Modeling
- Supply is an **abstracted resource** produced by provinces.
- The **capital** is the main source.
- Large population/industrial provinces can produce limited local supply.
- Small islands or low-population areas produce almost nothing.
- Surrounded units can survive for a time on local production + stockpiles + airdrops.

## Combat Width & Doomstack Prevention
- Primarily driven by **Infrastructure** level of the province.
- Terrain (jungle, mountains, urban, etc.) applies strong modifiers.
- Doctrine, leader traits, and infrastructure investment can increase effective combat width.
- Only a limited number of units can effectively engage at once. Excess units act as reserves.

## Major Combat Modifiers
- **Terrain**: Strong defensive bonuses in jungle, forest, mountains, urban.
- **River Crossing / Amphibious / Paradrop**: Significant penalties to attacker.
- **Engineers**: Reduce penalties, speed up digging in, enable fort repair and basic construction.
- **Night Attacks**: Moderate penalty (not crippling). Some surprise is possible.
- **Recon (Ground + Air + Satellites)**: Reduces fog of war and improves planning.
- **Shore Bombardment**: Strong attacker bonus vs coastal targets.
- **Air Support / Interdiction**: Affects soft/hard attack and enemy organization/supply.
- **Leaders, Doctrines, Focuses**: National and army-level multipliers.
- **Being Surrounded**: Blocks external reinforcements and supply (unless local production exists).

## Unit Display (Planned)
- NATO symbol on map.
- Offense / Defense / Movement values shown.
- Readiness (left of symbol) / Organization (right of symbol).
- Recon and espionage can show estimated enemy combat power.

## Intelligence Sources
- Locals in owned or formerly owned provinces.
- Physical adjacency + open borders / trade.
- Naval observation.
- Air reconnaissance.
- Satellites + AI (late game).

## Future Expansion
- Full combat resolver using `get_final_combat_stats()`.
- Combined arms bonuses.
- Fortification levels and engineer construction.
- Weather and day/night cycles (mud/rain/snow/precip/vis full penalties + air CAS/interdict in resolver for world-class main loop).
- Leader traits and doctrine effects.
- **Naval (implemented 2026)**: Phased resolver (search/detect/ASW/engage/disengage) with dynamic multi-source spotting (air recon/NAVAL_STRIKE, subs, surface, sat), ECM/jamming reducing detect/guided, fuel/endurance consumption in Supply for sea deployments (low fuel = vuln/forced RTB), ASW sensor+helo+depth subphases, leader traits (sea_wolf/carrier_admiral) + initiative for disengage (high retreat% prevents annihilation per history Jutland/Midway/Falklands), screening orders, era/tech gating (visual->radar->ecm->sat/nuke). HoI4 task-force mission pattern + historical realism without micro. See BM/Resolver/Supply/Formation + /tmp/naval-combat-testing-summary.md . Fuel/repair at ports/hooks, combined carrier support to land.

## Combat Width & Infrastructure

Combat effectiveness is limited by Infrastructure and Terrain rather than raw unit count. This is one of the primary systems used to prevent doomstacking.

Every province has an Infrastructure level that determines its base Combat Width — the number of units that can effectively engage in combat at the same time.

- Attacking province infrastructure limits how many of the attacker's units can effectively participate in the battle.
- Defending province infrastructure also limits how many defending units can be brought to bear effectively.
- Terrain (mountains, jungle, forest, urban, marsh, etc.) applies strong modifiers to effective combat width.
- Excess units beyond the combat width act as reserves and can reinforce during the battle.
- Attacking from multiple directions can slightly increase the effective combat width for the attacker.
- Doctrine, leader traits, and infrastructure development can increase a side's effective combat width.

This system rewards operational planning, infrastructure investment, and combined-arms coordination over simply stacking the maximum number of units in one province.

Rules are data-driven in `data/combat/combat_width_rules.json` and applied via `CombatWidthCalculator` / `CombatResolver.get_combat_width_for_battle()`.

## Leaders (Foundation)

- `Leader` resource: skills 0–10 (attack, defense, organization, logistics, planning), traits, experience, army assignment.
- Trait definitions in `data/leaders/leader_traits.json` (e.g. Desert Fox, Sea Wolf, Arctic Bear).
- `LeaderManager` autoload: register leaders, promote (`promote_leader`), assign to armies, national chiefs (`chief_of_army`, `chief_of_navy`, `chief_of_air_force`, `chief_of_space_force`) with cost preview via `can_assign_national_position()` and country-wide `get_national_bonuses()`.
- Example historical leaders in `data/leaders/historical_leaders_1936.json` (Rommel, Dönitz).
- Combat hooks: `CombatResolver.get_effective_combat_power(..., army_id, terrain)` applies leader attack, organization, logistics, and terrain-specific trait bonuses (Desert Fox, Arctic Bear, etc.) via `Leader.get_terrain_modifier()`.
