# scripts/ui/TopInfoBar.gd
class_name TopInfoBar
extends Control

const _HudIcons = preload("res://scripts/ui/HudIconLibrary.gd")

@export var player_country_tag: String = "USA"

@onready var date_time_label: Label = $ContentRow/LeftContainer/DateTimeLabel


@onready var pause_button: Button = $ContentRow/LeftContainer/TimeSpeedContainer/PauseButton
@onready var speed1_button: Button = $ContentRow/LeftContainer/TimeSpeedContainer/Speed1Button
@onready var speed2_button: Button = $ContentRow/LeftContainer/TimeSpeedContainer/Speed2Button
@onready var speed3_button: Button = $ContentRow/LeftContainer/TimeSpeedContainer/Speed3Button
@onready var speed4_button: Button = $ContentRow/LeftContainer/TimeSpeedContainer/Speed4Button

@onready var production_button: Button = $ContentRow/CenterContainer/ProductionButton
@onready var leaders_button: Button = $ContentRow/CenterContainer/LeadersButton
@onready var technology_button: Button = $ContentRow/CenterContainer/TechnologyButton
@onready var diplomacy_button: Button = $ContentRow/CenterContainer/DiplomacyButton
@onready var agents_button: Button = $ContentRow/CenterContainer/AgentsButton
@onready var map_button: Button = $ContentRow/CenterContainer/MapButton
var trade_button: Button   # Added dynamically for quick Trade access
var space_button: Button   # Space layer board (orbital compact ledger)
var matchmaking_button: Button  # Thin multiplayer queue lobby

@onready var steel_label: Label = $ContentRow/RightContainer/ResourcesContainer/SteelLabel
@onready var aluminum_label: Label = $ContentRow/RightContainer/ResourcesContainer/AluminumLabel
@onready var oil_label: Label = $ContentRow/RightContainer/ResourcesContainer/OilLabel
@onready var rubber_label: Label = $ContentRow/RightContainer/ResourcesContainer/RubberLabel

# High-value visibility polish: Compact "Direction" label for Trust Erosion / Demographic trajectory (from Policy/Law + erosion systems).
# Player always sees at a glance which way the nation is heading (immigration strain, printing, native growth, foreign military loyalty) and can act via Policy screen or agents.
var direction_label: Button   # Added dynamically for Policy/Demographic direction (Trust Erosion, non-citizen pressure, loyalty). Clickable to policy.

var menu_button: MenuButton  # created dynamically in _setup_compact_menu to save top bar space
# Legacy flat buttons may exist in scene; we consolidate into menu for space (hide them)
@onready var save_button: Button = $ContentRow/RightContainer/MenuContainer/SaveButton
@onready var load_button: Button = $ContentRow/RightContainer/MenuContainer/LoadButton
@onready var settings_button: Button = $ContentRow/RightContainer/MenuContainer/SettingsButton
@onready var help_button: Button = $ContentRow/RightContainer/MenuContainer/HelpButton

var debug_button: Button   # Only created in debug builds, added to menu

var current_speed: int = 1
var is_paused: bool = false
## Wall-clock last sim tick (msec). Avoids Timer + Engine.time_scale freeze/double-scale.
var _last_sim_tick_msec: int = 0
## True while a day advance is on the main thread (prevents tick-storm: day work >1s → immediate next day).
var _sim_tick_busy: bool = false
## When busy was set (watchdog clears stuck busy so clock cannot freeze at Feb 28 forever).
var _sim_tick_busy_since_msec: int = 0
const SIM_TICK_INTERVAL_MS := 1000
const SIM_TICK_BUSY_WATCHDOG_MS := 8000

## Layout breakpoints (viewport width). Secondary screens always live in More ▾ for usability.
const WIDTH_COMPACT := 1400
const WIDTH_NARROW := 1100
const WIDTH_SHOW_RESOURCES := 1500
const WIDTH_SHOW_ALL_SPEEDS := 900

@onready var _content_row: HBoxContainer = $ContentRow
@onready var _resources_container: HBoxContainer = $ContentRow/RightContainer/ResourcesContainer
@onready var _center_container: HBoxContainer = $ContentRow/CenterContainer
@onready var _left_container: HBoxContainer = $ContentRow/LeftContainer
@onready var _right_container: HBoxContainer = $ContentRow/RightContainer
@onready var _menu_container: HBoxContainer = $ContentRow/RightContainer/MenuContainer
@onready var _time_speed_container: HBoxContainer = $ContentRow/LeftContainer/TimeSpeedContainer

var _nav_overflow: MenuButton = null  # "More ▾" — secondary screens
var _speed_overflow: MenuButton = null  # collapses 2x/3x/4x on narrow widths


func _ready() -> void:
	add_to_group("top_info_bar")
	# PASS on root so empty bar chrome does not steal map pan; buttons still STOP.
	# ALWAYS so clicks work even if SceneTree is briefly paused during load.
	mouse_filter = Control.MOUSE_FILTER_PASS
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = false
	z_index = 20
	_apply_theme()
	_connect_buttons()
	_sync_pause_from_time_manager()
	_update_speed_buttons()
	_update_date_time()
	_update_resources()
	_update_direction()
	if date_time_label:
		date_time_label.clip_text = true
		date_time_label.visible = true
		date_time_label.custom_minimum_size = Vector2(148, 28)
		date_time_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		date_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		date_time_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
		date_time_label.add_theme_font_size_override("font_size", 13)
		_update_date_time()
	# Taller bar + safe top margin so Pause/Menu are not cut by window chrome / Godot game tab.
	custom_minimum_size.y = 52.0
	offset_bottom = 52.0
	offset_top = 0.0
	var cr := get_node_or_null("ContentRow") as Control
	if cr:
		cr.offset_left = 8.0
		cr.offset_right = -8.0
		cr.offset_top = 6.0
		cr.offset_bottom = -6.0
		cr.clip_contents = false
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(_on_game_year_advanced):
			TimeManager.game_year_advanced.connect(_on_game_year_advanced)
		if not TimeManager.game_month_advanced.is_connected(_on_game_month_advanced):
			TimeManager.game_month_advanced.connect(_on_game_month_advanced)
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)

	# Update direction on month for erosion/policy visibility.
	if typeof(TimeManager) != TYPE_NIL and not TimeManager.game_month_advanced.is_connected(_update_direction):
		TimeManager.game_month_advanced.connect(func(_y, _m): _update_direction())

	# Wall-clock tick (not Timer + Engine.time_scale). Engine.time_scale=0 freezes Timers and
	# double-scales day advance when both Engine and TimeManager scale are applied.
	_last_sim_tick_msec = Time.get_ticks_msec()
	set_process(true)
	process_mode = Node.PROCESS_MODE_ALWAYS

	if get_viewport():
		get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	# Start paused for F5 testing — unresponsive UI is usually sim/map load thrashing.
	call_deferred("_ensure_start_paused_for_playtest")


func get_bar_height() -> float:
	if size.y > 4.0:
		return size.y
	return custom_minimum_size.y


