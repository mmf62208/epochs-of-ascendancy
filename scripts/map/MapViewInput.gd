# scripts/map/MapViewInput.gd
## Map camera navigation helpers — keep pan/zoom responsive while simulation is paused
## (Engine.time_scale == 0 yields zero _process delta otherwise).
class_name MapViewInput
extends RefCounted

static var _last_real_usec: int = 0

const _PAUSE_DELTA_FALLBACK := 1.0 / 60.0
const _PAUSE_DELTA_MAX := 0.05

## True outer-window edge-pan strip, in screen pixels (not viewport / content-scale).
## Play 1280x740: a 64px HUD-offset band at y≈200 and y>676 was the wrong strip.
const EDGE_PAN_SCREEN_PX := 6.0

## Known autoload singletons that appear as direct children of the viewport root.
## These are plain Nodes (with scripts like GameData.gd) and MUST NEVER have .visible (or other CanvasItem-only props) accessed.
## Pre-filtering by name here (name is always valid on Node) + explicit separate type/visible checks below completely prevents
## the error: "Invalid access to property or key 'visible' on a base object of type 'Node (GameData.gd)'."
const _AUTOLOAD_NODE_NAMES: PackedStringArray = [
	"GameData", "TimeManager", "SaveLoadManager", "ProductionManager", "LeaderManager",
	"SupplyManager", "MapManager", "AgentManager", "BattleManager", "InfrastructureDevelopmentManager",
	"SpecialSiteManager", "WeatherManager",
]

## Use in _process camera movement: respects time scale when running, wall clock when paused.
static func motion_delta(scaled_delta: float) -> float:
	if Engine.time_scale > 0.001:
		_last_real_usec = Time.get_ticks_usec()
		return scaled_delta
	var now := Time.get_ticks_usec()
	var dt := _PAUSE_DELTA_FALLBACK
	if _last_real_usec > 0:
		dt = clampf(float(now - _last_real_usec) / 1_000_000.0, 0.0, _PAUSE_DELTA_MAX)
	_last_real_usec = now
	return maxf(dt, _PAUSE_DELTA_FALLBACK * 0.25)


## Pure strip math: window client pixels, independent of zoom / stretch / HUD offset.
static func edge_pan_direction_at(
	mouse_window: Vector2,
	window_size: Vector2,
	hovered_blocks: bool,
	window_focused: bool = true,
	mouse_inside_window: bool = true
) -> Vector2:
	if not window_focused or not mouse_inside_window:
		return Vector2.ZERO
	if hovered_blocks:
		return Vector2.ZERO
	if window_size.x < 2.0 or window_size.y < 2.0:
		return Vector2.ZERO
	if mouse_window.x < 0.0 or mouse_window.y < 0.0:
		return Vector2.ZERO
	if mouse_window.x > window_size.x or mouse_window.y > window_size.y:
		return Vector2.ZERO
	var dir := Vector2.ZERO
	var strip: float = EDGE_PAN_SCREEN_PX
	if mouse_window.x <= strip:
		dir.x -= 1.0
	elif mouse_window.x >= window_size.x - strip:
		dir.x += 1.0
	if mouse_window.y <= strip:
		dir.y -= 1.0
	elif mouse_window.y >= window_size.y - strip:
		dir.y += 1.0
	return dir


