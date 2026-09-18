# Paste this into a new Grok sitting (EOA repo root)

You are building **Epochs of Ascendancy** (Godot 4.7.1 GSG).

**Read first:** `docs/GAME_STATUS_SNAPSHOT.md` (live truth). Then `docs/SESSION_NOTES/2026-09-18_playtest_closeout_plan.md`. Load skills `eoa-full-test`, `eoa-godot`, `eoa-living-units`. Slash `/eoa-full-test`.

**Play tree (F5):** `execute-plan/856bb385-pr-3-factory-toe-on-the-default-play-strip` — not stale `main`. Godot only via `tools/run_godot.sh`. Board `world_accurate` ~3520. Never renumber `world_full` IDs. Click/AI initiator = `BattleManager.start_land_battle`, never `execute_province_assault`.

**Take ONE slice from this queue, in order. Stop when Maginot still works.**

0. **RSS 1× actually pauses** before ~3 GB. Print `TimeManager: RSS tripwire … last=`. No `OS.execute(awk)`. No `RENDERING_INFO_TOTAL_VIDEO_MEM_USED` (breaks 4.7.1).
1. **Chip pid-hash offset** so adjacent Rhine plates (Maginot/Kusel) are ≥24 px apart. Same-hex still peeks `×N`.
2. PLAYTEST §0b 11–15 + one 20d unpause note. Do not claim M6 complete.
3. Air: select CAS wing, right-click Paris = CAS covering that region. **H is not hills.**
4. Ctrl+S after occupy walk-in; Ctrl+L restores owners + fight.
5. Hex readout is **frozen**: fill-tint hover, convex-piece fills. Do **not** clip-all-NUTS / 13k / densify / museum borders.

**Hang-class:** no 3520 BFS on G/L; no `ClassName.has_method()` on RefCounted `class_name`; chip text Node2D not Control Labels; no full inspector rebuild on pick.

**Proof:** `HeadlessWorldAccurateUnitOrderLoopTest` RESULT=PASS after occupy/pick/air. `--quick` while iterating. Greps are not ready.

**Do not:** merge `origin/cursor/*` or `execute-plan/ceb60fdd-*`; GameData split; dual packages; epoch fit/lift; raise the 2.5 GB RSS cap.

**Today already landed** (do not re-implement): occupy only assault-hex; no GER bounce; canvas pick; in-country capital snap; 32px chip disk; F9 goods / political clean; left-click cycles / right-click same hex cancels; fill-tint hover; Moselle not hulled over LUX.

If the user is F5-ing, watch RSS and Maginot 710173 vs 710739. One slice. Then stop.
