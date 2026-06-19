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
	if data == null:
		push_warning("Bad proposed_children_geometry.json")
		return
	_children = data.get("proposed_children", data.get("children", []))
	_loaded = true
	print("Loaded ", _children.size(), " proposed children for debug draw (river splits from real rivers.json where river_cross high).")

func _draw():
	if not _loaded or _children.is_empty():
		_load_data()
		if _children.is_empty():
			return
	var count = min(_children.size(), max_to_draw)
	# Draw child polygons (canvas pixel space; scale/offset in parent scene or Camera as needed)
	for i in range(count):
		var c = _children[i]
		var pts = c.get("points", c.get("suggested_points", []))
		if pts.size() < 2:
			continue
		var pv2: PackedVector2Array = PackedVector2Array()
		for p in pts:
			pv2.append(Vector2(p[0] * draw_scale, p[1] * draw_scale))
		# close
		if pv2.size() >= 3:
			pv2.append(pv2[0])
		# color: blue default, green for river_aware (now carried from proposals for 126+ children)
		var col = line_color
		if c.get("river_aware", false):
			col = Color(0.2, 0.9, 0.4, 0.85)  # river-guided natural border highlight
		elif int(c.get("parent_id", 0)) == 82:
			col = Color(0.3, 0.7, 0.95, 0.8)  # fallback for the known river parent
		draw_polyline(pv2, col, 1.5)
		# small center marker + label
		var cx = c.get("suggested_center", c.get("label_anchor"))
		if cx and cx.size() >= 2:
			var cp = Vector2(cx[0] * draw_scale, cx[1] * draw_scale)
			draw_circle(cp, 3.0, col)
			var lbl = str(c.get("parent_id", "?")) + "_c" + str(c.get("child_index", i))
			draw_string(ThemeDB.fallback_font, cp + Vector2(4, -4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_color)
	# Legend / info
	draw_string(ThemeDB.fallback_font, Vector2(10, 20), "Proposed children (phase1): " + str(_children.size()) + "  |  green=river_aware (126 in full 471 set) natural border guided from rivers.json", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1,1,1,0.9))
	draw_string(ThemeDB.fallback_font, Vector2(20, 30), "NATO Symbol Preview + Phase1 Debug (stub)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1,1,1,0.8))
