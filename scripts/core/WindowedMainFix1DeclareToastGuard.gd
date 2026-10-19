extends SceneTree

## Windowed (xvfb) MAIN-FIX-1 guard: GER declares on POL with GER border hexes
## empty, then the toast layer is watched for 10 in-game days. An AI empty-hex
## capture may happen. If it does, each toast must be "Poland captured X from
## Germany (undefended)" and that province must actually change owner. No
## owner change → 0 toasts.
##
##   tools/eoa_main_fix1_declare_toast_guard.sh
##
## Not live Play.

const PLAY_SIZE := Vector2i(1280, 800)
const HOLD_DAYS := 10
const ELBLAG_PID := 711086
const SLUPSK_PID := 711091
const FLUSH_FRAMES := 6

var _failures: int = 0
var _boot: GDScript
var _war: GDScript
var _owners_before: Dictionary = {}
var _news_before: int = 0


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] WindowedMainFix1DeclareToastGuard: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] WindowedMainFix1DeclareToastGuard: ", msg)


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var lui := get_root().get_node_or_null("LeaderEventUI")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	if mm == null or tm == null or _boot == null or _war == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.boot(mm, sm, "GER"):
		_fail("boot failed")
		_finish()
		return
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	if lui != null and "force_toast_ui" in lui:
		lui.set("force_toast_ui", true)
	_war.reset_for_test()
	_war.clear_rule_overrides()
	var pol_to := _border_to(mm, "GER", "POL")
	var pol_from := _border_from(mm, "GER", "POL")
	if pol_to <= 0 or pol_from <= 0:
		_fail("missing GER-POL border")
		_finish()
		return
	_boot.make_division("mf1_pol_front", "POL", pol_to)
	_pass("POL division on border pid %d targeting GER %d" % [pol_to, pol_from])
	_log_pid(mm, "before", ELBLAG_PID, "Elbląski")
	_log_pid(mm, "before", SLUPSK_PID, "Słupski")
	_log_pid(mm, "before", pol_from, "GER border")
	var started: Dictionary = _war.begin_player_justify_from_province(pol_to)
	if not bool(started.get("ok", false)):
		_fail("justify failed %s" % str(started))
		_finish()
		return
	for day in range(0, 16):
		tm.total_days_elapsed = day
		_war.try_ai_declare_wars(day)
	if _war.is_at_war("GER", "POL"):
		_fail("auto-declared before click")
		_finish()
		return
	_owners_before = _owner_map(mm)
	_owners_before["GER_N"] = _owned_pids(mm, "GER")
	_owners_before["POL_N"] = _owned_pids(mm, "POL")
	_news_before = _capture_news().size()
	var declared: Dictionary = _war.player_declare_from_province(pol_to)
	if not bool(declared.get("ok", false)):
		_fail("declare failed %s" % str(declared))
		_finish()
		return
	_pass("GER declared on POL")
	if not _assert_toasts(mm, "on declare"):
		_finish()
		return
	if bm != null and bm.has_method("try_ai_start_land_battles"):
		var ai0: Dictionary = bm.call("try_ai_start_land_battles", int(tm.total_days_elapsed))
		print("  [INFO] try_ai_start_land_battles on declare %s" % str(ai0))
	if not _assert_toasts(mm, "after AI start"):
		_finish()
		return
	if not tm.has_method("advance_live_f5_equivalent_days"):
		_fail("advance_live_f5_equivalent_days missing")
		_finish()
		return
	var day_i := 0
	while day_i < HOLD_DAYS:
		var advanced: Dictionary = tm.call("advance_live_f5_equivalent_days", 1)
		if int(advanced.get("days", 0)) < 1:
			_fail("day %d did not advance %s" % [day_i + 1, str(advanced)])
			_finish()
			return
		if bm != null and bm.has_method("try_ai_start_land_battles"):
			bm.call("try_ai_start_land_battles", int(tm.total_days_elapsed))
		if not _assert_toasts(mm, "day %d" % (day_i + 1)):
			_finish()
			return
		day_i += 1
	_pass("watched toast layer for %d in-game days" % HOLD_DAYS)
	_log_pid(mm, "after", ELBLAG_PID, "Elbląski")
	_log_pid(mm, "after", SLUPSK_PID, "Słupski")
	_log_pid(mm, "after", pol_from, "GER border")
	if not _assert_toast_owner_match(mm, lui):
		_finish()
		return
	_finish()


