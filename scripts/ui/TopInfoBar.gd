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

@onready var save_button: Button = $ContentRow/RightContainer/MenuContainer/SaveButton
@onready var load_button: Button = $ContentRow/RightContainer/MenuContainer/LoadButton
@onready var settings_button: Button = $ContentRow/RightContainer/MenuContainer/SettingsButton
@onready var help_button: Button = $ContentRow/RightContainer/MenuContainer/HelpButton

var debug_button: Button   # Only created in debug builds

var current_speed: int = 1
var is_paused: bool = false


func _ready() -> void:
	_apply_theme()
	_connect_buttons()
	_sync_pause_from_time_manager()
	_update_speed_buttons()
	_update_date_time()
	_update_resources()
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(_on_game_year_advanced):
			TimeManager.game_year_advanced.connect(_on_game_year_advanced)
		if not TimeManager.game_month_advanced.is_connected(_on_game_month_advanced):
			TimeManager.game_month_advanced.connect(_on_game_month_advanced)
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()


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
	RetrowaveTheme.style_primary_button(production_button)
	RetrowaveTheme.style_primary_button(leaders_button)
	for btn in [save_button, load_button, settings_button, help_button, pause_button]:
		RetrowaveTheme.style_secondary_button(btn)

	# Debug overlay quick toggle (only in debug builds)
	if OS.is_debug_build() and debug_button == null:
		debug_button = Button.new()
		debug_button.text = "DBG"
		debug_button.tooltip_text = "Open Debug Overlay (F10 / Ctrl+Shift+R)"
		debug_button.custom_minimum_size = Vector2(42, 28)
		$ContentRow/RightContainer/MenuContainer.add_child(debug_button)
		RetrowaveTheme.style_secondary_button(debug_button)
		debug_button.pressed.connect(func(): DebugOverlay.toggle())

		# Pre-create the overlay (hidden) so hotkeys and other systems can find it immediately
		if DebugOverlay.instance == null:
			var overlay := DebugOverlay.new()
			add_child(overlay)
			overlay.visible = false


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


func _unhandled_input(event: InputEvent) -> void:
	# Global debug hotkey — now opens the dedicated Debug Overlay
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10 or (event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_R):
			DebugOverlay.toggle()
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
	var packed := load("res://scenes/ui/DiplomacyView.tscn")
	if packed:
		var view = packed.instantiate()
		get_tree().root.add_child(view)
		# DiplomacyView handles its own popup_centered in _ready
	else:
		_show_toast("Diplomacy screen not available yet.", 2.5, true)


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

func _on_trade_pressed() -> void:
	var packed := load("res://scenes/ui/TradeMarketView.tscn")
	if packed:
		var view = packed.instantiate()
		get_tree().root.add_child(view)
		if view.has_method("show_market"):
			view.show_market("PUBLIC")
		else:
			view.popup_centered(Vector2i(1100, 700))
	else:
		_show_toast("Trade Market not available.", 2.5, true)


func _close_screen(screen_name: String) -> void:
	var existing := get_tree().root.get_node_or_null(screen_name)
	if existing != null:
		existing.queue_free()


func _toggle_screen(screen_name: String, scene_path: String, configure: Callable) -> void:
	var existing := get_tree().root.get_node_or_null(screen_name)
	if existing != null:
		existing.queue_free()
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
	print("Open Help (TODO)")

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
	btn.pressed.connect(func():
		menu_option_selected.emit(option)
		# Default handlers for now (can be overridden by main menu scene later)
		match option:
			"save":
				SaveLoadManager.quicksave()
				_show_save_manager_popup()  # reuse existing
			"load":
				_on_load_pressed()
			"return_to_main":
				print("TODO: Return to Main Menu (emit signal for scene change)")
			"exit":
				get_tree().quit()
			"help":
				_on_help_pressed()
			_:
				print("Menu option:", option)
		# Close the menu after action (except save manager which manages itself)
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


## Dev convenience keybinds (F5 = quicksave, F9 = quickload).
## These are intentionally loud in the console so you know the save/load cycle fired.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
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
