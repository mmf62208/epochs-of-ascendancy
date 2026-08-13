# scripts/map/FeatureProgressRing.gd
## Pass 16–19: lightweight map glyph progress ring (airfield repair / construction).
## Live-updated from MapRenderer on day tick via set_progress. Pass 18: hover tooltip. Pass 19: click opens site.
extends Node2D

signal ring_clicked(province_id: int)

@export var progress: float = 0.0  # 0–1
@export var radius: float = 11.0
@export var ring_color: Color = Color(0.55, 0.85, 1.0, 0.9)
@export var track_color: Color = Color(0.15, 0.18, 0.22, 0.55)
@export var line_width: float = 2.4
## When true, ring means "repair remaining" (cyan→lime); else construction (amber).
@export var is_repair: bool = true
## Soft pulse on live refresh so day-tick updates are visible.
var _pulse: float = 0.0
var _tooltip_text: String = ""
var _tip_label: Label = null
var _hover: bool = false
var _area: Area2D = null
var province_id: int = -1


func _ready() -> void:
	z_index = 12
	set_process(false)
	_setup_hover_area()
	queue_redraw()


func _setup_hover_area() -> void:
	if _area != null and is_instance_valid(_area):
		return
	_area = Area2D.new()
	_area.name = "RingHoverArea"
	_area.input_pickable = true
	_area.monitoring = true
	_area.monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius + 6.0
	shape.shape = circle
	_area.add_child(shape)
	add_child(_area)
	_area.mouse_entered.connect(_on_mouse_entered)
	_area.mouse_exited.connect(_on_mouse_exited)
	_area.input_event.connect(_on_area_input)


func set_tooltip_text(text: String) -> void:
	_tooltip_text = text.strip_edges()
	if _tip_label != null and is_instance_valid(_tip_label):
		_tip_label.text = _tooltip_text


func set_progress(p: float, repair: bool = true) -> void:
	var np := clampf(p, 0.0, 1.0)
	var changed := absf(np - progress) > 0.01 or repair != is_repair
	progress = np
	is_repair = repair
	if is_repair:
		ring_color = Color(0.45, 0.95, 0.75, 0.92).lerp(Color(0.55, 0.85, 1.0, 0.92), progress)
	else:
		ring_color = Color(0.95, 0.75, 0.35, 0.9)
	if changed:
		_pulse = 1.0
		set_process(true)
	# Refresh default tooltip if none set externally.
	if _tooltip_text.is_empty() or _tooltip_text.begins_with("Airfield"):
		_tooltip_text = _default_tooltip()
		if _tip_label != null and is_instance_valid(_tip_label) and _hover:
			_tip_label.text = _tooltip_text
	queue_redraw()


func _default_tooltip() -> String:
	var pct := int(round(progress * 100.0))
	if is_repair:
		return "Airfield repair · %d%% restored" % pct
	return "Airfield construction · %d%% complete" % pct


func _on_mouse_entered() -> void:
	_hover = true
	_ensure_tip_label()
	if _tip_label != null:
		_tip_label.visible = true
		_tip_label.text = _tooltip_text if not _tooltip_text.is_empty() else _default_tooltip()


func _on_mouse_exited() -> void:
	_hover = false
	if _tip_label != null and is_instance_valid(_tip_label):
		_tip_label.visible = false


## Pass 19: left-click ring → open province/site inspector.
func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			ring_clicked.emit(province_id)
			get_viewport().set_input_as_handled()


func _ensure_tip_label() -> void:
	if _tip_label != null and is_instance_valid(_tip_label):
		return
	_tip_label = Label.new()
	_tip_label.name = "RingTooltip"
	_tip_label.z_index = 50
	_tip_label.position = Vector2(radius + 4.0, -radius - 14.0)
	_tip_label.add_theme_font_size_override("font_size", 11)
	_tip_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.95))
	_tip_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 0.9))
	_tip_label.add_theme_constant_override("outline_size", 3)
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.visible = false
	add_child(_tip_label)


func _process(delta: float) -> void:
	if _pulse <= 0.0:
		if not _hover:
			set_process(false)
		return
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var p := clampf(progress, 0.0, 1.0)
	var r := radius * (1.0 + 0.12 * _pulse)
	var lw := line_width + _pulse * 0.8
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, track_color, lw, true)
	if p < 0.02:
		return
	var start := -PI * 0.5
	var sweep := p * TAU
	var segs := maxi(4, int(28.0 * p))
	var col := ring_color
	if _pulse > 0.0:
		col = col.lightened(0.15 * _pulse)
	draw_arc(Vector2.ZERO, r, start, start + sweep, segs, col, lw + 0.3, true)
	# Leading tip
	var tip := Vector2(cos(start + sweep), sin(start + sweep)) * r
	draw_circle(tip, 1.6 + _pulse * 0.8, col)
