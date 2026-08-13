# EOA × Grok — setup for building together

This wires **project skills**, **slash commands**, a **gate script**, and a **workflow** so Grok sessions stay on the full-test path without re-explaining dual-board rules every time.

## What was added

| Path | Purpose |
|------|---------|
| `.grok/skills/eoa-full-test/SKILL.md` | Auto-loaded constraints + gate commands |
| `.grok/commands/eoa-full-test.md` | Slash: `/eoa-full-test` |
| `.grok/commands/eoa-gates.md` | Slash: `/eoa-gates` |
| `.grok/workflows/eoa-full-test-gates.rhai` | Workflow orchestration (pure → headless) |
| `tools/eoa_full_test_gates.sh` | One-shot machine gate runner |
| `AGENTS.md` | Short rules for any coding agent |

## What you do (human side)

### 1. Open the repo in Grok

Start Grok **from the EOA repo root** (or open this project as the workspace):

```bash
cd /home/mikef/Projects/epochs-of-ascendancy
# then start your usual Grok TUI / session on this directory
```

Skills and commands under `.grok/` are discovered automatically (no marketplace install).

### 2. Use slash commands

In the Grok TUI, type:

| Slash | Use when |
|-------|----------|
| **`/eoa-full-test`** | Starting a build session — loads constraints |
| **`/eoa-gates`** | “Is the game still green?” — runs full gates |
| **`/check-work`** | After a feature — independent verify |
| **`/skills`** | Confirm `eoa-full-test` appears |

If a command does not appear immediately: save files, restart the session, or wait a few seconds for skill reload.

### 3. Run gates yourself (terminal)

Anytime, no Grok required:

```bash
cd /home/mikef/Projects/epochs-of-ascendancy

# Fast loop (Python only)
tools/eoa_full_test_gates.sh --quick

# Full machine bar (needs Godot 4.7.1 via tools/run_godot.sh)
tools/eoa_full_test_gates.sh

# Full + logs + optional FPS sample (soft 30 FAIL OK)
tools/eoa_full_test_gates.sh --with-perf --log /tmp/eoa-gates-logs
```

### 4. Optional: run the workflow

The script is at `.grok/workflows/eoa-full-test-gates.rhai`. Project workflows require the **folder to be trusted** in Grok (same as trusting the repo for full tool access).

Once trusted:

```text
/workflow eoa-full-test-gates
```

Or with quick mode (if the UI passes args):

```text
args: { "quick": true }
```

Watch progress in `/workflows`. Agents run `tools/eoa_full_test_gates.sh`; allow **execute** if prompted.

**If the workflow will not load:** you can always run the shell script yourself (step 3) — that is the source of truth for green/red.

### 5. Play the game (graphical)

```bash
tools/run_godot.sh --path . res://scenes/TestScenario.tscn
```

Godot binary is resolved by `tools/run_godot.sh` (prefers `~/Applications/Godot-4.7.1/...`).

### 5b. Year multi-AI campaign (all nations as AI)

```bash
# Full 1 year · every land-owning tag is an AI agent (lean ticks)
tools/eoa_year_multi_ai_test.sh --days 365

# Fast smoke (30 days, majors only)
tools/eoa_year_multi_ai_test.sh --smoke

# Plan only (no Godot)
tools/eoa_year_multi_ai_test.sh --plan-only
```

Lean mode (default, `EOA_YEAR_MULTI_AI=1` via shell):

| Role | Behavior |
|------|----------|
| **Majors** (GER FRA ENG USA SOV ITA JAP POL) | Real `apply_production` every day (+ supply every 14d) |
| **All other land owners** | Registered as AI every day (soft ticks; no heavy apply) |
| **Calendar** | Quiet day advance (no full headless theater cascade) |

Calendar: **1936-01-01 → 1937-01-01** for 365d. Evidence JSON: `tools/map_generation/output/year_multi_ai_campaign_evidence.json`.  

Shell **fail-closed**: non-zero if `SCRIPT ERROR`, process Killed/OOM, missing `end ok=true`, or `major_apply_sum=0`.


### 6. Optional MCP / plugins

- **GitHub MCP** — only if you track issues/PRs for M6 findings.  
- **Game art skills** (`game-asset-core`, `game-ui-icons`, …) — already bundled; trigger by asking for icons/portraits/flags.  
- No marketplace plugin is required for this setup.

## What Grok does (agent side)

When you say “continue building EOA” or “fix the map”, Grok should:

1. Respect **eoa-full-test** constraints (no `world_full` renumber, pure products first).  
2. Prefer `tools/eoa_full_test_gates.sh` over inventing new dual packages.  
3. Keep **M6** as human playtest notes, not a fake automated PASS.  
4. Update `docs/GAME_STATUS_SNAPSHOT.md` only when truth changes.

## Quick “session start” phrase for you

Copy-paste to start a productive turn:

> `/eoa-full-test` Continue building EOA. Run gates if you touch map/war/save. Prefer the next high-value item from HOI4_EOA_GAP_REVIEW opportunities or SNAPSHOT, without inventing dual spam. M6 stays human-only.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `/eoa-gates` missing | Confirm files under `.grok/commands/`; restart Grok in repo root |
| Godot step fails | Ensure `tools/run_godot.sh` finds 4.7.1 under `~/Applications` |
| Gates fail after densify | Check `map_qc` + adjacency; restore from `data/provinces_world_accurate.bak_*` if needed |
| Soft 30fps FAIL | Expected on proxy; not a gate failure |

## Related docs

- Status: `docs/GAME_STATUS_SNAPSHOT.md`  
- HOI pillars: `docs/HOI4_EOA_GAP_REVIEW.md`  
- Playtest checklist: `docs/PLAYTEST_AND_DECISION_GUIDE.md`  
