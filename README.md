# Epochs of Ascendancy

**A grand strategy game of empire, industry, and ascendancy across the 20th and 21st centuries.**

Built in **Godot 4.6** — inspired by *Hearts of Iron IV*, *Terra Invicta*, and *Supreme Ruler*.

---

## Vision

Epochs of Ascendancy puts you in command of any nation across three pivotal starting dates:

- **1918** – Post-WWI world of empires, revolution, and fragile peace
- **1936** – Interwar rearmament, ideological struggle, and the road to global conflict
- **2026** – Modern multipolar world with great-power competition, advanced technology, and the dawn of new frontiers

Shape (or completely rewrite) history through economic mastery, technological leaps, military innovation, ideological conviction, diplomacy, trade, espionage, and bold strategic choices. Every decision ripples through the ages. Deep replayability comes from choosing any country and forging alternate histories.

The game emphasizes **player freedom in design** — from customizing divisions, tanks, planes, ships, and even spaceships/space stations, to building massive focus trees and tech trees that reflect your nation’s unique path to ascendancy.

---

## Current Features

- **Three playable start dates** (1918, 1936, 2026) with era-appropriate leader rosters
- **Phase 1 Europe test map** (~180 provinces) plus procedural pipeline toward 350–450 provinces
- **Grand theater map underlay** — stylized high-detail Europe raster with legacy map suppression
- **Terrain layer toggle** — detailed raster vs clean political province view (Debug → Map Visual Editor)
- **Starter map editor** — place cities/ports/airfields on the bg, export/load JSON for python roundtrip
- **Dynamic province system** — factories, special sites, development, infrastructure, population, victory points
- **Production line & unit design** — templates, refinement, national equipment stockpile
- **Leader system** — historical commanders, traits, training paths, replacements, national positions
- **Combat preview** — effective power, width, leader/terrain/province modifiers (full battle loop in progress)
- **Agent networks, technology, supply, weather overlays** on the interactive map
- **Interactive map** with camera (zoom to ~12×), InfoPanel, multiple overlay layers
- **Data-driven architecture** — JSON/resources for provinces, scenarios, countries, leaders, equipment

**Living snapshot:** [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) · **Docs:** [docs/README.md](docs/README.md) · **Tasks:** [TODO.md](TODO.md)

---

## Controls (playtest harness)

| Input | Action |
|-------|--------|
| **Left click** | Select province → scrollable InfoPanel |
| **Ctrl+click** | Assault adjacent enemy province (after staging a friendly division) |
| **Attack** (InfoPanel) | Launch assault on selected enemy province |
| **Esc / Close** | Dismiss inspector or open panels |
| **F10** / Ctrl+Shift+R | Debug overlay (drag title · resize **⤡** corner) |
| **L / R / T / C / Y** | Supply / roads / rails / cities / sites overlays |
| **F5 / F9** | Quicksave / quickload |
| **Menu** | Save manager, trade, help, restart scenario |
| Camera | Zoom wheel · WASD / edge pan · middle-drag |

---

## Expanded Scope & Key Systems

### Multiplayer
Primary focus is **2–4 players** online, with support for up to **4–8 players**. Games are designed around synchronous or turn-based-friendly online sessions. Authoritative server or peer-to-peer options will be evaluated. Hotseat/local multiplayer as a secondary mode. Multiplayer considerations will influence architecture from early on (state synchronization, desync prevention, etc.).

### Customization & Unit Designers
Full design freedom for key military and advanced assets:

- **Division Designer** — Customize infantry, support companies, templates
- **Tank Designer** — Chassis, guns, armor, engines, special modules
- **Plane Designer** — Fighters, bombers, CAS, transport aircraft
- **Boat / Ship Designer** — Surface fleet, submarines, carriers
- **Spaceship & Space Station / Satellite Designer** — Future-oriented units for orbital and deep-space operations (especially relevant in 2026+ scenarios)

Production lines feed these designs. Key equipment categories include infantry gear, artillery, drones (various types), and more. Units have stats, costs, and upgrade paths.

### Technology & Focus Trees
- **Large, branching Tech Tree** — Era-spanning research with prerequisites, bonuses, and alt-history branches
- **Large Focus Trees** — National/ideological paths with mutually exclusive or timed focuses. Major powers get deep trees; minors have meaningful options too

### Espionage, Agents & Intelligence
- **Agent system** with recruitment, assignment, skills, and experience
- **Espionage missions** (sabotage, intel gathering, influence ops, tech theft, etc.)
- **Facilities** supporting covert operations
- Integration with diplomacy, tech race, and internal stability

### Economy, Production & Trade
- Province-level and national production lines
- Resource management, stockpiles, and trade routes
- **Trade** as a major diplomatic and economic lever (bilateral deals, embargoes, global markets)

### Diplomacy & AI
- Deep diplomacy system (alliances, guarantees, trade agreements, ultimatums, influence)
- Robust **AI opponents** capable of long-term planning, reacting to player actions, and pursuing their own ascendancy goals
- AI will use many of the same systems (designers, focus trees, espionage) for fairness and depth

