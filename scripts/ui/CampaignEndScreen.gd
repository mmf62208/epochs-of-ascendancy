# scripts/ui/CampaignEndScreen.gd
## Modal campaign end. Layer 125: above the HUD (110) and the living title (120),
## below the Command Center (130). Never shown headless.
class_name CampaignEndScreen
extends CanvasLayer

var _model: Dictionary = {}
var _title: Label
var _reason: Label
var _stats: Label
var _btn_menu: Button
var _btn_load: Button
var _btn_keep: Button
var _btn_continue: Button
var _keep_reason: Label
var _panel: Panel


static func present(model: Dictionary) -> Node:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	_dismiss_overlays(tree)
	for n in tree.get_nodes_in_group("campaign_end_screen"):
		if is_instance_valid(n):
			n.queue_free()
	var layer := CampaignEndScreen.new()
	layer._model = model.duplicate(true)
	layer.layer = 125
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	return layer


static func _dismiss_overlays(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group("campaign_peace_sheet"):
		if is_instance_valid(n):
			if n is CanvasLayer:
				(n as CanvasLayer).visible = false
			n.queue_free()
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("hide_for_campaign_end"):
		LeaderEventUI.hide_for_campaign_end()
	var bar := tree.get_first_node_in_group("top_info_bar")
	if bar != null and bar.has_method("refresh_campaign_war_readout"):
		bar.call("refresh_campaign_war_readout")


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("campaign_end_screen")
	var blocker := ColorRect.new()
	blocker.name = "Blocker"
	blocker.color = Color(0.02, 0.03, 0.06, 0.92)
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(_on_blocker_input)
	add_child(blocker)
	_panel = Panel.new()
	_panel.name = "EndPanel"
	_panel.custom_minimum_size = Vector2(560, 360)
	_panel.position = Vector2(360, 180)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.12, 1.0)
	panel_style.border_color = Color(0.95, 0.86, 0.55, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	box.custom_minimum_size = Vector2(512, 320)
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_title = Label.new()
	_title.name = "Title"
	_title.text = str(_model.get("title", "Campaign over"))
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.95, 0.86, 0.55))
	box.add_child(_title)
	_reason = Label.new()
	_reason.name = "Reason"
	_reason.text = str(_model.get("reason", ""))
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.custom_minimum_size = Vector2(500, 48)
	box.add_child(_reason)
	var date_l := Label.new()
	date_l.name = "Date"
	date_l.text = str(_model.get("date", ""))
	box.add_child(date_l)
	_stats = Label.new()
	_stats.name = "Stats"
	_stats.text = _stats_line()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_stats)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_btn_menu = _button("Main menu", _on_main_menu)
	_btn_menu.name = "BtnMainMenu"
	row.add_child(_btn_menu)
	_btn_load = _button("Load", _on_load)
	_btn_load.name = "BtnLoad"
	row.add_child(_btn_load)
	_btn_keep = _button("Keep playing", _on_keep)
	_btn_keep.name = "BtnKeepPlaying"
	var allow_keep := bool(_model.get("allow_keep_playing", false))
	_btn_keep.visible = allow_keep
	_btn_keep.disabled = not allow_keep
	row.add_child(_btn_keep)
	_btn_continue = _button("Continue as another nation", _on_continue)
	_btn_continue.name = "BtnContinue"
	_btn_continue.visible = bool(_model.get("allow_continuation", false))
	row.add_child(_btn_continue)
	_keep_reason = Label.new()
	_keep_reason.name = "KeepPlayingReason"
	var keep_reason := str(_model.get("keep_playing_reason", ""))
	_keep_reason.text = keep_reason
	_keep_reason.visible = not allow_keep and not keep_reason.is_empty()
	_keep_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keep_reason.custom_minimum_size = Vector2(500, 24)
	box.add_child(_keep_reason)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _stats_line() -> String:
	var stats: Dictionary = _model.get("stats", {}) if _model.get("stats") is Dictionary else {}
	var cap_n := int(stats.get("capitulated_by_side", 0))
	var cap_phrase := "%d nations capitulated" % cap_n
	if typeof(CampaignEndDomain) != TYPE_NIL:
		cap_phrase = CampaignEndDomain.nation_capitulated_phrase(cap_n)
	return "Days %d. Provinces (controlled) %d → %d. Wars %d. %s. Factory share %.1f%%." % [
		int(stats.get("days", 0)),
		int(stats.get("provinces_start", 0)),
		int(stats.get("provinces_end", 0)),
		int(stats.get("wars_fought", 0)),
		cap_phrase,
		float(stats.get("factory_share", 0.0)) * 100.0,
	]


func _on_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func handle_pointer(event: InputEvent) -> String:
	if not (event is InputEventMouseButton):
		return "panel"
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return "panel"
	var pos := mb.position
	if _hit(_btn_menu, pos):
		_on_main_menu()
		return "main_menu"
	if _hit(_btn_load, pos):
		_on_load()
		return "load"
	if _btn_keep != null and _btn_keep.visible and not _btn_keep.disabled and _hit(_btn_keep, pos):
		_on_keep()
		return "keep"
	if _btn_continue != null and _btn_continue.visible and _hit(_btn_continue, pos):
		_on_continue()
		return "continue"
	return "panel"


func _hit(btn: Button, pos: Vector2) -> bool:
	if btn == null or not is_instance_valid(btn) or not btn.visible:
		return false
	return btn.get_global_rect().has_point(pos)


func _on_main_menu() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var bar := tree.get_first_node_in_group("top_info_bar")
	if bar != null and bar.has_method("open_command_center_stay"):
		bar.call("open_command_center_stay")
		return
	var existing := tree.root.get_node_or_null("MainMenu")
	if existing != null and is_instance_valid(existing) and not existing.is_queued_for_deletion():
		return
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	tree.root.add_child(menu)


func _on_load() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var bar := tree.get_first_node_in_group("top_info_bar")
	if bar != null and bar.has_method("_on_load_pressed"):
		bar.call("_on_load_pressed")
		return
	_on_main_menu()


func _on_keep() -> void:
	if not bool(_model.get("allow_keep_playing", false)):
		return
	if typeof(CampaignEndDomain) != TYPE_NIL:
		CampaignEndDomain.set_keep_playing()
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("restore_after_campaign_end"):
		LeaderEventUI.restore_after_campaign_end()
	visible = false
	queue_free()


func _on_continue() -> void:
	if typeof(GameData) != TYPE_NIL and GameData.has_method("trigger_national_defeat_or_continuation"):
		var tag := str(_model.get("player_tag", ""))
		GameData.trigger_national_defeat_or_continuation(tag, "campaign_defeat")