func _ensure_start_paused_for_playtest() -> void:
	## Graphical F5: start paused so map/UI stay responsive while player looks around.
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return
	if OS.get_environment("EOA_RUN_SIM_CYCLES").strip_edges() == "1":
		return
	# Don't re-pause if the player already hit 1x/▶ (deferred interactive can race this).
	if has_meta("player_owns_clock") and bool(get_meta("player_owns_clock")):
		return
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)
		is_paused = true
		# Keep Engine.time_scale at 1 so UI/input stay live; sim pause is TimeManager-only.
		Engine.time_scale = 1.0
		_last_sim_tick_msec = Time.get_ticks_msec()
		_update_speed_buttons()
		print("TopInfoBar: start PAUSED (press 1x / Space / keys 1-4 to advance time).")


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var vp_w := get_viewport().get_visible_rect().size.x
	var compact := vp_w < WIDTH_COMPACT
	var narrow := vp_w < WIDTH_NARROW
	var show_resources := vp_w >= WIDTH_SHOW_RESOURCES
	var show_all_speeds := vp_w >= WIDTH_SHOW_ALL_SPEEDS

	if _content_row:
		_content_row.offset_left = 8.0
		_content_row.offset_right = -8.0
		_content_row.offset_top = 6.0
		_content_row.offset_bottom = -6.0
		_content_row.add_theme_constant_override("separation", 4 if narrow else 6)
		_content_row.clip_contents = false

	if _left_container:
		_left_container.add_theme_constant_override("separation", 4)
		_left_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if date_time_label and date_time_label.get_parent() != _left_container:
			date_time_label.reparent(_left_container)
			_left_container.move_child(date_time_label, mini(1, _left_container.get_child_count() - 1))

	if _right_container:
		_right_container.add_theme_constant_override("separation", 6)
		_right_container.size_flags_horizontal = Control.SIZE_SHRINK_END
		if _menu_container:
			_right_container.move_child(_menu_container, _right_container.get_child_count() - 1)

	# Time: always keep Pause + 1x visible; fold 2x–4x into Speed ▾ when narrow.
	_ensure_speed_overflow_menu()
	_apply_speed_layout(show_all_speeds, compact)

	# Nav: primary 5 always on bar; everything else always in More ▾ (testing + player UX).
	_ensure_nav_overflow_menu()
	_apply_primary_nav_layout(compact, narrow)

	if _resources_container:
		_resources_container.visible = show_resources
		_resources_container.add_theme_constant_override("separation", 8)

	if steel_label:
		steel_label.visible = show_resources and vp_w >= WIDTH_SHOW_RESOURCES + 40
	if aluminum_label:
		aluminum_label.visible = show_resources and vp_w >= WIDTH_SHOW_RESOURCES + 160
	if oil_label:
		oil_label.visible = show_resources
	if rubber_label:
		rubber_label.visible = show_resources and vp_w >= WIDTH_SHOW_RESOURCES + 100

	if date_time_label:
		date_time_label.visible = true
		date_time_label.custom_minimum_size = Vector2(120 if narrow else (136 if compact else 148), 26)
		date_time_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		date_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		date_time_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		date_time_label.add_theme_font_size_override("font_size", 12 if compact else 13)
		date_time_label.tooltip_text = GameDateDisplay.format_top_bar_tooltip()

	if menu_button and is_instance_valid(menu_button):
		menu_button.text = "Menu" if not narrow else "M"
		menu_button.custom_minimum_size = Vector2(40 if narrow else 56, 28)
		menu_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		menu_button.tooltip_text = "Save · Load · Settings · Help · Policies · Debug"

	# Slim single-row bar (no second-row hotseat chrome cutting into buttons).
	custom_minimum_size.y = 48.0 if compact else 52.0
	offset_bottom = custom_minimum_size.y
	_refresh_hotseat_visibility()


func _ensure_speed_overflow_menu() -> void:
	if _speed_overflow != null and is_instance_valid(_speed_overflow):
		return
	if _time_speed_container == null:
		return
	_speed_overflow = MenuButton.new()
	_speed_overflow.name = "SpeedOverflowMenu"
	_speed_overflow.text = "Spd"
	_speed_overflow.tooltip_text = "Simulation speed (2x-4x)"
	_speed_overflow.custom_minimum_size = Vector2(40, 28)
	_time_speed_container.add_child(_speed_overflow)
	RetrowaveTheme.style_secondary_button(_speed_overflow)
	var pop: PopupMenu = _speed_overflow.get_popup()
	pop.clear()
	pop.add_item("2x", 2)
	pop.add_item("3x", 3)
	pop.add_item("4x", 4)
	pop.id_pressed.connect(_on_speed_overflow_pressed)


func _on_speed_overflow_pressed(id: int) -> void:
	_set_game_speed(id)


func _apply_speed_layout(show_all: bool, compact: bool) -> void:
	var h := 28 if compact else 30
	if pause_button:
		pause_button.custom_minimum_size = Vector2(36, h)
		pause_button.text = "||" if not is_paused else ">"
		pause_button.tooltip_text = "Pause / Resume (Space)"
		pause_button.visible = true
	if speed1_button:
		speed1_button.custom_minimum_size = Vector2(32, h)
		speed1_button.visible = true
	for sb in [speed2_button, speed3_button, speed4_button]:
		if sb:
			sb.custom_minimum_size = Vector2(32, h)
			sb.visible = show_all
	if _speed_overflow:
		_speed_overflow.visible = not show_all
		_speed_overflow.custom_minimum_size = Vector2(40, h)


func _ensure_nav_overflow_menu() -> void:
	if _nav_overflow != null and is_instance_valid(_nav_overflow):
		return
	if _center_container == null:
		return
	_nav_overflow = MenuButton.new()
	_nav_overflow.name = "NavOverflowMenu"
	_nav_overflow.text = "More ▾"
	_nav_overflow.tooltip_text = "Trade · Space · Match · Orders · HH Agenda · Map"
	_nav_overflow.visible = true
	_nav_overflow.custom_minimum_size = Vector2(64, 28)
	_center_container.add_child(_nav_overflow)
	RetrowaveTheme.style_nav_button(_nav_overflow)
	var pop := _nav_overflow.get_popup()
	pop.clear()
	pop.add_item("Trade", 5)
	pop.add_item("Space", 7)
	pop.add_item("Matchmaking", 8)
	pop.add_item("Orders", 6)
	pop.add_item("HH Agenda", 9)
	pop.add_separator()
	pop.add_item("Map (current)", 10)
	pop.id_pressed.connect(_on_nav_overflow_pressed)


func _on_nav_overflow_pressed(id: int) -> void:
	match id:
		5: _on_trade_pressed()
		6: _on_orders_pressed()
		7: _on_space_pressed()
		8: _on_matchmaking_pressed()
		9: _on_hh_agenda_pressed()
		10: _on_map_pressed()


## Primary strip: Prod / Leaders / Tech / Dipl / Agents always visible (short labels + icons).
## Secondary always in More ▾ so Pause/Menu never get crushed off-screen.
func _apply_primary_nav_layout(compact: bool, narrow: bool) -> void:
	if _nav_overflow:
		_nav_overflow.visible = true
		_nav_overflow.text = "More" if narrow else "More +"
		_nav_overflow.custom_minimum_size = Vector2(52 if narrow else 64, 26 if compact else 28)
	var pairs: Array[Array] = [
		[production_button, "Production", "Prod", "production"],
		[leaders_button, "Leaders", "Lead", "leaders"],
		[technology_button, "Technology", "Tech", "technology"],
		[diplomacy_button, "Diplomacy", "Dipl", "diplomacy"],
		[agents_button, "Agents", "Agnt", "agents"],
	]
	var h := 26 if compact else 28
	var w := 52 if narrow else (60 if compact else 72)
	for row in pairs:
		var btn: Button = row[0] as Button
		if btn == null:
			continue
		btn.visible = true
		btn.text = str(row[2])  # always short — frees left/right for Pause + Menu
		btn.custom_minimum_size = Vector2(w, h)
		btn.tooltip_text = str(row[1])
		var tex: Texture2D = _HudIcons.hud_icon(str(row[3]), 32)
		if tex != null:
			_HudIcons.apply_button_icon(btn, tex, true)
	# Hide secondary flat buttons — reachable via More ▾
	if map_button:
		map_button.visible = false
	if trade_button:
		trade_button.visible = false
	if space_button:
		space_button.visible = false
	if matchmaking_button:
		matchmaking_button.visible = false
	var orders_btn := get_node_or_null("ContentRow/CenterContainer/OrdersButton") as Button
	if orders_btn:
		orders_btn.visible = false
	var hh_btn := get_node_or_null("ContentRow/CenterContainer/HHAgendaButton") as Button
	if hh_btn:
		hh_btn.visible = false


func _apply_hud_icons() -> void:
	## Attach retrowave HUD + resource icons (safe if assets missing).
	var nav: Array[Array] = [
		[production_button, "production"],
		[leaders_button, "leaders"],
		[technology_button, "technology"],
		[diplomacy_button, "diplomacy"],
		[agents_button, "agents"],
		[map_button, "map"],
		[trade_button, "trade"],
		[space_button, "space"],
	]
	for row in nav:
		var btn: Button = row[0] as Button
		if btn == null:
			continue
		_HudIcons.wire_icon_hover_states(btn, str(row[1]), 32)
	# Speed + pause icons
	if pause_button:
		_refresh_pause_icon()
	var speed_btns: Array[Array] = [
		[speed1_button, "speed1"],
		[speed2_button, "speed2"],
		[speed3_button, "speed3"],
		[speed4_button, "speed4"],
	]
	for row in speed_btns:
		var sbtn: Button = row[0] as Button
		if sbtn == null:
			continue
		var skey := str(row[1])
		var stex: Texture2D = _HudIcons.hud_icon(skey, 32)
		if stex != null:
			_HudIcons.apply_button_icon(sbtn, stex, true)
	# Resource chips
	var res_pairs: Array[Array] = [
		[steel_label, "steel"],
		[aluminum_label, "aluminum"],
		[oil_label, "fuel"],
		[rubber_label, "rubber"],
	]
	for row in res_pairs:
		var lab: Label = row[0] as Label
		if lab == null:
			continue
		var rtex: Texture2D = _HudIcons.resource_icon(str(row[1]), 24)
		if rtex != null:
			_HudIcons.decorate_label_with_icon(lab, rtex, 18)


