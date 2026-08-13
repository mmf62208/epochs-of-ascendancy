class_name MapRendererPerf
extends RefCounted
## Lightweight frame / section timing for MapRenderer gap-closure Phase 1 + M5.
## Enable with EOA_MAP_PERF=1 or MapRenderer.enable_perf_profile = true.
## Logs [PERF MAP EVIDENCE] hotspots without allocating in the hot path when disabled.
## Session samples accumulate across windows for p50/p95 export (M5).

const ENV_FLAG := "EOA_MAP_PERF"
const SAMPLE_EVERY_N_FRAMES := 30
const MAX_SECTIONS := 24
const MAX_SESSION_SAMPLES := 2400
const DEFAULT_EXPORT_PATH := "user://map_perf_session_samples.json"
const DEFAULT_REPO_EXPORT := "res://tools/map_generation/output/map_perf_world_accurate_samples.json"
const DEFAULT_TMP_EXPORT := "/tmp/eoa-map-perf-world-accurate.json"

var enabled: bool = false
var _section_ms: Dictionary = {}  # name -> cumulative ms this window
var _section_calls: Dictionary = {}
var _frame_ms_samples: Array = []
var _session_frame_ms: Array = []  # M5: retained across windows
var _window_start_usec: int = 0
var _frames_in_window: int = 0
var _last_report: Dictionary = {}
var _active_starts: Dictionary = {}  # name -> start usec
var pilot_tag: String = "world_accurate"
var measure_kind: String = "renderer_frame"


func set_enabled(on: bool) -> void:
	enabled = on
	if on and _window_start_usec == 0:
		_window_start_usec = Time.get_ticks_usec()


func env_wants_profile() -> bool:
	return OS.get_environment(ENV_FLAG).strip_edges() == "1"


func begin(section: String) -> void:
	if not enabled:
		return
	_active_starts[section] = Time.get_ticks_usec()


func end(section: String) -> void:
	if not enabled:
		return
	if not _active_starts.has(section):
		return
	var start_u: int = int(_active_starts[section])
	_active_starts.erase(section)
	var dt_ms := float(Time.get_ticks_usec() - start_u) / 1000.0
	_section_ms[section] = float(_section_ms.get(section, 0.0)) + dt_ms
	_section_calls[section] = int(_section_calls.get(section, 0)) + 1


func mark_frame(frame_ms: float) -> void:
	if not enabled:
		return
	_frames_in_window += 1
	_frame_ms_samples.append(frame_ms)
	_session_frame_ms.append(frame_ms)
	if _session_frame_ms.size() > MAX_SESSION_SAMPLES:
		_session_frame_ms = _session_frame_ms.slice(_session_frame_ms.size() - MAX_SESSION_SAMPLES)
	if _frames_in_window >= SAMPLE_EVERY_N_FRAMES:
		_emit_report()


func force_report() -> Dictionary:
	return _emit_report()


func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)


func get_session_samples() -> Array:
	return _session_frame_ms.duplicate()


func clear_session_samples() -> void:
	_session_frame_ms.clear()


## Linear-interpolation percentile; pct in [0, 100].
static func percentile(samples: Array, pct: float) -> float:
	var vals: Array = []
	for v in samples:
		vals.append(float(v))
	if vals.is_empty():
		return 0.0
	vals.sort()
	var n := vals.size()
	if n == 1:
		return float(vals[0])
	var p := clampf(float(pct), 0.0, 100.0)
	if p <= 0.0:
		return float(vals[0])
	if p >= 100.0:
		return float(vals[n - 1])
	var rank := (p / 100.0) * float(n - 1)
	var lo := int(rank)
	var hi := mini(lo + 1, n - 1)
	var frac := rank - float(lo)
	return float(vals[lo]) * (1.0 - frac) + float(vals[hi]) * frac


