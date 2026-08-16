# EOA — Forward Program L1: Unit-Centric War Loop

| Field | Value |
|-------|-------|
| **Document** | Next-level Alpha improvements after full-test machine green |
| **Date** | 2026-08-16 |
| **Status** | Active — stack re-homed onto `cursor/l1-unit-war-loop-10a5` |
| **Launch bar** | **L1 Playable Alpha** ([`LAUNCH_READINESS_PLAN.md`](LAUNCH_READINESS_PLAN.md)) |
| **Board** | `world_accurate` **~3520** |
| **Engine** | Godot **4.7.1** via `tools/run_godot.sh` |
| **Prior DAG** | [`FORWARD_PROGRAM_2026_08_12.md`](FORWARD_PROGRAM_2026_08_12.md) (composer · hang-class · multi-AI gate) — **archive** |
| **Source stack** | `execute-plan/c5a8b0ae-pr-1` … `pr-6` (adopted; do **not** merge those remotes — this branch is the forward path) |

**Truth:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md) · residual [`EOA_RESIDUAL_PRIORITY_BOARD.md`](EOA_RESIDUAL_PRIORITY_BOARD.md) · skill `eoa-full-test`

---

## Overview

Full-test machine gates are green. First-session surfaces (capitals / Fronts / WarLoop / G / save) are gated. The **next player-visible depth** is fighting with **named units** on the Maginot theater: pick a pin → march on own land → honest assault → multi-day battle → thin unit card (template / stockpile / assign).

This program is **L1 Alpha loop honesty** — not new pillars, not densify, not GameData split, not designer commercial parity.

```mermaid
flowchart LR
  Pick[Pin-first pick] --> Reserve[Maginot land stations]
  Reserve --> Assault[Named-unit assault]
  Assault --> March[Own-land march]
  March --> Battle[Multi-day battle]
  Battle --> Card[Unit card assign]
  Card --> Human[Human §0b + M6 notes]
```

---

## PR ladder (machine — landed on this branch)

| PR | Slice | Pure / gate | Player value |
|----|-------|-------------|--------------|
| 1 | **Pin-first pick** — hit disk 48px / floor 20 · selected chip · no inspector storm | `unit_centric_pick_product` | Can select the unit you see |
| 2 | **OOB Maginot reserve** — GER `710173` / FRA `710739` land stations | `formation_station_resolver` + multi-front tests | Units exist on the front |
| 3 | **Assault honesty** — named fid, no Berlin fallback | `first_session_assault_surface_product` | Attack is the selected unit |
| 4 | **March orders** — own-land hops + pin lerp | `formation_march_product` | Move before fight |
| 5 | **Battles over time** — daily org/str · capture on break · attacker initiative | `multi_day_battle_product` | Fights last more than one click |
| 6 | **Unit card** — template / stockpile / thin assign mode (not factory retool) | composer + pick product | Reinforce without F10 |

§0b composer (`first_session_play_surface_product`) ANDs prior eight surfaces **plus** unit_pick + march + battle on `eoa_full_test_gates.sh --quick`.

---

## Goals & non-goals

### Goals

1. Player can F5 GER, zoom Maginot, **pick a unit pin**, march, and fight a **multi-day** battle without F10.
2. Assault uses the **named** formation — no silent capital/Berlin fallback.
3. Gates fail if pick / march / battle builders regress.
4. Docs honest: machine L1 loop closed; **M6 human notes still open**.

### Non-goals

- M6 20d/60d narrative (human-only)
- Soft 30fps hard-PASS · `renderer_frame`
- GameData mega-split · densify / SE Asia · museum / 13k
- Multiplayer · V3 markets · commercial HOI designer (residual #12 stays deferred)
- DESIGN_LADDER_A corridor/transit (`ceb60fdd-*` stay parked — do not merge)
- Merging `execute-plan/c5a8b0ae-*` remotes after this branch lands (abandon / rebase rule: **this branch wins**)

---

## Human proof (still required for L1 exit)

| Step | Action |
|------|--------|
| 1 | `tools/run_godot.sh --path . res://scenes/TestScenario.tscn` |
| 2 | Complete PLAYTEST §0b items **3–15** |
| 3 | Pick unit on Maginot `710173` · march · start multi-day battle · open unit card assign |
| 4 | Append [`SESSION_NOTES/2026-08-05_m6_smoke.md`](SESSION_NOTES/2026-08-05_m6_smoke.md) |
| 5 | Later: separate 20d + 60d M6 narrative notes |

Do **not** invent M6 complete from machine gates.

---

## Session protocol

Same as SNAPSHOT §0. After this stack merges:

| Role | Next |
|------|------|
| **Human** | §0b + unit loop smoke · then M6 notes |
| **Machine** | Playtest-driven shipped-path fix only |
| **Director** | When §0b+M6 filed → L1 ship kit ([`LAUNCH_READINESS_PLAN.md`](LAUNCH_READINESS_PLAN.md) Phase P2) |

---

## Verification

```bash
tools/eoa_full_test_gates.sh --quick
# includes: test_unit_centric_pick_product · formation_march · multi_day_battle · first_session composer
tools/eoa_full_test_gates.sh   # before merge claim
```

Godot only via `tools/run_godot.sh`. Dual board only via `EOA_SCENARIO=world_full`. Never renumber `world_full` IDs.
