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

const PANEL_WIDTH := 420
const PANEL_HEIGHT := 520
const MARGIN := 12

static var instance: DebugOverlay = null

var _main_container: PanelContainer
var _content_vbox: VBoxContainer
var _sections: Dictionary = {}           # title -> VBoxContainer
var _status_label: Label
var _last_refresh_time := 0.0

var _infra_count_label: Label
var _infra_list_vbox: VBoxContainer


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

	# Auto-refresh content when we become visible
	visibility_changed.connect(_on_visibility_changed)


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
					root.add_child(overlay)
					instance = overlay
	if instance:
		instance.visible = not instance.visible
		if instance.visible:
			instance._refresh_all_content()


static func show_overlay() -> void:
	if instance:
		instance.visible = true
		instance._refresh_all_content()
	elif Engine.get_main_loop():
		toggle()


static func hide_overlay() -> void:
	if instance:
		instance.visible = false


static func is_visible() -> bool:
	return instance != null and instance.visible


static func add_section(title: String) -> VBoxContainer:
	if instance == null:
		toggle()  # force creation
	if instance:
		return instance._ensure_section(title)
	return null


func _build_ui() -> void:
	_main_container = PanelContainer.new()
	_main_container.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_main_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_main_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(_main_container)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_main_container.add_child(outer)

	# Title bar
	var title_bar := HBoxContainer.new()
	outer.add_child(title_bar)

	var title := Label.new()
	title.text = "DEBUG OVERLAY"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(func(): visible = false)
	title_bar.add_child(close_btn)

	# Content
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_content_vbox)

	# Status bar at bottom
	_status_label = Label.new()
	_status_label.text = "Press F10 or Ctrl+Shift+R to toggle"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status_label)

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
	if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_national_special_site_trade_capacity_bonus"):
		var bonus := TradeManager.get_national_special_site_trade_capacity_bonus("USA")  # MVP: player tag
		var trade_label := Label.new()
		trade_label.text = "National Trade Capacity Bonus: +%d" % int(bonus)
		trade_label.add_theme_font_size_override("font_size", 10)
		trade_label.modulate = Color(0.5, 0.85, 0.6)
		infra_section.add_child(trade_label)

		# Also show total special site count for the player
		if typeof(MapManager) != TYPE_NIL:
			var total_sites := 0
			for pid in MapManager.get_provinces_by_owner("USA"):
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

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 13)
	_content_vbox.add_child(header)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_content_vbox.add_child(vbox)

	_sections[title] = vbox
	return vbox


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
	# Position in top-right, slightly inset
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	global_position = Vector2(vp.x - PANEL_WIDTH - 40, 80)


func _on_visibility_changed() -> void:
	if visible:
		_refresh_all_content()


func _refresh_all_content() -> void:
	_last_refresh_time = Time.get_unix_time_from_system()
	_refresh_infrastructure_section()
	_refresh_time_section()
	_refresh_proposed_status()
	_update_status()


func _refresh_infrastructure_section():
	var count_label := get_meta("infra_count_label") as Label
	var list := get_meta("infra_list") as VBoxContainer
	if count_label == null or list == null:
		return

	list.clear()

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
		ss_list.clear()
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
	if overlay == null:
		overlay = get_tree().get_first_node_in_group("infrastructure_overlay")
	if overlay == null:
		status_label.text = "Proposed: overlay not found"
		return

	var loaded: bool = false
	var count: int = 0
	var showing: bool = false

	if overlay.has_method("get"):
		loaded = bool(overlay.get("proposed_data_loaded"))
		var kids = overlay.get("proposed_children")
		if kids is Array:
			count = kids.size()
		showing = bool(overlay.get("show_proposed_splits"))

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


func _on_boost_all_projects():
	var manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
	if manager and manager.has_method("active_projects"):
		for pid in manager.active_projects.keys():
			var proj = manager.active_projects[pid]
			proj.progress = clampf(proj.progress + 25.0, 0.0, 100.0)

	_refresh_infrastructure_section()
	_toast("All projects boosted +25%")


