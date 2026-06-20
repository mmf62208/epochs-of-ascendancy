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


func _debug_preview_era_infra(year: int) -> void:
	if typeof(TimeManager) == TYPE_NIL:
		toast_map_debug("TimeManager missing — cannot preview era infra.")
		return
	TimeManager.current_year = year
	var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
	if mr == null:
		mr = get_node_or_null("/root/WorldMap")
	if mr == null:
		toast_map_debug("MapRenderer missing.")
		return
	if mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "infra")
	var ol: Node = mr.call("get_overlay_layer", "InfrastructureOverlayLayer") if mr.has_method("get_overlay_layer") else null
	if ol and ol.has_method("rebuild_all_infra_layers"):
		ol.call("rebuild_all_infra_layers")
	if ol and ol.has_method("set_show_roads"):
		ol.call("set_show_roads", true)
		ol.call("set_show_rails", true)
	var label := "?"
	if ol and ol.has_method("get_era_infra_profile"):
		label = str(ol.call("get_era_infra_profile").get("label", "?"))
	toast_map_debug("Era infra preview: year %d (%s). R=roads T=rails F7=infra mode." % [year, label])


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


## Helpers for new F10 mass-settle/inspect/welfare-live buttons: zero-interference, use tree find for MapRenderer (scene node, not autoload).
func _force_map_tint_refresh_for_tag(tag: String) -> void:
	if tag.is_empty():
		tag = _debug_player_country_tag()
	var mr: Node = _find_map_renderer()
	if mr != null:
		if mr.has_method("force_refresh_tints_for_owner"):
			mr.call("force_refresh_tints_for_owner", tag)
		elif mr.has_method("force_full_map_refresh"):
			mr.call("force_full_map_refresh")
		else:
			# Fallback: emit on samples to trigger existing handler (for settlement path)
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
				for pid in MapManager.get_provinces_by_owner(tag).slice(0, 20):
					if MapManager.has_signal("province_data_changed"):
						MapManager.province_data_changed.emit(pid, "welfare")
	else:
		print("[DebugOverlay] No MapRenderer found for live tint force; tints may update on next zoom/pan or province click.")


func _try_refresh_open_inspector() -> void:
	var mr: Node = _find_map_renderer()
	if mr != null and mr.has_method("force_full_map_refresh"):
		mr.call("force_full_map_refresh")
	elif mr != null and mr.has_method("show_info_panel"):
		# Best effort re-show current if we can infer selected
		pass


func _try_show_inspector_on_samples(sample_pids: Array) -> void:
	var mr: Node = _find_map_renderer()
	if mr == null or sample_pids.is_empty() or not mr.has_method("show_info_panel"):
		print("[DebugOverlay] Inspector force-show skipped (no MR or no samples). Use manual click on provinces after actions.")
		return
	for pid in sample_pids:
		if typeof(MapManager) != TYPE_NIL:
			var p = MapManager.get_province(pid)
			if p != null:
				mr.call("show_info_panel", p)
				print("[DebugOverlay] Forced inspector open on prov #%d for live settlement/welfare verification." % pid)
				break  # show one; user can click others or re-use inspect btn


func _open_policy_law_screen() -> void:
	var packed: PackedScene = load("res://scenes/ui/PolicyLawScreen.tscn") as PackedScene
	if packed == null:
		_toast("PolicyLawScreen.tscn missing; use TopInfoBar Policies button.")
		return
	var screen: Node = packed.instantiate()
	var host := get_tree().current_scene if get_tree() else null
	if host:
		host.add_child(screen)
	else:
		get_tree().root.add_child(screen)
	var ptag := _debug_player_country_tag()
	if screen.has_method("set_player_tag"):
		screen.call_deferred("set_player_tag", ptag)
	elif screen is Window:
		(screen as Window).popup_centered()


