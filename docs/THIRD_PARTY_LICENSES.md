# Third-Party Licenses and Attributions

This project, **Epochs of Ascendancy** (MIT licensed — see root LICENSE file), incorporates or plans to use the following third-party components, plugins, and assets. All are used in accordance with their respective licenses.

We document these here to ensure proper attribution, compliance, and easy reference for credits in the final game (e.g., in-game credits screen, `LICENSES/` folder, or documentation).

**General note:** Most Godot Asset Library addons use permissive licenses (MIT, Apache-2.0). Always review the `LICENSE` file inside each `addons/<name>/` folder after installation. For commercial use, include the required copyright notices and license texts.

## Core Project
- **Epochs of Ascendancy**
  - License: MIT
  - Copyright: (c) 2026 Mike F (and contributors)
  - Location: root LICENSE, README.md

## Installed Godot Plugins (as of current session)
These are enabled in `project.godot` (Project Settings > Plugins).

- **Dialogue Manager** (v3.10.4)
  - Author: Nathan Hoad and Dialogue Manager contributors
  - License: MIT
  - Copyright: (c) 2022-present Nathan Hoad and Dialogue Manager contributors
  - Usage: Branching narrative, events, peace negotiation choices, historical vs. alt-history decision trees, follow-on multi-year influence points.
  - Location: `addons/dialogue_manager/`
  - Full license: See `addons/dialogue_manager/LICENSE`
  - Attribution requirement: Include the above copyright notice and MIT permission notice in all copies or substantial portions of the Software (standard for game credits or a bundled licenses file).

- **Godot State Charts** (v0.22.4)
  - Author: Jan Thomä & Contributors
  - License: MIT
  - Copyright: (c) 2023 Jan Thomä
  - Usage: Visual state machines for peace treaty lifecycle, enforcement phases, follow-on event triggers, focus availability based on prior conference choices, continuation/successor logic states.
  - Location: `addons/godot_state_charts/`
  - Full license: See `addons/godot_state_charts/LICENSE`
  - Attribution requirement: Include the copyright notice and permission notice.

- **CalendarButton4x** (v1.0)
  - Author: CW
  - License: (Assumed permissive / check plugin files; commonly MIT or similar for small Godot UI tools)
  - Usage: Calendar / date UI elements (potentially for time-based follow-on events or in-game date display in the 1918–192x timeline).
  - Location: `addons/calendar_button/`
  - Note: Verify exact license in `plugin.cfg` or source. Include appropriate credit.

## Recommended Graph Plugins for Native GraphEdit (from Asset Library search)
Godot provides a built-in `GraphEdit` + `GraphNode` system for custom visual graph editors (nodes connected by edges). This is ideal for our needs:
- Focus trees (national/ideological paths with historical/alt-history branches)
- Tech trees (era-spanning research)
- Event graphs (Armistice peace negotiations, term choices, follow-on decision points 1919–1925+)
- State visualization for peace_state / treaty phases

We recommend installing these (all shown as MIT in the library at time of review) via Godot AssetLib to accelerate visual authoring without fully reinventing graph UI logic. They complement our existing Dialogue Manager (narrative branches) + Godot State Charts (logic).

**Top recommendations to install now:**
1. **Event Graph for Godot** (by kudo, MIT)
   - Why: Purpose-built for event systems. Perfect for the 1918 Armistice conference (branching term selections, agent-influenced outcomes), follow-on crises (1919 enforcement, 1923 Ruhr analog), and multi-year decision points. Visual graph for historical vs. alt-history paths.
   - Fits native GraphEdit patterns.

2. **Synapse: Graph-Based State Machine** (by gklompje, MIT)
   - Why: Graph-based state machine editor. Excellent companion to the Godot State Charts plugin we already have. Use for visual modeling of peace treaty "states" over time (e.g., pre-conference leverage → resolution → 1919 phase → 1923 crisis → continuation triggers). Helps design the "few influence and decision points" without pure code.

3. **Custom Graph Editor** (by Tehelka, MIT) or **Tree Maps - Graphs and Skill Trees** (by ToxicStarfall, MIT)
   - Why: General custom graph tools or tree/skill graph editors. Ideal prototype for future focus trees (national paths that react to peace outcomes) or leader skill trees. Use as a starting template to build a data-driven focus tree editor that exports to our JSON format (like the existing tech trees).

**Installation for any of the above:**
- In Godot editor: AssetLib tab → search the exact name → Download → Install to `addons/`.
- Enable in Project Settings > Plugins.
- Review their `LICENSE` (all MIT per library listing) and add entries to this document.
- Attribution: Same MIT requirements — include copyright notice in credits.

Other potentially useful from the search (MIT):
- SignalGraphVisualizer (for debugging our event signals and peace follow-ons).
- Graphite or Graph2D (general graphing/visualization helpers).

After installing any, run a quick test scene using Godot's GraphEdit to prototype one peace decision graph or focus branch. Example starting point: Create a new scene with a GraphEdit node, add GraphNodes for "Historical Exclusion", "Limited Observers", "Full Participants", connect them with conditions based on agent leverage / pre-conference missions, and export the selected path + effects to GameData.peace_state.

**Current progress on plugins you have enabled (Dialogue Manager + Godot State Charts):**
- Real .dialogue resources now drive the 1918 conference choice and the 1923 crisis (see data/peace/*.dialogue and the wired start_*_dialogue methods in GameData).
- The PeaceTreatyPhasesDemo (runnable via F10 or the button in the conference window) now launches the real 1923 crisis dialogue when you advance to 1923, records the response, and updates the simulated "State Machine Phase" label based on it. This is the live prototype for what a visual StateChart tree (designed in the Godot State Charts editor) would drive via send_event + guards reading peace_state. The .tscn stub has instructions for replacing the demo root with an actual StateChart node hierarchy.

## Other Third-Party / Future
- Any additional Godot Asset Library items, Python tools in `tools/`, or external assets will be added here with license details.
- For MCP / partner tools (e.g., if enabling Sentry, Cloudflare, etc., for dev assistance or future multiplayer): These are separate from game runtime. Review their individual terms of service for commercial/game use before relying on them in production. No automatic royalty-free game embedding assumed.

## How to Attribute in the Game
- In-game Credits screen: List "Dialogue Manager by Nathan Hoad (MIT)", "Godot State Charts by Jan Thomä (MIT)", etc.
- Bundle a copy of relevant LICENSE files in a `licenses/` or `THIRD_PARTY/` folder with the game distribution.
- Update this document whenever new plugins or assets are added.
- For the root project MIT: Already covered in README and LICENSE.

This document ensures we capture everything proactively. Last updated: 2026-06 (session).

**Questions or additions?** Provide the exact plugin name/author from AssetLib, and I'll add the entry with proper details. Always double-check the installed LICENSE file for the precise copyright text.