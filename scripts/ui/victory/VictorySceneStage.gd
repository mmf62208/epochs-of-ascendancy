# scripts/ui/victory/VictorySceneStage.gd
## Full-viewport host for the winner picture. Buttons sit in viewport space.
class_name VictorySceneStage
extends Control

var layers: VictorySceneLayers
var _buttons: Array[Button] = []
var _primary: Button
var _buttons_live: bool = false
var _fitted: bool = false


func configure(built: Dictionary, buttons: Array) -> void:
	name = "VictorySceneStage"
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var frame := Control.new()
	frame.name = "SceneFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size = Vector2(1280, 800)
	add_child(frame)
	layers = VictorySceneLayers.new()
	layers.name = "VictorySceneLayers"
	frame.add_child(layers)
	layers.configure(built)
	var bar := Control.new()
	bar.name = "ButtonBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	for spec_v in buttons:
		if not (spec_v is Dictionary):
			continue
		var spec: Dictionary = spec_v
		var btn := Button.new()
		btn.name = str(spec.get("name", "Btn"))
		btn.text = str(spec.get("text", ""))
		btn.custom_minimum_size = Vector2(180, 44)
		btn.size = Vector2(180, 44)
		btn.focus_mode = Control.FOCUS_ALL
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.modulate.a = 0.0
		btn.visible = true
		var tip := str(spec.get("tooltip", ""))
		if not tip.is_empty():
			btn.tooltip_text = tip
		if bool(spec.get("primary", false)):
			RetrowaveTheme.style_primary_button(btn)
			_primary = btn
		else:
			RetrowaveTheme.style_secondary_button(btn)
		var cb: Variant = spec.get("cb", null)
		if cb is Callable:
			btn.pressed.connect(cb)
		if not bool(spec.get("visible", true)):
			btn.visible = false
		if bool(spec.get("disabled", false)):
			btn.disabled = true
		bar.add_child(btn)
		_buttons.append(btn)
	if _primary == null and not _buttons.is_empty():
		_primary = _buttons[0]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_frame()


func _process(delta: float) -> void:
	if layers != null:
		layers.tick(delta)
	if not _fitted:
		layout_frame()
	if layers != null and layers.input_live() and not _buttons_live:
		arm_buttons()
	elif not _buttons_live:
		var alpha := 0.0 if layers == null else layers.button_alpha()
		for b in _buttons:
			b.modulate.a = alpha


func layout_frame() -> void:
	var vp := Vector2(1280, 800)
	var known := false
	if is_inside_tree():
		var seen := get_viewport_rect().size
		if seen.x >= 2.0 and seen.y >= 2.0:
			vp = seen
			known = true
	_fitted = known
	position = Vector2.ZERO
	size = vp
	custom_minimum_size = vp
	var frame := get_node_or_null("SceneFrame") as Control
	if frame != null:
		var s := maxf(vp.x / 1280.0, vp.y / 800.0)
		frame.scale = Vector2(s, s)
		frame.position = (vp - Vector2(1280, 800) * s) * 0.5
		frame.size = Vector2(1280, 800)
	_layout_buttons(vp)


func _layout_buttons(vp: Vector2) -> void:
	var bar := get_node_or_null("ButtonBar") as Control
	if bar == null:
		return
	bar.position = Vector2.ZERO
	bar.size = vp
	var x := vp.x - 40.0
	var y := maxf(8.0, vp.y - 40.0 - 44.0)
	for i in range(_buttons.size() - 1, -1, -1):
		var b := _buttons[i]
		b.size = Vector2(180, 44)
		b.position = Vector2(x - 180.0, y)
		x -= 192.0


func consume_skip(event: InputEvent) -> bool:
	if _buttons_live:
		return false
	if not _skip_event(event):
		return false
	skip()
	return true


func skip() -> void:
	if layers != null:
		layers.skip()
	arm_buttons()


func arm_buttons() -> void:
	_buttons_live = true
	for b in _buttons:
		if not b.visible:
			continue
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.modulate.a = 1.0
	if _primary != null and _primary.visible and not _primary.disabled:
		_primary.grab_focus()
	elif not _buttons.is_empty():
		for b in _buttons:
			if b.visible and not b.disabled:
				b.grab_focus()
				return


func _skip_event(event: InputEvent) -> bool:
	if event == null:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		return key.keycode == KEY_SPACE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		return true
	return false
