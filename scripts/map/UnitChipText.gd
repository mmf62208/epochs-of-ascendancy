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
var align_center: bool = false


func _draw() -> void:
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var lines: PackedStringArray = text.split("\n")
	var line_h: float = float(font_size) + 1.0
	var y: float = 0.0
	for line in lines:
		var pos := Vector2(0.0, y)
		var w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if align_center:
			pos.x -= w * 0.5
		elif align_right:
			pos.x -= w
		if outline_size > 0:
			font.draw_string_outline(
				get_canvas_item(), pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline_color
			)
		font.draw_string(get_canvas_item(), pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, font_color)
		y += line_h
