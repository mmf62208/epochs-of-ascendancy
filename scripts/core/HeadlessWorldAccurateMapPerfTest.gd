extends SceneTree

## M5 — headless map-tick proxy samples on world_accurate (~3520 post US+RoW sparse; was ~5670/~8761).
## Measures CPU map path (pick + adjacency + land path), not full GPU renderer FPS.
## Exports JSON for pure map_perf_fps_harness_product ingest.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMapPerfTest.gd
##
## For full renderer frames (graphical preferred):
##   EOA_MAP_PERF=1 EOA_SCENARIO=world_accurate tools/run_godot.sh --path . res://scenes/TestScenario.tscn
##   then F10 → Map Perf dump (writes /tmp + tools/map_generation/output/…).

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const SCENARIO_PATH := "res://data/scenarios/world_accurate.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const PERF_SCRIPT := "res://scripts/map/MapRendererPerf.gd"
const SAMPLE_N := 60
const GER_CAPITAL := 710300
const GER_FRONT := 710173

var _fail: PackedStringArray = []
var _pass: PackedStringArray = []


func _init() -> void:
	print("=== HEADLESS WORLD_ACCURATE MAP PERF (M5) start ===")
	call_deferred("_run")


func _run() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail.append("MapManager_autoload_missing")
		_finish()
		return
	if not _load_accurate_board(mm):
		_finish()
		return

	var n_prov := int(mm.call("get_province_count")) if mm.has_method("get_province_count") else 0
	# Post US + full RoW sparse merge ~3520; was ~5670 / ~8761. Floor 3000.
	if n_prov < 3000:
		_fail.append("too_few_provinces=%d" % n_prov)
		_finish()
		return
	_pass.append("loaded_provinces=%d" % n_prov)

	var PerfScr: GDScript = load(PERF_SCRIPT) as GDScript
	if PerfScr == null:
		_fail.append("MapRendererPerf_missing")
		_finish()
		return
	var perf = PerfScr.new()
	perf.set_enabled(true)
	perf.pilot_tag = "world_accurate"
	perf.measure_kind = "map_tick_proxy_headless"

	var rng := RandomNumberGenerator.new()
	rng.seed = 8761
	var capital_ids: Array = [GER_CAPITAL, 710707, 800792, 711414, 903534]
	for i in SAMPLE_N:
		var t0 := Time.get_ticks_usec()
		_map_tick_work(mm, capital_ids, rng)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		perf.mark_frame(ms)

	var stats: Dictionary = perf.session_stats() if perf.has_method("session_stats") else {}
	if int(stats.get("sample_n", 0)) < SAMPLE_N:
		_fail.append("sample_n=%d need %d" % [int(stats.get("sample_n", 0)), SAMPLE_N])
	else:
		_pass.append(
			"samples n=%d mean=%.2f p50=%.2f p95=%.2f ~%.1ffps" % [
				int(stats.get("sample_n", 0)),
				float(stats.get("mean_ms", 0.0)),
				float(stats.get("p50_ms", 0.0)),
				float(stats.get("p95_ms", 0.0)),
				float(stats.get("estimated_fps", 0.0)),
			]
		)

	var land_n := maxi(0, n_prov - 340)  # seas ~340 on accurate; approx OK for metadata
	var tmp_path := "/tmp/eoa-map-perf-world-accurate.json"
	var exp: Dictionary = perf.export_session_json(tmp_path, n_prov, land_n)
	if not bool(exp.get("write_ok", false)):
		_fail.append("export_tmp_failed")
	else:
		_pass.append("exported_tmp=%s" % tmp_path)

	var repo_path := ProjectSettings.globalize_path("res://tools/map_generation/output/map_perf_world_accurate_samples.json")
	var exp2: Dictionary = perf.export_session_json(repo_path, n_prov, land_n)
	if bool(exp2.get("write_ok", false)):
		_pass.append("exported_repo=%s" % repo_path)
	else:
		# user:// fallback
		var user_path := "user://map_perf_world_accurate_samples.json"
		var exp3: Dictionary = perf.export_session_json(user_path, n_prov, land_n)
		if bool(exp3.get("write_ok", false)):
			_pass.append("exported_user=%s" % user_path)
		else:
			_fail.append("export_repo_and_user_failed")

	# Soft 30fps is for full renderer; proxy is informational. Gate: samples exist + p95 finite.
	if float(stats.get("p95_ms", 0.0)) <= 0.0 and int(stats.get("sample_n", 0)) > 0:
		_fail.append("p95_invalid")
	else:
		_pass.append("p95_ok")

	_finish()


