# scripts/ui/DebugOverlay.gd
## Dedicated, toggleable debug overlay panel for Epochs of Ascendancy.
##
## Use this as the central place for all development tools, diagnostics, and quick actions.
## Toggle with F10 or Ctrl+Shift+R (wired in TopInfoBar).
##
## DESIGN GOALS:
## - Retrowave aesthetic (consistent with the rest of the game)
## - Draggable + always-on-top when open
## - Sections that are easy to extend
## - Only visible in debug builds by default (can be forced)
## - Minimal performance impact when closed
##
## HOW TO EXTEND (for future systems):
##   var section := DebugOverlay.add_section("My Cool System")
##   section.add_child(my_debug_vbox_or_labels)
##
##   Or call DebugOverlay.refresh() after changing state you want reflected.
##
## Access:
##   - Hotkey: F10 or Ctrl+Shift+R (global)
##   - TopInfoBar "DBG" button (debug builds only)
##   - Main Menu → Debug section
##
## This panel replaces the previous scattered debug hotkey behavior.

class_name DebugOverlay
extends Control

const PANEL_WIDTH := 520
const PANEL_HEIGHT := 680
const MIN_PANEL_SIZE := Vector2(380, 420)
const MAX_PANEL_SIZE := Vector2(960, 920)
const MARGIN := 12

static var instance: DebugOverlay = null

var _main_container: PanelContainer
var _content_vbox: VBoxContainer
var _sections: Dictionary = {}           # title -> VBoxContainer
var _status_label: Label
var _last_refresh_time := 0.0

var _infra_count_label: Label
var _infra_list_vbox: VBoxContainer

## Border demo state (F10 Phase 1 tools): snapshot for revert + step cycling.
var _simulate_blob: Array[int] = []
var _simulate_snapshot: Dictionary = {}
var _simulate_step: int = -1

const DEMO_OWNER_TAGS: Array[String] = [
	"YUG", "SRB", "CRO", "SLO", "HUN", "BGR", "GER", "SOV", "USA", "FRA",
]
const DEMO_STUB_COLORS: Dictionary = {
	"YUG": Color(0.22, 0.55, 0.28, 0.88),
	"SRB": Color(0.72, 0.28, 0.22, 0.88),
	"CRO": Color(0.25, 0.48, 0.72, 0.88),
	"SLO": Color(0.78, 0.72, 0.25, 0.88),
	"HUN": Color(0.65, 0.35, 0.55, 0.88),
	"BGR": Color(0.35, 0.62, 0.38, 0.88),
	"GER": Color(0.45, 0.45, 0.48, 0.88),
	"SOV": Color(0.72, 0.22, 0.22, 0.88),
	"USA": Color(0.28, 0.42, 0.72, 0.88),
	"FRA": Color(0.55, 0.62, 0.82, 0.88),
}

var _placed_list_vbox: VBoxContainer  # for Map Visual Editor placed objects list + delete (user can curate high-res map placements)
var _edited_provinces_list_vbox: VBoxContainer  # for Province Border Editor current edited provinces + edit/delete buttons

# Dragging support for the panel (using title bar)
var _dragging := false
var _drag_offset := Vector2.ZERO
var _title_bar: HBoxContainer
var _scroll: ScrollContainer
var _outer_vbox: VBoxContainer
var _panel_size := Vector2(PANEL_WIDTH, PANEL_HEIGHT)
var _resize_grip: Control
var _resizing := false
var _resize_start_mouse := Vector2.ZERO
var _resize_start_size := Vector2.ZERO


func _ready() -> void:
	if instance != null and instance != self:
		queue_free()
		return
	instance = self

	name = "DebugOverlay"
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS   # still respond when game is paused
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_ui()
	_apply_theme()
	_position_default()
	_clamp_panel_to_screen()

	# Make debug content more readable: larger fonts, clip long texts, compact
	_style_debug_content()

	# Auto-refresh content when we become visible
	visibility_changed.connect(_on_visibility_changed)

	# Ensure initial clamp for the wider readable panel
	call_deferred("_clamp_panel_to_screen")
	call_deferred("_sync_content_width")
	resized.connect(func(): _sync_content_width())


static func toggle() -> void:
	if instance == null:
		# Try to find or create one in the current tree
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			var root := tree.current_scene
			if root:
				var existing := root.find_child("DebugOverlay", true, false)
				if existing:
					instance = existing as DebugOverlay
				else:
					var overlay := DebugOverlay.new()
					# Build immediately (before add_child/_ready) so set_meta for infra etc. are present
					# even if visibility/refresh fires synchronously on some paths (menu->debug).
					overlay._build_ui()
					overlay._apply_theme()
					overlay._position_default()
					# Add to UILayer (CanvasLayer) if present so the debug panel is always in screen space,
					# independent of the map camera/transform. This prevents cutoff when panning/zooming
					# the map and allows proper dragging/scrolling without being "cut off on left and right".
					var ui_layer := root.get_node_or_null("UILayer") as CanvasLayer
					if ui_layer:
						ui_layer.add_child(overlay)
					else:
						root.add_child(overlay)
					instance = overlay
	if instance:
		instance.visible = not instance.visible
		if instance.visible:
			instance.call_deferred("_refresh_all_content")


static func show_overlay() -> void:
	if instance:
		instance.visible = true
		instance._refresh_all_content()
	elif Engine.get_main_loop():
		toggle()


static func hide_overlay() -> void:
	if instance:
		instance.visible = false


static func is_overlay_visible() -> bool:
	return instance != null and instance.visible


static func is_map_debug_tools_active() -> bool:
	return instance != null and instance.visible


static func toast_map_debug(msg: String) -> void:
	if instance != null:
		instance._toast(msg)
	else:
		print("MapDebug: ", msg)


func _debug_player_country_tag() -> String:
	if is_inside_tree() and typeof(TopInfoBar) != TYPE_NIL:
		var bar := TopInfoBar.find_in_tree(get_tree())
		if bar != null and not bar.player_country_tag.is_empty():
			return bar.player_country_tag
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var tag := str(LeaderManager.get_player_country_tag()).strip_edges()
		if not tag.is_empty():
			return tag
	return "USA"


static func add_section(title: String) -> VBoxContainer:
	if instance == null:
		toggle()  # force creation
	if instance:
		return instance._ensure_section(title)
	return null


