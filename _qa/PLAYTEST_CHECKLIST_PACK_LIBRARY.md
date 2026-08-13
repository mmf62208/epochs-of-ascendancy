# Playtest checklist — Pack library / minimap / theme / QR (Passes 46–64)

Game should be open (TestScenario). Log: `_qa/playtest_20260718_144048.log`

## A. Map basics (2 min)
1. Zoom/pan map — Europe should be visible; world underlay present
2. Click a province — inspector shows info
3. **F10** — harness panel opens without freeze
4. Note any hitch / black flash / script errors

## B. Pack compare card (3 min)
1. Find pack/compare UI on map (route pack compare card)
2. Toggle **Heat** on/off; move intensity slider
3. Cycle heat ramp (dropdown or ↻/↺ / ramp strip click)
4. Edit cool/hot colors when ramp = custom
5. **Pin SFX** mute + volume + bus dropdown + **▶** preview
6. **Lib** opens pack library; **Shift+Lib** second window

## C. Pack library window (5 min)
1. Layout: standard / compact / wide / left (or Ctrl+1–4)
2. Dock: float / left / right / bottom (or Ctrl+Shift arrows; drag title to edge)
3. Opacity **α** slider; **Link α** with second window open
4. **Theme** dropdown: classic / mono / amber / magenta
5. Chrome/Title color pickers — live preview; **Save Theme**
6. Theme name field — type partial id, autocomplete ↑↓ Enter / mouse hover
7. **Thr↗** copy theme · **Shift+Thr↗** theme QR popup · **Ctrl+Shift+Thr↗** strip
8. **Snap↗** copy chrome · **Shift+Snap↗** chrome QR · **Ctrl+Shift+Snap↗** strip
9. **QR↙** import from PNG (optional: Shift multi-file)
10. Select packs left/right — cyan/magenta pulse; multi-select cascade
11. Filter search; bulk select if available; pin focus from pack if wired

## D. Persistence (2 min)
1. Change theme + dock + SFX volume
2. Close Lib, reopen — prefs stick
3. Optional: quit & relaunch later to confirm `user://route_packs/_map_prefs.json`

## E. Combat / core (optional, 3 min)
1. Select friendly province → Ctrl+click enemy for assault preview/execute if available
2. F10 sample assault button
3. Quicksave / quickload if you use it

## Report back
- What worked
- What felt broken / slow / confusing
- Exact UI label you clicked when it failed
- Approx time / action when you saw a freeze

I'll watch the log for SCRIPT ERROR / MapRenderer / QR / Theme lines while you play.