func _refresh_pause_icon() -> void:
	if pause_button == null:
		return
	var key := "play" if is_paused else "pause"
	_HudIcons.wire_icon_hover_states(pause_button, key, 32)
	# Keep a short glyph as fallback text when textures missing.
	if pause_button.icon == null:
		pause_button.text = ">" if is_paused else "||"
	else:
		pause_button.text = ""


func _refresh_hotseat_visibility() -> void:
	## Only show End Turn / banner when multi-slot hotseat is actually active.
	var multi := false
	if typeof(SessionPlayers) != TYPE_NIL:
		if SessionPlayers.has_method("get_player_count"):
			multi = int(SessionPlayers.get_player_count()) > 1
		elif "slots" in SessionPlayers and SessionPlayers.slots is Array:
			multi = (SessionPlayers.slots as Array).size() > 1
	var banner := get_node_or_null("HotseatTurnBanner") as Control
	if banner:
		banner.visible = multi
	var end_row := get_node_or_null("HotseatEndTurnRow") as Control
	if end_row:
		end_row.visible = multi


func _apply_theme() -> void:
	RetrowaveTheme.style_top_info_bar(self)
	RetrowaveTheme.style_info_bar_label(date_time_label, RetrowaveTheme.CYAN)
	for label in [steel_label, aluminum_label, oil_label, rubber_label]:
		RetrowaveTheme.style_info_bar_label(label, RetrowaveTheme.TEXT_DIM)
	for btn in [
		production_button,
		leaders_button,
		technology_button,
		diplomacy_button,
		agents_button,
		map_button,
	]:
		RetrowaveTheme.style_nav_button(btn)

	# Quick Trade access button (lightweight addition)
	if trade_button == null:
		trade_button = Button.new()
		trade_button.text = "Trade"
		trade_button.custom_minimum_size = Vector2(70, 28)
		$ContentRow/CenterContainer.add_child(trade_button)
		RetrowaveTheme.style_nav_button(trade_button)
		# Place it after Diplomacy for logical grouping
		$ContentRow/CenterContainer.move_child(trade_button, diplomacy_button.get_index() + 1)
	# Space layer board (orbital compact ledger)
	if space_button == null:
		space_button = Button.new()
		space_button.text = "Space"
		space_button.custom_minimum_size = Vector2(70, 28)
		$ContentRow/CenterContainer.add_child(space_button)
		RetrowaveTheme.style_nav_button(space_button)
		$ContentRow/CenterContainer.move_child(space_button, trade_button.get_index() + 1)
	_apply_hud_icons()
	if matchmaking_button == null:
		matchmaking_button = Button.new()
		matchmaking_button.text = "Match"
		matchmaking_button.custom_minimum_size = Vector2(70, 28)
		$ContentRow/CenterContainer.add_child(matchmaking_button)
		RetrowaveTheme.style_nav_button(matchmaking_button)
		$ContentRow/CenterContainer.move_child(matchmaking_button, space_button.get_index() + 1)

	# Orders / HH Agenda exist as nodes for API/tests but stay hidden — open via More ▾.
	if get_node_or_null("ContentRow/CenterContainer/OrdersButton") == null:
		var orders_btn := Button.new()
		orders_btn.name = "OrdersButton"
		orders_btn.text = "Orders"
		orders_btn.visible = false
		orders_btn.tooltip_text = "Theater orders (also in More ▾)"
		$ContentRow/CenterContainer.add_child(orders_btn)
		orders_btn.pressed.connect(_on_orders_pressed)
	if get_node_or_null("ContentRow/CenterContainer/HHAgendaButton") == null:
		var hh_btn := Button.new()
		hh_btn.name = "HHAgendaButton"
		hh_btn.text = "HH Agenda"
		hh_btn.visible = false
		hh_btn.tooltip_text = "Hidden Hand agenda (also in More ▾)"
		$ContentRow/CenterContainer.add_child(hh_btn)
		hh_btn.pressed.connect(_on_hh_agenda_pressed)
	# Hotseat chrome only when multi-player session (not always-on second row).
	_ensure_hotseat_turn_banner()

	# Primary strip: Production / Leaders / Tech / Dipl / Agents.
	# More ▾: Trade, Space, Match, Orders, HH, Map.
	# Menu ☰: Save, Load, Settings, Help, Policies, Debug.
	direction_label = null

	if map_button:
		map_button.visible = false
		map_button.tooltip_text = "Map view (current). Also in More ▾"

	RetrowaveTheme.style_primary_button(production_button)
	RetrowaveTheme.style_primary_button(leaders_button)
	for btn in [save_button, load_button, settings_button, help_button, pause_button]:
		if btn:
			RetrowaveTheme.style_secondary_button(btn)

	_setup_compact_menu()
	# Hide secondary flat buttons immediately (layout re-applied deferred).
	if trade_button:
		trade_button.visible = false
	if space_button:
		space_button.visible = false
	if matchmaking_button:
		matchmaking_button.visible = false

	# Debug overlay quick toggle (only in debug builds) -- we put "Debug (F10)" inside the compact MenuButton
	# to save top bar space. F10 / Ctrl+Shift+R still work globally.
	var is_headless_ev := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
	if OS.is_debug_build() and debug_button == null and not is_headless_ev:
		# Pre-create the overlay (hidden) so hotkeys and other systems can find it immediately.
		# Use the static toggle/hide which now prefers adding under UILayer for proper screen-space behavior.
		# Deferred to avoid any early tree/window issues on Linux/X11.
		# Guard for headless 50T evidence runs (pre-existing "toggle" on GDScript error); skip precreate entirely under EOA_HEADLESS_EVIDENCE.
		call_deferred("_deferred_precreate_debug")


func _setup_compact_menu() -> void:
	# Replace flat menu buttons with a single MenuButton + PopupMenu to save horizontal space on the top bar.
	# This prevents left/right cutoff when the bar has many nav + resource buttons.
	# Actions are moved into the popup (like previous design).
	var menu_container := $ContentRow/RightContainer/MenuContainer
	if menu_container == null:
		return

	# Create or reuse MenuButton
	var mb: MenuButton = null
	if menu_button == null or not is_instance_valid(menu_button):
		mb = MenuButton.new()
		mb.text = "Menu"
		mb.custom_minimum_size = Vector2(70, 28)
		menu_container.add_child(mb)
		menu_button = mb
	else:
		mb = menu_button

	var popup := mb.get_popup()
	popup.clear()

	# Add items for the actions. We connect via id_pressed for simplicity.
	popup.add_item("Save", 0)
	popup.add_item("Load", 1)
	popup.add_separator()
	popup.add_item("Settings", 2)
	popup.add_item("Help", 3)
	popup.add_separator()
	popup.add_item("Policies / Direction (Dir)", 6)  # consolidated per spec to keep core 6 overhead clean
	popup.add_item("Map (current view)", 7)
	popup.add_separator()
	popup.add_item("Exit to Desktop", 5)
	var is_headless_ev := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
	if OS.is_debug_build() and not is_headless_ev:
		popup.add_separator()
		popup.add_item("Debug (F10)", 4)

	popup.id_pressed.connect(_on_menu_item_pressed)

	# Hide the old flat buttons to free space (they are still there in scene for now)
	for btn in [save_button, load_button, settings_button, help_button]:
		if btn and is_instance_valid(btn):
			btn.visible = false

	# If debug button was added flat, hide it too (DBG action is in menu)
	if debug_button and is_instance_valid(debug_button):
		debug_button.visible = false

	RetrowaveTheme.style_secondary_button(mb)


func _on_menu_item_pressed(id: int) -> void:
	match id:
		0: _on_save_pressed()
		1: _on_load_pressed()
		2: _on_settings_pressed()
		3: _on_help_pressed()
		5:
			get_tree().quit()
		4:
			var is_headless_ev2 := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
			if OS.is_debug_build() and not is_headless_ev2:
				call_deferred("_deferred_debug_toggle")
		6:
			# Consolidated Policies/Dir access (keeps primary overhead to exact 6: Prod/Leaders/Tech/Dip/Agents/Map)
			_toggle_root_popup(
				"PolicyLawScreen",
				"res://scenes/ui/PolicyLawScreen.tscn",
				func(view: Node) -> void:
					if view.has_method("set_player_tag"):
						view.call_deferred("set_player_tag", player_country_tag)
			)
			print("TopInfoBar: Policies/Dir via Menu (core overhead clean).")
		7:
			_on_map_pressed()