func _build_ui() -> void:
	if _main_container != null:
		return  # already built (e.g. early explicit call from static toggle creation path before _ready adds again)
	_apply_panel_size(Vector2(PANEL_WIDTH, PANEL_HEIGHT))

	_main_container = PanelContainer.new()
	_main_container.custom_minimum_size = _panel_size
	_main_container.size = _panel_size
	_main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_main_container)

	_outer_vbox = VBoxContainer.new()
	_outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_outer_vbox.add_theme_constant_override("separation", 6)
	_main_container.add_child(_outer_vbox)

	# Title bar (drag handle)
	_title_bar = HBoxContainer.new()
	_title_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outer_vbox.add_child(_title_bar)

	var title := Label.new()
	title.text = "DEBUG OVERLAY"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_bar.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(func(): visible = false)
	_title_bar.add_child(close_btn)

	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.gui_input.connect(_on_title_drag_input)

	# Section expand/collapse — keep above scroll so it stays visible
	var layout_hbox := HBoxContainer.new()
	layout_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var collapse_all_btn := Button.new()
	collapse_all_btn.text = "Collapse All"
	collapse_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collapse_all_btn.pressed.connect(func():
		for v in _sections.values():
			v.visible = false
	)
	layout_hbox.add_child(collapse_all_btn)
	var expand_all_btn := Button.new()
	expand_all_btn.text = "Expand All"
	expand_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expand_all_btn.pressed.connect(func():
		for v in _sections.values():
			v.visible = true
	)
	layout_hbox.add_child(expand_all_btn)
	_outer_vbox.add_child(layout_hbox)

	# Scrollable tool list — vertical only; content width tracks panel
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_outer_vbox.add_child(_scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content_vbox)

	# Status bar at bottom
	_status_label = Label.new()
	_status_label.text = "F10 toggle · drag title · resize ⤡ corner"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", 11)
	_outer_vbox.add_child(_status_label)

	_create_resize_grip()

	# === BUILT-IN SECTIONS ===

	# 1. Infrastructure Projects (rich debug view for map visuals work)
	var infra_section := _ensure_section("Infrastructure Projects")

	var infra_count_label := Label.new()
	infra_count_label.text = "Active Projects: 0"
	infra_section.add_child(infra_count_label)

	var infra_list := VBoxContainer.new()
	infra_list.add_theme_constant_override("separation", 3)
	infra_section.add_child(infra_list)

	var refresh_btn := Button.new()
	refresh_btn.text = "🔄 Refresh Infra Visuals"
	refresh_btn.pressed.connect(_on_refresh_infra_pressed)
	infra_section.add_child(refresh_btn)

	var force_tick_btn := Button.new()
	force_tick_btn.text = "⏭ Force 1 Day Tick"
	force_tick_btn.pressed.connect(_on_force_day_tick)
	infra_section.add_child(force_tick_btn)

	# Map Infrastructure Layers (toggleable/editable visuals for roads, rails, cities, sites/airfields/ports)
	var layers_label := Label.new()
	layers_label.text = "Map Layers (R/T/C/Y hotkeys or buttons):"
	layers_label.add_theme_font_size_override("font_size", 11)
	infra_section.add_child(layers_label)

	var roads_btn := Button.new()
	roads_btn.text = "🛤️ Toggle Roads"
	roads_btn.pressed.connect(_on_toggle_roads)
	infra_section.add_child(roads_btn)

	var rails_btn := Button.new()
	rails_btn.text = "🚂 Toggle Rails"
	rails_btn.pressed.connect(_on_toggle_rails)
	infra_section.add_child(rails_btn)

	var cities_btn := Button.new()
	cities_btn.text = "🏙 Toggle Cities/Urban"
	cities_btn.pressed.connect(_on_toggle_cities)
	infra_section.add_child(cities_btn)

	var sites_btn := Button.new()
	sites_btn.text = "🛫 Toggle Airfields/Ports (Sites)"
	sites_btn.pressed.connect(_on_toggle_sites)
	infra_section.add_child(sites_btn)

	var refresh_layers_btn := Button.new()
	refresh_layers_btn.text = "🔄 Refresh All Map Layers"
	refresh_layers_btn.pressed.connect(_on_refresh_layers)
	infra_section.add_child(refresh_layers_btn)

	# Extra powerful debug actions for map visual development
	var clear_sab_btn := Button.new()
	clear_sab_btn.text = "🧹 Clear All Sabotage"
	clear_sab_btn.pressed.connect(_on_clear_all_sabotage)
	infra_section.add_child(clear_sab_btn)

	var boost_btn := Button.new()
	boost_btn.text = "🚀 Boost All Projects +25%"
	boost_btn.pressed.connect(_on_boost_all_projects)
	infra_section.add_child(boost_btn)

	var complete_all_btn := Button.new()
	complete_all_btn.text = "✅ Complete All Projects Instantly"
	complete_all_btn.pressed.connect(_on_complete_all_projects)
	infra_section.add_child(complete_all_btn)

	var sabotage_random_btn := Button.new()
	sabotage_random_btn.text = "💣 Sabotage Random Active Project"
	sabotage_random_btn.pressed.connect(_on_sabotage_random_project)
	infra_section.add_child(sabotage_random_btn)

	var spawn_port_btn := Button.new()
	spawn_port_btn.text = "🏗 Spawn Test Port (Special Site)"
	spawn_port_btn.pressed.connect(_on_debug_spawn_port)
	infra_section.add_child(spawn_port_btn)

	var legend_toggle := Button.new()
	legend_toggle.text = "📖 Toggle Map Legend"
	legend_toggle.pressed.connect(_on_toggle_legend)
	infra_section.add_child(legend_toggle)

	# Special Sites quick view
	var special_sites_header := Label.new()
	special_sites_header.text = "Special Sites on Map:"
	special_sites_header.add_theme_font_size_override("font_size", 11)
	infra_section.add_child(special_sites_header)

	# Show current national trade capacity bonus (from TradeManager)
	var player_tag := _debug_player_country_tag()
	if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_national_special_site_trade_capacity_bonus"):
		var bonus := TradeManager.get_national_special_site_trade_capacity_bonus(player_tag)
		var trade_label := Label.new()
		trade_label.text = "National Trade Capacity Bonus: +%d" % int(bonus)
		trade_label.add_theme_font_size_override("font_size", 10)
		trade_label.modulate = Color(0.5, 0.85, 0.6)
		infra_section.add_child(trade_label)

		# Also show total special site count for the player
		if typeof(MapManager) != TYPE_NIL:
			var total_sites := 0
			for pid in MapManager.get_provinces_by_owner(player_tag):
				var p = MapManager.get_province(pid)
				if p: total_sites += p.special_sites.size()
			var count_label := Label.new()
			count_label.text = "Your Special Sites: %d" % total_sites
			count_label.add_theme_font_size_override("font_size", 9)
			infra_section.add_child(count_label)

	var special_sites_list := VBoxContainer.new()
	special_sites_list.name = "SpecialSitesList"
	infra_section.add_child(special_sites_list)

	# Store references
	set_meta("infra_count_label", infra_count_label)
	set_meta("infra_list", infra_list)
	set_meta("special_sites_list", special_sites_list)

	# === Map Generation Pipeline Debug (Phase 1) — only in debug builds ===
	if OS.is_debug_build():
		var mapgen_section := _ensure_section("Map Gen — Phase 1 (Proposed Splits)")
		mapgen_section.modulate = Color(0.85, 0.95, 1.0)

		var proposed_btn := Button.new()
		proposed_btn.text = "🗺️ Toggle Proposed Splits Overlay"
		proposed_btn.pressed.connect(_on_toggle_proposed_splits)
		mapgen_section.add_child(proposed_btn)

		var proposed_hint := Label.new()
		proposed_hint.text = "Loads tools/map_generation/output/phase1_europe/\nShows 120 naval-aware child proposals from current seed."
		proposed_hint.add_theme_font_size_override("font_size", 9)
		proposed_hint.modulate = Color(0.7, 0.82, 0.88)
		mapgen_section.add_child(proposed_hint)

		# Live status label (updated on refresh)
		var proposed_status := Label.new()
		proposed_status.name = "ProposedSplitsStatus"
		proposed_status.text = "Proposed: not loaded"
		proposed_status.add_theme_font_size_override("font_size", 9)
		mapgen_section.add_child(proposed_status)

		set_meta("proposed_splits_status", proposed_status)

		# === Real merge validation (item 2) ===
		var merge_btn := Button.new()
		merge_btn.text = "🔀 Load Phase 1 Merged Test Map (in-memory)"
		merge_btn.pressed.connect(_on_load_phase1_merged_map)
		mapgen_section.add_child(merge_btn)

		var merge_v2_btn := Button.new()
		merge_v2_btn.text = "🔀 Load IMPROVED Splitter v2 (better balance + naval densify)"
		merge_v2_btn.pressed.connect(func(): _on_load_phase1_merged_map(true))
		mapgen_section.add_child(merge_v2_btn)

		# Fast iteration button for splitter development
		var reload_raw_btn := Button.new()
		reload_raw_btn.text = "🔄 Reload Raw Proposed Splits (after editing Python splitter)"
		reload_raw_btn.pressed.connect(_on_reload_raw_proposed)
		mapgen_section.add_child(reload_raw_btn)

		# v3 with improved closest-child adjacency
		var merge_v3_btn := Button.new()
		merge_v3_btn.text = "🔀 Load v3 Closest-Child Wiring (cleanest borders)"
		merge_v3_btn.pressed.connect(func(): _on_load_phase1_merged_map(false, true))
		mapgen_section.add_child(merge_v3_btn)

		var playable_v3_btn := Button.new()
		playable_v3_btn.text = "🎮 Load v3 as Playable Test Map (180 provinces - owners assigned)"
		playable_v3_btn.pressed.connect(func(): _on_load_phase1_merged_map(false, true, true))
		mapgen_section.add_child(playable_v3_btn)

		var test_scenario_btn := Button.new()
		test_scenario_btn.text = "📜 Load Persistent Phase 1 Test Scenario (v6 - 180 provinces, coastal-aware PCA + rich attributes)"
		test_scenario_btn.pressed.connect(_on_load_phase1_test_scenario)
		mapgen_section.add_child(test_scenario_btn)

		var restore_btn := Button.new()
		restore_btn.text = "↩️ Restore Original Map Data"
		restore_btn.pressed.connect(_on_restore_original_map)
		mapgen_section.add_child(restore_btn)

		var merge_hint := Label.new()
		merge_hint.text = "Phase 1 v6: Coastal edge preservation in splitter (extra densify + radial cut bias on long outer arcs) + previous merge polish. Best test map yet."
		merge_hint.add_theme_font_size_override("font_size", 9)
		merge_hint.modulate = Color(0.7, 0.85, 0.75)
		mapgen_section.add_child(merge_hint)

		# === Phase 1 Test Tools ===
		var test_section := _ensure_section("Phase 1 Test Tools")
		test_section.modulate = Color(0.9, 0.88, 1.0)

		var highlight_naval_btn := Button.new()
		highlight_naval_btn.text = "Highlight High-Naval Provinces"
		highlight_naval_btn.pressed.connect(_on_highlight_naval_pressed)
		test_section.add_child(highlight_naval_btn)

		var highlight_chokepoints_btn := Button.new()
		highlight_chokepoints_btn.text = "Highlight Chokepoints / Straits"
		highlight_chokepoints_btn.pressed.connect(_on_highlight_chokepoints_pressed)
		test_section.add_child(highlight_chokepoints_btn)

		var show_subdivision_btn := Button.new()
		show_subdivision_btn.text = "Show Subdivision Candidates"
		show_subdivision_btn.pressed.connect(_on_show_subdivision_pressed)
		test_section.add_child(show_subdivision_btn)

		var reload_test_btn := Button.new()
		reload_test_btn.text = "Reload Phase 1 Test Scenario"
		reload_test_btn.pressed.connect(_on_reload_test_scenario_pressed)
		test_section.add_child(reload_test_btn)

		var print_report_btn := Button.new()
		print_report_btn.text = "Print Test Scenario Report"
		print_report_btn.pressed.connect(_on_print_test_report_pressed)
		test_section.add_child(print_report_btn)

		var conquest_btn := Button.new()
		conquest_btn.text = "⚔️ Cycle Border Demo (unite → split → tags → revert)"
		conquest_btn.pressed.connect(_on_cycle_border_demo)
		test_section.add_child(conquest_btn)

		var revert_cluster_btn := Button.new()
		revert_cluster_btn.text = "↩ Revert Border Demo Cluster"
		revert_cluster_btn.pressed.connect(_on_revert_border_demo)
		test_section.add_child(revert_cluster_btn)

		var combat_test_btn := Button.new()
		combat_test_btn.text = "🗡️ Test Combat (selected province → capture on win)"
		combat_test_btn.pressed.connect(_on_test_combat_capture)
		test_section.add_child(combat_test_btn)

		var ai_assault_btn := Button.new()
		ai_assault_btn.text = "AI Assault Pass (non-player divisions → adjacent enemies)"
		ai_assault_btn.pressed.connect(_on_run_ai_assault_pass)
		test_section.add_child(ai_assault_btn)

		var debug_map_hint := Label.new()
		debug_map_hint.text = "Debug map: Shift+click adjacent = attacker staging; right-click cycles owner (F10 open)"
		debug_map_hint.add_theme_font_size_override("font_size", 9)
		debug_map_hint.modulate = Color(0.65, 0.78, 0.85)
		test_section.add_child(debug_map_hint)

	# === Starter Map Visual Editor (for leveling provinces with images/objects) ===
	# Allows placing/editing objects (cities, airfields, ports, roads, buildings) tied to province areas.
	# Uses data from Python tool (positions, terrain features like hills/swamp/desert).
	# Supports seasons, damage, era/culture variants. Objects placed on the background image.
	# Next: integrate with MapRenderer for permanent visuals, export to JSON for Python roundtrip.
	# Expanded geo (Canaries + NA + Egypt + Suez + Iraq/ME) supported via data tags.
	var visual_editor_section := _ensure_section("Map Visual Editor (Starter)")
	visual_editor_section.modulate = Color(1.0, 0.95, 0.85)

	var editor_status := Label.new()
	editor_status.name = "MapEditorStatus"
	editor_status.text = "Editor: OFF (toggle to enable; use Place buttons or future click-to-place)"
	editor_status.add_theme_font_size_override("font_size", 10)
	visual_editor_section.add_child(editor_status)

	var toggle_editor_btn := Button.new()
	toggle_editor_btn.text = "Toggle Visual Editor"
	toggle_editor_btn.pressed.connect(_on_toggle_map_editor)
	visual_editor_section.add_child(toggle_editor_btn)

	# Prominent terrain toggle for clean view (separate terrain layer decision: YES per HOI4/EU4 reviews - players love clean political for ownership/infra focus + editing; detailed terrain for beauty/combat).
	var terrain_toggle_btn := Button.new()
	terrain_toggle_btn.text = "Toggle Terrain (clean view / no terrain)"
	terrain_toggle_btn.tooltip_text = "Hides the high-res detailed terrain raster (rivers/hills/swamps/desert image) for solid political fills. Great for editing placements precisely or focusing on strategy without visual noise. Weather still works."
	terrain_toggle_btn.pressed.connect(_on_toggle_terrain_layer)
	visual_editor_section.add_child(terrain_toggle_btn)

	var place_city_btn := Button.new()
	place_city_btn.text = "Place City Demo"
	place_city_btn.pressed.connect(_on_place_demo_city)
	visual_editor_section.add_child(place_city_btn)

	var place_airfield_btn := Button.new()
	place_airfield_btn.text = "Place Airfield Demo"
	place_airfield_btn.pressed.connect(_on_place_demo_airfield)
	visual_editor_section.add_child(place_airfield_btn)

	var export_placements_btn := Button.new()
	export_placements_btn.text = "Export Placements"
	export_placements_btn.pressed.connect(_on_export_map_placements)
	visual_editor_section.add_child(export_placements_btn)

	var clear_demo_btn := Button.new()
	clear_demo_btn.text = "Clear Demo Objects"
	clear_demo_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") as Node
		if mr and mr.has_method("clear_editor_demo_objects"):
			mr.call("clear_editor_demo_objects")
		else:
			var cont = get_tree().get_first_node_in_group("map_container")
			if cont:
				var dd = cont.get_node_or_null("DataDrivenObjects")
				if dd: dd.queue_free()
		_toast("Cleared")
		call_deferred("_refresh_placed_list")
	)
	visual_editor_section.add_child(clear_demo_btn)

	var weather_toggle_btn := Button.new()
	weather_toggle_btn.text = "Toggle Weather Layer"
	weather_toggle_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") as Node
		if mr and mr.has_method("_setup_weather_overlay_layer"):
			if mr.has_method("_setup_weather_overlay_layer"):
				mr.call("_setup_weather_overlay_layer")
			var cont = mr.get("container") if mr.get("container") else null
			if cont:
				var wl = cont.get_node_or_null("WeatherOverlayLayer")
				if wl and wl.has_method("toggle"):
					wl.toggle()
					_toast("Weather toggled")
				else:
					_toast("Weather pending")
			else:
				_toast("No container")
	)
	visual_editor_section.add_child(weather_toggle_btn)

	var force_snow_btn := Button.new()
	force_snow_btn.text = "Force Snow"
	force_snow_btn.pressed.connect(func():
		var wm = get_node_or_null("/root/WeatherManager")
		if wm and wm.has_method("simulate_day"):
			wm.simulate_day(1936, 1, 15)
			_toast("Snow advanced")
		else:
			_toast("No WM")
	)
	visual_editor_section.add_child(force_snow_btn)

	var winter_preview_btn := Button.new()
	winter_preview_btn.text = "Winter Preview (high-res snow tint)"
	winter_preview_btn.tooltip_text = "Force snow + ensure terrain layer ON so you see winter on the detailed 8K+ map bg (north heavier). Good for visual QC of seasonal on grand theater image."
	winter_preview_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") as Node
		if mr and mr.has_method("set_show_terrain_layer"):
			mr.call("set_show_terrain_layer", true)
		var wm = get_node_or_null("/root/WeatherManager")
		if wm and wm.has_method("simulate_day"):
			wm.simulate_day(1936, 1, 20)
		_toast("Winter preview on high-res")
	)
	visual_editor_section.add_child(winter_preview_btn)

	# Emergency / helper for the "styled map not the playable layer" issue: forces the high-res grand image as the full underlay + good camera + suppress.
	var force_styled_btn := Button.new()
	force_styled_btn.text = "Force Styled High-Res Map as Playable Base"
	force_styled_btn.tooltip_text = "Re-applies the upscaled grand theater image as full underlay, suppresses any gray/black/ProvinceMap rasters, re-frames camera to a nice view on the large image, ensures low-alpha polys so the detailed style is visible and playable. Use if you see items on gray/white/black instead of the beautiful map."
	force_styled_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") as Node
		if mr:
			if mr.has_method("apply_phase1_europe_background"):
				mr.call("apply_phase1_europe_background")
			if mr.has_method("_fit_background_to_bounds"):
				mr.call("_fit_background_to_bounds")
			if mr.has_method("_suppress_old_background_maps"):
				mr.call("_suppress_old_background_maps")
			# Re-frame camera to good spot on the large image
			var camc := get_tree().get_first_node_in_group("camera_controller") as Node
			if camc and camc.has_method("set_initial_view"):
				camc.call("set_initial_view", Vector2(1800, 650), 2.5, true)
			_toast("Forced high-res styled map as playable base")
		else:
			_toast("No map renderer")
		call_deferred("_refresh_placed_list")
	)
	visual_editor_section.add_child(force_styled_btn)

	var force_blackout_btn := Button.new()
	force_blackout_btn.text = "Cause Blackout"
	force_blackout_btn.pressed.connect(func():
		var wm = get_node_or_null("/root/WeatherManager")
		if wm and wm.has_method("cause_blackout"):
			wm.cause_blackout(999, true)
			_toast("Blackout demo")
	)
	visual_editor_section.add_child(force_blackout_btn)

	var print_naval_btn := Button.new()
	print_naval_btn.text = "Print Naval Stats"
	print_naval_btn.pressed.connect(func():
		var wm = get_node_or_null("/root/WeatherManager")
		if wm:
			print("Naval:", wm.get_naval_mission_effectiveness(999) if wm.has_method("get_naval_mission_effectiveness") else "?")
			print("Carrier:", wm.get_carrier_air_effectiveness(999) if wm.has_method("get_carrier_air_effectiveness") else "?")
			print("Power:", wm.get_power_availability(999) if wm.has_method("get_power_availability") else "?")
		_toast("See console")
	)
	visual_editor_section.add_child(print_naval_btn)

	# Additional place tools for map editing
	var place_port_btn := Button.new()
	place_port_btn.text = "Place Port Demo"
	place_port_btn.pressed.connect(func(): _place_demo_type("port"))
	visual_editor_section.add_child(place_port_btn)

	var place_factory_btn := Button.new()
	place_factory_btn.text = "Place Factory Demo"
	place_factory_btn.pressed.connect(func(): _place_demo_type("factory"))
	visual_editor_section.add_child(place_factory_btn)

	# Placed objects list + delete for user to curate/edit the high-res map placements (roundtrips via export/load)
	var placed_header := Label.new()
	placed_header.text = "Placed Objects (LMB places at high zoom; use list to delete/curate for python roundtrip):"
	placed_header.add_theme_font_size_override("font_size", 10)
	placed_header.modulate = Color(0.85, 0.9, 0.8)
	visual_editor_section.add_child(placed_header)

	_placed_list_vbox = VBoxContainer.new()
	_placed_list_vbox.add_theme_constant_override("separation", 1)
	visual_editor_section.add_child(_placed_list_vbox)

	var refresh_placed_btn := Button.new()
	refresh_placed_btn.text = "🔄 Refresh Placed List"
	refresh_placed_btn.pressed.connect(_refresh_placed_list)
	visual_editor_section.add_child(refresh_placed_btn)

	var load_placed_btn := Button.new()
	load_placed_btn.text = "Load Placements (JSON roundtrip)"
	load_placed_btn.tooltip_text = "Load from user://map_editor_placements.json (or export first then edit). Supports python tool roundtrip for curating 400-prov grand theater placements on the upscaled image."
	load_placed_btn.pressed.connect(_on_load_map_placements)
	visual_editor_section.add_child(load_placed_btn)

	var export_file_btn := Button.new()
	export_file_btn.text = "Export Placements to user:// JSON"
	export_file_btn.pressed.connect(_on_export_map_placements_to_file)
	visual_editor_section.add_child(export_file_btn)

	var editor_hint := Label.new()
	editor_hint.text = "Use high-res ultra map (auto 8K+). Toggle terrain for clean edit view. LMB while editor ON places precisely via camera inverse on terrain features. Delete from list. Export/Load for python leveling. Snow tints the raster; desert/hills/swamp infra ok."
	editor_hint.add_theme_font_size_override("font_size", 9)
	editor_hint.modulate = Color(0.7, 0.7, 0.6)
	visual_editor_section.add_child(editor_hint)

	# === In-Game Province Editor (for blank map design + modding) ===
	# Preferred approach per design session: draw/edit provinces directly on a clean parchment base map.
	# Supports point-by-point polygons, live preview, basic attributes, smart suggestions (future), and export to the layered JSON schema.
	# See docs/PROVINCE_EDITOR_IN_GAME_DESIGN.md
	var province_editor_section := _ensure_section("Province Border Editor (In-Game)")
	province_editor_section.modulate = Color(0.9, 1.0, 0.85)

	var prov_status := Label.new()
	prov_status.name = "ProvinceEditorStatus"
	prov_status.text = "Province Editor: OFF — toggle to draw provinces on the clean base map"
	prov_status.add_theme_font_size_override("font_size", 10)
	province_editor_section.add_child(prov_status)

	var toggle_prov_editor_btn := Button.new()
	toggle_prov_editor_btn.text = "Toggle Province Editor"
	toggle_prov_editor_btn.pressed.connect(_on_toggle_province_editor)
	province_editor_section.add_child(toggle_prov_editor_btn)

	var clean_base_btn := Button.new()
	clean_base_btn.text = "Switch to Clean Base Map (for editing)"
	clean_base_btn.tooltip_text = "Loads a clean parchment-style base (rivers/mountains visible, no political overlays) ideal for drawing new provinces. Uses the high-res grand as fallback."
	clean_base_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") as Node
		if mr and mr.has_method("set_clean_base_map"):
			mr.call("set_clean_base_map")
			_toast("Clean base map activated for province editing")
	)
	province_editor_section.add_child(clean_base_btn)

	var finish_prov_btn := Button.new()
	finish_prov_btn.text = "Finish Current Province (or Right-Click)"
	finish_prov_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe: pe._finish_current_province()
	)
	province_editor_section.add_child(finish_prov_btn)

	var export_prov_btn := Button.new()
	export_prov_btn.text = "Export Editor Provinces to user://"
	export_prov_btn.pressed.connect(_on_export_editor_provinces)
	province_editor_section.add_child(export_prov_btn)

	var refresh_prov_list_btn := Button.new()
	refresh_prov_list_btn.text = "Refresh Edited Provinces List"
	refresh_prov_list_btn.pressed.connect(_refresh_edited_provinces_list)
	province_editor_section.add_child(refresh_prov_list_btn)

	var apply_temp_btn := Button.new()
	apply_temp_btn.text = "Apply Temp Provinces to Map (test)"
	apply_temp_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("apply_temporary_to_map"):
			pe.call("apply_temporary_to_map")
			_toast("Temp provinces applied for testing (queries/preview)")
	)
	province_editor_section.add_child(apply_temp_btn)

	var add_variant_btn := Button.new()
	add_variant_btn.text = "Add Demo 1936 Variant (to first edited)"
	add_variant_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("add_historical_variant") and pe.has_method("get_edited_provinces"):
			var edited = pe.call("get_edited_provinces")
			if edited:
				var keys = edited.keys()
				var sid = keys[0] if keys.size() > 0 else -1
				if sid >= 0:
					pe.call("add_historical_variant", sid, 1936, {"owner_tag": "GER", "development_level": 2})
					_toast("Demo 1936 variant added (check export JSON)")
	)
	province_editor_section.add_child(add_variant_btn)

	var snap_btn := Button.new()
	snap_btn.text = "Toggle Snap to Rivers/Features"
	snap_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("toggle_snap"):
			# Toggle
			pe.snap_enabled = not pe.snap_enabled
			pe.toggle_snap(pe.snap_enabled)
			_toast("Snap " + ("ON (features/rivers proxy)" if pe.snap_enabled else "OFF - full manual control"))
	)
	province_editor_section.add_child(snap_btn)

	var grid_snap_btn := Button.new()
	grid_snap_btn.text = "Toggle Grid Snap (50u)"
	grid_snap_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe:
			pe.grid_snap_enabled = not pe.grid_snap_enabled
			_toast("Grid snap " + ("ON" if pe.grid_snap_enabled else "OFF"))
	)
	province_editor_section.add_child(grid_snap_btn)

	var pop_snap_btn := Button.new()
	pop_snap_btn.text = "Toggle Pop/Terrain Snap"
	pop_snap_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe:
			pe.pop_snap_enabled = not pe.pop_snap_enabled
			_toast("Pop snap " + ("ON (high pop/strategic)" if pe.pop_snap_enabled else "OFF"))
	)
	province_editor_section.add_child(pop_snap_btn)

	var river_snap_btn := Button.new()
	river_snap_btn.text = "Toggle River/Terrain Boundary Snap"
	river_snap_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe:
			pe.river_snap_enabled = not pe.river_snap_enabled
			_toast("River snap " + ("ON (rivers/coasts/terrain edges)" if pe.river_snap_enabled else "OFF"))
	)
	province_editor_section.add_child(river_snap_btn)

	var reload_rivers_btn := Button.new()
	reload_rivers_btn.text = "Reload Rivers for Snap (from data or editor)"
	reload_rivers_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("load_rivers_for_snap"):
			pe.call("load_rivers_for_snap", "user://editor_provinces/rivers.json")  # prefer editor export if present
			_toast("Rivers reloaded for snap")
	)
	province_editor_section.add_child(reload_rivers_btn)

	var preview_stats_btn := Button.new()
	preview_stats_btn.text = "Preview Stats (movement etc) for Edited"
	preview_stats_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("apply_temporary_to_map"):
			# Apply will print previews; or call a dedicated if added
			pe.call("apply_temporary_to_map")
			_toast("Stats previewed in console (override by re-editing)")
	)
	province_editor_section.add_child(preview_stats_btn)

	var clear_all_btn := Button.new()
	clear_all_btn.text = "Clear All Editor Provinces"
	clear_all_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("get_edited_provinces"):
			var edited = pe.call("get_edited_provinces")
			for tid in edited.keys():
				if pe.has_method("delete_edited_province"):
					pe.call("delete_edited_province", tid)
		_refresh_edited_provinces_list()
		_toast("Cleared all editor provinces")
	)
	province_editor_section.add_child(clear_all_btn)

	# Historical borders layer toggles (1918/1936/2026) to help with province border decisions in editor.
	# Shows approximate country borders for each era as visual aid (human can draw provinces to match or override).
	var borders_label := Label.new()
	borders_label.text = "Historical Borders (toggle for province decisions):"
	borders_label.add_theme_font_size_override("font_size", 10)
	province_editor_section.add_child(borders_label)

	var b1918 := Button.new()
	b1918.text = "1918 Borders"
	b1918.pressed.connect(func(): _toggle_historical_borders("1918"))
	province_editor_section.add_child(b1918)

	var b1936 := Button.new()
	b1936.text = "1936 Borders"
	b1936.pressed.connect(func(): _toggle_historical_borders("1936"))
	province_editor_section.add_child(b1936)

	var b2026 := Button.new()
	b2026.text = "2026 Borders"
	b2026.pressed.connect(func(): _toggle_historical_borders("2026"))
	province_editor_section.add_child(b2026)

	var clear_b := Button.new()
	clear_b.text = "Clear Borders Layer"
	clear_b.pressed.connect(func(): _clear_historical_borders())
	province_editor_section.add_child(clear_b)

	var conflict_toggle_btn := Button.new()
	conflict_toggle_btn.text = "Toggle Conflict Highlights Layer"
	conflict_toggle_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("highlight_conflicts"):
			pe.call("highlight_conflicts")  # global
			_toast("Conflict layer toggled (red overlays for overlaps)")
	)
	province_editor_section.add_child(conflict_toggle_btn)

	var save_btn := Button.new()
	save_btn.text = "Save Editor Session (persistent)"
	save_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("save_session"):
			pe.call("save_session")
			_toast("Editor session saved (persistent)")
	)
	province_editor_section.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load Editor Session"
	load_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("load_session"):
			pe.call("load_session")
			_refresh_edited_provinces_list()
			_toast("Editor session loaded")
	)
	province_editor_section.add_child(load_btn)

	var suggest_btn := Button.new()
	suggest_btn.text = "Auto-suggest Full Border (snap + continue)"
	suggest_btn.pressed.connect(func():
		var pe := _get_province_editor()
		if pe and pe.has_method("auto_suggest_border"):
			pe.call("auto_suggest_border", 4)
			_toast("Auto-suggested border continuation (drag to refine/override)")
	)
	province_editor_section.add_child(suggest_btn)

	_edited_provinces_list_vbox = VBoxContainer.new()
	_edited_provinces_list_vbox.add_theme_constant_override("separation", 2)
	province_editor_section.add_child(_edited_provinces_list_vbox)

	var prov_hint := Label.new()
	prov_hint.text = "LMB = add vertex or drag (after select). Right-click = finish. Select from list to edit existing. Clean base map recommended. See design doc for full features."
	prov_hint.add_theme_font_size_override("font_size", 9)
	prov_hint.modulate = Color(0.6, 0.7, 0.6)
	province_editor_section.add_child(prov_hint)

	# Quick access to Aircraft Design System skeleton (range / maintenance / prototyping)
	var air_section := _ensure_section("Aircraft Prototyping (Skeleton)")
	var air_btn := Button.new()
	air_btn.text = "Init AircraftDesignSystem + Demo Prototype"
	air_btn.pressed.connect(func():
		var ads := _get_or_create_aircraft_design_system()
		if ads:
			var fake_template: Dictionary = {"id": "demo_p51_early"}
			var st: Dictionary = ads.get_or_create_design_state("demo_p51_prototype", fake_template)
			ads.add_combat_experience("demo_p51_prototype", 450.0)
			_toast("AircraftDesignSystem ready")
			_update_air_status()
	)
	air_section.add_child(air_btn)

	var air_status_btn := Button.new()
	air_status_btn.text = "Refresh Aircraft Status"
	air_status_btn.pressed.connect(_update_air_status)
	air_section.add_child(air_status_btn)

	var link_demo_btn := Button.new()
	link_demo_btn.text = "Link Demo Air Design (for formation effects)"
	link_demo_btn.pressed.connect(func():
		var ads := _get_or_create_aircraft_design_system()
		if ads:
			ads.get_or_create_design_state("demo_p51_prototype", {"id": "demo_p51_early"})
			_toast("Demo design linked - ADS modifiers now active for air")
			_update_air_status()
	)
	air_section.add_child(link_demo_btn)

	var profile_demo_btn := Button.new()
	profile_demo_btn.text = "Demo AirMissionProfile (range + modifier)"
	profile_demo_btn.pressed.connect(func():
		var AirMissionProfileScript = load("res://scripts/air/AirMissionProfile.gd") as GDScript
		var profile = AirMissionProfileScript.new("demo_air_wing", "demo_p51_prototype", "FERRY_LONG_RANGE")
		if profile:
			var eff_range = profile.get_effective_range(1200.0)
			var mod = profile.get_mission_modifier()
			print("AirMissionProfile demo: eff_range=", eff_range, " mission_mod=", mod, " payload_mult=", profile.get_payload_multiplier())
			_toast("Profile: range " + str(int(eff_range)) + " mod " + str(mod))
	)
	air_section.add_child(profile_demo_btn)

	var maturity_details_btn := Button.new()
	maturity_details_btn.text = "Show Rich Maturity Details (console + future panel)"
	maturity_details_btn.pressed.connect(func():
		var ads := _get_or_create_aircraft_design_system()
		if ads and ads.has_method("get_or_create_design_state"):
			var st = ads.get_or_create_design_state("demo_p51_prototype", {"id": "demo_p51_early"})
			print("=== Rich Aircraft Maturity ===")
			print("Maturity: ", st.get("maturity"))
			print("Reliability offset: ", st.get("reliability_offset"))
			print("Maint mult: ", st.get("maintenance_multiplier"))
			print("Range mult: ", st.get("range_multiplier"))
			print("Combat XP: ", st.get("combat_xp"))
			print("Agents assigned: ", st.get("agent_assigned_ids"))
			print("Notes: ", st.get("historical_notes", "N/A"))
			_toast("Maturity details in console (extend to dedicated panel)")
	)
	air_section.add_child(maturity_details_btn)

	_air_status_label = Label.new()
	_air_status_label.text = "Aircraft Status: Init to start"
	_air_status_label.add_theme_font_size_override("font_size", 9)
	_air_status_label.modulate = Color(0.8, 0.9, 1.0)
	air_section.add_child(_air_status_label)

	var air_hint := Label.new()
	air_hint.text = "Full design in docs/AIRCRAFT_RANGE_MAINTENANCE_PROTOTYPING_DESIGN.md. Builds on existing ReliabilityCalculator + Agent + Special Sites + Tech. Use buttons to iterate prototype."
	air_hint.add_theme_font_size_override("font_size", 9)
	air_section.add_child(air_hint)

	# 2. Time & Simulation
	var time_section := _ensure_section("Time & Simulation")
	var time_label := Label.new()
	time_label.name = "TimeInfo"
	time_label.text = "Date: --"
	time_section.add_child(time_label)

	var advance_btn := Button.new()
	advance_btn.text = "Force +1 Day Tick"
	advance_btn.pressed.connect(_on_force_day_tick)
	time_section.add_child(advance_btn)

	# 3. Quick Actions
	var actions := _ensure_section("Quick Actions")
	var clear_sab := Button.new()
	clear_sab.text = "Clear All Sabotage Effects (Map)"
	clear_sab.pressed.connect(_on_clear_all_sabotage)
	actions.add_child(clear_sab)

	var dump_btn := Button.new()
	dump_btn.text = "Dump Manager Status to Console"
	dump_btn.pressed.connect(_on_dump_status)
	actions.add_child(dump_btn)

	# Footer hint
	var hint := Label.new()
	hint.text = "This panel is only available in debug builds."
	hint.modulate = Color(0.6, 0.6, 0.7)
	_content_vbox.add_child(hint)