func session_stats() -> Dictionary:
	var samples: Array = _session_frame_ms
	if samples.is_empty():
		return {
			"empty": true,
			"sample_n": 0,
			"mean_ms": 0.0,
			"p50_ms": 0.0,
			"p95_ms": 0.0,
			"min_ms": 0.0,
			"max_ms": 0.0,
			"estimated_fps": 0.0,
		}
	var acc := 0.0
	var mn := 1e18
	var mx := 0.0
	for v in samples:
		var f := float(v)
		acc += f
		if f < mn:
			mn = f
		if f > mx:
			mx = f
	var n := samples.size()
	var mean_ms := acc / float(n)
	return {
		"empty": false,
		"sample_n": n,
		"mean_ms": mean_ms,
		"p50_ms": percentile(samples, 50.0),
		"p95_ms": percentile(samples, 95.0),
		"min_ms": mn,
		"max_ms": mx,
		"estimated_fps": (1000.0 / mean_ms) if mean_ms > 0.001 else 0.0,
	}


## Pack I / M3 — budget gate vs target frame ms (16.67 ≈ 60fps, 33.3 ≈ 30fps).
func passes_budget(target_ms: float = 16.67) -> Dictionary:
	var stats: Dictionary = session_stats()
	if bool(stats.get("empty", true)):
		var rep: Dictionary = get_last_report()
		var avg := float(rep.get("frame_avg_ms", 0.0))
		var mx := float(rep.get("frame_max_ms", 0.0))
		var has_samples := int(rep.get("frames", 0)) > 0 or avg > 0.0 or mx > 0.0
		var ok := has_samples and avg > 0.0 and avg <= target_ms
		var hard_fail := avg > target_ms * 2.0
		return {
			"ok": ok and not hard_fail,
			"soft_ok": has_samples and not hard_fail,
			"frame_avg_ms": avg,
			"frame_max_ms": mx,
			"target_ms": target_ms,
			"fps_est": (1000.0 / avg) if avg > 0.001 else 0.0,
			"summary": "FPS budget · avg %.2fms · max %.2fms · target %.2fms · %s" % [
				avg, mx, target_ms, "PASS" if ok and not hard_fail else ("SOFT" if has_samples and not hard_fail else "FAIL"),
			],
			"report": rep,
			"empty": not has_samples,
		}
	var mean_ms := float(stats.get("mean_ms", 0.0))
	var p95_ms := float(stats.get("p95_ms", 0.0))
	var ok2 := mean_ms > 0.0 and mean_ms <= target_ms
	var hard2 := mean_ms > target_ms * 2.0
	return {
		"ok": ok2 and not hard2,
		"soft_ok": not hard2,
		"frame_avg_ms": mean_ms,
		"frame_max_ms": float(stats.get("max_ms", 0.0)),
		"p50_ms": float(stats.get("p50_ms", 0.0)),
		"p95_ms": p95_ms,
		"target_ms": target_ms,
		"fps_est": float(stats.get("estimated_fps", 0.0)),
		"sample_n": int(stats.get("sample_n", 0)),
		"summary": "FPS budget · n=%d · mean %.2fms · p50 %.2f · p95 %.2f · target %.2fms · %s" % [
			int(stats.get("sample_n", 0)), mean_ms, float(stats.get("p50_ms", 0.0)), p95_ms, target_ms,
			"PASS" if ok2 and not hard2 else "FAIL",
		],
		"report": get_last_report(),
		"empty": false,
	}


