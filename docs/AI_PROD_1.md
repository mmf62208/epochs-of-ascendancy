# AI-PROD-1

Headless campaign boots report `factories=3256` and still create **zero** AI production lines. Live `ScenarioLoader` already creates the lines. This slice adds an **opt-in** bootstrap. `CampaignLoopTestBoot.boot()` does not call it.

Base for this branch: `0c1122ae70414922b2b882afaace41f8f0318f62` (LOAD-SCREEN-1 #209 on `main`). The brief’s `e0388c58` pin was superseded by that merge. Branch `grok/ai-prod-1`.

## Diagnosis

Live path first, on the clean base, `HeadlessHwy3LiveScenarioTest` → `ScenarioLoader.load_scenario("world_accurate")`:

- `[ScenarioLoader] OOB production bootstrap — lines=15 assigned_to_factory=15`
- Owners: GER, FRA, ENG, USA, SOV, ITA, JAP (design + infantry) and POL (armor only).

So H2 is false on this SHA. Live lines are 15, not 0.

Headless path (`CampaignLoopTestBoot.boot` + `CapitulationDomain.apply_economy_factories_to_map` + `seed_1936_start_garrisons`), 30 live-equivalent days, no Fix A:

- Economy weights `factories=3256` (land `Province.factories` only).
- `FactoryManager` factory count `0`. `ProductionManager` line count `0` at day 0 and day 30.
- Soft-credit fallback fired on **30/30** days, **90** tag-applies (3 budgeted tags per day).

Root cause: `CampaignLoopTestBoot._load_board` (`scripts/core/CampaignLoopTestBoot.gd`, the integer `p.factories = 1|2` writes) never calls `ScenarioLoader.load_scenario` (`scripts/core/ScenarioLoader.gd` around the `_start_demo_production_lines` call) and never calls `FactoryManager.register_factories_for_province`. `CapitulationDomain.apply_economy_factories_to_map` (`scripts/core/CapitulationDomain.gd`) only writes economy weights. There is no later planner. `ProductionManager.advance_days_for_country` then takes the empty-line branch (`soft_stock_credit`, +1 `infantry_equipment`, `ok=true`). That branch is unchanged. It feeds the Perf4 seed digest.

## Fix A

`CampaignLoopTestBoot.boot_ai_production(skip_tag := "")` is a new static function. Call it **after** `apply_economy_factories_to_map()` and **not** from `boot()`.

It reads `res://data/scenarios/world_accurate.json` `countries[]` and uses the same first `starting_oob.land_designs` entry as `ScenarioLoader._start_demo_production_lines`. For each such tag except `skip_tag`:

1. One land province: `capital_province_id` when `MapManager` reports that tag as owner and the province is not sea, otherwise the tag’s lowest owned land pid.
2. `FactoryManager.register_factories_for_province(pid, tag, 1)`.
3. `ProductionManager.bootstrap_line_on_factory("oob_<TAG>_<design>", design, fid)`.
4. Majors GER, FRA, ENG, USA, SOV, ITA, JAP also get `infantry_m1_garand` (USA, ENG) or `infantry_k98_bolt_action` (the others). That factory’s `max_production_lines` is raised to at least 2.

Existing line ids are skipped (idempotent). One log line:

`CampaignLoopTestBoot: AI production boot lines=<n> factories=<n> by_tag=<json>`

Sim and future soak harnesses that want live AI lines must call `CampaignLoopTestBoot.boot_ai_production(player)` themselves. `HeadlessCampaignLoop1SoakTest` does **not** call it, so soak A/B md5s stay on the old zero-line path until OP opts in.

No edits to `ScenarioLoader.gd`, `ProductionManager.gd`, `FactoryManager.gd`, or `GameData.gd`. The soft-credit fallback is unchanged.

### Completions vs `completed_count`

The F5 day path (`advance_days`) increments `DesignLineState.units_produced`. It does not increment `ProductionLine.completed_count` (that counter moves in `advance_production` / `_complete_item`). `HeadlessAiProd1Test` treats a completion as `max(completed_count, units_produced)` on an `oob_*` infantry line. On the tip, 30 days gave `completed_count=0` and `units_produced` 3 or 4 on six majors (ENG 3, the other five 4).

## Test

`scripts/core/HeadlessAiProd1Test.gd` (not added to `tools/eoa_full_test_gates.sh`):

```bash
XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d) XDG_CACHE_HOME=$(mktemp -d) \
  tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAiProd1Test.gd
```

- Base (helper absent): `FAIL` with `AI lines=0`.
- Tip, `boot_ai_production("USA")`: `PASS`. 13 lines, 7 factories. GER, FRA, ENG, SOV, ITA, JAP, POL each own their `oob_` lines. Six majors complete infantry by day 30. A direct `advance_days_for_country("GER", 1.0)` reports `lines_touched=2` and `soft_stock_credit=0`.
- Scratch mutant that removes both `bootstrap_line_on_factory` calls: `FAIL` with `AI lines=0`. The mutant was not committed.

`AI_PROD_1_DAYS` overrides the day window (default 30). That flag is only the fallback d180 counter if Sim’s harness is missing.

## Out of scope

- Seed invariance across aivai seeds 1/2/3 (report only).
- Sim soak flags (1)–(4): stalemate, late passivity, garrison/ratio rejects, undefended flips.
- An AI production planner that adds lines over time.
- Changing the soft-credit fallback.
- Wiring the hook into `HeadlessCampaignLoop1SoakTest` or the gate script.

## Measured numbers

Filled in the session report `~/ai_prod_1_REPORT.md` (diagnosis, soft-credit tables, gates, d180). This file states the contract. The report holds the run tables.
