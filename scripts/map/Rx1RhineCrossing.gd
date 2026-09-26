class_name Rx1RhineCrossing
extends RefCounted

## RX-1 Rhine Crossing — edge-level rules for the Bonn–Duisburg stretch.
## Constants live in data/map/rx1_rhine_crossings.json (single config place).

const SPEC_PATH := "res://data/map/rx1_rhine_crossings.json"
const RHINE_UNBRIDGED_MOVE_MULT := 2.0
const RHINE_BRIDGED_MOVE_MULT := 1.15
const RHINE_UNBRIDGED_ATTACK_MALUS := 0.30
const RHINE_BRIDGED_ATTACK_MALUS := 0.10
const FIRST_SESSION_MANDATE_COST := 0

static var _loaded: bool = false
static var _spec: Dictionary = {}
static var _edges: Dictionary = {}  # "a-b" -> row
static var _bridged: Dictionary = {}  # "a-b" -> bool (runtime, seeded from 1936)
static var _course: PackedVector2Array = PackedVector2Array()
static var _theater: Dictionary = {}  # pid -> true


static func edge_key(a: int, b: int) -> String:
	if a < b:
		return "%d-%d" % [a, b]
	return "%d-%d" % [b, a]


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_spec = {}
	_edges.clear()
	_bridged.clear()
	_course = PackedVector2Array()
	_theater.clear()
	if not FileAccess.file_exists(SPEC_PATH):
		return
	var f := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_spec = parsed
	var consts: Dictionary = _spec.get("constants", {})
	for row_v in _spec.get("edges", []):
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var pair: Variant = row.get("edge", [])
		if typeof(pair) != TYPE_ARRAY or (pair as Array).size() < 2:
			continue
		var a := int((pair as Array)[0])
		var b := int((pair as Array)[1])
		var key := edge_key(a, b)
		_edges[key] = row
		_bridged[key] = bool(row.get("bridged_1936", false))
		_theater[a] = true
		_theater[b] = true
	var pts: Variant = (_spec.get("course", {}) as Dictionary).get("points", [])
	if pts is Array:
		for p in pts:
			if p is Array and (p as Array).size() >= 2:
				_course.append(Vector2(float(p[0]), float(p[1])))


static func reset_to_1936() -> void:
	ensure_loaded()
	for key in _edges.keys():
		var row: Dictionary = _edges[key]
		_bridged[key] = bool(row.get("bridged_1936", false))


static func constants() -> Dictionary:
	ensure_loaded()
	var c: Dictionary = _spec.get("constants", {})
	return {
		"RHINE_UNBRIDGED_MOVE_MULT": float(c.get("RHINE_UNBRIDGED_MOVE_MULT", RHINE_UNBRIDGED_MOVE_MULT)),
		"RHINE_BRIDGED_MOVE_MULT": float(c.get("RHINE_BRIDGED_MOVE_MULT", RHINE_BRIDGED_MOVE_MULT)),
		"RHINE_UNBRIDGED_ATTACK_MALUS": float(c.get("RHINE_UNBRIDGED_ATTACK_MALUS", RHINE_UNBRIDGED_ATTACK_MALUS)),
		"RHINE_BRIDGED_ATTACK_MALUS": float(c.get("RHINE_BRIDGED_ATTACK_MALUS", RHINE_BRIDGED_ATTACK_MALUS)),
		"first_session_mandate_cost": int(c.get("first_session_mandate_cost", FIRST_SESSION_MANDATE_COST)),
	}


static func course_points() -> PackedVector2Array:
	ensure_loaded()
	return _course


static func is_crossing(a: int, b: int) -> bool:
	ensure_loaded()
	return _edges.has(edge_key(a, b))


static func is_crossing_province(pid: int) -> bool:
	ensure_loaded()
	return _theater.has(int(pid))


static func is_bridged(a: int, b: int) -> bool:
	ensure_loaded()
	var key := edge_key(a, b)
	if not _bridged.has(key):
		return false
	return bool(_bridged[key])


