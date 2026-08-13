# Playtest checklist — HUD click + map input (world_full F5)

Use after a **fresh** launch of `TestScenario` (close any frozen older windows first).

## Ordered checks (do these in order)

| # | Action | Expected |
|---|--------|----------|
| 1 | Wait until load screen is gone and map is visible | Date shows (e.g. `1 Jan 1936`), top bar visible |
| 2 | Hover **Prod**, **Lead**, **Menu**, **1x** | Buttons highlight / hover style changes |
| 3 | Mouse **wheel** over open ocean (not over a panel) | Map zooms in/out |
| 4 | **Middle-drag** or **right-drag** on map | Map pans |
| 5 | Click **1x** (or press keyboard **`1`**) | Console: `TopInfoBar: SPEED 1x`; date advances within ~1–2s |
| 6 | Wait a few seconds | Date keeps advancing slowly; hover/scroll still work |
| 7 | Click **\|\|** or press **Space** | Pauses; date stops; hover/scroll still work |
| 8 | Keys **2** / **3** / **4** | Speed changes; still clickable |
| 9 | **Menu** → close without hanging | Overlay dismisses; map input returns |
| 10 | **Tech** (once) | Toast “Technology — TAG…”; panel centered under top bar (drag title bar); log `TechnologyScreen: opened` / `TopInfoBar: opened TechnologyScreen`. Close via Close or click Tech again. |
## Keyboard fallbacks (when mouse feels dead)

- **`1`–`4`** — set speed and unpause  
- **`Space`** or **`.`** — pause / resume  
- **Middle / right drag** — pan  
- **Wheel** — zoom  
- **WASD / arrows** — pan  

## Symptom → cause

| Symptom | Likely cause |
|---------|----------------|
| Buttons never highlight, map crawls, CPU ~100% while only hovering top bar | Edge-pan thrash (should be fixed: top chrome blocks edge pan) |
| Click 1x then whole UI dies for many seconds; log floods Pillar/AIR SORTIE | Day-advance storm (should be fixed: 1 day/tick + busy flag) |
| After **Tech**, game freezes; log: `Stack overflow` / `can_research`↔`get_node_status` | Tech recursion (should be fixed) |
| Tech click, no panel, then hover/scroll die; stuck mid-year (e.g. Feb) | Heavy open/refresh freeze or day thrash (deferred open + light daily path should fix) |
| Scroll “sticks” on one side | Edge pan still active — move mouse off edge; top chrome should not pan || Click 1x briefly works then date freezes again without you pausing | Deferred re-pause (should be fixed: `player_owns_clock`) |
| Log: `Signal 'pressed' is already connected` on every speed click | Nav buttons re-wired on speed (should be fixed: `_connect_once`) |

## Headless verification (developers)

```bash
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHudClockTechTest.gd
```

Expect: `HeadlessHudClockTechTest: PASS`

## Map navigation (current)

- **Wheel zoom**: over open map (not over Tech list / scroll panels). Slightly larger step.
  - Fixed: each wheel notch used to rebuild **all 2665 province fills** → lag/glitch; now light LOD only + debounced fill band.
- **Edge pan**: left / right / **bottom** edges (not top bar). Works while **paused**. Larger margin (~64px).
- **Drag pan**: middle-mouse or **right-mouse** drag on the map.
- **WASD / arrows**: pan always.
- With **1x on**: interactive days skip air sorties; reinforce every 3rd day — wheel should stay usable.
- Supply legend: **Close ✕**, **L**, or **Esc**.

## Closing stuck panels

| Panel | How to close |
|-------|----------------|
| Supply legend (big left text after **L**) | **Close ✕** button, or **L**, or **Esc** |
| Technology | **Close** on panel, click **Tech** again, or **Esc** |
| Province inspector | **Close** on panel or **Esc** |
| Notices (bottom-right) | **x** on the notice |
| Main menu | **Esc** or menu close |
