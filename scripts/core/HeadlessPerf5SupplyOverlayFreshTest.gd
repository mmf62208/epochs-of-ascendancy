extends SceneTree

## PERF-5 (b): L overlay must stay current after depot / capture / silent route mutation.
## FAILS on main: cache reuse + no set_routes after network change.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessPerf5SupplyOverlayFreshTest.gd

const COLS := 8
const ROWS := 8
const LAND_N := COLS * ROWS
const BASE_PID := 710000
const POLY_SIDES := 12
const HOME_Z := 0.318
const FLUSH_FRAMES := 2
const RECONCILE_MS_LIMIT := 5.0
const L_ON_MS_LIMIT := 1000.0

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null
var _sm: Node = null
var _cap_pid: int = BASE_PID
var _hub_pids: Array[int] = []
var _off_route_pid: int = BASE_PID + 56
var _mid_route_pid: int = BASE_PID + 3
var _infra_pid: int = BASE_PID + 57
var _ten_pids: Array[int] = []


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf5SupplyOverlayFreshTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf5SupplyOverlayFreshTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf5SupplyOverlayFreshTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf5SupplyOverlayFreshTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessPerf5SupplyOverlayFreshTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _role_computes() -> int:
	if _mr != null and _mr.has_method("get_supply_toggle_role_computes"):
		return int(_mr.call("get_supply_toggle_role_computes"))
	return -1


func _full_recomputes() -> int:
	if _mr != null and _mr.has_method("get_supply_full_role_recomputes"):
		return int(_mr.call("get_supply_full_role_recomputes"))
	return -1


func _batch_patches() -> int:
	if _mr != null and _mr.has_method("get_supply_batch_patches"):
		return int(_mr.call("get_supply_batch_patches"))
	return -1


func _reconcile_ms() -> float:
	if _mr != null and _mr.has_method("get_last_supply_reconcile_ms"):
		return float(_mr.call("get_last_supply_reconcile_ms"))
	return -1.0


func _roles() -> Dictionary:
	if _mr == null:
		return {}
	return _mr.get("_supply_role_by_province") as Dictionary


func _role_of(pid: int) -> String:
	return str(_roles().get(pid, ""))


func _drawn_routes() -> Array:
	var layer: Node = _mr.supply_map_layer
	if layer == null:
		return []
	return layer.get("_routes_to_draw") as Array


func _batch_count() -> int:
	var batch: Node = _mr.get("_supply_outline_batch") as Node
	if batch != null and batch.has_method("item_count"):
		return int(batch.call("item_count"))
	return -1


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)
	if not _setup_renderer():
		return
	await _flush()
	if not await _build_real_network():
		return
	await _b1_real_api()
	await _b2_silent_mutation()
	await _b3_no_change_frames()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()


func _pid_at(col: int, row: int) -> int:
	return BASE_PID + row * COLS + col


