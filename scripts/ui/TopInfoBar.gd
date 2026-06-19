# scripts/ui/TopInfoBar.gd
class_name TopInfoBar
extends Control

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

const WIDTH_COMPACT := 1280
const WIDTH_NARROW := 1040
const WIDTH_NAV_OVERFLOW := 1180

@onready var _content_row: HBoxContainer = $ContentRow
@onready var _resources_container: HBoxContainer = $ContentRow/RightContainer/ResourcesContainer
@onready var _center_container: HBoxContainer = $ContentRow/CenterContainer
@onready var _left_container: HBoxContainer = $ContentRow/LeftContainer
@onready var _right_container: HBoxContainer = $ContentRow/RightContainer
@onready var _menu_container: HBoxContainer = $ContentRow/RightContainer/MenuContainer

var _nav_overflow: MenuButton = null


func _ready() -> void:
	add_to_group("top_info_bar")
	_apply_theme()
	_connect_buttons()
	_sync_pause_from_time_manager()
	_update_speed_buttons()
	_update_date_time()
	_update_resources()
	_update_direction()
	if date_time_label:
		date_time_label.clip_text = false
		date_time_label.visible = true
		date_time_label.custom_minimum_size = Vector2(210, 28)
		date_time_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		date_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		date_time_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
		date_time_label.add_theme_font_size_override("font_size", 14)
		_update_date_time()
	# Robust against top cutoff on Linux/WM titlebars, fractional scaling, or viewport vs window mismatch.
	custom_minimum_size.y = 84.0
	offset_bottom = 84.0
	offset_top = 0.0
	var cr := get_node_or_null("ContentRow") as Control
	if cr:
		cr.offset_left = 12.0
		cr.offset_right = -12.0
		cr.offset_top = 10.0
		cr.offset_bottom = -10.0
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

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()

	if get_viewport():
		get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")


func get_bar_height() -> float:
	if size.y > 4.0:
		return size.y
	return custom_minimum_size.y


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var vp_w := get_viewport().get_visible_rect().size.x
	var compact := vp_w < WIDTH_COMPACT
	var narrow := vp_w < WIDTH_NARROW
	var nav_overflow := vp_w < WIDTH_NAV_OVERFLOW

	if _content_row:
		_content_row.offset_left = 12.0
		_content_row.offset_right = -12.0
		_content_row.add_theme_constant_override("separation", 4 if narrow else (6 if compact else 8))

	if _left_container:
		_left_container.add_theme_constant_override("separation", 4 if compact else 8)
		_left_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if date_time_label and date_time_label.get_parent() != _left_container:
			date_time_label.reparent(_left_container)
			_left_container.move_child(date_time_label, 1)

	if _right_container:
		_right_container.add_theme_constant_override("separation", 6 if compact else 10)
		_right_container.size_flags_horizontal = Control.SIZE_SHRINK_END
		if _menu_container:
			_right_container.move_child(_menu_container, _right_container.get_child_count() - 1)

	var speed_btns := [pause_button, speed1_button, speed2_button, speed3_button, speed4_button]
	for sb in speed_btns:
		if sb:
			sb.custom_minimum_size = Vector2(38 if compact else 42, 30 if compact else 34)
			sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_ensure_nav_overflow_menu()
	_apply_nav_overflow_mode(nav_overflow, compact)

	if _resources_container:
		_resources_container.visible = vp_w >= WIDTH_COMPACT and not narrow
		_resources_container.add_theme_constant_override("separation", 8 if compact else 12)

	if steel_label:
		steel_label.visible = vp_w >= WIDTH_COMPACT + 120
	if aluminum_label:
		aluminum_label.visible = vp_w >= WIDTH_COMPACT + 200
	if rubber_label:
		rubber_label.visible = vp_w >= WIDTH_COMPACT + 80

	if date_time_label:
		date_time_label.visible = true
		date_time_label.custom_minimum_size = Vector2(200 if compact else 210, 28)
		date_time_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		date_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		date_time_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		date_time_label.add_theme_font_size_override("font_size", 13 if compact else 14)
		date_time_label.tooltip_text = GameDateDisplay.format_top_bar_tooltip()

	if menu_button and is_instance_valid(menu_button):
		menu_button.custom_minimum_size = Vector2(56 if compact else 64, 30 if compact else 34)
		menu_button.size_flags_horizontal = Control.SIZE_SHRINK_END

	custom_minimum_size.y = 84.0 if not compact else 80.0
	offset_bottom = custom_minimum_size.y


