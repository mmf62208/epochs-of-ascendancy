# Epochs of Ascendancy — TODO

**Living snapshot:** [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) · **Doc index:** [docs/README.md](docs/README.md) · **Testing:** [docs/TESTING_PLAN.md](docs/TESTING_PLAN.md)

---

## Now (highest leverage)

1. **Main-loop combat** — ✅ Province assault (`BattleManager`); still need AI orders + multi-province campaigns
2. **Active infrastructure investment** — finish player/AI project loop per [DESIGN_InfrastructureDevelopmentSystem.md](docs/DESIGN_InfrastructureDevelopmentSystem.md) (InfoPanel invest UI exists; polish + save/load).
3. **Save/load completeness** — long sessions including active projects, formations, and scenario metadata.
4. **Headless CI** — stable `--quit-after 15` smoke; optional `EOA_RUN_FULL_LEADER_TESTS=1` for full roster reload.

---

## Map & visuals

- [x] Grand theater underlay + terrain toggle + map visual editor (Debug → Map Visual Editor)
- [x] Dynamic `BorderLayer` + F10 border demo / test combat / owner cycle
- [x] Phase 1 test scenario (~180 provinces) + generation tooling in `tools/map_generation/`
- [ ] Replace placeholder `ultra_high.jpg` with final art master
- [ ] Scale generation toward 350–450 province Europe target
- [ ] Unit icons on map (NATO / basic toggle)

---

## Systems backlog (medium)

| Area | Next step |
|------|-----------|
| Combat | Terrain/weather/air in resolver; battle initiation from map |
| Leaders | Training bonuses in live battles; news feed panel |
| Technology | Expand beyond Support/Radio slice |
| Agents | Persistent province rings + detection pressure |
| Diplomacy | Flesh out `DiplomacyView` beyond stub |
| Production | Screen data caching; assignment UI polish |
| Trade | Already functional — balance + AI offers |

---

## Recently completed (June 2026)

- **Jun 6:** Debug overlay layout (full-width buttons, vertical scroll only, draggable + **⤡ resize**); WorldMap InfoPanel scroll; TopInfoBar/MainMenu HUD sync; phased combat headless test; `SpecialSiteManager` autoload + site ID fixes.
- **Jun 5:** Grand theater auto-load, terrain toggle, map editor export/load, weather on high-res bg.
- **Jun 4–5:** BorderLayer, F10 combat capture demo, TestRunner map-first bootstrap, leader roster fallback for `phase1_europe_test`.

---

## Deep reference (do not duplicate here)

Long-form status, leader/combat/agent notes, and historical session bullets were **condensed into** [CURRENT_STATE.md](docs/CURRENT_STATE.md) and [docs/README.md](docs/README.md). Use these design docs when implementing:

- Infrastructure: [DESIGN_InfrastructureDevelopmentSystem.md](docs/DESIGN_InfrastructureDevelopmentSystem.md)
- Map sequencing: [MAP_IMPLEMENTATION_PLAN.md](docs/MAP_IMPLEMENTATION_PLAN.md)
- Leaders: [LEADER_SYSTEM_DESIGN.md](docs/LEADER_SYSTEM_DESIGN.md)
- Technology: [TECHNOLOGY_SYSTEM_DESIGN.md](docs/TECHNOLOGY_SYSTEM_DESIGN.md)
- UI patterns: [UI_DESIGN_REFERENCE.md](docs/UI_DESIGN_REFERENCE.md)

---

## Suggested implementation order

1. Combat battle loop on map (formations → resolver → owner change → borders)
2. Infrastructure investment Phase A completion + save/load
3. Save/load hardening + autosave UX
4. Rich agent networks OR expanded tech trees (pick based on playtest feedback)