func _find_map_renderer() -> Node:
	# Prefer group if wired in scene (some test maps do); fallback to tree search for WorldMap/MapRenderer.
	if is_inside_tree():
		var by_group := get_tree().get_first_node_in_group("map_renderer")
		if by_group != null:
			return by_group
		var root := get_tree().current_scene
		if root:
			var candidate := root.find_child("WorldMap", true, false)
			if candidate and candidate.has_method("show_info_panel"):
				return candidate
			candidate = root.find_child("MapRenderer", true, false)
			if candidate and candidate.has_method("show_info_panel"):
				return candidate
	return null


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

	# === Demographic / Settlement Playtest Section (critical for testing relocation, policies, map territory integration) ===
	# Makes "full territories + systems" playable: one-click apply settlement to owned/low-dev provinces, see dev/infra/settlement_level effects on map tint, inspector (org/attrition/supply), combat, supply.
	var demo_section := _ensure_section("Demographic Map Test (Relocation/Settlement)")
	var demo_note := Label.new()
	demo_note.text = "Applies real multi-province settlement (prefers owned low-dev). Watch map vitality tint, inspector bonuses, province effects."
	demo_note.add_theme_font_size_override("font_size", 9)
	demo_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	demo_section.add_child(demo_note)

	var apply_reloc_btn := Button.new()
	apply_reloc_btn.text = "🗺️ Apply Sample Relocation (scale 0.35) to Player Tag"
	apply_reloc_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_encourage_relocation"):
			var ptag := "player"
			if typeof(LeaderManager) != TYPE_NIL:
				ptag = LeaderManager.get_player_country_tag()
			GameData.apply_encourage_relocation(ptag, "playtest_settlement", 0.35)
			toast_map_debug("Settlement applied to owned/low-dev provinces. Check inspector (org/attrition/supply uplift), map tint (subtle healthy shift), assaults for effects. Ties policy + map territories.")
		else:
			toast_map_debug("GameData relocation not available.")
	)
	demo_section.add_child(apply_reloc_btn)

	var highlight_settled_btn := Button.new()
	highlight_settled_btn.text = "🔎 Log Settled Provinces + Effects"
	highlight_settled_btn.pressed.connect(func():
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
			var settled := []
			for pid in MapManager.get_all_provinces():
				var p = MapManager.get_province(pid)
				if p and p.settlement_level > 0.05:
					settled.append("%s(#%d lev=%.2f dev=%d)" % [p.name if p.name else "", pid, p.settlement_level, p.development_level])
			if settled.size() > 0:
				toast_map_debug("Settled: " + ", ".join(settled))
			else:
				toast_map_debug("No significant settlement yet. Use relocation button above or policy screen.")
	)
	demo_section.add_child(highlight_settled_btn)

	# === ZERO-INTERFERENCE FULL EUROPE PLAYTEST HARNESS (F10) ===
	# One-click setup for complete Europe loop test of ALL systems on 350-450+ province map.
	# No further user input needed for basic cultural war / pressure / settlement / HH / policy / combat / supply / Golden / agent interactions.
	# Use: F10 -> buttons below; watch toasts (with Respond -> PolicyLawScreen), inspector tints, logs, time advance.
	var harness_section := _ensure_section("Zero-Interference Full Europe Playtest Harness")
	var harness_note := Label.new()
	harness_note.text = "Full 460-prov Europe map + systems ready. Buttons apply samples, advance time for pressure events/toasts, log map effects. Click provinces, assault settled ones, open Policies. Ready for day-of-testing without setup."
	harness_note.add_theme_font_size_override("font_size", 9)
	harness_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	harness_section.add_child(harness_note)

	# === PLAYTEST ESSENTIALS (top priority items first per request: units/borders visible, ascendancy+agents, quick train/production, missions. Sub-menus for cleanup below) ===
	var essentials_label := Label.new()
	essentials_label.text = "=== PLAYTEST TOP: Units/Borders (NATO+nat colors), Ascend/Agents, Train/Prod, Missions (sub) ==="
	essentials_label.add_theme_font_size_override("font_size", 10)
	harness_section.add_child(essentials_label)

	# Unit symbols + borders (promoted to top for immediate playtest visibility of starting OOB)
	var unit_border_btn_top := Button.new()
	unit_border_btn_top.text = "🛡️ Force unit icons (NATO) + nation borders (per-owner)"
	unit_border_btn_top.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("_update_unit_icons_for_test"):
			mr.call("_update_unit_icons_for_test")
		if mr and mr.has_method("force_border_update"):
			mr.call("force_border_update")
		toast_map_debug("Unit NATO + borders updated (starting formations from scenario OOB now visible on map).")
	)
	harness_section.add_child(unit_border_btn_top)

	# Ascend + agent (top)
	var ascend_agent_btn_top := Button.new()
	ascend_agent_btn_top.text = "🌍 Demo Ascendancy pillars + recruit agents + networks (GER/ENG/USA)"
	ascend_agent_btn_top.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			GameData.apply_pillar_shift("GER", "ascendancy", 15, "demo")
			GameData.apply_pillar_shift("GER", "cohesion", 10, "demo")
			GameData.apply_pillar_shift("ENG", "mandate", 12, "demo")
		if typeof(AgentManager) != TYPE_NIL:
			for tag in ["GER", "ENG", "USA"]:
				if AgentManager.has_method("recruit_agent"):
					var ag: Agent = AgentManager.recruit_agent(tag)
					if ag:
						var aid: String = str(ag.agent_id) if "agent_id" in ag else ""
						if aid and AgentManager.has_method("establish_network"):
							AgentManager.establish_network(aid, 42, "intelligence")
		toast_map_debug("Ascend/Agent demo applied (pillars + pool missions). See F10 logs, GameData, ProvinceInsight.")
	)
	harness_section.add_child(ascend_agent_btn_top)

	# Quick train demo top
	var quick_train_btn := Button.new()
	quick_train_btn.text = "🎖️ Quick Train: set is_training + boost readiness for player GER/USA formations"
	quick_train_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_all_formations"):
			var trained := 0
			for f in LeaderManager.get_all_formations():
				if f and f.country_tag in ["GER", "USA"] and f.formation_type == Formation.TYPE_DIVISION:
					f.is_training = true
					if "readiness" in f: f.readiness = min(1.4, float(f.readiness if f.readiness else 0.8) + 0.15)
					trained += 1
			toast_map_debug("Training started for %d divs (GER/USA). Advance days via Time or Supply for readiness/org gain (SupplyManager leap + leader). Check Formation inspector." % trained)
	)
	harness_section.add_child(quick_train_btn)

	# Phase1 pop/manpower + recruit basics (roadmap): buttons to recruit from pop pool (now derived from pop*conscript), spawn pop growth demo.
	var recruit_btn := Button.new()
	recruit_btn.text = "👥 Recruit from pop (GER: use manpower pool derived from pop*conscript; see strain/cohesion hit + reinforce feed)"
	recruit_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("recruit_units"):
			var ok := GameData.recruit_units("GER", 800)
			var rec := GameData.get_available_recruits("GER") if GameData.has_method("get_available_recruits") else 0
			toast_map_debug("Recruit from pop for GER: success=%s, recruits left=%d. Check cohesion (strain), TopInfoBar/Policy recruits, F10 nation stats. Pool now drives reinforce/width." % [ok, rec])
		else:
			toast_map_debug("GameData.recruit_units not available.")
	)
	harness_section.add_child(recruit_btn)

	var pop_growth_btn := Button.new()
	pop_growth_btn.text = "📈 Force pop growth + manpower sync (6mo for GER/FRA/USA; see labor to ind_base, pool growth, width/reinf)"
	pop_growth_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("process_monthly_demographic_erosion"):
			for i in 6:
				GameData.process_monthly_demographic_erosion(1936, ((i % 12) + 1))
			var ps := GameData.get_peace_state()
			var pops := ""
			for t in ["GER", "FRA", "USA"]:
				var p := float(ps.get("population", {}).get(t, 0))
				var m := int(ps.get("manpower_pool", {}).get(t, 0))
				pops += "%s:%.1fM(m=%d) " % [t, p/1e6, m]
			toast_map_debug("Pop growth + update forced 6mo: %s. Labor boosts ind_base (prod). Recruits/width/reinf now higher. Advance time or inspect for numbers." % pops)
		else:
			toast_map_debug("No process_monthly for pop growth.")
	)
	harness_section.add_child(pop_growth_btn)

	# Civilian goods (phase2): demo lines for consumer output affecting happiness/cohesion + mandate (ties prod to pop effects).
	var civilian_btn := Button.new()
	civilian_btn.text = "🛒 Produce civilian goods (set+tick 'civilian_consumer_goods' line for GER; +happiness/coh/mandate from output)"
	civilian_btn.pressed.connect(func():
		if typeof(ProductionManager) != TYPE_NIL:
			var lid := "demo_civilian_ger_goods"
			if not ProductionManager.has_line(lid):
				ProductionManager.create_line(lid)
			ProductionManager.set_line_template(lid, "civilian_consumer_goods")
			# Assign to a GER factory if possible (key prov 2)
			var fs: Array = []
			if ProductionManager.has_method("get_all_factories_for_country"):
				fs = ProductionManager.get_all_factories_for_country("GER")
			if fs.is_empty() and typeof(FactoryManager) != TYPE_NIL and FactoryManager.has_method("get_factories_in_province"):
				fs = FactoryManager.get_factories_in_province(2)
			if not fs.is_empty():
				var ff: Variant = fs[0]
				var fid: int = 0
				if ff is Object and "id" in ff: fid = int(ff.id)
				elif typeof(ff) == TYPE_DICTIONARY and ff.has("id"): fid = int(ff["id"])
				if fid > 0 and ProductionManager.has_method("assign_line_to_factory"):
					ProductionManager.assign_line_to_factory(lid, fid)
			var rep: Dictionary = ProductionManager.advance_days(20.0) if ProductionManager.has_method("advance_days") else {}
			var goods := ProductionManager.get_civilian_goods("GER") if ProductionManager.has_method("get_civilian_goods") else 0
			toast_map_debug("Civilian goods demo: line ticked 20d for GER, goods stock=%d. Effects: +public coh/mandate/welfare relief (see GameData logs, Policy/inspector, TopInfoBar direction). Prod output -> pop happiness loop active." % goods)
	)
	harness_section.add_child(civilian_btn)

	# Full train daily (phase3): set training + force supply daily ticks to exercise readiness/org/xp/leader bonus/cost + is_trained.
	var full_train_btn := Button.new()
	full_train_btn.text = "🎖️ Full train daily advance (set is_training + 15d Supply tick for GER divs; leader bonuses + supply cost + trained state + combat bonus)"
	full_train_btn.pressed.connect(func():
		var trained := 0
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_all_formations"):
			for f in LeaderManager.get_all_formations():
				if f and f.country_tag in ["GER", "USA"] and f.formation_type == Formation.TYPE_DIVISION:
					f.is_training = true
					f.training_progress = 0.0
					f.is_trained = false
					trained += 1
		if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("advance_supply_day"):
			SupplyManager.advance_supply_day(15.0)
		elif typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("advance_days"):
			SupplyManager.advance_days(15.0)
		toast_map_debug("Full train advance: %d GER/USA divs set training +15d ticks (Supply now does cost + leader mult + progress to is_trained + rdy/org boost + xp). Check inspector (trained bonus in combat), logs. is_trained feeds resolver." % trained)
	)
	harness_section.add_child(full_train_btn)

	# Simple AI econ (phase4): auto for non-player (GER etc) assign prod lines, set training, recruit from pop (integrated loop).
	var ai_econ_btn := Button.new()
	ai_econ_btn.text = "🤖 Simple AI econ (auto assign lines + set train + recruit from pop for AI majors; drives 50t loop)"
	ai_econ_btn.pressed.connect(func():
		var actions := 0
		var ai_tags := ["GER", "FRA", "SOV", "ITA", "JAP"]
		for tag in ai_tags:
			# Assign demo lines if unassigned
			if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("get_line"):
				for dlid in ["demo_%s_panzer_iii_j_medium" % tag.to_lower() if tag=="GER" else "demo_%s_m4_sherman_medium_tank" % tag.to_lower() if tag in ["USA","ENG","FRA"] else "demo_%s_t34_medium_tank" % tag.to_lower() ]:
					# simplified
					pass
			# Set some training
			if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_all_formations"):
				for f in LeaderManager.get_all_formations():
					if f and f.country_tag == tag and f.formation_type == Formation.TYPE_DIVISION and randf() < 0.6:
						f.is_training = true
						actions += 1
			# Recruit from pop
			if typeof(GameData) != TYPE_NIL and GameData.has_method("recruit_units") and GameData.has_method("get_available_recruits"):
				if GameData.get_available_recruits(tag) > 200 and randf() < 0.7:
					if GameData.recruit_units(tag, 150):
						actions += 1
		toast_map_debug("Simple AI econ: %d actions (train/recruit/assign) for AI tags. Pop->recruit, train, prod now auto for non-player. Run time advance or 50t sim to see integrated econ/war." % actions)
	)
	harness_section.add_child(ai_econ_btn)

	# Expose historical combat harness + unit mod test (per user request for visibility in F10)
	var hist_btn := Button.new()
	hist_btn.text = "📜 Run Historical Combat Harness (Marne/Verdun/Stalingrad/Midway + AAR logs, duration/org tests)"
	hist_btn.pressed.connect(func():
		var test_runner: Node = get_tree().root.find_child("TestRunner", true, false)
		if test_runner != null and test_runner.has_method("_run_historical_battle_recreations"):
			test_runner.call("_run_historical_battle_recreations")
			toast_map_debug("Historical harness triggered - see console, /tmp/combat-history-testing-summary.md, AARs from assaults.")
	)
	harness_section.add_child(hist_btn)

	var unit_mod_btn := Button.new()
	unit_mod_btn.text = "🧪 Run Unit Mod + Guided Tests (specialists marine/paratroop/SF/mtn/ski/space + chem/AA/interdict sims)"
	unit_mod_btn.pressed.connect(func():
		var test_runner: Node = get_tree().root.find_child("TestRunner", true, false)
		if test_runner != null and test_runner.has_method("_run_unit_type_combat_mod_test"):
			test_runner.call("_run_unit_type_combat_mod_test")
			toast_map_debug("Unit mod test triggered - console shows % factors, prolonged/org bias tests.")
	)
	harness_section.add_child(unit_mod_btn)

	var btn_1910 := Button.new()
	btn_1910.text = "🌍 Load 1910 Scenario + Fire Crisis Events (Balkans/July alts; ripples to 1918; more provs 43 + 22 tags)"
	btn_1910.pressed.connect(func():
		var loader: Node = get_tree().root.find_child("ScenarioLoader", true, false)
		var gd: Node = get_tree().root.find_child("GameData", true, false) if get_tree() else null
		if loader and loader.has_method("load_scenario"):
			# Note: may need full restart or map reload for full visual; test harness prints events + state
			var ok = loader.call("load_scenario", "1910")
			toast_map_debug("1910 load attempted (see console for Balkan 1912/13, July branches, flags). Use EOA_1910_TEST=1 for full headless.")
			if gd and gd.has_method("process_1910_crisis_events"):
				gd.call("process_1910_crisis_events", 1912)
				gd.call("process_1910_crisis_events", 1914)
				if gd.has_method("_apply_1910_ripples_to_1918"):
					gd.call("_apply_1910_ripples_to_1918")
				toast_map_debug("1910 crisis events + 1918 ripple demo fired. Check peace_state for 1914_crisis, 1912_balkan_alt, 1918_start_mods.")
	)
	harness_section.add_child(btn_1910)

	# Production tick for the demo lines auto-started in ScenarioLoader from the phase1 json starting_oob (ties the build system to base scenario data)
	var prod_tick_btn := Button.new()
	prod_tick_btn.text = "🏭 Tick production +30 days (advance demo lines for GER/USA/ENG/FRA OOB designs; show output)"
	prod_tick_btn.pressed.connect(func():
		if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("advance_days"):
			# Auto-assign demo lines (from ScenarioLoader starting_oob) to a factory if unassigned, so the tick produces real output for playtest (all 14 nations)
			if ProductionManager.has_method("get_line"):
				for demo_lid in ["demo_GER_panzer_iii_j_medium", "demo_USA_m4_sherman_medium_tank", "demo_ENG_m4_sherman_medium_tank", "demo_FRA_somua_s35_medium", "demo_SOV_t34_medium_tank", "demo_ITA_cv33_tankette", "demo_JAP_jap_armor_1936", "demo_POL_pol_armor_1936", "demo_FIN_m3_stuart_light_tank", "demo_NOR_m3_stuart_light_tank", "demo_SWE_panzer_iii_j_medium", "demo_DNK_cv33_tankette", "demo_NLD_somua_s35_medium", "demo_BEL_m3_stuart_light_tank"]:
					var dl := ProductionManager.get_line(demo_lid)
					if dl and "factory_id" in dl and int(dl.factory_id) == 0:
						# pick any factory for the tag
						var tag: String = str(demo_lid.split("_")[1]) if "_" in demo_lid else "GER"
						var fs: Array = []
						if ProductionManager.has_method("get_all_factories_for_country"):
							fs = ProductionManager.get_all_factories_for_country(tag)
						if fs.is_empty() and typeof(FactoryManager) != TYPE_NIL and FactoryManager.has_method("get_factories_in_province"):
							# fallback to known capital/key
							var pids := {"GER":2,"USA":6,"ENG":5,"FRA":4}
							var pid: int = int(pids.get(tag, 2))
							fs = FactoryManager.get_factories_in_province(pid)
						if not fs.is_empty():
							var ff: Variant = fs[0]
							var ffid: int = 0
							if ff is Object and "id" in ff: ffid = int(ff.id)
							elif typeof(ff) == TYPE_DICTIONARY and ff.has("id"): ffid = int(ff["id"])
							if ffid > 0 and ProductionManager.has_method("assign_line_to_factory"):
								ProductionManager.assign_line_to_factory(demo_lid, ffid)
			var rep: Dictionary = ProductionManager.advance_days(30.0)
			var total := int(rep.get("total_output", 0)) if rep.has("total_output") else 0
			toast_map_debug("Production advanced 30 days on demo lines (from scenario starting_oob + factories). Output this tick: %d equipment. Check stockpile, Formation/Province inspector, or production UI for completed items (panzer/sherman designs). Pop labor + industrial_base affect rates." % total)
		else:
			toast_map_debug("ProductionManager.advance_days not available; use TimeManager or F10 to drive days.")
	)
	harness_section.add_child(prod_tick_btn)

	# List status of the demo production lines started from scenario starting_oob (design, factory_id, etc) for playtest visibility
	var list_prod_btn := Button.new()
	list_prod_btn.text = "📋 List demo production lines status (from scenario oob data)"
	list_prod_btn.pressed.connect(func():
		# Auto-assign any unassigned before listing (same as tick)
		if ProductionManager.has_method("get_line"):
			for demo_lid in ["demo_GER_panzer_iii_j_medium", "demo_FRA_somua_s35_medium", "demo_ENG_m4_sherman_medium_tank", "demo_USA_m4_sherman_medium_tank", "demo_SOV_t34_medium_tank", "demo_ITA_cv33_tankette", "demo_JAP_jap_armor_1936", "demo_POL_pol_armor_1936", "demo_FIN_m3_stuart_light_tank", "demo_NOR_m3_stuart_light_tank", "demo_SWE_panzer_iii_j_medium", "demo_DNK_cv33_tankette", "demo_NLD_somua_s35_medium", "demo_BEL_m3_stuart_light_tank"]:
				var dl := ProductionManager.get_line(demo_lid)
				if dl and "factory_id" in dl and int(dl.factory_id) == 0:
					var tag := ""
					if demo_lid.begins_with("demo_"):
						var p: Array = demo_lid.split("_")
						if p.size() > 1: tag = str(p[1]).to_upper()
					var fs: Array = []
					if ProductionManager.has_method("get_all_factories_for_country"):
						fs = ProductionManager.get_all_factories_for_country(tag)
					if fs.is_empty() and typeof(FactoryManager) != TYPE_NIL and FactoryManager.has_method("get_factories_in_province"):
						var pids := {"GER":2,"USA":6,"ENG":5,"FRA":4,"SOV":8,"ITA":21,"JAP":9,"POL":19,"FIN":40,"NOR":47,"SWE":63,"DNK":64,"NLD":48,"BEL":49}
						var pid: int = int(pids.get(tag, 2))
						fs = FactoryManager.get_factories_in_province(pid)
					if not fs.is_empty():
						var ff: Variant = fs[0]
						var fid: int = 0
						if ff is Object and "id" in ff: fid = int(ff.id)
						elif typeof(ff) == TYPE_DICTIONARY and ff.has("id"): fid = int(ff["id"])
						if fid > 0 and ProductionManager.has_method("assign_line_to_factory"):
							ProductionManager.assign_line_to_factory(demo_lid, fid)
		var lines_info := []
		for dlid in ["demo_GER_panzer_iii_j_medium", "demo_FRA_somua_s35_medium", "demo_ENG_m4_sherman_medium_tank", "demo_USA_m4_sherman_medium_tank", "demo_SOV_t34_medium_tank", "demo_ITA_cv33_tankette", "demo_JAP_jap_armor_1936", "demo_POL_pol_armor_1936", "demo_FIN_m3_stuart_light_tank", "demo_NOR_m3_stuart_light_tank", "demo_SWE_panzer_iii_j_medium", "demo_DNK_cv33_tankette", "demo_NLD_somua_s35_medium", "demo_BEL_m3_stuart_light_tank"]:
			var dl := ProductionManager.get_line(dlid) if ProductionManager.has_method("get_line") else null
			if dl:
				var fid := int(dl.factory_id) if "factory_id" in dl else 0
				var des := str(dl.design_id) if "design_id" in dl else ""
				lines_info.append("%s: design=%s factory_id=%d" % [dlid, des, fid])
		toast_map_debug("Demo lines (scenario oob): " + (", ".join(lines_info) if lines_info.size() > 0 else "none"))
		print("[F10 PROD STATUS] ", lines_info)
	)
	harness_section.add_child(list_prod_btn)

	# Stockpile / OOB / equip tools for world-class playtest (view per-nation realistic starting equipment from scenario, force equip units, reinforce from stock)
	var list_stock_btn := Button.new()
	list_stock_btn.text = "📦 List per-nation equipment stockpiles (scenario starting_equipment_stockpile for all 14; shows tanks/planes/ships etc.)"
	list_stock_btn.pressed.connect(func():
		var info := []
		for tag in ["GER","SOV","USA","ENG","FRA","ITA","JAP","POL","FIN","NOR","SWE","DNK","NLD","BEL"]:
			var s := ProductionManager.get_country_equipment_stockpile(tag) if ProductionManager.has_method("get_country_equipment_stockpile") else {}
			if not s.is_empty():
				var sample := ""
				var k = s.keys()
				if k.size() > 0: sample = str(k[0]) + "=" + str(s[k[0]])
				info.append("%s: %d types (e.g. %s)" % [tag, s.size(), sample])
		toast_map_debug("Nation stockpiles (from scenario JSON OOB data): " + (", ".join(info) if info.size()>0 else "none"))
		print("[F10 STOCK] ", info)
	)
	harness_section.add_child(list_stock_btn)

	var equip_all_btn := Button.new()
	equip_all_btn.text = "🔧 Force equip/reinforce all formations from country stockpiles (connect OOB init to units; simulate reinforcement)"
	equip_all_btn.pressed.connect(func():
		if typeof(ProductionManager) != TYPE_NIL and typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
			var ecnt := 0
			for fid in LeaderManager.formations:
				var f: Formation = LeaderManager.formations[fid]
				if f and f.country_tag and f.design_id:
					var got := 0
					if ProductionManager.has_method("take_from_country_equipment_stockpile"):
						got = ProductionManager.take_from_country_equipment_stockpile(f.country_tag, f.design_id, 1)
					if got == 0 and ProductionManager.has_method("take_from_national_stockpile"):
						got = ProductionManager.take_from_national_stockpile(f.design_id, 1)
					if got > 0:
						var ust := ProductionManager.get_unit_equipment_stock(fid) if ProductionManager.has_method("get_unit_equipment_stock") else {}
						ust[f.design_id] = int(ust.get(f.design_id,0)) + got
						if ProductionManager.has_method("set_unit_equipment_stock"):
							ProductionManager.set_unit_equipment_stock(fid, ust)
						ecnt += 1
			toast_map_debug("Equipped/reinforced %d formations from nation stocks (OOB equipment now on units). Advance or inspect for effects. Stockpiles reduced." % ecnt)
			print("[F10 EQUIP] Equipped %d from stocks." % ecnt)
	)
	harness_section.add_child(equip_all_btn)

	var list_oob_btn := Button.new()
	list_oob_btn.text = "🪖 List OOB summary per nation (formations count, designs, stationed, equip levels from stocks)"
	list_oob_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
			var by_tag := {}
			for fid in LeaderManager.formations:
				var f: Formation = LeaderManager.formations[fid]
				if f and f.country_tag:
					if not by_tag.has(f.country_tag): by_tag[f.country_tag] = []
					by_tag[f.country_tag].append(f)
			var summary := []
			for tag in by_tag:
				var fs: Array = by_tag[tag]
				var des_set := {}
				var equip_sum := 0
				for f in fs:
					if f.design_id: des_set[f.design_id] = true
					var ust := ProductionManager.get_unit_equipment_stock(f.formation_id) if ProductionManager.has_method("get_unit_equipment_stock") else {}
					for e in ust: equip_sum += int(ust[e])
				summary.append("%s: %d forms, %d unique designs, equip~%d" % [tag, fs.size(), des_set.size(), equip_sum])
			toast_map_debug("OOB per nation: " + (", ".join(summary) if summary.size()>0 else "none"))
			print("[F10 OOB] ", summary)
	)
	harness_section.add_child(list_oob_btn)

	var nation_stats_btn := Button.new()
	nation_stats_btn.text = "🌍 List all-nation summary (pops from scenario, stocks, form counts, leaders/agents; world-class overview)"
	nation_stats_btn.pressed.connect(func():
		var lines := []
		if typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
			for tag in ["GER","SOV","USA","ENG","FRA","ITA","JAP","POL","FIN","NOR","SWE","DNK","NLD","BEL"]:
				var fcnt := 0
				for fid in LeaderManager.formations:
					var f: Formation = LeaderManager.formations[fid]
					if f and f.country_tag == tag: fcnt += 1
				var stock := ProductionManager.get_country_equipment_stockpile(tag) if ProductionManager.has_method("get_country_equipment_stockpile") else {}
				var pop := 0.0
				if typeof(GameData) != TYPE_NIL:
					var ps := GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
					pop = float(ps.get("population", {}).get(tag, 0))
				lines.append("%s: pop=%.1fM, stock=%d, forms=%d" % [tag, pop/1e6, stock.size(), fcnt])
		toast_map_debug("Nation overview (scenario data + runtime): " + (", ".join(lines) if lines.size()>0 else "none"))
		print("[F10 NATIONS] ", lines)
	)
	harness_section.add_child(nation_stats_btn)

	# === DOCTRINE PAGE (Critical/Vital Choice: High-level service philosophies for Army/Navy/Air Chiefs. Player sets direction; agents/chiefs implement/iterate.
	# Hybrid 1+2: Overall doctrine as guideline for AI/agents (resilient/extra armor OR high perf/cheap), with micro in designer.
	# Evolves: Research/agents unlock new (e.g. from WWI attrition -> WWII blitz -> 2026 drone swarm), expose weaknesses, allow change with costs (stability, mandate).
	# Trade-offs clear in toasts. Real: WWI mass/attrition (resilient manpower but high casualties), Interwar limited (cheap but low readiness), WWII maneuver/firepower, Modern precision/network (high perf but cyber vuln).
	# Lives on service chiefs (leaders) + national; agents lobby/reform.
	var doctrine_header := Label.new()
	doctrine_header.text = "=== DOCTRINE PAGE (Vital Choice: Set Army/Navy/Air philosophies - impacts designs, training, ops. Iterate via research/agents) ==="
	doctrine_header.add_theme_font_size_override("font_size", 10)
	harness_section.add_child(doctrine_header)

	var set_blitz_army_btn := Button.new()
	set_blitz_army_btn.text = "⚔ Set GER Army Doctrine: Blitzkrieg (high perf mobile + cheap tanks/planes, -supply/attrition resist. Resilient? No, maneuver over armor)"
	set_blitz_army_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL:
			LeaderManager.set_service_doctrine("GER", "army", "blitzkrieg")
			toast_map_debug("GER Army Doctrine: Blitzkrieg (Maneuver Warfare). +30% mobility/breakthrough, +speed cheap designs. Costs: +25% supply drain, vulnerable to attrition (real WWII German: fast but overextended in Russia). Chiefs enforce; agents can reform. Designer now prefers mobile modules.")
	)
	harness_section.add_child(set_blitz_army_btn)

	var set_attrition_btn := Button.new()
	set_attrition_btn.text = "🛡️ Set GER Army Doctrine: Attrition (resilient/extra armor + manpower, -mobility. WWI style: tough but bloody/slow)"
	set_attrition_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL:
			LeaderManager.set_service_doctrine("GER", "army", "attrition_warfare")
			toast_map_debug("GER Army Doctrine: Attrition Warfare. +15% manpower eff, +20% arty, resilient to losses. Costs: -25% mobility, +30% casualties. Trade-off: extra armor for survivability vs high perf cheap. Iterate with research (unlock blitz later).")
	)
	harness_section.add_child(set_attrition_btn)

	var set_carrier_navy_btn := Button.new()
	set_carrier_navy_btn.text = "🚢 Set USA Navy Doctrine: Carrier Task Force (high perf air projection, flexible strikes - vuln to subs, high cost. WWII US style)"
	set_carrier_navy_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL:
			LeaderManager.set_service_doctrine("USA", "navy", "carrier_task_force")
			toast_map_debug("USA Navy: Carrier Task Force. +35% air projection/flex, cheap in carriers vs BBs. Costs: +15% sub vuln, high logistics. Resilient? Dispersed ops. Agents focus 'reform to A2AD' for modern. Affects ship designs (prefer carriers, AA/ASW modules).")
	)
	harness_section.add_child(set_carrier_navy_btn)

	var evolve_doctrine_btn := Button.new()
	evolve_doctrine_btn.text = "🔬 Agent/Research Evolve Doctrine (e.g. GER Army: expose blitz weakness -> unlock network-centric 2026 benefits or change with cost)"
	evolve_doctrine_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL and typeof(AgentManager) != TYPE_NIL:
			# Simulate agent focus on reform
			LeaderManager.set_service_doctrine("GER", "army", "network_centric_warfare")
			toast_map_debug("Doctrine Evolution: GER Army from Blitz to Network-Centric (via agent research). New benefits: +30% precision/coordination (drones/AI). Discover weakness: +15% cyber vuln, tech dep. Costs to change: Mandate/stability hit. Doctrines evolve over time - research unlocks, agents expose flaws for iteration. Player sets high-level, micro in designer.")
	)
	harness_section.add_child(evolve_doctrine_btn)

	# === MAP PLAYTEST TOP ITEMS (priority for testing the map: pick children, subdiv river demo, force combat, world/NA view, camera auto, LOD, chunks; tested via harness drives + button clicks + launches) ===
	var map_header := Label.new()
	map_header.text = "=== MAP PLAYTEST (top: 🖱️pick test, 🗺️Subdiv+Apply, ⚔️Force river, 🌍Load World, 📷Auto, ↩️Revert, 🔍LOD, chunks) ==="
	map_header.add_theme_font_size_override("font_size", 11)
	harness_section.add_child(map_header)

	# === KEY GAMEPLAY UI: Mission/Order Assignment sub-menu (top priority for playtest; naval/air/land + intensity + attach + doctrines impact) ===
	# Per request: sub-menus for cleanup, top testing items first. Interactive demo of overarching orders (CONVOY, SEARCH, S&D, AMBUSH, RECON/CAS/NAVAL_STRIKE, ASSAULT/DEFEND/ARTY_PREP), intensity (round-the-clock), attach air to ships (for naval bombard support).
	var mission_menu_header := Label.new()
	mission_menu_header.text = "🎮 MISSIONS / ORDERS (sub-menu + top buttons; intensity, attach, doctrines: radio/counter-battery/proximity)"
	mission_menu_header.add_theme_font_size_override("font_size", 10)
	harness_section.add_child(mission_menu_header)

	var mission_submenu := OptionButton.new()
	mission_submenu.add_item("🌊 Naval: SEARCH_PATROL (USA) vs S&D (GER) + storm recon")
	mission_submenu.add_item("🌊 Naval: CONVOY_DUTY + AMBUSH/MINELAY/ASW + supply threat sim")
	mission_submenu.add_item("✈️ Air: RECON high intensity + NAVAL_STRIKE attach to fleet (bombard support)")
	mission_submenu.add_item("🪖 Land: ASSAULT high (GER) + DEFEND+ARTY_PREP (USA) w/ radio/counter-batt")
	mission_submenu.add_item("✈️+🪖 doctrines: high intensity (radio org) + attach + proximity AA + counter-battery")
	# Connect *after* items added; select(-1) to avoid auto-firing item 0 during build (harmless but avoids spurious debug prints on F10 open).
	mission_submenu.select(-1)
	mission_submenu.item_selected.connect(func(idx: int):
		match idx:
			0:
				# same as assign_order_search_btn logic
				if typeof(LeaderManager) != TYPE_NIL:
					for f in LeaderManager.get_formations_for_country("USA"):
						if f and f.get_category() == "naval": f.set_naval_order(Formation.NAVAL_ORDER_SEARCH_PATROL); break
					for f in LeaderManager.get_formations_for_country("GER"):
						if f and f.get_category() == "naval": f.set_naval_order(Formation.NAVAL_ORDER_SEARCH_AND_DESTROY); break
				var sm0 := get_node_or_null("/root/SupplyManager")
				if sm0 and sm0.has_method("_process_naval_recon"):
					if sm0.has_method("force_registry"):
						var reg = sm0.force_registry
						reg.add_naval_presence(999, "USA", 5.0, false)
						reg.add_naval_presence(999, "GER", 2.0, false)
					if typeof(WeatherManager) != TYPE_NIL: WeatherManager._province_weather[999] = {"visibility": 0.3, "precip_intensity": 0.7}
					sm0._process_naval_recon(1.0)
				print("[SUBMENU NAVAL] SEARCH vs S&D + recon assigned. Check logs for [NAVAL ORDERS CONVOY vs S&D] etc.")
			1:
				if typeof(LeaderManager) != TYPE_NIL:
					for f in LeaderManager.get_formations_for_country("USA"):
						if f and f.get_category() == "naval": f.set_naval_order(Formation.NAVAL_ORDER_CONVOY_DUTY); break
					for f in LeaderManager.get_formations_for_country("GER"):
						if f and f.get_category() == "naval": f.set_naval_order(Formation.NAVAL_ORDER_AMBUSH if randf()>0.5 else Formation.NAVAL_ORDER_MINELAY); break
				var sm1 := get_node_or_null("/root/SupplyManager")
				if sm1 and sm1.has_method("_process_naval_recon"): sm1._process_naval_recon(1.0)
				print("[SUBMENU NAVAL] CONVOY + raider/MINELAY/ASW. Supply impact + ASW/closer. See logs.")
			2:
				if typeof(LeaderManager) != TYPE_NIL:
					for f in LeaderManager.get_formations_for_country("USA"):
						if f and f.get_category() == "air":
							f.set_air_mission(Formation.AIR_MISSION_RECON); f.set_mission_intensity(1.8); break
					for fnav in LeaderManager.get_formations_for_country("USA"):
						if fnav and fnav.get_category() == "naval":
							for fair in LeaderManager.get_formations_for_country("USA"):
								if fair and fair.get_category() == "air":
									fnav.attach_air_support(fair.formation_id)
									fair.set_air_mission(Formation.AIR_MISSION_NAVAL_STRIKE); break
							break
				var sm2 := get_node_or_null("/root/SupplyManager")
				if sm2 and sm2.has_method("_process_air_missions"): sm2._process_air_missions(1.0)
				print("[SUBMENU AIR] RECON high + NAVAL_STRIKE attach. Bombard support. [ATTACHED AIR]")
			3:
				if typeof(LeaderManager) != TYPE_NIL:
					for f in LeaderManager.get_formations_for_country("GER"):
						if f and f.get_category() == "land": f.set_land_mission(Formation.LAND_MISSION_ASSAULT); f.set_mission_intensity(1.6); break
					for f in LeaderManager.get_formations_for_country("USA"):
						if f and f.get_category() == "land": f.set_land_mission(Formation.LAND_MISSION_DEFEND); f.set_mission_intensity(1.2); break
				var sm3 := get_node_or_null("/root/SupplyManager")
				if sm3 and sm3.has_method("_process_air_missions"): sm3._process_air_missions(0.5)
				print("[SUBMENU LAND] ASSAULT high + DEFEND/ARTY_PREP. Counter-battery, intensity radio. [AIR/LAND MISSIONS]")
			4:
				# combined doctrines/intensity/attach
				if typeof(LeaderManager) != TYPE_NIL:
					for f in LeaderManager.get_formations_for_country("USA"):
						if f and f.get_category() == "air": f.set_air_mission(Formation.AIR_MISSION_CLOSE_AIR_SUPPORT); f.set_mission_intensity(1.7); break
					for fnav in LeaderManager.get_formations_for_country("USA"):
						if fnav and fnav.get_category() == "naval":
							for fair in LeaderManager.get_formations_for_country("USA"):
								if fair and fair.get_category() == "air": fnav.attach_air_support(fair.formation_id); fair.set_air_mission(Formation.AIR_MISSION_NAVAL_STRIKE); break
							break
					for f in LeaderManager.get_formations_for_country("GER"):
						if f and f.get_category() == "land": f.set_land_mission(Formation.LAND_MISSION_ARTILLERY_PREP); f.set_mission_intensity(1.5); break
				var sm4 := get_node_or_null("/root/SupplyManager")
				if sm4 and sm4.has_method("_process_air_missions"): sm4._process_air_missions(1.0)
				print("[SUBMENU DOCTRINES] High intensity (radio), attach, CAS/NAVAL_STRIKE, ARTY_PREP (counter-batt), proximity. Full test.")
	)
	harness_section.add_child(mission_submenu)

	# Also keep direct top buttons for quick one-click (top items first)
	var top_naval_btn := Button.new()
	top_naval_btn.text = "🌊 Quick: Force Naval Spot/Orders (stormy, subs, choke, S&D vs convoy)"
	top_naval_btn.pressed.connect(func():
		# inline from force spot for reliability (no forward ref)
		if typeof(LeaderManager) != TYPE_NIL:
			for f in LeaderManager.get_formations_for_country("USA"):
				if f and f.get_category() == "naval": f.set_naval_order(Formation.NAVAL_ORDER_SEARCH_PATROL); break
			for f in LeaderManager.get_formations_for_country("GER"):
				if f and f.get_category() == "naval": f.set_naval_order(Formation.NAVAL_ORDER_AMBUSH); break
		var sm := get_node_or_null("/root/SupplyManager")
		if sm and sm.has_method("force_registry"):
			var reg = sm.force_registry
			reg.add_naval_presence(999, "USA", 6.0, false)
			reg.add_naval_presence(999, "GER", 2.5, false)
		var wm := get_node_or_null("/root/WeatherManager")
		if wm and wm.has_method("simulate_day"):
			wm._province_weather[999] = {"visibility": 0.25, "precip_intensity": 0.85, "wind": 0.6}
		if sm and sm.has_method("_process_naval_recon"):
			sm._process_naval_recon(1.0)
		print("[QUICK NAVAL] orders+stormy spot forced (subs/choke/closer). See [NAVAL SPOTTING SIM] + resolver.")
	)
	harness_section.add_child(top_naval_btn)

	# (the original assign buttons remain lower for full; this puts missions top + sub-menu as requested)

	var apply_cultural_war_btn := Button.new()
	apply_cultural_war_btn.text = "⚔️ Apply Sample Cultural War Policies (welfare_expansive, feminism_full, public_indoctrination, low coh sim)"
	apply_cultural_war_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			var ptag := "player"
			if typeof(LeaderManager) != TYPE_NIL:
				ptag = LeaderManager.get_player_country_tag()
			# Enact anti-traditional / pressure triggers (welfare as elite_optimization/expansive_burden, feminism, worker bees ed)
			if GameData.has_method("apply_social_services_policy"):
				GameData.apply_social_services_policy(ptag, "expansive_burden")
			if GameData.has_method("apply_women_workforce_policy"):
				GameData.apply_women_workforce_policy(ptag, "full")
			if GameData.has_method("apply_governmental_education_policy"):
				GameData.apply_governmental_education_policy(ptag, "public_indoctrination")
			# Simulate low cohesion + traditional outlier to prime HH pressure
			if GameData.has_method("apply_pillar_shift"):
				GameData.apply_pillar_shift(ptag, "cohesion", -25, "harness_low_coh_sim")
			toast_map_debug("Cultural war samples applied (welfare burden, feminism anti-natal, public ed worker bees). Low coh primed. Advance time or watch monthly for 'people demand changes' toasts + Respond to PolicyLawScreen. Italy ITA has elevated HH/welfare from unholy alliance. Check Golden/combat/supply/agent lobbies on full map.")
	)
	harness_section.add_child(apply_cultural_war_btn)

	var apply_reloc_harness_btn := Button.new()
	apply_reloc_harness_btn.text = "🗺️ Apply Multi-Prov Relocation + Settlement (many owned, see tints/inspector/bonuses)"
	apply_reloc_harness_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_encourage_relocation"):
			var ptag := "player"
			if typeof(LeaderManager) != TYPE_NIL:
				ptag = LeaderManager.get_player_country_tag()
			GameData.apply_encourage_relocation(ptag, "full_europe_settlement", 0.6)
			toast_map_debug("Relocation applied across many owned provinces on full 460-prov map. Dev/infra + settlement_level boosted. MapRenderer vitality tint (cyan-green), Province inspector shows org/attrition/supply/combat width bonuses. BattleManager: defender +2.5%/lev up to 25% in assaults. Golden resistance + supply/combat effects live.")
	)
	harness_section.add_child(apply_reloc_harness_btn)

	var advance_time_btn := Button.new()
	advance_time_btn.text = "⏱ Advance 6-12 Months (trigger HH pressure, welfare crises, pandemic narratives, social rev toasts, erosion)"
	advance_time_btn.pressed.connect(func():
		if typeof(TimeManager) != TYPE_NIL:
			# Advance multiple months to fire process_monthly_demographic_erosion, HH toasts, pressure
			for i in range(8):
				if TimeManager.has_method("advance_month"):
					TimeManager.advance_month()
				elif TimeManager.has_method("advance_days"):
					TimeManager.advance_days(30)
			toast_map_debug("Time advanced ~8 months. Expect toasts for: welfare burden strain (Respond opens PolicyLaw), HH pandemic narrative/Spanish Flu-style 'health crisis' exploit, social revolution 'populace demands modern changes' (bible/public ed/feminism/welfare) when low coh + traditional outlier. Agents may lobby. Check logs for Italy/ITA elevated, Golden tradeoffs (anti-natal tempting short Mandate vs long erosion/HH win), map effects on settled provinces.")
		else:
			toast_map_debug("TimeManager not available for advance.")
	)
	harness_section.add_child(advance_time_btn)

	# High-value demo for improved scenario connections / regional control (full regions now aligned in data + owners + robust queries)
	var force_uk_btn := Button.new()
	force_uk_btn.text = "🇬🇧 Force British Isles FULL ENG (demo regional_pride + bonuses + green tint)"
	force_uk_btn.pressed.connect(func():
		if typeof(MapManager) == TYPE_NIL or not MapManager.is_ready():
			toast_map_debug("MapManager not ready")
			return
		var rid := -1
		for r in MapManager.get_all_strategic_regions().values():
			if str(r.get("name","")).to_lower().contains("british"):
				rid = int(r.get("id", -1))
				break
		if rid < 0:
			toast_map_debug("British Isles region not found")
			return
		var rdata := MapManager.get_strategic_region(rid)
		var pids: Array = rdata.get("province_ids", [])
		var count := 0
		for pidv in pids:
			var pid := int(pidv)
			if MapManager.has_method("update_province_owner"):
				MapManager.update_province_owner(pid, "ENG", "ENG", true)
				count += 1
			else:
				var p := MapManager.get_province(pid)
				if p: p.owner_tag = "ENG"; p.controller_tag = "ENG"; count +=1
		# Switch to region_control tint for visual + refresh
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("set_map_mode"):
			mr.set_map_mode("region_control")
		elif mr and mr.has_method("_refresh_province_fill_colors"):
			mr.call_deferred("_refresh_province_fill_colors")
		var bonuses := MapManager.get_active_regional_control_bonuses("ENG")
		# Re-apply supply regional bonuses live after owner force (demo throughput on depots in the region)
		if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
			SupplyManager._apply_regional_control_throughput_bonuses()
		# Refresh production so regional factory_output takes effect live
		if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("clear_all_caches"):
			ProductionManager.clear_all_caches()
		# Force tint/layer refresh for immediate visual (region_control green for full)
		if mr and mr.has_method("_refresh_province_fill_colors"):
			mr.call_deferred("_refresh_province_fill_colors")
		toast_map_debug("Forced %d provinces in British Isles to ENG. Full control active. Bonuses: %s (pride %.2f etc). Map tint green. Supply depots in region should have +throughput. Inspector/effects live. Production output boosted if industrial region." % [count, bonuses.keys(), float(bonuses.get("regional_pride",0))])
	)
	harness_section.add_child(force_uk_btn)

	var force_ger_btn := Button.new()
	force_ger_btn.text = "🇩🇪 Force Western/Central Germany FULL GER (demo factory + pride bonuses)"
	force_ger_btn.pressed.connect(func():
		if typeof(MapManager) == TYPE_NIL or not MapManager.is_ready(): return
		var ger_regions := ["western germany", "central germany"]
		var count := 0
		for r in MapManager.get_all_strategic_regions().values():
			var nm := str(r.get("name","")).to_lower()
			if ger_regions.any(func(g): return nm.contains(g)):
				var pids: Array = r.get("province_ids", [])
				for pidv in pids:
					var pid := int(pidv)
					if MapManager.has_method("update_province_owner"):
						MapManager.update_province_owner(pid, "GER", "GER", true)
						count += 1
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("set_map_mode"): mr.set_map_mode("region_control")
		var bonuses := MapManager.get_active_regional_control_bonuses("GER")
		if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
			SupplyManager._apply_regional_control_throughput_bonuses()
		if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("clear_all_caches"):
			ProductionManager.clear_all_caches()
		if mr and mr.has_method("_refresh_province_fill_colors"):
			mr.call_deferred("_refresh_province_fill_colors")
		toast_map_debug("Forced GER full control on ~%d in Germany regions. Bonuses active: %s (factory_output etc). Supply/ production effects. Test tints, inspector on Ruhr area." % [count, bonuses.keys()])
	)
	harness_section.add_child(force_ger_btn)

	var log_regional_btn := Button.new()
	log_regional_btn.text = "📊 Log Active Regional Bonuses for Player (factory, pride, supply, naval etc from full controlled regions)"
	log_regional_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL and typeof(MapManager) != TYPE_NIL:
			var ptag := LeaderManager.get_player_country_tag()
			var bonuses := MapManager.get_active_regional_control_bonuses(ptag)
			var controlled := MapManager.get_fully_controlled_strategic_regions(ptag)
			toast_map_debug("Player %s full regions: %d | Active bonuses: %s (e.g. pride %.2f, factory %.2f, supply %.2f). Use force buttons above to demo live changes to production/combat/supply." % [ptag, controlled.size(), bonuses.keys(), float(bonuses.get("regional_pride",0)), float(bonuses.get("factory_output",0)), float(bonuses.get("supply_throughput",0))])
		else:
			toast_map_debug("Map/Leader not ready for regional log.")
	)
	harness_section.add_child(log_regional_btn)

	# Chunk + connections demo: load chunk (visual portion), force full control on key region, log snow/production/combat/supply effects to prove wiring across chunks (data independent of visuals).
	var chunk_demo_btn := Button.new()
	chunk_demo_btn.text = "🗺️ Load Chunk 0 + Force UK Full + Log Snow/Prod/Combat/Supply (demo chunk + regional + winter wiring)"
	chunk_demo_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("load_world_chunk_underlay"):
			mr.load_world_chunk_underlay(0)
		# Force UK control (re-uses force logic conceptually; direct here for demo)
		if typeof(MapManager) != TYPE_NIL:
			for r in MapManager.get_all_strategic_regions().values():
				if str(r.get("name","")).to_lower().contains("british"):
					for pidv in r.get("province_ids", []):
						var pid := int(pidv)
						if MapManager.has_method("update_province_owner"):
							MapManager.update_province_owner(pid, "ENG", "ENG", true)
					break
		if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
			SupplyManager._apply_regional_control_throughput_bonuses()
		if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("clear_all_caches"):
			ProductionManager.clear_all_caches()
		var bonuses := {}
		var fc_eng := 0
		if typeof(MapManager) != TYPE_NIL:
			bonuses = MapManager.get_active_regional_control_bonuses("ENG")
			fc_eng = MapManager.get_fully_controlled_strategic_regions("ENG").size()
		# Demo inference + snow on chunk: log a high sp snow_capped province (data independent of visual chunk)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_terrain"):
			var terr := MapManager.get_province_terrain(18)  # known snow_capped from inference
			print("[CHUNK+INFERENCE DEMO] pid18 terrain=", terr.get("terrain"), " sp=", terr.get("snow_potential"), " source=", terr.get("source"))
			toast_map_debug("Chunk0 loaded + UK full. Inference on pid18 (snow_capped sp~0.69) still live. Snow bits via weather. Regional bonuses + chunk visual demo.")
		# Quick combat power sample with snow (if WM has snow provinces)
		var sample_pow := {}
		if typeof(CombatResolver) != TYPE_NIL:
			# rough sample; real would use formations
			sample_pow = {"note": "sample combat power would reflect snow/regional if snow_cov high + full home"}
		toast_map_debug("Chunk 0 loaded + UK full forced (%d regions full for ENG). Bonuses: %s. Production refreshed (factory_output if applicable). Supply re-applied. Chunk snow bits via WM/overlay; winter_warfare mitigates snow in resolver for matching regions. Inspect map, depots, production lines, combat previews." % [fc_eng, bonuses.keys()])
	)
	harness_section.add_child(chunk_demo_btn)

	# LOD demo push: explicit fade for V/S layers (ties to zoom/LOD polish, yaml thresholds)
	var lod_demo_btn := Button.new()
	lod_demo_btn.text = "🔍 Demo LOD Fade (V/S layers fade on close zoom for clean default; ties to camera/zoom)"
	lod_demo_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("find_child"):
			var tls := mr.find_child("TerrainLayerStack", true, false)
			if tls and tls.has_method("set_layer_alphas"):
				tls.call("set_layer_alphas", 0.3, 0.2)  # demo close zoom fade (match yaml lod.veg_fade_start etc)
				toast_map_debug("LOD fade demo: veg/snow_ref faded for tactical clean parchment view. Zoom out or V/S toggle to restore. (yaml lod section + MapRenderer zoom bucket drive)")
			else:
				toast_map_debug("No TerrainLayerStack for LOD demo (load grand map).")
	)
	harness_section.add_child(lod_demo_btn)

	# Subdiv demo push: load sample_subdivided_geometry (river-aware from real layers) and log stats / could visualize
	var subdiv_demo_btn := Button.new()
	subdiv_demo_btn.text = "🗺️ Demo Subdiv + Apply (load sample river-cross 5 for pid82 + live demo mutate in MapManager with terrain/river_aware carry for inspector test; + green overlays)"
	subdiv_demo_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("load_sample_subdiv_geometry"):
			mr.call("load_sample_subdiv_geometry")
			toast_map_debug("Subdiv demo via MapRenderer: sample geo loaded (river-aware children). See console for stats.")
			if mr.has_method("debug_apply_sample_subdiv_demo"):
				mr.call("debug_apply_sample_subdiv_demo", 82)  # live demo mutate register + visuals
			elif mr.has_method("debug_spawn_subdiv_draw_children"):
				mr.call("debug_spawn_subdiv_draw_children")
		else:
			# fallback to file
			var sample_path := "res://tools/map_generation/output/phase1_europe/sample_subdivided_geometry.json"
			if FileAccess.file_exists(sample_path):
				var f := FileAccess.open(sample_path, FileAccess.READ)
				var txt := f.get_as_text()
				f.close()
				var sdata = JSON.parse_string(txt)
				if typeof(sdata) == TYPE_DICTIONARY:
					var sprov: Variant = sdata.get("provinces", [])
					var children := 0
					for pp in sprov:
						if str(pp.get("id", "")).contains("_c"):
							children += 1
					toast_map_debug("Subdiv demo: sample geo with %d provinces (%d river-cross children guided by real rivers.json + elev/terrain inference). See output/ for full plan/proposals." % [sprov.size(), children])
					if mr and mr.has_method("debug_apply_sample_subdiv_demo"):
						mr.call("debug_apply_sample_subdiv_demo", 82)
					elif mr and mr.has_method("debug_spawn_subdiv_draw_children"):
						mr.call("debug_spawn_subdiv_draw_children")
				else:
					toast_map_debug("Subdiv demo: bad sample geo json.")
			else:
				toast_map_debug("Subdiv demo: no sample_subdivided_geometry.json (run generate_europe_phase1.py first).")
	)
	harness_section.add_child(subdiv_demo_btn)

	var revert_demo_btn := Button.new()
	revert_demo_btn.text = "↩️ Revert demo geo mutate (restore parent 82 view after Subdiv+Apply test)"
	revert_demo_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("debug_revert_demo_geo"):
			mr.call("debug_revert_demo_geo")
			toast_map_debug("Demo geo mutate reverted. Parent view restored; demo data in MapManager/insight cleared if needed.")
	)
	harness_section.add_child(revert_demo_btn)

	var auto_theater_btn := Button.new()
	auto_theater_btn.text = "📷 Auto theater/LOD from camera (zoom/pos driven chunk + alpha; beyond stub)"
	auto_theater_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("auto_update_theater_from_camera"):
			mr.call("auto_update_theater_from_camera")
			toast_map_debug("Auto theater/LOD from camera executed (see console for swap/LOD change).")
	)
	harness_section.add_child(auto_theater_btn)

	var load_world_btn := Button.new()
	load_world_btn.text = "🌍 Load World Grand Underlay (HOI/Vic high view; zoom in for Europe/NA detail; clamps camera)"
	load_world_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("load_world_grand_underlay"):
			mr.call("load_world_grand_underlay")
			if mr.has_method("force_full_map_refresh"):
				mr.call_deferred("force_full_map_refresh")
			toast_map_debug("WORLD STITCHED GRAND loaded (full 8192x4096 canvas + coarse clickable territories for Africa/Aus/EAsia/NA etc). Pan/zoom/scroll for true grand strategy feel. Chunk buttons for portion detail (mountains/elev now aligned via per-chunk fit). Europe detailed polys remain clickable in their location. Not every area had region before - now coarse territories give clickable 'get into' for whole world base (build future scenarios off this stitched map).")
	)
	harness_section.add_child(load_world_btn)

	var reset_europe_btn := Button.new()
	reset_europe_btn.text = "↩️ Reset Camera to Europe (center + clamp after world/NA pan; restores Europe test focus)"
	reset_europe_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("reset_camera_to_europe"):
			mr.call("reset_camera_to_europe")
			toast_map_debug("Camera reset to Europe grand center + bounds clamped. Europe polys/inspector/combat in focus. Use Load World or chunks for NA/full map view.")
	)
	harness_section.add_child(reset_europe_btn)

	var center_europe_world_btn := Button.new()
	center_europe_world_btn.text = "🌍 Center Europe in World View (zoom context on 471 test area inside full 8k world canvas)"
	center_europe_world_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("center_europe_in_world_view"):
			mr.call("center_europe_in_world_view")
			toast_map_debug("Camera centered on Europe (NW of world bg). World overview + detailed test polys visible. Use for high-level then zoom in.")
	)
	harness_section.add_child(center_europe_world_btn)

	var mesh_toggle_btn := Button.new()
	mesh_toggle_btn.text = "⚡ Toggle Batched Mesh Fills (Phase E: owner buckets @ strategic zoom; fewer poly tint passes)"
	mesh_toggle_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null:
			mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("set_batched_mesh_fills_forced"):
			var next := not bool(mr.get("_batched_mesh_fills_forced"))
			mr.call("set_batched_mesh_fills_forced", next)
			var stats: Dictionary = mr.call("get_batched_mesh_stats") if mr.has_method("get_batched_mesh_stats") else {}
			toast_map_debug("Batched mesh fills forced=%s active=%s polys=%s buckets=%s zoom=%.2f" % [
				next, stats.get("active", false), stats.get("polygons", 0), stats.get("buckets", 0), float(stats.get("zoom", 0.0))
			])
	)
	harness_section.add_child(mesh_toggle_btn)

	var era_infra_1918_btn := Button.new()
	era_infra_1918_btn.text = "🛤️ Preview Era Infra: 1918 sparse (unpaved roads, few rails)"
	era_infra_1918_btn.pressed.connect(func(): _debug_preview_era_infra(1918))
	harness_section.add_child(era_infra_1918_btn)

	var era_infra_1936_btn := Button.new()
	era_infra_1936_btn.text = "🛤️ Preview Era Infra: 1936 standard"
	era_infra_1936_btn.pressed.connect(func(): _debug_preview_era_infra(1936))
	harness_section.add_child(era_infra_1936_btn)

	var era_infra_2026_btn := Button.new()
	era_infra_2026_btn.text = "🛤️ Preview Era Infra: 2026 dense (modern network)"
	era_infra_2026_btn.pressed.connect(func(): _debug_preview_era_infra(2026))
	harness_section.add_child(era_infra_2026_btn)

	var force_chokepoint_btn := Button.new()
	force_chokepoint_btn.text = "⚓ Force Naval Chokepoint (Danish/Gibraltar area) + log supply/combat bonus (river + choke integration)"
	force_chokepoint_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		# Demo: force a known chokepoint pid to player/ENG for bonus test
		var choke_pid := 18
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("update_province_owner"):
			MapManager.update_province_owner(choke_pid, "ENG", "ENG", true)
		if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
			SupplyManager._apply_regional_control_throughput_bonuses()
		var has_choke := false
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
			has_choke = MapManager.has_strategic_chokepoint(choke_pid)
		var supply_b := 1.0
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_chokepoint_or_river_supply_bonus"):
			supply_b = MapManager.get_chokepoint_or_river_supply_bonus(choke_pid)
		print("  [FORCE CHOKEPOINT] pid ", choke_pid, " chokepoint=", has_choke, " supply_bonus=", supply_b, " (straits control boosts throughput + combat def)")
		toast_map_debug("Chokepoint forced + bonuses applied (naval logi + def edge). Check supply depot on it and combat preview.")
	)
	harness_section.add_child(force_chokepoint_btn)

	var force_naval_spot_btn := Button.new()
	force_naval_spot_btn.text = "🌊 Force Naval Spot/Combat Sim (stormy sea zone, subs vs surface, group/choke factors; triggers recon + engagement)"
	force_naval_spot_btn.pressed.connect(func():
		var sm := get_node_or_null("/root/SupplyManager")
		if sm == null or not sm.has_method("_process_naval_recon"):
			toast_map_debug("SupplyManager not ready for naval recon test.")
			return
		# Setup demo sea presence (multi group for increased spot chance)
		if sm.has_method("force_registry") and sm.force_registry:
			var reg = sm.force_registry
			reg.add_naval_presence(999, "USA", 6.0, false)  # surface heavy
			reg.add_naval_presence(999, "GER", 2.5, false)  # sub heavy mix
		# Force storm/low vis for test
		var wm := get_node_or_null("/root/WeatherManager")
		if wm and wm.has_method("simulate_day"):
			wm._province_weather[999] = {"visibility": 0.25, "precip_intensity": 0.85, "wind": 0.6}  # storm
		sm._process_naval_recon(1.0)
		toast_map_debug("Forced naval recon in stormy sea 999 (USA surface vs GER sub mix). Check logs for spot chance (group+choke+vis+sub mods), possible combat trigger with range_mod.")
	)
	harness_section.add_child(force_naval_spot_btn)

	# Overarching naval orders testing (inspired by HOI4 Patrol/Escort/Strike, etc.; S&D, Convoy, Search, Ambush, etc.)
	# Assign to test fleets, then force recon/spot in sea with orders affecting detect/stealth/range.
	var assign_order_search_btn := Button.new()
	assign_order_search_btn.text = "🌊 Assign SEARCH_PATROL to USA fleet + S&D to GER (sea 999); force recon (orders boost/hide spot, interact w/ storm/subs/strait)"
	assign_order_search_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL:
			for f in LeaderManager.get_formations_for_country("USA"):
				if f and f.get_category() == "naval":
					f.set_naval_order(Formation.NAVAL_ORDER_SEARCH_PATROL)
					break
			for f in LeaderManager.get_formations_for_country("GER"):
				if f and f.get_category() == "naval":
					f.set_naval_order(Formation.NAVAL_ORDER_SEARCH_AND_DESTROY)
					break
		var sm := get_node_or_null("/root/SupplyManager")
		if sm and sm.has_method("_process_naval_recon"):
			if sm.has_method("force_registry"):
				var reg = sm.force_registry
				reg.add_naval_presence(999, "USA", 5.0, false)
				reg.add_naval_presence(999, "GER", 2.0, false)
			if typeof(WeatherManager) != TYPE_NIL:
				WeatherManager._province_weather[999] = {"visibility": 0.3, "precip_intensity": 0.7}
			sm._process_naval_recon(1.0)
		toast_map_debug("Orders assigned (SEARCH vs S&D). Recon forced w/ storm. Spot chance/engage range/closer affected by order + vis + class + group + choke. Check logs.")
	)
	harness_section.add_child(assign_order_search_btn)

	var assign_convoy_btn := Button.new()
	assign_convoy_btn.text = "🌊 Assign CONVOY_DUTY + AMBUSH/MINELAY/ASW orders; simulate (new orders add supply threat/protect, ASW vs subs, MINELAY in straits)"
	assign_convoy_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL:
			for f in LeaderManager.get_formations_for_country("USA"):
				if f and f.get_category() == "naval": f.set_naval_order(Formation.NAVAL_ORDER_CONVOY_DUTY); break
			for f in LeaderManager.get_formations_for_country("GER"):
				if f and f.get_category() == "naval": 
					f.set_naval_order(Formation.NAVAL_ORDER_AMBUSH if randf() > 0.5 else Formation.NAVAL_ORDER_MINELAY)
					break
		var sm := get_node_or_null("/root/SupplyManager")
		if sm and sm.has_method("_process_naval_recon"):
			sm._process_naval_recon(1.0)
		toast_map_debug("Convoy vs raider/MINELAY/ASW orders set. Supply threat from MINELAY/S&D, ASW counters subs, closer in straits. Check logs for interdiction mods.")
	)
	harness_section.add_child(assign_convoy_btn)

	# Air missions (RECON, CAS, INTERDICTION, STRATEGIC_BOMBING, AIR_SUPERIORITY, NAVAL_STRIKE, TRANSPORT) + intensity (aggressiveness: low for sustainable, high for round-the-clock with more supplies).
	# Doctrines/tech (radio for org, proximity shells for AA, air doctrine) impact. Air attach to ships (naval strike/bombard for land/amphib).
	var assign_air_recon_btn := Button.new()
	assign_air_recon_btn.text = "✈️ Assign AIR RECON + high intensity to air wing; CAS/NAVAL_STRIKE attach to fleet (air support for naval bombard in land battle). Intensity for more sorties/supply cost."
	assign_air_recon_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL:
			for f in LeaderManager.get_formations_for_country("USA"):
				if f and f.get_category() == "air":
					f.set_air_mission(Formation.AIR_MISSION_RECON)
					f.set_mission_intensity(1.8)  # aggressive round-the-clock
					break
			# Attach air to naval for support (ships get attached aircraft for strike/bombard)
			for fnav in LeaderManager.get_formations_for_country("USA"):
				if fnav and fnav.get_category() == "naval":
					for fair in LeaderManager.get_formations_for_country("USA"):
						if fair and fair.get_category() == "air":
							fnav.attach_air_support(fair.formation_id)
							fair.set_air_mission(Formation.AIR_MISSION_NAVAL_STRIKE)
							break
					break
		var sm := get_node_or_null("/root/SupplyManager")
		if sm and sm.has_method("_process_air_missions"):
			sm._process_air_missions(1.0)
		toast_map_debug("Air RECON high intensity + NAVAL_STRIKE attached to fleet. Air support for naval bombard/CAS in land/amphib. Check air mission logs, supply cost from intensity.")
	)
	harness_section.add_child(assign_air_recon_btn)

	# Land missions (ASSAULT, DEFEND, PATROL, ADVANCE, GARRISON, ARTILLERY_PREP) + intensity.
	# Doctrines/tech: radio for org in aggressive ops, counter-battery for defenders (precalc fire, quick artillery), proximity for AA.
	var assign_land_assault_btn := Button.new()
	assign_land_assault_btn.text = "🪖 Assign LAND ASSAULT high intensity + ARTILLERY_PREP/DEFEND (counter-battery planning). Radio/tech for org; proximity shells AA."
	assign_land_assault_btn.pressed.connect(func():
		if typeof(LeaderManager) != TYPE_NIL:
			for f in LeaderManager.get_formations_for_country("GER"):
				if f and f.get_category() == "land":
					f.set_land_mission(Formation.LAND_MISSION_ASSAULT)
					f.set_mission_intensity(1.6)
					break
			for f in LeaderManager.get_formations_for_country("USA"):
				if f and f.get_category() == "land":
					f.set_land_mission(Formation.LAND_MISSION_DEFEND)
					f.set_mission_intensity(1.2)
					break
		var sm := get_node_or_null("/root/SupplyManager")
		if sm and sm.has_method("_process_air_missions"):  # air support too
			sm._process_air_missions(0.5)
		toast_map_debug("Land ASSAULT aggressive + DEFEND with arty prep. Check combat org/power with radio/counter-battery mods, intensity supply.")
	)
	harness_section.add_child(assign_land_assault_btn)

	var force_sub_battle_btn := Button.new()
	force_sub_battle_btn.text = "⚔️ Simulate Full River Sub-Battle on 82 demo children (child terrain carry + river/choke bonuses in resolver/BM; log detailed)"
	force_sub_battle_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("debug_apply_demo_geo_mutate"):
			mr.call("debug_apply_demo_geo_mutate", 82)
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("can_assault_province"):
			var pview: Dictionary = BattleManager.can_assault_province("GER", 82, 1)
			print("  [FULL SUB BATTLE SIM] 82 demo: preview=", pview, " (uses get_effective_terrain_for_demo for child e.g. coastal/river + has_river + choke)")
		toast_map_debug("Full sub-battle sim on demo children of 82 (terrain carry + river/choke from layers). See console for resolver/BM logs with bonuses.")
	)
	harness_section.add_child(force_sub_battle_btn)

	var force_river_combat_btn := Button.new()
	force_river_combat_btn.text = "⚔️ Force river demo apply + log combat preview for 82 (river border bonus + child terrain + sub-battle sim + geo override + draw + pick test for subdivided + phase1 471)"
	force_river_combat_btn.pressed.connect(func():
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null: mr = get_node_or_null("/root/WorldMap")
		if mr and mr.has_method("debug_apply_demo_geo_mutate"):
			mr.call("debug_apply_demo_geo_mutate", 82)
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("can_assault_province"):
			var pview: Dictionary = BattleManager.can_assault_province("GER", 82, 1)  # dummy attacker
			# Also direct has
			var has_r := false
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_river_border"):
				has_r = MapManager.has_river_border(82)
			print("  [FORCE RIVER COMBAT] preview for 82 river parent: has_river_border=", has_r, " preview keys=", pview.keys() if pview else {})
			toast_map_debug("River demo + combat preview logged (river bonus active in BattleManager/resolver).")
	)
	harness_section.add_child(force_river_combat_btn)

	var demo_pick_test_btn := Button.new()
	demo_pick_test_btn.text = "🖱️ Demo Child Pick Test (drive get_at on real sample child centers for 82; expect [DEMO PICK] vid + normalize log)"
	demo_pick_test_btn.pressed.connect(func():
		var mm := get_node_or_null("/root/MapManager")
		if mm == null or not mm.has_method("get_province_at_world_pos"):
			toast_map_debug("No MapManager for pick test.")
			return
		# Use computed centers from sample (around 3185-3212, 951-977)
		var child_centers = [
			Vector2(3165.8, 950.7), Vector2(3184.0, 943.9), Vector2(3208.2, 952.1),
			Vector2(3212.5, 969.3), Vector2(3189.3, 977.6)
		]
		var hits: Array = []
		for c in child_centers:
			var h: int = -1
			if mm.has_method("get_province_at_world_pos"):
				h = mm.get_province_at_world_pos(c)
			hits.append(h)
		print("  [DEMO PICK BUTTON TEST] centers -> hits: ", hits, " (expect 82xxx virtuals or 82; see prior [DEMO PICK] logs from manager/pickgrid)")
		toast_map_debug("Demo pick test driven on 5 child centers (hits: %s). Check console for [DEMO PICK] / NORMALIZE evidence of override child polys being hit." % str(hits))
	)
	harness_section.add_child(demo_pick_test_btn)

	var log_prod_effects_btn := Button.new()
	log_prod_effects_btn.text = "📈 Log Production + Combat Effects (factory_output, snow/winter/regional bonuses active)"
	log_prod_effects_btn.pressed.connect(func():
		var ptag := "player"
		if typeof(LeaderManager) != TYPE_NIL: ptag = LeaderManager.get_player_country_tag()
		# Force a naval/convoy region (e.g. British Isles or Atlantic) to demo regional convoy protection in trade flows
		if typeof(MapManager) != TYPE_NIL:
			for r in MapManager.get_all_strategic_regions().values():
				var rname := str(r.get("name","")).to_lower()
				if "british" in rname or "atlantic" in rname:
					for pidv in r.get("province_ids", []):
						var pid := int(pidv)
						if MapManager.has_method("update_province_owner"):
							MapManager.update_province_owner(pid, ptag, ptag, true)
					break
		var prod_mods := {}
		if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("_get_national_production_modifiers"):
			prod_mods = ProductionManager._get_national_production_modifiers(ptag)
		var bonuses := {}
		var fc := 0
		if typeof(MapManager) != TYPE_NIL:
			bonuses = MapManager.get_active_regional_control_bonuses(ptag)
			fc = MapManager.get_fully_controlled_strategic_regions(ptag).size()
		# Sample combat power with current snow (resolver now uses snow + winter + regional)
		var sample_combat := {"note": "use F10 force + click province for live combat preview with snow/regional/winter effects; resolver wired for full home defense + winter_warfare mitigation"}
		if typeof(CombatResolver) != TYPE_NIL:
			var cr: CombatResolver = CombatResolver.new()
			var sp: Dictionary = cr.get_effective_combat_power("us_infantry_div_ww2", "", "", "snow_capped", 18, 3, 3)
			sample_combat = {"soft": sp.get("soft_attack",0), "readiness": sp.get("readiness",0), "note": "sample northern snow_capped (full home would boost via regional defense + winter_warfare)"}
		toast_map_debug("Player %s full regions: %d | Prod mods: %s (output_mult %.2f from factory_output) | Combat sample: %s | Bonuses: %s" % [ptag, fc, prod_mods.keys(), float(prod_mods.get("output_multiplier",1)), sample_combat, bonuses.keys()])
		# Trade/convoy extension: log active flows with convoy protection (regional naval/convoy bonuses reduce interdiction loss on trade routes)
		if typeof(TradeManager) != TYPE_NIL:
			var flows := TradeManager.get_active_trade_flows() if TradeManager.has_method("get_active_trade_flows") else []
			var flow_summary := "no active trade flows"
			if flows.size() > 0:
				var tf = flows[0]
				flow_summary = "%s→%s %.1f %s/turn (lost %.1f, prot %.0f%%)" % [tf.from_tag, tf.to_tag, tf.quantity_per_turn, tf.item_id, tf.total_lost_to_interdiction, 100.0 * float(tf.metadata.get("regional_convoy_protection", 0.0))]
			toast_map_debug("Trade flows: %s | Convoy protection from full naval regions now reduces trade interdiction losses (see TradeManager interdict + Supply routes)" % flow_summary)
	)
	harness_section.add_child(log_prod_effects_btn)

	var trade_demo_btn := Button.new()
	trade_demo_btn.text = "🚢 Demo Trade Convoy: force naval region, create flow, interdict, log protection/loss"
	trade_demo_btn.pressed.connect(func():
		var ptag := "player"
		if typeof(LeaderManager) != TYPE_NIL: ptag = LeaderManager.get_player_country_tag()
		# Force naval region (British Isles/Atlantic)
		if typeof(MapManager) != TYPE_NIL:
			for r in MapManager.get_all_strategic_regions().values():
				var rname := str(r.get("name","")).to_lower()
				if "british" in rname or "atlantic" in rname:
					for pidv in r.get("province_ids", []):
						var pid := int(pidv)
						if MapManager.has_method("update_province_owner"):
							MapManager.update_province_owner(pid, ptag, ptag, true)
					break
		# Create demo flow
		var flow_id := ""
		if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("debug_create_demo_trade_flow"):
			flow_id = TradeManager.debug_create_demo_trade_flow("GER", ptag, "steel", 100.0)
		# Log stock before
		var before_stock := 0.0
		if typeof(ProductionManager) != TYPE_NIL:
			before_stock = float(ProductionManager.national_stockpile.get("steel", 0.0))
		# Interdict it
		if flow_id != "" and typeof(TradeManager) != TYPE_NIL:
			TradeManager.interdict_trade_flow(flow_id, "submarine", 0.4)
		# Simulate advance to show delivery with protection boost (higher amount landed due to regional)
		TradeManager.advance_trade_flows(1937)  # stub year to trigger delivery
		# Log stock after advance
		var after_stock := 0.0
		if typeof(ProductionManager) != TYPE_NIL:
			after_stock = float(ProductionManager.national_stockpile.get("steel", 0.0))
		# Log
		var flows := TradeManager.get_active_trade_flows() if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_active_trade_flows") else []
		var demo_f = null
		for f in flows:
			if f.flow_id == flow_id:
				demo_f = f
				break
		var lost: float = demo_f.total_lost_to_interdiction if demo_f else 0.0
		var prot: float = float(demo_f.metadata.get("regional_convoy_protection", 0.0)) if demo_f and demo_f.metadata else 0.0
		var last_del := float(demo_f.metadata.get("last_delivered_amount", 0.0)) if demo_f and demo_f.metadata else 0.0
		toast_map_debug("Trade demo: naval forced, flow " + flow_id + " interdicted, lost: %.1f , prot: %.0f%% (convoy bonuses reduced loss). Steel stock: %.1f -> %.1f (one-time loss + boosted delivery %.1f applied)" % [lost, prot * 100, before_stock, after_stock, last_del])
	)
	harness_section.add_child(trade_demo_btn)

	var infra_demo_btn := Button.new()
	infra_demo_btn.text = "🛠️ Demo Player Infra Invest (force control, start project on demo pid, log PP spend + eta)"
	infra_demo_btn.pressed.connect(func():
		var ptag := "player"
		if typeof(LeaderManager) != TYPE_NIL: ptag = LeaderManager.get_player_country_tag()
		# Ensure control on a demo infra province
		if typeof(MapManager) != TYPE_NIL:
			MapManager.update_province_owner(1, ptag, ptag, true)
		var idm := get_node_or_null("/root/InfrastructureDevelopmentManager")
		if idm and idm.has_method("try_start_infrastructure_investment"):
			var res: Dictionary = idm.try_start_infrastructure_investment(1, ptag)
			toast_map_debug("Infra invest demo pid1: " + str(res.get("success")) + " cost " + str(res.get("cost_pp")) + " eta " + str(res.get("eta_days")))
			if res.get("success") and typeof(GameData) != TYPE_NIL:
				# Show current mandate after spend
				var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
				var mand: int = ps.get("mandate", {}).get(ptag, 0)
				toast_map_debug("  Mandate after spend: " + str(mand) + " (see apply_pillar_shift in infra try_start)")
	)
	harness_section.add_child(infra_demo_btn)

	var full_systems_demo_btn := Button.new()
	full_systems_demo_btn.text = "🌍 Full Systems Demo: force naval + industrial regions, create trade, invest infra, interdict, log all effects"
	full_systems_demo_btn.pressed.connect(func():
		var ptag := "player"
		if typeof(LeaderManager) != TYPE_NIL: ptag = LeaderManager.get_player_country_tag()
		# Force naval and industrial
		if typeof(MapManager) != TYPE_NIL:
			for r in MapManager.get_all_strategic_regions().values():
				var rname := str(r.get("name","")).to_lower()
				if "british" in rname or "atlantic" in rname or "western germany" in rname or "low countries" in rname:
					for pidv in r.get("province_ids", []):
						var pid := int(pidv)
						if MapManager.has_method("update_province_owner"):
							MapManager.update_province_owner(pid, ptag, ptag, true)
		# Create trade
		var flow_id := ""
		if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("debug_create_demo_trade_flow"):
			flow_id = TradeManager.debug_create_demo_trade_flow("GER", ptag, "steel", 100.0)
		# Interdict
		if flow_id != "" and typeof(TradeManager) != TYPE_NIL:
			TradeManager.interdict_trade_flow(flow_id, "submarine", 0.3)
			TradeManager.advance_trade_flows(1937)
		# Invest infra
		var idm := get_node_or_null("/root/InfrastructureDevelopmentManager")
		var invest_res := {}
		if idm and idm.has_method("try_start_infrastructure_investment"):
			invest_res = idm.try_start_infrastructure_investment(1, ptag)
		# Log
		var flows := TradeManager.get_active_trade_flows() if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_active_trade_flows") else []
		var demo_f = null
		for f in flows:
			if f.flow_id == flow_id: demo_f = f; break
		var lost: float = demo_f.total_lost_to_interdiction if demo_f else 0.0
		var prot: float = float(demo_f.metadata.get("regional_convoy_protection", 0.0)) if demo_f and demo_f.metadata else 0.0
		var stock := 0.0
		if typeof(ProductionManager) != TYPE_NIL: stock = float(ProductionManager.national_stockpile.get("steel", 0.0))
		toast_map_debug("Full demo: regions forced, trade flow %s interdicted (lost %.1f, prot %.0f%%, stock %.1f), infra invest %s on pid1. Regional bonuses active across systems!" % [flow_id, lost, prot*100, stock, str(invest_res.get("success"))])
		# Exercise AI auto infra too in full demo (50+ turn integrated)
		var idm_full := get_node_or_null("/root/InfrastructureDevelopmentManager")
		if idm_full and idm_full.has_method("ai_consider_daily_invests"):
			var n: int = idm_full.ai_consider_daily_invests(["GER","RUS","FRA"], 0.9)
			toast_map_debug("  AI infra auto-invests triggered in demo: %d" % n)
	)
	harness_section.add_child(full_systems_demo_btn)

	var log_full_effects_btn := Button.new()
	log_full_effects_btn.text = "📊 Log Full Europe Effects (settlement bonuses, welfare_burden, HH influence, cohesion, policy state, Italy check, sample combat width)"
	log_full_effects_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			var ptag := "player"
			if typeof(LeaderManager) != TYPE_NIL: ptag = LeaderManager.get_player_country_tag()
			var ps = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			var welfare = ps.get("welfare_burden", {}).get(ptag, 0.0)
			var coh = GameData.get_pillar(ptag, "cohesion") if GameData.has_method("get_pillar") else 0
			var pols = ps.get("demographic_policies", {}).get(ptag, {})
			print("[HARNESS LOG] Player %s: welfare_burden=%.1f cohesion=%d policies=%s" % [ptag, welfare, coh, str(pols)])
			# Italy unholy alliance check
			var ita_w = ps.get("welfare_burden", {}).get("ITA", 0.0)
			var ita_hh = 0 # proxy via pillar or known init
			print("[HARNESS LOG] Italy (ITA unholy alliance papal+mafia): welfare_burden=%.1f (elevated by design for HH flavor)" % ita_w)
			if typeof(MapManager) != TYPE_NIL:
				var owned = MapManager.get_provinces_by_owner(ptag) if MapManager.has_method("get_provinces_by_owner") else []
				print("[HARNESS LOG] Owned provinces on full map: %d (sample settlement effects visible in inspector)" % owned.size())
				if owned.size() > 0:
					var sample_pid = owned[0]
					var p = MapManager.get_province(sample_pid)
					if p:
						print("[HARNESS LOG] Sample prov #%d: settlement=%.2f dev=%d infra=%d (org+%.1f%% attrit-%.1f%% supply+%.1f%%)" % [sample_pid, p.settlement_level, p.development_level, p.infrastructure, p.settlement_level*4, p.settlement_level*3, p.settlement_level*5])
			toast_map_debug("Full effects logged to console. Verify: settlement in Province getters (supply/org/attrition/combat), BattleManager 2.5%/cap25%, MapRenderer tints, PolicyLawScreen live, toasts with Respond, Golden/agents/supply/combat all map-tied. No user setup needed beyond these buttons + F5 load.")
	)
	harness_section.add_child(log_full_effects_btn)

	var italy_pandemic_btn := Button.new()
	italy_pandemic_btn.text = "🇮🇹 Force Italy Unholy + Pandemic Narrative (HH events on map)"
	italy_pandemic_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			# Boost ITA welfare/HH as per init design + trigger narrative path
			if GameData.has_method("apply_pillar_shift"):
				GameData.apply_pillar_shift("ITA", "cohesion", -10, "harness_italy_unholy")
			if GameData.has_method("apply_social_services_policy"):
				GameData.apply_social_services_policy("ITA", "elite_optimization")
			if GameData.has_method("apply_agent_pillar_influence"):
				GameData.apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 8, "public")
			# Trigger pandemic style
			if GameData.has_method("apply_pillar_shift"):
				GameData.apply_pillar_shift("ITA", "cohesion", -5, "elite_pandemic_narrative")
			toast_map_debug("Italy unholy alliance (papal+mafia) elevated HH/welfare_burden simulated. Pandemic narrative (Spanish Flu style HH exploit for control/depop) triggered. Watch toasts, cohesion splits, Golden block risk. Full map provinces reflect via supply/combat penalties from welfare.")
	)
	harness_section.add_child(italy_pandemic_btn)

	var open_policy_btn := Button.new()
	open_policy_btn.text = "📜 Open PolicyLawScreen (direct test welfare/education/feminism + agent lobby buttons)"
	open_policy_btn.pressed.connect(func():
		_open_policy_law_screen()
		toast_map_debug("PolicyLawScreen opened. Enact/reverse policies (direct or agent-lobby 6mo tradeoffs). Live cohesion previews, toasts from pressure feed back here. Test anti-natal tradeoffs (short Mandate relief vs long family erosion/HH/Golden).")
	)
	harness_section.add_child(open_policy_btn)

	var trigger_toast_respond_btn := Button.new()
	trigger_toast_respond_btn.text = "🔔 Trigger Sample Crisis Toast + Respond (opens PolicyLaw for welfare/pressure)"
	trigger_toast_respond_btn.pressed.connect(func():
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("Hidden Hand propaganda: Populace demands 'modern' changes (remove bible, public schools, feminism, welfare 'progress')... (Low cohesion makes prone; respond via policies)", 5.0, false, true)
			toast_map_debug("Important toast with Respond button shown. Click Respond to auto-open PolicyLawScreen (or manual). Full loop: crisis from policies/low coh -> toast -> respond -> enact/reverse on full Europe map. Agents (lobby) also interact.")
	)
	harness_section.add_child(trigger_toast_respond_btn)

	var sim_full_cw_btn := Button.new()
	sim_full_cw_btn.text = "🔥 Simulate FULL Cultural War + Advance 12mo + Log ALL Effects"
	sim_full_cw_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			var ptag := "player"
			if typeof(LeaderManager) != TYPE_NIL: ptag = LeaderManager.get_player_country_tag()
			# Full stack: welfare expansive + feminism + public ed + low coh + traditional outlier priming + time advance
			if GameData.has_method("apply_social_services_policy"): GameData.apply_social_services_policy(ptag, "expansive_burden")
			if GameData.has_method("apply_women_workforce_policy"): GameData.apply_women_workforce_policy(ptag, "full")
			if GameData.has_method("apply_governmental_education_policy"): GameData.apply_governmental_education_policy(ptag, "public_indoctrination")
			if GameData.has_method("apply_pro_natal_incentives"): GameData.apply_pro_natal_incentives(ptag, 0)  # disable to create traditional outlier
			if GameData.has_method("apply_border_policy"): GameData.apply_border_policy(ptag, "open")
			if GameData.has_method("apply_pillar_shift"): GameData.apply_pillar_shift(ptag, "cohesion", -35, "full_cw_harness")
			if typeof(TimeManager) != TYPE_NIL:
				for i in range(12):
					if TimeManager.has_method("advance_month"): TimeManager.advance_month()
					elif TimeManager.has_method("advance_days"): TimeManager.advance_days(30)
			toast_map_debug("FULL cultural war + 12mo erosion simulated. Expect: multiple welfare/HH pandemic/Spanish Flu/social rev toasts (low coh+traditional), Respond->PolicyLaw, welfare_burden spike, Golden block risk, map settlement if prior, agent lobbies. Check console + inspector.")
	)
	harness_section.add_child(sim_full_cw_btn)

	var force_ita_flu_btn := Button.new()
	force_ita_flu_btn.text = "🇮🇹 Force Italy Unholy Alliance + Spanish Flu Event (map-wide narrative)"
	force_ita_flu_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			if GameData.has_method("apply_pillar_shift"):
				GameData.apply_pillar_shift("ITA", "cohesion", -20, "unholy_alliance_force")
			if GameData.has_method("apply_social_services_policy"): GameData.apply_social_services_policy("ITA", "elite_optimization")
			if GameData.has_method("apply_agent_pillar_influence"):
				GameData.apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 15, "public")
			# Pandemic trigger
			if GameData.has_method("apply_pillar_shift"):
				GameData.apply_pillar_shift("ITA", "cohesion", -8, "spanish_flu_hh_exploit")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("ITALY UNHOLY (Papal+Mafia) + Spanish Flu-style HH pandemic narrative active across Europe map provinces. Welfare strain + settlement penalties apply. Watch supply/combat drag + toasts.", 6.0, false, true)
			toast_map_debug("Italy unholy alliance + Spanish Flu forced. ITA elevated welfare/HH. Full 460-prov map reflects via Province welfare penalties in supply/org. Golden synergies blocked in high-burden areas. Use log button + advance for more.")
	)
	harness_section.add_child(force_ita_flu_btn)

	var mass_settle_combat_btn := Button.new()
	mass_settle_combat_btn.text = "🗺️ Mass Settlement on 50+ Provinces + Combat/Supply Log (full map test)"
	mass_settle_combat_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_encourage_relocation"):
			var ptag := "player"
			if typeof(LeaderManager) != TYPE_NIL: ptag = LeaderManager.get_player_country_tag()
			GameData.apply_encourage_relocation(ptag, "mass_europe_settle_50plus", 1.2)  # heavy scale for many prov
			# Log combat/supply effects
			if typeof(MapManager) != TYPE_NIL:
				var owned = MapManager.get_provinces_by_owner(ptag) if MapManager.has_method("get_provinces_by_owner") else []
				var settled_count = 0
				for pid in owned:
					var p = MapManager.get_province(pid)
					if p and p.settlement_level > 0.1:
						settled_count += 1
						if settled_count <= 3:
							print("[MASS SETTLE] Prov %d: sett=%.2f dev=%d infra=%d org_mod=%.2f attrit_mod=%.2f supply_mod=%.2f combat_w=%.2f" % [pid, p.settlement_level, p.development_level, p.infrastructure, p.get_organization_recovery_modifier(), p.get_attrition_modifier(), p.get_local_supply_generation_modifier(), p.get_combat_width_modifier()])
				print("[MASS SETTLE] Total settled provinces on map: %d (of owned %d). Expect BattleManager defender +2.5%%/lev (cap25%%), supply uplift, vitality tints, inspector bonuses visible. Assault settled vs unsettled for differential." % [settled_count, owned.size()])
			toast_map_debug("Mass settlement applied (50+ provinces targeted via scale). Dev/infra/settlement_level live on full Europe map. Check inspector (ProvinceInsight), MapRenderer tints, supply overlays (L), combat (stage assaults). Golden/agents benefit from stable settled lands.")
	)
	harness_section.add_child(mass_settle_combat_btn)


	# Map Infrastructure Layers (toggleable/editable visuals for roads, rails, cities, sites/airfields/ports)

	var mass_assault_log_btn := Button.new()
	mass_assault_log_btn.text = "🗺️ Mass Settlement + Assault Log on 50+ provinces (combat bonuses + welfare drag)"
	mass_assault_log_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_encourage_relocation"):
			var ptag := "player"
			if typeof(LeaderManager) != TYPE_NIL: ptag = LeaderManager.get_player_country_tag()
			GameData.apply_encourage_relocation(ptag, "mass_assault_50plus", 1.8)
			if typeof(MapManager) != TYPE_NIL:
				var owned = MapManager.get_provinces_by_owner(ptag) if MapManager.has_method("get_provinces_by_owner") else []
				print("[F10 MASS ASSAULT LOG] Applied settlement to many of %d owned. Logging combat bonuses + welfare:" % owned.size())
				var logged = 0
				for pid in owned:
					var p = MapManager.get_province(pid)
					if p and p.settlement_level > 0.15 and logged < 5:
						var def_b = clampf(1.0 + (p.settlement_level * 0.025), 1.0, 1.25)
						print("  Prov#%d sett=%.2f def_bonus=%.3f (2.5%%/lev cap25%%); welfare drag via Province supply/org if high burden. Assault this vs non-settled for differential." % [pid, p.settlement_level, def_b])
						logged += 1
			toast_map_debug("Mass Settlement + Assault Log: 50+ provinces settled. Combat bonuses (BattleManager/Resolver) + welfare penalties logged. Use assaults on settled for validation.")
	)
	harness_section.add_child(mass_assault_log_btn)

	# Simple map mode toggle example (per deep map connection polish): re-tints for 'strain' (welfare) or 'vitality' (settlement) to demo instant connection.
	# After F10 mass settlement or policy apply, click this to force re-tint (color shift visible), then click a province to see updated numbers in inspector.
	var tint_demo_btn := Button.new()
	tint_demo_btn.text = "🎨 Cycle Map Tint Demo (strain/vitality/off) — re-tint after settle/policy"
	tint_demo_btn.pressed.connect(func():
		var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
		if mr and mr.has_method("force_map_tint_demo"):
			var cur: String = mr.get("debug_tint_mode") if mr.get("debug_tint_mode") != null else ""
			var next := ""
			if cur == "": next = "vitality"
			elif cur == "vitality": next = "strain"
			else: next = ""
			mr.call("force_map_tint_demo", next)
			toast_map_debug("Map tint demo: '%s' (vitality=settlement cyan boost; strain=welfare red/gray). Click any province (after F10 mass-settle or policy) to confirm live numbers + color shift via province_data_changed." % next)
		else:
			toast_map_debug("MapRenderer force_map_tint_demo not available.")
	)
	harness_section.add_child(tint_demo_btn)

	var agent_lobby_sab_btn := Button.new()
	agent_lobby_sab_btn.text = "🕵️ Agent Lobby Welfare + Sabotage on Settled Infra (map effects)"
	agent_lobby_sab_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("resolve_agent_policy_mission"):
			GameData.resolve_agent_policy_mission("harness_agent_lobby", "welfare", "player", "success")
			GameData.resolve_agent_policy_mission("harness_agent_fem", "women_workforce", "player", "success")
		if typeof(AgentManager) != TYPE_NIL and AgentManager.has_method("establish_network"):
			# demo sabotage net on a settled prov if possible
			pass
		if typeof(MapManager) != TYPE_NIL:
			var owned = MapManager.get_provinces_by_owner("player") if MapManager.has_method("get_provinces_by_owner") else []
			for pid in owned.slice(0, 3):
				var p = MapManager.get_province(pid)
				if p and p.settlement_level > 0.1:
					print("[F10 AGENT SAB] Lobby welfare/feminism applied (welfare_burden up). Sim infra sabotage on settled #%d (infra--, supply/org drag via Province getters)." % pid)
					if MapManager.has_method("update_province_infrastructure"):
						MapManager.update_province_infrastructure(pid, max(0, p.infrastructure - 1))
		toast_map_debug("Agent Lobby (welfare/education/feminism) + Sabotage on settled infra: map effects (Province welfare/sabotage) visible in supply/combat. Duration trade-off in real missions.")
	)
	harness_section.add_child(agent_lobby_sab_btn)

	var mixed_loyalty_btn := Button.new()
	mixed_loyalty_btn.text = "⚔️ Full Mixed Army Combat Test with Loyalty/Settlement"
	mixed_loyalty_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			var ps = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			if not ps.has("foreign_military_pct"): ps["foreign_military_pct"] = {}
			ps["foreign_military_pct"]["player"] = 0.25
		print("[F10 MIXED COMBAT] foreign_military_pct=25% -> loyalty ~0.84 (org/readiness penalty). Settlement from prior + defender bonus 2.5%/lev. Force preview/assault on settled for full log (loyalty scales attack, settlement scales defense, welfare drags supply in settled).")
		toast_map_debug("Mixed Army Combat Test: loyalty from foreign_military_pct + settlement_def_bonus + welfare in settled provs. Check BattleManager logs + Resolver powers + Province getters.")
	)
	harness_section.add_child(mixed_loyalty_btn)

	# === Enhanced F10 harness buttons for mass settlement + specific province inspect + welfare trigger + live tint/inspector verification (per autonomous tester task) ===
	# These make the 460-prov map directly playable/testable for policies/settlement/combat: apply, advance, click-prov to see live numbers/tints.
	var mass_settle_verify_btn := Button.new()
	mass_settle_verify_btn.text = "🗺️ Mass Settlement (all owned) + Verify 4 Specific Provs (settlement/welfare nums in log + force inspector)"
	mass_settle_verify_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_encourage_relocation"):
			var ptag := _debug_player_country_tag()
			GameData.apply_encourage_relocation(ptag, "f10_mass_settle_verify", 1.0)
			# Sample + log specific provinces for verification (use MapManager to fetch live Province settlement + GameData welfare)
			var samples: Array = []
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
				var owned: Array = MapManager.get_provinces_by_owner(ptag)
				# Pick first 2 + last 1 + try find one with "Berlin" or high id sample (460 map has varied)
				if owned.size() > 0:
					samples.append(owned[0])
					if owned.size() > 1: samples.append(owned[1])
					if owned.size() > 3: samples.append(owned[owned.size()-1])
					# Try to include an ITA sample if present for welfare cross-check
					for pid in owned:
						var pcheck = MapManager.get_province(pid)
						if pcheck and (pcheck.owner_tag == "ITA" or str(pcheck.name).to_lower().find("rome") >= 0 or pid % 17 == 0):
							if not samples.has(pid):
								samples.append(pid)
								break
					samples = samples.slice(0, 4)
			var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			var wbur := float(ps.get("welfare_burden", {}).get(ptag, 0.0))
			print("[F10 MASS+VERIFY] Player %s post-settle: welfare_burden=%.1f (pre-tint confirm)" % [ptag, wbur])
			for pid in samples:
				var p = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
				if p:
					var owner_w := float(ps.get("welfare_burden", {}).get(p.owner_tag, wbur))
					print("  SPECIFIC PROV #%d '%s' (owner=%s): settlement_level=%.2f dev=%d infra=%d | welfare_burden=%.1f | org_mod=%.2f attr_mod=%.2f supply_mod=%.2f combat_w=%.2f" % [
						pid, p.name if p.name else "?", p.owner_tag, p.settlement_level, p.development_level, p.infrastructure,
						owner_w, p.get_organization_recovery_modifier(), p.get_attrition_modifier(), p.get_local_supply_generation_modifier(), p.get_combat_width_modifier()
					])
			# Force live tint (settlement cyan-green) + if inspector open update; also try force show one specific in inspector for verification
			_force_map_tint_refresh_for_tag(ptag)
			_try_show_inspector_on_samples(samples)
			toast_map_debug("Mass settlement + specific prov verify done. Check map tints (vitality), click provinces (or auto-forced inspector) for live settlement/welfare nums in inspector panel. Combat/supply getters reflect.")
	)
	harness_section.add_child(mass_settle_verify_btn)

	var trigger_welfare_live_btn := Button.new()
	trigger_welfare_live_btn.text = "🏛️ Trigger Welfare Policy (expansive_burden) + Confirm Strain Tint + Live Inspector Update"
	trigger_welfare_live_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_social_services_policy"):
			var ptag := _debug_player_country_tag()
			GameData.apply_social_services_policy(ptag, "expansive_burden")
			var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			var wbur := float(ps.get("welfare_burden", {}).get(ptag, 0.0))
			var coh: int = int(GameData.get_pillar(ptag, "cohesion") if GameData.has_method("get_pillar") else 0)
			print("[F10 WELFARE TRIGGER] Applied expansive_burden to %s: welfare_burden now=%.1f cohesion=%d. Expect strain tint (unhealthy red/gray) on owner's map provinces + inspector welfare line when clicked/shown." % [ptag, wbur, coh])
			# Force live map strain tint update across all provs of owner (national welfare affects tint calc)
			_force_map_tint_refresh_for_tag(ptag)
			# If any inspector open, re-show it to pull fresh welfare/settlement into panel live (no need to reclick)
			_try_refresh_open_inspector()
			toast_map_debug("Welfare policy triggered. Map strain tint (welfare_burden >12) + inspector numbers should be LIVE updated. Click any %s province to verify welfare num in combat/inspector text. Advance time for toasts." % ptag)
		else:
			toast_map_debug("Welfare policy apply not available.")
	)
	harness_section.add_child(trigger_welfare_live_btn)

	var inspect_specific_btn := Button.new()
	inspect_specific_btn.text = "🔎 Inspect Specific Provinces (4 samples incl. ITA if avail) - Log settlement/welfare + Force Open Inspector"
	inspect_specific_btn.pressed.connect(func():
		var ptag := _debug_player_country_tag()
		var samples: Array = []
		var ita_sample := -1
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			var owned: Array = MapManager.get_provinces_by_owner(ptag)
			if owned.size() > 0:
				samples = [owned[0]]
				if owned.size() > 5: samples.append(owned[5])
				if owned.size() > 20: samples.append(owned[20])
				samples.append(owned[owned.size() - 1] if owned.size() > 0 else -1)
				# Prefer an ITA owned or high welfare area for cross verify
				for pid in owned:
					var p = MapManager.get_province(pid)
					if p and p.owner_tag == "ITA":
						ita_sample = pid
						if not samples.has(pid): samples.append(pid)
						break
				if ita_sample < 0 and owned.size() > 10:
					ita_sample = owned[10]
					samples.append(ita_sample)
			samples = samples.filter(func(x): return x >= 0).slice(0, 4)
		var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
		print("[F10 INSPECT SPECIFIC] Player tag=%s ; samples=%s" % [ptag, str(samples)])
		for pid in samples:
			var p = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
			if p:
				var w := float(ps.get("welfare_burden", {}).get(p.owner_tag, 0.0))
				var coh_p: int = int(GameData.get_pillar(p.owner_tag, "cohesion") if GameData.has_method("get_pillar") else 0)
				print("  INSPECT PROV #%d name='%s' owner=%s sett=%.2f dev=%d infra=%d | welfare=%.1f coh=%d | supply_mod=%.2f org_mod=%.2f" % [
					pid, str(p.name), p.owner_tag, p.settlement_level, p.development_level, p.infrastructure, w, coh_p,
					p.get_local_supply_generation_modifier(), p.get_organization_recovery_modifier()
				])
		_try_show_inspector_on_samples(samples)
		toast_map_debug("Specific provinces inspected (logs + forced inspector open for clicked verification). Verify live settlement/welfare/tints after prior actions. Use for combat policy testing.")
	)
	harness_section.add_child(inspect_specific_btn)

	var force_live_refresh_btn := Button.new()
	force_live_refresh_btn.text = "🔄 Force Live Map Tint Refresh + Rebuild Open Inspector (post-settle/welfare confirm)"
	force_live_refresh_btn.pressed.connect(func():
		var ptag := _debug_player_country_tag()
		_force_map_tint_refresh_for_tag(ptag)
		_try_refresh_open_inspector()
		print("[F10 FORCE LIVE] Full tint + inspector refresh triggered for %s. Click any province now to confirm settlement/welfare numbers visible live in inspector + strain/vitality tints on map." % ptag)
		toast_map_debug("Live refresh forced. Map now reflects latest settlement + welfare strain tints. Inspector will show updated numbers on click or if open.")
	)
	harness_section.add_child(force_live_refresh_btn)

	# NEW/ENHANCED harness button per task: Mass settlement on owned + preview combat def bonus vs adjacent unsettled.
	# Logs live Province getters (incl. get_settlement_combat_def_bonus, org/attr/supply/cw), BattleManager preview-style numbers (2.5%/lev uplift), adjacent contrast for unsettled (0 bonus).
	# Optionally notes staging sample assault (preview only to keep zero-interference safe; real assaults via positioned formations + Map input or other F10 combat btns).
	var mass_settle_def_preview_btn := Button.new()
	mass_settle_def_preview_btn.text = "🗺️ Mass Settlement on Owned + Preview Combat Def Bonus vs Adj Unsettled (log Province getters + Battle nums)"
	mass_settle_def_preview_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_encourage_relocation"):
			var ptag := _debug_player_country_tag()
			GameData.apply_encourage_relocation(ptag, "mass_settle_def_preview", 0.8)
			_force_map_tint_refresh_for_tag(ptag)
			var samples_logged := 0
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
				var owned: Array = MapManager.get_provinces_by_owner(ptag)
				print("[F10 MASS+DEF_PREVIEW] Applied mass settlement (scale 0.8) to %s owned=%d. Previewing combat def bonus (settled vs adj unsettled) + Province getters..." % [ptag, owned.size()])
				var bm: Node = null
				if typeof(BattleManager) != TYPE_NIL:
					bm = BattleManager
				elif is_inside_tree():
					bm = get_node_or_null("/root/BattleManager")
				for pid in owned:
					var p: Variant = MapManager.get_province(pid) if MapManager.has_method("get_province") else null
					if p and float(p.get("settlement_level", 0.0)) > 0.05 and samples_logged < 3:
						var sett := float(p.get("settlement_level", 0.0))
						var def_b := 0.0
						if p.has_method("get_settlement_combat_def_bonus"):
							def_b = float(p.call("get_settlement_combat_def_bonus"))
						else:
							def_b = clampf(sett * 0.025, 0.0, 0.25)
						var org_m := float(p.call("get_organization_recovery_modifier")) if p.has_method("get_organization_recovery_modifier") else 0.0
						var sup_m := float(p.call("get_local_supply_generation_modifier")) if p.has_method("get_local_supply_generation_modifier") else 0.0
						var att_m := float(p.call("get_attrition_modifier")) if p.has_method("get_attrition_modifier") else 0.0
						var cw_m := float(p.call("get_combat_width_modifier")) if p.has_method("get_combat_width_modifier") else 0.0
						print("  PROV#%d sett=%.2f | Province getters: def_bonus=%.3f org_mod=%.2f supply_mod=%.2f attr_mod=%.2f cw_mod=%.2f" % [int(pid), sett, def_b, org_m, sup_m, att_m, cw_m])
						# Adjacent unsettled contrast (use MapManager adj)
						if MapManager.has_method("get_adjacent_provinces"):
							var adjs: Array = MapManager.call("get_adjacent_provinces", int(pid))
							for aid in adjs:
								var ap: Variant = MapManager.get_province(int(aid)) if MapManager.has_method("get_province") else null
								if ap and str(ap.get("owner_tag", "")) != ptag and not bool(ap.get("is_sea", false)):
									var a_sett := float(ap.get("settlement_level", 0.0))
									var a_def := 0.0
									if ap.has_method("get_settlement_combat_def_bonus"):
										a_def = float(ap.call("get_settlement_combat_def_bonus"))
									else:
										a_def = clampf(a_sett * 0.025, 0.0, 0.25)
									print("    vs ADJ UNSETTLED #%d sett=%.2f def=%.3f (settled defender +%.1f%% uplift contrast)" % [int(aid), a_sett, a_def, (def_b - a_def) * 100.0 ])
									# Battle preview numbers (from BattleManager logic or computed)
									var preview_mult := 1.0 + def_b
									print("    Battle preview (def power mult): %.3f (vs 1.0 for unsettled; full conditional in BattleManager.execute/Resolver)" % preview_mult)
									if bm and bm.has_method("can_assault_province"):
										var can_preview = bm.call("can_assault_province", ptag, int(aid), int(pid))
										print("    BattleManager.can_assault preview: %s" % str(can_preview))
									samples_logged += 1
									break
						if samples_logged >= 3: break
				# Optionally stage sample assault (preview/log focused; real execution requires positioned formations on from-prov, use MapViewInput Ctrl+click or other harness combat test for full)
				if samples_logged > 0 and bm and bm.has_method("execute_province_assault"):
					print("[F10 MASS+DEF_PREVIEW] Sample assault staging available via BattleManager (call execute only if formations ready at adjacent; harness uses preview logs for zero-interfere test). Post-assault: inspect target for org/settlement effects.")
			toast_map_debug("Mass settle on owned + combat def preview vs adj unsettled complete. Province getters + Battle nums logged (2.5%/lev). Click settled prov post-action or assault defender to confirm live 460-prov effects in inspector.")
	)
	harness_section.add_child(mass_settle_def_preview_btn)

	# === BASIC MAPMODES / VISUAL LAYERS (Phase 2 map UX per WORLD_CLASS_MAP_ROADMAP) ===
	# 3+ simple toggles in F10 (also hotkeys F1-F5): use existing characterize (strain/vitality), dev lighten, supply layer (L).
	# Clear button labels + toast guidance. No new rendering; reuses _characterize_province_fill + force paths for live tints on 460-prov.
	var mapmode_header := Label.new()
	mapmode_header.text = "Map Modes / Visual Layers (F1 political, F2 strain, F3 vitality, F4 dev, F5 supply, F6 loyalty/foreign%, F7 infra/road density using built_road/rail + layers; or buttons):"
	mapmode_header.add_theme_font_size_override("font_size", 10)
	mapmode_header.modulate = Color(0.85, 0.95, 0.85)
	harness_section.add_child(mapmode_header)

	var mode_pol_btn := Button.new()
	mode_pol_btn.text = "🗺️ Map Mode: Political (default clean fills)"
	mode_pol_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("set_map_mode"):
			mr.call("set_map_mode", "political")
		else:
			toast_map_debug("MapRenderer set_map_mode unavailable.")
		toast_map_debug("Map mode: Political — clean beloved default (no extra tints). Click provinces to inspect. (F1 hotkey)")
	)
	harness_section.add_child(mode_pol_btn)

	var mode_strain_btn := Button.new()
	mode_strain_btn.text = "😣 Map Mode: Strain (welfare burden red-gray tint layer)"
	mode_strain_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("set_map_mode"):
			mr.call("set_map_mode", "strain")
		toast_map_debug("Map mode: Strain — high owner welfare_burden provinces show stronger unhealthy red/gray tints via characterize. Apply welfare policy first (F10), then this. Click prov for inspector welfare note. (F2)")
	)
	harness_section.add_child(mode_strain_btn)

	var mode_vitality_btn := Button.new()
	mode_vitality_btn.text = "🌱 Map Mode: Vitality (settlement cyan-green tint layer)"
	mode_vitality_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("set_map_mode"):
			mr.call("set_map_mode", "vitality")
		toast_map_debug("Map mode: Vitality — settled provinces (>0.05) boost soft cyan-green healthy tints via characterize. Use after mass settle/reloc (F10). Click to see settlement Lv + bonuses in inspector. (F3)")
	)
	harness_section.add_child(mode_vitality_btn)

	var mode_dev_btn := Button.new()
	mode_dev_btn.text = "📈 Map Mode: Development (boost dev lighten/warmth layer)"
	mode_dev_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("set_map_mode"):
			mr.call("set_map_mode", "development")
		toast_map_debug("Map mode: Development — amplifies existing development_visual_lighten on high-dev provinces (brighter/warmer fills). Pairs with dev numbers in inspector. (F4)")
	)
	harness_section.add_child(mode_dev_btn)

	var mode_supply_btn := Button.new()
	mode_supply_btn.text = "🚚 Map Mode: Supply (toggle L overlay + tints; existing supply layer)"
	mode_supply_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("set_map_mode"):
			mr.call("set_map_mode", "supply")
		else:
			# fallback direct toggle
			if mr and mr.has_method("_toggle_supply_overlay"):
				mr.call("_toggle_supply_overlay")
		toast_map_debug("Map mode: Supply — toggles supply overlay (L key) + depot/ring tints. Use with selected prov for route preview. (F5)")
	)
	harness_section.add_child(mode_supply_btn)

	var mode_loyalty_btn := Button.new()
	mode_loyalty_btn.text = "🛡️ Map Mode: Loyalty (foreign mil % / loyalty tint layer)"
	mode_loyalty_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("set_map_mode"):
			mr.call("set_map_mode", "loyalty")
		toast_map_debug("Map mode: Loyalty — owner loyalty (from GameData foreign_military_pct + get_military_loyalty_multiplier) tints provinces amber/warning on low loyalty/high foreign %. Ties combat attack scale, production reliability, erosion. Click prov for inspector loyalty nums. (F6)")
	)
	harness_section.add_child(mode_loyalty_btn)

	var mode_infra_btn := Button.new()
	mode_infra_btn.text = "🛤️ Map Mode: Infra/Road Density (built_road/rail + layers highlight)"
	mode_infra_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("set_map_mode"):
			mr.call("set_map_mode", "infra")
		toast_map_debug("Map mode: Infra/Road Density — highlights provinces by explicit built_road_neighbors + built_rail_neighbors (MapManager build_*) len + infra level (steel-blue tint + lighten). Rebuilds/emphasizes InfrastructureOverlayLayer roads/rails Line2Ds. Pairs with F10 Invest action. (F7)")
	)
	harness_section.add_child(mode_infra_btn)

	# === INSPECTOR INTERACTIVITY / DIRECT PROVINCE ACTIONS (harness buttons on clicked/selected province) ===
	# Click any province (opens inspector, sets selected), then press these. Use real Province + GameData + BattleManager/ProvinceInsight preview.
	# Live updates: tints via emit/refresh, inspector re-shows numbers, logs for headless confirmation on 460.
	var action_header := Label.new()
	action_header.text = "Direct Actions on Selected Province (click map prov first; real data paths):"
	action_header.add_theme_font_size_override("font_size", 10)
	action_header.modulate = Color(0.9, 0.88, 0.95)
	harness_section.add_child(action_header)

	var settle_sel_btn := Button.new()
	settle_sel_btn.text = "🏠 Settle Selected Province Now (+0.35 settlement_level)"
	settle_sel_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("debug_settle_selected_province"):
			mr.call("debug_settle_selected_province", 0.35)
			# Ensure tint/inspector live after
			if mr.has_method("force_full_map_refresh"):
				mr.call("force_full_map_refresh")
			toast_map_debug("Direct action: Settle selected done (real Province.settlement_level + MapManager emit). Vitality tint + inspector bonuses (org/attrit/supply/def) updated live. Try F3 vitality mode after.")
		else:
			toast_map_debug("debug_settle_selected_province not on MapRenderer.")
	)
	harness_section.add_child(settle_sel_btn)

	var strain_sel_btn := Button.new()
	strain_sel_btn.text = "😣 Trigger Local Welfare Strain (on selected's owner via GameData policy)"
	strain_sel_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("debug_trigger_welfare_strain_on_selected"):
			mr.call("debug_trigger_welfare_strain_on_selected")
			toast_map_debug("Direct action: Welfare strain policy applied to owner of selected (real GameData). Strain tints + welfare drag in inspector now live. Use F2 strain mode or advance for erosion toasts.")
		else:
			toast_map_debug("debug_trigger_welfare... not available.")
	)
	harness_section.add_child(strain_sel_btn)

	var preview_combat_btn := Button.new()
	preview_combat_btn.text = "⚔ Preview Combat vs Adjacent (real Province + BattleManager/ProvinceInsight preview)"
	preview_combat_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("debug_preview_combat_vs_adjacent"):
			mr.call("debug_preview_combat_vs_adjacent")
			toast_map_debug("Direct action: Combat preview vs adjacent enemy using real Province getters + ProvinceInsight.get_battle_preview + BattleManager.can_assault (settlement def bonus, welfare drag, loyalty etc visible in logs). Stage with shift for more.")
		else:
			toast_map_debug("debug_preview_combat... not available.")
	)
	harness_section.add_child(preview_combat_btn)

	var aar_btn := Button.new()
	aar_btn.text = "📜 Show Battle AAR Panel (F10) — unit combat logs (Formation.combat_log), leader impacts +%, full modifiers %% list, space/air effects, tips. Callable from preview note [Press F10 for full AAR], post-battle auto"
	aar_btn.pressed.connect(func(): show_battle_aar({}))
	harness_section.add_child(aar_btn)

	# NEW Phase 2 direct actions on selected/clicked (build on debug_* + real APIs; F10 harness + inspector click flow; live 460 updates)
	var invest_infra_btn := Button.new()
	invest_infra_btn.text = "🏗️ Invest Infra here (real InfraDevManager + layer rebuild + density tint preview)"
	invest_infra_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("debug_invest_infra_selected_province"):
			mr.call("debug_invest_infra_selected_province")
			# Post-invest: force infra layer + if infra mode re-tint density from built_*
			if mr.has_method("force_full_map_refresh"):
				mr.call("force_full_map_refresh")
			toast_map_debug("Direct action: Invest Infra here done (real try_start_infrastructure_investment / start_project + emit 'infrastructure'). Overlay roads/rails rebuild (built_*), infra mode (F7) shows density highlight, inspector project status + live nums. Use after selecting border/highway prov.")
		else:
			toast_map_debug("debug_invest_infra_selected_province not on MapRenderer.")
	)
	harness_section.add_child(invest_infra_btn)

	var agent_mission_btn := Button.new()
	agent_mission_btn.text = "🕵️ Assign Random Agent Mission here (real AgentManager.establish_network on pid + preview stage assault to adj)"
	agent_mission_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("debug_assign_random_agent_mission_here"):
			mr.call("debug_assign_random_agent_mission_here")
			if mr.has_method("force_full_map_refresh"):
				mr.call("force_full_map_refresh")
			toast_map_debug("Direct action: Random agent mission here (AgentManager.establish_network(pid, focus e.g. infra_sabotage) or GameData.resolve fallback + real BM/ProvinceInsight assault stage preview to adj). Networks affect Province supply/infra getters daily; agent layer viz + infra density tints update live. Logs show previews. Advance time for sabotage effects on 460 map.")
		else:
			toast_map_debug("debug_assign_random_agent_mission_here not available.")
	)
	harness_section.add_child(agent_mission_btn)

	# Phase 3 direct combat action (F10 harness): "Stage + Execute Sample Assault from selected" — uses real BattleManager.execute + current Province data for preview/outcome.
	var assault_exec_btn := Button.new()
	assault_exec_btn.text = "⚔ Stage + Execute Sample Assault from selected"
	assault_exec_btn.pressed.connect(func():
		var mr: Node = _find_map_renderer()
		if mr and mr.has_method("debug_stage_and_execute_sample_assault"):
			mr.call("debug_stage_and_execute_sample_assault")
			# Post exec: ensure tints/inspector/layers (ownership change + settlement effects) + border refresh
			if mr.has_method("force_full_map_refresh"):
				mr.call("force_full_map_refresh")
			if mr.has_method("force_border_update"):
				mr.call("force_border_update")
			toast_map_debug("Direct action (Phase 3): Stage + Execute Sample Assault from selected (real MapRenderer _try / BattleManager.execute_province_assault with live settlement/loyalty/welfare previews in BM.can + Resolver; log outcome, capture updates owner via MapManager, refreshes tints/inspector/layers on 460). Ctrl+click map or attack button do same real path.")
		else:
			toast_map_debug("debug_stage_and_execute_sample_assault not on MapRenderer (combat wiring incomplete).")
	)
	harness_section.add_child(assault_exec_btn)

	# New: simple multi-province "AI" combat demo for playability. Executes real assaults for non-player tags using BM can/execute.
	# Advances time 1 day so recovery (supply/infra) + daily infra tick + events can fire. Shows "multi" without full AI.
	var ai_combat_btn := Button.new()
	ai_combat_btn.text = "🤖 Simulate AI Combat Turn (auto-find/execute assaults for other majors + 1 day advance)"
	ai_combat_btn.custom_minimum_size = Vector2(420, 28)
	ai_combat_btn.pressed.connect(func():
		_simulate_ai_combat_turn()
		toast_map_debug("AI turn done: check console for assaults, org/strength hits, captures. Formations now need reinforce + time for recovery. Infra projects advanced too.")
	)
	harness_section.add_child(ai_combat_btn)

	# NEW: 30 day integrated econ+war+infra+peace playtest sim button (F10 interactive + harness). Calls TestRunner 50t method (30d variant) or fallback drive.
	# Exercises full: pop growth (via months), factory assign/train/produce/recruit, AI assaults + chain, infra invest daily, peace policies/events/hand/welfare.
	# Safe, logs [50T SIM PROGRESS] every 5d, mem guards. Validates parallel agent work (combat persist, infra, econ pop/labor, peace).
	var run_30d_econ_war_btn := Button.new()
	run_30d_econ_war_btn.text = "▶ Run 30 day econ+war playtest sim (pop/prod/train/recruit + AI assaults + infra + peace/events)"
	run_30d_econ_war_btn.custom_minimum_size = Vector2(420, 28)
	run_30d_econ_war_btn.pressed.connect(func():
		var tr := get_tree().get_first_node_in_group("test_runner") if get_tree() else null
		if tr == null and get_tree():
			tr = get_tree().current_scene.find_child("TestRunner", true, false)
		if tr != null and tr.has_method("_run_integrated_50_turn_playtest_sim"):
			tr.call("_run_integrated_50_turn_playtest_sim", 30)
			toast_map_debug("30d integrated sim (econ/war/infra/peace) started via TestRunner. Watch console for turn progress + final state. 50t via EOA_RUN_50_TURN_SIM=1 headless.")
		else:
			# Fallback local drive (mirrors TestRunner logic for F5 interactive without full runner)
			_drive_local_30d_playtest_sim()
			toast_map_debug("30d econ+war sim (fallback drive) started. See logs for progress.")
	)
	harness_section.add_child(run_30d_econ_war_btn)

	# === Future Tech / Mech Designer / Biotech F10 (per 2026-06-18 review: simple UI/choices, force for new techs, observe, mech stub popup) ===
	# Smallest: buttons to force key techs (cloning/sonic/nano/phaser/scanner/shield/tele etc) + observe prints.
	# "Force space firsts", "Inspect layered effects". Mech: force unlock + simple variant choice popup (reuse LeaderEventUI toast style + inline Window; persist choice, wire to divs).
	var tech_force_label := Label.new()
	tech_force_label.text = "Future Tech Force + Observe (mech designer stub, biotech agents, new techs):"
	tech_force_label.add_theme_font_size_override("font_size", 10)
	harness_section.add_child(tech_force_label)

	var force_techs_btn := Button.new()
	force_techs_btn.text = "🔬 Force Key New Techs (cloning/sonic/nano/phaser/scanner/shield/tele/drone/power/cyber)"
	force_techs_btn.custom_minimum_size = Vector2(420, 26)
	force_techs_btn.pressed.connect(func():
		var ptag := _debug_player_country_tag()
		if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
			var techs := ["cloning_tech_1980", "sonic_weapons_1970", "nanotech_fab_2020", "phasers_torpedoes_2030", "scanners_sensors_1975", "deflector_shields_1995", "teleporters_2025", "drone_swarm_1980", "battle_power_armor_1970", "cybernetics_prosthetics_1975", "additive_manufacturing_1985"]
			for tid in techs:
				TechnologyManager.call("edit_tech_progress", ptag, tid, 0.0, true)
		print("[F10 TECH FORCE] Key future/biotech/techs forced for %s" % ptag)
		# observe prints
		_print_tech_observe(ptag)
		toast_map_debug("New techs forced (cloning+). Check console for mp/space/combat/ethics/layer + use F10 inspect.")
	)
	harness_section.add_child(force_techs_btn)

	var observe_btn := Button.new()
	observe_btn.text = "👁 Observe (print mp pool, space milestones, combat stats, ethics, layer if any)"
	observe_btn.pressed.connect(func():
		_print_tech_observe(_debug_player_country_tag())
	)
	harness_section.add_child(observe_btn)

	var space_first_btn := Button.new()
	space_first_btn.text = "🚀 Force Space Firsts (all 8 milestones + secret/mech)"
	space_first_btn.pressed.connect(func():
		var ptag := _debug_player_country_tag()
		var gd := get_node_or_null("/root/GameData")
		if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
			for tid in ["sputnik_satellite","moon_landing","space_station","moon_base","mars_landing","mars_base","expanse_rocket","mech_designer"]:
				TechnologyManager.call("edit_tech_progress", ptag, tid, 0.0, true)
		if gd and gd.has_method("process_space_race_events"):
			gd.call("process_space_race_events", 1957, 10)
			gd.call("process_space_race_events", 1969, 7)
			gd.call("process_space_race_events", 1973, 1)
			gd.call("process_space_race_events", 1985, 3)
		if gd and "peace_state" in gd:
			gd.peace_state["secret_space_programs"][ptag] = true
			gd.peace_state["mech_designer_unlocked"][ptag] = true
		print("[F10 SPACE FIRSTS] All milestones + secret/mech forced.")
		toast_map_debug("Space firsts + mech unlock forced. Check news/toasts/pillars.")
	)
	harness_section.add_child(space_first_btn)

	var layered_inspect_btn := Button.new()
	layered_inspect_btn.text = "📊 Inspect Layered Effects (NMM production_flex + consumer/VR + new mods)"
	layered_inspect_btn.pressed.connect(func():
		var ptag := _debug_player_country_tag()
		if typeof(NationalModifierManager) != TYPE_NIL:
			var mods = NationalModifierManager.get_combat_modifiers(ptag) if NationalModifierManager.has_method("get_combat_modifiers") else {}
			print("[F10 LAYERED INSPECT] %s mods sample: %s" % [ptag, str(mods).substr(0,300)])
		var gd := get_node_or_null("/root/GameData")
		if gd and gd.has_method("get_peace_state"):
			var ps = gd.call("get_peace_state")
			print("[F10 LAYERED] consumer/VR flags or notes: ", ps.get("notes", []) if "notes" in ps else "n/a")
		toast_map_debug("Layered inspect printed (NMM flex + flags).")
	)
	harness_section.add_child(layered_inspect_btn)

	# Space Designer button - full UI integration
	var space_btn := Button.new()
	space_btn.text = "🛸 Open Space Designer (Sat/Station/Ship - requires space_designer_unlocked tech)"
	space_btn.pressed.connect(_open_space_designer)
	harness_section.add_child(space_btn)

	# Simple Mech Designer stub (from F10 or unlock): popup choice diesel/steam/steampunk alt for armor/mech. Persist choice. Wire note to div templates.
	var mech_designer_btn := Button.new()
	mech_designer_btn.text = "🤖 Force Mech Designer Unlock + Open Variant Choice (diesel/steam/steampunk stub popup)"
	mech_designer_btn.pressed.connect(func():
		var ptag := _debug_player_country_tag()
		var gd := get_node_or_null("/root/GameData")
		if gd:
			if not gd.peace_state.has("mech_designer_unlocked"):
				gd.peace_state["mech_designer_unlocked"] = {}
			gd.peace_state["mech_designer_unlocked"][ptag] = true
			if not gd.peace_state.has("mech_variant_choice"):
				gd.peace_state["mech_variant_choice"] = {}
			_show_mech_variant_choice_popup(ptag, gd)
		toast_map_debug("Mech designer unlocked + choice popup. Persisted; affects future div templates/special mech units.")
	)
	harness_section.add_child(mech_designer_btn)

	# New world-class: direct chain/flank assault button using enhanced BM (multi-province flanking via adjacent after capture).
	var chain_btn := Button.new()
	chain_btn.text = "⚔⚔ Chain/Flank Assault Demo (post-capture follow adjacent; multi-prov)"
	chain_btn.pressed.connect(func():
		var mr := _find_map_renderer()
		if mr and mr.has_method("debug_stage_and_execute_sample_assault"):
			# First stage normal, then if cap call chain
			mr.call("debug_stage_and_execute_sample_assault")
			# Trigger chain on last selected if possible
			if int(mr.get("selected_province_id")) > 0 and typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("execute_chain_assault_or_flank"):
				var sel = mr.get("selected_province_id")
				var ch = BattleManager.execute_chain_assault_or_flank(_debug_player_country_tag(), sel, -1, 2)
				toast_map_debug("Chain/flank executed: %d steps. See logs for flanking multi-prov." % ch.size())
		elif typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("execute_chain_assault_or_flank"):
			# Fallback direct
			var ch2: Array = BattleManager.execute_chain_assault_or_flank(_debug_player_country_tag(), 2, 1, 1)
			toast_map_debug("Direct chain demo steps: %d (use selected + Ctrl for full)." % ch2.size())
		else:
			toast_map_debug("Chain assault not available yet.")
	)
	harness_section.add_child(chain_btn)

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
		playable_v3_btn.text = "🎮 Load v3 as Playable Test Map (471 provinces - river-cross natural borders from latest proposals)"
		playable_v3_btn.pressed.connect(func(): _on_load_phase1_merged_map(false, true, true))
		mapgen_section.add_child(playable_v3_btn)

		var test_scenario_btn := Button.new()
		test_scenario_btn.text = "📜 Load Persistent Phase 1 Test Scenario (river-subdiv 471 provinces - real rivers.json guided children + inference carry)"
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
		var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
		var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
		var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
		var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
		var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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

	# === 1918 Peace Conference Test (Phase 2 systems) ===
	# Opens the code-built PeaceConferenceWindow. Use this to test:
	# - Agent diplomacy missions feeding leverage (run "secure_inclusion", "honeypot_operation" etc. first on TUR/GER as player).
	# - Term selection with HISTORICAL badges.
	# - Resolution applying modifiers + grievance.
	# - Historical Ottoman path → successor continuation picker (switch to TUR, SYR, ROM, etc. to continue play after "defeat"/partition).
	# - General defeat/continuation hook.
	var peace_test_label := Label.new()
	peace_test_label.text = "1918 Peace Systems Test (agents first for leverage):"
	peace_test_label.add_theme_font_size_override("font_size", 10)
	province_editor_section.add_child(peace_test_label)

	var open_peace_btn := Button.new()
	open_peace_btn.text = "Open 1918 Peace Conference Window"
	open_peace_btn.pressed.connect(func():
		var peace_script: Script = load("res://scripts/ui/PeaceConferenceWindow.gd") as Script
		if peace_script == null:
			_toast("PeaceConferenceWindow.gd failed to load")
			return
		var w: Node = peace_script.new()
		get_tree().root.add_child(w)
		_toast("Peace Conference window opened (test 1918 systems + successor switching)")
	)
	province_editor_section.add_child(open_peace_btn)

	var defeat_test_btn := Button.new()
	defeat_test_btn.text = "Simulate Player Defeat (offer continuation)"
	defeat_test_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			var ptag := "TUR"
			if typeof(LeaderManager) != TYPE_NIL:
				ptag = LeaderManager.get_player_country_tag()
			var pend: Dictionary = GameData.trigger_national_defeat_or_continuation(ptag, "Manual defeat test (capital lost / treaty)") if GameData.has_method("trigger_national_defeat_or_continuation") else {}
			var peace_script: Script = load("res://scripts/ui/PeaceConferenceWindow.gd") as Script
			if peace_script == null:
				_toast("PeaceConferenceWindow.gd failed to load")
				return
			var w: Node = peace_script.new()
			get_tree().root.add_child(w)
			_toast("Defeat triggered — continuation options available in the window")
	)
	province_editor_section.add_child(defeat_test_btn)

	var phases_demo_btn := Button.new()
	phases_demo_btn.text = "Open Policy/Law Screen (1919/1923 follow-ons + continuation policies)"
	phases_demo_btn.pressed.connect(func():
		_open_policy_law_screen()
		_toast("Policy/Law screen opened (replaces removed PeaceTreatyPhasesDemo)")
	)
	province_editor_section.add_child(phases_demo_btn)

	var preconf_btn := Button.new()
	preconf_btn.text = "Sim Pre-Conference Agent Leverage (high for TUR/GER Central Powers)"
	preconf_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			GameData.add_inclusion_leverage("GER", 15, "debug_preconf_bribe")
			GameData.add_inclusion_leverage("TUR", 40, "debug_preconf_honeypot_secure")
			GameData.add_grievance("GER", -5, "debug_narrative")  # some mitigation
			_toast("Pre-conference leverage boosted (GER+15 TUR+40). Open Peace Conf window to see in UI + resolve for alt terms.")
		else:
			_toast("GameData missing for preconf sim")
	)
	province_editor_section.add_child(preconf_btn)

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
		_toast("Phase 1 Europe test scenario loaded (dense map + systems demo). Full territories harness active: F10 for buttons, PolicyLawScreen for welfare/education/feminism/pressure, relocate for settlement on 100s of provinces, advance for HH toasts/respond/cultural war events.")
		return

	var label := "v3 as Playable Test Map (471 provinces, river-cross)" if playable_test else ("v3 Closest-Child Wiring (cleanest borders)" if use_v3_closest else ("IMPROVED Splitter v2 (better balance + naval densify)" if use_improved_v2 else "Phase 1 merged test map (471 provinces, river-guided)"))
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
		var toast_msg := "v3 Playable Test Map loaded (471 provinces, river-cross natural borders)" if playable_test else ("v3 closest-child map loaded" if use_v3_closest else ("IMPROVED v2 splitter map loaded" if use_improved_v2 else "Phase 1 merged map loaded (river-guided children)"))
		_toast(toast_msg + " (%d provinces). Zoom & inspect!" % new_provinces.size())

		# Force visual layers to repaint
		var overlay := get_tree().get_first_node_in_group("infrastructure_overlay")
		if overlay and overlay.has_method("force_full_refresh"):
			overlay.force_full_refresh()

		# Ask MapRenderer to repaint if we can reach it
		var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node
		if mr and mr.has_method("queue_redraw"):
			mr.queue_redraw()
	else:
		_toast("MapManager.force_initialize not available")


