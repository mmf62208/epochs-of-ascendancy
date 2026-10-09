extends SceneTree

## RHINE-1: the drawn Rhine is named above the far zoom ceiling.
## Loads Rx1RhineLayer. No TestScenario.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRhine1RiverNameCheck.gd

const RhineLayerScript = preload("res://scripts/map/Rx1RhineLayer.gd")
const RoadTierScript = preload("res://scripts/map/RoadTierVisual.gd")
const LAYER_SRC := "res://scripts/map/Rx1RhineLayer.gd"
const HOME_Z := 0.318
const MID_Z := 1.20

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	_run()
	var ok := _failures.is_empty()
	print("EOA_RHINE RESULT=%s" % ("PASS" if ok else "FAIL"))
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("EOA_RHINE FAIL %s" % msg)


func _run() -> void:
	var home := bool(RhineLayerScript.rhine_label_visible_at_zoom(HOME_Z))
	var ceiling_z := float(RoadTierScript.ZOOM_FAR_MAX)
	var ceiling := bool(RhineLayerScript.rhine_label_visible_at_zoom(ceiling_z))
	var mid := bool(RhineLayerScript.rhine_label_visible_at_zoom(MID_Z))
	var close_z := float(RoadTierScript.ZOOM_CLOSE_MIN)
	var close := bool(RhineLayerScript.rhine_label_visible_at_zoom(close_z))
	var nonfinite := bool(RhineLayerScript.rhine_label_visible_at_zoom(INF))
	print("EOA_RHINE home_z=%.3f visible=%s" % [HOME_Z, home])
	print("EOA_RHINE ceiling_z=%.3f visible=%s" % [ceiling_z, ceiling])
	print("EOA_RHINE mid_z=%.3f visible=%s" % [MID_Z, mid])
	print("EOA_RHINE close_z=%.3f visible=%s" % [close_z, close])
	print("EOA_RHINE nonfinite=%s" % nonfinite)
	print("EOA_RHINE label=%s along=%.2f" % [RhineLayerScript.RHINE_LABEL, RhineLayerScript.RHINE_LABEL_ALONG])
	print(
		"EOA_RHINE river_px=%d halo_px=%d z=%d"
		% [
			int(RhineLayerScript.RIVER_SCREEN_PX),
			int(RhineLayerScript.HALO_SCREEN_PX),
			int(RhineLayerScript.MAP_BELOW_UNITS_Z),
		]
	)
	if home or ceiling or nonfinite:
		_fail("far band shows the Rhine name")
	if not mid or not close:
		_fail("mid or close hides the Rhine name")
	var src := FileAccess.get_file_as_string(LAYER_SRC)
	var draw_at := src.find("func _draw")
	var fn_at := src.find("static func rhine_label_visible_at_zoom")
	var draw := ""
	if draw_at >= 0 and fn_at > draw_at:
		draw = src.substr(draw_at, fn_at - draw_at)
	if "rhine_label_visible_at_zoom(_canvas_zoom())" not in draw:
		_fail("draw does not ask rhine_label_visible_at_zoom")
	if "_draw_rhine_name(pts)" not in draw:
		_fail("draw does not place the Rhine name")
	if "const RIVER_SCREEN_PX := 7.0" not in src or "const HALO_SCREEN_PX := 14.0" not in src:
		_fail("river width changed")
	if "const MAP_BELOW_UNITS_Z := 22" not in src:
		_fail("river z changed")