func _ensure_section(title: String) -> VBoxContainer:
	if _sections.has(title):
		return _sections[title]

	var section_vbox := VBoxContainer.new()
	section_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_vbox.add_theme_constant_override("separation", 2)
	_content_vbox.add_child(section_vbox)

	var header_hbox := HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_vbox.add_child(header_hbox)

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header)

	var collapse_btn := Button.new()
	collapse_btn.text = "[-]"
	collapse_btn.custom_minimum_size = Vector2(32, 22)
	collapse_btn.add_theme_font_size_override("font_size", 10)
	header_hbox.add_child(collapse_btn)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 4)
	section_vbox.add_child(content_vbox)

	var collapsed := false
	collapse_btn.pressed.connect(func():
		collapsed = not collapsed
		content_vbox.visible = not collapsed
		collapse_btn.text = "[+]" if collapsed else "[-]"
	)

	_sections[title] = content_vbox
	return content_vbox


func _apply_theme() -> void:
	if typeof(RetrowaveTheme) == TYPE_NIL:
		return

	RetrowaveTheme.style_detail_panel(_main_container)
	_main_container.modulate = Color(1, 1, 1, 0.95)  # slightly transparent

	for child in _content_vbox.get_children():
		if child is Label:
			RetrowaveTheme.style_body_label(child)
		elif child is Button:
			RetrowaveTheme.style_secondary_button(child)