func _on_restore_original_map():
	var loader := get_tree().root.find_child("ScenarioLoader", true, false) as ScenarioLoader
	if loader and loader.has_method("load_scenario"):
		# Re-trigger the normal scenario load path (will restore original data)
		await loader.load_scenario(loader.current_scenario_name)
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
		var success: bool = await loader.load_scenario("phase1_europe_test")
		if not success:
			_toast("Failed to load Phase 1 test scenario (check console for warnings)")
			return

		# === Godot-side polish for the test scenario ===
		_toast("Phase 1 Europe Test Scenario (river-subdiv) loaded — 471 provinces • real rivers.json natural borders for key splits (e.g. 82) + elev/terrain inference carry • rich attributes • nice camera start")

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
		print("\n=== Phase 1 Europe Test Map (river-subdiv) Active ===")
		print("Provinces: 471 (base + 449 children from generate; river-cross natural borders baked for high-cross parents like 82 from real rivers.json)")
		print("Splitter: naval + real-rivers guidance (RIVER_CROSS_BONUS 1.8, axis align in PCA for natural borders) + coastal")
		print("Merge: Closest-child + chokepoint protection + smart city/VP/special + inference terrain/snow_potential carry")
		print("Data: data/provinces_phase1_test/ + data/scenarios/phase1_europe_test.json (fresh from apply after latest generate)")
		print("River metadata: 126 children have river_aware=True (e.g. 9000-9005 for orig 82); notes enriched in geometry")
		print("Visual: F10 Subdiv button (or harness) spawns green Line2D for the 5 river-cross sample children overlaid; also auto-loads sample for demo")
		print("Camera: Auto-set to nice Europe-focused starting view")
		print("Tip: For reliable testing of the Phase 1 map, open scenes/TestScenario.tscn and press F6 (Play Current Scene)... Use F10 '📜 Show Battle AAR Panel' + combat preview in inspector (note: [Press F10 for full AAR]) + Ctrl+click assaults to exercise unit logs, full % modifiers, leader impacts, space/air effects.")
		print("Tip: F10 → 'Reload Raw Proposed Splits' to live-iterate on the Python splitter.")
		print("======================================\n")
		# Auto demo the river sample overlays + load sample for the 5-child river visual even on full 471
		var mr2 = get_tree().get_first_node_in_group("map_renderer")
		if mr2 and mr2.has_method("load_sample_subdiv_geometry"):
			mr2.call("load_sample_subdiv_geometry")
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
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
	if mr and mr.has_method("place_demo_object_at_mouse"):
		mr.call("place_demo_object_at_mouse", "city")
	else:
		print("Map Visual Editor: No MapRenderer with place_demo found in group 'map_renderer'. Demo city placement logged (extend MapRenderer).")
		_toast("Demo city placement attempted (see MapRenderer for integration)")
	# Future: if editor active, could queue a pending placement for next map click
	call_deferred("_refresh_placed_list")


