# Current State of Epochs of Ascendancy

**Last updated:** August 9, 2026  
**Playtest entry:** `scenes/TestScenario.tscn` (F5) → `phase1_europe_test` via `TestRunner.gd`  
**Doc index:** [README.md](README.md)

---

## Executive summary

Strong **map/visual foundation** and **deep simulation backend**. Phase 1 Europe (~180 provinces), grand theater underlay, dynamic borders, F10 debug tools, scrollable province inspector, and a resizable debug overlay are playable. Core autoloads (Time, Supply, Production, Leaders, Agents, Technology, Special Sites, Battle, Infra Development, AI Battle Director) are largely implemented.

**Recently completed (this pass):** Infrastructure investment Phase B loop (Political Power spend, development invest, cancel + refund, passive factory→dev growth, hostile capture cancel, light AI investment) and basic AI province assault orders (`AIBattleDirector`).

Main remaining gaps for a 50+ turn playtest: **multi-province campaigns / AI movement**, **save/load hardening for long sessions**, and **tech/agent depth**.

---

## Map & visuals — **Strong**

| Area | Status |
|------|--------|
| Grand theater underlay | ✅ `europe_grand_theater_ultra_high.jpg`; legacy maps suppressed |
| Terrain toggle | ✅ Political vs detailed raster |
| Map visual editor | ✅ Debug placement, list/delete, JSON export/load |
| Dynamic borders | ✅ `BorderLayer`; refreshes on owner change |
| F10 tools | ✅ Border demo, test combat, AI assault pass, owner cycle |
| Debug overlay UX | ✅ Full-width layout, vertical scroll, drag + resize (⤡) |
| Province inspector | ✅ Scrollable `InfoPanel` on province click |
| Phase 1 scenario | ✅ `data/provinces_phase1_test/` |
| Production art | ⚠️ Placeholder JPG — replace for QC |

---

## UI shell — **Good**

| Area | Status |
|------|--------|
| TopInfoBar | ✅ Pause/speed, nav buttons, trade/diplomacy toggle |
| MainMenu | ✅ Save manager, fade, help dialog, scenario restart |
| LeaderEventUI | ✅ Toasts; headless-safe replacement popups |
| DebugOverlay | ✅ Resizable panel, readable section layout |
| Invest / Dev / Cancel | ✅ InfoPanel buttons with PP cost + project status |

---

## Core systems

| System | Status |
|--------|--------|
| Time | ✅ Daily/monthly/yearly ticks; TopInfoBar wired |
| Supply + overlays | ✅ L key; agent pressure, repair breakdown |
| Production | ✅ Lines, refinement, stockpile; screen backends tested |
| Leaders | ✅ 1918/1936/2026 rosters, training, replacements |
| Agents | ✅ Daily sabotage/disruption; network foundation |
| Technology | ⚠️ Support/Radio functional; expand trees |
| Infrastructure | ✅ Invest + Development projects, PP ledger, daily tick, sabotage duel, save/load, AI invest, passive factory growth |
| Combat | ✅ Province assault (`BattleManager`); ✅ AI assaults (`AIBattleDirector`); multi-day campaigns still pending |
| Special sites | ✅ Manager + tier IDs; build from InfoPanel |
| Weather | ⚠️ Overlay stub on grand theater |
| Save/load | ⚠️ Projects + PP persist; long-session gaps remain |

---

## Testing (headless)

```bash
godot --headless --path . res://scenes/TestScenario.tscn --quit-after 15
```

Production line suite passes (design, stockpile, combat width, phased combat, formations). Full leader roster reload is **skipped by default** (OOM risk); set `EOA_RUN_FULL_LEADER_TESTS=1` for the heavy block.

Details: [TESTING_PLAN.md](TESTING_PLAN.md)

---

## Top priorities

1. Multi-province campaigns / AI formation movement (assaults exist; operational war still thin)
2. Save/load hardening for multi-hour sessions (formations, scenario metadata, PP mid-run)
3. Technology expansion beyond Support/Radio
4. Replace placeholder map master art when ready

Backlog: [TODO.md](../TODO.md)

---

## Quick playtest

1. **F5** on `TestScenario.tscn`
2. Click provinces → scrollable inspector; **Invest Infra / Invest Dev / Cancel Project**; **Close** or Esc
3. **F10** → debug tools; drag title bar; resize with **⤡** corner; **AI Assault Pass**
4. **Menu** → save/load; **Return to Title** reloads scenario
5. **L / R / T / C / Y** — map overlays
6. **Combat:** click friendly province with a division → **Ctrl+click** adjacent enemy (or **Attack** in InfoPanel). Try GER on province 1 vs FRA neighbors after setting TopInfoBar country to **GER**.
7. Unpause time — AI countries with adjacent deployments may launch assaults every few days.

---

## Related docs

| Doc | Purpose |
|-----|---------|
| [README.md](README.md) | Documentation index |
| [TESTING_PLAN.md](TESTING_PLAN.md) | Regression checklist |
| [TEST_MAP_GRAND_THEATER_FOUNDATION.md](TEST_MAP_GRAND_THEATER_FOUNDATION.md) | Map QC |
| [DESIGN_InfrastructureDevelopmentSystem.md](DESIGN_InfrastructureDevelopmentSystem.md) | Infra investment design |
| [SESSION_NOTES/2026-06-05.md](SESSION_NOTES/2026-06-05.md) | June review |
| [../README.md](../README.md) | Project vision + install |
