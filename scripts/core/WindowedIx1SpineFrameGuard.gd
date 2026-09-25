extends SceneTree

## WINDOWED Ix-1 spine frame/RSS guard (xvfb). Not the product Play path.
## After a simulated Build Road Spine press, frames must keep advancing and
## RSS must stay under 2 GB for 60 s.
##
##   tools/eoa_ix1_spine_frame_guard.sh
##   xvfb-run -a tools/run_godot.sh -s res://scripts/core/WindowedIx1SpineFrameGuard.gd
##
## Do NOT pass a second --path (tools/run_godot.sh already sets it).

const KOLN := Vector2(4254.322147319904, 944.0958606451493)
const BONN := Vector2(4257.177146765402, 951.4167452117305)
const LEV := Vector2(4254.883084567324, 940.9953109260416)
const RSS_LIMIT_MB := 2048

var _frames: int = 0
var _last_log_sec: int = -1
var _t0_msec: int = 0
var _rss0_mb: int = 0
var _preview: Node2D = null
var _guard_secs: int = 60
var _fail_reason: String = ""


class StubMap extends Node:
	func get_province_centroid(pid: int) -> Vector2:
		match pid:
			710416:
				return Vector2(4257.177146765402, 951.4167452117305)
			710417:
				return Vector2(4254.322147319904, 944.0958606451493)
			710418:
				return Vector2(4254.883084567324, 940.9953109260416)
			_:
				return Vector2.ZERO

	func get_all_provinces() -> Dictionary:
		return {}

	func get_adjacency_system() -> Variant:
		return null

	func get_province(_pid: int) -> Variant:
		return null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	print("WindowedIx1SpineFrameGuard: DisplayServer=", ds)
	if ds == "headless":
		print("EOA_SMOKE_FRAME_GUARD frames=0 rss_mb=0 FAIL")
		print("WindowedIx1SpineFrameGuard: RESULT=FAIL need windowed DisplayServer")
		_flush()
		quit(1)
		return
	var env_secs := OS.get_environment("EOA_FRAME_GUARD_SECS").strip_edges()
	if env_secs.is_valid_int():
		_guard_secs = clampi(int(env_secs), 5, 120)
	var toast := Label.new()
	toast.name = "BuildingToast"
	toast.text = "Building…"
	toast.position = Vector2(16, 16)
	root.add_child(toast)
	var LayerScript: GDScript = load("res://scripts/map/InfrastructureOverlayLayer.gd") as GDScript
	if LayerScript == null:
		print("EOA_SMOKE_FRAME_GUARD frames=0 rss_mb=0 FAIL")
		print("WindowedIx1SpineFrameGuard: RESULT=FAIL overlay script missing")
		_flush()
		quit(1)
		return
	var overlay: Node2D = LayerScript.new() as Node2D
	overlay.name = "Ix1FrameGuardOverlay"
	root.add_child(overlay)
	var stub := StubMap.new()
	stub.name = "StubMap"
	root.add_child(stub)
	overlay.set("map_manager", stub)
	if overlay.has_method("set_ix1_spine_preview"):
		overlay.call("set_ix1_spine_preview", "queued", 710417, 0.0)
	if overlay.has_method("ix1_preview_loop_caps"):
		print("WindowedIx1SpineFrameGuard: caps=", overlay.call("ix1_preview_loop_caps"))
	_preview = overlay.get_node_or_null("Ix1SpinePreview") as Node2D
	# Stress: non-finite / zero-length / one-missing must not spin.
	if _preview != null and _preview.has_method("setup_spine"):
		_preview.call(
			"setup_spine",
			"queued",
			0.0,
			710417,
			{
				710416: BONN,
				710417: KOLN,
				710418: LEV,
			},
		)
		_preview.call(
			"setup_spine",
			"queued",
			0.0,
			710417,
			{
				710416: Vector2(NAN, NAN),
				710417: KOLN,
				710418: KOLN,
			},
		)
		_preview.call(
			"setup_spine",
			"construction",
			35.0,
			710417,
			{
				710416: BONN,
				710417: KOLN,
				710418: LEV,
			},
		)
	_t0_msec = Time.get_ticks_msec()
	_rss0_mb = _read_rss_mb()
	print(
		"EOA_SMOKE_FRAME_GUARD who=guard.start frames=0 rss_mb=%d ds=%s secs=%d (after press; NOT product Begin/Esc/clock PASS)"
		% [_rss0_mb, ds, _guard_secs]
	)
	_flush()
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	_frames += 1
	if _preview != null and _preview.has_method("redraw_spine"):
		_preview.call("redraw_spine")
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed == _last_log_sec:
		return
	_last_log_sec = elapsed
	var rss := _read_rss_mb()
	print(
		"EOA_SMOKE_FRAME_GUARD frames=%d rss_mb=%d elapsed=%d (after press; NOT product Begin/Esc/clock PASS)"
		% [_frames, rss, elapsed]
	)
	_flush()
	if rss >= RSS_LIMIT_MB:
		_fail_reason = "rss"
		_finish(false, rss)
		return
	if elapsed >= _guard_secs:
		var frames_ok := _frames >= maxi(_guard_secs * 2, 10)
		if not frames_ok:
			_fail_reason = "frames_stalled"
		_finish(frames_ok and rss < RSS_LIMIT_MB, rss)


func _finish(ok: bool, rss: int) -> void:
	var verdict := "PASS" if ok else "FAIL"
	print("EOA_SMOKE_FRAME_GUARD frames=%d rss_mb=%d %s" % [_frames, rss, verdict])
	if not ok and not _fail_reason.is_empty():
		print("WindowedIx1SpineFrameGuard: fail_reason=", _fail_reason)
	print("WindowedIx1SpineFrameGuard: RESULT=", verdict)
	_flush()
	if process_frame.is_connected(_on_process):
		process_frame.disconnect(_on_process)
	quit(0 if ok else 1)


func _read_rss_mb() -> int:
	# Never /proc/self via OS.execute — that is the child (awk), not Godot.
	var path := "/proc/%d/status" % OS.get_process_id()
	var from_file := _parse_vmrss_kb_text(_read_text_file(path))
	if from_file > 0:
		return from_file
	var output: Array = []
	var code := OS.execute("/usr/bin/awk", PackedStringArray(["/VmRSS/{print $2}", path]), output, true, false)
	if code == 0 and not output.is_empty():
		var kb := int(str(output[0]).strip_edges())
		if kb > 0:
			return int(round(float(kb) / 1024.0))
	return 0


func _read_text_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt


func _parse_vmrss_kb_text(txt: String) -> int:
	for line in txt.split("\n"):
		if not line.begins_with("VmRSS:"):
			continue
		var compact := line.replace("\t", " ")
		var parts: PackedStringArray = compact.split(" ", false)
		if parts.size() >= 2:
			return int(round(float(parts[1]) / 1024.0))
	return 0


func _flush() -> void:
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