func _position_default() -> void:
	var vp := Vector2(1280, 720)
	if get_viewport():
		vp = get_viewport_rect().size
	global_position = Vector2(vp.x - _panel_size.x - 24, 72)
	_update_resize_grip_position()
	_clamp_panel_to_screen()


func _clamp_panel_to_screen() -> void:
	if not is_inside_tree() or not get_viewport():
		return
	var vp := get_viewport_rect().size
	var w := _panel_size.x
	var h := _panel_size.y
	global_position.x = clampf(global_position.x, 8.0, maxf(8.0, vp.x - w - 8.0))
	global_position.y = clampf(global_position.y, 8.0, maxf(8.0, vp.y - h - 8.0))
	_update_resize_grip_position()


func _apply_panel_size(new_size: Vector2) -> void:
	_panel_size = Vector2(
		clampf(new_size.x, MIN_PANEL_SIZE.x, MAX_PANEL_SIZE.x),
		clampf(new_size.y, MIN_PANEL_SIZE.y, MAX_PANEL_SIZE.y),
	)
	custom_minimum_size = _panel_size
	size = _panel_size
	if _main_container:
		_main_container.custom_minimum_size = _panel_size
		_main_container.size = _panel_size
	call_deferred("_sync_content_width")
	_update_resize_grip_position()


func _sync_content_width() -> void:
	if _scroll == null or _content_vbox == null:
		return
	var w := maxi(300, int(_scroll.size.x) - 16)
	_content_vbox.custom_minimum_size.x = w


func _create_resize_grip() -> void:
	if _resize_grip != null and is_instance_valid(_resize_grip):
		return
	_resize_grip = Panel.new()
	_resize_grip.name = "ResizeGrip"
	_resize_grip.custom_minimum_size = Vector2(22, 22)
	_resize_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_grip.tooltip_text = "Drag to resize the debug panel"
	var grip_label := Label.new()
	grip_label.text = "⤡"
	grip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grip_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resize_grip.add_child(grip_label)
	_resize_grip.gui_input.connect(_on_resize_grip_input)
	add_child(_resize_grip)
	_update_resize_grip_position()


func _update_resize_grip_position() -> void:
	if _resize_grip == null:
		return
	_resize_grip.position = _panel_size - Vector2(22, 22)


func _on_resize_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_resizing = true
				_resize_start_mouse = get_global_mouse_position()
				_resize_start_size = _panel_size
			else:
				_resizing = false
				_clamp_panel_to_screen()
	elif event is InputEventMouseMotion and _resizing:
		var delta := get_global_mouse_position() - _resize_start_mouse
		_apply_panel_size(_resize_start_size + delta)
		_clamp_panel_to_screen()


func _style_debug_content() -> void:
	if not _content_vbox:
		return
	_style_control_recursive(_content_vbox)


