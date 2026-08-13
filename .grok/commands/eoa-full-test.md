---
description: Load EOA full-test constraints (board ~3520, dual bar, gate commands, HOI open P0=0)
---

# /eoa-full-test

Apply the project skill **eoa-full-test** for this session.

1. Read `.grok/skills/eoa-full-test/SKILL.md` if not already loaded.
2. Confirm working context is Epochs of Ascendancy and default board is `world_accurate` ~3520.
3. Briefly restate hard constraints (dual board, no world_full renumber, pure products preferred, M6 human-only).
4. Ask what the user wants to build next, or if they said nothing specific, propose the next non-P0 high-value item from `docs/HOI4_EOA_GAP_REVIEW.md` §3 (e.g. human M6 checklist support, supply-hub depth, SE Asia density only if noisy) without inventing dual-package spam.
5. When implementing, run `tools/eoa_full_test_gates.sh --quick` after pure changes and full gates before claiming done.