func _assert_toasts(mm: Node, label: String) -> bool:
	var news: Array = _capture_news()
	var new_rows: Array = news.slice(_news_before, news.size()) if news.size() > _news_before else []
	for raw in new_rows:
		var row: Dictionary = raw
		var title := str(row.get("title", "")).strip_edges()
		var parsed: Dictionary = _parse_capture_title(title)
		if parsed.is_empty():
			_fail("%s capture toast not 'attacker captured X from owner': %s" % [label, title])
			return false
		var pid := _pid_from_province_name(mm, str(parsed.get("province", "")))
		if pid <= 0:
			_fail("%s capture news has no province: %s" % [label, title])
			return false
		var owner := _owner_of(mm, pid)
		var prev := str(_owners_before.get(pid, _owners_before.get(str(pid), owner)))
		if prev == owner:
			_fail(
				"%s capture toast with no owner change pid=%d owner=%s title=%s"
				% [label, pid, owner, title]
			)
			return false
		var att_name := str(parsed.get("attacker", ""))
		if att_name == "Poland" and owner != "POL":
			_fail("%s Poland toast but owner is %s pid=%d" % [label, owner, pid])
			return false
		if att_name == "Germany" and owner != "GER":
			_fail("%s Germany toast but owner is %s pid=%d" % [label, owner, pid])
			return false
		_pass("%s real capture pid=%d %s → %s (%s)" % [label, pid, prev, owner, title])
	if new_rows.is_empty():
		_pass("%s no capture toast" % label)
	_news_before = news.size()
	return true


func _assert_toast_owner_match(mm: Node, lui: Node) -> bool:
	var flips: Array = _flipped_pids(mm)
	var news: Array = _capture_news()
	if flips.is_empty():
		if not news.is_empty():
			_fail("no ownership change but capture toasts=%d %s" % [news.size(), str(news)])
			return false
		_pass("no ownership change; toast cards=0")
		_scan_toast_layer(lui)
		return true
	if news.size() != flips.size():
		_fail(
			"capture toasts=%d must equal owner flips=%d news=%s flips=%s"
			% [news.size(), flips.size(), str(news), str(flips)]
		)
		return false
	var named: Dictionary = {}
	for raw in news:
		var row: Dictionary = raw
		var title := str(row.get("title", "")).strip_edges()
		var parsed: Dictionary = _parse_capture_title(title)
		if parsed.is_empty():
			_fail("final capture toast wording: %s" % title)
			return false
		var pid := _pid_from_province_name(mm, str(parsed.get("province", "")))
		if pid not in flips:
			_fail("toast names pid=%d which did not flip: %s" % [pid, title])
			return false
		named[pid] = true
		if str(parsed.get("from", "")) == "Germany" and bool(parsed.get("undefended", false)) == false:
			_fail("GER land empty-hex toast missing (undefended): %s" % title)
			return false
	if named.size() != flips.size():
		_fail("toasts named %d pids, flips=%d" % [named.size(), flips.size()])
		return false
	_pass("toasts=%d flips=%d 1:1 correctly worded" % [news.size(), flips.size()])
	_scan_toast_layer(lui)
	return true


func _scan_toast_layer(lui: Node) -> void:
	if lui == null or not ("_toast_container" in lui):
		_pass("no toast container (headless skip)")
		return
	var tc: Variant = lui.get("_toast_container")
	if tc == null or not (tc is Node):
		_pass("toast container empty")
		return
	var found := 0
	for child in (tc as Node).get_children():
		var text := _control_text(child)
		if " captured " in text and " from " in text:
			found += 1
			print("  [INFO] toast layer: %s" % text)
		elif "Province captured" in text:
			found += 1
			print("  [INFO] toast layer: %s" % text)
	_pass("toast layer capture cards=%d" % found)