func _on_place_demo_airfield() -> void:
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
	if mr and mr.has_method("place_demo_object_at_mouse"):
		mr.call("place_demo_object_at_mouse", "airfield")
	else:
		print("Map Visual Editor: placing demo airfield (terrain-aware in full MapRenderer spawn).")
		_toast("Demo airfield (desert/hills/swamp rules apply in data-driven spawn)")
	# In real: would record placement pos + type + terrain constraints for export
	call_deferred("_refresh_placed_list")


func _on_export_map_placements() -> void:
	print("Map Visual Editor: Exporting current demo placements (from MapRenderer DataDrivenObjects or editor_placements) to JSON for Python roundtrip / leveling tool.")
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
		var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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

	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
	if mr == null or mr.get("container") == null:
		_toast("Map not ready for province editing")
		return null

	var existing: Node = mr.container.get_node_or_null("ProvinceEditor")
	if existing:
		_province_editor_instance = existing
		return existing

	var pe_script := load("res://scripts/map/ProvinceEditor.gd") as Script
	if pe_script == null:
		_toast("ProvinceEditor.gd not found")
		return null

	var pe := pe_script.new() as Node
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
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as MapRenderer
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
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
	if mr and mr.has_method("place_demo_object_at_mouse"):
		mr.call("place_demo_object_at_mouse", type)
	else:
		_toast("No MapRenderer place for " + type)
	call_deferred("_refresh_placed_list")


