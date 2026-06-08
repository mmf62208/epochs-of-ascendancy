# debug_proposed_children.gd
# Stub for IconPreviewTest / DebugDrawer to avoid load errors.
# Original draws proposed child polygons from JSON for map gen QC.

extends Node2D

@export var json_path: String = "res://tools/map_generation/output/phase1_europe/proposed_children_geometry.json"
@export var draw_scale: float = 1.0
@export var line_color: Color = Color(0.2, 0.8, 1.0, 0.7)
@export var label_color: Color = Color(1, 1, 0.2, 0.9)
@export var max_to_draw: int = 60

var _children: Array = []
var _loaded: bool = false

func _ready():
	_load_data()

func _load_data():
	if _loaded:
		return
	if not FileAccess.file_exists(json_path):
		push_warning("Could not load proposed children JSON: " + json_path)
		return
	var f = FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		push_warning("Could not load proposed children JSON: " + json_path)
		return
	var txt = f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if data == null or not data.has("proposed_children"):
		push_warning("Bad or empty proposed_children_geometry.json")
		return
	_children = data["proposed_children"]
	_loaded = true
	print("Loaded ", _children.size(), " proposed children for debug draw (stub).")

func _draw():
	if not _loaded or _children.is_empty():
		_load_data()
		if _children.is_empty():
			return
	# Minimal draw to avoid errors; full impl in original
	var count = min(_children.size(), max_to_draw)
	for i in range(count):
		# stub: just skip complex draw for now
		pass

	# Simple legend
	draw_string(ThemeDB.fallback_font, Vector2(20, 30), "NATO Symbol Preview + Phase1 Debug (stub)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1,1,1,0.8))