func write_scratch_budget(path: String = "/tmp/eoa-map-perf-budget.json", target_ms: float = 16.67) -> Dictionary:
	var budget: Dictionary = passes_budget(target_ms)
	var payload := {
		"budget": budget,
		"report": get_last_report(),
		"session": session_stats(),
		"env": ENV_FLAG,
		"target_ms": target_ms,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		budget["write_ok"] = false
		budget["path"] = path
		return budget
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	budget["write_ok"] = true
	budget["path"] = path
	print("[PERF MAP FPS] wrote %s · %s" % [path, budget.get("summary", "")])
	return budget


## M5: export full session samples + p50/p95 for pure harness ingest.
func export_session_json(
	path: String = DEFAULT_TMP_EXPORT,
	province_count: int = 8761,
	land_n: int = 8421,
) -> Dictionary:
	var stats: Dictionary = session_stats()
	var payload := {
		"ok": not bool(stats.get("empty", true)),
		"empty": bool(stats.get("empty", true)),
		"pilot_tag": pilot_tag,
		"measure_kind": measure_kind,
		"province_count": province_count,
		"land_n": land_n,
		"env": ENV_FLAG,
		"sample_n": int(stats.get("sample_n", 0)),
		"mean_ms": float(stats.get("mean_ms", 0.0)),
		"p50_ms": float(stats.get("p50_ms", 0.0)),
		"p95_ms": float(stats.get("p95_ms", 0.0)),
		"min_ms": float(stats.get("min_ms", 0.0)),
		"max_ms": float(stats.get("max_ms", 0.0)),
		"estimated_fps": float(stats.get("estimated_fps", 0.0)),
		"frame_times_ms": get_session_samples(),
		"budget_ms_30": 1000.0 / 30.0,
		"budget_ms_60": 1000.0 / 60.0,
		"soft_p95_ms_30": 48.0,
		"summary": "Map perf session · pilot=%s · n=%d · mean %.2fms · p50 %.2f · p95 %.2f · ~%.1f fps · %s" % [
			pilot_tag,
			int(stats.get("sample_n", 0)),
			float(stats.get("mean_ms", 0.0)),
			float(stats.get("p50_ms", 0.0)),
			float(stats.get("p95_ms", 0.0)),
			float(stats.get("estimated_fps", 0.0)),
			"EMPTY" if bool(stats.get("empty", true)) else "SAMPLED",
		],
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		payload["write_ok"] = false
		payload["path"] = path
		print("[PERF MAP M5] export FAILED path=%s" % path)
		return payload
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	payload["write_ok"] = true
	payload["path"] = path
	print("[PERF MAP M5] %s · wrote %s" % [payload.get("summary", ""), path])
	return payload


func _emit_report() -> Dictionary:
	var ranked: Array = []
	for k in _section_ms.keys():
		ranked.append({
			"section": str(k),
			"ms_total": float(_section_ms[k]),
			"calls": int(_section_calls.get(k, 0)),
			"ms_avg": float(_section_ms[k]) / maxf(1.0, float(_section_calls.get(k, 1))),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("ms_total", 0.0)) > float(b.get("ms_total", 0.0))
	)
	if ranked.size() > MAX_SECTIONS:
		ranked = ranked.slice(0, MAX_SECTIONS)
	var frame_avg := 0.0
	var frame_max := 0.0
	if not _frame_ms_samples.is_empty():
		var acc := 0.0
		for v in _frame_ms_samples:
			var f := float(v)
			acc += f
			if f > frame_max:
				frame_max = f
		frame_avg = acc / float(_frame_ms_samples.size())
	var top_name := ""
	var top_ms := 0.0
	if not ranked.is_empty():
		top_name = str(ranked[0].get("section", ""))
		top_ms = float(ranked[0].get("ms_total", 0.0))
	var sess: Dictionary = session_stats()
	_last_report = {
		"ok": true,
		"frame_avg_ms": frame_avg,
		"frame_max_ms": frame_max,
		"frames": _frames_in_window,
		"session_n": int(sess.get("sample_n", 0)),
		"session_p50_ms": float(sess.get("p50_ms", 0.0)),
		"session_p95_ms": float(sess.get("p95_ms", 0.0)),
		"hotspots": ranked,
		"top_section": top_name,
		"top_ms": top_ms,
		"empty": ranked.is_empty() and _frame_ms_samples.is_empty(),
		"summary": "PERF MAP · frames %d · avg %.2fms · max %.2fms · sess p50 %.2f p95 %.2f · top %s %.2fms"
			% [
				_frames_in_window, frame_avg, frame_max,
				float(sess.get("p50_ms", 0.0)), float(sess.get("p95_ms", 0.0)),
				top_name, top_ms,
			],
	}
	print("[PERF MAP EVIDENCE] %s" % _last_report["summary"])
	for i in mini(5, ranked.size()):
		var h: Dictionary = ranked[i]
		print("[PERF MAP HOTSPOT] #%d %s total=%.2fms avg=%.3fms calls=%d" % [
			i + 1, h.get("section"), h.get("ms_total"), h.get("ms_avg"), h.get("calls"),
		])
	# reset window (session samples retained)
	_section_ms.clear()
	_section_calls.clear()
	_frame_ms_samples.clear()
	_frames_in_window = 0
	_window_start_usec = Time.get_ticks_usec()
	return _last_report.duplicate(true)