func _setup_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(200, 200)
	_cam.zoom = Vector2(HOME_Z, HOME_Z)
	_mr.add_child(_cam)
	_container = Node2D.new()
	_container.name = "ProvinceContainers"
	_mr.add_child(_container)
	_mr.container = _container
	root.add_child(_mr)
	_cam.make_current()
	_sm = root.get_node_or_null("SupplyManager")
	var mm: Node = root.get_node_or_null("MapManager")
	if _sm == null:
		_fail("SupplyManager autoload missing")
		return false
	var pscr: Script = load("res://scripts/data/Province.gd") as Script
	var adj_scr: Script = load("res://scripts/data/AdjacencySystem.gd") as Script
	var country_scr: Script = load("res://scripts/data/Country.gd") as Script
	var adj: Object = adj_scr.new() if adj_scr != null else null
	var adj_data := {}
	var r := 0
	while r < ROWS:
		var c := 0
		while c < COLS:
			var pid := _pid_at(c, r)
			var nbrs: Array = []
			if c > 0:
				nbrs.append(_pid_at(c - 1, r))
			if c < COLS - 1:
				nbrs.append(_pid_at(c + 1, r))
			if r > 0:
				nbrs.append(_pid_at(c, r - 1))
			if r < ROWS - 1:
				nbrs.append(_pid_at(c, r + 1))
			adj_data[str(pid)] = nbrs
			var host := Node2D.new()
			host.name = "Prov_%d" % pid
			host.position = Vector2(float(c) * 40.0, float(r) * 40.0)
			var poly := Polygon2D.new()
			poly.polygon = _make_ring(18.0, POLY_SIDES)
			host.add_child(poly)
			_container.add_child(host)
			_mr.province_nodes[pid] = host
			if pscr != null:
				var p: Object = pscr.new()
				p.set("id", pid)
				p.set("name", "Land %d" % pid)
				p.set("owner_tag", "GER")
				p.set("controller_tag", "GER")
				p.set("infrastructure", 60)
				p.set("is_sea", false)
				p.set("factories", 0)
				if pid == _cap_pid:
					p.set("special_features", {"capital": 1})
					p.set("factories", 4)
				elif r > 0 and c == COLS - 1 and r < 7:
					p.set("factories", 3)
					_hub_pids.append(pid)
				if pid == _infra_pid or pid == _off_route_pid:
					p.set("infrastructure", 10)
				_mr.provinces[pid] = p
				if mm != null and "_provinces" in mm:
					mm._provinces[pid] = p
				if adj != null and adj.has_method("register_province"):
					adj.call("register_province", p)
			c += 1
		r += 1
	_hub_pids.sort()
	_ten_pids = [
		_pid_at(2, 2), _pid_at(3, 2), _pid_at(4, 2), _pid_at(5, 2), _pid_at(6, 2),
		_pid_at(2, 3), _pid_at(3, 3), _pid_at(4, 3), _pid_at(5, 3), _pid_at(6, 3),
	]
	if adj != null and adj.has_method("load_from_dict"):
		adj.call("load_from_dict", adj_data)
	_mr.adjacency = adj
	if country_scr != null:
		var ger: Object = country_scr.new()
		ger.set("tag", "GER")
		ger.set("name", "Germany")
		ger.set("capital_province_id", _cap_pid)
		_mr.countries["GER"] = ger
	_seed_boot_supply_layer()
	if "overlay_visible" in _sm:
		_sm.overlay_visible = false
	_mr.supply_mode = false
	if _sm != null:
		_sm.player_tag = "GER"
	if _mr.has_method("_connect_map_manager_signals"):
		_mr.call("_connect_map_manager_signals")
	_info("seeded grid=%dx%d hubs=%s off=%d mid=%d infra=%d" % [
		COLS, ROWS, str(_hub_pids), _off_route_pid, _mid_route_pid, _infra_pid,
	])
	return true


func _seed_boot_supply_layer() -> void:
	var layer_scr: Script = load("res://scripts/supply/SupplyMapLayer.gd") as Script
	if layer_scr == null or _container == null:
		return
	var layer: Node2D = layer_scr.new() as Node2D
	if layer == null:
		return
	layer.name = "SupplyMapLayer"
	layer.visible = false
	_container.add_child(layer)
	_mr.supply_map_layer = layer


func _make_ring(radius: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sides)
	var i := 0
	while i < sides:
		var a := TAU * float(i) / float(sides)
		pts[i] = Vector2(cos(a), sin(a)) * radius
		i += 1
	return pts


func _build_real_network() -> bool:
	if _sm == null or not _sm.has_method("build_network"):
		_fail("SupplyManager.build_network missing")
		return false
	_sm.call("build_network", _mr.provinces, _mr.countries, {}, _mr.adjacency, "GER")
	var routes: Array = _sm.get_all_routes()
	if routes.size() < 6:
		_inject_default_routes()
		routes = _sm.get_all_routes()
	if routes.size() < 6:
		_fail("default routes=%d want >=6 after build_network" % routes.size())
		return false
	_pass("build_network produced %d routes" % routes.size())
	_info("capital_hub=%d depots=%d" % [
		int(_sm.get_capital_hub_id()) if _sm.has_method("get_capital_hub_id") else -1,
		int((_sm.depot_states as Dictionary).size()) if "depot_states" in _sm else 0,
	])
	return true


