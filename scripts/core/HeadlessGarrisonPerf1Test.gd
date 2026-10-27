extends SceneTree

## GARRISON-PERF-1: icon rebuilds coalesce, and a retreating garrison is not
## "undefended". Deferred light captures do not apply after campaign end or
## after the quit fence. Empty-hex captures still say (undefended).
const OPOLSKI := 711080
const GLIWICKI := 711058
const BYTOMSKI := 711057
const NYSKI := 711079
const HAUTES_ALPES := 710796
const ALPES_HP := 710795
const SOSNOWIECKI := 711060
const POZNAN := 711064
const ELBING := 711086
const STOLP := 711091
const FIXTURES: Array[int] = [
	GLIWICKI, BYTOMSKI, NYSKI, HAUTES_ALPES, ALPES_HP, SOSNOWIECKI, POZNAN,
]

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessGarrisonPerf1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessGarrisonPerf1Test: ", msg)


func _run() -> void:
	_assert_icon_batch()
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm == null or bm == null or lm == null or boot == null:
		_fail("autoloads missing")
		_finish()
		return
	if not boot.call("boot", mm, sm, "GER"):
		_fail("board boot failed")
		_finish()
		return
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("seed_1936_start_garrisons missing")
		_finish()
		return
	var seeded: Dictionary = lm.call("seed_1936_start_garrisons", true)
	print("GARRISON_PERF1_SEED placed=%s" % str(seeded.get("placed", -1)))
	_assert_retreat_wording(mm, lm, bm)
	_assert_empty_hex_still_undefended(mm, lm, bm)
	await _assert_open_session_flushes(mm, bm)
	await _assert_campaign_end_drops(mm, bm)
	await _assert_quit_fence_drops(mm, bm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessGarrisonPerf1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessGarrisonPerf1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _assert_icon_batch() -> void:
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		_fail("MapRenderer script missing")
		return
	var mr: Node = scr.new()
	if not mr.has_method("queue_unit_icon_rebuild"):
		_fail("queue_unit_icon_rebuild missing")
		return
	mr.call("queue_unit_icon_rebuild", [OPOLSKI])
	mr.call("queue_unit_icon_rebuild", [GLIWICKI, BYTOMSKI])
	var raw: Variant = mr.get("_queued_icon_pids")
	var n := 0
	if raw is Dictionary:
		n = (raw as Dictionary).size()
		(raw as Dictionary).clear()
	var posts := int(mr.get("_icon_flush_posts"))
	var queued: bool = bool(mr.get("_icon_flush_queued"))
	# The deferred flush must not rebuild an unmounted renderer.
	mr.set("_icon_flush_queued", false)
	if n != 3 or posts != 1 or not queued:
		_fail("icon batch n=%d posts=%d queued=%s" % [n, posts, str(queued)])
		return
	_pass("icon rebuild coalesced to 1 flush for 3 pids")


func _assert_retreat_wording(mm: Node, lm: Node, bm: Node) -> void:
	var owner := _owner(mm, OPOLSKI)
	var stationed := _stationed(lm, OPOLSKI)
	print("GARRISON_PERF1_OPOLSKI owner=%s stationed=%d" % [owner, stationed.size()])
	if owner.is_empty() or stationed.is_empty():
		_fail("Opolski %d has no garrison (owner=%s n=%d)" % [OPOLSKI, owner, stationed.size()])
		return
	var att := "POL" if owner != "POL" else "GER"
	bm.set("last_capture_notice", "")
	bm.call("_apply_attacker_win_capture_light", att, OPOLSKI, 0, "")
	var notice := str(bm.get("last_capture_notice"))
	var still := _stationed(lm, OPOLSKI).size()
	print("GARRISON_PERF1_RETREAT notice=%s still=%d" % [notice, still])
	if "(undefended)" in notice:
		_fail("retreat toast said undefended: %s" % notice)
		return
	if "captured" not in notice.to_lower():
		_fail("retreat toast missing captured: %s" % notice)
		return
	if still > 0:
		_fail("garrison did not leave Opolski")
		return
	_pass("retreat toast: %s" % notice)


func _assert_empty_hex_still_undefended(mm: Node, lm: Node, bm: Node) -> void:
	var owner := _owner(mm, ELBING)
	_clear_stationed(lm, ELBING)
	if not _stationed(lm, ELBING).is_empty():
		_fail("could not clear Elbing")
		return
	var att := "POL" if owner != "POL" else "GER"
	bm.set("last_capture_notice", "")
	bm.call("_apply_attacker_win_capture_light", att, ELBING, 0, "")
	var notice := str(bm.get("last_capture_notice"))
	print("GARRISON_PERF1_EMPTY notice=%s" % notice)
	if "(undefended)" not in notice or "captured" not in notice.to_lower():
		_fail("empty hex notice: %s" % notice)
		return
	_pass("empty hex still undefended: %s" % notice)


func _assert_open_session_flushes(mm: Node, bm: Node) -> void:
	_open_session()
	if not bm.has_method("_queue_light_capture"):
		_fail("_queue_light_capture missing")
		return
	var owner := _owner(mm, STOLP)
	var att := "POL" if owner != "POL" else "GER"
	bm.call("_queue_light_capture", att, STOLP, 0, "")
	# Godot 4.7 flushes the message queue, then runs _process, then honors quit().
	# A backlog queued from a deferred call must survive that _process and the
	# next idle frame. A live session applies on the frame after that.
	await process_frame
	var mid := _owner(mm, STOLP)
	print("GARRISON_PERF1_OPEN_FRAME1 %d %s -> %s" % [STOLP, owner, mid])
	if mid != owner:
		_fail("frame 1 flushed %d (%s -> %s)" % [STOLP, owner, mid])
		return
	await process_frame
	var mid2 := _owner(mm, STOLP)
	print("GARRISON_PERF1_OPEN_FRAME2 %d %s -> %s" % [STOLP, owner, mid2])
	if mid2 != owner:
		_fail("frame 2 flushed %d (%s -> %s); quit would apply" % [STOLP, owner, mid2])
		return
	await process_frame
	var now := _owner(mm, STOLP)
	print("GARRISON_PERF1_OPEN %d %s -> %s" % [STOLP, owner, now])
	if now == owner or now != att:
		_fail("open session did not flush %d (%s -> %s)" % [STOLP, owner, now])
		return
	_pass("open session held two frames then flushed Stolp")


func _assert_campaign_end_drops(mm: Node, bm: Node) -> void:
	var before := _snapshot(mm)
	_peace()["campaign_end"] = {"outcome": "garrperf1"}
	bm.set("last_capture_notice", "")
	for pid in [GLIWICKI, NYSKI, HAUTES_ALPES]:
		_defer_capture(bm, pid, before[pid])
	await process_frame
	await process_frame
	if not _owners_held(mm, before, "campaign-end"):
		return
	if "(undefended)" in str(bm.get("last_capture_notice")):
		_fail("campaign-end toast %s" % str(bm.get("last_capture_notice")))
		return
	_pass("campaign end dropped deferred captures")


func _assert_quit_fence_drops(mm: Node, bm: Node) -> void:
	var before := _snapshot(mm)
	_peace().erase("campaign_end")
	get_root().set_meta("eoa_capture_session_closed", true)
	set_meta("eoa_capture_session_closed", true)
	bm.set("last_capture_notice", "")
	for pid in [BYTOMSKI, ALPES_HP, SOSNOWIECKI, POZNAN]:
		_defer_capture(bm, pid, str(before.get(pid, "")))
	await process_frame
	await process_frame
	if not _owners_held(mm, before, "quit-fence"):
		return
	if "(undefended)" in str(bm.get("last_capture_notice")):
		_fail("quit-fence toast %s" % str(bm.get("last_capture_notice")))
		return
	_pass("quit fence dropped deferred captures")


func _defer_capture(bm: Node, pid: int, owner: String) -> void:
	var att := "POL" if owner != "POL" else "GER"
	bm.call_deferred("_deferred_resolve_attacker_win", att, pid, 0, "")
	if bm.has_method("_queue_light_capture"):
		bm.call("_queue_light_capture", att, pid, 0, "")


func _peace() -> Dictionary:
	var gd := get_root().get_node_or_null("GameData")
	if gd == null:
		return {}
	var ps: Variant = gd.get("peace_state")
	return ps if ps is Dictionary else {}


func _open_session() -> void:
	_peace().erase("campaign_end")
	if get_root().has_meta("eoa_capture_session_closed"):
		get_root().remove_meta("eoa_capture_session_closed")
	if has_meta("eoa_capture_session_closed"):
		remove_meta("eoa_capture_session_closed")


func _snapshot(mm: Node) -> Dictionary:
	var before := {}
	for pid in FIXTURES:
		var owner := _owner(mm, pid)
		before[pid] = owner
		if owner.is_empty():
			_fail("fixture %d missing" % pid)
	return before


func _owners_held(mm: Node, before: Dictionary, label: String) -> bool:
	for pid in FIXTURES:
		var now := _owner(mm, pid)
		if now != str(before.get(pid, "")):
			_fail("%s flipped %d %s -> %s" % [label, pid, str(before.get(pid, "")), now])
			return false
	return true


func _owner(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _stationed(lm: Node, pid: int) -> Array:
	var out: Array = []
	if not ("formations" in lm) or not (lm.formations is Dictionary):
		return out
	for fid_v in lm.formations.keys():
		var f: Object = lm.formations[fid_v] as Object
		if f == null:
			continue
		if int(f.get("stationed_province_id")) == pid:
			out.append(f)
	return out


func _clear_stationed(lm: Node, pid: int) -> void:
	if not ("formations" in lm) or not (lm.formations is Dictionary):
		return
	var drop: Array = []
	for fid_v in lm.formations.keys():
		var f: Object = lm.formations[fid_v] as Object
		if f != null and int(f.get("stationed_province_id")) == pid:
			drop.append(fid_v)
	for fid_v in drop:
		lm.formations.erase(fid_v)
