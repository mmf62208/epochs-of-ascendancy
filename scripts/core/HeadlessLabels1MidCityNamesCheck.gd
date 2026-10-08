extends SceneTree

## LABELS-1: Bonn / Köln / Leverkusen names follow the mid road band.
## Calls the shipped gate the gold-spine overlay already uses
## (end_labels_visible_for_span). Fails on the old 1.50 floor.
## Does not boot a second label path. Never EOA_SKIP_TITLE.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessLabels1MidCityNamesCheck.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")

const HOME_Z := 0.318
const MID_Z := 1.20
const OVERLAY := "res://scripts/map/InfrastructureOverlayLayer.gd"

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var ceiling: float = float(RoadTierVisualScript.ZOOM_FAR_MAX)
	var close_z: float = float(RoadTierVisualScript.ZOOM_CLOSE_MIN)
	var home_on := bool(RoadTierVisualScript.end_labels_visible_for_span(HOME_Z, 40.0))
	var ceiling_on := bool(RoadTierVisualScript.end_labels_visible_for_span(ceiling, 40.0))
	var mid_on := bool(RoadTierVisualScript.end_labels_visible_for_span(MID_Z, 40.0))
	var close_on := bool(RoadTierVisualScript.end_labels_visible_for_span(close_z, 40.0))
	var bonn := int(RoadTierVisualScript.BONN_ID)
	var koeln := int(RoadTierVisualScript.KOELN_ID)
	var lev := int(RoadTierVisualScript.LEVERKUSEN_ID)
	print("EOA_LABELS home_z=%.3f visible=%s" % [HOME_Z, str(home_on)])
	print("EOA_LABELS ceiling_z=%.3f visible=%s" % [ceiling, str(ceiling_on)])
	print("EOA_LABELS mid_z=%.3f visible=%s" % [MID_Z, str(mid_on)])
	print("EOA_LABELS close_z=%.3f visible=%s" % [close_z, str(close_on)])
	print("EOA_LABELS ids=%d,%d,%d" % [bonn, koeln, lev])
	if home_on:
		_fail("home_visible")
	if ceiling_on:
		_fail("ceiling_visible")
	if not mid_on:
		_fail("mid_hidden")
	if MID_Z >= 1.50 or MID_Z <= ceiling:
		_fail("mid_zoom_not_inside_band")
	if not close_on:
		_fail("close_hidden")
	if close_z < ceiling:
		_fail("close_zoom")
	if bonn != 710416 or koeln != 710417 or lev != 710418:
		_fail("ids_%d_%d_%d" % [bonn, koeln, lev])
	_assert_overlay_uses_gate()
	var ok := _failures.is_empty()
	print(
		"HeadlessLabels1MidCityNamesCheck: RESULT=%s reasons=%s"
		% ["PASS" if ok else "FAIL", str(_failures)]
	)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _assert_overlay_uses_gate() -> void:
	var src := FileAccess.get_file_as_string(OVERLAY)
	if src.is_empty():
		_fail("overlay_missing")
		return
	var sync_at := src.find("func _sync_end_labels")
	if sync_at < 0:
		_fail("no_sync_end_labels")
		return
	var sync := src.substr(sync_at, 900)
	if not sync.contains("end_labels_visible_for_span"):
		_fail("overlay_skips_gate")
	if sync.contains("END_LABEL_ZOOM_MIN") or sync.contains("zoom >= 1.50"):
		_fail("overlay_second_zoom_path")
	if not src.contains('_make_end_label("Bonn")'):
		_fail("missing_bonn_label")
	if not src.contains('_make_end_label("Köln")'):
		_fail("missing_koln_label")
	if not src.contains('_make_end_label("Leverkusen")'):
		_fail("missing_lev_label")
	if not src.contains("710416") or not src.contains("710417") or not src.contains("710418"):
		_fail("overlay_missing_ids")


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("EOA_LABELS FAIL %s" % msg)
