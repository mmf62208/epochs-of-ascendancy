extends SceneTree

## BAVARIA-1 terrain bars on the committed world_accurate JSON.
## T3 (generator byte-identity and source mutants) lives in
## tools/map_generation/tests/test_bavaria1_terrain_keywords.py.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessBavaria1TerrainTest.gd

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const LAYER_PATH := "res://data/provinces_world_accurate/province_terrain_layer.json"
const ALPINE_PATH := "res://tools/map_generation/data/alpine_nuts3.txt"
const PROVINCE_COUNT := 3536

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessBavaria1TerrainTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessBavaria1TerrainTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok: bool = _failures == 0
	print("HeadlessBavaria1TerrainTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessBavaria1TerrainTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


func _load_json(path: String) -> Variant:
	var text := _read_text(path)
	if text.is_empty():
		_fail("missing " + path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("bad json " + path)
		return null
	return parsed


func _alpine_codes() -> Dictionary:
	var out: Dictionary = {}
	for raw in _read_text(ALPINE_PATH).split("\n"):
		var line := raw.split("#")[0].strip_edges()
		if line.is_empty():
			continue
		var parts := line.split(" ", false)
		var code := str(parts[0]).to_upper()
		var kind := "mountains"
		if parts.size() > 1:
			kind = str(parts[1]).to_lower()
		out[code] = kind
	return out


func _word_char(c: int) -> bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)


func _andes_is_false(low: String) -> bool:
	var i := low.find("andes")
	if i < 0:
		return false
	var before_ok := i == 0 or not _word_char(low.unicode_at(i - 1))
	var after := i + 5
	var after_ok := after >= low.length() or not _word_char(low.unicode_at(after))
	return not (before_ok and after_ok)


func _run() -> void:
	var base_v: Variant = _load_json(BASE_PATH)
	var layer_v: Variant = _load_json(LAYER_PATH)
	if base_v == null or layer_v == null:
		return
	var base: Dictionary = base_v
	var layer: Dictionary = layer_v
	if str(base.keys()) != '["provinces"]' and not (base.keys().size() == 1 and base.has("provinces")):
		_fail("base gained keys")
	if not (layer.keys().size() == 1 and layer.has("provinces")):
		_fail("terrain layer gained keys")
	var provs: Array = base.get("provinces", [])
	var layer_rows: Dictionary = layer.get("provinces", {})
	if provs.size() != PROVINCE_COUNT or layer_rows.size() != PROVINCE_COUNT:
		_fail("province count %d layer %d" % [provs.size(), layer_rows.size()])
		return
	var alpine := _alpine_codes()
	if alpine.is_empty():
		_fail("alpine_nuts3.txt empty")
		return
	var by_nuts: Dictionary = {}
	var berg_bad: Array = []
	var seen: Dictionary = {}
	for p_v in provs:
		if typeof(p_v) != TYPE_DICTIONARY:
			_fail("province row not a dict")
			return
		var p: Dictionary = p_v
		var pid := int(p.get("id", 0))
		var key := str(pid)
		if seen.has(pid):
			_fail("duplicate pid %d" % pid)
		seen[pid] = true
		if not layer_rows.has(key):
			_fail("terrain layer missing %d" % pid)
			continue
		var row_v: Variant = layer_rows[key]
		if typeof(row_v) != TYPE_DICTIONARY:
			_fail("terrain row not a dict %d" % pid)
			continue
		var row: Dictionary = row_v
		if row.keys().size() != 2 or not row.has("terrain") or not row.has("domain"):
			_fail("terrain row keys changed %d" % pid)
		if str(row.get("terrain", "")) != str(p.get("terrain", "")):
			_fail("base/layer terrain disagree %d" % pid)
		var nuts := str(p.get("nuts_id", "")).to_upper()
		if not nuts.is_empty():
			by_nuts[nuts] = p
		var terr := str(p.get("terrain", ""))
		var low := str(p.get("name", "")).to_lower()
		if terr == "mountains" and ("berg" in low or _andes_is_false(low)) and not alpine.has(nuts):
			berg_bad.append(str(p.get("name", "")))
	if seen.size() != PROVINCE_COUNT:
		_fail("pid set size %d" % seen.size())
	if not berg_bad.is_empty():
		_fail("berg/andes-only mountains: %s" % str(berg_bad))
	else:
		_pass("T1 no berg/andes-only mountains")
	for pair in [[710224, "Starnberg"], [710217, "Landsberg"], [710290, "Aichach-Friedberg"], [710265, "Nürnberg"], [710177, "Heidelberg"], [710876, "Bergamo"], [710760, "Landes"], [710367, "Hameln-Pyrmont"]]:
		var pid2: int = int(pair[0])
		var row2: Dictionary = layer_rows[str(pid2)]
		if str(row2.get("terrain", "")) == "mountains":
			_fail("%s still mountains" % str(pair[1]))
	for pair3 in [[710216, "Garmisch-Partenkirchen"], [710208, "Berchtesgadener Land"], [710299, "Oberallgäu"]]:
		var pid3: int = int(pair3[0])
		var row3: Dictionary = layer_rows[str(pid3)]
		if str(row3.get("terrain", "")) != "mountains":
			_fail("%s not mountains (%s)" % [str(pair3[1]), str(row3.get("terrain", ""))])
	for nuts2 in ["AT333", "AT334", "AT335", "CH012", "CH056", "FRK27", "FRK28", "DE21N", "DE21M"]:
		if not by_nuts.has(nuts2):
			_fail("missing nuts %s" % nuts2)
			continue
		var pr: Dictionary = by_nuts[nuts2]
		if str(pr.get("terrain", "")) != "mountains":
			_fail("%s not mountains" % nuts2)
	if _failures == 0:
		_pass("T2 alpine rim and Tirol/Valais/Graubünden/Savoie are mountains")
		_pass("T4 pid set %d, no new keys" % PROVINCE_COUNT)