func _map_tick_work(mm: Node, capital_ids: Array, rng: RandomNumberGenerator) -> void:
	# Pick capitals
	for cid in capital_ids:
		if mm.has_method("get_province_centroid"):
			var c: Vector2 = mm.get_province_centroid(int(cid))
			if mm.has_method("get_province_at_world_pos") and c != Vector2.ZERO:
				mm.get_province_at_world_pos(c, true)
	# Adjacent fan-out
	for _j in 80:
		var pid := int(capital_ids[rng.randi() % capital_ids.size()])
		if mm.has_method("get_adjacent_provinces"):
			mm.get_adjacent_provinces(pid, true)
	# Corridor path sample
	if mm.has_method("find_land_path"):
		mm.find_land_path(GER_CAPITAL, GER_FRONT, "GER", 40)
	if mm.has_method("find_infra_weighted_land_path"):
		mm.find_infra_weighted_land_path(GER_CAPITAL, GER_FRONT, "GER", 50)


func _load_accurate_board(mm: Node) -> bool:
	var base := _load_json(BASE_PATH)
	var geo := _load_json(GEO_PATH)
	var own_doc := _load_json(OWN_PATH)
	if base.is_empty() or geo.is_empty():
		_fail.append("data_load_failed")
		return false
	var ProvScript: GDScript = load(PROV_SCRIPT) as GDScript
	var MapDataScript: GDScript = load(MAP_DATA_SCRIPT) as GDScript
	if ProvScript == null or MapDataScript == null:
		_fail.append("script_load_failed")
		return false
	var owners: Dictionary = own_doc.get("owners", {}) as Dictionary
	var provs: Dictionary = {}
	for row in base.get("provinces", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid := int(row.get("id", 0))
		if pid <= 0:
			continue
		var p = ProvScript.new()
		p.id = pid
		p.name = str(row.get("name", "Province %d" % pid))
		p.terrain = str(row.get("terrain", "plains"))
		p.domain = str(row.get("domain", "land"))
		var terr_l := str(p.terrain).strip_edges().to_lower()
		p.is_sea = terr_l in ["sea", "ocean", "water", "lake"] or str(p.domain).strip_edges().to_lower() in ["sea", "ocean", "naval"]
		var ot := str(owners.get(str(pid), "")).strip_edges().to_upper()
		if not ot.is_empty():
			p.owner_tag = ot
			p.controller_tag = ot
		# light infra for weighted path
		if "infrastructure" in p:
			p.infrastructure = 5
		provs[pid] = p

	var geometry: Dictionary = {}
	for row in geo.get("provinces", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid2 := int(row.get("id", 0))
		if pid2 <= 0:
			continue
		var pts: Array = row.get("points", [])
		var packed := PackedVector2Array()
		for pt in pts:
			if pt is Array and pt.size() >= 2:
				packed.append(Vector2(float(pt[0]), float(pt[1])))
		geometry[pid2] = {
			"points": packed,
			"label_anchor": row.get("label_anchor", []),
			"meta": row.get("meta", {}),
		}

	var adj = null
	if FileAccess.file_exists(ADJ_PATH):
		var AdjScr: GDScript = load("res://scripts/data/AdjacencySystem.gd") as GDScript
		if AdjScr != null:
			adj = AdjScr.new()
			if adj.has_method("load_adjacency"):
				adj.call("load_adjacency", ADJ_PATH)
			if adj.has_method("begin_bulk_registration"):
				adj.call("begin_bulk_registration")
			for _pid in provs.keys():
				if adj.has_method("register_province"):
					adj.call("register_province", provs[_pid])
			if adj.has_method("end_bulk_registration"):
				adj.call("end_bulk_registration")
	var map_data = MapDataScript.new(provs, geometry, adj, {})
	mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	return true


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	return data if data is Dictionary else {}


func _finish() -> void:
	for s in _pass:
		print("  [PASS] ", s)
	for s in _fail:
		print("  [FAIL] ", s)
	var ok := _fail.is_empty()
	print("HeadlessWorldAccurateMapPerfTest: ", "PASS" if ok else "FAIL", " fails=", _fail.size())
	quit(0 if ok else 1)