func _style_control_recursive(node: Node) -> void:
	if node is Button:
		var btn := node as Button
		btn.add_theme_font_size_override("font_size", 13)
		btn.clip_text = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.x = 0
	elif node is Label:
		var lbl := node as Label
		if lbl.autowrap_mode == TextServer.AUTOWRAP_OFF:
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if lbl.get_theme_font_size("font_size") <= 0:
			lbl.add_theme_font_size_override("font_size", 12)
	elif node is VBoxContainer or node is HBoxContainer:
		(node as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in node.get_children():
		_style_control_recursive(child)

func _on_title_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_panel_to_screen()


func _on_visibility_changed() -> void:
	if visible:
		call_deferred("_sync_content_width")
		call_deferred("_refresh_all_content")


func _refresh_all_content() -> void:
	_last_refresh_time = Time.get_unix_time_from_system()
	_refresh_infrastructure_section()
	_refresh_time_section()
	_refresh_proposed_status()
	_update_status()
	_style_debug_content()  # re-apply readable styling to dynamically added items
	call_deferred("_refresh_placed_list")  # keep editor list fresh when debug reopens
	call_deferred("_refresh_edited_provinces_list")
	_update_air_status()  # refresh aircraft tracker


func _refresh_infrastructure_section():
	if not has_meta("infra_count_label") or not has_meta("infra_list"):
		# Meta not yet set (build_ui may race on first menu->debug toggle or creation path); skip safely.
		# The infrastructure section will populate on next refresh after _build_ui runs set_meta.
		return
	if not is_inside_tree():
		call_deferred("_refresh_infrastructure_section")
		return
	var count_label := get_meta("infra_count_label") as Label
	var list := get_meta("infra_list") as VBoxContainer
	if count_label == null or list == null:
		return

	for child in list.get_children():
		child.queue_free()

	var manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
	if not manager:
		count_label.text = "Active Projects: (Manager not found)"
		return

	if not manager.has_method("get_all_active_projects"):
		count_label.text = "Active Projects: (get_all_active_projects missing)"
		return

	var active: Array = manager.get_all_active_projects()
	count_label.text = "Active Projects: %d" % active.size()

	for proj in active:
		var line := Label.new()
		var status := "🚧 %s → Lv.%d  %d%% (ETA %dd)" % [
			proj.get("province_name", proj.get("province_id", "?")),
			int(proj.get("target_level", 0)),
			int(proj.get("progress_percent", 0)),
			int(proj.get("eta_days", 0))
		]
		if bool(proj.get("is_sabotaged", false)):
			status = "⚠️ " + status + " [SABOTAGED]"
			line.modulate = Color(1.0, 0.65, 0.35)

		line.text = status
		line.add_theme_font_size_override("font_size", 11)
		list.add_child(line)

	# Refresh Special Sites list
	var ss_list := get_meta("special_sites_list") as VBoxContainer
	if ss_list:
		for child in ss_list.get_children():
			child.queue_free()
		if typeof(MapManager) != TYPE_NIL:
			for pid in MapManager.get_all_provinces().keys():
				var p := MapManager.get_province(int(pid))
				if p and p.special_sites.size() > 0:
					for site in p.special_sites:
						var line := Label.new()
						var state := "✓" if site.is_completed() else "🚧" if site.is_under_construction() else "⚠"
						line.text = "  %s %s (P%d)" % [state, site.id, int(pid)]
						line.add_theme_font_size_override("font_size", 10)
						ss_list.add_child(line)


func _refresh_time_section() -> void:
	var time_label := _content_vbox.find_child("TimeInfo", true, false) as Label
	if time_label == null or typeof(TimeManager) == TYPE_NIL:
		return

	var date := TimeManager.get_current_date() if TimeManager.has_method("get_current_date") else {}
	var txt := "Date: %04d-%02d-%02d" % [
		date.get("year", 0),
		date.get("month", 0),
		date.get("day", 0)
	]
	time_label.text = txt


func _update_status() -> void:
	if _status_label:
		_status_label.text = "Last refreshed: %s  •  F10 / Ctrl+Shift+R to toggle" % Time.get_datetime_string_from_unix_time(int(_last_refresh_time))


func _refresh_proposed_status(overlay: Node = null):
	var status_label := get_meta("proposed_splits_status") as Label
	if status_label == null:
		return
	if not is_inside_tree() or get_tree() == null:
		call_deferred("_refresh_proposed_status", overlay)
		return
	if overlay == null:
		overlay = get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay == null:
		status_label.text = "Proposed: overlay not found"
		return

	var loaded: bool = false
	var count: int = 0
	var showing: bool = false

	if overlay is InfrastructureOverlayLayer:
		var layer := overlay as InfrastructureOverlayLayer
		loaded = layer.proposed_data_loaded
		count = layer.proposed_children.size()
		showing = layer.show_proposed_splits
	elif "proposed_data_loaded" in overlay:
		loaded = bool(overlay.proposed_data_loaded)
		if "proposed_children" in overlay and overlay.proposed_children is Array:
			count = (overlay.proposed_children as Array).size()
		if "show_proposed_splits" in overlay:
			showing = bool(overlay.show_proposed_splits)

	if showing:
		status_label.text = "Proposed: %d children  •  VISIBLE (cyan)" % count
		status_label.modulate = Color(0.4, 0.95, 0.85)
	else:
		status_label.text = "Proposed: %d loaded  •  hidden" % count if loaded else "Proposed: not loaded (debug only)"
		status_label.modulate = Color(0.7, 0.8, 0.85)


func _on_refresh_infra_pressed():
	var manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
	if manager and manager.has_method("refresh_all_project_visuals"):
		manager.refresh_all_project_visuals()

	# Also refresh the dedicated map visual layer if present
	var overlay := get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("force_full_refresh"):
		overlay.force_full_refresh()

	_refresh_infrastructure_section()
	_refresh_proposed_status(overlay)
	_toast("Infra visuals refreshed")


func _on_force_day_tick() -> void:
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("advance_one_day"):
		TimeManager.advance_one_day()
		_toast("Forced +1 day tick")
		_refresh_time_section()
	else:
		_toast("TimeManager.advance_one_day() not available")


func _on_toggle_roads():
	var overlay := get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("toggle_roads"):
		overlay.toggle_roads()
		_toast("Toggled Roads layer")
	else:
		_toast("InfrastructureOverlayLayer not found")

func _on_toggle_rails():
	var overlay := get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("toggle_rails"):
		overlay.toggle_rails()
		_toast("Toggled Rails layer")
	else:
		_toast("InfrastructureOverlayLayer not found")

func _on_toggle_cities():
	var overlay := get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("toggle_cities"):
		overlay.toggle_cities()
		_toast("Toggled Cities/Urban layer")
	else:
		_toast("InfrastructureOverlayLayer not found")

func _on_toggle_sites():
	var overlay := get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("toggle_sites"):
		overlay.toggle_sites()
		_toast("Toggled Airfields/Ports/Sites layer")
	else:
		_toast("InfrastructureOverlayLayer not found")

func _on_refresh_layers():
	var overlay := get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("force_full_refresh"):
		overlay.force_full_refresh()
		_toast("Refreshed all map layers (roads/rails/cities)")


func _on_boost_all_projects():
	var manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
	if manager and manager.has_method("active_projects"):
		for pid in manager.active_projects.keys():
			var proj: Variant = manager.active_projects[pid]
			proj.progress = clampf(proj.progress + 25.0, 0.0, 100.0)

	_refresh_infrastructure_section()
	_toast("All projects boosted +25%")


func _on_complete_all_projects():
	var manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
	if manager and manager.has_method("active_projects"):
		for pid in manager.active_projects.keys():
			var proj: Variant = manager.active_projects[pid]
			proj.progress = 100.0
			# Trigger completion logic if available
			if manager.has_method("complete_project_for_debug"):
				manager.complete_project_for_debug(int(pid))

	_refresh_infrastructure_section()
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		for pid in (manager.active_projects.keys() if manager else []):
			MapManager.notify_province_changed(int(pid), "infrastructure_project")
	_toast("All projects forced to completion")


func _on_sabotage_random_project():
	var manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
	if not manager or not manager.has_method("active_projects"):
		return

	var keys = manager.active_projects.keys()
	if keys.is_empty():
		_toast("No active projects to sabotage")
		return

	var random_pid = keys[randi() % keys.size()]
	var proj: Variant = manager.active_projects[random_pid]
	proj.modifiers["sabotage"] = -0.8   # strong sabotage

	_refresh_infrastructure_section()
	if typeof(MapManager) != TYPE_NIL:
		MapManager.notify_province_changed(int(random_pid), "infrastructure_project")
	_toast("Sabotaged random project in province " + str(random_pid))


func _on_debug_spawn_port():
	var selected := -1
	# Try to use currently selected province from MapRenderer if available
	var mr: MapRenderer = get_tree().get_first_node_in_group("map_renderer") as MapRenderer
	if mr != null:
		selected = mr.selected_province_id

	if selected < 0:
		# Fallback: use first province owned by player
		if typeof(MapManager) != TYPE_NIL:
			for pid in MapManager.get_all_provinces().keys():
				var p = MapManager.get_province(int(pid))
				if p and p.owner_tag == "USA":
					selected = int(pid)
					break

	if selected >= 0:
		if typeof(InfrastructureDevelopmentManager) != TYPE_NIL and InfrastructureDevelopmentManager.has_method("debug_start_special_site_project"):
			InfrastructureDevelopmentManager.debug_start_special_site_project(selected, "port_tier_2")
		elif typeof(InfrastructureDevelopmentManager) != TYPE_NIL and InfrastructureDevelopmentManager.has_method("debug_spawn_special_site"):
			InfrastructureDevelopmentManager.debug_spawn_special_site(selected, "port_tier_2")
		_refresh_infrastructure_section()
		_toast("Started special site project (or instant spawn)")
	else:
		_toast("No suitable province found for debug spawn")


func _on_toggle_legend():
	var overlay = get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("toggle_legend"):
		overlay.toggle_legend()
		_toast("Toggled Infrastructure Legend")
	else:
		_toast("InfrastructureOverlayLayer not found or has no legend support")


func _on_toggle_proposed_splits():
	var overlay = get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("toggle_proposed_splits"):
		overlay.toggle_proposed_splits()
		_toast("Toggled Phase 1 Proposed Splits")
		_refresh_proposed_status(overlay)
	else:
		_toast("InfrastructureOverlayLayer not found (proposed splits unavailable)")


func _on_clear_all_sabotage() -> void:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
		var provinces: Dictionary = MapManager.get_all_provinces()
		var cleared := 0
		for pid in provinces.keys():
			if typeof(SupplyManager) != TYPE_NIL:
				var depot = SupplyManager.depot_states.get(int(pid))
				if depot and "sabotage_level" in depot:
					depot.sabotage_level = 0.0
					cleared += 1
			if typeof(AgentManager) != TYPE_NIL and AgentManager.has_method("networks"):
				if int(pid) in AgentManager.networks:
					# Soft clear by marking inactive if possible
					pass
		_toast("Cleared sabotage on %d provinces" % cleared)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
			for pid in provinces.keys():
				MapManager.notify_province_changed(int(pid), "effects")
	else:
		_toast("Could not clear sabotage (managers not ready)")


func _on_dump_status() -> void:
	print("\n=== DEBUG OVERLAY DUMP ===")
	print("Time: ", TimeManager.get_current_date() if typeof(TimeManager) != TYPE_NIL else "N/A")

	if typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		print("Infra Projects: ", InfrastructureDevelopmentManager.active_projects.size() if "active_projects" in InfrastructureDevelopmentManager else "N/A")

	if typeof(SaveLoadManager) != TYPE_NIL:
		print("Last save path: ", SaveLoadManager._last_save_path if "_last_save_path" in SaveLoadManager else "N/A")

	print("===========================\n")
	_toast("Status dumped to console (F12 to open Godot console)")


func _toast(msg: String) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(msg, 2.0)
	else:
		print("DebugOverlay: ", msg)


# =============================================================================
# Phase 1 Map Merge Hot-Load (Item 2 - Real Merge Validation)
# =============================================================================

const PHASE1_MERGED_BASE := "tools/map_generation/output/phase1_europe/merged_test_map/"

func _on_load_phase1_merged_map(use_improved_v2: bool = false, use_v3_closest: bool = false, playable_test: bool = false):
	if not OS.is_debug_build():
		_toast("Phase 1 merge load is debug-only")
		return

	var label := "v3 as Playable Test Map (180 provinces)" if playable_test else ("v3 Closest-Child Wiring (cleanest borders)" if use_v3_closest else ("IMPROVED Splitter v2 (better balance + naval densify)" if use_improved_v2 else "Phase 1 merged test map (180 provinces)"))
	_toast("Loading " + label + "...")

	var base := PHASE1_MERGED_BASE
	if use_v3_closest or playable_test:
		base = "tools/map_generation/output/phase1_europe/merged_v3_closest_wiring/"
	elif use_improved_v2:
		base = "tools/map_generation/output/phase1_europe/merged_improved_v2/"

	var manifest_path := base + "manifest.json"
	var geo_path := base + "provinces_geometry.json"
	var adj_path := base + "province_adjacency.json"
	var terrain_path := base + "province_terrain_layer.json"
	var res_path := base + "province_resources_layer.json"
	var eco_path := base + "province_economy_layer.json"

	# Try several dev locations
	var candidates := [
		base,
		"res://" + base,
		"../" + base,
		"../../" + base,
	]

	var found_base := ""
	for c in candidates:
		if FileAccess.file_exists(c + "manifest.json"):
			found_base = c
			break

	if found_base == "":
		_toast("Could not find merged test map. Run the Python apply_phase1_merge.py first.")
		return

	# Load all pieces
	var manifest := _load_json_dict(found_base + "manifest.json")
	var geo_data := _load_json_dict(found_base + "provinces_geometry.json")
	var adj_data := _load_json_dict(found_base + "province_adjacency.json")
	var terrain_data := _load_json_dict(found_base + "province_terrain_layer.json")
	var res_data := _load_json_dict(found_base + "province_resources_layer.json")
	var eco_data := _load_json_dict(found_base + "province_economy_layer.json")

	# Build AdjacencySystem in memory
	var AdjSys := preload("res://scripts/data/AdjacencySystem.gd")
	var adj_sys := AdjSys.new()
	adj_sys.load_from_dict(adj_data)

	# Build lightweight Province dict from the merged geometry + layers
	var new_provinces: Dictionary = {}
	var geo_entries: Array = geo_data.get("provinces", [])
	for entry in geo_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pid := int(entry.get("id", 0))
		if pid <= 0:
			continue

		var p: Province = Province.new()
		p.id = pid
		p.name = "Child " + str(pid) if entry.has("parent_id") else ("Province " + str(pid))
		p.terrain = "plains"
		p.is_sea = false

		# Pull attributes from the merged layers when available
		var terrain_by_id: Dictionary = terrain_data.get("provinces", {}) as Dictionary
		var tdata: Dictionary = terrain_by_id.get(str(pid), {}) as Dictionary
		if tdata.has("terrain"):
			p.terrain = str(tdata["terrain"])

		var eco_by_id: Dictionary = eco_data.get("provinces", {}) as Dictionary
		var edata: Dictionary = eco_by_id.get(str(pid), {}) as Dictionary
		if edata.has("population"):
			p.population = int(edata["population"])
		if edata.has("infrastructure"):
			p.infrastructure = int(edata["infrastructure"])
		if edata.has("development_level"):
			p.development_level = int(edata["development_level"])

		var res_by_id: Dictionary = res_data.get("provinces", {}) as Dictionary
		var rdata: Dictionary = res_by_id.get(str(pid), {}) as Dictionary
		if rdata.has("resources"):
			p.resources = rdata["resources"].duplicate(true)

		# Minimal geometry attachment (MapRenderer / overlays will use the geometry dict too)
		new_provinces[pid] = p

	# Build geometry dict in the shape MapManager expects
	var new_geometry: Dictionary = {}
	for entry in geo_entries:
		var pid := int(entry.get("id", 0))
		if pid > 0:
			new_geometry[pid] = entry

	# Countries - keep whatever the current map has (we don't touch ownership for this visual test)
	var current_countries := {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_country"):
		# We can't easily enumerate, so we leave countries empty and let the game keep previous ownership
		pass

	# Assign test owners for playable mode (simple demo assignment for validation)
	if playable_test:
		var test_tags := ["GER", "ENG", "FRA", "SOV", "ITA", "POL", "USA"]
		var idx := 0
		for pid in new_provinces.keys():
			if pid >= 9000:  # new children from v3
				var p: Province = new_provinces[pid]
				var tag: String = str(test_tags[idx % test_tags.size()])
				p.owner_tag = tag
				p.controller_tag = tag
				idx += 1
		_toast("Assigned test owners to new provinces for playable validation.")

	# Push the new data
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_initialize"):
		MapManager.force_initialize(new_provinces, new_geometry, adj_sys, current_countries)
		var toast_msg := "v3 Playable Test Map loaded (180 provinces, test owners)" if playable_test else ("v3 closest-child map loaded" if use_v3_closest else ("IMPROVED v2 splitter map loaded" if use_improved_v2 else "Phase 1 merged map loaded"))
		_toast(toast_msg + " (%d provinces). Zoom & inspect!" % new_provinces.size())

		# Force visual layers to repaint
		var overlay := get_tree().get_first_node_in_group("infrastructure_overlay")
		if overlay and overlay.has_method("force_full_refresh"):
			overlay.force_full_refresh()

		# Ask MapRenderer to repaint if we can reach it
		var mr := get_tree().get_first_node_in_group("map_renderer")
		if mr and mr.has_method("queue_redraw"):
			mr.queue_redraw()
	else:
		_toast("MapManager.force_initialize not available")


func _on_restore_original_map():
	var loader := get_tree().root.find_child("ScenarioLoader", true, false) as ScenarioLoader
	if loader and loader.has_method("load_scenario"):
		# Re-trigger the normal scenario load path (will restore original data)
		loader.load_scenario(loader.current_scenario_name)
		_toast("Original map data restored")
	else:
		_toast("Cannot auto-restore. Restart the game or reload the scenario manually.")


func _on_reload_raw_proposed():
	var overlay = get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("reload_proposed_splits"):
		overlay.reload_proposed_splits()
		overlay.set_show_proposed_splits(true)
		_toast("Raw proposed splits reloaded from disk (fast iteration mode)")
	else:
		_toast("Could not find InfrastructureOverlayLayer")


func _on_load_phase1_test_scenario():
	# This now uses the proper persistent scenario + custom data dir support
	var loader := get_tree().root.find_child("ScenarioLoader", true, false) as ScenarioLoader
	if loader and loader.has_method("load_scenario"):
		var success := loader.load_scenario("phase1_europe_test")
		if not success:
			_toast("Failed to load Phase 1 test scenario (check console for warnings)")
			return

		# === Godot-side polish for the test scenario ===
		_toast("Phase 1 Europe Test Scenario v6 loaded — 180 provinces • PCA + coastal edges • rich attributes • nice camera start")

		# Auto-enable useful overlays for map dev/testing
		var infra_overlay = get_tree().get_first_node_in_group("infrastructure_overlay")
		if infra_overlay and infra_overlay.has_method("set_show_proposed_splits"):
			infra_overlay.set_show_proposed_splits(true)
			if infra_overlay.has_method("reload_proposed_splits"):
				infra_overlay.reload_proposed_splits()

		# Try to set a nice starting camera view focused on Europe
		_set_nice_starting_view_for_test_map()

		# Force redraws
		var mr = get_tree().get_first_node_in_group("map_renderer")
		if mr and mr.has_method("queue_redraw"):
			mr.queue_redraw()
		if infra_overlay and infra_overlay.has_method("force_full_refresh"):
			infra_overlay.force_full_refresh()

		# Rich console diagnostics
		print("\n=== Phase 1 Europe Test Map v6 Active ===")
		print("Provinces: ~180 (100 original + 120 generated children)")
		print("Splitter: PCA + strong coastal edge preservation (v6)")
		print("Merge: Closest-child + chokepoint protection + smart city/VP/special distribution")
		print("Data: data/provinces_phase1_test/ + data/scenarios/phase1_europe_test.json")
		print("Camera: Auto-set to nice Europe-focused starting view")
		print("Tip: For reliable testing of the Phase 1 map, open scenes/TestScenario.tscn and press F6 (Play Current Scene), or right-click it in the FileSystem dock → 'Set as Main Scene' so F5 launches the test map.")
		print("Tip: F10 → 'Reload Raw Proposed Splits' to live-iterate on the Python splitter.")
		print("======================================\n")
	else:
		_toast("ScenarioLoader not available for persistent test scenario load")


@warning_ignore("return_value_discarded", "unsafe_cast")
func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var data: Variant = parser.data
	if data is Dictionary:
		return data
	return {}


func _set_nice_starting_view_for_test_map():
	"""Set a pleasant starting camera position + zoom when the Phase 1 test map is loaded.
	Uses robust discovery and defers the change for safety after scene loading.
	"""
	var cam_ctrl := get_tree().get_first_node_in_group("camera_controller")
	if cam_ctrl == null:
		cam_ctrl = get_tree().root.find_child("CameraInput", true, false)
	if cam_ctrl == null:
		cam_ctrl = get_node_or_null("/root/TestScenario/WorldMap/CameraInput")
	if cam_ctrl == null:
		cam_ctrl = get_node_or_null("/root/Main/WorldMap/CameraInput")
	if cam_ctrl == null:
		push_warning("DebugOverlay: Could not find CameraController for test map view.")
		return

	# Reasonable starting view for the GRAND THEATER test map (full UK/Ireland + Scand high north + N Russia image scope + current polys).
	# Focus roughly on Western/Central Europe (Germany visible), closer zoom to show the high-res larger map detail (for counters, lines, weather at close view).
	# User can zoom even closer (up to 12x) and pan to explore the full high-detail image areas.
	# When more provinces are added to seed/geometry for UK/Scand/NRus, they will align under the bg.
	var target_pos := Vector2(1800, 650)
	var target_zoom := 2.5  # Closer initial zoom to demonstrate the higher quality larger map for close views.

	# Defer to avoid race conditions with _ready / lerp systems
	call_deferred("_apply_test_map_camera_view", cam_ctrl, target_pos, target_zoom)

	print("DebugOverlay: Queued nice starting view for GRAND THEATER Phase 1 Test Map (UK/Ireland/Scand/N Russia scope in bg)")

func _apply_test_map_camera_view(cam_ctrl: Node, pos: Vector2, zoom: float):
	if cam_ctrl == null or not is_instance_valid(cam_ctrl):
		return

	# Prefer the new public API if available (cleaner and respects controller limits)
	if cam_ctrl.has_method("set_initial_view"):
		cam_ctrl.call("set_initial_view", pos, zoom, true)
	else:
		# Fallback for older versions
		if cam_ctrl.has("target") and cam_ctrl.target:
			cam_ctrl.target.position = pos
			if "scale" in cam_ctrl.target:
				var clamped_zoom := clampf(zoom, 0.15, 6.0)
				cam_ctrl.target.scale = Vector2.ONE * clamped_zoom

		if "_target_zoom" in cam_ctrl:
			cam_ctrl._target_zoom = clampf(zoom, 0.15, 6.0)

	print("CameraController: Applied test map starting view (pos=", pos, ", zoom=", zoom, ")")


# =============================================================================
# Phase 1 Test Tools
# =============================================================================

const PHASE1_PLAN_RES := "res://tools/map_generation/output/phase1_europe/phase1_europe_plan.json"
const PHASE1_PLAN_FALLBACK := "tools/map_generation/output/phase1_europe/phase1_europe_plan.json"


@warning_ignore("return_value_discarded", "unsafe_cast")
func _load_phase1_plan_dict() -> Dictionary:
	var plan: Dictionary = _load_json_dict(PHASE1_PLAN_RES)
	if plan.is_empty():
		plan = _load_json_dict(PHASE1_PLAN_FALLBACK)
	if not (plan is Dictionary):
		return {}
	return plan


func _on_highlight_naval_pressed() -> void:
	# Placeholder — future: tint provinces in MapRenderer / test overlay layer
	var plan := _load_phase1_plan_dict()
	var naval := plan.get("naval_analysis", {}) as Dictionary
	var ranked: Array = plan.get("high_priority_candidates", [])
	var coastal_n := 0
	var high_naval: Array = []
	for entry in ranked:
		if entry is Dictionary and bool(entry.get("is_coastal", false)):
			coastal_n += 1
		if entry is Dictionary and float(entry.get("naval_importance", 0.0)) >= 1.5:
			high_naval.append(entry)
	print("Highlighting high naval importance provinces...")
	print(
		"  Pipeline plan: coastal=%s chokepoints=%s protected_straits=%s"
		% [naval.get("coastal", "?"), naval.get("chokepoints", "?"), naval.get("protected_straits", "?")]
	)
	print("  High-priority coastal candidates: %d (naval_importance >= 1.5: %d)" % [coastal_n, high_naval.size()])
	for i in mini(high_naval.size(), 8):
		var e: Dictionary = high_naval[i]
		print(
			"    pid %s  naval=%.2f  splits=%s"
			% [e.get("province_id", "?"), float(e.get("naval_importance", 0.0)), e.get("suggested_splits", "?")]
		)
	_toast("Naval highlight: see console (overlay tint TBD)")


func _on_highlight_chokepoints_pressed() -> void:
	var plan := _load_phase1_plan_dict()
	var ranked: Array = plan.get("high_priority_candidates", [])
	var choke: Array = []
	for entry in ranked:
		if entry is Dictionary and bool(entry.get("is_chokepoint", false)):
			choke.append(entry)
	print("Highlighting chokepoints and straits...")
	print("  Chokepoint candidates in plan: %d" % choke.size())
	for i in mini(choke.size(), 10):
		var e: Dictionary = choke[i]
		print(
			"    pid %s  priority=%.2f  naval=%.2f"
			% [e.get("province_id", "?"), float(e.get("priority_score", 0.0)), float(e.get("naval_importance", 0.0))]
		)
	_toast("Chokepoint highlight: see console (overlay tint TBD)")


func _on_show_subdivision_pressed() -> void:
	var overlay = get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay and overlay.has_method("set_show_proposed_splits"):
		overlay.set_show_proposed_splits(true)
		if overlay.has_method("reload_proposed_splits"):
			overlay.reload_proposed_splits()
		_refresh_proposed_status(overlay)
		_toast("Subdivision candidates overlay ON")
	else:
		_on_toggle_proposed_splits()
	print("Showing subdivision candidates...")


func _on_reload_test_scenario_pressed() -> void:
	print("Reloading Phase 1 Test Scenario...")
	_on_load_phase1_test_scenario()


func _on_print_test_report_pressed() -> void:
	var plan := _load_phase1_plan_dict()
	var naval := plan.get("naval_analysis", {}) as Dictionary
	var subdiv := plan.get("subdivision", {}) as Dictionary
	var live_n := 0
	var live_coastal := 0
	var live_sea := 0
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
		var all: Dictionary = MapManager.get_all_provinces()
		live_n = all.size()
		for p in all.values():
			if p is Province:
				if p.is_sea:
					live_sea += 1
				elif p.resolve_has_port() or str(p.terrain).to_lower() in ["coastal", "coast", "harbor", "port"]:
					live_coastal += 1
	print("=== Phase 1 Test Scenario Report ===")
	print("Live map (MapManager): %d provinces (%d coastal, %d sea)" % [live_n, live_coastal, live_sea])
	print(
		"Pipeline naval_analysis: coastal=%s chokepoints=%s protected_straits=%s island_groups=%s"
		% [
			naval.get("coastal", "TODO"),
			naval.get("chokepoints", "TODO"),
			naval.get("protected_straits", "TODO"),
			naval.get("island_groups", "TODO"),
		]
	)
	print(
		"Pipeline subdivision: ranked=%s children_proposed=%s parents=%s"
		% [
			subdiv.get("candidates_ranked", "TODO"),
			subdiv.get("children_proposed", "TODO"),
			subdiv.get("unique_parents_subdivided", "TODO"),
		]
	)
	print("Target Phase 1 density: %s" % plan.get("target_province_count", "350-450"))
	print("====================================")
	_toast("Phase 1 report printed to console")


# =============================================================================
# Starter Map Visual Editor handlers (for playtest leveling + object placement on bg images)
# =============================================================================

func _on_toggle_map_editor() -> void:
	var active: bool = not get_meta("map_editor_active", false)
	set_meta("map_editor_active", active)
	var status_label := find_child("MapEditorStatus", true, false) as Label
	if status_label:
		status_label.text = "Editor: " + ("ON (LMB places precisely at high zoom on high-res map; use terrain toggle for clean edit)" if active else "OFF")
	_toast("Map Visual Editor " + ("ENABLED" if active else "DISABLED"))
	print("Map Visual Editor toggled: ", active, " - LMB while ON places at exact mouse world pos (camera inverse) on the detailed terrain in ultra high-res bg. Use list+delete, export/load for python roundtrip. Toggle terrain for clean view.")
	call_deferred("_refresh_placed_list")


func _on_place_demo_city() -> void:
	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	if mr and mr.has_method("place_demo_object_at_mouse"):
		mr.call("place_demo_object_at_mouse", "city")
	else:
		print("Map Visual Editor: No MapRenderer with place_demo found in group 'map_renderer'. Demo city placement logged (extend MapRenderer).")
		_toast("Demo city placement attempted (see MapRenderer for integration)")
	# Future: if editor active, could queue a pending placement for next map click
	call_deferred("_refresh_placed_list")


func _on_place_demo_airfield() -> void:
	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	if mr and mr.has_method("place_demo_object_at_mouse"):
		mr.call("place_demo_object_at_mouse", "airfield")
	else:
		print("Map Visual Editor: placing demo airfield (terrain-aware in full MapRenderer spawn).")
		_toast("Demo airfield (desert/hills/swamp rules apply in data-driven spawn)")
	# In real: would record placement pos + type + terrain constraints for export
	call_deferred("_refresh_placed_list")


func _on_export_map_placements() -> void:
	print("Map Visual Editor: Exporting current demo placements (from MapRenderer DataDrivenObjects or editor_placements) to JSON for Python roundtrip / leveling tool.")
	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	if mr and mr.has_method("export_editor_placements"):
		var data: Dictionary = mr.call("export_editor_placements")
		print("  Exported data keys: ", data.keys() if data else "empty")
		# Also write to user:// for easy roundtrip / python ingest
		var path := "user://map_editor_placements.json"
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(data, "\t"))
			f.close()
			print("  Also wrote to ", path, " (load via button or python tool)")
		else:
			print("  (note: could not write user:// file)")
	else:
		print("  (stub) Would collect rects from DataDrivenObjects children + any manual editor adds, with terrain tags, season/damage variants, era/culture.")
		print("  Example JSON would include positions relative to bg image + province id hints for roundtrip.")
	_toast("Placements exported (see console + user://map_editor_placements.json)")
	call_deferred("_refresh_placed_list")


func _input(event: InputEvent) -> void:
	# Allow closing with Escape while focused
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

	# Starter map visual editor: feed mouse screen pos to MapRenderer so next "place at mouse" uses click location
	# (rough conversion via camera zoom; full would use map container global transform + province hit test).
	# When editor active, LMB click will also auto-place a demo city for quick iteration (toggle off to stop).
	if get_meta("map_editor_active", false) and event is InputEventMouse:
		var mr := get_tree().get_first_node_in_group("map_renderer") as Node
		if mr:
			if event is InputEventMouseMotion:
				mr.set_meta("last_editor_screen_mouse", event.position)
			elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if mr.has_method("place_demo_object_at_mouse"):
					mr.call("place_demo_object_at_mouse", "city")
					# Optional toast via call or just console
					print("Map Visual Editor: LMB placed demo city at precise mouse world pos (camera inverse, high-res terrain features). Pan+click to position, use other Place buttons or list delete for curation.")
					call_deferred("_refresh_placed_list")

	# Province Border Editor (in-game) — pass input to the editor when active
	if get_meta("province_editor_active", false) and event is InputEventMouse:
		var pe := _get_province_editor()
		if pe and pe.has_method("handle_map_input"):
			if pe.handle_map_input(event):
				get_viewport().set_input_as_handled()
				return

# --- Province Editor helpers ---

var _province_editor_instance: Node = null

# Historical borders overlay for 1918/1936/2026 to aid province decisions (toggleable in editor)
var _historical_border_layer: Node2D = null
var _current_border_era: String = ""

func _get_province_editor() -> Node:
	if _province_editor_instance and is_instance_valid(_province_editor_instance):
		return _province_editor_instance

	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	if mr == null or mr.get("container") == null:
		_toast("Map not ready for province editing")
		return null

	var existing: Node = mr.container.get_node_or_null("ProvinceEditor")
	if existing:
		_province_editor_instance = existing
		return existing

	var pe_script := load("res://scripts/map/ProvinceEditor.gd")
	if pe_script == null:
		_toast("ProvinceEditor.gd not found")
		return null

	var pe := (pe_script as GDScript).new() as Node
	pe.name = "ProvinceEditor"
	mr.container.add_child(pe)
	_province_editor_instance = pe
	return pe

func _on_toggle_province_editor() -> void:
	var active: bool = not get_meta("province_editor_active", false)
	set_meta("province_editor_active", active)

	var pe := _get_province_editor()
	if pe and pe.has_method("set_active"):
		pe.set_active(active)
		if active and pe.has_method("load_session"):
			pe.call("load_session")  # auto-load persistent session on enable

	var status_label := find_child("ProvinceEditorStatus", true, false) as Label
	if status_label:
		status_label.text = "Province Editor: " + ("ON — LMB add vertex, Right-click finish. Use clean base map." if active else "OFF")

	_toast("Province Border Editor " + ("ENABLED" if active else "DISABLED"))
	print("ProvinceEditor toggled: ", active)
	call_deferred("_refresh_edited_provinces_list")

func _on_export_editor_provinces() -> void:
	var pe := _get_province_editor()
	if pe and pe.has_method("export_to_json"):
		var res: Dictionary = pe.call("export_to_json")
		_toast("Exported " + str(res.get("count", 0)) + " provinces")
		print("Province editor export: ", res)
		call_deferred("_refresh_edited_provinces_list")
	else:
		_toast("ProvinceEditor not available")

func _refresh_edited_provinces_list() -> void:
	if _edited_provinces_list_vbox == null or not is_instance_valid(_edited_provinces_list_vbox):
		return
	for ch in _edited_provinces_list_vbox.get_children():
		ch.queue_free()

	var pe := _get_province_editor()
	if pe == null or not pe.has_method("get_edited_provinces"):
		var l := Label.new()
		l.text = "(no province editor or no provinces yet)"
		l.add_theme_font_size_override("font_size", 9)
		_edited_provinces_list_vbox.add_child(l)
		return

	var edited: Dictionary = pe.call("get_edited_provinces")
	if edited.is_empty():
		var l := Label.new()
		l.text = "(no provinces drawn yet - LMB to start)"
		l.add_theme_font_size_override("font_size", 9)
		_edited_provinces_list_vbox.add_child(l)
		return

	for temp_id in edited.keys():
		var data: Dictionary = edited[temp_id]
		var pts: PackedVector2Array = data.get("points", PackedVector2Array())
		var row := HBoxContainer.new()

		var lbl := Label.new()
		lbl.text = "Prov %d (%d pts)" % [temp_id, pts.size()]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 9)
		row.add_child(lbl)

		var sel_btn := Button.new()
		sel_btn.text = "Select/Edit"
		sel_btn.custom_minimum_size = Vector2(70, 18)
		sel_btn.add_theme_font_size_override("font_size", 8)
		sel_btn.pressed.connect(func():
			if pe.has_method("select_province_for_edit"):
				pe.call("select_province_for_edit", temp_id)
			_toast("Selected for vertex drag")
		)
		row.add_child(sel_btn)

		var del_btn := Button.new()
		del_btn.text = "Del"
		del_btn.custom_minimum_size = Vector2(40, 18)
		del_btn.add_theme_font_size_override("font_size", 8)
		del_btn.pressed.connect(func():
			if pe.has_method("delete_edited_province"):
				pe.call("delete_edited_province", temp_id)
			_refresh_edited_provinces_list()
			_toast("Deleted temp province")
		)
		row.add_child(del_btn)

		var hl_btn := Button.new()
		hl_btn.text = "HL Conflict"
		hl_btn.custom_minimum_size = Vector2(60, 18)
		hl_btn.add_theme_font_size_override("font_size", 8)
		hl_btn.pressed.connect(func():
			if pe.has_method("highlight_conflicts"):
				pe.call("highlight_conflicts", temp_id)
			_toast("Highlighted conflicts for " + str(temp_id))
		)
		row.add_child(hl_btn)

		_edited_provinces_list_vbox.add_child(row)

