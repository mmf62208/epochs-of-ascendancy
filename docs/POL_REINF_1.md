# POL-REINF-1

AI Poland’s COVER/REINFORCE redeploys were feeding the attack path: freshly
moved `garrison_1936` units counted as attacker power, and captured German
land (skip_captured on defence) was still a launch base. This slice anchors
those defensive garrisons and forbids garrison launches from war-captured
hexes. It does not restore main’s ping-pong cover pool.

## Product (BattleManager.gd only)

- **G1** `POL_REINF_ANCHOR_DAYS = 30` (range named `MIN=21` / `MAX=45`).
  COVER and `_ai_move_garrison_to` stamp `_ai_def_anchor_day[fid]`. While
  anchored, a `garrison_1936` is excluded from AI attacker power, the preview
  formation, stack-march, rear-spare, and follow-on. Runtime only: not in
  `get_save_data`.
- **G2** If the from-hex is war-captured and every formation that would
  attack is `garrison_1936`, reject `garrison_captured_src`. Field divisions
  on the same hex may still launch. Home-land retakes are unaffected.
- Prints (one line per tag per day): `AI_DEF_ANCHOR skip <TAG> <fid> @ <pid>`
  and `AI_GARRISON_CAPTURED_SRC skip <TAG> @ <pid>`.
- No human/player check. `_ai_front_powers`, B2 ramp, and the per-hex index
  are unedited.

## Standalone test

```bash
XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessPolReinf1Test.gd
```

Not wired into `tools/eoa_full_test_gates.sh`. Requires LIVE fingerprint
`garrisons placed=536 skipped_occupied=40 targets=576`. Mechanism G1 and G2
each FAIL when only that guard is removed. Gerplayer bars: GER net
d14≤5, d21/30/60≤6, undefended≤1; d180 net≤7 und≤2. Tip 1/1/1/2/2 und=0.
The day loop flushes queued F5 light captures so owner flips apply without
an idle frame. Garrison spare-marches from a hex that already touches the
enemy are skipped so last front defenders stay put (keep-set analog).

## MERGE HOLD

Stacked on `grok/b2-live-1` (PR #200). Draft. Do not merge.

## Box pins (tip)

- Seed `20fe9063de285f19d4f9b8a105abfd31` (StabilityJustice + VictoryPaths).
- Identity `d22b87cf21fdf3b5bd54753a36a56b8c`; twin `5f87a16c300f2c9f57fad4059334ef40`.
- Mutants `4a9c21e5` / `43e14082`. NE `0.9853` (3207/3255). Garrison 576, ENG 188.
- `--quick` ALL PASSED. Map-select (d) 135ms, (b) warm 127ms. CL1 S1 d154 / S2+S2b d139 md5 `b9cf8d50` / S3 0.4983@152 then 0.6098@218, failures=1.
