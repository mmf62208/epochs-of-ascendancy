extends SceneTree

## SHORE-1: land-sea CoastEdge_ ink stays a fixed screen width.
## Loads MapZoomLOD. No TestScenario.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessShore1CoastInkCheck.gd

const LodScript = preload("res://scripts/map/MapZoomLOD.gd")
const LOD_SRC := "res://scripts/map/MapZoomLOD.gd"
const RENDER_SRC := "res://scripts/map/MapRenderer.gd"
const ROAD_SRC := "res://scripts/map/RoadTierVisual.gd"
const HOME_Z := 0.318

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	_run()
	var ok := _failures.is_empty()
	print("EOA_SHORE RESULT=%s" % ("PASS" if ok else "FAIL"))
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("EOA_SHORE FAIL %s" % msg)


func _expect_screen(z: float, tag: String) -> void:
	var world := float(LodScript.coast_border_width_for_zoom(z))
	var screen := world * z
	print("EOA_SHORE %s_z=%.3f world=%.3f screen=%.3f" % [tag, z, world, screen])
	if absf(screen - float(LodScript.COAST_SCREEN_PX)) > 0.02:
		_fail("%s screen width %.3f" % [tag, screen])


func _run() -> void:
	_expect_screen(HOME_Z, "home")
	_expect_screen(0.55, "strategic_ceiling")
	_expect_screen(1.15, "far_road")
	_expect_screen(1.55, "operational_ceiling")
	_expect_screen(2.60, "close")
	var nonfinite := float(LodScript.coast_border_width_for_zoom(INF))
	var clamped := float(LodScript.coast_border_width_for_zoom(0.0))
	print("EOA_SHORE nonfinite_world=%.3f clamped_world=%.3f" % [nonfinite, clamped])
	print("EOA_SHORE screen_px=%.1f" % float(LodScript.COAST_SCREEN_PX))
	if absf(nonfinite - float(LodScript.COAST_SCREEN_PX)) > 0.02:
		_fail("nonfinite zoom did not fall back to 1.0")
	if absf(clamped - float(LodScript.COAST_SCREEN_PX) / 0.04) > 0.02:
		_fail("zero zoom was not clamped")
	if float(LodScript.coast_border_width_for_zoom(HOME_Z)) <= 1.4:
		_fail("home coast is still the old world-unit hairline")
	if absf(float(LodScript.country_border_width(LodScript.Tier.STRATEGIC)) - 4.2) > 0.001:
		_fail("country frontier width changed")
	if LodScript.show_province_internal_borders(LodScript.Tier.STRATEGIC):
		_fail("strategic shows internal borders")
	if LodScript.show_province_internal_borders(LodScript.Tier.OPERATIONAL):
		_fail("operational shows internal borders")
	if not LodScript.show_province_internal_borders(LodScript.Tier.TACTICAL):
		_fail("tactical hides internal borders")
	var lod := FileAccess.get_file_as_string(LOD_SRC)
	if "static func coast_border_width(" in lod:
		_fail("tier coast width is still callable")
	if "const COAST_SCREEN_PX := 4.5" not in lod:
		_fail("coast screen px missing")
	var ren := FileAccess.get_file_as_string(RENDER_SRC)
	if "const COAST_BORDER_COLOR := Color(0.02, 0.04, 0.08, 0.94)" not in ren:
		_fail("coast ink color changed")
	if "coast_border_width(tier)" in ren or "coast_border_width(_map_lod_tier)" in ren:
		_fail("renderer still uses tier coast width")
	if "func _apply_coast_ink_width" not in ren:
		_fail("zoom retint missing")
	if "seg.visible = want_internal" not in ren:
		_fail("ProvEdge_ visibility gate missing")
	if "const PROVINCE_EDGE_PREFIX := \"ProvEdge_\"" not in ren:
		_fail("ProvEdge_ prefix missing")
	var apply_at := ren.find("func _apply_coast_ink_width")
	var next_fn := ren.find("\nfunc ", apply_at + 8)
	var apply := ren.substr(apply_at, next_fn - apply_at) if next_fn > apply_at else ""
	if "_update_country_borders" in apply or "_sync_border_lod" in apply:
		_fail("coast retint rebuilds frontiers")
	var roads := FileAccess.get_file_as_string(ROAD_SRC)
	if "const HIGHWAY_FAR_CASING_SCREEN_PX := 5.5" not in roads:
		_fail("highway far casing changed")
	if "const HIGHWAY_FAR_CORE_SCREEN_PX := 3.2" not in roads:
		_fail("highway far core changed")
	if "const END_LABEL_ZOOM_MIN := 1.50" not in roads or "return zoom >= END_LABEL_ZOOM_MIN" not in roads:
		_fail("city label floor changed")