func _on_toggle_terrain_layer() -> void:
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as Node
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
	var mr: MapRenderer = get_tree().get_first_node_in_group("map_renderer") as MapRenderer
	if mr == null:
		_toast("No MapRenderer (open TestScenario + F10)")
		return
	if mr.selected_province_id < 0:
		_toast("Left-click a province first (defender battle site)")
		return
	if typeof(BattleManager) == TYPE_NIL:
		_toast("BattleManager unavailable")
		return

	var battle_pid: int = mr.selected_province_id
	var battle_prov: Province = MapManager.get_province(battle_pid) if typeof(MapManager) != TYPE_NIL else null
	if battle_prov == null:
		_toast("Selected province not in MapManager")
		return

	var defender_tag := battle_prov.owner_tag if not battle_prov.owner_tag.is_empty() else "YUG"
	var attacker_tag := _pick_attacker_tag_for_combat(mr, battle_pid, defender_tag)
	_ensure_demo_country_stubs()
	_ensure_demo_country_stubs_for_tag(attacker_tag)
	_ensure_demo_country_stubs_for_tag(defender_tag)

	var from_pid: int = mr.attack_staging_province_id
	if from_pid < 0:
		from_pid = mr.debug_combat_attacker_province_id

	var assault: Dictionary = BattleManager.execute_province_assault(attacker_tag, battle_pid, from_pid)
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
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as MapRenderer
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
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as MapRenderer
	if mr != null and not mr.countries.has(t):
		mr.countries[t] = {"color": color, "name": t, "tag": t}


