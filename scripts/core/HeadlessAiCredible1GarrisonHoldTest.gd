extends SceneTree

## B10G: 1936 start garrisons. POL declares on GER. Player-GER gives no orders.
## GER must keep Berlin and at least 90% of the weighted Brandenburg/Saxony core
## for 60 days. Seeds 193601, 193602, 193603. No unseeded RNG.
## The AI-GER variant is FIX1b (EOA_B10G_AI=1). Air B10 stays in the behaviour test.

const SEEDS: Array[int] = [193601, 193602, 193603]
const DAYS := 60
const MIN_CORE := 90.0
const BERLIN := 710300
const SCENARIO := "res://data/scenarios/world_accurate.json"
const MAJOR_TAGS: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]

var _failures := 0
var _mm: Node
var _sm: Node
var _lm: Node
var _tm: Node
var _bm: Node
var _boot: GDScript
var _war: GDScript
var _gar: GDScript
var _move: GDScript
var _spawn: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_AI_CREDIBLE", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAiCredible1GarrisonHoldTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAiCredible1GarrisonHoldTest: ", msg)


func _run() -> void:
	_mm = get_root().get_node_or_null("MapManager")
	_sm = get_root().get_node_or_null("SupplyManager")
	_lm = get_root().get_node_or_null("LeaderManager")
	_tm = get_root().get_node_or_null("TimeManager")
	_bm = get_root().get_node_or_null("BattleManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_gar = load("res://scripts/core/AiStartGarrisonDomain.gd") as GDScript
	_move = load("res://scripts/formations/FormationMovement.gd") as GDScript
	_spawn = load("res://scripts/formations/FormationSpawner.gd") as GDScript
	if _mm == null or _boot == null or _war == null or _gar == null or _spawn == null or _lm == null or _tm == null:
		_fail("autoloads or scripts missing")
		_finish()
		return
	var roster: Array = _scenario_roster()
	if roster.is_empty():
		_fail("world_accurate roster empty")
		_finish()
		return
	for s in SEEDS:
		_one("player", int(s), roster)
	if OS.get_environment("EOA_B10G_AI").strip_edges() == "1":
		for s2 in SEEDS:
			_one("ai", int(s2), roster)
	_finish()


func _one(variant: String, which: int, roster: Array) -> void:
	seed(which)
	var player := "GER" if variant == "player" else "USA"
	if not _boot.boot(_mm, _sm, player):
		_fail("boot failed seed=%d" % which)
		return
	_lm.call("set_player_country_tag", player)
	_war.reset_for_test()
	_war.clear_rule_overrides()
	if _bm != null and _bm.has_method("apply_save_data"):
		_bm.call("apply_save_data", {})
	_clear_marches()
	if _lm.has_method("clear_all_formations"):
		_lm.call("clear_all_formations")
	var spawner = _spawn.new()
	for entry_v in roster:
		var entry: Dictionary = entry_v
		var tag := str(entry.get("tag", ""))
		var owned: Array = _owned(tag)
		var borders: Array = _border_ids(tag, owned)
		spawner.spawn_test_formations_for_country(
			tag,
			int(entry.get("count", 4)),
			int(entry.get("capital", -1)),
			owned,
			entry.get("keys", []),
			borders,
		)
	var rep: Dictionary = _gar.call("apply")
	print("B10G garrison seed=%d %s" % [which, str(rep.get("summary", ""))])
	_print_major_rows(rep, which)
	if bool(rep.get("skipped", false)):
		_fail("garrison apply skipped seed=%d" % which)
		return
	var snap: Dictionary = _gar.call("core_snapshot", "GER")
	var core_w := int(snap.get("weight", 0))
	if core_w <= 0:
		_fail("GER weighted core empty seed=%d" % which)
		return
	var decl: Dictionary = _war.declare_war("POL", "GER", "b10g")
	if not bool(decl.get("ok", false)):
		_fail("POL declare failed seed=%d %s" % [which, str(decl)])
		return
	print("B10G declare seed=%d called=%s" % [which, str(decl.get("called", []))])
	var berlin_days := 0
	var min_pct := 100.0
	var day60 := 0.0
	var open: Dictionary = {}
	var captures: Array = []
	var prev_owner: Dictionary = {}
	var prev_units: Dictionary = _units_on("GER")
	for pid_v in snap.get("pids", []):
		prev_owner[int(pid_v)] = "GER"
	for day_i in range(1, DAYS + 1):
		_tm.call("advance_live_f5_equivalent_days", 1)
		var held := _held_weight(snap)
		var pct := 100.0 * float(held) / float(core_w)
		if pct < min_pct:
			min_pct = pct
		day60 = pct
		var berlin_owner := _owner_of(BERLIN)
		if berlin_owner == "GER":
			berlin_days += 1
		_note_captures(snap, prev_owner, prev_units, day_i, open, captures)
		prev_units = _units_on("GER")
		if day_i == 20 or day_i == 40 or day_i == 60:
			print(
				"B10G progress variant=%s seed=%d day=%d berlin=%s core=%.1f min=%.1f"
				% [variant, which, day_i, berlin_owner, pct, min_pct]
			)
	var cap_txt := _format_captures(snap, captures)
	print(
		"B10G result variant=%s seed=%d berlin_days=%d min_core=%.1f day60=%.1f empty_captures=%d %s"
		% [variant, which, berlin_days, min_pct, day60, captures.size(), cap_txt]
	)
	if berlin_days >= DAYS and min_pct + 0.001 >= MIN_CORE and day60 + 0.001 >= MIN_CORE:
		_pass(
			"%s seed=%d berlin_days=%d min_core=%.1f day60=%.1f empty_captures=%d"
			% [variant, which, berlin_days, min_pct, day60, captures.size()]
		)
	else:
		_fail(
			"%s seed=%d berlin_days=%d min_core=%.1f day60=%.1f empty_captures=%d %s"
			% [variant, which, berlin_days, min_pct, day60, captures.size(), cap_txt]
		)


func _note_captures(
	snap: Dictionary,
	prev_owner: Dictionary,
	prev_units: Dictionary,
	day_i: int,
	open: Dictionary,
	captures: Array,
) -> void:
	var names: Dictionary = snap.get("names", {})
	for pid_v in snap.get("pids", []):
		var pid := int(pid_v)
		var now := _owner_of(pid)
		var was := str(prev_owner.get(pid, "GER"))
		if was == "GER" and now != "GER":
			var empty := not bool(prev_units.get(pid, false))
			if empty:
				open[pid] = {
					"pid": pid,
					"start": day_i,
					"owner": now,
					"name": str(names.get(pid, "")),
				}
			else:
				print("B10G battle_capture day=%d pid=%d %s -> %s" % [day_i, pid, str(names.get(pid, "")), now])
		elif was != "GER" and now == "GER" and open.has(pid):
			var row: Dictionary = open[pid]
			row["pid"] = pid
			row["end"] = day_i - 1
			captures.append(row)
			open.erase(pid)
		prev_owner[pid] = now
	if day_i == DAYS:
		var keys: Array = open.keys()
		keys.sort()
		for k in keys:
			var row2: Dictionary = open[k]
			row2["end"] = DAYS
			row2["pid"] = int(k)
			captures.append(row2)


func _format_captures(snap: Dictionary, captures: Array) -> String:
	if captures.is_empty():
		return "captures=none"
	var names: Dictionary = snap.get("names", {})
	var parts: PackedStringArray = PackedStringArray()
	for row_v in captures:
		var row: Dictionary = row_v
		var pid := int(row.get("pid", 0))
		var start := int(row.get("start", 0))
		var end := int(row.get("end", start))
		var nm := str(row.get("name", names.get(pid, "")))
		parts.append("%d:%s d=%d..%d days=%d ->%s" % [pid, nm, start, end, end - start + 1, str(row.get("owner", ""))])
	return "captures=" + " | ".join(parts)


func _held_weight(snap: Dictionary) -> int:
	var weights: Dictionary = snap.get("weights", {})
	var total := 0
	for pid_v in snap.get("pids", []):
		var pid := int(pid_v)
		if _owner_of(pid) == "GER":
			total += int(weights.get(pid, 0))
	return total


func _units_on(tag: String) -> Dictionary:
	var on: Dictionary = {}
	if _lm == null or not _lm.has_method("get_formations_for_country"):
		return on
	for f in _lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft != "division" and ft != "garrison":
			continue
		on[int(f.stationed_province_id)] = true
	return on


func _owner_of(pid: int) -> String:
	var p = _mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.owner_tag).strip_edges().to_upper()