func _control_text(n: Node) -> String:
	var bits: PackedStringArray = []
	if n is Label:
		bits.append((n as Label).text)
	for c in n.get_children():
		bits.append(_control_text(c))
	return " ".join(bits)


func _capture_news() -> Array:
	var out: Array = []
	var lui: Node = get_root().get_node_or_null("LeaderEventUI")
	if lui == null or not ("news_history" in lui):
		return out
	var hist: Variant = lui.get("news_history")
	if not (hist is Array):
		return out
	for raw in hist:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var title := str(row.get("title", "")).strip_edges()
		var body := str(row.get("body", "")).strip_edges()
		if " captured " in title and " from " in title:
			out.append(row)
			continue
		if title == "Province captured":
			out.append(row)
	return out


func _parse_capture_title(title: String) -> Dictionary:
	var t := title.strip_edges()
	var cap := t.find(" captured ")
	var frm := t.find(" from ")
	if cap < 0 or frm <= cap:
		return {}
	var attacker := t.substr(0, cap).strip_edges()
	var pname := t.substr(cap + 10, frm - (cap + 10)).strip_edges()
	var rest := t.substr(frm + 6).strip_edges()
	var undef := rest.ends_with("(undefended)")
	if undef:
		rest = rest.substr(0, rest.length() - 13).strip_edges()
	return {
		"attacker": attacker,
		"province": pname,
		"from": rest,
		"undefended": undef,
	}


func _pid_from_province_name(mm: Node, name: String) -> int:
	var want := name.strip_edges()
	if want.is_empty() or mm == null or not mm.has_method("get_all_provinces"):
		return -1
	var provs: Variant = mm.call("get_all_provinces")
	if not (provs is Dictionary):
		return -1
	for pid_v in (provs as Dictionary).keys():
		var p: Object = (provs as Dictionary)[pid_v]
		if p != null and str(p.get("name")) == want:
			return int(pid_v)
	return -1


func _owner_map(mm: Node) -> Dictionary:
	var out := {}
	if mm == null or not mm.has_method("get_all_provinces"):
		return out
	var provs: Variant = mm.call("get_all_provinces")
	if not (provs is Dictionary):
		return out
	for pid_v in (provs as Dictionary).keys():
		var pid := int(pid_v)
		out[pid] = _owner_of(mm, pid)
	return out


func _flipped_pids(mm: Node) -> Array:
	var out: Array = []
	var now: Dictionary = _owner_map(mm)
	for pid_v in now.keys():
		if typeof(pid_v) != TYPE_INT:
			continue
		var pid := int(pid_v)
		var before := str(_owners_before.get(pid, now[pid]))
		var after := str(now[pid])
		if before != after:
			out.append(pid)
	out.sort()
	return out


func _owned_pids(mm: Node, tag: String) -> Array:
	var out: Array = []
	if mm == null or not mm.has_method("get_provinces_by_owner"):
		return out
	for pid_v in mm.call("get_provinces_by_owner", tag):
		out.append(int(pid_v))
	out.sort()
	return out


func _owner_of(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid) if mm != null else null
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _controller_of(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid) if mm != null else null
	if p == null:
		return ""
	var ctrl := str(p.get("controller_tag")).strip_edges().to_upper()
	if ctrl.is_empty():
		return str(p.get("owner_tag")).strip_edges().to_upper()
	return ctrl


func _log_pid(mm: Node, when: String, pid: int, label: String) -> void:
	print(
		"  [INFO] %s %s pid=%d owner=%s ctrl=%s"
		% [when, label, pid, _owner_of(mm, pid), _controller_of(mm, pid)]
	)


func _border_from(mm: Node, att: String, defender: String) -> int:
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


func _finish() -> void:
	var ok := _failures == 0
	print("WindowedMainFix1DeclareToastGuard: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("WindowedMainFix1DeclareToastGuard: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
