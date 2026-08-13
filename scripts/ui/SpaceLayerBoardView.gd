# scripts/ui/SpaceLayerBoardView.gd
## Player-facing space layer board + discovery choice surface.
## Lightweight Window mirroring TradeMarketView desk style.
class_name SpaceLayerBoardView
extends Window

const PLAYER_FALLBACK := "USA"

var _player_tag: String = PLAYER_FALLBACK
var _title: Label
var _body: RichTextLabel
var _discovery_box: VBoxContainer
var _choice_box: VBoxContainer
var _status: Label
var _refresh_btn: Button
var _close_btn: Button
var _layer_btns: HBoxContainer
var _selected_discovery_id: String = ""
## discovery_id -> last resolve result (session UX)
var _last_resolve: Dictionary = {}


func _ready() -> void:
	title = "Space Layer Board"
	size = Vector2i(780, 560)
	unresizable = false
	_resolve_player()
	_build_ui()
	refresh_board()


func _resolve_player() -> void:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		_player_tag = str(LeaderManager.get_player_country_tag())
	if _player_tag.is_empty():
		_player_tag = PLAYER_FALLBACK


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	root.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_title = Label.new()
	_title.text = "Space Layer — %s" % _player_tag
	_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title)
	_layer_btns = HBoxContainer.new()
	_layer_btns.add_theme_constant_override("separation", 6)
	vbox.add_child(_layer_btns)
	for layer_id in ["earth_surface", "near_earth", "cis_lunar", "inner_system", "outer_system", "galaxy_bridge"]:
		var b := Button.new()
		b.text = layer_id.replace("_", " ")
		b.pressed.connect(_on_layer_pressed.bind(layer_id))
		_layer_btns.add_child(b)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.fit_content = false
	_body.scroll_active = true
	_body.custom_minimum_size = Vector2(0, 160)
	vbox.add_child(_body)
	# Discovery choice surface
	var disc_title := Label.new()
	disc_title.text = "Unresolved discoveries"
	disc_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(disc_title)
	_discovery_box = VBoxContainer.new()
	_discovery_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_discovery_box)
	var choice_title := Label.new()
	choice_title.text = "Choices (select discovery first)"
	vbox.add_child(choice_title)
	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_choice_box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = ""
	vbox.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(row)
	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.pressed.connect(refresh_board)
	row.add_child(_refresh_btn)
	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.pressed.connect(hide)
	row.add_child(_close_btn)


func _on_layer_pressed(layer_id: String) -> void:
	if typeof(SpaceLayerManager) == TYPE_NIL:
		return
	if SpaceLayerManager.has_method("set_view_layer"):
		SpaceLayerManager.set_view_layer(layer_id)
	refresh_board()


func refresh_board() -> void:
	_resolve_player()
	if _title:
		_title.text = "Space Layer — %s" % _player_tag
	if typeof(SpaceLayerManager) == TYPE_NIL or not SpaceLayerManager.has_method("build_space_layer_ui_board"):
		if _body:
			_body.text = "[i]SpaceLayerManager board unavailable.[/i]"
		return
	var board: Dictionary = SpaceLayerManager.build_space_layer_ui_board(_player_tag)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b]" % str(board.get("plain", "")))
	lines.append("")
	var strips: Array = board.get("strips", []) as Array if board.get("strips") is Array else []
	for s in strips:
		lines.append("• %s" % str(s))
	var fog: Dictionary = board.get("fog", {}) if board.get("fog") is Dictionary else {}
	lines.append("")
	lines.append("[b]Layers[/b] (view: %s)" % str(board.get("view_layer", "")))
	for row in fog.get("layers", []):
		if not (row is Dictionary):
			continue
		var L: Dictionary = row as Dictionary
		var state := "open" if bool(L.get("unlocked", false)) else ("fog" if bool(L.get("fogged", false)) else "?")
		lines.append("  %s — %s" % [str(L.get("id", "")), state])
	if _body:
		_body.text = "\n".join(lines)
	_rebuild_discovery_list()
	_rebuild_choice_buttons()


