# Epochs of Ascendancy — agent instructions

Godot **4.7.1** grand strategy. Default F5 board: **`world_accurate` ~3520** provinces (post US + RoW sparse).

## Always

1. Read `docs/GAME_STATUS_SNAPSHOT.md` for current truth.
2. Load project skill **eoa-full-test** (`.grok/skills/eoa-full-test/SKILL.md`) for map/war/save work.
3. Prefer pure products under `tools/map_generation/lib/` + unit tests + headless Godot over dual-package spam.
4. **Never renumber `world_full` IDs.** Dual scaffold: `EOA_SCENARIO=world_full`.
5. After non-trivial changes run:

```bash
tools/eoa_full_test_gates.sh --quick   # while iterating
tools/eoa_full_test_gates.sh           # before claiming done
```

## Humans + Grok together

| Command / tool | What it does |
|----------------|--------------|
| `/eoa-full-test` | Load full-test constraints into the session |
| `/eoa-gates` | Run the gate script and report |
| `/check-work` | Adversarial verify last changes |
| Workflow `eoa-full-test-gates` | Multi-agent gate run (pure then headless) |

Setup guide: `docs/EOA_GROK_SETUP.md`  
HOI pillars: `docs/HOI4_EOA_GAP_REVIEW.md` (open machine P0 = 0)  
Playtest: `docs/PLAYTEST_AND_DECISION_GUIDE.md`

## Non-goals (do not treat as gates)

- M6 human 20d/60d narrative notes  
- Soft 30fps hard-pass if proxy still fails honestly  
- Museum borders, 13k provinces, multiplayer product, full V3 markets  

## Godot

Always launch via `tools/run_godot.sh` (not a bare `godot` that might be the wrong version).
