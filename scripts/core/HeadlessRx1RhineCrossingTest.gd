extends SceneTree

## RX-1 Rhine Crossing: edge penalties, bridged vs unbridged ETA/attack,
## shared-border guard (not kNN), and Build Bridge start→complete.
## Must FAIL on 1d092a14 (APIs / spec missing) and PASS on the RX-1 tip.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRx1RhineCrossingTest.gd

const SRC_RULES := "res://scripts/map/Rx1RhineCrossing.gd"
const SRC_LAYER := "res://scripts/map/Rx1RhineLayer.gd"
const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_MOVE := "res://scripts/formations/FormationMovement.gd"
const SRC_COMBAT := "res://scripts/combat/CombatResolver.gd"
const SRC_BATTLE := "res://scripts/combat/BattleManager.gd"
const SRC_SUPPLY := "res://scripts/supply/SupplyPathfinder.gd"
const SRC_SPEC := "res://data/map/rx1_rhine_crossings.json"
const NEUSS_ID := 710413
const METTMANN_ID := 710412
const DUSSELDORF_ID := 710401
const KOELN_ID := 710417
const ESSEN_ID := 710403

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRx1RhineCrossingTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRx1RhineCrossingTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessRx1RhineCrossingTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRx1RhineCrossingTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_needles()
	_test_named_constants()
	_test_edge_penalties_and_eta()
	_test_shared_border_not_knn()
	_test_bridge_start_to_complete()
	_test_inspector_and_battle_copy()


func _test_source_needles() -> void:
	var rules := _read(SRC_RULES)
	var layer := _read(SRC_LAYER)
	var idm := _read(SRC_IDM)
	var ren := _read(SRC_REN)
	var move := _read(SRC_MOVE)
	var combat := _read(SRC_COMBAT)
	var battle := _read(SRC_BATTLE)
	var supply := _read(SRC_SUPPLY)
	if "RHINE_UNBRIDGED_MOVE_MULT" not in rules or "func move_mult" not in rules or "func attack_malus" not in rules:
		_fail("Rx1RhineCrossing missing named constants / move_mult / attack_malus")
		return
	if "class_name Rx1RhineLayer" not in layer or "func _draw" not in layer:
		_fail("Rx1RhineLayer missing _draw vector path")
		return
	if "try_start_rhine_bridge" not in idm or "start_rhine_bridge_project" not in idm or "should_show_build_bridge_button" not in idm:
		_fail("IDM missing Build Bridge pipeline")
		return
	if "BtnBuildRhineBridge" not in ren or "_on_build_rhine_bridge_pressed" not in ren or "Rhine crossing:" not in ren:
		_fail("MapRenderer missing Build Bridge chrome / inspector copy")
		return
	if "rx1_move_mult" not in move:
		_fail("FormationMovement missing rx1_move_mult hop hook")
		return
	if "rx1_attack_malus" not in combat:
		_fail("CombatResolver missing rx1_attack_malus")
		return
	if "rhine_attack_malus" not in battle:
		_fail("BattleManager missing rhine_attack_malus preview")
		return
	if "rx1_move_mult" not in supply:
		_fail("SupplyPathfinder missing rx1_move_mult")
		return
	_pass("shipped API needles present")


func _test_named_constants() -> void:
	Rx1RhineCrossing.ensure_loaded()
	var c: Dictionary = Rx1RhineCrossing.constants()
	if absf(float(c.get("RHINE_UNBRIDGED_MOVE_MULT", 0.0)) - 2.0) > 0.001:
		_fail("RHINE_UNBRIDGED_MOVE_MULT != 2.0")
		return
	if absf(float(c.get("RHINE_BRIDGED_MOVE_MULT", 0.0)) - 1.15) > 0.001:
		_fail("RHINE_BRIDGED_MOVE_MULT != 1.15")
		return
	if absf(float(c.get("RHINE_UNBRIDGED_ATTACK_MALUS", 0.0)) - 0.30) > 0.001:
		_fail("RHINE_UNBRIDGED_ATTACK_MALUS != 0.30")
		return
	if absf(float(c.get("RHINE_BRIDGED_ATTACK_MALUS", 0.0)) - 0.10) > 0.001:
		_fail("RHINE_BRIDGED_ATTACK_MALUS != 0.10")
		return
	_pass("named constants 2.0 / 1.15 / 0.30 / 0.10")