### Replayability & Alternate History
- Play **any country**
- Decisions have lasting consequences across economic, military, technological, and diplomatic spheres
- Strong support for alt-history outcomes through flexible trees, events, and player-driven unit/strategy design
- Multiple paths to victory or dominance (economic, military, technological, ideological, or hybrid)

---

## Development & Testing (June 2026)

- **Current state:** [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md)
- **Documentation index:** [docs/README.md](docs/README.md)
- **Roadmap / tasks:** [TODO.md](TODO.md)
- **Testing plan:** [docs/TESTING_PLAN.md](docs/TESTING_PLAN.md)
- **Map QC:** [docs/TEST_MAP_GRAND_THEATER_FOUNDATION.md](docs/TEST_MAP_GRAND_THEATER_FOUNDATION.md)

### Playtest quick start

1. Godot **4.6.2+** → open `scenes/TestScenario.tscn` → **F5**
2. Default: **phase1_europe_test** with grand theater underlay
3. **F10** — debug overlay (collapsible sections, map editor, border/combat tools)
4. Headless smoke: `godot --headless --path . res://scenes/TestScenario.tscn --quit-after 15`

---

## Systems Overview

- **Province & Map System** — Geography, resources, special features, dynamic state
- **Country & Ideology System** — Stability, support, leadership
- **Resource, Economy & Production** — Factories, lines, output, trade
- **Technology & Focus Trees** — Research and national direction
- **Unit Designers & Production** — Highly customizable military and advanced assets
- **Espionage & Agents** — Covert operations and intelligence
- **Diplomacy & Trade** — Relations and economic interaction
- **War & Military** — Units, movement, combat (with designer-created templates)
- **Scenario System** — Multiple start dates with tailored data
- **Multiplayer Foundation** — Online play for 2–8 players
- **AI Opponents** — Capable singleplayer experience
- **Data-Driven & Moddable** — JSON-heavy for easy extension

---

## Roadmap (Updated)

### Phase 1 — Prototype (✅ Complete)
- Core data loading, province system, interactive map, InfoPanel
- Camera navigation (zoom/WASD/edge/middle-drag) — solid for current needs

### Phase 2 — Data & Core Systems Foundation
- Expand data models for TechTree, FocusTree, Equipment/Unit definitions, ProductionLines
- Basic national economy and production loop
- Infrastructure & development mechanics
- Scenario data expansion

### Phase 3 — Designers & Military Core
- Implement Division, Tank, Plane, Ship designers (UI + backend)
- Production line system feeding designers
- Basic military units, templates, and movement
- Initial focus tree framework

### Phase 4 — Advanced Gameplay
- Full tech research system
- Deep focus trees for major powers
- Espionage system + agent management + missions/facilities
- Trade routes and diplomacy mechanics
- War mechanics and combat resolution

### Phase 5 — Multiplayer, AI & Polish
- Multiplayer architecture and online play (2–4 primary, up to 4–8)
- Capable AI opponents using core systems
- UI/UX polish, tooltips, national overview screens
- Sound, visuals, camera refinements
- Save/load, replay tools

### Phase 6 — Future & Release
- Spaceship / space station / satellite designers and orbital mechanics
- 2026+ specific content (advanced tech, space race elements)
- Balance, alt-history events, Steam integration
- Mod support expansion

**Note on Map Visuals (updated June 2026):** Grand theater underlay, terrain toggle, dynamic borders, starter map editor, and resizable F10 debug panel are **in the build**. Main-loop combat and production-grade 8K source art are **next** — see [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md).

---

## Tech Stack & Development

- **Godot Engine 4.6+** + **GDScript**
- Data-driven design (JSON + Godot Resources for provinces, countries, tech, focuses, units, etc.)
- Networking: Godot built-in (ENet/WebRTC) or plugins evaluated for multiplayer
- Development aided by **Cursor** + latest **Grok / Grok Build** multi-agent coding tools for rapid iteration on complex systems

---

## How to Run (Development)

1. Clone the repository
2. Open in **Godot 4.6.2** or newer
3. For full playtest harness: open `scenes/TestScenario.tscn` and press **F5**
4. Or open `scenes/WorldMap.tscn` for the base map scene

---

## Map & Visual Assets

The game uses a **grand theater stylized Europe raster** (`assets/maps/europe_grand_theater_ultra_high.jpg`) as the primary underlay, with province vectors and overlays on top. Legacy grey `world_map` assets are suppressed on load.

- Toggle **terrain layer** (detailed art vs clean political view) in Debug → Map Visual Editor
- Curate placements at high zoom; export `user://map_editor_placements.json` for python roundtrip
- Replace the placeholder JPG with your final upscaled master when ready (see grand theater test doc)

QC checklist: [docs/TEST_MAP_GRAND_THEATER_FOUNDATION.md](docs/TEST_MAP_GRAND_THEATER_FOUNDATION.md)

---

## Contributing

Contributions welcome from Godot devs, historians, strategy fans, UI designers, and anyone passionate about deep grand strategy with alt-history freedom.

---

## License

MIT License — see LICENSE file.

---

**Let’s build the definitive grand strategy experience of ascendancy across the ages.**
