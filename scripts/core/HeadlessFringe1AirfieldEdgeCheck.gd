extends SceneTree

## FRINGE-1: intact airfield sprites have a hard alpha edge, nearest sampling,
## and a non-antialiased close halo. Loads FacilityIconLayer. No TestScenario.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFringe1AirfieldEdgeCheck.gd

const FacilityIconLayerScript = preload("res://scripts/map/FacilityIconLayer.gd")
const LAYER_SRC := "res://scripts/map/FacilityIconLayer.gd"
const SITES_SRC := "res://data/provinces_world_accurate/project_sites.json"
const EXPECT_SEEDS := "710430:1,710434:2,710423:3,710451:4"
const SPINE: Array[int] = [710416, 710417, 710418]

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	_run()
	var ok := _failures.is_empty()
	print("EOA_FRINGE RESULT=%s" % ("PASS" if ok else "FAIL"))
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("EOA_FRINGE FAIL %s" % msg)


func _run() -> void:
	var layer: Node = FacilityIconLayerScript.new()
	root.add_child(layer)
	var src := FileAccess.get_file_as_string(LAYER_SRC)
	var outline_aa := _outline_antialiased(src)
	print("EOA_FRINGE outline_antialiased=%s" % ("true" if outline_aa else "false"))
	if outline_aa:
		_fail("halo outline polyline is antialiased")
	var halo := float(layer.HALO_PX)
	print("EOA_FRINGE halo_px=%d" % int(round(halo)))
	if absf(halo - 2.0) > 0.001:
		_fail("halo px is %s" % halo)
	var sampling := _sampling_name(int(layer.texture_filter))
	print("EOA_FRINGE texture_sampling=%s" % sampling)
	if sampling != "nearest":
		_fail("texture sampling is %s" % sampling)
	_check_sprites(layer)
	_check_seeds()


func _outline_antialiased(src: String) -> bool:
	if src.contains("draw_polyline(pts, color, width, true)"):
		return true
	if not src.contains("const HALO_OUTLINE_ANTIALIASED := false"):
		return true
	if not src.contains("draw_polyline(pts, color, width, HALO_OUTLINE_ANTIALIASED)"):
		return true
	return false


func _sampling_name(filt: int) -> String:
	if filt == CanvasItem.TEXTURE_FILTER_NEAREST:
		return "nearest"
	if filt == CanvasItem.TEXTURE_FILTER_LINEAR:
		return "linear"
	if filt == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		return "linear"
	if filt == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
		return "linear"
	if filt == CanvasItem.TEXTURE_FILTER_PARENT_NODE:
		return "parent"
	if filt == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
		return "nearest_mip"
	if filt == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC:
		return "nearest_mip"
	return "other"


func _check_sprites(layer: Node) -> void:
	for level in [1, 2, 3, 4]:
		for px in [32, 64]:
			var stem := "airfield_l%d_intact" % level
			var path := "%s%s_%d.png" % [layer.FAC_DIR, stem, px]
			var tex: Texture2D = layer._load_tex(stem, px)
			var drawn: Image = null
			if tex != null:
				drawn = tex.get_image()
			var filed := _png_image(path)
			var drawn_stats := _alpha_stats(drawn)
			var file_stats := _alpha_stats(filed)
			var name := "%s_%d" % [stem, px]
			print(
				"EOA_FRINGE sprite=%s opaque=%d partial=%d size=%d"
				% [name, int(drawn_stats["opaque"]), int(drawn_stats["partial"]), int(drawn_stats["size"])]
			)
			if drawn == null or filed == null:
				_fail("%s did not load" % name)
				continue
			if drawn_stats != file_stats:
				_fail("%s drawn alpha disagrees with the png" % name)
			if int(drawn_stats["partial"]) != 0:
				_fail("%s partial=%s" % [name, drawn_stats["partial"]])
			if int(drawn_stats["size"]) != px:
				_fail("%s size=%s" % [name, drawn_stats["size"]])
			if not _opaque_band(px, int(drawn_stats["opaque"])):
				_fail("%s opaque=%s outside band" % [name, drawn_stats["opaque"]])


func _png_image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


func _alpha_stats(img: Image) -> Dictionary:
	var opaque := 0
	var partial := 0
	var size := 0
	if img == null:
		return {"opaque": -1, "partial": -1, "size": 0}
	var w := img.get_width()
	var h := img.get_height()
	size = w if w == h else 0
	for y in h:
		for x in w:
			var a := int(round(img.get_pixel(x, y).a * 255.0))
			if a <= 0:
				continue
			if a >= 250:
				opaque += 1
			else:
				partial += 1
	return {"opaque": opaque, "partial": partial, "size": size}


func _opaque_band(px: int, opaque: int) -> bool:
	if px == 32:
		return opaque >= 150 and opaque <= 900
	if px == 64:
		return opaque >= 700 and opaque <= 3600
	return false


func _check_seeds() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SITES_SRC))
	var parts: PackedStringArray = PackedStringArray()
	var air_pids: Array[int] = []
	if parsed is Dictionary:
		var sites: Variant = (parsed as Dictionary).get("sites", [])
		if sites is Array:
			for item in sites:
				if not (item is Dictionary):
					continue
				var rec: Dictionary = item
				var kind := str(rec.get("project_type", rec.get("site_id", ""))).to_lower()
				if not kind.begins_with("airfield"):
					continue
				var pid := int(rec.get("province_id", 0))
				var tier := int(rec.get("tier", 0))
				parts.append("%d:%d" % [pid, tier])
				air_pids.append(pid)
	var got := ",".join(parts)
	print("EOA_FRINGE seeds=%s" % got)
	if got != EXPECT_SEEDS:
		_fail("seeds %s" % got)
	for pid in SPINE:
		if air_pids.has(pid):
			_fail("spine pid %d is an airfield" % pid)
	print("EOA_FRINGE not_airfields=710416,710417,710418")