var _aircraft_design_system: Node = null
var _air_status_label: Label = null  # Live tracker for aircraft prototype maturity/reliability in Debug

func _get_or_create_aircraft_design_system() -> Node:
	if _aircraft_design_system and is_instance_valid(_aircraft_design_system):
		return _aircraft_design_system

	var script := load("res://scripts/air/AircraftDesignSystem.gd")
	if script == null:
		_toast("AircraftDesignSystem.gd not found")
		return null

	_aircraft_design_system = (script as GDScript).new()
	_aircraft_design_system.name = "AircraftDesignSystem"
	get_tree().root.add_child(_aircraft_design_system)
	return _aircraft_design_system

func _update_air_status() -> void:
	if _air_status_label == null:
		return
	var ads := _get_or_create_aircraft_design_system()
	if ads == null or not ads.has_method("get_or_create_design_state"):
		_air_status_label.text = "Aircraft Status: ADS not ready"
		return
	var st: Dictionary = ads.get_or_create_design_state("demo_p51_prototype", {"id": "demo_p51_early"})
	var mat = float(st.get("maturity", 0.0))
	var rel_off = float(st.get("reliability_offset", 0.0))
	var agents = st.get("agent_assigned_ids", [])
	var maint = float(st.get("maintenance_multiplier", 1.0))
	_air_status_label.text = "Aircraft: Mat=%.2f Rel=%.1f Maint=%.1fx Agents=%d\nXP/iter: use buttons (rich panel in future production UI)" % [mat, rel_off, maint, len(agents)]

