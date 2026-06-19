# UI Design Reference — Epochs of Ascendancy

**Last updated:** June 2026 · **Index:** [README.md](README.md)

## Debug overlay (F10)

Development tools live in a **screen-space panel** on `UILayer` (not map space).

| Expectation | Implementation |
|-------------|----------------|
| Readable without horizontal scroll | Buttons and labels span panel width; vertical scroll only |
| Reposition | Drag the **DEBUG OVERLAY** title bar |
| Resize | Drag the **⤡** grip at the bottom-right corner |
| Long tool lists | Collapsible sections; Collapse All / Expand All above the scroll area |
| Aesthetic | `RetrowaveTheme.style_detail_panel` — match TopInfoBar / MainMenu |

Avoid fixed pixel offsets for dynamic tool rows; append to section `VBoxContainer`s so layout stays coherent when the panel is resized.

## Core UI Principles

### Layered Complexity (Very Important)
- **Surface Layer**: Key information must be immediately visible and easy to understand.
- **Deeper Layers**: Complex math, modifiers, calculations, and detailed breakdowns should be accessible but not forced on the player (tooltips, detail panels, expandable sections).
- Goal: Transparency without overwhelming the player. The player should not need to dig through code or multiple menus to understand the current state.

### What We Want to Avoid
- Visual clutter and too many small numbers on screen at once.
- Poor contrast or hard-to-read text.
- Unclear interaction states (what can I click? what will happen?).
- Forcing the player to do mental math to understand important information.
- Overly complex assignment flows.

### What Works Well (Inspiration)
- Clean visual hierarchy and strong use of color coding.
- Summary information first, details on demand.
- Clear status at a glance (good use of icons, progress bars, and color).
- Progressive disclosure — don't show everything at once.

### Visual Direction (Current Inspiration)
- Minimalist retrowave aesthetic.
- Dark backgrounds with neon/cyan/magenta accents.
- Clean typography and high readability.
- Strong emphasis on clarity over decoration.

## Production Assignment Screen

**Full specification:** [PRODUCTION_ASSIGNMENT_SCREEN.md](PRODUCTION_ASSIGNMENT_SCREEN.md)

### Recommended Layout

**1. Top Summary Bar** (Always visible)
- Total Factories
- Average Efficiency (color coded)
- Factories Currently Retooling
- Estimated Total Daily Output
- Quick status indicators (green / yellow / red)

**2. Filters & Search**
- Filter by Factory Type (All, Shipyards, Tank Factories, Aircraft, etc.)
- Filter by Status (All, Producing, Retooling, Idle)
- Search by current design name

**3. Main Factory List**
Recommended columns (left to right):
- Location / Province
- Current Design (with icon if available)
- Efficiency (progress bar + percentage)
- Retooling Status (clear text or progress)
- Production Lines (used / max)
- Estimated Daily Output
- Quick Action button

**4. Detail Panel (Right side)**
When a factory is selected, show:
- Full factory details
- Current production status
- Retooling information (if active)
- Button: **Change Production**

### Interaction Rules
- Selecting a factory opens the detail panel.
- Changing production should trigger the retooling warning popup (with efficiency impact and time to full recovery).
- Future: Add a "Smart Assign" suggestion feature.

## Leader Assignment Screen

**Full specification:** [LEADER_ASSIGNMENT_SCREEN.md](LEADER_ASSIGNMENT_SCREEN.md)

### Recommended Layout

**1. National Positions Section (Top)**
- Chief of the Army
- Chief of the Navy
- Chief of the Air Force
- Chief of the Space Force
- Show current leader + key bonuses they provide
- Clear "Change" button with future cost preview

**2. Two Column Layout**
- **Left Column**: Available Leaders (filterable)
- **Right Column**: Armies / Fleets / Air Wings without a leader

**3. Leader List**
Each entry should show:
- Name
- Key skills (Attack / Defense / Logistics)
- Important traits (as icons or short tags)
- Current status (Available / Injured / Captured)
- "Assign" button

### Interaction Rules
- Simple click-to-assign flow is preferred over drag-and-drop for clarity.
- When assigning a leader, show what bonuses they will bring to that formation.
- National positions should feel more significant than regular army assignments.

## General Guidelines

- Prioritize **readability** and **decision-making speed** over visual flair.
- Use color meaningfully (efficiency, status, warnings).
- Always communicate **why** something is happening (especially retooling penalties and national position changes).
- Keep the most important information on the main view. Hide complexity behind tooltips and detail panels.
- Design for both keyboard/mouse and future controller support where reasonable.

## Future Expansion Notes
- Add caching for screen data when performance becomes relevant.
- Expand tooltip depth for advanced players (showing exact modifier breakdowns).
- Consider adding a "Smart Advisor" mode for production and leader assignment.

## Related Implementation

- Screen data resources: `scripts/ui_data/ProductionScreenData.gd`, `scripts/ui_data/LeaderScreenData.gd`
- Backend builders: `ProductionManager.get_production_screen_data()`, `LeaderManager.get_leader_screen_data()`
- Detailed specs: [PRODUCTION_ASSIGNMENT_SCREEN.md](PRODUCTION_ASSIGNMENT_SCREEN.md), [LEADER_ASSIGNMENT_SCREEN.md](LEADER_ASSIGNMENT_SCREEN.md)

## 2026-06 Menu/TopInfoBar/LS decision + polish (per task)
Menus: keep Production/Leaders/Tech/Diplomacy/Agents/Map as primary overhead for theme+loops (econ/mil/tech/dip/will/theater). resources+date right upper, speeds left. Consolidate save/settings/help (Policies/Dir) to Menu for room. Confirmed date right. LS polished w/ improved generated images (ascendant/agents etc epic jpgs) + visibility during world grand 471 stitch. Small graphic tweaks (e.g. date colors, bar widths) in code (TopInfoBar, LoadingScreen, Retrowave). See CURRENT_STATE, TopInfoBar.gd, LoadingScreen.gd.
