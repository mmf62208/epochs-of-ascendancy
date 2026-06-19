# scripts/map/MapViewInput.gd
## Map camera navigation helpers — keep pan/zoom responsive while simulation is paused
## (Engine.time_scale == 0 yields zero _process delta otherwise).
class_name MapViewInput
extends RefCounted

static var _last_real_usec: int = 0

const _PAUSE_DELTA_FALLBACK := 1.0 / 60.0
const _PAUSE_DELTA_MAX := 0.05

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


## True when the hovered GUI should block map edge-scroll (not TopInfoBar strip).
## Also returns true if any blocking popup/Window/Screen is currently *open and visible* anywhere
## (so edge pan is suppressed even when mouse is at screen edge over the bare map while a dialog is up).
static func edge_pan_blocked_by_gui(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var hovered: Control = viewport.gui_get_hovered_control()
	var node: Node = hovered
	const BLOCKING_POPUP_NAMES: PackedStringArray = [
		"LeaderAssignmentScreen", "PolicyLawScreen", "LeaderPickerPopup", "LeaderDetailScreen",
		"LeaderReplacementPickerPopup", "NationalSpiritsScreen", "ProductionAssignmentScreen",
		"AgentAssignmentScreen", "TechnologyScreen", "DiplomacyView", "TradeMarketView",
		"MainMenu", "RetirementOfferPopup", "RetoolingWarningPopup", "DesignPickerPopup",
		"MissionPickerPopup", "TrainingPathScreen", "FormationPickerPopup", "SaveManagerPopup",
		"MainMenuPopup", "DraggablePanel",
	]
	# First pass: if hovering over a blocking UI, block (standard case)
	while node != null:
		if node.name == "TopInfoBar":
			return false
		var nname := str(node.name)
		if nname in BLOCKING_POPUP_NAMES or nname.ends_with("Screen") or nname.ends_with("Popup") or "Picker" in nname or nname.ends_with("View"):
			return true
		if node is Window:
			return true
		if node is Panel or node is PanelContainer:
			var panel_name := nname
			if panel_name in [
				"InfoPanel",
				"SaveManagerPopup",
				"MainMenuPopup",
				"SupplyMenuPanel",
			]:
				return true
		node = node.get_parent()
	if hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		return true

	# Global popup check: if any known blocking popup/dialog is open+visible (mouse may be on map edge outside it)
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
	# Only CanvasItem / Window nodes have .visible. Guard explicitly with separate statements so no expression can ever read .visible on a plain Node.
	if not (n is CanvasItem or n is Window):
		return false
	if not n.visible:
		return false
	# Now safe: n is a visible CanvasItem/Window. Check name patterns for popups/panels.
	if nn in [
		"LeaderAssignmentScreen", "PolicyLawScreen", "LeaderPickerPopup", "LeaderDetailScreen",
		"LeaderReplacementPickerPopup", "NationalSpiritsScreen", "ProductionAssignmentScreen",
		"AgentAssignmentScreen", "TechnologyScreen", "DiplomacyView", "TradeMarketView",
		"MainMenu", "RetirementOfferPopup", "RetoolingWarningPopup", "DesignPickerPopup",
		"MissionPickerPopup", "TrainingPathScreen", "FormationPickerPopup", "SaveManagerPopup",
		"MainMenuPopup",
	] or nn.ends_with("Screen") or nn.ends_with("Popup") or "Picker" in nn or nn.ends_with("View"):
		return true
	if n is Window:
		return true
	if n is Panel or n is PanelContainer:
		if nn in ["InfoPanel", "SupplyMenuPanel", "SaveManagerPopup", "MainMenuPopup"]:
			return true
	return false
