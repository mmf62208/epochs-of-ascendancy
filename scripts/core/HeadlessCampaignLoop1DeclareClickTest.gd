extends SceneTree

## CL1 FIX #1: player justifications must not auto-declare.
## After 14 days GER vs POL is ready, not at war. Declare is press-on-down
## so leftover MapRenderer left-up swallow (same class as
## HeadlessProd1ButtonOpenTest) cannot eat the click.
## Inspector Declare is only for the ready target.
##
## Declare is diplomatic only: after the click, 3 live days must not issue
## a new order to any player unit or move any player unit.

const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 8
const HOLD_DAYS := 3
const HOLD_FRONT_FID := "cl1_ger_hold_front"
const HOLD_INTERIOR_FID := "cl1_ger_hold_interior"
const BERLIN_PID := 710300

var _failures := 0
var _event_seq := 0
var _boot: GDScript
var _war: GDScript
var _chrome: GDScript
var _move: GDScript
var _leftover: Node
var _ui: CanvasLayer
var _host_pol: Panel
var _host_fra: Panel
var _pol_to := -1
var _pol_from := -1
var _fra_to := -1
var _hold_interior := -1
var _hold_before: Dictionary = {}


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessCampaignLoop1DeclareClickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCampaignLoop1DeclareClickTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCampaignLoop1DeclareClickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCampaignLoop1DeclareClickTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	var sp := get_root().get_node_or_null("SessionPlayers")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_chrome = load("res://scripts/ui/CampaignWarChrome.gd") as GDScript
	_move = load("res://scripts/formations/FormationMovement.gd") as GDScript
	if mm == null or tm == null or _boot == null or _war == null or _chrome == null:
		_fail("autoloads missing")
		return
	if not _boot.boot(mm, sm, "GER"):
		_fail("boot failed")
		return
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "GER")
	_war.reset_for_test()
	_war.clear_rule_overrides()
	_pol_to = _border_to(mm, "GER", "POL")
	_pol_from = _border_from(mm, "GER", "POL")
	_fra_to = _border_to(mm, "GER", "FRA")
	if _pol_to <= 0 or _pol_from <= 0 or _fra_to <= 0:
		_fail("missing GER border POL=%d←%d FRA=%d" % [_pol_to, _pol_from, _fra_to])
		return
	_pass("borders POL %d←%d FRA %d" % [_pol_to, _pol_from, _fra_to])
	var started: Dictionary = _war.begin_player_justify_from_province(_pol_to)
	if not bool(started.get("ok", false)):
		_fail("begin GER justify POL failed %s" % str(started))
		return
	if int(started.get("ready_day", -1)) != 14:
		_fail("player ready_day want 14 got %s" % str(started.get("ready_day")))
		return
	_pass("GER justifying POL ready_day=14")
	for day in range(0, 16):
		tm.total_days_elapsed = day
		_war.try_ai_declare_wars(day)
	if _war.is_at_war("GER", "POL"):
		_fail("player war auto-declared on day %d" % int(tm.total_days_elapsed))
		return
	if not bool(_war.player_justify_is_ready_for("POL")):
		_fail("POL justify not ready on day %d" % int(tm.total_days_elapsed))
		return
	if bool(_war.player_justify_is_ready_for("FRA")):
		_fail("FRA justify ready without a FRA claim")
		return
	_pass("day %d GER–POL not at war, Declare ready for POL only" % int(tm.total_days_elapsed))
	if not _station_player_hold(mm, lm):
		return
	_hold_before = _player_hold_snapshot(lm)
	if _hold_before.is_empty():
		_fail("player hold snapshot empty")
		return
	_leftover = _LeftoverReleaseSwallow.new()
	_leftover.name = "Cl1LeftoverReleaseSwallow"
	root.add_child(_leftover)
	_ui = CanvasLayer.new()
	_ui.name = "Cl1DeclareUI"
	_ui.layer = 110
	root.add_child(_ui)
	_host_pol = _make_host("InspectorPol", Vector2(40, 80))
	_host_fra = _make_host("InspectorFra", Vector2(40, 280))
	_ui.add_child(_host_pol)
	_ui.add_child(_host_fra)
	var pol_prov: Object = mm.call("get_province", _pol_to)
	var fra_prov: Object = mm.call("get_province", _fra_to)
	_chrome.mount(_host_pol, pol_prov)
	_chrome.mount(_host_fra, fra_prov)
	await _flush()
	var pol_btn := _host_pol.get_node_or_null("BtnDeclareWar") as Button
	var fra_btn := _host_fra.get_node_or_null("BtnDeclareWar") as Button
	if pol_btn == null or not pol_btn.visible or pol_btn.disabled:
		_fail("POL Declare missing/disabled text=%s" % (str(pol_btn.text) if pol_btn != null else "null"))
		return
	if pol_btn.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("POL Declare action_mode want BUTTON_PRESS got %s" % str(pol_btn.action_mode))
		return
	if str(pol_btn.text).find("Declare war on") < 0 or str(pol_btn.text).find("Poland") < 0:
		_fail("POL button want Declare war on Poland got %s" % pol_btn.text)
		return
	_pass("POL inspector %s" % pol_btn.text)
	if fra_btn == null or not fra_btn.visible:
		_fail("FRA inspector button missing")
		return
	if str(fra_btn.text).find("Declare") >= 0:
		_fail("FRA inspector must not say Declare got %s" % fra_btn.text)
		return
	if not fra_btn.disabled or str(fra_btn.text).find("Justify") < 0:
		_fail("FRA inspector want disabled Justify got enabled=%s text=%s" % [str(not fra_btn.disabled), fra_btn.text])
		return
	_pass("FRA inspector %s disabled" % fra_btn.text)
	if not _click_control(fra_btn, true):
		_fail("could not click FRA inspector")
		return
	await _flush()
	if _war.is_at_war("GER", "FRA") or _war.is_at_war("GER", "POL"):
		_fail("FRA click started a war POL=%s FRA=%s" % [str(_war.is_at_war("GER", "POL")), str(_war.is_at_war("GER", "FRA"))])
		return
	_pass("FRA click did not declare")
	if not _click_control(pol_btn, true):
		_fail("could not click POL Declare")
		return
	await _flush()
	if not _war.is_at_war("GER", "POL"):
		_fail("POL Declare click did not start the war")
		_cleanup()
		return
	_pass("leftover-swallow Declare click started GER–POL")
	if not _assert_player_hold(lm, _hold_before, "on declare"):
		_cleanup()
		return
	if not tm.has_method("advance_live_f5_equivalent_days"):
		_fail("advance_live_f5_equivalent_days missing")
		_cleanup()
		return
	var advanced: Dictionary = tm.call("advance_live_f5_equivalent_days", HOLD_DAYS)
	if int(advanced.get("days", 0)) < HOLD_DAYS:
		_fail("wanted %d live days after declare got %s" % [HOLD_DAYS, str(advanced)])
		_cleanup()
		return
	_pass("advanced %d live days after declare" % HOLD_DAYS)
	if not _assert_player_hold(lm, _hold_before, "after %d days" % HOLD_DAYS):
		_cleanup()
		return
	_pass("player units held: no new order, no move")
	_cleanup()