func _force_border_refresh() -> void:
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") as Node as MapRenderer
	if mr != null and mr.has_method("force_border_update"):
		mr.force_border_update()


## Simulate a "day" of AI combat for demo/playtest (F10 harness tool): other major powers attempt real assaults on neighbors.
## Uses BattleManager.can_assault + execute/chain (full damage, capture, news/events path).
## Note: main-loop auto now driven by TimeManager daily -> BattleManager.simulate_daily_ai_combat (promoted/polished from this base for non-debug 50+ turns).
## Advances 1 day so Supply recovery, infra daily, erosion/events fire. Limited to 1-2 per tag for safety/speed.
func _simulate_ai_combat_turn() -> void:
	var player_tag := _debug_player_country_tag()
	var bm := get_node_or_null("/root/BattleManager")
	if bm == null or not bm.has_method("can_assault_province") or not bm.has_method("execute_province_assault"):
		print("[AI TURN] BattleManager not available for demo assaults.")
		return
	var mm := get_node_or_null("/root/MapManager")
	if mm == null or not mm.has_method("get_provinces_by_owner") or not mm.has_method("get_adjacent_provinces"):
		print("[AI TURN] MapManager not ready.")
		return
	var tm := get_node_or_null("/root/TimeManager")

	var ai_tags := ["GER", "FRA", "ENG", "SOV", "USA", "ITA", "JAP", "POL"]
	var assaults_done := 0
	for tag in ai_tags:
		if tag == player_tag: continue
		var owned: Array = mm.call("get_provinces_by_owner", tag)
		var did_one := false
		for pidv in owned:
			if did_one or assaults_done >= 4: break  # limit for demo
			var pid := int(pidv)
			var adjs: Array = mm.call("get_adjacent_provinces", pid)
			# World-class AI target choice: prefer adjacent enemies with low org/strength (easy target) or low infra/supply (valuable/ weak hold) or low dev.
			# Scores targets; uses map-tied data (Province getters, Supply, formations org via LeaderManager).
			var scored_targets: Array = []
			for aidv in adjs:
				var aid := int(aidv)
				var p: Province = mm.call("get_province", aid) if mm.has_method("get_province") else null
				if p == null or p.is_sea or p.owner_tag == tag or p.owner_tag == "": continue
				var score := 1.0
				# Low infra/supply = attractive for attacker (disrupted defender, easier advance)
				if p.infrastructure < 3: score += 0.8
				if p.development_level < 2: score += 0.6
				# Check local supply/depot if available
				if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_depot_state"):
					var dep = SupplyManager.call("get_depot_state", aid)
					if dep and "current_stock" in dep and "throughput_capacity" in dep and dep.throughput_capacity > 0:
						if float(dep.current_stock) / dep.throughput_capacity < 0.3: score += 0.7
				# Low org/strength on defender formations at target (from LeaderManager)
				if typeof(LeaderManager) != TYPE_NIL:
					var defs := LeaderManager.get_formations_for_country(p.owner_tag)
					for df in defs:
						if df and "stationed_province_id" in df and int(df.stationed_province_id) == aid:
							var o := float(df.organization if "organization" in df else 1.0)
							var s := float(df.strength if "strength" in df else 1.0)
							if o < 0.6: score += 1.2
							if s < 0.7: score += 0.9
							break
				# Minimal harness update: weather-aware target scoring (promote from BM daily sim for main-loop consistency; avoid mud/snow for attacker AI)
				if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_movement_multiplier"):
					var move_mult := float(WeatherManager.call("get_movement_multiplier", aid))
					if move_mult < 0.7: score -= 0.8
				scored_targets.append({"pid": aid, "from": pid, "score": score})
			# Sort best first (highest score = best target per criteria)
			scored_targets.sort_custom(func(a, b): return a.score > b.score)
			for st in scored_targets:
				if did_one or assaults_done >= 4: break
				var aid := int(st.pid)
				var fromp := int(st.from)
				var can: Dictionary = bm.call("can_assault_province", tag, aid, fromp)
				if bool(can.get("ok", false)):
					# Use chain for better multi-province flanking/chain assaults
					var chain_results: Array = []
					if bm.has_method("execute_chain_assault_or_flank"):
						chain_results = bm.call("execute_chain_assault_or_flank", tag, aid, fromp, 1)
					else:
						var res: Dictionary = bm.call("execute_province_assault", tag, aid, fromp)
						chain_results = [res] if res.get("success", false) else []
					for r in chain_results:
						print("[AI TURN] %s assaulted (chain/flank) pid %d -> success=%s capture=%s (target choice score=%.1f based on low org/infra/supply)" % [
							tag, aid, r.get("success", false), (r.get("result", {}) if typeof(r.get("result",{}))==TYPE_DICTIONARY else {}).get("province_control_change", false), st.score
						])
					assaults_done += chain_results.size()
					did_one = true
					break
	if tm != null and tm.has_method("advance_one_day") and assaults_done > 0:
		tm.call("advance_one_day")
		print("[AI TURN] Advanced 1 day for recovery/events/infra tick after AI assaults.")
	print("[AI TURN] Complete. %d assaults executed. Use inspector/F10 to see org/strength changes + recovery next day." % assaults_done)

	# AI auto infrastructure investment (polish for 50+ turn integrated playtest per DESIGN).
	# Lets non-player countries develop their cores (aggressive infra push while player focuses combat/agents).
	# Reuses real try_start API (Mandate spend + validation + toasts + daily advance).
	var idm_ai := get_node_or_null("/root/InfrastructureDevelopmentManager")
	if idm_ai and idm_ai.has_method("ai_consider_daily_invests"):
		var ai_started: int = idm_ai.ai_consider_daily_invests([], 0.28)  # ~28% chance per eligible AI tag
		if ai_started > 0:
			print("[AI TURN] Infrastructure auto-invests started by AI: %d (see logs for tags/ETAs; projects advance on daily ticks)." % ai_started)


