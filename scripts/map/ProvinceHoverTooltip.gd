class_name ProvinceHoverTooltip
extends PanelContainer

## Floating multiline province tooltip for map hover (BBCode for retrowave accents).

# Compact hover card (~½ prior size) — short province glance, not full inspector.
@export var max_width: float = 190.0
@export var max_height: float = 190.0
@export var font_size: int = 11

var _rich: RichTextLabel
var _panel_style: StyleBoxFlat
var _supply_accent: bool = false
var _compare_accent: bool = false
var _selected_accent: bool = false
var _candidate_accent: bool = false
var _conflict_accent: bool = false
var _agent_accent: bool = false
var _tech_accent: bool = false
var _support_accent: bool = false
var _engineer_accent: bool = false
var _engineers_needed_accent: bool = false
var _agent_activity_accent: bool = false
var _agent_pressure_kind: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 200
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	add_child(margin)

	_rich = RichTextLabel.new()
	_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rich.bbcode_enabled = true
	_rich.fit_content = true
	_rich.scroll_active = true
	_rich.custom_minimum_size = Vector2(max_width - 12.0, 0)
	_rich.add_theme_font_size_override("normal_font_size", font_size)
	_rich.meta_clicked.connect(_on_meta_clicked)
	_rich.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(_rich)

	_panel_style = StyleBoxFlat.new()
	_apply_panel_style()
	add_theme_stylebox_override("panel", _panel_style)


func set_supply_accent(active: bool) -> void:
	if _supply_accent == active:
		return
	_supply_accent = active
	_apply_panel_style()


func set_compare_accent(active: bool) -> void:
	if _compare_accent == active:
		return
	_compare_accent = active
	_apply_panel_style()


func set_selected_accent(active: bool) -> void:
	if _selected_accent == active:
		return
	_selected_accent = active
	_apply_panel_style()


func set_candidate_accent(active: bool) -> void:
	if _candidate_accent == active:
		return
	_candidate_accent = active
	_apply_panel_style()


func set_conflict_accent(active: bool) -> void:
	if _conflict_accent == active:
		return
	_conflict_accent = active
	_apply_panel_style()


func set_agent_accent(active: bool) -> void:
	if _agent_accent == active:
		return
	_agent_accent = active
	_apply_panel_style()


func set_tech_accent(active: bool) -> void:
	if _tech_accent == active:
		return
	_tech_accent = active
	_apply_panel_style()


func set_support_accent(active: bool) -> void:
	if _support_accent == active:
		return
	_support_accent = active
	_apply_panel_style()


func set_engineer_accent(active: bool) -> void:
	if _engineer_accent == active:
		return
	_engineer_accent = active
	_apply_panel_style()


func set_engineers_needed_accent(active: bool) -> void:
	if _engineers_needed_accent == active:
		return
	_engineers_needed_accent = active
	_apply_panel_style()


func set_agent_activity_accent(active: bool) -> void:
	if _agent_activity_accent == active:
		return
	_agent_activity_accent = active
	_apply_panel_style()


func set_agent_pressure_kind(kind: String) -> void:
	var k := kind.strip_edges()
	if _agent_pressure_kind == k:
		return
	_agent_pressure_kind = k
	_apply_panel_style()