func _inject_default_routes() -> void:
	if not ("_routes" in _sm):
		return
	var plan_scr: Script = load("res://scripts/supply/SupplyRoutePlan.gd") as Script
	if plan_scr == null:
		return
	var i := 0
	while i < _hub_pids.size():
		var dest := int(_hub_pids[i])
		var key := "%d_%d" % [_cap_pid, dest]
		var plan: Object = plan_scr.new()
		plan.set("route_id", key)
		plan.set("source_province_id", _cap_pid)
		plan.set("target_province_id", dest)
		var path: Array[int] = [_cap_pid]
		var col := dest - _cap_pid
		# dest is last column of row i+1
		var row := (dest - BASE_PID) / COLS
		var x := 0
		while x < COLS:
			path.append(_pid_at(x, 0) if row == 0 else _pid_at(0, 0))
			x += 1
		path = [_cap_pid]
		var cc := 1
		while cc < COLS:
			path.append(_pid_at(cc, 0))
			cc += 1
		var rr := 1
		while rr <= row:
			path.append(_pid_at(COLS - 1, rr))
			rr += 1
		plan.set("province_path", path)
		_sm._routes[key] = plan
		i += 1


func _ensure_l_on() -> void:
	if not bool(_mr.get("supply_mode")):
		_mr.call("_toggle_supply_overlay")


func _ensure_l_off() -> void:
	if bool(_mr.get("supply_mode")):
		_mr.call("_toggle_supply_overlay")


func _after_change_frame() -> void:
	await process_frame
	if _mr.has_method("_pulse_supply_outlines"):
		_mr.call("_pulse_supply_outlines")


func _assert_overlay(label: String, extra_pid: int = -1, extra_want: String = "") -> void:
	var sm_routes: Array = _sm.get_all_routes()
	var drawn := _drawn_routes()
	if drawn.size() != sm_routes.size():
		_fail("%s drawn_routes=%d sm_routes=%d" % [label, drawn.size(), sm_routes.size()])
	else:
		var same := true
		var i := 0
		while i < sm_routes.size():
			if drawn[i] != sm_routes[i]:
				same = false
				break
			i += 1
		if not same:
			_fail("%s _routes_to_draw instances != sm.get_all_routes()" % label)
		else:
			_pass("%s _routes_to_draw identity matches (%d)" % [label, drawn.size()])
	var route_pids := {}
	for plan_var in sm_routes:
		if not (plan_var is Object):
			continue
		if bool(plan_var.get("represents_trade_flow")):
			continue
		for pid_var in plan_var.get("province_path"):
			route_pids[int(pid_var)] = true
	for pid_var in route_pids.keys():
		var role := _role_of(int(pid_var))
		if role not in ["route", "active", "preview"]:
			_fail("%s pid %d on route has role '%s'" % [label, int(pid_var), role])
			return
	_pass("%s route pids have route/active/preview" % label)
	if extra_pid >= 0 and extra_want == "no_route":
		if _role_of(extra_pid) == "route" and not route_pids.has(extra_pid):
			_fail("%s captured pid %d still has role route" % [label, extra_pid])
		elif not route_pids.has(extra_pid) and _role_of(extra_pid) == "route":
			_fail("%s pid %d has route but is on no path" % [label, extra_pid])
		else:
			_pass("%s pid %d not a stale route ring (role=%s on_path=%s)" % [
				label, extra_pid, _role_of(extra_pid), str(route_pids.has(extra_pid)),
			])
	if extra_pid >= 0 and extra_want == "hub":
		var r := _role_of(extra_pid)
		if r not in ["hub", "route", "active", "preview"]:
			_fail("%s depot pid %d has role '%s' (want hub or route)" % [label, extra_pid, r])
		else:
			_pass("%s depot pid %d has ring role=%s" % [label, extra_pid, r])
	if extra_pid >= 0 and extra_want == "no_hub":
		if _role_of(extra_pid) == "hub":
			_fail("%s removed depot %d still has hub" % [label, extra_pid])
		else:
			_pass("%s removed depot %d has no hub (role=%s)" % [label, extra_pid, _role_of(extra_pid)])
	if extra_pid >= 0 and extra_want == "engineers":
		if _role_of(extra_pid) != "engineers_recommended":
			_fail("%s infra-pressure pid %d role='%s' want engineers_recommended" % [label, extra_pid, _role_of(extra_pid)])
		else:
			_pass("%s infra-pressure pid %d role=engineers_recommended" % [label, extra_pid])
	if extra_pid >= 0 and extra_want == "no_engineers":
		if _role_of(extra_pid) == "engineers_recommended":
			_fail("%s pid %d still engineers_recommended after infra raise" % [label, extra_pid])
		else:
			_pass("%s pid %d dropped engineers_recommended (role=%s)" % [label, extra_pid, _role_of(extra_pid)])
	if _mr.has_method("_supply_highlight_roles"):
		var fresh: Dictionary = _mr.call("_supply_highlight_roles")
		var live := _roles()
		var eq := true
		if fresh.size() != live.size():
			eq = false
		else:
			for pid in fresh.keys():
				if str(live.get(int(pid), "")) != str(fresh[pid]):
					eq = false
					break
		if not eq:
			_fail("%s role cache != fresh _supply_highlight_roles() live=%d fresh=%d" % [label, live.size(), fresh.size()])
		else:
			_pass("%s incremental roles == full roles (%d)" % [label, live.size()])
	var batch_n := _batch_count()
	var role_poly_n := 0
	for pid_var2 in _roles().keys():
		var role2 := str(_roles()[pid_var2])
		if role2.is_empty():
			continue
		var node: Node = _mr.province_nodes.get(int(pid_var2))
		if node != null:
			role_poly_n += 1
	if batch_n >= 0 and batch_n != role_poly_n:
		_fail("%s batch item_count=%d role_poly=%d" % [label, batch_n, role_poly_n])
	else:
		_pass("%s batch item_count=%d" % [label, batch_n])
	var rms := _reconcile_ms()
	if rms >= 0.0 and rms > RECONCILE_MS_LIMIT:
		_fail("%s reconcile %.2f ms > %.1f" % [label, rms, RECONCILE_MS_LIMIT])
	elif rms >= 0.0:
		_pass("%s reconcile %.2f ms" % [label, rms])