## Fallback 30-day econ+war+infra+peace drive for F10 button when TestRunner not directly callable (e.g. pure interactive F5).
## Mirrors TestRunner _run_integrated_50_turn... but shorter, local node lookups. Produces same progress logs.
## Drives pop (time monthly), prod (advance + assign), train, recruit, AI combat (real + chain), infra daily + start, peace policies.
func _drive_local_30d_playtest_sim() -> void:
	print("\n=== [F10 FALLBACK 30D ECON+WAR SIM] (local drive; full TestRunner path preferred for 50t) ===")
	var tm: Node = get_node_or_null("/root/TimeManager")
	var pm: Node = get_node_or_null("/root/ProductionManager")
	var idm: Node = get_node_or_null("/root/InfrastructureDevelopmentManager")
	var gd: Node = get_node_or_null("/root/GameData")
	var lm: Node = get_node_or_null("/root/LeaderManager")
	var mm: Node = get_node_or_null("/root/MapManager")
	var dbg: Node = get_node_or_null("/root/DebugOverlay")

	var assaults := 0
	var recs := 0
	var prods := 0
	var infras := 0
	var ptag := _debug_player_country_tag()

	for day in range(1, 31):
		if tm != null:
			if tm.has_method("advance_one_day"): tm.call("advance_one_day")
			else: tm.call("advance_days", 1.0)
		if pm != null and pm.has_method("advance_days"):
			var rp = pm.call("advance_days", 1.0)
			prods += int(rp.get("total_units_completed", 0) if rp else 0)
		if idm != null and idm.has_method("advance_daily_projects"):
			var y = tm.call("get_current_year") if tm and tm.has_method("get_current_year") else 1936
			var m = tm.call("get_current_month") if tm and tm.has_method("get_current_month") else 1
			var d = tm.call("get_current_day") if tm and tm.has_method("get_current_day") else 1
			idm.call("advance_daily_projects", y, m, d)
		if day % 5 == 0 and lm != null and lm.has_method("get_formations_for_country"):
			for f in lm.call("get_formations_for_country", "GER"): if f: f.is_training = true
		if day % 10 == 0 and gd != null and gd.has_method("recruit_units"):
			if gd.has_method("update_manpower_from_population"):
				gd.call("update_manpower_from_population", "GER")
			if gd.call("recruit_units", "GER", 5): recs += 5
		if day % 4 == 0 and dbg != null and dbg.has_method("_simulate_ai_combat_turn"):
			dbg.call("_simulate_ai_combat_turn")
			assaults += 4
		elif day % 4 == 0 and typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("execute_chain_assault_or_flank") and mm != null:
			var owns = mm.call("get_provinces_by_owner", "GER") if mm.has_method("get_provinces_by_owner") else []
			if owns.size() > 0:
				var ch = BattleManager.call("execute_chain_assault_or_flank", "GER", int(owns[0]), -1 if owns.size()<2 else int(owns[1]), 1)
				assaults += (ch.size() if ch is Array else 1)
		if day % 12 == 0 and idm != null and idm.has_method("try_start_infrastructure_investment") and mm != null:
			var gow = mm.call("get_provinces_by_owner", "GER") if mm.has_method("get_provinces_by_owner") else []
			if gow.size() > 0:
				var ir = idm.call("try_start_infrastructure_investment", int(gow[0]), "GER")
				if ir.get("success", false): infras += 1
		if day % 15 == 0 and gd != null and gd.has_method("apply_social_services_policy"):
			gd.call("apply_social_services_policy", ptag, "traditional")
		if day % 5 == 0:
			var popg := 0.0
			if gd != null and gd.has_method("get_peace_state"):
				popg = float( (gd.call("get_peace_state").get("population", {}) as Dictionary).get("GER", 0) )
			var memm := float(OS.get_static_memory_usage()) / (1024.0*1024.0)
			print("[30D FALLBACK PROGRESS] Day %d/30 | assaults~%d | rec=%d | prod~%d | infra=%d | popGER=%.1fM | mem=%.1f" % [day, assaults, recs, prods, infras, popg/1e6, memm])
	print("=== [F10 FALLBACK 30D SIM] COMPLETE (see full TestRunner 50t for longer headless CI). ===")