func _toggle_signal_graph_safe() -> void:
	var script = load("res://scripts/debug/SignalGraphHarness.gd")
	if script == null:
		return
	if script.has_method("toggle"):
		script.toggle()
		return
	var tree := get_tree()
	if tree == null:
		return
	var existing = tree.root.get_node_or_null("SignalGraphHarness")
	if existing != null and existing.has_method("toggle_window"):
		existing.toggle_window()
		return
	var inst = script.new()
	inst.name = "SignalGraphHarness"
	tree.root.add_child(inst)
	if inst.has_method("toggle_window"):
		inst.toggle_window()


func _deferred_signal_graph_toggle() -> void:
	var is_headless_ev := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
	if is_headless_ev:
		return
	_toggle_signal_graph_safe()


func _deferred_debug_toggle() -> void:
	var is_headless_ev := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
	if is_headless_ev:
		return  # skip entirely for headless evidence runs to avoid GDScript 'toggle' errors on base script
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toggle()
	else:
		var root := get_tree().root if get_tree() else null
		var dbg := root.get_node_or_null("DebugOverlay") if root else null
		if dbg and dbg.has_method("toggle"):
			dbg.toggle()

func _deferred_precreate_debug() -> void:
	## NEVER call DebugOverlay.toggle() here — that opens a 520x680 STOP panel and
	## steals top-bar / map clicks until hide races complete (F5 "buttons dead").
	var is_headless_ev := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
	if is_headless_ev:
		return
	# Static precreate (never toggle/show — that steals map/UI input).
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.precreate_hidden()


func _connect_buttons() -> void:
	_wire_speed_button(pause_button, -1)
	_wire_speed_button(speed1_button, 1)
	_wire_speed_button(speed2_button, 2)
	_wire_speed_button(speed3_button, 3)
	_wire_speed_button(speed4_button, 4)
	# Nav / menu — connect once only (was wrongly re-connected on every speed press → stacked Tech opens → stack overflow).
	_connect_once(production_button, _on_production_pressed)
	_connect_once(leaders_button, _on_leaders_pressed)
	_connect_once(technology_button, _on_technology_pressed)
	_connect_once(diplomacy_button, _on_diplomacy_pressed)
	_connect_once(agents_button, _on_agents_pressed)
	_connect_once(map_button, _on_map_pressed)
	_connect_once(trade_button, _on_trade_pressed)
	_connect_once(space_button, _on_space_pressed)
	_connect_once(matchmaking_button, _on_matchmaking_pressed)
	_connect_once(save_button, _on_menu_pressed)
	_connect_once(load_button, _on_menu_pressed)
	_connect_once(settings_button, _on_settings_pressed)
	_connect_once(help_button, _on_help_pressed)


func _connect_once(btn: Button, handler: Callable) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.disabled = false
	if not btn.pressed.is_connected(handler):
		btn.pressed.connect(handler)


## Ensure speed/pause buttons always receive clicks (process always + stop filter + named handler).
func _wire_speed_button(btn: Button, speed_or_pause: int) -> void:
	if btn == null or not is_instance_valid(btn):
		push_warning("TopInfoBar: missing speed/pause button (speed_or_pause=%d)" % speed_or_pause)
		return
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.disabled = false
	btn.focus_mode = Control.FOCUS_ALL
	btn.set_meta("eoa_speed", speed_or_pause)
	# Disconnect stale connections then attach one clean handler.
	for c in btn.pressed.get_connections():
		var callable: Callable = c.get("callable", Callable())
		if callable.is_valid():
			btn.pressed.disconnect(callable)
	if speed_or_pause < 0:
		btn.pressed.connect(_on_pause_pressed)
	else:
		btn.pressed.connect(_on_speed_button_pressed.bind(btn))


func _on_speed_button_pressed(btn: Button) -> void:
	var sp := 1
	if btn != null and btn.has_meta("eoa_speed"):
		sp = int(btn.get_meta("eoa_speed"))
	_set_game_speed(sp)


func _process(_delta: float) -> void:
	# Wall-clock 1 Hz tick — independent of Engine.time_scale so pause/unpause never freezes the bar.
	var now := Time.get_ticks_msec()
	# Busy watchdog: if a day handler hung or never cleared, free the clock (was stuck at Feb 28).
	if _sim_tick_busy and _sim_tick_busy_since_msec > 0 and now - _sim_tick_busy_since_msec > SIM_TICK_BUSY_WATCHDOG_MS:
		push_warning(
			"TopInfoBar: sim tick busy >%dms — clearing so calendar can advance (was freezing around month ends)."
			% SIM_TICK_BUSY_WATCHDOG_MS
		)
		_sim_tick_busy = false
		_sim_tick_busy_since_msec = 0
	# Player owns clock: never let TimeManager stay paused while UI shows running (re-pause race).
	if (
		not is_paused
		and has_meta("player_owns_clock")
		and bool(get_meta("player_owns_clock"))
		and typeof(TimeManager) != TYPE_NIL
		and TimeManager.is_paused()
	):
		TimeManager.set_paused(false)
		TimeManager.set_time_scale(float(current_speed))
	if is_paused or _sim_tick_busy:
		return
	if _last_sim_tick_msec <= 0:
		_last_sim_tick_msec = now
		return
	if now - _last_sim_tick_msec < SIM_TICK_INTERVAL_MS:
		return
	_on_tick()
	# Stamp AFTER work so a multi-second day advance cannot chain into a storm (UI stays dead).
	_last_sim_tick_msec = Time.get_ticks_msec()


func _on_tick() -> void:
	if is_paused or _sim_tick_busy:
		return
	_sim_tick_busy = true
	_sim_tick_busy_since_msec = Time.get_ticks_msec()
	var date_before := ""
	if typeof(TimeManager) != TYPE_NIL:
		# Ensure TM is running before we try to step (re-pause races used to freeze at Feb 28).
		if TimeManager.is_paused() and has_meta("player_owns_clock") and bool(get_meta("player_owns_clock")):
			TimeManager.set_paused(false)
			TimeManager.set_time_scale(float(current_speed))
		var d0: Dictionary = TimeManager.get_current_date()
		date_before = str(d0.get("date_string", ""))
		# 1 wall-sec → time_scale game hours (1× = hour-by-hour, not day-by-day).
		# current_speed already mirrored into TimeManager.time_scale via _set_game_speed.
		TimeManager.advance_real_time(1.0)
		var d1: Dictionary = TimeManager.get_current_date()
		var date_after := str(d1.get("date_string", ""))
		# Do NOT force a full day when only the hour changed — that was making 1× jump day-by-day.
		_update_date_time()
		if date_after != date_before and int(d1.get("day", 0)) == 1 and int(d1.get("hour", 0)) == 0:
			print("TopInfoBar: calendar month rolled → %s" % date_after)
	else:
		_update_date_time()

	_update_resources()
	_update_direction()
	_sim_tick_busy = false
	_sim_tick_busy_since_msec = 0

func _update_direction() -> void:
	# Trajectory chip removed from top bar (Menu → Policies) to prevent right-edge clipping.
	pass


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# Space / > : toggle pause (fallback if 1x click is blocked by an overlay)
	if event.keycode == KEY_SPACE or event.keycode == KEY_PERIOD:
		_on_pause_pressed()
		get_viewport().set_input_as_handled()
		return
	# 1–4 number keys set speed and unpause
	if event.keycode == KEY_1 or event.keycode == KEY_KP_1:
		_set_game_speed(1)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_2 or event.keycode == KEY_KP_2:
		_set_game_speed(2)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_3 or event.keycode == KEY_KP_3:
		_set_game_speed(3)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_4 or event.keycode == KEY_KP_4:
		_set_game_speed(4)
		get_viewport().set_input_as_handled()
		return
	# Global debug hotkey — opens the dedicated Debug Overlay
	if event.keycode == KEY_F10 or (event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_R):
		var is_headless_ev3 := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
		if not is_headless_ev3:
			call_deferred("_deferred_debug_toggle")
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F11:
		var is_headless_ev4 := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
		if not is_headless_ev4:
			call_deferred("_deferred_signal_graph_toggle")
		else:
			_toggle_signal_graph_safe()
		get_viewport().set_input_as_handled()
		return
	# EOA_HOTKEY_CTRL_S — save/load no longer collide with F5/F9 mapmodes
	if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_S:
		_show_save_manager_popup()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and not event.shift_pressed and event.keycode == KEY_S:
		if typeof(SaveLoadManager) != TYPE_NIL:
			var ok := false
			var abs_p := ""
			var kb := 0
			if SaveLoadManager.has_method("save_game_detailed"):
				var res: Dictionary = SaveLoadManager.save_game_detailed("quicksave")
				ok = bool(res.get("ok", false))
				abs_p = str(res.get("absolute_path", res.get("path", "")))
				kb = int(int(res.get("bytes", 0)) / 1024)
			elif SaveLoadManager.has_method("quicksave"):
				ok = bool(SaveLoadManager.quicksave())
			print("Ctrl+S QuickSave triggered ok=%s path=%s" % [str(ok), abs_p])
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				if ok:
					LeaderEventUI.show_toast("Quicksave OK · %d KB (slot: quicksave)" % kb, 2.8)
				else:
					LeaderEventUI.show_toast("Quicksave FAILED — see console", 3.5)
			# Refresh Command Center list if open.
			var mm: Node = get_tree().root.find_child("MainMenu", true, false) if get_tree() else null
			if mm != null and mm.has_method("_refresh_save_list"):
				mm.call_deferred("_refresh_save_list")
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and not event.shift_pressed and event.keycode == KEY_L:
		if typeof(SaveLoadManager) != TYPE_NIL:
			SaveLoadManager.quickload()
			_update_date_time()
			_update_resources()
			print("Ctrl+L QuickLoad triggered")
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		# Prefer closing map overlays (supply legend / tech) over opening Main Menu.
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr == null and get_tree() and get_tree().current_scene:
			mr = get_tree().current_scene.find_child("MapRenderer", true, false)
		if mr != null and mr.has_method("_dismiss_map_overlays_esc") and bool(mr.call("_dismiss_map_overlays_esc")):
			get_viewport().set_input_as_handled()
			return
		_on_menu_pressed()
		get_viewport().set_input_as_handled()