func _on_complete_all_projects():
	var manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
	if manager and manager.has_method("active_projects"):
		for pid in manager.active_projects.keys():
			var proj = manager.active_projects[pid]
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
	var proj = manager.active_projects[random_pid]
	proj.modifiers["sabotage"] = -0.8   # strong sabotage

	_refresh_infrastructure_section()
	if typeof(MapManager) != TYPE_NIL:
		MapManager.notify_province_changed(int(random_pid), "infrastructure_project")
	_toast("Sabotaged random project in province " + str(random_pid))


func _on_debug_spawn_port():
	var selected := -1
	# Try to use currently selected province from MapRenderer if available
	if typeof(MapRenderer) != TYPE_NIL and MapRenderer.has_method("selected_province_id"):
		selected = MapRenderer.selected_province_id

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

		var Prov := preload("res://scripts/map/Province.gd")
		var p := Prov.new()
		p.id = pid
		p.name = "Child " + str(pid) if entry.has("parent_id") else ("Province " + str(pid))
		p.terrain = "plains"
		p.is_sea = false

		# Pull attributes from the merged layers when available
		var tdata := terrain_data.get("provinces", {}).get(str(pid), {})
		if tdata.has("terrain"):
			p.terrain = str(tdata["terrain"])

		var edata := eco_data.get("provinces", {}).get(str(pid), {})
		if edata.has("population"):
			p.population = int(edata["population"])
		if edata.has("infrastructure"):
			p.infrastructure = int(edata["infrastructure"])
		if edata.has("development_level"):
			p.development_level = int(edata["development_level"])

		var rdata := res_data.get("provinces", {}).get(str(pid), {})
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
				var tag := test_tags[idx % test_tags.size()]
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
	if typeof(ScenarioLoader) != TYPE_NIL and ScenarioLoader.has_method("load_scenario"):
		# Re-trigger the normal scenario load path (will restore original data)
		ScenarioLoader.load_scenario(ScenarioLoader.current_scenario_name)
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
	if typeof(ScenarioLoader) != TYPE_NIL and ScenarioLoader.has_method("load_scenario"):
		ScenarioLoader.load_scenario("phase1_europe_test")

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
		print("Tip: F10 → 'Reload Raw Proposed Splits' to live-iterate on the Python splitter.")
		print("======================================\n")
	else:
		_toast("ScenarioLoader not available for persistent test scenario load")


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
	var data := parser.data
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}


func _set_nice_starting_view_for_test_map():
	"""Set a pleasant starting camera position + zoom when the Phase 1 test map is loaded."""
	var cam_ctrl := get_tree().get_first_node_in_group("camera_controller")
	if cam_ctrl == null:
		# Fallback search (common in this project)
		cam_ctrl = get_node_or_null("/root/Main/WorldMap/CameraInput")
	if cam_ctrl == null or not cam_ctrl.has_method("_ready"):  # basic sanity
		return

	# Reasonable starting view for the expanded Europe test map (4096x2048 texture)
	# Focus roughly on Western/Central Europe, medium zoom
	var target_pos := Vector2(1800, 650)   # good center for Europe on this texture
	var target_zoom := 0.85

	if cam_ctrl.has("target") and cam_ctrl.target:
		cam_ctrl.target.position = target_pos
		if "scale" in cam_ctrl.target:
			cam_ctrl.target.scale = Vector2.ONE * target_zoom

	# Also try to set internal target zoom if the controller uses it
	if "_target_zoom" in cam_ctrl:
		cam_ctrl._target_zoom = target_zoom

	print("CameraController: Set nice starting view for Phase 1 Test Map (pos=", target_pos, ", zoom=", target_zoom, ")")


# =============================================================================
# Phase 1 Test Tools
# =============================================================================

const PHASE1_PLAN_RES := "res://tools/map_generation/output/phase1_europe/phase1_europe_plan.json"
const PHASE1_PLAN_FALLBACK := "tools/map_generation/output/phase1_europe/phase1_europe_plan.json"


func _load_phase1_plan_dict() -> Dictionary:
	var plan := _load_json_dict(PHASE1_PLAN_RES)
	if plan.is_empty():
		plan = _load_json_dict(PHASE1_PLAN_FALLBACK)
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


func _input(event: InputEvent) -> void:
	# Allow closing with Escape while focused
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