func _clear_box(box: VBoxContainer) -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _rebuild_discovery_list() -> void:
	_clear_box(_discovery_box)
	if typeof(SpaceLayerManager) == TYPE_NIL or not SpaceLayerManager.has_method("list_unresolved_discoveries"):
		var lab := Label.new()
		lab.text = "(discovery API unavailable)"
		_discovery_box.add_child(lab)
		return
	var unresolved: Array = SpaceLayerManager.list_unresolved_discoveries(_player_tag)
	if unresolved.is_empty():
		var empty := Label.new()
		empty.text = "No unresolved discoveries."
		_discovery_box.add_child(empty)
		return
	for d in unresolved:
		if not (d is Dictionary):
			continue
		var row: Dictionary = d as Dictionary
		var did := str(row.get("discovery_id", ""))
		var b := Button.new()
		b.text = "%s · %s @ %s" % [did, str(row.get("class_id", "")), str(row.get("body_id", ""))]
		b.toggle_mode = true
		b.button_pressed = (did == _selected_discovery_id)
		b.pressed.connect(_on_discovery_selected.bind(did))
		_discovery_box.add_child(b)


func _on_discovery_selected(discovery_id: String) -> void:
	_selected_discovery_id = discovery_id
	_rebuild_discovery_list()
	_rebuild_choice_buttons()
	if _status:
		_status.text = "Selected %s" % discovery_id


func _rebuild_choice_buttons() -> void:
	_clear_box(_choice_box)
	if _selected_discovery_id.is_empty():
		var hint := Label.new()
		hint.text = "Select a discovery to show choices."
		_choice_box.add_child(hint)
		return
	if typeof(SpaceLayerManager) == TYPE_NIL or not SpaceLayerManager.has_method("list_discovery_choices"):
		return
	var listed: Dictionary = SpaceLayerManager.list_discovery_choices(_selected_discovery_id)
	if bool(listed.get("resolved", false)):
		var done := Label.new()
		done.text = "Already resolved: %s" % str(listed.get("chosen_id", ""))
		_choice_box.add_child(done)
		return
	var choices: Array = listed.get("choices", []) as Array if listed.get("choices") is Array else []
	for c in choices:
		if not (c is Dictionary):
			continue
		var ch: Dictionary = c as Dictionary
		var cid := str(ch.get("id", ""))
		var btn := Button.new()
		btn.text = str(ch.get("label", cid))
		btn.pressed.connect(_on_choice_pressed.bind(_selected_discovery_id, cid))
		_choice_box.add_child(btn)


func _on_choice_pressed(discovery_id: String, choice_id: String) -> void:
	if typeof(SpaceLayerManager) == TYPE_NIL or not SpaceLayerManager.has_method("resolve_discovery_choice"):
		return
	var res: Dictionary = SpaceLayerManager.resolve_discovery_choice(discovery_id, choice_id, {"silent": false})
	_last_resolve = res.duplicate(true)
	if bool(res.get("ok", false)):
		if _status:
			_status.text = "Resolved %s → %s" % [discovery_id, choice_id]
		_selected_discovery_id = ""
	else:
		if _status:
			_status.text = "Resolve failed: %s" % str(res.get("error", "unknown"))
	refresh_board()


## Dual/live helper: list + resolve path without needing click simulation.
func apply_discovery_choice_from_board(discovery_id: String, choice_id: String, opts: Dictionary = {}) -> Dictionary:
	if typeof(SpaceLayerManager) == TYPE_NIL:
		return {"ok": false, "error": "no_slm"}
	var listed: Dictionary = SpaceLayerManager.list_discovery_choices(discovery_id)
	if not bool(listed.get("ok", false)):
		return {"ok": false, "error": "list_failed", "listed": listed}
	var res: Dictionary = SpaceLayerManager.resolve_discovery_choice(discovery_id, choice_id, opts)
	_last_resolve = res.duplicate(true)
	return {
		"ok": bool(res.get("ok", false)),
		"listed": listed,
		"resolve": res,
		"board_surface": true,
		"ui": "SpaceLayerBoardView",
	}


func get_unresolved_from_board() -> Array:
	if typeof(SpaceLayerManager) == TYPE_NIL or not SpaceLayerManager.has_method("list_unresolved_discoveries"):
		return []
	return SpaceLayerManager.list_unresolved_discoveries(_player_tag)


func show_board(tag: String = "") -> void:
	if not tag.is_empty():
		_player_tag = tag.strip_edges().to_upper()
	popup_centered()
	refresh_board()
