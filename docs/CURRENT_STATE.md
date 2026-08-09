# Current State of Epochs of Ascendancy

**Last updated:** August 9, 2026  
**Playtest entry:** `scenes/TestScenario.tscn` (F5) → `phase1_europe_test` via `TestRunner.gd`  
**Doc index:** [README.md](README.md)

**Note on playtest history:** June 15 cloud playtest/UX pass (PR #1) was never merged to `main` until this branch. Local August playtest notes are not in the git session archive yet — capture them under `docs/SESSION_NOTES/` or Notion when available.

---

## Executive summary

Epochs of Ascendancy has a strong **simulation backend**, **grand-theater map foundation**, and **debug/playtest harness**. Agents are pushed toward the intended "player's will" role (traits, record/honing, sponsor/lead hooks, passive national impacts). Technology has a richer 1890s-1938 foundation with diffusion/catch-up, agent early unlocks, and national/agent-led projects.

**August 9 continuation:** Infrastructure investment Phase B is wired (Political Power, Invest Infra/Dev, cancel, AI invest, passive factory→dev, save/load) and basic AI province assaults exist via `AIBattleDirector`. June 15 playtest UX fixes (country selector, ESC layering, safer load, weather day tick) are merged onto this branch.

The project is playable for targeted actions. It is **not yet a self-contained 50+ turn campaign demo** — remaining gaps: **multi-province campaigns / AI movement**, **save/load hardening**, **Ascendancy/peace**, and less F10 reliance.

---

## Overall maturity

| Area | Assessment |
|------|------------|
| Targeted playtest actions | ✅ Strong: assault, invest, station, overlays, inspector, debug actions |
| Backend depth | ✅ Strong: production, agents, technology, supply, leaders, map effects |
| Visual/map foundation | ✅ Strong: grand theater underlay, borders, overlays, editor, icons |
| Self-contained campaign loop | ⚠️ Incomplete: economy → design/produce → field/fight needs campaigns + polish |
| Unique identity | ✅ Emerging: agents as will + Ascendancy/pillars + timeline projects |
| Long-session reliability | ⚠️ Improving: broad persistence exists; targeted hardening remains |

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
| Phase 1 scenario | ✅ Dense Europe harness; generated child data and settlement effects |
| Unit icons | ✅ NATO archetype symbols with owner tint in playtest |
| Production art | ⚠️ Placeholder JPG — replace for QC |

---

## UI shell — **Good, still debug-heavy**

| Area | Status |
|------|--------|
| TopInfoBar | ✅ Pause/speed, nav buttons, trade/diplomacy toggle, player country selector |
| MainMenu | ✅ Save manager, fade, help dialog, scenario restart |
| LeaderEventUI | ✅ Toasts; headless-safe replacement popups |
| DebugOverlay | ✅ Resizable panel, readable section layout |
| Invest / Dev / Cancel | ✅ InfoPanel buttons with PP cost + project status |
| ESC behavior | ✅ Closes topmost debug/popup/screen/InfoPanel before opening menu |
| Main gameplay screens | ⚠️ Exist, but need more live feedback and less F10 reliance |

---

## Core systems

| System | Status |
|--------|--------|
| Time | ✅ Daily/monthly/yearly ticks; TopInfoBar wired; interactive time enabled by default |
| Supply + overlays | ✅ L key; agent pressure, repair breakdown |
| Production | ✅ 1000+ templates/modules, lines, refinement, stockpile/OOB hooks; screen backends tested |
| Leaders | ✅ 1918/1936/2026 rosters, training, replacements |
| Agents | ✅ Traits/skills, networks, positive/negative missions, record/honing, passive national impacts, sponsor/lead hooks |
| Technology | ✅ 1890s-1938 foundations, diffusion/catch-up, agent early unlocks, national projects; more content/balance needed |
| Infrastructure | ✅ Phase B: PP ledger, Invest Infra/Dev, cancel/refund, daily tick, sabotage duel, AI invest, passive factory growth, save/load |
| Combat | ✅ Province assault (`BattleManager`) + ✅ AI assaults (`AIBattleDirector`); multi-day campaigns / AI movement still pending |
| Special sites | ✅ Manager + tier IDs; build from InfoPanel |
| Weather | ⚠️ Overlay/manager stub; daily signal wired, but live battle/supply/air/naval consequences pending |
| Save/load | ⚠️ Broad persistence + projects/PP; long-session edge cases remain |
| Policy / pillars | ⚠️ PolicyLawScreen and pillar concepts exist; more surface area and Ascendancy integration pending |

---

## Recent high-value additions

- **Aug 9:** Infra Phase B + `AIBattleDirector`; merged unmerged June 15 playtest UX/roadmap branch (PR #1) into continuation work.
- **Agents as will:** industrial/resource/research/military traits, passive national effects, positive missions, veteran record/honing, project sponsor/lead hooks, and NMM/Production/Supply/Tech ties.
- **Technology:** richer 1890s-1938 base, diffusion thresholds, catch-up/early bonuses, ahead-penalty mitigation, agent trait early unlocks, and national/agent-led project hooks.
- **Playtest UX (Jun 15):** top-bar country selector, safer F9 load path, ESC top-layer close, draggable-panel clamping, weather daily tick hookup, ScenarioLoader lookup fixes.
- **Map harness:** dense Phase 1 Europe scenario, child province/settlement effects, NATO/nation icons, overlays, inspector, debug actions, and headless production/combat checks.

---

## Testing (headless)

```bash
godot --headless --path . res://scenes/TestScenario.tscn --quit-after 15
# Bounded smoke (recommended when interactive time would hang):
EOA_FREEZE_TIME=1 godot --headless --path . res://scenes/TestScenario.tscn --quit-after 15
```

Production line suite passes (design, stockpile, combat width, phased combat, formations). Full leader roster reload is **skipped by default** (OOM risk); set `EOA_RUN_FULL_LEADER_TESTS=1` for the heavy block.

Latest validation notes (June 15 playtest agent):

- Godot 4.6.2 editor/import pass completed; it generated the missing `BattleManager.gd.uid`.
- `EOA_FREEZE_TIME=1` headless bootstrap printed PASS lines for production/combat checks.
- The smoke scene currently remains interactive after test output; add a reliable CI exit mode before treating it as fully automated.
- Known warnings are mostly content/tooling warnings: invalid scene UID fallback, optional `data/map/rivers.json` missing, phase1 demo IDs not found, and missing phase1 starting tech/countries block.

Details: [TESTING_PLAN.md](TESTING_PLAN.md)

---

## Top priorities

1. **Multi-province campaigns / AI formation movement** — assault AI exists; operational war still thin.
2. **Save/load hardening for long sessions** — active infra/PP, formations, agent passive impacts, diffusion, scenario metadata, autosave UX.
3. **Tech construction bonuses + Industry Foundations** — wire into provincial projects; overlay/effect preview polish.
4. **1918 Peace + Ascendancy Initiatives / Golden path** — initiative tree, PeaceConferenceWindow, agent sponsorship.
5. **Agent will expansion** — direct directives, milestones, passive-impact feedback, timeline projects.
6. **Main UI polish** — production/tech/agent/diplomacy/inspector without F10 crutches.
7. **AI/content/balance** — invest/produce/attack/trade basics; 1918-38 flavor.

Backlog: [TODO.md](../TODO.md)

---

## Quick playtest

1. **F5** on `TestScenario.tscn`
2. Pick player country in TopInfoBar if testing a specific nation (for example **GER** for the province 1 assault demo)
3. Click provinces → scrollable inspector; **Invest Infra / Invest Dev / Cancel Project**; **Close** or Esc
4. **F10** → debug tools; drag title bar; resize with **⤡** corner; **AI Assault Pass**
5. **Menu** → save/load; **Return to Title** reloads scenario
6. **L / R / T / C / Y** — map overlays
7. **Combat:** click friendly province with a division → **Ctrl+click** adjacent enemy (or **Attack** in InfoPanel)
8. Unpause time — AI countries with adjacent deployments may launch assaults every few days

---

## Best next steps

### Phase 1 — close playable loops

1. AI formation movement + multi-province campaign resolution on top of `BattleManager` / `AIBattleDirector`.
2. Save/load regression: active infra/PP, formations, agent effects, diffusion, scenario metadata, autosave UX.
3. Tech construction bonuses + overlay/effect preview polish for infrastructure projects.

### Phase 2 — build the unique identity

1. Full 1918 peace and Ascendancy Initiative system: tree data, UI, resolution, pillars, Golden specials, and multi-year follow-ons.
2. Agent will directives and timeline projects: direct player assignments, visible milestones, project sponsorship, and historical/alt-history flavor.

### Ongoing

- Polish main screens and inspector feedback so play no longer depends on F10.
- Expand AI for investment, production, attacks, trade, and agent priorities.
- Expand 1918-1938 agents/projects/doctrines/content and balance agent power, diffusion, and population growth.

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
