extends SceneTree

## Year multi-AI campaign: every land-owning nation is an AI agent; advance time N days.
## Default N=365 (1 year). Override with env:
##   EOA_YEAR_AI_DAYS=365
##   EOA_YEAR_AI_MAJORS_ONLY=1   # only scenario majors
##   EOA_YEAR_AI_MAX_FACTIONS=16 # cap tag count
##
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessYearMultiAiCampaignTest.gd
##   tools/eoa_year_multi_ai_test.sh
##
## Loads world_accurate board into MapManager, setup_all_ai, apply_year_multi_ai_campaign_live.

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const SCENARIO_PATH := "res://data/scenarios/world_accurate.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"

const MAJOR_TAGS: Array = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"]

var _fail: PackedStringArray = []
var _pass: PackedStringArray = []


func _init() -> void:
	print("=== YEAR MULTI-AI CAMPAIGN start ===")
	call_deferred("_run")


func _autoload(name: String) -> Node:
	# SceneTree.root is the window viewport; autoloads are direct children by name.
	var n: Node = root.get_node_or_null(name)
	if n != null:
		return n
	return root.get_node_or_null("/root/" + name)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var data = JSON.parse_string(txt)
	return data if data is Dictionary else {}


func _env_int(key: String, default_v: int) -> int:
	var raw := OS.get_environment(key).strip_edges()
	if raw.is_empty():
		return default_v
	return int(raw)


func _env_bool(key: String) -> bool:
	var raw := OS.get_environment(key).strip_edges().to_lower()
	return raw in ["1", "true", "yes", "on"]


func _run() -> void:
	var mm: Node = _autoload("MapManager")
	var gd: Node = _autoload("GameData")
	var sp: Node = _autoload("SessionPlayers")
	var tm: Node = _autoload("TimeManager")
	if mm == null or gd == null or sp == null:
		_fail.append("autoloads_missing")
		_finish()
		return
	if not gd.has_method("apply_year_multi_ai_campaign_live"):
		_fail.append("missing_apply_year_multi_ai_campaign_live")
		_finish()
		return
	if not sp.has_method("setup_all_ai"):
		_fail.append("missing_setup_all_ai")
		_finish()
		return

	if not _load_accurate_board(mm):
		_finish()
		return

	var days := _env_int("EOA_YEAR_AI_DAYS", 365)
	var majors_only := _env_bool("EOA_YEAR_AI_MAJORS_ONLY")
	var max_fac := _env_int("EOA_YEAR_AI_MAX_FACTIONS", 0)
	var tags := _collect_owner_tags(mm, majors_only, max_fac)
	if tags.size() < 4:
		_fail.append("too_few_tags=%d" % tags.size())
		_finish()
		return
	_pass.append("tags_n=%d" % tags.size())
	print("[YEAR AI] factions (%d): %s" % [tags.size(), ", ".join(tags)])

	sp.call("setup_all_ai", tags)
	if int(sp.slots.size()) < tags.size():
		_fail.append("session_slots=%d want>=%d" % [sp.slots.size(), tags.size()])
	else:
		_pass.append("session_all_ai_slots=%d" % sp.slots.size())

	# Seed TimeManager to 1936-01-01 when possible
	if tm != null:
		if "current_year" in tm:
			tm.current_year = 1936
		if "current_month" in tm:
			tm.current_month = 1
		if "current_day" in tm:
			tm.current_day = 1

	var capital_pid := _first_capital_or_owned(mm, str(tags[0]))
	print("[YEAR AI] starting campaign days=%d capital_pid=%d" % [days, capital_pid])
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = gd.call("apply_year_multi_ai_campaign_live", days, capital_pid)
	var elapsed := int(Time.get_ticks_msec() - t0)
	print("[YEAR AI] result: ", JSON.stringify(res))

	if not bool(res.get("ok", false)):
		_fail.append("year_campaign_ok=false")
	else:
		_pass.append("year_campaign_ok")
	if int(res.get("days", 0)) != days:
		_fail.append("days_mismatch=%s" % str(res.get("days")))
	else:
		_pass.append("days=%d" % days)
	if int(res.get("ai_applied_sum", 0)) <= 0:
		_fail.append("ai_applied_sum=0")
	else:
		_pass.append("ai_applied_sum=%d" % int(res.get("ai_applied_sum", 0)))
	if int(res.get("factions_n", 0)) < 4:
		_fail.append("factions_n_low")
	else:
		_pass.append("factions_n=%d" % int(res.get("factions_n", 0)))
	# Majors must perform real production applies (not soft-only)
	var major_apply := int(res.get("major_apply_sum", 0))
	if major_apply <= 0 and days >= 7:
		_fail.append("major_apply_sum=0")
	else:
		_pass.append("major_apply_sum=%d" % major_apply)
	if bool(res.get("lean", false)):
		_pass.append("lean=true")
	if not bool(res.get("year_span_ok", true)) and days >= 300:
		_fail.append("year_span_not_ok")
	else:
		_pass.append("year_span_ok")
	_pass.append("elapsed_ms=%d" % elapsed)
	_pass.append("start=%s end=%s" % [str(res.get("start", "?")), str(res.get("end", "?"))])

	# light check via get_province_count
	var n := int(mm.call("get_province_count")) if mm.has_method("get_province_count") else 0
	if n < 3000:
		_fail.append("province_n_low=%d" % n)
	else:
		_pass.append("provinces=%d" % n)

	_write_evidence_json(res, tags, days, elapsed)
	_finish()