func _ensure_nav_overflow_menu() -> void:
	if _nav_overflow != null and is_instance_valid(_nav_overflow):
		return
	if _center_container == null:
		return
	_nav_overflow = MenuButton.new()
	_nav_overflow.name = "NavOverflowMenu"
	_nav_overflow.text = "Gov"
	_nav_overflow.visible = false
	_nav_overflow.custom_minimum_size = Vector2(54, 30)
	_center_container.add_child(_nav_overflow)
	RetrowaveTheme.style_nav_button(_nav_overflow)
	var pop := _nav_overflow.get_popup()
	pop.add_item("Production", 0)
	pop.add_item("Leaders", 1)
	pop.add_item("Technology", 2)
	pop.add_item("Diplomacy", 3)
	pop.add_item("Agents", 4)
	pop.add_item("Trade", 5)
	pop.id_pressed.connect(_on_nav_overflow_pressed)


func _on_nav_overflow_pressed(id: int) -> void:
	match id:
		0: _on_production_pressed()
		1: _on_leaders_pressed()
		2: _on_technology_pressed()
		3: _on_diplomacy_pressed()
		4: _on_agents_pressed()
		5: _on_trade_pressed()


func _apply_nav_overflow_mode(use_overflow: bool, compact: bool) -> void:
	if _nav_overflow:
		_nav_overflow.visible = use_overflow
	var nav_btns: Array[Button] = [
		production_button, leaders_button, technology_button,
		diplomacy_button, agents_button,
	]
	if map_button:
		nav_btns.append(map_button)
	for btn in nav_btns:
		if btn:
			btn.visible = not use_overflow
	if trade_button:
		trade_button.visible = not use_overflow and not compact
	if not use_overflow:
		_set_nav_button_labels(compact, get_viewport().get_visible_rect().size.x < WIDTH_NARROW)


func _set_nav_button_labels(compact: bool, narrow: bool) -> void:
	var pairs: Array[Array] = [
		[production_button, "Production", "Prod"],
		[leaders_button, "Leaders", "Lead"],
		[technology_button, "Technology", "Tech"],
		[diplomacy_button, "Diplomacy", "Dipl"],
		[agents_button, "Agents", "Agnt"],
		[map_button, "Map", "Map"],
	]
	for row in pairs:
		var btn: Button = row[0] as Button
		if btn == null:
			continue
		btn.text = str(row[2]) if (compact or narrow) else str(row[1])
		btn.custom_minimum_size = Vector2(52 if narrow else (62 if compact else 0), 26 if compact else 32)
	if trade_button:
		trade_button.text = "Trade" if not compact else "Trd"
		trade_button.visible = not narrow
		trade_button.custom_minimum_size = Vector2(48 if compact else 70, 26 if compact else 28)


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

	# Per spec decision: core 6 primary overhead kept (Production/Leaders/Tech/Diplomacy/Agents/Map) for theme+loops (econ/mil/tech/dip/will/theater).
	# resources+date right, speeds left, save/settings/help (and Policies/Dir) consolidated to Menu for room/visibility polish + clean bar.
	# Compact Dir (trajectory visibility for will/erosion) retained as small button (high value awareness) but can be menu-driven; placed for no cutoff.

	# Direction / loyalty trajectory lives in Menu → Policies (keeps bar from clipping on the right).
	direction_label = null

	map_button.visible = false
	map_button.tooltip_text = "You are on the map (open screens via Production, Leaders, etc.)"

	RetrowaveTheme.style_primary_button(production_button)
	RetrowaveTheme.style_primary_button(leaders_button)
	for btn in [save_button, load_button, settings_button, help_button, pause_button]:
		RetrowaveTheme.style_secondary_button(btn)

	_setup_compact_menu()

	# Debug overlay quick toggle (only in debug builds) -- we put "Debug (F10)" inside the compact MenuButton
	# to save top bar space. F10 / Ctrl+Shift+R still work globally.
	if OS.is_debug_build() and debug_button == null:
		# Pre-create the overlay (hidden) so hotkeys and other systems can find it immediately.
		# Use the static toggle/hide which now prefers adding under UILayer for proper screen-space behavior.
		# Deferred to avoid any early tree/window issues on Linux/X11.
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
	if OS.is_debug_build():
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
			if OS.is_debug_build():
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
	var is_headless_ev := OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1"
	if is_headless_ev:
		return  # pre-existing fix: guard _deferred_precreate_debug "toggle" call for headless (EOA_HEADLESS_EVIDENCE or has_method); safe for 50T evidence runs
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toggle()
	else:
		var root := get_tree().root if get_tree() else null
		var dbg := root.get_node_or_null("DebugOverlay") if root else null
		if dbg and dbg.has_method("toggle"):
			dbg.toggle()
	# hide after a frame to let creation settle (avoids X11 window issues on some systems)
	var dbg2 := (get_tree().root.get_node_or_null("DebugOverlay") if get_tree() else null)
	if dbg2 and dbg2.has_method("hide_overlay"):
		get_tree().create_timer(0.01).timeout.connect(dbg2.hide_overlay, CONNECT_ONE_SHOT)
	elif typeof(DebugOverlay) != TYPE_NIL:
		get_tree().create_timer(0.01).timeout.connect(Callable(DebugOverlay, "hide_overlay"), CONNECT_ONE_SHOT)