# --- Historical borders for editor aid (1918 pre-Versailles, 1936 interwar, 2026 modern) ---
# Data: approximate polylines in grand theater world coords (0-5000 x 0-2000). Human override by drawing provinces freely.
var _historical_border_data := {
	"1918": [
		# Simplified major 1918 borders (e.g. German Empire, Russian, etc. - demo only)
		[Vector2(1200,400), Vector2(1800,300), Vector2(2200,450), Vector2(2500,600)],
		[Vector2(800,200), Vector2(1400,150), Vector2(1600,350)],
	],
	"1936": [
		[Vector2(1000,300), Vector2(1700,250), Vector2(2100,400), Vector2(2400,550), Vector2(2800,700)],
		[Vector2(700,180), Vector2(1300,120), Vector2(1500,300)],
	],
	"2026": [
		[Vector2(900,350), Vector2(1600,280), Vector2(2000,420), Vector2(2300,580), Vector2(2700,750)],
		[Vector2(600,150), Vector2(1200,100), Vector2(1400,280)],
	]
}

func _toggle_historical_borders(era: String) -> void:
	var mr := get_tree().get_first_node_in_group("map_renderer") as MapRenderer
	if mr == null or mr.container == null:
		_toast("Map not ready")
		return

	if _current_border_era == era:
		_clear_historical_borders()
		return

	_clear_historical_border_lines()
	_current_border_era = era
	_ensure_historical_border_layer(mr)

	var lines = _historical_border_data.get(era, [])
	for line_pts in lines:
		var l := Line2D.new()
		l.points = PackedVector2Array(line_pts)
		l.width = 4.0
		l.default_color = Color(0.8, 0.2, 0.2, 0.7) if era == "1918" else (Color(0.2, 0.6, 0.9, 0.7) if era == "1936" else Color(0.2, 0.8, 0.4, 0.7))
		l.z_index = 10
		_historical_border_layer.add_child(l)

	_toast("Showing " + era + " borders (aid for province drawing - fully overrideable)")


func _ensure_historical_border_layer(mr: MapRenderer) -> void:
	if _historical_border_layer != null and is_instance_valid(_historical_border_layer):
		return
	_historical_border_layer = Node2D.new()
	_historical_border_layer.name = "HistoricalBordersLayer"
	_historical_border_layer.z_index = 5  # Above bg, under polys
	mr.container.add_child(_historical_border_layer)


func _clear_historical_border_lines() -> void:
	if _historical_border_layer == null or not is_instance_valid(_historical_border_layer):
		return
	for ch in _historical_border_layer.get_children():
		ch.queue_free()


func _clear_historical_borders() -> void:
	_clear_historical_border_lines()
	if _historical_border_layer != null and is_instance_valid(_historical_border_layer):
		_historical_border_layer.queue_free()
	_historical_border_layer = null
	_current_border_era = ""
	print("Historical borders layer cleared.")


func _place_demo_type(type: String) -> void:
	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	if mr and mr.has_method("place_demo_object_at_mouse"):
		mr.call("place_demo_object_at_mouse", type)
	else:
		_toast("No MapRenderer place for " + type)
	call_deferred("_refresh_placed_list")


func _on_toggle_terrain_layer() -> void:
	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	if mr and mr.has_method("toggle_terrain_layer"):
		mr.call("toggle_terrain_layer")
		_toast("Terrain layer toggled (clean view when OFF)")
	else:
		_toast("Terrain toggle: MapRenderer not ready")
	call_deferred("_refresh_placed_list")


