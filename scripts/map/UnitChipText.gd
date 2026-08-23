# scripts/map/UnitChipText.gd
## Map-counter text without Control/Label (800 Labels on 3520 froze F5 GUI pick).
class_name UnitChipText
extends Node2D

var text: String = ""
var font_size: int = 13
var font_color: Color = Color.WHITE
var outline_color: Color = Color(0.04, 0.04, 0.07, 1.0)
var outline_size: int = 4
var align_right: bool = false


func _draw() -> void:
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var pos := Vector2.ZERO
	if align_right:
		pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if outline_size > 0:
		font.draw_string_outline(
			get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline_color
		)
	font.draw_string(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, font_color)
