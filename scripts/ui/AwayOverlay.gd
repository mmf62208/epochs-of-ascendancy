# scripts/ui/AwayOverlay.gd
## AUTOSAVE-1 idle overlay. Modal, dulls the map, does not unpause on dismiss.
class_name AwayOverlay
extends CanvasLayer

const OVERLAY_LAYER := 140

var _dim: ColorRect
var _panel: PanelContainer


func _ready() -> void:
	layer = OVERLAY_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.06, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_dim)
	_panel = PanelContainer.new()
	_panel.name = "AwayPanel"
	_panel.custom_minimum_size = Vector2(420, 140)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -210
	_panel.offset_top = -70
	_panel.offset_right = 210
	_panel.offset_bottom = 70
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	var title := Label.new()
	title.name = "AwayTitle"
	title.text = "Away — game paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	var body := Label.new()
	body.name = "AwayBody"
	body.text = "Click or press a key to continue"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
