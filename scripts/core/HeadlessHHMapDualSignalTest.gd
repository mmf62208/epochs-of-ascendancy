extends SceneTree

## Headless: Hidden Hand monthly map feedback produces primary + secondary signals
## with distinct action classes; economic_pressure / sabotage apply map effects.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHHMapDualSignalTest.gd

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessHHMapDualSignalTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessHHMapDualSignalTest: ", msg)


func _run_and_quit() -> void:
	_run()
	print("HeadlessHHMapDualSignalTest: ", "PASS" if _failures == 0 else "FAIL", " (failures=", _failures, ")")
	quit(0 if _failures == 0 else 1)


func _run() -> void:
	var gd: Node = root.get_node_or_null("GameData")
	var mm: Node = root.get_node_or_null("MapManager")
	if gd == null or mm == null:
		_fail("GameData/MapManager missing")
		return
	if not gd.has_method("process_hh_monthly_map_feedback"):
		_fail("process_hh_monthly_map_feedback missing")
		return
	# Ensure peace state + high hand influence so economic/sabotage can fire.
	if gd.has_method("_init_peace_state_if_needed"):
		gd.call("_init_peace_state_if_needed")
	var ps: Dictionary = gd.get_peace_state() if gd.has_method("get_peace_state") else {}
	if not ps.has("hand_influence"):
		ps["hand_influence"] = {}
	var hi: Dictionary = ps["hand_influence"]
	hi["HIDDEN_HAND"] = 0.55
	ps["hand_influence"] = hi
	if "peace_state" in gd:
		gd.peace_state = ps

	# Month 3 → sabotage primary at high influence; secondary should complement.
	var sig: Dictionary = gd.process_hh_monthly_map_feedback(1936, 3)
	print("  [INFO] primary month3: ", sig)
	if not bool(sig.get("active", false)):
		_fail("primary signal not active")
		return
	if int(sig.get("province_id", -1)) < 0:
		_fail("primary province_id invalid")
		return
	var action := str(sig.get("action_class", ""))
	if action.is_empty():
		_fail("primary action_class empty")
		return
	_pass("primary signal active action=%s pid=%d" % [action, int(sig.get("province_id", -1))])

	var ps2: Dictionary = gd.get_peace_state() if gd.has_method("get_peace_state") else {}
	var sec: Dictionary = ps2.get("hh_secondary_map_signal", {}) if ps2 is Dictionary else {}
	print("  [INFO] secondary: ", sec)
	if not bool(sec.get("active", false)):
		_fail("secondary signal not active")
		return
	var sec_action := str(sec.get("action_class", ""))
	if sec_action.is_empty():
		_fail("secondary action_class empty")
		return
	if sec_action == action:
		_fail("secondary action should differ from primary (%s)" % action)
		return
	if int(sec.get("province_id", -1)) == int(sig.get("province_id", -1)):
		_fail("secondary should target different province")
		return
	_pass("secondary signal active action=%s pid=%d (≠ primary)" % [sec_action, int(sec.get("province_id", -1))])

	# Month 4 → economic_pressure at high influence
	var sig_econ: Dictionary = gd.process_hh_monthly_map_feedback(1936, 4)
	print("  [INFO] primary month4: ", sig_econ)
	var a4 := str(sig_econ.get("action_class", ""))
	# With hand 0.55 and month%3==1 → economic_pressure
	if a4 != "economic_pressure" and a4 != "propaganda" and a4 != "influence" and a4 != "black_market" and a4 != "sabotage" and a4 != "infiltration":
		_fail("month4 unexpected action %s" % a4)
		return
	if a4 == "economic_pressure":
		_pass("month4 economic_pressure fired map_effect=%s" % str(sig_econ.get("map_effect", "")))
	else:
		_pass("month4 action=%s (still valid HH class)" % a4)

	# Helpers pure path
	var Helpers = load("res://scripts/map/MapNextListHelpers.gd")
	if Helpers != null and Helpers.has_method("pick_hh_secondary_action_class"):
		var sec_pick: String = str(Helpers.pick_hh_secondary_action_class(3, 0.5, "sabotage"))
		# Complementary map-visible classes: economic_pressure or infiltration (third fingerprint)
		if sec_pick != "economic_pressure" and sec_pick != "infiltration":
			_fail("pick_hh_secondary sabotage→expected economic_pressure|infiltration got %s" % sec_pick)
			return
		_pass("pick_hh_secondary sabotage→%s" % sec_pick)
	else:
		_fail("pick_hh_secondary_action_class missing")