func _apply_panel_style() -> void:
	if _panel_style == null:
		_panel_style = StyleBoxFlat.new()
	if _compare_accent and _selected_accent:
		_panel_style.bg_color = Color(0.15, 0.1, 0.1, 0.96)
	elif _compare_accent:
		_panel_style.bg_color = Color(0.14, 0.11, 0.08, 0.96)
	elif _candidate_accent:
		_panel_style.bg_color = Color(0.12, 0.1, 0.08, 0.95)
	elif _conflict_accent and _agent_accent and _supply_accent:
		_panel_style.bg_color = Color(0.1, 0.12, 0.14, 0.96)
	elif _conflict_accent and _agent_accent:
		_panel_style.bg_color = Color(0.12, 0.08, 0.14, 0.96)
	elif _conflict_accent:
		_panel_style.bg_color = Color(0.14, 0.08, 0.09, 0.95)
	elif _agent_accent:
		_panel_style.bg_color = Color(0.1, 0.09, 0.16, 0.95)
	elif _engineers_needed_accent and _supply_accent:
		_panel_style.bg_color = Color(0.12, 0.09, 0.08, 0.96)
	elif _engineer_accent and (_supply_accent or _agent_accent):
		_panel_style.bg_color = Color(0.07, 0.12, 0.16, 0.96)
	elif _engineer_accent:
		_panel_style.bg_color = Color(0.06, 0.14, 0.14, 0.95)
	elif _tech_accent or _support_accent:
		_panel_style.bg_color = Color(0.08, 0.11, 0.18, 0.95)
	elif _selected_accent:
		_panel_style.bg_color = Color(0.12, 0.09, 0.14, 0.95)
	else:
		_panel_style.bg_color = Color(0.08, 0.1, 0.16, 0.94)
	if _compare_accent:
		_panel_style.border_color = Color(1.0, 0.72, 0.35, 0.95)
		_panel_style.shadow_color = Color(0.55, 0.35, 0.12, 0.4)
	elif _candidate_accent:
		_panel_style.border_color = Color(1.0, 0.65, 0.32, 0.82)
		_panel_style.shadow_color = Color(0.45, 0.28, 0.1, 0.32)
	elif _selected_accent and _conflict_accent and _agent_accent and _supply_accent:
		_panel_style.border_color = Color(0.98, 0.42, 0.88).lerp(Color(0.45, 0.88, 0.78), 0.45)
		_panel_style.shadow_color = Color(0.4, 0.2, 0.35, 0.38)
	elif _selected_accent and _conflict_accent and _agent_accent and _supply_accent and _support_accent:
		_panel_style.border_color = Color(0.98, 0.5, 0.82, 0.96).lerp(Color(0.45, 0.88, 0.78), 0.42)
		_panel_style.shadow_color = Color(0.4, 0.22, 0.38, 0.4)
	elif _selected_accent and _conflict_accent and _agent_accent and _support_accent:
		_panel_style.border_color = Color(0.98, 0.5, 0.82, 0.96).lerp(Color(0.4, 0.85, 1.0, 0.28), 0.35)
		_panel_style.shadow_color = Color(0.45, 0.15, 0.35, 0.38)
	elif _selected_accent and _conflict_accent and _agent_accent:
		_panel_style.border_color = Color(0.98, 0.5, 0.82, 0.96)
		_panel_style.shadow_color = Color(0.45, 0.15, 0.35, 0.38)
	elif _conflict_accent and _agent_accent and _supply_accent and _agent_pressure_kind == "disrupt":
		_panel_style.border_color = Color(0.45, 0.88, 0.78).lerp(Color(1.0, 0.58, 0.32), 0.5)
		_panel_style.shadow_color = Color(0.25, 0.35, 0.15, 0.38)
	elif _conflict_accent and _agent_accent and _supply_accent and _agent_pressure_kind == "sabotage":
		_panel_style.border_color = Color(0.45, 0.88, 0.78).lerp(Color(1.0, 0.42, 0.48), 0.48)
		_panel_style.shadow_color = Color(0.2, 0.32, 0.18, 0.38)
	elif _conflict_accent and _agent_accent and _supply_accent and _support_accent:
		_panel_style.border_color = Color(0.5, 0.82, 0.95).lerp(Color(0.95, 0.5, 0.78), 0.35)
		_panel_style.shadow_color = Color(0.2, 0.35, 0.45, 0.38)
	elif _conflict_accent and _agent_accent and _supply_accent:
		_panel_style.border_color = Color(0.45, 0.88, 0.78).lerp(Color(0.95, 0.5, 0.78), 0.55)
		_panel_style.shadow_color = Color(0.2, 0.35, 0.35, 0.38)
	elif _conflict_accent and _agent_accent and _support_accent:
		_panel_style.border_color = Color(0.95, 0.5, 0.78, 0.94).lerp(Color(0.4, 0.85, 1.0, 0.28), 0.28)
		_panel_style.shadow_color = Color(0.45, 0.18, 0.35, 0.38)
	elif _conflict_accent and _agent_accent and _agent_pressure_kind == "disrupt":
		_panel_style.border_color = Color(0.98, 0.58, 0.32, 0.96).lerp(Color(0.95, 0.5, 0.78), 0.35)
		_panel_style.shadow_color = Color(0.55, 0.28, 0.15, 0.4)
	elif _conflict_accent and _agent_accent and _agent_pressure_kind == "sabotage":
		_panel_style.border_color = Color(1.0, 0.42, 0.48, 0.96).lerp(Color(0.95, 0.5, 0.78), 0.35)
		_panel_style.shadow_color = Color(0.55, 0.15, 0.2, 0.4)
	elif _conflict_accent and _agent_accent:
		_panel_style.border_color = Color(0.95, 0.5, 0.78, 0.94)
		_panel_style.shadow_color = Color(0.45, 0.18, 0.35, 0.38)
	elif _conflict_accent:
		_panel_style.border_color = Color(1.0, 0.48, 0.48, 0.9)
		_panel_style.shadow_color = Color(0.5, 0.15, 0.15, 0.35)
	elif _agent_accent and _supply_accent and _agent_pressure_kind == "disrupt":
		_panel_style.border_color = Color(0.35, 0.95, 0.72).lerp(Color(1.0, 0.62, 0.32), 0.45)
		_panel_style.shadow_color = Color(0.2, 0.4, 0.15, 0.36)
	elif _agent_accent and _supply_accent and _agent_pressure_kind == "sabotage":
		_panel_style.border_color = Color(0.35, 0.95, 0.72).lerp(Color(1.0, 0.45, 0.5), 0.42)
		_panel_style.shadow_color = Color(0.18, 0.38, 0.18, 0.36)
	elif _agent_accent and _agent_activity_accent and _agent_pressure_kind == "disrupt":
		_panel_style.border_color = Color(1.0, 0.62, 0.32, 0.98)
		_panel_style.shadow_color = Color(0.55, 0.32, 0.12, 0.42)
	elif _agent_accent and _agent_activity_accent and _agent_pressure_kind == "sabotage":
		_panel_style.border_color = Color(1.0, 0.45, 0.5, 0.98)
		_panel_style.shadow_color = Color(0.55, 0.15, 0.22, 0.42)
	elif _agent_accent and _agent_activity_accent:
		_panel_style.border_color = Color(0.85, 0.62, 1.0, 0.98)
		_panel_style.shadow_color = Color(0.45, 0.28, 0.65, 0.42)
	elif _agent_accent:
		_panel_style.border_color = Color(0.72, 0.52, 1.0, 0.92)
		_panel_style.shadow_color = Color(0.35, 0.2, 0.55, 0.38)
	elif _support_accent and (_conflict_accent or _agent_accent or _supply_accent):
		_panel_style.border_color = Color(0.4, 0.85, 1.0, 0.92)
		_panel_style.shadow_color = Color(0.15, 0.32, 0.5, 0.36)
	elif _engineers_needed_accent and _supply_accent:
		_panel_style.border_color = Color(1.0, 0.68, 0.28, 0.96).lerp(Color(0.4, 0.92, 0.82, 0.35), 0.25)
		_panel_style.shadow_color = Color(0.55, 0.32, 0.08, 0.42)
	elif _engineer_accent and _supply_accent and _agent_pressure_kind == "repair":
		_panel_style.border_color = Color(0.35, 0.95, 0.78, 0.96).lerp(Color(0.5, 0.88, 1.0, 0.35), 0.35)
		_panel_style.shadow_color = Color(0.12, 0.42, 0.38, 0.4)
	elif _engineer_accent and _supply_accent:
		_panel_style.border_color = Color(0.4, 0.92, 0.82, 0.94)
		_panel_style.shadow_color = Color(0.14, 0.38, 0.35, 0.38)
	elif _engineer_accent:
		_panel_style.border_color = Color(0.45, 0.98, 0.82, 0.92)
		_panel_style.shadow_color = Color(0.15, 0.45, 0.35, 0.36)
	elif _support_accent and _tech_accent:
		_panel_style.border_color = Color(0.5, 0.9, 1.0, 0.96)
		_panel_style.shadow_color = Color(0.18, 0.38, 0.55, 0.4)
	elif _tech_accent:
		_panel_style.border_color = Color(0.45, 0.82, 1.0, 0.9)
		_panel_style.shadow_color = Color(0.15, 0.35, 0.55, 0.35)
	elif _selected_accent:
		_panel_style.border_color = Color(0.98, 0.42, 0.88, 0.98)
		_panel_style.shadow_color = Color(0.45, 0.12, 0.38, 0.38)
	elif _supply_accent and _agent_pressure_kind == "disrupt":
		_panel_style.border_color = Color(1.0, 0.58, 0.22, 0.96)
		_panel_style.shadow_color = Color(0.55, 0.28, 0.08, 0.4)
	elif _supply_accent and _agent_pressure_kind == "sabotage":
		_panel_style.border_color = Color(1.0, 0.42, 0.45, 0.96)
		_panel_style.shadow_color = Color(0.55, 0.15, 0.2, 0.4)
	elif _supply_accent and _agent_pressure_kind == "repair":
		_panel_style.border_color = Color(0.35, 0.92, 0.72, 0.96)
		_panel_style.shadow_color = Color(0.15, 0.45, 0.35, 0.38)
	elif _supply_accent and _agent_pressure_kind == "stalemate":
		_panel_style.border_color = Color(1.0, 0.55, 0.35, 0.94).lerp(Color(0.35, 0.92, 0.72, 0.96), 0.45)
		_panel_style.shadow_color = Color(0.4, 0.28, 0.18, 0.36)
	elif _supply_accent and _agent_pressure_kind == "depot":
		_panel_style.border_color = Color(1.0, 0.72, 0.28, 0.94)
		_panel_style.shadow_color = Color(0.5, 0.35, 0.1, 0.38)
	elif _conflict_accent and _supply_accent and _agent_pressure_kind == "repair":
		_panel_style.border_color = Color(1.0, 0.48, 0.48, 0.9).lerp(Color(0.35, 0.92, 0.72, 0.96), 0.45)
		_panel_style.shadow_color = Color(0.35, 0.2, 0.25, 0.36)
	elif _agent_accent and _supply_accent and _support_accent and _agent_pressure_kind == "disrupt":
		_panel_style.border_color = Color(1.0, 0.58, 0.22, 0.94).lerp(Color(0.4, 0.85, 1.0, 0.35), 0.38)
		_panel_style.shadow_color = Color(0.45, 0.28, 0.12, 0.38)
	elif _agent_accent and _supply_accent and _support_accent:
		_panel_style.border_color = Color(0.4, 0.85, 1.0, 0.9).lerp(Color(0.35, 0.95, 0.72, 0.35), 0.4)
		_panel_style.shadow_color = Color(0.15, 0.32, 0.45, 0.36)
	elif _supply_accent and _support_accent and _agent_pressure_kind == "repair":
		_panel_style.border_color = Color(0.35, 0.92, 0.72, 0.94).lerp(Color(0.42, 0.82, 1.0, 0.35), 0.4)
		_panel_style.shadow_color = Color(0.15, 0.42, 0.45, 0.36)
	elif _supply_accent and _support_accent:
		_panel_style.border_color = Color(0.35, 0.92, 0.72, 0.92).lerp(Color(0.4, 0.85, 1.0, 0.35), 0.35)
		_panel_style.shadow_color = Color(0.15, 0.38, 0.42, 0.36)
	elif _supply_accent:
		_panel_style.border_color = Color(0.35, 0.95, 0.72, 0.95)
		_panel_style.shadow_color = Color(0.15, 0.45, 0.35, 0.35)
	else:
		_panel_style.border_color = Color(0.35, 0.55, 0.85, 0.9)
		_panel_style.shadow_color = Color(0, 0, 0, 0.45)
	var border_w := 2
	if _compare_accent:
		border_w = 3
	elif _candidate_accent:
		border_w = 2
	elif (_conflict_accent and _agent_accent) or (_selected_accent and _conflict_accent and _agent_accent):
		border_w = 3
	elif _conflict_accent or _agent_accent or _tech_accent or _support_accent or _engineer_accent or _engineers_needed_accent:
		border_w = 2
	elif _selected_accent:
		border_w = 2
	_panel_style.set_border_width_all(border_w)
	_panel_style.set_corner_radius_all(4)
	_panel_style.shadow_size = 4