func _write_evidence_json(res: Dictionary, tags: Array, days: int, elapsed: int) -> void:
	var doc := {
		"kind": "year_multi_ai_campaign",
		"ok": bool(res.get("ok", false)),
		"days": days,
		"factions_n": tags.size(),
		"faction_tags": tags,
		"result": res,
		"elapsed_ms_outer": elapsed,
		"board": "world_accurate",
		"lean": bool(res.get("lean", true)),
	}
	var text := JSON.stringify(doc, "\t")
	var paths: Array = [
		"user://year_multi_ai_campaign_evidence.json",
		ProjectSettings.globalize_path("res://tools/map_generation/output/year_multi_ai_campaign_evidence.json"),
	]
	for path_v in paths:
		var path := str(path_v)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			_pass.append("evidence=%s" % path)
			print("[YEAR AI] evidence written: ", path)
		else:
			print("[YEAR AI] evidence write skipped: ", path)


func _collect_owner_tags(mm: Node, majors_only: bool, max_fac: int) -> Array:
	var counts: Dictionary = {}
	var own_doc := _load_json(OWN_PATH)
	var owners: Dictionary = own_doc.get("owners", {}) as Dictionary
	for k in owners.keys():
		var t := str(owners[k]).strip_edges().to_upper()
		if t.is_empty():
			continue
		counts[t] = int(counts.get(t, 0)) + 1
	var tags: Array = []
	for m in MAJOR_TAGS:
		if counts.has(m):
			tags.append(m)
	if not majors_only:
		# add remaining by size
		var rest: Array = []
		for t2 in counts.keys():
			if not tags.has(t2):
				rest.append({"t": t2, "n": int(counts[t2])})
		rest.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
		for row in rest:
			tags.append(str(row["t"]))
	if max_fac > 0 and tags.size() > max_fac:
		tags = tags.slice(0, max_fac)
	return tags


func _first_capital_or_owned(mm: Node, tag: String) -> int:
	var sc := _load_json(SCENARIO_PATH)
	for c in sc.get("countries", []):
		if typeof(c) != TYPE_DICTIONARY:
			continue
		if str(c.get("tag", "")).to_upper() == tag:
			var cap := int(c.get("capital_province_id", 0))
			if cap > 0:
				return cap
	if mm.has_method("get_provinces_by_owner"):
		var owns: Array = mm.call("get_provinces_by_owner", tag)
		if owns.size() > 0:
			return int(owns[0])
	return 710300


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
	if mm.has_method("initialize_from_map_data"):
		mm.call("initialize_from_map_data", map_data)
	else:
		_fail.append("initialize_from_map_data_missing")
		return false
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	var n := int(mm.call("get_province_count")) if mm.has_method("get_province_count") else provs.size()
	if n < 3000:
		_fail.append("too_few_provinces=%d" % n)
		return false
	_pass.append("loaded_provinces=%d" % n)
	return true


func _finish() -> void:
	var ok := _fail.is_empty()
	print("PASS: ", " | ".join(_pass) if not _pass.is_empty() else "(none)")
	if not ok:
		print("FAIL: ", " | ".join(_fail))
	print("=== YEAR MULTI-AI CAMPAIGN end ok=%s ===" % str(ok).to_lower())
	quit(0 if ok else 1)