func _set_game_speed(speed: int) -> void:
	current_speed = clampi(speed, 1, 4)
	is_paused = false
	# Player took clock control — TestRunner must not re-pause on deferred interactive passes.
	set_meta("player_owns_clock", true)
	# Clear any stuck busy from a prior hung day so 1x always restarts the clock.
	_sim_tick_busy = false
	_sim_tick_busy_since_msec = 0
	# Speed is TimeManager.time_scale only — never Engine.time_scale (freezes Timers/UI at 0; double-scales days).
	Engine.time_scale = 1.0
	_sync_time_manager_controls()
	_update_speed_buttons()
	_update_date_time()
	# Defer first day so this click returns immediately (hover/scroll stay live).
	# Immediate advance_days() was freezing the main thread for multiple seconds.
	_last_sim_tick_msec = 0  # force next _process to fire soon
	call_deferred("_deferred_first_day_step")
	print("TopInfoBar: SPEED %dx (unpaused) — clock running" % current_speed)


func _deferred_first_day_step() -> void:
	if is_paused or _sim_tick_busy:
		return
	_on_tick()
	_last_sim_tick_msec = Time.get_ticks_msec()


func _update_speed_buttons() -> void:
	var buttons := [speed1_button, speed2_button, speed3_button, speed4_button]
	for i in buttons.size():
		if buttons[i]:
			RetrowaveTheme.style_speed_button(buttons[i], not is_paused and (i + 1) == current_speed)
			# Dim inactive speeds; keep icon visibility high on active.
			buttons[i].modulate = Color.WHITE if (not is_paused and (i + 1) == current_speed) else Color(0.75, 0.8, 0.9, 0.9)
	if pause_button:
		_refresh_pause_icon()
		if is_paused:
			pause_button.modulate = RetrowaveTheme.MAGENTA
			pause_button.tooltip_text = "Resume simulation"
		else:
			pause_button.modulate = Color.WHITE
			pause_button.tooltip_text = "Pause simulation (keeps UI responsive)"
	if _speed_overflow and is_instance_valid(_speed_overflow):
		_speed_overflow.text = "%dx" % current_speed if not is_paused else "Spd"


func _on_pause_pressed() -> void:
	is_paused = not is_paused
	set_meta("player_owns_clock", true)
	Engine.time_scale = 1.0
	_sync_time_manager_controls()
	_update_speed_buttons()
	_update_date_time()
	if not is_paused:
		_last_sim_tick_msec = 0
		call_deferred("_deferred_first_day_step")
	print("TopInfoBar: %s (speed %dx)" % ["PAUSED" if is_paused else "RESUMED", current_speed])


func _on_game_year_advanced(_year: int) -> void:
	_update_date_time()


func _on_game_month_advanced(_year: int, _month: int) -> void:
	_update_date_time()
	_update_resources()


func _on_game_day_advanced(_year: int, _month: int, _day: int) -> void:
	_update_date_time()


func _sync_pause_from_time_manager() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	is_paused = TimeManager.is_paused()


func _sync_time_manager_controls() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	TimeManager.set_paused(is_paused)
	# time_scale is game-days-per-real-second; pause is a separate flag (do not pass 0 — TM clamps to 0.1).
	TimeManager.set_time_scale(float(current_speed))

## Auto-pause/resume helper for main menu (priority 1).
## Pauses the game (and TimeManager) when menu opens, resumes on close.
## Non-intrusive: preserves previous speed/pause state where possible.
func _pause_for_menu(pause: bool) -> void:
	if typeof(TimeManager) == TYPE_NIL:
		Engine.time_scale = 1.0
		return

	if pause:
		# Store previous state if not already paused by menu
		if not has_meta("was_paused_before_menu"):
			set_meta("was_paused_before_menu", is_paused)
			set_meta("speed_before_menu", current_speed)
		is_paused = true
		Engine.time_scale = 1.0
		TimeManager.set_paused(true)
		TimeManager.set_time_scale(float(current_speed))
	else:
		# Restore previous state
		var was_paused = get_meta("was_paused_before_menu", false)
		var prev_speed = get_meta("speed_before_menu", 1)
		is_paused = was_paused
		current_speed = prev_speed
		Engine.time_scale = 1.0
		TimeManager.set_paused(is_paused)
		TimeManager.set_time_scale(float(current_speed))
		if not is_paused:
			_last_sim_tick_msec = Time.get_ticks_msec()
		# Clean meta
		remove_meta("was_paused_before_menu")
		remove_meta("speed_before_menu")

	_update_speed_buttons()
	_update_date_time()


func _update_date_time() -> void:
	date_time_label.text = GameDateDisplay.format_top_bar_line(true)
	var tip := GameDateDisplay.format_top_bar_tooltip()
	date_time_label.tooltip_text = tip
	pause_button.tooltip_text = "Pause / resume simulation\n\n" + tip if not tip.is_empty() else "Pause / resume simulation"
	if is_paused:
		date_time_label.modulate = RetrowaveTheme.MAGENTA
		pause_button.tooltip_text = "Resume simulation\n\n" + tip if not tip.is_empty() else "Resume simulation"
	else:
		date_time_label.modulate = Color.WHITE


func _update_resources() -> void:
	var stockpile: Dictionary = ProductionManager.national_stockpile
	steel_label.text = "Steel: %.0f" % float(stockpile.get("steel", 0.0))
	aluminum_label.text = "Aluminum: %.0f" % float(stockpile.get("aluminum", 0.0))
	# Fuel major absorbs oil feedstock; show Fuel (Energy when present for industry meter).
	var fuel_amt := float(stockpile.get("fuel", stockpile.get("oil", 0.0)))
	var energy_amt := float(stockpile.get("energy", 0.0))
	if energy_amt > 0.0:
		oil_label.text = "Energy: %.0f  Fuel: %.0f" % [energy_amt, fuel_amt]
	else:
		oil_label.text = "Fuel: %.0f" % fuel_amt
	rubber_label.text = "Rubber: %.0f" % float(stockpile.get("rubber", 0.0))


func _close_overlay_screens() -> void:
	_close_screen("ProductionAssignmentScreen")
	_close_screen("LeaderAssignmentScreen")
	_close_screen("AgentAssignmentScreen")
	_close_screen("NationalSpiritsScreen")
	_close_screen("TechnologyScreen")
	_close_screen("OrderCommandPanel")


func _on_orders_pressed() -> void:
	# Do not mass-close other windows; do not call refresh before enter_tree (was freeze + double rebuild).
	_toggle_screen(
		"OrderCommandPanel",
		"res://scenes/ui/OrderCommandPanel.tscn",
		func(scene: Node) -> void:
			if scene == null:
				return
			if "country_tag" in scene:
				scene.set("country_tag", player_country_tag)
			# refresh() is deferred from OrderCommandPanel._ready — avoid sync freeze here.
	)