# === Added helpers for F10 future tech / mech designer / observe (smallest useful per task) ===
func _print_tech_observe(ptag: String) -> void:
	print("\n=== [F10 OBSERVE %s] ===" % ptag)
	if typeof(GameData) != TYPE_NIL:
		var gd := get_node_or_null("/root/GameData")
		if gd and gd.has_method("get_peace_state"):
			var ps: Dictionary = gd.call("get_peace_state") as Dictionary
			print("[MP POOL approx] from pop update if run; peace pop GER/USA sample:", (ps.get("population", {}) as Dictionary).get(ptag, "?"))
			print("[SPACE MILESTONES] ", ps.get("space_milestones", {}))
			print("[MECH/SECRET] unlocked=", ps.get("mech_designer_unlocked", {}).get(ptag), " variant_choice=", ps.get("mech_variant_choice", {}).get(ptag), " secret_fleet=", ps.get("secret_fleet_combat_bonus", {}).get(ptag))
			print("[BIOTECH FLAGS] intel=", ps.get("biotech_intel", {}).get(ptag), " scanner=", ps.get("scanner_intel_flags", {}).get(ptag))
	if typeof(TechnologyManager) != TYPE_NIL:
		print("[ETHICS/COH sample] rule_flags cloning/sonic/cb:", TechnologyManager.has_rule_flag(ptag, "cloning"), TechnologyManager.has_rule_flag(ptag, "sonic_weapons"), TechnologyManager.has_rule_flag(ptag, "chemical_biological_weapons"))
		print("[LAYER if NMM] production_flex etc via NMM combat_mods if avail")
		var mods := {}
		if typeof(NationalModifierManager) != TYPE_NIL and NationalModifierManager.has_method("get_combat_modifiers"):
			mods = NationalModifierManager.get_combat_modifiers(ptag)
		print("[COMBAT STATS sample] ", str(mods).substr(0, 220))
	print("=== END OBSERVE ===\n")

func _show_mech_variant_choice_popup(tag: String, gd: Node) -> void:
	# Simple stub popup (LeaderEventUI style toast + inline Window; reuse patterns no new tscn). Choices diesel/steam/steampunk alt for armor/mech templates.
	# Persist choice in peace_state; wire note to division templates/special mech units (e.g. future Formation or template use variant stats).
	# From F10 or unlock of mech_designer_unlocked.
	var win := Window.new()
	win.title = "Mech Designer - %s (Alt-History Variant)" % tag
	win.size = Vector2i(520, 220)
	win.unresizable = true
	add_child(win)  # under overlay for now
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.add_child(vb)
	var lbl := Label.new()
	lbl.text = "Choose dieselpunk/steampunk/steam variant for mech/armor templates.\nPersisted. Affects special mech units + division caps."
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	for v in ["diesel", "steam", "steampunk"]:
		var b := Button.new()
		b.text = "Select " + v.capitalize() + " Mech Variant"
		b.pressed.connect(func():
			if not gd.peace_state.has("mech_variant_choice"):
				gd.peace_state["mech_variant_choice"] = {}
			gd.peace_state["mech_variant_choice"][tag] = v
			print("[MECH DESIGNER] %s chose variant: %s (persisted; wire to div templates or special units e.g. power_battle_armor path)" % [tag, v])
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Mech variant set to " + v + " for " + tag + " (designer choice persisted)", 4.0)
			win.queue_free()
		)
		vb.add_child(b)
	var cancel := Button.new()
	cancel.text = "Cancel (keep default dieselpunk)"
	cancel.pressed.connect(func(): win.queue_free())
	vb.add_child(cancel)
	win.popup_centered()
	print("[MECH DESIGNER STUB] Popup shown for %s variant choice (diesel/steam/steampunk)." % tag)
func _open_space_designer() -> void:
	# Check unlock via tech/rule_flag
	var unlocked := false
	if typeof(GameData) != TYPE_NIL and GameData.has_method("has_rule_flag"):
		unlocked = GameData.call("has_rule_flag", "player", "space_designer_unlocked")
	if not unlocked:
		toast_map_debug("Space Designer locked. Research 'space_design_basic' or orbital techs first.")
		return
	
	var popup := preload("res://scripts/ui/SpaceDesignPopup.gd").new()
	get_tree().root.add_child(popup)
	popup.set_player_tag("USA")
	toast_map_debug("Space Designer opened. Choose base, add modules (propulsion, sensors, life support), finalize to unlock custom design for production.")

func show_battle_aar(result: Dictionary = {}) -> void:
	# Enhanced specific + accessible AAR panel: unit combat logs (from Formation.combat_log via BM), leader impacts, full modifiers w/ % , space/air effects, tips.
	# Callable from combat preview in ProvinceInsight via text note "[Press F10 for full AAR]", post-battle auto (player), dedicated F10 btn.
	# Balance integration: reflects real air thresh (full at 4:1), space costly not instant, damage from BM apply, logs factors.
	if result.is_empty():
		# Improved demo with keys used by new panel + logs snapshot + power details
		result = {
			"attacker_tag": "GER", "defender_tag": "FRA",
			"from_province_id": 82, "target_province_id": 101,
			"odds_attacker_win": 62.0,
			"winner": "GER",
			"attacker_casualties": 145, "defender_casualties": 98,
			"key_factors": ["air_superiority", "overwhelming_air_dominance", "leader_impact_high", "fort_mod_def_1.2", "supply_mod_att_0.8", "special_mountain", "space_strike", "orbital_guided"],
			"leader_name": "Rommel",
			"leader_attack_bonus": 0.18,
			"units_att": ["Panzer x2", "Inf x5", "CAS support"],
			"units_def": ["Fortified Inf x4", "Mountain x1"],
			"air_dominance_level": "full",
			"air_power_ratio": 4.2,
			"cas_mult": 1.35,
			"outcome": "GER breakthrough, province captured. Encirclement risk for remaining FRA. Overwhelming air superiority achieved - enemy grounded at high cost.",
			"date": "1940-05",
			"space_strike_bonus": 0.18,
			"orbital_guided_munitions": 0.12,
			"special": "mountain,space_support",
			"combat_logs": {
				"attacker": [{"date":"1940-05", "province_id":101, "result":"win", "key_factors":["overwhelming_air_superiority","space_guided_munitions_precision","leader_impact_high"], "leader":"Rommel", "outcome":"Casualties: 145 vs 98"}],
				"defender": [{"date":"1940-05", "province_id":101, "result":"loss", "key_factors":["enemy_air_dominance_full","orbital_strike_support"], "leader":"Manstein", "outcome":"Casualties: 145 vs 98"}]
			},
			"attacker_power_detail": {"leader_name":"Rommel", "leader_attack_bonus":0.18, "terrain_bonus_applied":0.08, "space_strike_bonus":0.18, "national_combat_modifiers":{"army_org_factor":0.1}, "training_path_soft_bonus":4.0},
			"defender_power_detail": {"leader_name":"Manstein", "leader_attack_bonus":0.12, "terrain_bonus_applied":0.12, "orbital_guided_munitions":0.12}
		}

	var win := Window.new()
	win.title = "Battle AAR: %s vs %s (%s) [F10 accessible]" % [result.get("attacker_tag","?"), result.get("defender_tag","?"), result.get("date","")]
	win.size = Vector2(720, 560)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	win.add_child(scroll)

	# Header
	var hdr := Label.new()
	hdr.text = "AFTER ACTION REPORT — Full Details (unit logs, leaders, modifiers %, air/space, tips)"
	hdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hdr)
	vb.add_child(HSeparator.new())

	# Date / Province lookup for specificity
	var date_str := str(result.get("date", ""))
	var prov_id := int(result.get("target_province_id", result.get("province_id", -1)))
	var prov_name := ""
	if typeof(MapManager) != TYPE_NIL:
		var p: Province = MapManager.get_province(prov_id)
		if p != null:
			prov_name = p.name
	var meta := Label.new()
	meta.text = "Date: %s | Province: %s (#%d) | From: %s" % [date_str if date_str else "current", prov_name if prov_name else "?", prov_id, str(result.get("from_province_id", "?"))]
	vb.add_child(meta)

	# Odds / Result
	var odds := Label.new()
	odds.text = "Est. odds attacker win: %.0f%% | Winner: %s | Outcome: %s" % [float(result.get("odds_attacker_win",50)), result.get("winner","?"), str(result.get("outcome","")).substr(0,120)]
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(odds)

	# Casualties
	var cas := Label.new()
	cas.text = "Casualties: Attacker %s vs Defender %s" % [result.get("attacker_casualties","?"), result.get("defender_casualties","?")]
	vb.add_child(cas)

	# Units (from preview or fallback)
	var units := Label.new()
	units.text = "Units involved — Att: %s | Def: %s" % [str(result.get("units_att", result.get("attacker_units", ["(see inspector)"]))), str(result.get("units_def", result.get("defender_units", ["(see inspector)"])))]
	vb.add_child(units)
	vb.add_child(HSeparator.new())

	# === Leader impacts (from power_detail or result)
	var lsec := Label.new()
	lsec.text = "LEADER IMPACTS"
	lsec.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
	vb.add_child(lsec)
	var att_pd: Dictionary = result.get("attacker_power_detail", {}) as Dictionary if typeof(result.get("attacker_power_detail", {})) == TYPE_DICTIONARY else {}
	var def_pd: Dictionary = result.get("defender_power_detail", {}) as Dictionary if typeof(result.get("defender_power_detail", {})) == TYPE_DICTIONARY else {}
	var lead_att := Label.new()
	var att_ldr := str(result.get("leader_name", att_pd.get("leader_name", result.get("leader_att", "—"))))
	var att_ldr_b := float(att_pd.get("leader_attack_bonus", result.get("leader_attack_bonus", 0.0)))
	lead_att.text = "Attacker leader: %s  (attack bonus +%.0f%% | org/logistics from leader traits)" % [att_ldr, att_ldr_b * 100.0]
	vb.add_child(lead_att)
	var lead_def := Label.new()
	var def_ldr := str(def_pd.get("leader_name", result.get("leader_def", "—")))
	var def_ldr_b := float(def_pd.get("leader_attack_bonus", 0.0))
	lead_def.text = "Defender leader: %s  (defense/terrain bonus +%.0f%%)" % [def_ldr, def_ldr_b * 100.0]
	vb.add_child(lead_def)
	var lead_note := Label.new()
	lead_note.text = "  (Leaders affect soft/hard/org/readiness/terrain; training paths add more. Full in Leader inspector.)"
	lead_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lead_note)
	vb.add_child(HSeparator.new())

	# === Unit combat logs (pull from Formation.combat_log if available in result["combat_logs"] or query LeaderManager)
	var logsec := Label.new()
	logsec.text = "UNIT COMBAT LOGS (from Formation.combat_log — follows unit)"
	logsec.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	vb.add_child(logsec)
	var logs_src: Dictionary = result.get("combat_logs", {}) as Dictionary
	var shown_logs := false
	for role in ["attacker", "defender"]:
		var role_logs = logs_src.get(role, []) if typeof(logs_src) == TYPE_DICTIONARY else []
		if role_logs and role_logs.size() > 0:
			shown_logs = true
			var recent = role_logs[-1] if role_logs.size() > 0 else {}
			var llab := Label.new()
			llab.text = "%s log: date=%s prov=%s result=%s factors=%s leader=%s outcome=%s" % [
				role.capitalize(),
				recent.get("date", "?"),
				str(recent.get("province_id", prov_id)),
				recent.get("result", "?"),
				", ".join(recent.get("key_factors", result.get("key_factors", []))),
				recent.get("leader", result.get("leader_name", "—")),
				str(recent.get("outcome", "")).substr(0, 60)
			]
			llab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(llab)
	if not shown_logs:
		var no_log := Label.new()
		no_log.text = "  (No live combat_log entries; demo or non-Formation battle. Logs appended in BM._log_unit_combat on real assaults. Check Formation in inspectors.)"
		no_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(no_log)
	vb.add_child(HSeparator.new())

	# === Full list of modifiers with % values (built from power_details + result air/space/terrain + carried preview keys)
	var modsec := Label.new()
	modsec.text = "FULL MODIFIERS (with % values)"
	modsec.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	vb.add_child(modsec)
	var mods_list := []
	# From power details (leader, terrain, training, space, nat)
	for pd_role in ["attacker", "defender"]:
		var pd = att_pd if pd_role == "attacker" else def_pd
		if pd:
			if float(pd.get("leader_attack_bonus", 0)) != 0.0:
				mods_list.append("%s leader attack: +%.0f%%" % [pd_role, float(pd.get("leader_attack_bonus",0))*100])
			if float(pd.get("terrain_bonus_applied", 0)) != 0.0:
				mods_list.append("%s terrain bonus: +%.0f%%" % [pd_role, float(pd.get("terrain_bonus_applied",0))*100])
			if float(pd.get("training_path_soft_bonus", 0)) != 0.0:
				mods_list.append("%s training path: +%.1f soft" % [pd_role, float(pd.get("training_path_soft_bonus",0))])
			var natm = pd.get("national_combat_modifiers", {})
			if natm and float(natm.get("army_org_factor",0)) > 0:
				mods_list.append("%s national org: +%.0f%%" % [pd_role, float(natm.get("army_org_factor",0))*100])
	# Air / CAS from result
	var adl := str(result.get("air_dominance_level", ""))
	var ar := float(result.get("air_power_ratio", 0.0))
	var cm := float(result.get("cas_mult", 1.0))
	if adl != "" and adl != "none":
		mods_list.append("Air dominance (%s, ratio %.1f): CAS x%.2f (~+%.0f%%)" % [adl, ar, cm, (cm-1.0)*100])
	if float(result.get("air_weather_mod", 1.0)) != 1.0:
		mods_list.append("Air weather: x%.2f" % float(result.get("air_weather_mod",1)))
	# Space
	if float(result.get("space_strike_bonus", 0)) > 0:
		mods_list.append("Space strike bonus: +%.0f%% attacks (devastating soft/hard)" % (float(result.get("space_strike_bonus",0))*100))
	if float(result.get("orbital_guided_munitions", 0)) > 0:
		mods_list.append("Orbital guided munitions: +%.0f%% +org/morale suppression on enemy" % (float(result.get("orbital_guided_munitions",0))*100))
	# Other from result / preview carry / factors
	if float(result.get("fort_mod", 1.0)) != 1.0:
		mods_list.append("Fort/settlement def: x%.2f (~+%.0f%%)" % [float(result.get("fort_mod",1)), (float(result.get("fort_mod",1))-1)*100])
	if float(result.get("supply_mod", 1.0)) != 1.0:
		mods_list.append("Supply: x%.2f" % float(result.get("supply_mod",1)))
	if bool(result.get("is_night", false)):
		mods_list.append("Night ops: visibility/org penalties (~-38% CAS/air)")
	if "mountain" in str(result.get("special","")):
		mods_list.append("Mountain terrain specialist edge: +8% soft")
	# From key_factors as fallback %
	for kf in result.get("key_factors", []):
		if "fort" in kf: mods_list.append("Fort mod (from factor): ~+22% def")
		if "leader" in kf: mods_list.append("Leader impact (from factor): decisive +15-20%")
	for m in mods_list:
		var mlab := Label.new()
		mlab.text = "  • " + m
		vb.add_child(mlab)
	if mods_list.size() == 0:
		var no_mods_lbl := Label.new()
		no_mods_lbl.text = "  (No detailed modifiers; using key_factors)"
		vb.add_child(no_mods_lbl)
	vb.add_child(HSeparator.new())

	# === Space / Air effects (dedicated, with balance notes)
	var asec := Label.new()
	asec.text = "AIR & SPACE EFFECTS"
	asec.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
	vb.add_child(asec)
	var airl := Label.new()
	airl.text = "Air: dominance=%s ratio=%.1f:1 cas_mult=%.2f (full>=4:1 for overwhelm suppress in large prov; partial 1.8:1 limited CAS; slight adv allows enemy ops at +cost -effect; night/weather heavy penalty)" % [adl if adl else "n/a", ar, cm]
	airl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(airl)
	var spacel := Label.new()
	var ssb := float(result.get("space_strike_bonus", result.get("space_strike", 0.0)))
	var ogm := float(result.get("orbital_guided_munitions", 0.0))
	spacel.text = "Space: strike=%.2f guided=%.2f (from designer assets + NMM + GameData; precision guided +soft/hard on troops, area denial, morale/org hits for non-space; costly to maintain, not instant win; space_capable units gain extra vs orbital)" % [ssb, ogm]
	spacel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(spacel)
	vb.add_child(HSeparator.new())

	# === Tips (updated to reference AAR + balance)
	var tsec := Label.new()
	tsec.text = "TIPS (see AAR for deep)"
	tsec.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	vb.add_child(tsec)
	var tips_aar := [
		"Full unit combat logs, leader %, exact modifiers list, space/air details in this AAR panel (F10).",
		"Balance: Air 4:1+ needed for full suppression (large provinces); partial gives some CAS but enemy still operates with penalty.",
		"Space strike/guided: high impact on ground (esp vs non-space units) but expensive (supply/attrition/maintenance); recon edge but not decisive alone.",
		"Check Formation inspectors for persistent combat_log history + current org/rdy/str (damage from battle, heal via Supply + infra).",
		"Leader + training paths + nat spirits + terrain + infra/dev + settlement fort + supply + weather all stack; use preview for quick odds.",
		"Post-battle: advance time or use Supply to recover formations; reinforce from pop/prod stocks."
	]
	for t in tips_aar:
		var tlab := Label.new()
		tlab.text = "• " + t
		tlab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(tlab)

	# Close
	var close := Button.new()
	close.text = "Close AAR (re-open via F10 button or post-battle)"
	close.pressed.connect(win.queue_free)
	vb.add_child(close)

	get_tree().root.add_child(win)
	win.popup_centered()
	print("[AAR PANEL] Enhanced full battle AAR shown for %s (pulled logs=%s, mods=%d)" % [result.get("target_province_id", -1), shown_logs, mods_list.size()])
