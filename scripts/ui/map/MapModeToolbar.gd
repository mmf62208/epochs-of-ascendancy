# scripts/ui/map/MapModeToolbar.gd
## Player-facing map mode toolbar (Political, Strain, Vitality, Development, Supply, Loyalty, Infra).
extends PanelContainer

signal mode_changed(mode: String)
signal layout_changed()

const MODES: Array[String] = [
	"political", "strain", "vitality", "development", "supply", "loyalty", "infra"
]

const MODE_LABELS: Dictionary = {
	"political": "Political",
	"strain": "Strain",
	"vitality": "Vitality",
	"development": "Development",
	"supply": "Supply",
	"loyalty": "Loyalty",
	"infra": "Infra",
}

const MODE_HINTS: Dictionary = {
	"political": "Clean country colors (default)",
	"strain": "Welfare / cultural strain (red-gray)",
	"vitality": "Settlement vitality (cyan-green)",
	"development": "Development level lighten",
	"supply": "Supply routes overlay",
	"loyalty": "Foreign military loyalty tint",
	"infra": "Roads, rails, built infrastructure",
}

const COLLAPSED_HEIGHT := 28.0
const EXPANDED_HEIGHT := 56.0

var _map_renderer: Node = null
var _buttons: Dictionary = {}
var _legend: Label = null
var _body: VBoxContainer = null
var _collapse_btn: Button = null
var _current_mode: String = "political"
var _collapsed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func bind_map_renderer(renderer: Node) -> void:
	_map_renderer = renderer
	set_mode("political", false)


func get_panel_height() -> float:
	return COLLAPSED_HEIGHT if _collapsed else EXPANDED_HEIGHT


func _build_ui() -> void:
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	_collapse_btn = Button.new()
	_collapse_btn.text = "▾"
	_collapse_btn.focus_mode = Control.FOCUS_NONE
	_collapse_btn.custom_minimum_size = Vector2(28, 24)
	_collapse_btn.pressed.connect(_toggle_collapsed)
	outer.add_child(_collapse_btn)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	outer.add_child(_body)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	_body.add_child(title_row)

	var title := Label.new()
	title.text = "Map Mode"
	title.add_theme_font_size_override("font_size", 12)
	title_row.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_body.add_child(row)

	for mode in MODES:
		var btn := Button.new()
		btn.text = MODE_LABELS.get(mode, mode.capitalize())
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 26)
		btn.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_on_mode_pressed(mode)
		)
		row.add_child(btn)
		_buttons[mode] = btn

	_legend = Label.new()
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend.add_theme_font_size_override("font_size", 10)
	_legend.modulate = Color(0.85, 0.9, 1.0, 0.85)
	_body.add_child(_legend)
	_update_legend("political")


func _toggle_collapsed() -> void:
	_collapsed = not _collapsed
	if _body:
		_body.visible = not _collapsed
	if _collapse_btn:
		_collapse_btn.text = "▸" if _collapsed else "▾"
	layout_changed.emit()


func _on_mode_pressed(mode: String) -> void:
	set_mode(mode, true)


func set_mode(mode: String, notify_renderer: bool = true) -> void:
	var m := mode.strip_edges().to_lower()
	if not m in MODES:
		m = "political"
	if m == _current_mode and notify_renderer:
		return
	_current_mode = m
	for key in _buttons.keys():
		var btn: Button = _buttons[key]
		btn.button_pressed = (key == m)
	_update_legend(m)
	if notify_renderer and _map_renderer != null and _map_renderer.has_method("set_map_mode"):
		_map_renderer.call("set_map_mode", m)
	mode_changed.emit(m)


func _update_legend(mode: String) -> void:
	if _legend:
		_legend.text = MODE_HINTS.get(mode, "")


func get_current_mode() -> String:
	return _current_mode