## Pack F — HH multi-month agenda as primary TopInfoBar screen.
func _on_hh_agenda_pressed() -> void:
	var existing := get_tree().root.get_node_or_null("HHAgendaPopup")
	if existing != null:
		existing.queue_free()
		return
	var panel := Panel.new()
	panel.name = "HHAgendaPopup"
	panel.size = Vector2(560, 420)
	panel.position = Vector2(180, 100)
	panel.z_index = 100
	var vbox := VBoxContainer.new()
	vbox.size = panel.size - Vector2(20, 20)
	vbox.position = Vector2(10, 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Hidden Hand — Multi-month agenda"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var filter := OptionButton.new()
	filter.add_item("All factions", 0)
	filter.add_item("Player", 1)
	filter.add_item("Majors", 2)
	vbox.add_child(filter)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = true
	body.custom_minimum_size = Vector2(520, 220)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)
	var refresh_body := func() -> void:
		var lines: PackedStringArray = []
		if typeof(GameData) != TYPE_NIL:
			if GameData.has_method("format_hh_multi_month_agenda_product_plain"):
				lines.append(str(GameData.format_hh_multi_month_agenda_product_plain(1)))
			elif GameData.has_method("get_hh_agenda_trail"):
				var trail: Variant = GameData.get_hh_agenda_trail()
				lines.append("Trail: %s" % str(trail))
			if GameData.has_method("format_hh_player_path_plain"):
				lines.append(str(GameData.format_hh_player_path_plain(1)))
		body.text = "\n".join(lines) if not lines.is_empty() else "[color=#8899aa]HH agenda ready — advance steps below.[/color]"
	refresh_body.call()
	var row := HBoxContainer.new()
	var mk := func(label: String, aid: String) -> void:
		var b := Button.new()
		b.text = label
		b.pressed.connect(func():
			if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_order_panel_action"):
				GameData.apply_order_panel_action(aid, 1)
			elif typeof(GameData) != TYPE_NIL and aid == "hh_agenda_close" and GameData.has_method("apply_hh_agenda_close_live"):
				GameData.apply_hh_agenda_close_live(1)
			refresh_body.call()
		)
		row.add_child(b)
	mk.call("Trail board", "hh_month_trail_board")
	mk.call("Monthly brief", "hh_month_brief")
	mk.call("Quarterly counter", "hh_month_quarterly_counter")
	mk.call("Advance close-live", "hh_agenda_close")
	vbox.add_child(row)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): panel.queue_free())
	vbox.add_child(close_btn)
	get_tree().root.add_child(panel)


## Pack L — N1 hotseat turn lock banner.
func _ensure_hotseat_turn_banner() -> void:
	if get_node_or_null("HotseatTurnBanner") != null:
		return
	var banner := Label.new()
	banner.name = "HotseatTurnBanner"
	banner.text = "Hotseat: —"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	banner.custom_minimum_size = Vector2(0, 16)
	banner.visible = false
	# Overlay at bottom of top bar area — do NOT steal left/right button space.
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 48.0
	banner.offset_bottom = 64.0
	add_child(banner)
	if typeof(SessionPlayers) != TYPE_NIL:
		if SessionPlayers.has_signal("active_player_changed") and not SessionPlayers.active_player_changed.is_connected(_on_hotseat_active_changed):
			SessionPlayers.active_player_changed.connect(_on_hotseat_active_changed)
		_refresh_hotseat_banner()
	var end_row := HBoxContainer.new()
	end_row.name = "HotseatEndTurnRow"
	end_row.visible = false
	end_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	end_row.offset_left = -140.0
	end_row.offset_top = 48.0
	end_row.offset_right = -8.0
	end_row.offset_bottom = 72.0
	var end_btn := Button.new()
	end_btn.text = "End Turn"
	end_btn.tooltip_text = "Hotseat: end turn / rotate active player"
	end_btn.pressed.connect(_on_hotseat_end_turn)
	end_row.add_child(end_btn)
	add_child(end_row)
	_refresh_hotseat_visibility()


func _on_hotseat_active_changed(tag: String, _slot_index: int, turn: int) -> void:
	_refresh_hotseat_banner(tag, turn)


func _refresh_hotseat_banner(tag: String = "", turn: int = -1) -> void:
	var banner := get_node_or_null("HotseatTurnBanner") as Label
	if banner == null or typeof(SessionPlayers) == TYPE_NIL:
		return
	var t := tag if not tag.is_empty() else str(SessionPlayers.get_active_tag())
	var tn := turn if turn >= 0 else int(SessionPlayers.turn)
	var human := true
	if SessionPlayers.has_method("is_active_human"):
		human = bool(SessionPlayers.is_active_human())
	banner.text = "Hotseat · Turn %d · Active %s · %s" % [tn, t, "HUMAN" if human else "AI (input locked)"]


func _on_hotseat_end_turn() -> void:
	if typeof(SessionPlayers) == TYPE_NIL:
		return
	if SessionPlayers.has_method("flush_command_queue"):
		SessionPlayers.flush_command_queue()
	## Pack D/K — AI tags advance fleet / daily packages on rotate
	if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_multi_faction_ai_daily_depth_live"):
		GameData.apply_multi_faction_ai_daily_depth_live(1)
	if SessionPlayers.has_method("rotate_active_player"):
		SessionPlayers.rotate_active_player()
	_refresh_hotseat_banner()


func _on_production_pressed() -> void:
	# Multi-window: do not close other overlays; re-click toggles this screen only.
	_toggle_screen(
		"ProductionAssignmentScreen",
		"res://scenes/ui/ProductionAssignmentScreen.tscn",
		func(scene: Node) -> void:
			var screen := scene as ProductionAssignmentScreen
			if screen != null:
				screen.country_tag = player_country_tag
	)


func _on_leaders_pressed() -> void:
	_toggle_screen(
		"LeaderAssignmentScreen",
		"res://scenes/ui/LeaderAssignmentScreen.tscn",
		func(scene: Node) -> void:
			var screen := scene as LeaderAssignmentScreen
			if screen != null:
				screen.country_tag = player_country_tag
				if typeof(LeaderManager) != TYPE_NIL:
					LeaderManager.set_player_country_tag(player_country_tag)
	)


func _on_technology_pressed() -> void:
	_toggle_screen(
		"TechnologyScreen",
		"res://scenes/ui/TechnologyScreen.tscn",
		func(scene: Node) -> void:
			var screen := scene as TechnologyScreen
			if screen != null:
				screen.country_tag = player_country_tag
	)
	_show_toast("Technology — drag title / Esc closes top window / multi-window OK", 2.5)


func _on_diplomacy_pressed() -> void:
	_close_overlay_screens()
	_toggle_root_popup(
		"DiplomacyView",
		"res://scenes/ui/DiplomacyView.tscn",
		func(view: Node) -> void:
			if view.has_method("popup_centered"):
				view.call_deferred("popup_centered", Vector2i(1100, 700))
	)


func _on_agents_pressed() -> void:
	_toggle_screen(
		"AgentAssignmentScreen",
		"res://scenes/ui/AgentAssignmentScreen.tscn",
		func(scene: Node) -> void:
			var screen := scene as AgentAssignmentScreen
			if screen != null:
				screen.country_tag = player_country_tag
				if typeof(LeaderManager) != TYPE_NIL:
					LeaderManager.set_player_country_tag(player_country_tag)
	)


func _on_map_pressed() -> void:
	_close_overlay_screens()
	_show_toast("Map view — click a province to open the inspector", 2.5)


func _on_trade_pressed() -> void:
	_close_overlay_screens()
	_toggle_root_popup(
		"TradeMarketView",
		"res://scenes/ui/TradeMarketView.tscn",
		func(view: Node) -> void:
			if view.has_method("show_market"):
				view.call_deferred("show_market", "PUBLIC")
			elif view.has_method("popup_centered"):
				view.call_deferred("popup_centered", Vector2i(1100, 700))
	)


func _on_space_pressed() -> void:
	## Open player SpaceLayerBoardView (script-instantiated; no scene required).
	_close_overlay_screens()
	var existing := get_tree().root.get_node_or_null("SpaceLayerBoardView")
	if existing != null:
		if existing is Window:
			existing.hide()
		existing.call_deferred("queue_free")
		return
	var script = load("res://scripts/ui/SpaceLayerBoardView.gd")
	if script == null:
		_show_toast("Space board unavailable", 2.0)
		return
	var view = script.new()
	if view == null:
		_show_toast("Space board failed to open", 2.0)
		return
	view.name = "SpaceLayerBoardView"
	get_tree().root.add_child(view)
	if view.has_method("show_board"):
		view.call_deferred("show_board", player_country_tag)
	elif view is Window:
		(view as Window).call_deferred("popup_centered")