func _connect_buttons() -> void:
	pause_button.pressed.connect(_on_pause_pressed)
	speed1_button.pressed.connect(func() -> void: _set_game_speed(1))
	speed2_button.pressed.connect(func() -> void: _set_game_speed(2))
	speed3_button.pressed.connect(func() -> void: _set_game_speed(3))
	speed4_button.pressed.connect(func() -> void: _set_game_speed(4))

	production_button.pressed.connect(_on_production_pressed)
	leaders_button.pressed.connect(_on_leaders_pressed)
	technology_button.pressed.connect(_on_technology_pressed)
	diplomacy_button.pressed.connect(_on_diplomacy_pressed)
	agents_button.pressed.connect(_on_agents_pressed)
	map_button.pressed.connect(_on_map_pressed)

	if trade_button:
		trade_button.pressed.connect(_on_trade_pressed)

	save_button.pressed.connect(_on_menu_pressed)  # Open main menu for immersion (Save/Load now behind menu)
	load_button.pressed.connect(_on_menu_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	help_button.pressed.connect(_on_help_pressed)


func _on_tick() -> void:
	# Drive simulation from real time when not paused
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.advance_real_time(1.0)   # 1 real second → scaled game days

	_update_date_time()
	_update_resources()
	_update_direction()

func _update_direction() -> void:
	# Trajectory chip removed from top bar (Menu → Policies) to prevent right-edge clipping.
	pass


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# Global debug hotkey — opens the dedicated Debug Overlay
	if event.keycode == KEY_F10 or (event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_R):
		call_deferred("_deferred_debug_toggle")
		get_viewport().set_input_as_handled()
		return
	# Dev convenience keybinds (F5/F6/F9/ESC)
	if event.keycode == KEY_F5:
		if typeof(SaveLoadManager) != TYPE_NIL:
			SaveLoadManager.quicksave()
			print("F5 QuickSave triggered")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F9:
		if typeof(SaveLoadManager) != TYPE_NIL:
			SaveLoadManager.quickload()
			_update_date_time()
			_update_resources()
			print("F9 QuickLoad triggered")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F6:
		_show_save_manager_popup()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		_on_menu_pressed()
		get_viewport().set_input_as_handled()


func _set_game_speed(speed: int) -> void:
	current_speed = clampi(speed, 1, 4)
	is_paused = false
	Engine.time_scale = float(current_speed)
	_sync_time_manager_controls()
	_update_speed_buttons()
	_update_date_time()


func _update_speed_buttons() -> void:
	var buttons := [speed1_button, speed2_button, speed3_button, speed4_button]
	for i in buttons.size():
		RetrowaveTheme.style_speed_button(buttons[i], not is_paused and (i + 1) == current_speed)
	if is_paused:
		pause_button.modulate = RetrowaveTheme.MAGENTA
	else:
		pause_button.modulate = Color.WHITE


func _on_pause_pressed() -> void:
	is_paused = not is_paused
	Engine.time_scale = 0.0 if is_paused else float(current_speed)
	_sync_time_manager_controls()
	_update_speed_buttons()
	_update_date_time()


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
	TimeManager.set_time_scale(float(current_speed) if not is_paused else 0.0)

## Auto-pause/resume helper for main menu (priority 1).
## Pauses the game (and TimeManager) when menu opens, resumes on close.
## Non-intrusive: preserves previous speed/pause state where possible.
func _pause_for_menu(pause: bool) -> void:
	if typeof(TimeManager) == TYPE_NIL:
		# Fallback to direct Engine control
		Engine.time_scale = 0.0 if pause else float(current_speed)
		return

	if pause:
		# Store previous state if not already paused by menu
		if not has_meta("was_paused_before_menu"):
			set_meta("was_paused_before_menu", is_paused)
			set_meta("speed_before_menu", current_speed)
		is_paused = true
		Engine.time_scale = 0.0
		TimeManager.set_paused(true)
		TimeManager.set_time_scale(0.0)
	else:
		# Restore previous state
		var was_paused = get_meta("was_paused_before_menu", false)
		var prev_speed = get_meta("speed_before_menu", 1)
		is_paused = was_paused
		current_speed = prev_speed
		Engine.time_scale = 0.0 if is_paused else float(current_speed)
		TimeManager.set_paused(is_paused)
		TimeManager.set_time_scale(float(current_speed) if not is_paused else 0.0)
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
	oil_label.text = "Oil: %.0f" % float(stockpile.get("oil", 0.0))
	rubber_label.text = "Rubber: %.0f" % float(stockpile.get("rubber", 0.0))


func _close_overlay_screens() -> void:
	_close_screen("ProductionAssignmentScreen")
	_close_screen("LeaderAssignmentScreen")
	_close_screen("AgentAssignmentScreen")
	_close_screen("NationalSpiritsScreen")
	_close_screen("TechnologyScreen")


func _on_production_pressed() -> void:
	_close_overlay_screens()
	_close_screen("ProductionAssignmentScreen")
	_toggle_screen(
		"ProductionAssignmentScreen",
		"res://scenes/ui/ProductionAssignmentScreen.tscn",
		func(scene: Node) -> void:
			var screen := scene as ProductionAssignmentScreen
			if screen != null:
				screen.country_tag = player_country_tag
	)


func _on_leaders_pressed() -> void:
	_close_overlay_screens()
	_close_screen("LeaderAssignmentScreen")
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
	_close_overlay_screens()
	_toggle_screen(
		"TechnologyScreen",
		"res://scenes/ui/TechnologyScreen.tscn",
		func(scene: Node) -> void:
			var screen := scene as TechnologyScreen
			if screen != null:
				screen.country_tag = player_country_tag
	)


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
	_close_overlay_screens()
	_close_screen("AgentAssignmentScreen")
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
		return

	var scene: Node = packed.instantiate()
	if scene == null:
		return
	configure.call(scene)
	scene.name = screen_name
	get_tree().root.add_child(scene)


func _on_save_pressed() -> void:
	# Deprecated direct path - now routes through main menu for immersion
	_on_menu_pressed()

func _on_load_pressed() -> void:
	# Deprecated direct path - now routes through main menu for immersion
	_on_menu_pressed()

func _on_menu_pressed() -> void:
	# Clean architecture: instance the dedicated MainMenu scene (priority 1).
	# The scene handles its own auto-pause, Save Manager, and emits/responds to signals.
	var existing := get_tree().root.get_node_or_null("MainMenu")
	if existing != null:
		if existing.has_method("_on_close_requested"):
			existing._on_close_requested()
		else:
			existing.queue_free()
			_pause_for_menu(false)
		return

	var packed := load("res://scenes/ui/MainMenu.tscn")
	if packed == null:
		# Fallback to the old code-driven popup during development
		_show_main_menu_popup_fallback()
		return

	var menu: Node = packed.instantiate()
	menu.name = "MainMenu"
	if menu.has_signal("menu_closed"):
		menu.menu_closed.connect(func() -> void:
			_sync_pause_from_time_manager()
			_update_speed_buttons()
		)
	get_tree().root.add_child(menu)


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
		+ "F5 quicksave · F9 quickload · ESC closes most panels."
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
## Lists saves from SaveLoadManager.list_saves(), with Load / Delete actions.
## Rename is available via SaveLoadManager.rename_save() from console/script for now.
## This gives immediate usable UX without requiring a dedicated .tscn yet.
func _show_save_manager_popup() -> void:
	if typeof(SaveLoadManager) == TYPE_NIL:
		print("SaveLoadManager not ready")
		return

	# Remove any previous instance
	var existing := get_tree().root.get_node_or_null("SaveManagerPopup")
	if existing != null:
		existing.queue_free()

	var panel := Panel.new()
	panel.name = "SaveManagerPopup"
	panel.size = Vector2(520, 380)
	panel.position = Vector2(200, 120)
	panel.z_index = 100

	# Simple styling (reuses theme if possible)
	if has_node("/root/RetrowaveTheme"):
		# best effort
		pass

	var vbox := VBoxContainer.new()
	vbox.size = panel.size - Vector2(20, 20)
	vbox.position = Vector2(10, 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Save Manager (F6 to close, click actions)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var saves := SaveLoadManager.list_saves()
	if saves.is_empty():
		var l := Label.new()
		l.text = "No saves yet. Use F5 / Save button to create 'quicksave' or 'autosave'."
		vbox.add_child(l)
	else:
		for s in saves:
			var h := HBoxContainer.new()
			var slot_label := Label.new()
			var meta := s.get("metadata", {}) as Dictionary
			var ts := str(meta.get("timestamp", ""))
			slot_label.text = "%s  (%s)" % [s.get("slot", "?"), ts.substr(0, 16) if ts.length() > 16 else ts]
			slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(slot_label)

			var load_btn := Button.new()
			load_btn.text = "Load"
			load_btn.pressed.connect(func():
				SaveLoadManager.load_game(s.get("slot", ""))
				_update_date_time()
				_update_resources()
				panel.queue_free()
			)
			h.add_child(load_btn)

			var del_btn := Button.new()
			del_btn.text = "Delete"
			del_btn.pressed.connect(func():
				SaveLoadManager.delete_save(s.get("slot", ""))
				panel.queue_free()
				_show_save_manager_popup()  # refresh
			)
			h.add_child(del_btn)

			vbox.add_child(h)

	var close_btn := Button.new()
	close_btn.text = "Close (F6)"
	close_btn.pressed.connect(func(): panel.queue_free())
	vbox.add_child(close_btn)

	get_tree().root.add_child(panel)
	print("Save Manager popup opened (%d saves)" % saves.size())


## Helper to populate the Save Manager list inside the main menu with rich metadata.
func _populate_save_list(parent: VBoxContainer, owning_panel: Panel) -> void:
	parent.add_child(Control.new())  # spacer
	var saves := SaveLoadManager.list_saves()
	if saves.is_empty():
		var l := Label.new()
		l.text = "No saves yet. Use the menu to create one."
		parent.add_child(l)
		return

	for s in saves:
		var h := HBoxContainer.new()
		var meta := s.get("metadata", {}) as Dictionary
		var ts := str(meta.get("timestamp", meta.get("last_played", "")))
		var scenario := str(meta.get("scenario_id", "unknown"))
		var label_text := "%s | %s | %s" % [s.get("slot", "?"), ts.substr(0, 16), scenario]
		var slot_label := Label.new()
		slot_label.text = label_text
		slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(slot_label)

		var load_btn := Button.new()
		load_btn.text = "Load"
		load_btn.pressed.connect(func():
			var ok := SaveLoadManager.load_game(s.get("slot", ""))
			_update_date_time()
			_update_resources()
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Game loaded: " + s.get("slot", ""), 2.5)
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