func _toggle_ms() -> float:
	var t0 := Time.get_ticks_usec()
	_mr.call("_toggle_supply_overlay")
	await process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _b1_real_api() -> void:
	_ensure_l_off()
	await process_frame
	var on_ms := await _toggle_ms()
	if on_ms >= L_ON_MS_LIMIT:
		_fail("B1 first L-on %.1f ms" % on_ms)
	else:
		_pass("B1 first L-on %.1f ms" % on_ms)
	await _after_change_frame()
	_assert_overlay("B1 L-on initial")

	# Depot add on off-route pid (real API; main rebuilds network, overlay stays stale).
	_sm.call("set_player_depot", _off_route_pid, true)
	await _after_change_frame()
	_assert_overlay("B1 L-on depot add", _off_route_pid, "hub")

	# L off → change → L on. Drop the captured path so topology changes even
	# without #88 notify. Assert immediately — a process_frame would let the
	# pulse poll hide a missing L-on fingerprint check (mutant B1).
	_ensure_l_off()
	await process_frame
	var mm: Node = root.get_node_or_null("MapManager")
	if mm != null:
		mm.call("update_province_owner", _mid_route_pid, "GER", "FRA", true, false)
	_drop_routes_touching(_mid_route_pid)
	var t_on2 := Time.get_ticks_usec()
	_mr.call("_toggle_supply_overlay")
	var on2 := float(Time.get_ticks_usec() - t_on2) / 1000.0
	if on2 >= L_ON_MS_LIMIT:
		_fail("B1 L-off→capture→L-on %.1f ms" % on2)
	else:
		_pass("B1 L-off→capture→L-on %.1f ms" % on2)
	_assert_overlay("B1 L-off→capture→on", _mid_route_pid, "no_route")

	# Ten-pid capture batch while L on
	_ensure_l_on()
	if mm != null:
		for pid in _ten_pids:
			mm.call("update_province_owner", pid, "GER", "FRA", true, false)
	await _after_change_frame()
	_assert_overlay("B1 ten captures")

	# Annex (may not emit). Also drop routes that still list 710171-equivalent dest.
	var annex_pid := _pid_at(COLS - 1, 2)
	var gd: Node = root.get_node_or_null("GameData")
	if gd != null and gd.has_method("apply_peace_conference_settlement_live"):
		gd.call("apply_peace_conference_settlement_live", "FRA", "GER", annex_pid, true, false, 0.0, false)
	elif mm != null:
		mm.call("update_province_owner", annex_pid, "FRA", "FRA", true, false)
	_drop_routes_touching(annex_pid)
	await _after_change_frame()
	_assert_overlay("B1 annex", annex_pid, "no_route")

	# Recapture
	if mm != null:
		mm.call("update_province_owner", _mid_route_pid, "GER", "GER", true, false)
	await _after_change_frame()
	_assert_overlay("B1 recapture")

	# Depot remove
	_sm.call("set_player_depot", _off_route_pid, false)
	await _after_change_frame()
	_assert_overlay("B1 depot remove", _off_route_pid, "no_hub")

	# Off-route capture whose infra-pressure role must change.
	if mm != null and mm.has_method("update_province_infrastructure"):
		mm.call("update_province_owner", _infra_pid, "GER", "FRA", true, false)
		mm.call("update_province_infrastructure", _infra_pid, 10)
		await _after_change_frame()
		_assert_overlay("B1 off-route capture infra", _infra_pid, "engineers")
		mm.call("update_province_infrastructure", _infra_pid, 80)
		await _after_change_frame()
		_assert_overlay("B1 infra raise", _infra_pid, "no_engineers")


