extends SceneTree

## NATION-TAGS-1. Parses board JSON only (no scenario boot, seed-neutral).
## Tags UKR / MDA / PRC / MAN resolve, 1936 owners of those tags stay empty,
## 1945 Poland owns every cc=PL province, and gap ids 905849–905869 exist
## with symmetric adjacency and the era owners below.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessNationTags1Test.gd

const ERAS: Array[int] = [1910, 1918, 1936, 1945, 2026]
const NEW_TAGS: Array[String] = ["UKR", "MDA", "PRC", "MAN"]

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessNationTags1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessNationTags1Test: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessNationTags1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessNationTags1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _read_text(res_path: String) -> String:
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return ""
	return FileAccess.get_file_as_string(abs_path)


func _read_json(res_path: String) -> Variant:
	var text := _read_text(res_path)
	if text.is_empty():
		_fail("missing " + res_path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_fail("json " + res_path)
	return parsed


func _gap_table() -> Array:
	return [
		{"id": 905849, "name": "Kiev", "owners": ["RUS", "UKR", "SOV", "SOV", "UKR"]},
		{"id": 905850, "name": "Odessa", "owners": ["RUS", "UKR", "SOV", "SOV", "UKR"]},
		{"id": 905851, "name": "Kharkiv", "owners": ["RUS", "UKR", "SOV", "SOV", "UKR"]},
		{"id": 905852, "name": "Dnipropetrovsk", "owners": ["RUS", "UKR", "SOV", "SOV", "UKR"]},
		{"id": 905853, "name": "Crimean ASSR", "owners": ["RUS", "UKR", "SOV", "SOV", "UKR"]},
		{"id": 905854, "name": "Lviv", "owners": ["AUS", "POL", "POL", "SOV", "UKR"]},
		{"id": 905855, "name": "Lutsk", "owners": ["RUS", "POL", "POL", "SOV", "UKR"]},
		{"id": 905856, "name": "Chernivtsi", "owners": ["AUS", "ROM", "ROM", "SOV", "UKR"]},
		{"id": 905857, "name": "Chisinau", "owners": ["RUS", "ROM", "ROM", "SOV", "MDA"]},
		{"id": 905858, "name": "Harbin", "owners": ["CHI", "CHI", "CHI", "MAN", "PRC"]},
		{"id": 905859, "name": "Changchun", "owners": ["CHI", "CHI", "CHI", "MAN", "PRC"]},
		{"id": 905860, "name": "Qiqihar", "owners": ["CHI", "CHI", "CHI", "MAN", "PRC"]},
		{"id": 905861, "name": "Hailar", "owners": ["CHI", "CHI", "CHI", "MAN", "PRC"]},
		{"id": 905862, "name": "Chongqing", "owners": ["CHI", "CHI", "CHI", "CHI", "PRC"]},
		{"id": 905863, "name": "Guangzhou", "owners": ["CHI", "CHI", "CHI", "CHI", "PRC"]},
		{"id": 905864, "name": "Chengdu", "owners": ["CHI", "CHI", "CHI", "CHI", "PRC"]},
		{"id": 905865, "name": "Fuzhou", "owners": ["CHI", "CHI", "CHI", "CHI", "PRC"]},
		{"id": 905866, "name": "Zhengzhou", "owners": ["CHI", "CHI", "CHI", "CHI", "PRC"]},
		{"id": 905867, "name": "Taiyuan", "owners": ["CHI", "CHI", "CHI", "CHI", "PRC"]},
		{"id": 905868, "name": "Guiyang", "owners": ["CHI", "CHI", "CHI", "CHI", "PRC"]},
		{"id": 905869, "name": "Hohhot", "owners": ["CHI", "CHI", "CHI", "CHI", "PRC"]},
	]


func _run() -> void:
	var catalog = _read_json("res://data/nations/nation_tags1.json")
	var loader := _read_text("res://scripts/core/ScenarioLoader.gd")
	var labels := _read_text("res://scripts/map/MapPoliticalLabelsLayer.gd")
	var scenario := _read_text("res://data/scenarios/world_accurate.json")
	var names := {
		"UKR": "Ukraine",
		"MDA": "Moldova",
		"PRC": "People's Republic of China",
		"MAN": "Manchukuo",
	}
	var colors := {
		"UKR": "#005BBB",
		"MDA": "#003DA5",
		"PRC": "#DE2910",
		"MAN": "#FFDE00",
	}
	if catalog is Dictionary:
		var rows: Array = (catalog as Dictionary).get("tags", [])
		var by_tag := {}
		for row in rows:
			if row is Dictionary:
				by_tag[str(row.get("tag", ""))] = row
		for tag in NEW_TAGS:
			var row: Variant = by_tag.get(tag)
			if not (row is Dictionary):
				_fail("catalog missing " + tag)
			elif str(row.get("name", "")) != str(names[tag]) or str(row.get("color", "")) != str(colors[tag]):
				_fail("catalog fields " + tag)
			else:
				_pass("catalog " + tag)
			var flag_name := tag.to_lower() + ".png"
			var flag_path := ProjectSettings.globalize_path("res://data/nations/flags/" + flag_name)
			if not FileAccess.file_exists(flag_path) or FileAccess.get_file_as_bytes(flag_path).size() < 32:
				_fail("flag " + flag_name)
			else:
				_pass("flag " + flag_name)
	for tag in NEW_TAGS:
		var needle := '"%s": "%s"' % [tag, str(names[tag])]
		if loader.find(needle) < 0:
			_fail("ScenarioLoader missing " + needle)
		elif loader.find(str(colors[tag])) < 0:
			_fail("ScenarioLoader missing color " + tag)
		else:
			_pass("loader " + tag)
		if labels.find(needle) < 0:
			_fail("labels missing " + needle)
		else:
			_pass("label " + tag)
		if scenario.find('"tag": "%s"' % tag) >= 0:
			_fail("world_accurate.json country " + tag)
	var base = _read_json("res://data/provinces_world_accurate/provinces_base.json")
	var adj_doc = _read_json("res://data/provinces_world_accurate/province_adjacency.json")
	if not (base is Dictionary) or not (adj_doc is Dictionary):
		return
	var provinces: Array = (base as Dictionary).get("provinces", [])
	var by_id := {}
	var pl_ids: Array[int] = []
	var ee_id := -1
	for p in provinces:
		if not (p is Dictionary):
			continue
		var pid := int(p.get("id", 0))
		by_id[pid] = p
		var cc := str(p.get("cntr_code", "")).to_upper()
		if cc == "PL":
			pl_ids.append(pid)
		elif cc == "EE" and ee_id < 0:
			ee_id = pid
	var own := {}
	for year in ERAS:
		var doc = _read_json("res://data/provinces_world_accurate/province_ownership_%s.json" % year)
		if doc is Dictionary:
			own[year] = (doc as Dictionary).get("owners", {})
		else:
			own[year] = {}
	var owners_1936: Dictionary = own[1936]
	for tag in NEW_TAGS:
		var n := 0
		for key in owners_1936.keys():
			if str(owners_1936[key]) == tag:
				n += 1
		if n != 0:
			_fail("1936 %s owns %d" % [tag, n])
		else:
			_pass("1936 %s owns 0" % tag)
	var owners_1945: Dictionary = own[1945]
	if str(owners_1936.get("711112", "")) != "POL" or str(owners_1945.get("711112", "")) != "POL":
		_fail("Warsaw 711112 1936/1945 %s/%s" % [str(owners_1936.get("711112", "")), str(owners_1945.get("711112", ""))])
	else:
		_pass("Warsaw POL in 1936 and 1945")
	if str(owners_1936.get("711074", "")) != "GER" or str(owners_1945.get("711074", "")) != "POL":
		_fail("711074 1936/1945 %s/%s" % [str(owners_1936.get("711074", "")), str(owners_1945.get("711074", ""))])
	else:
		_pass("711074 GER in 1936 and POL in 1945")
	if pl_ids.size() != 73:
		_fail("cc=PL count %d" % pl_ids.size())
	var pol_n := 0
	for pid in pl_ids:
		if str(owners_1945.get(str(pid), "")) == "POL":
			pol_n += 1
	if pol_n != pl_ids.size():
		_fail("1945 POL on cc=PL %d/%d" % [pol_n, pl_ids.size()])
	else:
		_pass("1945 POL on all cc=PL provinces")
	if ee_id < 0 or str(owners_1945.get(str(ee_id), "")) != "SOV":
		_fail("1945 EE %s not SOV" % ee_id)
	else:
		_pass("1945 EE stays SOV")
	var adj: Dictionary = (adj_doc as Dictionary).get("adjacency", {})
	var mem = _read_json("res://data/provinces_world_accurate/hierarchy_membership_1936.json")
	var p2r: Dictionary = {}
	if mem is Dictionary:
		p2r = (mem as Dictionary).get("province_to_region", {})
	for spec in _gap_table():
		var pid := int(spec["id"])
		var row: Variant = by_id.get(pid)
		if not (row is Dictionary):
			_fail("missing province %s" % pid)
			continue
		if str(row.get("name", "")) != str(spec["name"]):
			_fail("%s name %s" % [pid, str(row.get("name", ""))])
		if str(row.get("domain", "")) != "land":
			_fail("%s not land" % pid)
		var expect: Array = spec["owners"]
		for i in ERAS.size():
			var year: int = ERAS[i]
			var got := str((own[year] as Dictionary).get(str(pid), ""))
			if got != str(expect[i]):
				_fail("%s era %s owner %s != %s" % [pid, year, got, str(expect[i])])
		if int(p2r.get(str(pid), 0)) <= 0:
			_fail("%s missing 1936 region" % pid)
		var nbrs: Array = adj.get(str(pid), [])
		if nbrs.is_empty():
			_fail("%s adjacency empty" % pid)
		else:
			var symmetric := true
			for n in nbrs:
				var back: Array = adj.get(str(int(n)), [])
				var linked := false
				for entry in back:
					if int(entry) == pid:
						linked = true
						break
				if not linked:
					symmetric = false
					_fail("%s adjacency not symmetric with %s" % [pid, str(int(n))])
					break
			if symmetric:
				_pass("%s owners and adjacency" % pid)
	if _failures == 0:
		_pass("gaps 905849-905869")