func _print_major_rows(rep: Dictionary, which: int) -> void:
	var rows: Variant = rep.get("tags", [])
	if not (rows is Array):
		return
	for row_v in rows:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var tag := str(row.get("tag", ""))
		if which != SEEDS[0] and tag != "GER" and tag != "POL":
			continue
		print(
			"B10G place seed=%d tag=%s capital=%s(%d) border=%d/%d units=%d open=%d stations=%s"
			% [
				which,
				tag,
				"y" if bool(row.get("capital_garrisoned", false)) else "n",
				int(row.get("capital_pid", -1)),
				int(row.get("border_covered", 0)),
				int(row.get("border_total", 0)),
				int(row.get("units", 0)),
				int(row.get("open_contacts", 0)),
				str(row.get("stations", "")),
			]
		)
		if int(row.get("open_contacts", 0)) > 0 and (tag == "GER" or tag == "POL"):
			print("B10G open seed=%d tag=%s pids=%s" % [which, tag, str(row.get("open_pids", []))])


func _scenario_roster() -> Array:
	if not FileAccess.file_exists(SCENARIO):
		return []
	var f := FileAccess.open(SCENARIO, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return []
	var countries: Variant = (parsed as Dictionary).get("countries", [])
	if not (countries is Array):
		return []
	var out: Array = []
	for item in countries:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var tag := str(d.get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var major := bool(d.get("major_power", false)) or tag in MAJOR_TAGS
		var keys: Array = []
		var raw_keys: Variant = d.get("key_provinces", [])
		if raw_keys is Array:
			for k in raw_keys:
				var pid := int(k)
				if pid > 0:
					keys.append(pid)
		out.append({
			"tag": tag,
			"count": 8 if major else 4,
			"capital": int(d.get("capital_province_id", -1)),
			"keys": keys,
		})
	out.sort_custom(func(a, b):
		return str(a.get("tag", "")) < str(b.get("tag", ""))
	)
	return out


func _owned(tag: String) -> Array:
	var out: Array = []
	for pid_v in _mm.call("get_provinces_by_owner", tag):
		var p = _mm.call("get_province", int(pid_v))
		if p == null or bool(p.is_sea):
			continue
		out.append(int(pid_v))
	out.sort()
	return out


func _border_ids(tag: String, owned: Array) -> Array:
	var own_set: Dictionary = {}
	for pid in owned:
		own_set[int(pid)] = true
	var out: Array = []
	for pid2 in owned:
		var pid := int(pid2)
		var is_border := false
		for nid_v in _mm.call("get_adjacent_provinces", pid, true):
			var nid := int(nid_v)
			if own_set.has(nid):
				continue
			var n = _mm.call("get_province", nid)
			if n == null or bool(n.is_sea):
				continue
			var ot := str(n.owner_tag).strip_edges().to_upper()
			if ot.is_empty() or ot == tag:
				continue
			is_border = true
			break
		if is_border:
			out.append(pid)
	out.sort()
	return out


func _clear_marches() -> void:
	if _move == null:
		return
	for raw in _move.call("list_marches"):
		if raw is Dictionary:
			_move.call("clear_march", str((raw as Dictionary).get("formation_id", "")))


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAiCredible1GarrisonHoldTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAiCredible1GarrisonHoldTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
