# scripts/map/MapPoliticalLabelsLayer.gd
## Nation + strategic-region name labels (Vic3/EU4/HOI4-style zoom LOD).
class_name MapPoliticalLabelsLayer
extends Node2D

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")

var _nation_labels: Dictionary = {}  # tag -> Label
var _region_labels: Dictionary = {}  # region_id -> Label
var _built: bool = false
var _current_tier: int = 0  # MapZoomLOD.Tier.STRATEGIC
var _hover_region_id: int = -1


func _ready() -> void:
	z_index = 12
	set_process(false)


func rebuild_from_map_data(province_centroids: Dictionary, provinces: Dictionary) -> void:
	_clear_labels()
	if typeof(MapManager) == TYPE_NIL:
		return
	_build_nation_labels(province_centroids, provinces)
	_build_region_labels(province_centroids)
	_built = true
	_apply_tier_visibility(_current_tier)


func sync_tier(tier: int) -> void:
	if tier == _current_tier and _built:
		_apply_region_label_visibility()
		return
	_current_tier = tier
	if not _built:
		return
	_apply_tier_visibility(tier)


func set_hovered_region(region_id: int, tier: int = -1) -> void:
	if tier >= 0:
		_current_tier = tier
	_hover_region_id = region_id
	if not _built:
		return
	_apply_region_label_visibility()


func _clear_labels() -> void:
	for lbl in _nation_labels.values():
		if lbl is Node:
			(lbl as Node).queue_free()
	for lbl in _region_labels.values():
		if lbl is Node:
			(lbl as Node).queue_free()
	_nation_labels.clear()
	_region_labels.clear()
	_built = false


func _build_nation_labels(province_centroids: Dictionary, provinces: Dictionary) -> void:
	var by_tag: Dictionary = {}  # tag -> {sum, count, color}
	for pid_var in province_centroids.keys():
		var pid := int(pid_var)
		if not provinces.has(pid):
			continue
		var prov: Province = provinces[pid]
		if prov == null or prov.is_sea:
			continue
		var tag := prov.owner_tag.strip_edges().to_upper()
		if tag.is_empty():
			continue
		var c: Vector2 = province_centroids[pid]
		if not by_tag.has(tag):
			var col := Color(0.85, 0.88, 0.95, 0.95)
			if MapManager.has_method("get_country_color"):
				col = MapManager.get_country_color(tag)
			by_tag[tag] = {"sum": Vector2.ZERO, "count": 0, "color": col, "name": tag}
		var entry: Dictionary = by_tag[tag]
		entry["sum"] = (entry["sum"] as Vector2) + c
		entry["count"] = int(entry["count"]) + 1
		if MapManager.has_method("get_country"):
			var country = MapManager.get_country(tag)
			if country != null:
				if country is Dictionary and country.has("name"):
					entry["name"] = str(country["name"])
				elif country is Object and country.has_method("get"):
					var nm: Variant = country.get("name")
					if nm != null and str(nm) != "":
						entry["name"] = str(nm)

	for tag_var in by_tag.keys():
		var tag := str(tag_var)
		var e: Dictionary = by_tag[tag]
		var n := int(e["count"])
		if n <= 0:
			continue
		var center := (e["sum"] as Vector2) / float(n)
		var lbl := _make_label(str(e["name"]), center, 22, e["color"] as Color)
		lbl.name = "NationLabel_%s" % tag
		add_child(lbl)
		_nation_labels[tag] = lbl


func _build_region_labels(province_centroids: Dictionary) -> void:
	if not MapManager.has_method("get_all_strategic_regions"):
		return
	var regions: Dictionary = MapManager.get_all_strategic_regions()
	for rid_var in regions.keys():
		var rid := int(rid_var)
		var reg: Dictionary = regions[rid_var]
		if reg.is_empty():
			continue
		var pids: Array = reg.get("province_ids", [])
		var sum := Vector2.ZERO
		var count := 0
		for pid_var in pids:
			var pid := int(pid_var)
			if not province_centroids.has(pid):
				continue
			sum += province_centroids[pid] as Vector2
			count += 1
		if count <= 0:
			continue
		var center := sum / float(count)
		var rname := str(reg.get("name", MapManager.get_strategic_region_name(rid)))
		var lbl := _make_label(rname, center, 16, Color(0.78, 0.82, 0.92, 0.9))
		lbl.name = "RegionLabel_%d" % rid
		add_child(lbl)
		_region_labels[rid] = lbl


func _make_label(text: String, pos: Vector2, font_px: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_px)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.1, 0.92))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.z_index = 12
	return lbl


func _apply_tier_visibility(tier: int) -> void:
	var show_n: bool = MapZoomLODScript.show_nation_labels(tier)
	var show_r: bool = MapZoomLODScript.show_region_labels(tier)
	for lbl in _nation_labels.values():
		if lbl is Label:
			var l := lbl as Label
			l.visible = show_n
			if show_n:
				var c := l.get_theme_color("font_color")
				c.a = MapZoomLODScript.label_alpha_for_tier(tier, "nation")
				l.add_theme_color_override("font_color", c)
	_apply_region_label_visibility(show_r)


func _apply_region_label_visibility(force_show_tier: bool = false) -> void:
	var show_r: bool = force_show_tier or MapZoomLODScript.show_region_labels(_current_tier)
	for rid_var in _region_labels.keys():
		var rid := int(rid_var)
		var lbl: Variant = _region_labels[rid_var]
		if not (lbl is Label):
			continue
		var l := lbl as Label
		var active := show_r and _hover_region_id >= 0 and rid == _hover_region_id
		l.visible = active
		if active:
			var c2 := l.get_theme_color("font_color")
			c2.a = MapZoomLODScript.label_alpha_for_tier(_current_tier, "region")
			l.add_theme_color_override("font_color", c2)
