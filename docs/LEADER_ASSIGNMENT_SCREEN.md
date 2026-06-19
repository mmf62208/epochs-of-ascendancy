# Leader Assignment Screen — Detailed Specification

**Last Updated:** May 2026  
**Status:** Design Phase  
**Related Systems:** LeaderManager, LeaderScreenData, Leader, National Positions

---

## 1. Purpose

The Leader Assignment Screen allows the player to manage their military leadership. It serves two main purposes:

- Assigning and reassigning field commanders (generals, admirals, air marshals) to armies, fleets, and air wings.
- Managing the top national military positions (Chief of the Army, Chief of the Navy, Chief of the Air Force, Chief of the Space Force).

Good leadership should feel **impactful and personal**. Players should develop favorite generals over time and feel the consequences of poor assignments or losing experienced leaders.

---

## 2. Core Design Philosophy

- **Clarity First**: The player should quickly see who is available, who is already assigned, and who holds the top national positions.
- **Layered Information**: Show key skills and traits at a glance. Hide detailed modifier breakdowns in tooltips or a detail panel.
- **Strategic Weight**: National positions (Chiefs) should feel more important than regular army assignments.
- **Emotional Connection**: Traits, experience, and status (injured/captured) should help players form attachments to certain leaders.
- **Minimalist Retrowave Aesthetic**: Clean, readable, dark theme with strong visual hierarchy and accent colors.

---

## 3. Recommended Screen Layout

### 3.1 National Positions Section (Top)

**Purpose**: Show and manage the four (or five) most important military leadership roles in the country.

**Layout**:
- Four (or five) prominent cards/boxes for:
  - Chief of the Army
  - Chief of the Navy
  - Chief of the Air Force
  - Chief of the Space Force
- Each card should display:
  - Current leader's name (or "Unassigned")
  - Key bonuses they provide to the nation
  - Button: **Change / Assign**

**Design Note**: These positions should have more visual weight than regular leader assignments because they affect the entire country.

---

### 3.2 Two-Column Main Area

#### Left Column: Available Leaders

- Scrollable list of all unassigned (and non-captured) leaders.
- Each entry should show:
  - Name
  - Leader Type (General / Admiral / Air Marshal)
  - Key Skills (Attack / Defense / Logistics)
  - Notable Traits (as small icons or tags)
  - Status indicators (if injured)
- Filters:
  - By Type (All / Army / Navy / Air)
  - By Skill Tier (Elite / Veteran / Average)
  - Search by name or trait

#### Right Column: Formations Without Leaders

- List of armies, fleets, or air wings that currently have no leader assigned.
- Each entry should show:
  - Formation name
  - Current size / strength
  - Button: **Assign Leader**

---

### 3.3 Detail Panel (Side Panel)

When a leader is selected (from either column), show:

- Full name and background (if available)
- All skills with values
- All traits with short descriptions
- Experience and number of battles fought
- Current status (Available / Injured / Captured)
- **Primary Action Button**: **Assign to Army / Fleet** (context dependent)
- Button to view full trait/modifier breakdown (deeper layer)

---

## 4. Interaction Flow

### Assigning a Regular Leader
1. Player selects an available leader.
2. Detail panel shows leader information.
3. Player clicks **Assign**.
4. Player selects a formation from the right column (or from a list).
5. Leader is assigned. Both lists update.

### Changing a National Position (Chief)
1. Player clicks **Change** on one of the national position cards.
2. A list of eligible leaders appears (filtered appropriately).
3. Player selects a new leader.
4. **Warning / Cost Popup** appears (once costs are implemented).
5. Confirmation changes the national position and applies bonuses.

### Removing a Leader
- Future: Allow unassigning leaders from formations (with possible small cooldown or penalty).

---

## 5. Data Requirements

This screen should be powered primarily by `LeaderScreenData`.

**Key Fields Needed**:
- `total_leaders`
- `available_leaders`
- `injured_leaders`
- `captured_leaders`
- `national_positions`
- `leaders` (array of leader summaries)
- `leaders_by_availability`
- `leaders_by_type`

**Leader Summary Dictionary** should include:
- `leader_id`
- `name`
- `leader_type`
- `attack_skill`
- `defense_skill`
- `logistics_skill`
- `traits`
- `experience`
- `is_injured`
- `is_captured`
- `assigned_army_id`
- `skill_tier` (elite / veteran / average / green)

---

## 6. Visual & UX Guidelines

- Use **color and icons** to quickly communicate leader status and traits.
- National positions should feel **prestigious** (larger cards, stronger visual treatment).
- Make injured or captured leaders clearly visible but not overly punitive in the UI.
- Keep the two-column layout balanced and easy to scan.
- Tooltips should explain what each skill and trait actually does.
- Avoid showing raw modifier numbers on the main list (use them in the detail panel or tooltips).

---

## 7. Future Enhancements

- Drag-and-drop assignment (optional, click-based should remain primary)
- Leader portraits ✅ implemented: small icons in list rows + header col (24px TextureRect from summary portrait_path); DetailScreen full. Agent portraits in AgentAssignmentScreen too. Save/load hardened.
- Historical leader bios and flavor text
- Ability to promote leaders
- Special events tied to leader traits or experience (e.g., "Desert Fox" gaining bonuses in desert campaigns)
- List of formations that would benefit most from a specific leader

---

## 8. Success Criteria

A good Leader Assignment Screen should allow the player to quickly answer:

- Who are my best available leaders right now?
- Which of my armies/fleets don't have a commander?
- What bonuses am I currently getting from my Chiefs of Staff?
- Is one of my important generals injured or captured?
- Which leader should I assign to this new army I just created?

---

**End of Specification**
