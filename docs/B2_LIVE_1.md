# B2-LIVE-1

B2 (`_ai_offensive_ramp_ok`) now runs on the shipped 1936 start. The previous
`_ai_has_committed_field_army(tag)` skip treated any stationed non-`garrison_1936`
division as a committed army, so Maginot chips, ScenarioLoader OOB, and
`capdef_*` capital raises all switched the ramp off.

## (a) Per-war front army

`_ai_has_committed_field_army(tag, def_tag)` is true only when at least
`FIELD_ARMY_FRONT_MIN = 3` non-`garrison_1936`, non-`capdef_` division/garrison
formations sit on hexes the tag owns that touch land `def_tag` controls.
Cached per `tag|def_tag` with station gen + board epoch.

**Why 3:** live 1936 OOB dump (`HeadlessB2Live1Test` A1):

- fingerprint `garrisons placed=536 skipped_occupied=40 targets=576` (LIVE, not APPROX)
- GER land OOB 6, of which **ger_pol=0** and **ger_fra=5** (Maginot 710173×2 + neighbour plus HOI leftovers on the FRA border)
- 3 sits above a 1-hex leftover and matches the Maginot chip count on one front without treating that as a POL army
- CL1 still qualifies: it stations one `cl1_*` on every GER-POL border hex (16 on this board)

`capdef_*` never counts, even with 4 on the POL front (A2b).

## (b) Save compatibility

- `_ai_garrison_seed_n` does not back-fill `peace_state.garrison_seed_n` from current `garrison_1936` units (war raises reuse those ids). Missing key uses `LeaderManager.garrison_1936_seed_target_n` (same border+capital rule as the 1936 seed).
- `LeaderManager.get_save_data` emits `garrisons_1936_seeded` only when true (identity hashes that never seeded stay put). `apply_save_data` restores it; old blobs without the key infer true when any loaded formation has `garrison_1936`.
- Non-forced `seed_1936_start_garrisons` does not overwrite an existing `garrison_seed_n`. Continue (`force=false`) returns `already=true` once the latch is restored.
- `GameData` initial `peace_state` and the migration `has` guards include `garrison_seed_n: {}`. Round-trip is GameData + LeaderManager only (`SaveLoadManager.gd` untouched).

B1 fresh-game raise budget (seed × 10%, clamp 1–10):

`GER 10, FRA 10, ENG 10, SOV 4, ITA 3, JAP 2, USA 4, POL 4, CZE 2`

## (c) Caches

- Light capture: extra `bump_ai_board_epoch()` removed. Owner change still bumps once via `WarStateDomain.note_province_owner_changed` (`skip_emit` skips the MapManager signal). C1 epoch delta 2 → 1.
- Threat rebuild scans only hexes that `_station_touches_enemy`. C2 on GER-vs-POL garrison seed: **rebuilds=2, scanned=38, own_land=421** (base scanned key missing / full 421). COVER hole fills batch `bump_ai_station_gen` once per tag per pass. Same COVER station map.

## (d) Ramp phases

`[111, 7]`, `wd >= 111`, and unused `RAMP_SR_FAST` deleted. `RAMP_END_DAYS` stays 90.
Comments: 21d hold, 15d gaps d21-50, 10d gaps d51-89, unrestricted from d90.

## (e) Nits

- `get_formations_for_country` caches the gffc `typeof`/`has_method` check (T5 counter still live).
- `AI_RAMP_BLOCK` renamed `AI_RAMP_SR_LOW` (only BattleManager printed it).
- Deleted unused `_ai_has_adjacent_enemy_division`.
- `AI_HOP_CACHE` prints on signature change or every 30 days.
- DefenceTest comment no longer claims CAMPAIGN_LOOP gates B2.

## LIVE-OOB arm

USA observer, GER declares on POL, real spawn + chips + `seed_1936_start_garrisons(true)`.
GER capital raise `capdef_GER_710300` at d21. Pair stays not fielded.

| day | tag | foe | fielded | phase | gap | ready | rej_ramp |
|-----|-----|-----|---------|-------|-----|-------|----------|
| 21 | GER | POL | false | GAP | 15 | true | 0 |
| 21 | POL | GER | false | OPEN_SR<1 | 15 | true | 0 |
| 30 | GER | POL | false | GAP | 15 | true | 0 |
| 60 | GER | POL | false | GAP | 10 | true | 0 |
| 90 | GER | POL | false | EXPIRED | 10 | true | 0 |

Base 1-arg check is SKIP_FIELDED (any Maginot/OOB chip). Tip evaluates the hold/gap.
`offensive_ramp` rejects stay 0 on this OOB because 1-stack vs 1-stack fails the 1.5 ratio (and POL COVER fills empty hexes) before the ramp gate; `_ai_offensive_ramp_ok` is false before d21 and true at d21 (GAP) with fielded=false after the capdef raise.

## Tests

`scripts/core/HeadlessB2Live1Test.gd` is standalone (not in the gates runner).
A1–A6, B1–B3, C1–C2, D1 FAIL on `95003ad3`, PASS on this tip.