static func window_allows_edge_pan(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	if DisplayServer.get_name() == "headless":
		return true
	var win: Window = viewport.get_window()
	if win == null:
		return true
	return win.has_focus()


static func mouse_is_inside_window(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var win: Window = viewport.get_window()
	if win == null:
		return true
	var mouse: Vector2 = win.get_mouse_position()
	var sz := Vector2(win.size)
	return mouse.x >= 0.0 and mouse.y >= 0.0 and mouse.x <= sz.x and mouse.y <= sz.y


## Any hovered UI Control that is not the map itself blocks edge pan
## (toasts, top bar, unit card, panels, popups). IGNORE filters are not hovered.
static func hovered_ui_blocks_edge_pan(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var hovered: Control = viewport.gui_get_hovered_control()
	if hovered == null:
		return false
	if hovered.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	var nn := str(hovered.name)
	if nn == "WorldMap" or nn == "MapRenderer" or nn.begins_with("Province"):
		return false
	return true


## Screen-pixel edge direction, or ZERO when blocked / not on the true rim.
static func edge_pan_direction_screen(viewport: Viewport) -> Vector2:
	if viewport == null:
		return Vector2.ZERO
	var win: Window = viewport.get_window()
	if win == null:
		return Vector2.ZERO
	var mouse: Vector2 = win.get_mouse_position()
	var sz := Vector2(win.size)
	var inside: bool = mouse.x >= 0.0 and mouse.y >= 0.0 and mouse.x <= sz.x and mouse.y <= sz.y
	return edge_pan_direction_at(
		mouse,
		sz,
		hovered_ui_blocks_edge_pan(viewport),
		window_allows_edge_pan(viewport),
		inside
	)


## True when a modal / command-center style overlay is open — blocks ALL map nav
## (WASD, edge pan, middle/right drag). Does NOT block for mere HUD hover.
static func modal_blocks_map_nav(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	return _any_visible_blocking_popup(viewport)


## True when this control or an ancestor is map chrome that must freeze edge-pan
## (province inspector, docked unit card, TopInfoBar, named popups). Walks
## ancestors; also honors `blocks_edge_pan` / `unit_card_dock` meta on roots.
static func control_or_ancestor_blocks_edge_pan(node: Node) -> bool:
	const BLOCKING_POPUP_NAMES: PackedStringArray = [
		"LeaderAssignmentScreen", "PolicyLawScreen", "LeaderPickerPopup", "LeaderDetailScreen",
		"LeaderReplacementPickerPopup", "NationalSpiritsScreen", "ProductionAssignmentScreen", "OrderCommandPanel",
		"AgentAssignmentScreen", "TechnologyScreen", "DiplomacyView", "TradeMarketView",
		"MainMenu", "RetirementOfferPopup", "RetoolingWarningPopup", "DesignPickerPopup",
		"MissionPickerPopup", "TrainingPathScreen", "FormationPickerPopup", "SaveManagerPopup",
		"MainMenuPopup", "DraggablePanel",
	]
	var walk: Node = node
	while walk != null:
		if walk.has_meta("blocks_edge_pan") and bool(walk.get_meta("blocks_edge_pan")):
			return true
		if walk.has_meta("unit_card_dock") and bool(walk.get_meta("unit_card_dock")):
			return true
		var nname := str(walk.name)
		# Province inspector + docked unit card / UnitDetailPopup (name, not Panel-only).
		if (
			nname == "InfoPanel"
			or nname == "UnitDetailPopup"
			or nname.begins_with("UnitDetailPopup")
		):
			return true
		# Top bar MUST block edge-pan — otherwise mouse over 1x/Prod continuously
		# pans the camera and thrash-redraws world_full (no hover flash, no wheel scroll).
		if nname == "TopInfoBar" or nname == "MapModeToolbar" or nname == "Minimap" or nname == "StrategicMinimap":
			return true
		if nname in BLOCKING_POPUP_NAMES or nname.ends_with("Screen") or nname.ends_with("Popup") or "Picker" in nname:
			return true
		# DiplomacyView / TradeMarketView are popups; bare "View" suffix is too broad (blocked map chrome).
		if nname in ["DiplomacyView", "TradeMarketView", "SpaceLayerBoardView", "MatchmakingLobbyView"]:
			return true
		if walk is Window and (walk as Window).visible:
			# Main game Window is the scene-tree root. Treating it as a modal
			# would freeze edge-pan for every hovered Control (incl. Close tests).
			# Real picker Windows are parented under the tree.
			if walk.get_parent() == null:
				break
			return true
		if walk is Panel or walk is PanelContainer:
			var panel_name := nname
			if panel_name in [
				"InfoPanel",
				"SaveManagerPopup",
				"MainMenuPopup",
				"SupplyMenuPanel",
				"SupplyOverlayLegend",
				"MapLegendPanel",
				"TechnologyScreen",
			]:
				return true
		walk = walk.get_parent()
	return false


static func _visible_control_contains_mouse(ctrl: Node, mouse: Vector2) -> bool:
	if ctrl == null or not (ctrl is Control):
		return false
	var c: Control = ctrl as Control
	if not c.visible:
		return false
	return c.get_global_rect().has_point(mouse)


## Fallback when gui_get_hovered_control is null at the screen edge: mouse
## still sits on InfoPanel / UnitDetailPopup / docked card Close.
static func _mouse_over_map_chrome_blocks_edge_pan(viewport: Viewport) -> bool:
	if viewport == null or viewport.get_tree() == null:
		return false
	var mouse: Vector2 = viewport.get_mouse_position()
	var mrs: Array = viewport.get_tree().get_nodes_in_group("map_renderer")
	for mr_v in mrs:
		if mr_v == null or not (mr_v is Node):
			continue
		var mr: Node = mr_v as Node
		var ui: Node = mr.get_node_or_null("UI")
		if ui == null:
			continue
		var ip: Node = ui.get_node_or_null("InfoPanel")
		if _visible_control_contains_mouse(ip, mouse):
			if ip is Node and not ip.has_meta("blocks_edge_pan"):
				ip.set_meta("blocks_edge_pan", true)
			return true
		var card: Node = ui.get_node_or_null("UnitDetailPopup")
		if _visible_control_contains_mouse(card, mouse):
			if card is Node and not card.has_meta("blocks_edge_pan"):
				card.set_meta("blocks_edge_pan", true)
			return true
		for ch in ui.get_children():
			if ch == null or not (ch is Control):
				continue
			var ch_c: Control = ch as Control
			if not ch_c.visible:
				continue
			var docked: bool = ch_c.has_meta("unit_card_dock") and bool(ch_c.get_meta("unit_card_dock"))
			var flagged: bool = ch_c.has_meta("blocks_edge_pan") and bool(ch_c.get_meta("blocks_edge_pan"))
			if (docked or flagged) and ch_c.get_global_rect().has_point(mouse):
				return true
	return false


## True when the hovered GUI should block map edge-scroll (includes TopInfoBar / HUD chrome).
## Also returns true if any blocking popup/Window/Screen is currently *open and visible* anywhere
## (so edge pan is suppressed even when mouse is at screen edge over the bare map while a dialog is up).
static func edge_pan_blocked_by_gui(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var hovered: Control = viewport.gui_get_hovered_control()
	# First pass: only block when hovering real HUD/modals — NOT every STOP Control
	# (was returning true for any STOP, so edge pan never worked near legend/notices/map UI).
	if control_or_ancestor_blocks_edge_pan(hovered):
		return true
	# Close sits in the north/bottom edge bands; hover can be null there.
	if _mouse_over_map_chrome_blocks_edge_pan(viewport):
		return true
	# NOTE: do NOT treat every MOUSE_FILTER_STOP as a block — map hit areas / labels used STOP
	# and that disabled edge pan on most of the board.

	# Global popup check: modal screens open even if mouse is on map edge
	if _any_visible_blocking_popup(viewport):
		return true
	return false

## Returns true if any blocking popup, Window, or screen (by name pattern or type) is currently visible.
## This ensures edge-scroll is disabled while popups are open even if the mouse is not hovering the popup.
static func _any_visible_blocking_popup(viewport: Viewport) -> bool:
	if viewport == null or viewport.get_tree() == null:
		return false
	var root: Node = viewport.get_tree().root
	if root == null:
		return false
	# Direct children (common for picker Windows and DraggablePanel screens added via add_child to root).
	# Note: autoloads (GameData etc.) are also direct children of the Viewport root; they are plain Nodes (script GameData.gd etc.) and must be skipped before any .visible access.
	for child in root.get_children():
		if str(child.name) in _AUTOLOAD_NODE_NAMES:
			continue
		if _is_visible_blocking_node(child):
			return true
	# Also scan a bit deeper for safety (e.g. inside CanvasLayer/UI layers)
	if root.has_node("UI"):
		var ui := root.get_node("UI")
		for c in ui.get_children():
			if _is_visible_blocking_node(c):
				return true
	return false

static func _is_visible_blocking_node(n: Node) -> bool:
	if n == null:
		return false
	var nn := str(n.name)
	# Skip autoload/data singletons FIRST (name access is safe on any Node; prevents the exact error "Invalid access to ... 'visible' on a base object of type 'Node (GameData.gd)'").
	if nn in _AUTOLOAD_NODE_NAMES:
		return false
	# Non-visual top-level scene roots are never blocking popups.
	if nn == "TopInfoBar" or nn == "WorldMap" or nn == "TestScenario" or nn.begins_with("Map"):
		return false
	# Command Center is a CanvasLayer (NOT CanvasItem) — must treat by name before the CanvasItem guard.
	# Without this, WASD/edge/drag still pan under MainMenu (user playtest 2026-08-07).
	# Closing / queued leftover must not freeze empty-area left-drag (Fri CC smoke
	# Drag1–3 no camera move after Esc→CC dismiss). Open CC still blocks.
	if nn == "MainMenu" or nn == "MainMenuPopup":
		if n.is_queued_for_deletion():
			return false
		if bool(n.get("_closing")):
			return false
		if n is CanvasLayer:
			for ch_layer in n.get_children():
				if ch_layer is CanvasItem and (ch_layer as CanvasItem).visible:
					return true
				if ch_layer is CanvasLayer:
					return true
			return false
		if n is CanvasItem and (n as CanvasItem).visible:
			return true
		# Visible if any CanvasItem child is up (Root panel under layer).
		for ch in n.get_children():
			if ch is CanvasItem and (ch as CanvasItem).visible:
				return true
			if ch is CanvasLayer:
				return true
		return false
	# Only CanvasItem / Window nodes have .visible. Guard explicitly with separate statements so no expression can ever read .visible on a plain Node.
	if not (n is CanvasItem or n is Window):
		# CanvasLayer screens (other than MainMenu handled above)
		if n is CanvasLayer and (nn.ends_with("Screen") or nn.ends_with("Popup") or "Picker" in nn):
			return true
		return false
	if not n.visible:
		return false
	# Now safe: n is a visible CanvasItem/Window. Check name patterns for popups/panels.
	# Docked map chrome must NOT freeze left-drag pan (Play: pan dead while inspector/unit card up).
	if nn in ["InfoPanel", "UnitDetailPopup", "ProvinceHoverTooltip", "MapModeToolbar", "MapProvinceSearch"]:
		return false
	if nn in [
		"LeaderAssignmentScreen", "PolicyLawScreen", "LeaderPickerPopup", "LeaderDetailScreen",
		"LeaderReplacementPickerPopup", "NationalSpiritsScreen", "ProductionAssignmentScreen", "OrderCommandPanel",
		"AgentAssignmentScreen", "TechnologyScreen", "DiplomacyView", "TradeMarketView",
		"MainMenu", "RetirementOfferPopup", "RetoolingWarningPopup", "DesignPickerPopup",
		"MissionPickerPopup", "TrainingPathScreen", "FormationPickerPopup", "SaveManagerPopup",
		"MainMenuPopup",
	] or nn.ends_with("Screen") or nn.ends_with("Popup") or "Picker" in nn or nn.ends_with("View"):
		return true
	if n is Window:
		return true
	if n is Panel or n is PanelContainer:
		if nn in ["SupplyMenuPanel", "SaveManagerPopup", "MainMenuPopup"]:
			return true
	return false