static func set_bridged(a: int, b: int, value: bool = true) -> void:
	ensure_loaded()
	var key := edge_key(a, b)
	if _edges.has(key):
		_bridged[key] = value


static func move_mult(a: int, b: int) -> float:
	ensure_loaded()
	if not is_crossing(a, b):
		return 1.0
	var c := constants()
	if is_bridged(a, b):
		return float(c["RHINE_BRIDGED_MOVE_MULT"])
	return float(c["RHINE_UNBRIDGED_MOVE_MULT"])


static func attack_malus(a: int, b: int) -> float:
	ensure_loaded()
	if not is_crossing(a, b):
		return 0.0
	var c := constants()
	if is_bridged(a, b):
		return float(c["RHINE_BRIDGED_ATTACK_MALUS"])
	return float(c["RHINE_UNBRIDGED_ATTACK_MALUS"])


static func crossings_for(pid: int) -> Array[Dictionary]:
	ensure_loaded()
	var out: Array[Dictionary] = []
	for key in _edges.keys():
		var row: Dictionary = _edges[key]
		var pair: Variant = row.get("edge", [])
		if typeof(pair) != TYPE_ARRAY or (pair as Array).size() < 2:
			continue
		var a := int((pair as Array)[0])
		var b := int((pair as Array)[1])
		if a != pid and b != pid:
			continue
		var other := b if a == pid else a
		var names: Variant = row.get("names", [])
		var name_a := str((names as Array)[0]) if names is Array and (names as Array).size() >= 1 else str(a)
		var name_b := str((names as Array)[1]) if names is Array and (names as Array).size() >= 2 else str(b)
		out.append({
			"a": a,
			"b": b,
			"other": other,
			"bridged": is_bridged(a, b),
			"names": [name_a, name_b],
			"midpoint": row.get("midpoint", [0, 0]),
			"historical": str(row.get("historical", "")),
		})
	return out


static func first_unbridged_for(pid: int) -> Dictionary:
	for row in crossings_for(pid):
		if not bool(row.get("bridged", true)):
			return row
	return {}


static func inspector_lines(pid: int) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for row in crossings_for(pid):
		var a := int(row.get("a", 0))
		var b := int(row.get("b", 0))
		var names: Array = row.get("names", [])
		var na := str(names[0]) if names.size() >= 1 else str(a)
		var nb := str(names[1]) if names.size() >= 2 else str(b)
		if bool(row.get("bridged", false)):
			lines.append("Rhine crossing: bridged (%s ↔ %s)" % [na, nb])
		else:
			lines.append("Rhine crossing: no bridge (%s ↔ %s)" % [na, nb])
		var um := move_mult(a, b)
		var mal := attack_malus(a, b)
		lines.append("  hop ×%.2f · attack −%d%%" % [um, int(round(mal * 100.0))])
	return lines


static func battle_penalty_line(from_id: int, to_id: int) -> String:
	if not is_crossing(from_id, to_id):
		return ""
	var mal := attack_malus(from_id, to_id)
	if is_bridged(from_id, to_id):
		return "Rhine crossing: bridged (−%d%% attack)" % int(round(mal * 100.0))
	return "Rhine crossing: no bridge (−%d%% attack)" % int(round(mal * 100.0))


static func unbridged_build_target() -> Array[int]:
	ensure_loaded()
	var raw: Variant = _spec.get("unbridged_build_target", [])
	var out: Array[int] = []
	if raw is Array and (raw as Array).size() >= 2:
		out.append(int((raw as Array)[0]))
		out.append(int((raw as Array)[1]))
	return out


static func first_session_mandate_cost() -> int:
	return int(constants().get("first_session_mandate_cost", FIRST_SESSION_MANDATE_COST))


static func export_bridged() -> Dictionary:
	ensure_loaded()
	return _bridged.duplicate()


static func apply_bridged(saved: Dictionary) -> void:
	ensure_loaded()
	for key in saved.keys():
		if _edges.has(str(key)):
			_bridged[str(key)] = bool(saved[key])
