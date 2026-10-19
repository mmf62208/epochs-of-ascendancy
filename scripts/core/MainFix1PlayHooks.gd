# scripts/core/MainFix1PlayHooks.gd
## Dev-only Play hooks for MAIN-FIX-1. Off unless an env flag is set.
##
##   EOA_MAIN_FIX1_FORCE_CAPTURE=1  — GER takes one POL border province through
##     BattleManager._apply_attacker_win_capture_light (the live capture path).
##   EOA_MAIN_FIX1_PEACE_HOLD_S=600 — open the campaign peace sheet and keep
##     the window alive at least that many seconds.
##
## Wired from TestRunner after living chips. Never on by default.
class_name MainFix1PlayHooks
extends RefCounted


static func maybe_run(host: Node = null) -> void:
	var capture_on := OS.get_environment("EOA_MAIN_FIX1_FORCE_CAPTURE").strip_edges() == "1"
	var hold_raw := OS.get_environment("EOA_MAIN_FIX1_PEACE_HOLD_S").strip_edges()
	var hold_s := int(hold_raw) if hold_raw.is_valid_int() else 0
	if not capture_on and hold_s <= 0:
		return
	print(
		"MAIN_FIX1_HOOK who=MainFix1PlayHooks.maybe_run capture=%s hold_s=%d"
		% ["1" if capture_on else "0", hold_s]
	)
	if capture_on:
		_force_real_capture()
	if hold_s > 0:
		_open_peace_hold(host, hold_s)


static func _force_real_capture() -> Dictionary:
	var mm: Node = _autoload("MapManager")
	var bm: Node = _autoload("BattleManager")
	if mm == null or bm == null or not bm.has_method("_apply_attacker_win_capture_light"):
		print("MAIN_FIX1_HOOK who=force_capture fail=missing_managers")
		return {"ok": false, "reason": "missing managers"}
	var to_id := _border_to(mm, "GER", "POL")
	var from_id := _border_from(mm, "GER", "POL")
	if to_id <= 0 or from_id <= 0:
		print("MAIN_FIX1_HOOK who=force_capture fail=no_border")
		return {"ok": false, "reason": "no GER-POL border"}
	var before_owner := _owner_of(mm, to_id)
	print(
		"MAIN_FIX1_HOOK who=force_capture path=BattleManager._apply_attacker_win_capture_light to=%d from=%d before_owner=%s"
		% [to_id, from_id, before_owner]
	)
	bm.call("_apply_attacker_win_capture_light", "GER", to_id, from_id, "")
	var after_owner := _owner_of(mm, to_id)
	print(
		"MAIN_FIX1_HOOK who=force_capture after_owner=%s flipped=%s"
		% [after_owner, str(after_owner == "GER" and before_owner != "GER")]
	)
	return {
		"ok": after_owner == "GER",
		"to_id": to_id,
		"from_id": from_id,
		"before_owner": before_owner,
		"after_owner": after_owner,
	}


static func _open_peace_hold(host: Node, hold_s: int) -> void:
	var secs := maxi(hold_s, 600)
	print("MAIN_FIX1_HOOK who=peace_hold open_s=%d" % secs)
	if typeof(PeaceConferenceWindow) == TYPE_NIL:
		print("MAIN_FIX1_HOOK who=peace_hold fail=no_window")
		return
	var opened: Dictionary = PeaceConferenceWindow.open_living_sheet(
		"GER",
		"LUX",
		710977,
		{"campaign": true, "outcome_default": "annex_all", "loser": "LUX", "leader": "GER"},
	)
	print("MAIN_FIX1_HOOK who=peace_hold opened=%s" % str(opened))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		if host != null and host.get_tree() != null:
			tree = host.get_tree()
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(float(secs))
	if timer != null:
		timer.timeout.connect(func() -> void:
			print("MAIN_FIX1_HOOK who=peace_hold hold_done_s=%d" % secs)
		)


static func _autoload(node_name: String) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(node_name)


static func _owner_of(mm: Node, pid: int) -> String:
	if mm == null or not mm.has_method("get_province"):
		return ""
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


static func _border_from(mm: Node, att: String, defender: String) -> int:
	if mm == null or not mm.has_method("get_provinces_by_owner"):
		return -1
	var owned: Array = mm.call("get_provinces_by_owner", att)
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
		nbrs.sort()
		for nid_v in nbrs:
			var n: Object = mm.call("get_province", int(nid_v))
			if n == null or bool(n.get("is_sea")):
				continue
			if str(n.get("owner_tag")).strip_edges().to_upper() == defender:
				return pid
	return -1


static func _border_to(mm: Node, att: String, defender: String) -> int:
	if mm == null or not mm.has_method("get_provinces_by_owner"):
		return -1
	var owned: Array = mm.call("get_provinces_by_owner", att)
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
		nbrs.sort()
		for nid_v in nbrs:
			var n: Object = mm.call("get_province", int(nid_v))
			if n == null or bool(n.get("is_sea")):
				continue
			if str(n.get("owner_tag")).strip_edges().to_upper() == defender:
				return int(nid_v)
	return -1