func _make_host(host_name: String, pos: Vector2) -> Panel:
	var host := Panel.new()
	host.name = host_name
	host.position = pos
	host.size = Vector2(320, 160)
	host.custom_minimum_size = Vector2(320, 160)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	return host


func _make_mouse(screen_pt: Vector2, pressed: bool) -> InputEventMouseButton:
	_event_seq += 1
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.canceled = false
	ev.double_click = false
	ev.position = screen_pt
	ev.global_position = screen_pt
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.set_meta("eoa_cl1_declare_seq", _event_seq)
	return ev


func _warp_mouse(screen_pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)
	DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))


func _click_at(screen_pt: Vector2, swallow_release: bool) -> void:
	if _leftover != null and _leftover.has_method("arm"):
		if swallow_release:
			_leftover.call("arm")
		else:
			_leftover.call("disarm")
	_warp_mouse(screen_pt)
	var down: InputEventMouseButton = _make_mouse(screen_pt, true)
	Input.parse_input_event(down)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	var up: InputEventMouseButton = _make_mouse(screen_pt, false)
	Input.parse_input_event(up)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _click_control(ctrl: Control, swallow_release: bool) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	var r: Rect2 = ctrl.get_global_rect()
	if r.size.x < 4.0 or r.size.y < 4.0:
		return false
	_click_at(r.get_center(), swallow_release)
	return true


func _station_player_hold(mm: Node, lm: Node) -> bool:
	if lm == null or not ("formations" in lm) or not (lm.formations is Dictionary):
		_fail("LeaderManager.formations missing")
		return false
	(lm.formations as Dictionary).clear()
	if _move != null and _move.has_method("apply_save_data"):
		_move.call("apply_save_data", {})
	var bm := get_root().get_node_or_null("BattleManager")
	if bm != null:
		if "include_player_in_ai_land_battles" in bm:
			bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
	_hold_interior = _interior_ger(mm, _pol_from)
	if _hold_interior <= 0:
		_fail("no interior GER province for hold unit")
		return false
	_boot.make_division(HOLD_FRONT_FID, "GER", _pol_from)
	_boot.make_division(HOLD_INTERIOR_FID, "GER", _hold_interior)
	_pass("stationed %s @%d and %s @%d" % [HOLD_FRONT_FID, _pol_from, HOLD_INTERIOR_FID, _hold_interior])
	return true