func _on_matchmaking_pressed() -> void:
	_close_overlay_screens()
	var existing := get_tree().root.get_node_or_null("MatchmakingLobbyView")
	if existing != null:
		if existing is Window:
			existing.hide()
		existing.call_deferred("queue_free")
		return
	var script = load("res://scripts/ui/MatchmakingLobbyView.gd")
	if script == null:
		_show_toast("Matchmaking lobby unavailable", 2.0)
		return
	var view = script.new()
	if view == null:
		_show_toast("Matchmaking lobby failed to open", 2.0)
		return
	view.name = "MatchmakingLobbyView"
	get_tree().root.add_child(view)
	if view.has_method("show_lobby"):
		view.call_deferred("show_lobby", player_country_tag)
	elif view is Window:
		(view as Window).call_deferred("popup_centered")


func _close_screen(screen_name: String) -> void:
	var existing := get_tree().root.get_node_or_null(screen_name)
	if existing != null:
		if existing is Window:
			existing.hide()
		existing.call_deferred("queue_free")


func _toggle_root_popup(scene_name: String, scene_path: String, configure: Callable = Callable()) -> void:
	var existing := get_tree().root.get_node_or_null(scene_name)
	if existing != null:
		if existing is Window:
			existing.hide()
		existing.call_deferred("queue_free")
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_show_toast("%s not available yet." % scene_name, 2.5, true)
		return
	var view: Node = packed.instantiate()
	if view == null:
		return
	view.name = scene_name
	get_tree().root.add_child(view)
	if configure.is_valid():
		configure.call(view)


func _toggle_screen(screen_name: String, scene_path: String, configure: Callable) -> void:
	var existing := get_tree().root.get_node_or_null(screen_name)
	if existing != null:
		if existing is Window:
			existing.hide()
		existing.call_deferred("queue_free")
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("%s not found at %s" % [screen_name, scene_path])
		_show_toast("%s unavailable" % screen_name, 2.0, true)
		return

	var scene: Node = packed.instantiate()
	if scene == null:
		return
	configure.call(scene)
	scene.name = screen_name
	if scene is Control:
		var ctl := scene as Control
		ctl.process_mode = Node.PROCESS_MODE_ALWAYS
		ctl.mouse_filter = Control.MOUSE_FILTER_STOP
		# Stack above existing windows; DraggablePanel.bring_to_front can raise further.
		if ctl is DraggablePanel:
			(ctl as DraggablePanel).bring_to_front()
		else:
			ctl.z_index = 100
	# Prefer UILayer so panel sits above map canvas (root child can render under map).
	var ui_layer := get_tree().current_scene.get_node_or_null("UILayer") as CanvasLayer if get_tree().current_scene else null
	if ui_layer:
		ui_layer.add_child(scene)
	else:
		get_tree().root.add_child(scene)
	# Ensure newly opened screen is topmost among siblings.
	if scene is Control and scene.get_parent() != null:
		scene.get_parent().move_child(scene, scene.get_parent().get_child_count() - 1)
		if scene is DraggablePanel:
			(scene as DraggablePanel).bring_to_front()
	print("TopInfoBar: opened %s (multi-window OK — drag title, Esc closes front)" % screen_name)


func _on_save_pressed() -> void:
	# Immediate quicksave (user expectation: Menu→Save writes a file), then open Command Center.
	print("TopInfoBar: Menu Save → quicksave + open Command Center")
	if typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("save_game_detailed"):
		var res: Dictionary = SaveLoadManager.save_game_detailed("quicksave")
		if bool(res.get("ok", false)):
			var kb := int(int(res.get("bytes", 0)) / 1024)
			print("TopInfoBar: quicksave ok %d KB → %s" % [kb, str(res.get("absolute_path", ""))])
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Saved quicksave (%d KB)" % kb, 2.5)
		else:
			push_error("TopInfoBar: quicksave failed: %s" % str(res.get("error", "?")))
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Save failed: %s" % str(res.get("error", "?")), 3.5, true)
	elif typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("quicksave"):
		SaveLoadManager.quicksave()
	_open_command_center(true)


func _on_load_pressed() -> void:
	# Open Command Center focused on the save list (Load buttons on each slot).
	print("TopInfoBar: Menu Load → open Command Center")
	_open_command_center(true)


func _on_menu_pressed() -> void:
	_open_command_center(false)


func _open_command_center(refresh_list: bool = true) -> void:
	# Instance the Command Center overlay (CanvasLayer). Toggle closed if already open.
	var existing := get_tree().root.get_node_or_null("MainMenu")
	if existing != null:
		if refresh_list and existing.has_method("_refresh_save_list"):
			existing.call("_refresh_save_list")
			if existing.has_method("_set_status"):
				existing.call("_set_status", "Save list ready — use Load on a slot, or Save Game.")
			return
		if existing.has_method("_force_close"):
			existing.call("_force_close")
		elif existing.has_method("_on_close_requested"):
			existing.call("_on_close_requested")
		else:
			existing.queue_free()
			_pause_for_menu(false)
		return

	var packed := load("res://scenes/ui/MainMenu.tscn")
	if packed == null:
		_show_main_menu_popup_fallback()
		return

	var menu: Node = packed.instantiate()
	menu.name = "MainMenu"
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	if menu.has_signal("menu_closed"):
		menu.menu_closed.connect(func() -> void:
			_sync_pause_from_time_manager()
			_update_speed_buttons()
		)
	get_tree().root.add_child(menu)
	if refresh_list and menu.has_method("_refresh_save_list"):
		menu.call_deferred("_refresh_save_list")


func _on_settings_pressed() -> void:
	_on_menu_pressed()


func _on_help_pressed() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Epochs of Ascendancy — Quick Help"
	dlg.dialog_text = (
		"Grand strategy playtest harness.\n\n"
		+ "• Click provinces to inspect ownership, logistics, and combat stats\n"
		+ "• F10 — debug tools (map editor, borders, combat demo)\n"
		+ "• L — supply overlay · R/T/C/Y — infra sub-layers · S — peak snow\n"
		+ "• Menu — save/load and settings\n\n"
		+ "Ctrl+S quicksave · Ctrl+L quickload · Ctrl+Shift+S save browser · ESC closes most panels."
	)
	dlg.confirmed.connect(dlg.queue_free)
	get_tree().root.add_child(dlg)
	dlg.popup_centered(Vector2i(520, 260))

## === Main Menu Architecture (priority 1) ===
## TopInfoBar is the trigger:
##   - Emits `menu_option_selected(option: String)` (for future external MainMenu scenes).
##   - On button press / ESC, instances res://scenes/ui/MainMenu.tscn (or falls back to legacy popup).
## The MainMenu scene (MainMenu.gd + .tscn) is responsible for:
##   - Auto-pause on open / resume on close (self-contained via TimeManager).
##   - All menu options + integrated Save Manager view.
## This keeps TopInfoBar lightweight and the menu fully self-contained/extensible.
## See MainMenu.gd for the full implementation and SaveLoadManager.gd for the APIs it uses.

signal menu_option_selected(option: String)  # e.g. "save", "load", "return_to_main", "exit"

func _show_main_menu_popup_fallback() -> void:
	# Legacy code-driven popup (used as fallback until MainMenu.tscn is created/assigned).
	# In a full implementation this would be removed in favor of the scene.
	if typeof(SaveLoadManager) == TYPE_NIL:
		print("SaveLoadManager not ready")
		return

	var existing := get_tree().root.get_node_or_null("MainMenuPopup")
	if existing != null:
		existing.queue_free()

	_pause_for_menu(true)

	var panel := Panel.new()
	panel.name = "MainMenuPopup"
	panel.size = Vector2(620, 480)
	panel.position = Vector2( (get_viewport().get_visible_rect().size.x - 620) / 2 , 80)
	panel.z_index = 200

	var main_vbox := VBoxContainer.new()
	main_vbox.size = panel.size - Vector2(20, 20)
	main_vbox.position = Vector2(10, 10)
	panel.add_child(main_vbox)

	var title := Label.new()
	title.text = "Epochs of Ascendancy (Fallback Menu)"
	main_vbox.add_child(title)

	# Minimal options for fallback
	var options := ["Save Game", "Load Game", "Return to Main Menu", "Exit to Desktop"]
	for opt in options:
		var b := Button.new()
		b.text = opt
		b.pressed.connect(func():
			menu_option_selected.emit(opt.to_lower().replace(" ", "_"))
			panel.queue_free()
			_pause_for_menu(false)
		)
		main_vbox.add_child(b)

	get_tree().root.add_child(panel)
	print("Fallback main menu opened (auto-paused)")