func _refresh_placed_list() -> void:
	if _placed_list_vbox == null or not is_instance_valid(_placed_list_vbox):
		return
	# Clear
	for ch in _placed_list_vbox.get_children():
		ch.queue_free()
	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	if mr == null:
		var l := Label.new(); l.text = "(no map renderer)"; l.add_theme_font_size_override("font_size", 9); _placed_list_vbox.add_child(l); return
	var placements: Array = []
	if mr.has_method("get_editor_placements"):
		placements = mr.call("get_editor_placements") as Array
	elif mr.has_meta("editor_placements"):
		placements = mr.get_meta("editor_placements", []) as Array
	# Also scan live DataDrivenObjects for current nodes (more accurate after deletes)
	var live_nodes: Array = []
	var cont = mr.get("container") if mr.get("container") != null else null
	if cont:
		var dp := (cont as Node).get_node_or_null("DataDrivenObjects") as Node
		if dp:
			for i in dp.get_child_count():
				var ch := dp.get_child(i)
				if ch:
					live_nodes.append(ch)
	# Build UI rows from meta (authoritative) + live cross-ref
	if placements.is_empty() and live_nodes.is_empty():
		var l := Label.new()
		l.text = "(no placements yet - LMB or Place buttons while editor ON)"
		l.add_theme_font_size_override("font_size", 9)
		l.modulate = Color(0.6,0.6,0.6)
		_placed_list_vbox.add_child(l)
		return
	for i in range(placements.size()):
		var p: Dictionary = placements[i] as Dictionary
		var typ := str(p.get("type", "?"))
		var posarr: Array = p.get("position", [0,0])
		var px := float(posarr[0]) if posarr.size() > 0 else 0.0
		var py := float(posarr[1]) if posarr.size() > 1 else 0.0
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s @ %.0f,%.0f" % [typ, px, py]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.clip_text = true
		row.add_child(lbl)
		var delb := Button.new()
		delb.text = "Del"
		delb.custom_minimum_size = Vector2(36, 16)
		delb.add_theme_font_size_override("font_size", 8)
		delb.pressed.connect(func():
			# delete from meta
			if mr.has_method("remove_editor_placement_at"):
				mr.call("remove_editor_placement_at", Vector2(px, py))
			# try remove matching live node
			if cont:
				var dpp := (cont as Node).get_node_or_null("DataDrivenObjects") as Node
				if dpp:
					for j in range(dpp.get_child_count()-1, -1, -1):
						var nd := dpp.get_child(j)
						if nd and nd.position.distance_to(Vector2(px,py)) < 40.0:
							nd.queue_free()
							break
			_refresh_placed_list()
			_toast("Deleted")
		)
		row.add_child(delb)
		_placed_list_vbox.add_child(row)
	# Also list any live-only nodes not in meta (e.g. data-driven spawns)
	for nd in live_nodes:
		var already := false
		for pr in placements:
			var pp := Vector2(float((pr as Dictionary).get("position",[0,0])[0]), float((pr as Dictionary).get("position",[0,0])[1]))
			if nd.position.distance_to(pp) < 25.0: already = true; break
		if already: continue
		var row2 := HBoxContainer.new()
		var lbl2 := Label.new()
		lbl2.text = "[live] %s @ %.0f,%.0f" % [nd.name, nd.position.x, nd.position.y]
		lbl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl2.add_theme_font_size_override("font_size", 9)
		row2.add_child(lbl2)
		var del2 := Button.new()
		del2.text = "Del"
		del2.custom_minimum_size = Vector2(36,16)
		del2.add_theme_font_size_override("font_size", 8)
		del2.pressed.connect(func():
			if is_instance_valid(nd): nd.queue_free()
			_refresh_placed_list()
		)
		row2.add_child(del2)
		_placed_list_vbox.add_child(row2)


func _on_load_map_placements() -> void:
	var path := "user://map_editor_placements.json"
	if not FileAccess.file_exists(path):
		# fallback to project tools output if present
		path = "res://tools/map_generation/output/map_editor_placements.json"
		if not FileAccess.file_exists(path):
			_toast("No placements JSON found (export first)")
			print("Load placements: tried user:// and tools/.../map_editor_placements.json - none found")
			return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_toast("Could not open " + path)
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		_toast("Bad JSON")
		return
	var data: Dictionary = parsed as Dictionary
	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	var count := 0
	if data.has("placements") and mr and mr.has_method("place_demo_object_at_mouse"):
		# For roundtrip, pass exact stored world pos (place_demo supports exact_world_pos param for no-jitter load).
		for p in data["placements"] as Array:
			var typ := str((p as Dictionary).get("type", "city"))
			var posarr: Array = (p as Dictionary).get("position", [1200.0, 650.0])
			var epos := Vector2(float(posarr[0]), float(posarr[1]))
			mr.call("place_demo_object_at_mouse", typ, epos)
			count += 1
	print("Loaded %d placements from %s (exact pos from JSON; LMB re-place or delete to tweak on high-res image)" % [count, path])
	_toast("Loaded %d (see console)" % count)
	call_deferred("_refresh_placed_list")


func _on_export_map_placements_to_file() -> void:
	var mr := get_tree().get_first_node_in_group("map_renderer") as Node
	if mr and mr.has_method("export_editor_placements"):
		var data: Dictionary = mr.call("export_editor_placements")
		var path := "user://map_editor_placements.json"
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(data, "\t"))
			f.close()
			print("Exported placements to ", path)
			_toast("Exported to user://map_editor_placements.json")
		else:
			_toast("Write failed")
	else:
		_toast("No export method")
	call_deferred("_refresh_placed_list")


# =============================================================================
# Dynamic borders + phased combat (F10 Phase 1 playtest tools)
# =============================================================================

func _on_cycle_border_demo() -> void:
	var blob := _collect_demo_blob()
	if blob.is_empty():
		return

	if _simulate_step < 0:
		_snapshot_cluster_owners(blob)
		_simulate_blob = blob
		_simulate_step = 0

	match _simulate_step:
		0:
			_ensure_demo_country_stubs()
			for pid in blob:
				MapManager.update_province_owner(pid, "YUG", "YUG", false)
			_toast("Step 1/4: united %d provinces as YUG" % blob.size())
		1:
			if blob.size() >= 3:
				MapManager.update_province_owner(blob[blob.size() - 1], "SRB", "SRB", false)
			if blob.size() >= 4:
				MapManager.update_province_owner(blob[blob.size() - 2], "CRO", "CRO", false)
			if blob.size() >= 6:
				MapManager.update_province_owner(blob[1], "SRB", "SRB", false)
			_toast("Step 2/4: SRB/CRO split — watch BorderLayer frontiers")
		2:
			var tags := ["YUG", "SRB", "CRO", "SLO", "HUN", "BGR"]
			for i in blob.size():
				var tag: String = tags[i % tags.size()]
				MapManager.update_province_owner(blob[i], tag, tag, false)
			_toast("Step 3/4: historical tag mosaic on cluster")
		3:
			_revert_border_demo()
			_simulate_step = -1
			return

	_simulate_step += 1
	_force_border_refresh()


func _on_revert_border_demo() -> void:
	if _revert_border_demo():
		_toast("Reverted border demo cluster to pre-demo owners")
	else:
		_toast("No border demo snapshot — run Cycle Border Demo first")


func _revert_border_demo() -> bool:
	if _simulate_snapshot.is_empty():
		return false
	for pid_var in _simulate_snapshot.keys():
		var pid := int(pid_var)
		var snap: Dictionary = _simulate_snapshot[pid_var]
		MapManager.update_province_owner(
			pid,
			str(snap.get("owner", "")),
			str(snap.get("controller", snap.get("owner", ""))),
			true,
		)
	_simulate_snapshot.clear()
	_simulate_blob.clear()
	_simulate_step = -1
	_force_border_refresh()
	return true


func _on_test_combat_capture() -> void:
	var mr := get_tree().get_first_node_in_group("map_renderer") as MapRenderer
	if mr == null:
		_toast("No MapRenderer (open TestScenario + F10)")
		return
	if mr.selected_province_id < 0:
		_toast("Left-click a province first (defender battle site)")
		return
	if typeof(BattleManager) == TYPE_NIL:
		_toast("BattleManager unavailable")
		return

	var battle_pid := mr.selected_province_id
	var battle_prov: Province = MapManager.get_province(battle_pid) if typeof(MapManager) != TYPE_NIL else null
	if battle_prov == null:
		_toast("Selected province not in MapManager")
		return

	var defender_tag := battle_prov.owner_tag if not battle_prov.owner_tag.is_empty() else "YUG"
	var attacker_tag := _pick_attacker_tag_for_combat(mr, battle_pid, defender_tag)
	_ensure_demo_country_stubs()
	_ensure_demo_country_stubs_for_tag(attacker_tag)
	_ensure_demo_country_stubs_for_tag(defender_tag)

	var from_pid := mr.attack_staging_province_id
	if from_pid < 0:
		from_pid = mr.debug_combat_attacker_province_id

	var assault := BattleManager.execute_province_assault(attacker_tag, battle_pid, from_pid)
	if not bool(assault.get("success", false)):
		_toast(str(assault.get("reason", "Combat failed")))
		return

	var result: Dictionary = assault.get("result", {}) as Dictionary
	var winner := str(result.get("winner", ""))
	var captured := bool(result.get("province_control_change", false))
	var outcome := str(result.get("outcome", winner))

	if winner == "attacker" and captured:
		_toast(
			"Combat %s: %s captured province %d (%s)" % [outcome, attacker_tag, battle_pid, battle_prov.name]
		)
	else:
		_toast(
			"Combat %s — winner=%s capture=%s (no border change)" % [outcome, winner, str(captured)]
		)
	print("DebugOverlay test combat pid=%d result=%s" % [battle_pid, result])


func _on_run_ai_assault_pass() -> void:
	if typeof(AIBattleDirector) == TYPE_NIL:
		_toast("AIBattleDirector unavailable")
		return
	if not AIBattleDirector.has_method("run_ai_assault_pass"):
		_toast("AIBattleDirector missing run_ai_assault_pass")
		return
	var n: int = int(AIBattleDirector.run_ai_assault_pass())
	if n <= 0:
		_toast("AI assault pass: no valid attacks (need enemy divisions adjacent to foes)")
	else:
		_toast("AI assault pass launched %d attack(s)" % n)
		_force_border_refresh()


func _pick_attacker_tag_for_combat(mr: MapRenderer, battle_pid: int, defender_tag: String) -> String:
	if mr.debug_combat_attacker_province_id >= 0:
		var staging: Province = MapManager.get_province(mr.debug_combat_attacker_province_id)
		if staging != null and not staging.owner_tag.is_empty():
			var stag_tag := staging.owner_tag.strip_edges().to_upper()
			if stag_tag != defender_tag.strip_edges().to_upper():
				return stag_tag

	var adj: AdjacencySystem = mr.adjacency
	if adj != null:
		for nid in adj.get_neighbors(battle_pid):
			var nprov: Province = MapManager.get_province(int(nid))
			if nprov == null:
				continue
			var ntag := nprov.owner_tag.strip_edges().to_upper()
			if not ntag.is_empty() and ntag != defender_tag.strip_edges().to_upper():
				return ntag
	for tag in ["GER", "SRB", "CRO", "SOV", "USA"]:
		if tag != defender_tag.strip_edges().to_upper():
			return tag
	return "GER"


func _division_template_for_tag(country_tag: String) -> String:
	match country_tag.strip_edges().to_upper():
		"GER":
			return "german_infantry_division_1943"
		"USA":
			return "us_infantry_div_ww2"
		"SRB", "CRO", "YUG", "SLO", "HUN", "BGR":
			return "german_infantry_division_1943_mixed"
		_:
			return "us_marine_division_ww2"


func _collect_demo_blob() -> Array[int]:
	var mr := get_tree().get_first_node_in_group("map_renderer") as MapRenderer
	if mr == null:
		_toast("No MapRenderer in tree (open TestScenario + F10)")
		return []
	var container: Node2D = mr.get_node_or_null("ProvinceContainers") as Node2D
	if container == null:
		_toast("No ProvinceContainers")
		return []

	var candidates: Array[int] = []
	for node in container.get_children():
		if node.name.begins_with("Prov_"):
			var pid := int(node.name.substr(5))
			if pid >= 9000:
				candidates.append(pid)
				if candidates.size() >= 12:
					break
	if candidates.size() < 4:
		_toast("Need at least 4 phase1 provinces (9000+). Load Phase1 test first.")
		return []

	var adj: AdjacencySystem = mr.adjacency
	var blob: Array[int] = []
	var seed: int = candidates[0]
	blob.append(seed)
	if adj != null:
		for n in adj.get_neighbors(seed):
			if blob.size() < 5 and candidates.has(int(n)):
				blob.append(int(n))
	for c in candidates:
		if blob.size() >= 6:
			break
		if not blob.has(c):
			blob.append(c)
	return blob


func _snapshot_cluster_owners(blob: Array[int]) -> void:
	_simulate_snapshot.clear()
	for pid in blob:
		var p: Province = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
		if p == null:
			continue
		_simulate_snapshot[pid] = {
			"owner": p.owner_tag,
			"controller": p.controller_tag,
		}


func _ensure_demo_country_stubs() -> void:
	for tag in DEMO_STUB_COLORS.keys():
		_ensure_demo_country_stubs_for_tag(str(tag))


func _ensure_demo_country_stubs_for_tag(tag: String) -> void:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return
	var color: Color = DEMO_STUB_COLORS.get(t, Color(0.5, 0.5, 0.55, 0.9))
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("ensure_country_stub"):
		MapManager.ensure_country_stub(t, color)
	var mr := get_tree().get_first_node_in_group("map_renderer") as MapRenderer
	if mr != null and not mr.countries.has(t):
		mr.countries[t] = {"color": color, "name": t, "tag": t}


func _force_border_refresh() -> void:
	var mr := get_tree().get_first_node_in_group("map_renderer") as MapRenderer
	if mr != null and mr.has_method("force_border_update"):
		mr.force_border_update()