func show_text(
	text: String,
	screen_pos: Vector2,
	viewport_size: Vector2,
	use_bbcode: bool = true,
	supply_overlay_active: bool = false,
	compare_active: bool = false,
	selected_accent: bool = false,
	candidate_accent: bool = false,
	conflict_accent: bool = false,
	agent_accent: bool = false,
	tech_accent: bool = false,
	support_accent: bool = false,
	engineer_accent: bool = false,
	engineers_needed_accent: bool = false,
	dual_situation_accent: bool = false,
	agent_activity_accent: bool = false,
	agent_pressure_kind: String = "",
) -> void:
	var dual := dual_situation_accent and not compare_active and not candidate_accent
	set_supply_accent(supply_overlay_active and not compare_active and not candidate_accent)
	set_compare_accent(compare_active)
	set_selected_accent(selected_accent and not compare_active)
	set_candidate_accent(candidate_accent and not compare_active)
	set_conflict_accent(
		(conflict_accent or dual) and not compare_active and not candidate_accent
	)
	set_agent_accent((agent_accent or dual) and not compare_active and not candidate_accent)
	var pressure_kind := agent_pressure_kind.strip_edges()
	set_agent_pressure_kind(pressure_kind if not compare_active and not candidate_accent else "")
	set_agent_activity_accent(
		(agent_activity_accent or not pressure_kind.is_empty())
		and not compare_active
		and not candidate_accent
	)
	set_tech_accent(tech_accent and not compare_active and not candidate_accent)
	set_support_accent(support_accent and not compare_active and not candidate_accent)
	set_engineer_accent(engineer_accent and not compare_active and not candidate_accent)
	set_engineers_needed_accent(engineers_needed_accent and not compare_active and not candidate_accent)
	if use_bbcode:
		_rich.bbcode_enabled = true
		_rich.text = text
	else:
		_rich.bbcode_enabled = false
		_rich.text = text

	visible = not text.is_empty()
	if not visible:
		return

	var inner_w := maxf(max_width - 12.0, 80.0)
	_rich.fit_content = true
	_rich.scroll_active = false
	_rich.custom_minimum_size = Vector2(inner_w, 0)
	_rich.reset_size()
	reset_size()
	var size := get_minimum_size()
	if size.y > max_height:
		_rich.fit_content = false
		_rich.custom_minimum_size = Vector2(inner_w, max_height - 12.0)
		_rich.scroll_active = true
		reset_size()
		size = get_minimum_size()
	# Cap reported size so positioning never assumes a huge card.
	size.x = minf(size.x, max_width)
	size.y = minf(size.y, max_height)
	var pos := screen_pos + Vector2(12, 10)
	if pos.x + size.x > viewport_size.x - 8.0:
		pos.x = viewport_size.x - size.x - 8.0
	if pos.y + size.y > viewport_size.y - 8.0:
		pos.y = screen_pos.y - size.y - 12.0
	position = pos


func _on_meta_clicked(meta: Variant) -> void:
	var key := str(meta).strip_edges()
	if not key.begins_with("focus_province:"):
		return
	var pid := int(key.substr("focus_province:".length()))
	if pid < 0 or typeof(MapTechnologyContext) == TYPE_NIL:
		return
	MapTechnologyContext.focus_province_on_map(pid)


func hide_tooltip() -> void:
	visible = false