func _add_menu_button(parent: VBoxContainer, label: String, option: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(func() -> void:
		menu_option_selected.emit(option)
		if option == "save":
			SaveLoadManager.quicksave()
			_show_save_manager_popup()
		elif option == "load":
			_on_load_pressed()
		elif option == "return_to_main":
			get_tree().change_scene_to_file("res://scenes/TestScenario.tscn")
		elif option == "exit":
			get_tree().quit()
		elif option == "help":
			_on_help_pressed()
		else:
			print("Menu option:", option)
		if option != "save":
			if parent.get_parent() is Panel:
				parent.get_parent().queue_free()
	)
	parent.add_child(btn)


## Basic in-code Save Manager popup (F6 or via Save button enhancement).
## Pack G: primary path uses save_browser_campaign_product_live + apply_save_browser_* only.
func _show_save_manager_popup() -> void:
	if typeof(SaveLoadManager) == TYPE_NIL and typeof(GameData) == TYPE_NIL:
		print("SaveLoadManager not ready")
		return

	# Remove any previous instance
	var existing := get_tree().root.get_node_or_null("SaveManagerPopup")
	if existing != null:
		existing.queue_free()

	var panel := Panel.new()
	panel.name = "SaveManagerPopup"
	panel.size = Vector2(560, 420)
	panel.position = Vector2(200, 120)
	panel.z_index = 100

	var vbox := VBoxContainer.new()
	vbox.size = panel.size - Vector2(20, 20)
	vbox.position = Vector2(10, 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Save Browser (product APIs · Pack G)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var product: Dictionary = {}
	if typeof(GameData) != TYPE_NIL and GameData.has_method("save_browser_campaign_product_live"):
		product = GameData.save_browser_campaign_product_live()
	var prod_lbl := Label.new()
	prod_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prod_lbl.text = str(product.get("summary", product.get("plain", "Save browser product")))
	vbox.add_child(prod_lbl)

	var action_row := HBoxContainer.new()
	var resume_btn := Button.new()
	resume_btn.text = "Resume recommended"
	resume_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_save_browser_resume"):
			GameData.apply_save_browser_resume(1)
		_update_date_time()
		_update_resources()
		panel.queue_free()
	)
	action_row.add_child(resume_btn)
	var cp_btn := Button.new()
	cp_btn.text = "Checkpoint (product)"
	cp_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_save_browser_checkpoint"):
			GameData.apply_save_browser_checkpoint(1)
		panel.queue_free()
		_show_save_manager_popup()
	)
	action_row.add_child(cp_btn)
	vbox.add_child(action_row)

	var rows: Array = []
	if SaveLoadManager != null and SaveLoadManager.has_method("list_slots_for_ui"):
		rows = SaveLoadManager.list_slots_for_ui()
	elif SaveLoadManager != null:
		rows = SaveLoadManager.list_saves()
	if rows.is_empty():
		var l := Label.new()
		l.text = "No slots. Use Checkpoint to create autosave via product API."
		vbox.add_child(l)
	else:
		for s in rows:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var h := HBoxContainer.new()
			var slot_label := Label.new()
			var occupied := bool(s.get("occupied", true))
			var row_text := str(s.get("label", s.get("slot", "?")))
			if row_text.is_empty():
				var meta := s.get("metadata", {}) as Dictionary
				var ts := str(meta.get("timestamp", ""))
				row_text = "%s  (%s)" % [s.get("slot", "?"), ts.substr(0, 16) if ts.length() > 16 else ts]
			slot_label.text = row_text
			slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(slot_label)

			var load_btn := Button.new()
			load_btn.text = "Load"
			load_btn.disabled = not occupied
			load_btn.pressed.connect(func():
				## Route through product resume when possible; else slot load via order panel save_slot
				var slot_n := str(s.get("slot", ""))
				if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_order_panel_action"):
					GameData.apply_order_panel_action("save_slot:%s" % slot_n if not slot_n.begins_with("save_slot:") else slot_n, 1)
					## Prefer explicit load if SaveLoadManager available for occupied slots
					if occupied and SaveLoadManager.has_method("load_game_detailed"):
						SaveLoadManager.load_game_detailed(slot_n)
					elif occupied:
						SaveLoadManager.load_game(slot_n)
				elif SaveLoadManager.has_method("load_game_detailed"):
					SaveLoadManager.load_game_detailed(slot_n)
				else:
					SaveLoadManager.load_game(slot_n)
				_update_date_time()
				_update_resources()
				panel.queue_free()
			)
			h.add_child(load_btn)

			var save_btn := Button.new()
			save_btn.text = "Save"
			save_btn.pressed.connect(func():
				var slot_n := str(s.get("slot", ""))
				## Pack G: prefer product checkpoint; per-slot still via SaveLoadManager for UI honesty
				if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_save_browser_checkpoint"):
					GameData.apply_save_browser_checkpoint(1)
				if SaveLoadManager.has_method("save_game_detailed"):
					SaveLoadManager.save_game_detailed(slot_n)
				else:
					SaveLoadManager.save_game(slot_n)
				panel.queue_free()
				_show_save_manager_popup()
			)
			h.add_child(save_btn)

			var del_btn := Button.new()
			del_btn.text = "Delete"
			del_btn.disabled = not occupied
			del_btn.pressed.connect(func():
				SaveLoadManager.delete_save(s.get("slot", ""))
				panel.queue_free()
				_show_save_manager_popup()
			)
			h.add_child(del_btn)

			vbox.add_child(h)

	var close_btn := Button.new()
	close_btn.text = "Close (F6)"
	close_btn.pressed.connect(func(): panel.queue_free())
	vbox.add_child(close_btn)

	get_tree().root.add_child(panel)
	print("Save Browser popup opened (%d slots) via product APIs" % rows.size())


## Helper to populate the Save Manager list inside the main menu with rich metadata.
func _populate_save_list(parent: VBoxContainer, owning_panel: Panel) -> void:
	parent.add_child(Control.new())  # spacer
	var rows: Array = []
	if SaveLoadManager.has_method("list_slots_for_ui"):
		rows = SaveLoadManager.list_slots_for_ui()
	else:
		rows = SaveLoadManager.list_saves()
	if rows.is_empty():
		var l := Label.new()
		l.text = "No saves yet. Use the menu to create one."
		parent.add_child(l)
		return

	for s in rows:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var h := HBoxContainer.new()
		var occupied := bool(s.get("occupied", true))
		var meta := s.get("metadata", {}) as Dictionary
		var ts := str(meta.get("timestamp", meta.get("last_played", "")))
		var scenario := str(meta.get("scenario_id", "unknown"))
		var label_text := str(s.get("label", ""))
		if label_text.is_empty():
			label_text = "%s | %s | %s" % [s.get("slot", "?"), ts.substr(0, 16), scenario]
		var slot_label := Label.new()
		slot_label.text = label_text
		slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(slot_label)

		var load_btn := Button.new()
		load_btn.text = "Load"
		load_btn.disabled = not occupied
		load_btn.pressed.connect(func():
			var slot_n := str(s.get("slot", ""))
			if SaveLoadManager.has_method("load_game_detailed"):
				SaveLoadManager.load_game_detailed(slot_n)
			else:
				SaveLoadManager.load_game(slot_n)
			_update_date_time()
			_update_resources()
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Game loaded: " + slot_n, 2.5)
			if owning_panel and is_instance_valid(owning_panel):
				owning_panel.queue_free()
			_pause_for_menu(false)
		)
		h.add_child(load_btn)

		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.pressed.connect(func():
			SaveLoadManager.delete_save(s.get("slot", ""))
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Save deleted: " + s.get("slot", ""), 2.0, true)
			if owning_panel and is_instance_valid(owning_panel):
				owning_panel.queue_free()
			_show_main_menu_popup_fallback()  # refresh
		)
		h.add_child(del_btn)

		# Rename (lightweight foundation - future menu can use proper dialog)
		var rename_btn := Button.new()
		rename_btn.text = "Rename"
		rename_btn.pressed.connect(func():
			# Simple inline rename for foundation (in full UI this would be a nice dialog)
			print("Rename requested for " + s.get("slot", "") + " (use SaveLoadManager.rename_save in console for now)")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Rename: use console for now (API ready)", 2.0)
			if owning_panel and is_instance_valid(owning_panel):
				owning_panel.queue_free()
			_show_main_menu_popup_fallback()
		)
		h.add_child(rename_btn)

		parent.add_child(h)


func _show_toast(message: String, duration: float = 2.5, is_error: bool = false) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(message, duration, is_error)
	else:
		push_warning(message)


static func find_in_tree(tree: SceneTree) -> TopInfoBar:
	if tree == null:
		return null
	var direct := tree.root.get_node_or_null("UILayer/TopInfoBar")
	if direct is TopInfoBar:
		return direct as TopInfoBar
	for child in tree.root.get_children():
		var nested := child.get_node_or_null("UILayer/TopInfoBar")
		if nested is TopInfoBar:
			return nested as TopInfoBar
	return tree.get_first_node_in_group("top_info_bar") as TopInfoBar