func _interior_ger(mm: Node, front_pid: int) -> int:
	if mm == null:
		return -1
	var berlin: Object = mm.call("get_province", BERLIN_PID) if mm.has_method("get_province") else null
	if berlin != null and not bool(berlin.get("is_sea")) and str(berlin.get("owner_tag")).strip_edges().to_upper() == "GER":
		if BERLIN_PID != front_pid and BERLIN_PID != _pol_to:
			return BERLIN_PID
	if not mm.has_method("get_provinces_by_owner"):
		return -1
	var owned: Array = mm.call("get_provinces_by_owner", "GER")
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		if pid == front_pid or pid == _pol_to:
			continue
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
		var borders_pol := false
		for nid_v in nbrs:
			var n: Object = mm.call("get_province", int(nid_v))
			if n == null or bool(n.get("is_sea")):
				continue
			if str(n.get("owner_tag")).strip_edges().to_upper() == "POL":
				borders_pol = true
				break
		if not borders_pol:
			return pid
	return -1


func _player_hold_snapshot(lm: Node) -> Dictionary:
	var out: Dictionary = {}
	if lm == null or not ("formations" in lm) or not (lm.formations is Dictionary):
		return out
	var forms: Dictionary = lm.formations
	for fid_v in forms.keys():
		var f: Object = forms[fid_v]
		if f == null:
			continue
		var tag := ""
		if "country_tag" in f:
			tag = str(f.country_tag).strip_edges().to_upper()
		if tag != "GER":
			continue
		if "campaign_inactive" in f and bool(f.campaign_inactive):
			continue
		var fid := str(fid_v)
		var march_dest := -1
		if _move != null and _move.has_method("get_march"):
			var march: Dictionary = _move.call("get_march", fid)
			if not march.is_empty():
				march_dest = int(march.get("dest_id", -1))
		var station := -1
		if "stationed_province_id" in f:
			station = int(f.stationed_province_id)
		var mission := ""
		if "current_land_mission" in f:
			mission = str(f.current_land_mission)
		var in_combat := false
		if "is_in_combat" in f:
			in_combat = bool(f.is_in_combat)
		out[fid] = {
			"station": station,
			"mission": mission,
			"in_combat": in_combat,
			"march_dest": march_dest,
		}
	return out


func _player_ger_marches() -> Array:
	var fids: Array = []
	if _move == null or not _move.has_method("list_marches"):
		return fids
	var marches: Array = _move.call("list_marches")
	for raw in marches:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if str(row.get("country_tag", "")).strip_edges().to_upper() != "GER":
			continue
		fids.append(str(row.get("formation_id", "")))
	return fids


func _player_attack_battles() -> Array:
	var out: Array = []
	var bm := get_root().get_node_or_null("BattleManager")
	if bm == null or not bm.has_method("get_open_land_battles"):
		return out
	var battles: Array = bm.call("get_open_land_battles")
	for raw in battles:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = raw
		if str(b.get("att_tag", "")).strip_edges().to_upper() != "GER":
			continue
		out.append("%s→%s" % [str(b.get("from_id", -1)), str(b.get("to_id", -1))])
	return out


func _assert_player_hold(lm: Node, before: Dictionary, label: String) -> bool:
	var after: Dictionary = _player_hold_snapshot(lm)
	if after.size() != before.size():
		_fail("%s player unit count %d → %d" % [label, before.size(), after.size()])
		return false
	for fid_v in before.keys():
		var fid := str(fid_v)
		if not after.has(fid):
			_fail("%s missing player unit %s" % [label, fid])
			return false
		var a: Dictionary = after[fid]
		var b: Dictionary = before[fid]
		if int(a.get("station", -2)) != int(b.get("station", -3)):
			_fail("%s %s moved %s → %s" % [label, fid, str(b.get("station")), str(a.get("station"))])
			return false
		if str(a.get("mission", "")) != str(b.get("mission", "x")):
			_fail("%s %s mission %s → %s" % [label, fid, str(b.get("mission")), str(a.get("mission"))])
			return false
		if int(a.get("march_dest", -1)) != int(b.get("march_dest", -2)):
			_fail("%s %s new march dest %s" % [label, fid, str(a.get("march_dest"))])
			return false
	var marches: Array = _player_ger_marches()
	if not marches.is_empty():
		_fail("%s player marches %s" % [label, str(marches)])
		return false
	var attacks: Array = _player_attack_battles()
	if not attacks.is_empty():
		_fail("%s player attack orders %s" % [label, str(attacks)])
		return false
	_pass("%s player units held (%d)" % [label, after.size()])
	return true


func _border_from(mm: Node, att: String, defender: String) -> int:
	if not mm.has_method("get_provinces_by_owner"):
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


func _border_to(mm: Node, att: String, defender: String) -> int:
	if not mm.has_method("get_provinces_by_owner"):
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


func _cleanup() -> void:
	if _host_pol != null and is_instance_valid(_host_pol):
		_host_pol.queue_free()
	if _host_fra != null and is_instance_valid(_host_fra):
		_host_fra.queue_free()
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	if _leftover != null and is_instance_valid(_leftover):
		_leftover.queue_free()


class _LeftoverReleaseSwallow extends Node:
	## Mimic MapRenderer leftover left-up swallow after Begin / pan skip-pick.
	var _armed: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process_input(true)

	func arm() -> void:
		_armed = true

	func disarm() -> void:
		_armed = false

	func _input(event: InputEvent) -> void:
		if not _armed:
			return
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			return
		_armed = false
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