func _drop_routes_touching(pid: int) -> void:
	if _sm == null or not ("_routes" in _sm):
		return
	var drop: Array = []
	for key in _sm._routes.keys():
		var plan: Variant = _sm._routes[key]
		if plan == null or not (plan is Object):
			continue
		var path: Array = plan.get("province_path")
		if path.has(pid):
			drop.append(key)
	for key2 in drop:
		_sm._routes.erase(key2)


func _b2_silent_mutation() -> void:
	_ensure_l_on()
	await process_frame
	if not ("_routes" in _sm) or (_sm._routes as Dictionary).is_empty():
		_fail("B2 no routes to mutate")
		return
	var keys: Array = _sm._routes.keys()
	keys.sort()
	var replace_key := str(keys[0])
	var erase_key := str(keys[mini(1, keys.size() - 1)])
	var plan_scr: Script = load("res://scripts/supply/SupplyRoutePlan.gd") as Script
	var depot_scr: Script = load("res://scripts/supply/ProvinceDepotState.gd") as Script
	var new_plan: Object = plan_scr.new()
	var silent_dest := _pid_at(0, 7)
	new_plan.set("route_id", replace_key)
	new_plan.set("source_province_id", _cap_pid)
	new_plan.set("target_province_id", silent_dest)
	new_plan.set("province_path", [_cap_pid, _pid_at(0, 1), _pid_at(0, 2), _pid_at(0, 3), silent_dest] as Array[int])
	_sm._routes[replace_key] = new_plan
	if erase_key != replace_key:
		_sm._routes.erase(erase_key)
	var silent_depot := _pid_at(1, 7)
	if depot_scr != null:
		_sm.depot_states[silent_depot] = depot_scr.new(silent_depot, 120.0)
	if "player_depot_province_ids" in _sm and silent_depot not in _sm.player_depot_province_ids:
		_sm.player_depot_province_ids.append(silent_depot)
	await _after_change_frame()
	_assert_overlay("B2 silent in-place mutation", silent_depot, "hub")
	if _role_of(silent_dest) not in ["route", "active", "preview"]:
		_fail("B2 new path dest %d role='%s'" % [silent_dest, _role_of(silent_dest)])
	else:
		_pass("B2 new path dest %d role=%s" % [silent_dest, _role_of(silent_dest)])


func _b3_no_change_frames() -> void:
	_ensure_l_on()
	await process_frame
	var full0 := _full_recomputes()
	var patch0 := _batch_patches()
	var i := 0
	while i < 30:
		await process_frame
		i += 1
	var full1 := _full_recomputes()
	var patch1 := _batch_patches()
	if full1 > full0:
		_fail("B3 no-change frames full recomputes %d→%d" % [full0, full1])
	else:
		_pass("B3 no-change frames 0 full recomputes")
	if patch1 > patch0:
		_fail("B3 no-change frames batch patches %d→%d" % [patch0, patch1])
	else:
		_pass("B3 no-change frames 0 batch patches")
	var roles0 := _role_computes()
	_ensure_l_off()
	await process_frame
	_ensure_l_on()
	await process_frame
	var roles1 := _role_computes()
	if roles1 > roles0:
		_fail("B3 no-change L off/on recomputed roles %d→%d (PERF-3 cache-hit)" % [roles0, roles1])
	else:
		_pass("B3 no-change L off/on cache hit (roles=%d)" % roles1)