func _test_edge_penalties_and_eta() -> void:
	Rx1RhineCrossing.reset_to_1936()
	if not Rx1RhineCrossing.is_crossing(NEUSS_ID, METTMANN_ID):
		_fail("Neuss–Mettmann is not a listed crossing")
		return
	if Rx1RhineCrossing.is_bridged(NEUSS_ID, METTMANN_ID):
		_fail("Neuss–Mettmann must start unbridged (Build Bridge target)")
		return
	if not Rx1RhineCrossing.is_bridged(NEUSS_ID, DUSSELDORF_ID):
		_fail("Neuss–Düsseldorf must seed bridged (Oberkasseler 1898)")
		return
	if Rx1RhineCrossing.is_crossing(KOELN_ID, ESSEN_ID):
		_fail("Köln–Essen must not be a listed crossing (kNN / non-touching)")
		return
	var un_move := Rx1RhineCrossing.move_mult(NEUSS_ID, METTMANN_ID)
	var br_move := Rx1RhineCrossing.move_mult(NEUSS_ID, DUSSELDORF_ID)
	if un_move <= br_move + 0.2:
		_fail("unbridged hop ×%.2f not longer than bridged ×%.2f" % [un_move, br_move])
		return
	var un_atk := Rx1RhineCrossing.attack_malus(NEUSS_ID, METTMANN_ID)
	var br_atk := Rx1RhineCrossing.attack_malus(NEUSS_ID, DUSSELDORF_ID)
	if un_atk <= br_atk:
		_fail("unbridged attack malus %.2f not worse than bridged %.2f" % [un_atk, br_atk])
		return
	var mm: Node = _autoload("MapManager")
	if mm != null and mm.has_method("rx1_move_mult"):
		if absf(float(mm.call("rx1_move_mult", NEUSS_ID, METTMANN_ID)) - 2.0) > 0.001:
			_fail("MapManager.rx1_move_mult unbridged != 2.0")
			return
		if absf(float(mm.call("rx1_attack_malus", NEUSS_ID, DUSSELDORF_ID)) - 0.10) > 0.001:
			_fail("MapManager.rx1_attack_malus bridged != 0.10")
			return
	_pass("unbridged hop ×2.0 / attack −30%% vs bridged ×1.15 / −10%%; Essen not a crossing")


func _test_shared_border_not_knn() -> void:
	if not FileAccess.file_exists(SRC_SPEC):
		_fail("rx1_rhine_crossings.json missing")
		return
	var raw := _read(SRC_SPEC)
	if "710413" not in raw or "face_bank_convention" not in raw:
		_fail("spec missing Neuss edge or face-bank convention")
		return
	if '"710417"' in raw and '"710403"' in raw:
		# Listed as a crossing pair would be a kNN leak. The control id is allowed as a note.
		if raw.find("710417-710403") >= 0 or raw.find("[710417, 710403]") >= 0 or raw.find("[710403, 710417]") >= 0:
			_fail("spec lists Köln–Essen as a crossing (kNN leak)")
			return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("spec is not a dictionary")
		return
	var edges: Array = (parsed as Dictionary).get("edges", []) as Array
	if edges.size() < 4:
		_fail("spec has fewer than 4 crossing edges")
		return
	var unbridged := 0
	for row_v in edges:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if not bool(row.get("real_shared_border", false)):
			_fail("listed edge is not a real shared border: %s" % str(row.get("edge", [])))
			return
		if not bool(row.get("bridged_1936", true)):
			unbridged += 1
	if unbridged < 1:
		_fail("no unbridged 1936 seed for Build Bridge")
		return
	_pass("shared-border spec lists GISCO edges; Köln–Essen not a crossing; one unbridged seed")


func _test_bridge_start_to_complete() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null or not idm.has_method("simulate_rx1_bridge_start_to_complete"):
		_fail("simulate_rx1_bridge_start_to_complete missing")
		return
	Rx1RhineCrossing.reset_to_1936()
	var result: Dictionary = idm.call("simulate_rx1_bridge_start_to_complete", 50)
	print("  [DETAIL] rx1 start_to_complete ", result)
	if not bool(result.get("ok", false)) or not bool(result.get("bridged", false)):
		_fail("Build Bridge did not complete: %s" % str(result))
		return
	var states: Array = result.get("visual_states", []) as Array
	if states.size() < 3 or str(states[0]) != "queued" or str(states[1]) != "construction" or str(states[states.size() - 1]) != "built":
		_fail("visual states not queued→construction→built: %s" % str(states))
		return
	if not Rx1RhineCrossing.is_bridged(NEUSS_ID, METTMANN_ID):
		_fail("Neuss–Mettmann still unbridged after complete")
		return
	var after := Rx1RhineCrossing.move_mult(NEUSS_ID, METTMANN_ID)
	if absf(after - 1.15) > 0.001:
		_fail("completed crossing move_mult is %.2f not 1.15" % after)
		return
	_pass("Build Bridge queued→construction→built flips Neuss–Mettmann to bridged")


func _test_inspector_and_battle_copy() -> void:
	Rx1RhineCrossing.reset_to_1936()
	var lines: PackedStringArray = Rx1RhineCrossing.inspector_lines(NEUSS_ID)
	var joined := " ".join(lines)
	if "Rhine crossing:" not in joined:
		_fail("inspector_lines missing Rhine crossing:")
		return
	if "no bridge" not in joined and "bridged" not in joined:
		_fail("inspector_lines missing bridged / no bridge")
		return
	var un := Rx1RhineCrossing.battle_penalty_line(NEUSS_ID, METTMANN_ID)
	var br := Rx1RhineCrossing.battle_penalty_line(NEUSS_ID, DUSSELDORF_ID)
	if "no bridge" not in un or "bridged" not in br:
		_fail("battle penalty lines missing: un=%s br=%s" % [un, br])
		return
	_pass("inspector + battle preview copy names bridged / no bridge")
