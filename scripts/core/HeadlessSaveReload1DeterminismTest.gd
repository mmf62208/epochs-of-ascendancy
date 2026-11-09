extends SceneTree

## SR1 test B. A save/load (and a fresh process) continues the same 60 days.
## CAMPAIGN-SAVE-1 P1: SR1_DET_MODE=identity_twin proves mid-war gather hash
## identity after a fresh-session load, then a 60-day no-save twin. Mutants that
## drop land_war.marches or game_data.campaign_wars must change the hash.
const _Hash = preload("res://scripts/core/SaveStateHash.gd")
const _Io = preload("res://scripts/core/SaveReload1Io.gd")
const N_DAYS := 60
const _DIGEST_MISS := "map_ui,province_editor,metadata.timestamp/timestamp_unix/last_played/play_time_seconds/wall_time,time.paused,*.ms,*.total_ms"

var _failures := 0
var _sl
var _tm
var _gd
var _bm
var _created: Array[String] = []


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	# Autosave stays off while the fixture is built. The autosave mode turns it on
	# only for the traced window.
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveReload1DeterminismTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveReload1DeterminismTest: ", msg)


func _run() -> void:
	var t0 := Time.get_ticks_usec()
	_sl = get_root().get_node_or_null("SaveLoadManager")
	_tm = get_root().get_node_or_null("TimeManager")
	_gd = get_root().get_node_or_null("GameData")
	_bm = get_root().get_node_or_null("BattleManager")
	var mode := OS.get_environment("SR1_DET_MODE").strip_edges()
	if mode.is_empty():
		mode = "inproc"
	if mode == "ref":
		_mode_ref()
	elif mode == "load":
		_mode_load()
	elif mode == "autosave":
		_mode_autosave()
	elif mode == "diag_ref" or mode == "diag_load":
		_mode_diag(mode)
	elif mode == "diag_pick_ref" or mode == "diag_pick_load":
		_mode_diag_pick(mode)
	elif mode == "identity_twin":
		_mode_identity_twin()
	else:
		_mode_inproc()
	_cleanup()
	var wall_s := float(Time.get_ticks_usec() - t0) / 1000000.0
	var reseed := 0.0
	if _tm != null and _tm.has_method("reseed_cost_ms"):
		reseed = float(_tm.reseed_cost_ms())
	print("PERF determinism mode=%s wall_s=%.1f reseed_ms_per_call=%.4f" % [mode, wall_s, reseed])
	_finish()


func _mode_ref() -> void:
	if not _build("sr1test_det_pristine"):
		return
	var t_save := Time.get_ticks_usec()
	var saved: Dictionary = _sl.save_game_detailed("sr1test_det200")
	var save_ms := float(Time.get_ticks_usec() - t_save) / 1000.0
	_track("sr1test_det200")
	if not bool(saved.get("ok", false)):
		_fail("ref save failed: %s" % str(saved.get("error", "")))
		return
	print("SAVE_METRIC ms=%.1f bytes=%d" % [save_ms, int(saved.get("bytes", 0))])
	var text := _trace(false)
	_write_trace(text)
	_pass("ref trace md5=%s days=%d" % [_md5(text), N_DAYS])


func _mode_load() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if boot == null or mm == null or not bool(boot.boot(mm, sm, "GER")):
		_fail("load-process boot failed")
		return
	var t_load := Time.get_ticks_usec()
	var loaded: Dictionary = _sl.load_game_detailed("sr1test_det200")
	var load_ms := float(Time.get_ticks_usec() - t_load) / 1000.0
	_track("sr1test_det200")
	if not bool(loaded.get("ok", false)):
		_fail("fresh process load failed: %s" % str(loaded.get("error", "")))
		return
	var load_bytes := 0
	var load_path := str(loaded.get("path", ""))
	if not load_path.is_empty() and FileAccess.file_exists(load_path):
		load_bytes = FileAccess.get_file_as_bytes(load_path).size()
	print("LOAD_METRIC ms=%.1f bytes=%d" % [load_ms, load_bytes])
	_tm.paused = false
	var text := _trace(false)
	_write_trace(text)
	_pass("load trace md5=%s" % _md5(text))


func _mode_inproc() -> void:
	if not _build("sr1test_b_pristine"):
		return
	var ref_text := _trace(false)
	if not _build("sr1test_b_pristine"):
		return
	var saved: Dictionary = _sl.save_game_detailed("sr1test_b_mid")
	_track("sr1test_b_mid")
	if not bool(saved.get("ok", false)):
		_fail("inproc save failed: %s" % str(saved.get("error", "")))
		return
	_tm.paused = false
	var adv: Dictionary = _tm.advance_live_f5_equivalent_days(3)
	if not bool(adv.get("ok", false)):
		_fail("inproc 3-day detour failed %s" % str(adv))
		return
	# A fresh process boots with run_seed 0. Drop it so this load has to restore it.
	_tm.run_seed = 0
	var loaded: Dictionary = _sl.load_game_detailed("sr1test_b_mid")
	if not bool(loaded.get("ok", false)):
		_fail("inproc load failed: %s" % str(loaded.get("error", "")))
		return
	_tm.paused = false
	var load_text := _trace(false)
	_compare_traces("inproc", ref_text, load_text)


func _mode_identity_twin() -> void:
	if not _build("sr1test_id_pristine"):
		return
	var before: Dictionary = _sl._gather_save_data().duplicate(true)
	var h0 := str(_Hash.state_hash(before))
	_print_digest("before_save", before, h0)
	if not _midwar_ready(before):
		return
	var t_save := Time.get_ticks_usec()
	var saved: Dictionary = _sl.save_game_detailed("sr1test_id_mid")
	var save_ms := float(Time.get_ticks_usec() - t_save) / 1000.0
	_track("sr1test_id_mid")
	if not bool(saved.get("ok", false)):
		_fail("identity save failed: %s" % str(saved.get("error", "")))
		return
	print("SAVE_METRIC ms=%.1f bytes=%d hash=%s" % [save_ms, int(saved.get("bytes", 0)), h0])
	var skip_twin := OS.get_environment("SR1_SKIP_TWIN").strip_edges() == "1"
	var ref_text := ""
	var h_end_ref := ""
	if not skip_twin:
		ref_text = _trace(false)
		h_end_ref = _hash_now()
		print("TWIN_REF days=%d end_hash=%s md5=%s" % [N_DAYS, h_end_ref, _md5(ref_text)])
	if not _fresh_session():
		return
	var loaded: Dictionary = _sl.load_game_detailed("sr1test_id_mid")
	if not bool(loaded.get("ok", false)):
		_fail("identity fresh-session load failed: %s" % str(loaded.get("error", "")))
		return
	_tm.paused = false
	var after: Dictionary = _sl._gather_save_data()
	var h1 := str(_Hash.state_hash(after))
	_print_digest("after_reload", after, h1)
	if h0 != h1:
		_fail("identity hash diverged before=%s after=%s" % [h0, h1])
		_print_identity_diff(before, after)
		return
	_pass("identity hash identical %s (volatile stripped)" % h0)
	print("IDENTITY MATCH hash=%s" % h0)
	if not skip_twin:
		var load_text := _trace(false)
		var h_end_load := _hash_now()
		print("TWIN_LOAD days=%d end_hash=%s md5=%s" % [N_DAYS, h_end_load, _md5(load_text)])
		_compare_traces("identity-twin", ref_text, load_text)
		if h_end_ref != h_end_load:
			_fail("60-day twin end-state hash diverged ref=%s load=%s" % [h_end_ref, h_end_load])
		else:
			_pass("60-day twin end-state hash identical %s" % h_end_load)
	if OS.get_environment("SR1_SKIP_MUTANT").strip_edges() == "1":
		return
	_assert_mutant_bites("drop_marches", h0, before)
	_assert_mutant_bites("drop_wars", h0, before)


func _mode_autosave() -> void:
	if not _build("sr1test_auto_pristine"):
		return
	var ref_path := OS.get_environment("SR1_REF_TRACE").strip_edges()
	if ref_path.is_empty() or not FileAccess.file_exists(ref_path):
		_fail("autosave mode needs SR1_REF_TRACE")
		return
	var ref_text := FileAccess.get_file_as_string(ref_path)
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "1")
	_sl.autosave_slot_prefix = "sr1test_auto"
	for i in range(1, 4):
		_track("sr1test_auto_%d" % i)
	var text := _trace(true)
	if int(_sl.autosave_writes) < 2:
		_fail("autosave wrote %d times in the window (want >= 2)" % int(_sl.autosave_writes))
	else:
		_pass("autosave wrote %d rotating slots" % int(_sl.autosave_writes))
	var quit_h0 := _hash_now()
	var quit_res: Dictionary = _sl._write_quit_autosave()
	if not bool(quit_res.get("ok", false)):
		_fail("quit autosave failed: %s" % str(quit_res.get("error", "")))
	elif _hash_now() != quit_h0:
		_fail("quit autosave changed the state hash")
	else:
		_pass("quit autosave left the state hash unchanged")
	_compare_traces("autosave-inert", ref_text, text)


func _mode_diag(mode: String) -> void:
	var d200 := _Io.evidence_file("diag_d200.bin")
	var d201 := _Io.evidence_file("diag_d201.bin")
	var d202 := _Io.evidence_file("diag_d202.bin")
	if mode == "diag_ref":
		if not _build("sr1test_diag_pristine"):
			return
		var saved: Dictionary = _sl.save_game_detailed("sr1test_diag200")
		_track("sr1test_diag200")
		if not bool(saved.get("ok", false)):
			_fail("diag save failed")
			return
		_store_blob(d200, _sl._gather_save_data())
		_tm.paused = false
		var adv: Dictionary = _tm.advance_live_f5_equivalent_days(1)
		if not bool(adv.get("ok", false)):
			_fail("diag advance failed %s" % str(adv))
			return
		_store_blob(d201, _sl._gather_save_data())
		_tm.paused = false
		var adv_b: Dictionary = _tm.advance_live_f5_equivalent_days(1)
		if not bool(adv_b.get("ok", false)):
			_fail("diag advance d202 failed %s" % str(adv_b))
			return
		_store_blob(d202, _sl._gather_save_data())
		_pass("diag ref wrote d200 d201 d202")
		return
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if boot == null or mm == null or not bool(boot.boot(mm, sm, "GER")):
		_fail("diag boot failed")
		return
	var loaded: Dictionary = _sl.load_game_detailed("sr1test_diag200")
	_track("sr1test_diag200")
	if not bool(loaded.get("ok", false)):
		_fail("diag load failed %s" % str(loaded.get("error", "")))
		return
	var now200: Dictionary = _sl._gather_save_data()
	_report_blob("d200", _load_blob(d200), now200)
	_tm.paused = false
	var adv2: Dictionary = _tm.advance_live_f5_equivalent_days(1)
	if not bool(adv2.get("ok", false)):
		_fail("diag load advance failed %s" % str(adv2))
		return
	_report_blob("d201", _load_blob(d201), _sl._gather_save_data())
	_tm.paused = false
	var adv3: Dictionary = _tm.advance_live_f5_equivalent_days(1)
	if not bool(adv3.get("ok", false)):
		_fail("diag load advance d202 failed %s" % str(adv3))
		return
	_report_blob("d202", _load_blob(d202), _sl._gather_save_data())


func _mode_diag_pick(mode: String) -> void:
	if mode == "diag_pick_ref":
		if not _build("sr1test_diagpick_pristine"):
			return
		var saved: Dictionary = _sl.save_game_detailed("sr1test_diagpick")
		_track("sr1test_diagpick")
		if not bool(saved.get("ok", false)):
			_fail("diag pick save failed")
			return
	else:
		var mm := get_root().get_node_or_null("MapManager")
		var sm := get_root().get_node_or_null("SupplyManager")
		var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
		if boot == null or mm == null or not bool(boot.boot(mm, sm, "GER")):
			_fail("diag pick boot failed")
			return
		var loaded: Dictionary = _sl.load_game_detailed("sr1test_diagpick")
		_track("sr1test_diagpick")
		if not bool(loaded.get("ok", false)):
			_fail("diag pick load failed %s" % str(loaded.get("error", "")))
			return
		_tm.paused = false
	_probe_pick("d200")
	for step in range(3):
		_tm.paused = false
		var adv: Dictionary = _tm.advance_live_f5_equivalent_days(1)
		if not bool(adv.get("ok", false)):
			_fail("diag pick advance failed %s" % str(adv))
			return
		_probe_pick("d%d" % int(_tm.get_total_days_elapsed()))
	_pass("diag pick probes done")


func _probe_pick(label: String) -> void:
	var war := load("res://scripts/core/WarStateDomain.gd") as GDScript
	var mm: Node = get_root().get_node("MapManager")
	var lm: Node = get_root().get_node("LeaderManager")
	var divs := {"JAP": 0, "CHI": 0, "SOV": 0, "POL": 0}
	var forms: Variant = lm.get("formations")
	if forms is Dictionary:
		for fid in forms:
			var fobj: Object = forms[fid] as Object
			if fobj == null or str(fobj.get("formation_type")) != "division":
				continue
			var tag := str(fobj.get("country_tag")).strip_edges().to_upper()
			if divs.has(tag):
				divs[tag] = int(divs[tag]) + 1
	var st: Variant = _gd.peace_state.get("campaign_wars", {})
	var booted: Variant = (st as Dictionary).get("booted", "MISSING") if st is Dictionary else "NA"
	var wars: Dictionary = (st as Dictionary).get("wars", {}) if st is Dictionary else {}
	var truces: Dictionary = (st as Dictionary).get("truces", {}) if st is Dictionary else {}
	var neigh: Array = war.land_neighbours("JAP")
	var str_j := float(war.military_strength("JAP"))
	var str_c := float(war.military_strength("CHI"))
	var str_s := float(war.military_strength("SOV"))
	var str_p := float(war.military_strength("POL"))
	var ratio := str_j / maxf(str_c, 0.0001)
	var allied := bool(war._formal_allies("JAP", "CHI"))
	var pick := str(war._pick_declare_target("JAP", "GER", true, 1.5))
	var dirty := bool(mm.get("_owner_index_dirty"))
	print("PROBE %s day=%d dirty=%s booted=%s divs=%s str=JAP:%.4f CHI:%.4f SOV:%.4f POL:%.4f ratio=%.4f neigh_n=%d chi_neigh=%s allied=%s war=%s truce=%s pick=%s run_seed=%s" % [
		label, int(_tm.get_total_days_elapsed()), str(dirty), str(booted), str(divs),
		str_j, str_c, str_s, str_p, ratio, neigh.size(), str(neigh.has("CHI")),
		str(allied), str(wars.has("CHI|JAP")), str(truces.get("CHI|JAP", "")), pick, str(_tm.run_seed),
	])


func _store_blob(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write %s" % path)
		return
	f.store_buffer(var_to_bytes(data))
	f.close()


func _load_blob(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = bytes_to_var(f.get_buffer(f.get_length()))
	f.close()
	return parsed if parsed is Dictionary else {}


func _report_blob(label: String, expect: Dictionary, got: Dictionary) -> void:
	if expect.is_empty():
		_fail("%s missing reference blob" % label)
		return
	var hs_e: Dictionary = _Hash.section_hashes(expect)
	var hs_g: Dictionary = _Hash.section_hashes(got)
	var keys: Array = hs_e.keys()
	for k in hs_g.keys():
		if k not in keys:
			keys.append(k)
	keys.sort()
	var mismatched := 0
	for k2 in keys:
		if str(hs_e.get(k2, "")) != str(hs_g.get(k2, "")):
			mismatched += 1
			var sec_diff := str(_Hash.first_diff(expect.get(k2, null), got.get(k2, null)))
			print("DIAG %s section %s ref=%s load=%s first=%s" % [label, str(k2), str(hs_e.get(k2, "MISSING")), str(hs_g.get(k2, "MISSING")), sec_diff.substr(0, 300)])
	var diff := str(_Hash.first_diff(_Hash._strip(expect), _Hash._strip(got)))
	print("DIAG %s sections_differ=%d first=%s" % [label, mismatched, diff.substr(0, 500)])
	if mismatched == 0 and diff.is_empty():
		_pass("%s blobs match" % label)
	else:
		_fail("%s blobs differ" % label)


func _build(slot: String) -> bool:
	var mw := load("res://scripts/core/SaveReload1Mw200.gd") as GDScript
	if mw == null:
		_fail("MW200 helper failed to compile")
		return false
	var built: Dictionary = mw.build(slot)
	_track(slot)
	print("MW200 ", built)
	if not bool(built.get("ok", false)):
		_fail("MW200 fixture: %s" % str(built.get("error", built)))
		return false
	_pass("MW200 day=%s" % str(built.get("day", 0)))
	return true


func _trace(flush_auto: bool) -> String:
	var lines: PackedStringArray = []
	for i in N_DAYS:
		_tm.paused = false
		var adv: Dictionary = _tm.advance_live_f5_equivalent_days(1)
		if not bool(adv.get("ok", false)):
			_fail("trace day advance failed at i=%d %s" % [i, str(adv)])
			break
		if flush_auto:
			_sl.flush_pending_autosave()
		lines.append(_row())
		if (i + 1) % 10 == 0:
			print("TRACE day %d/%d elapsed=%s" % [i + 1, N_DAYS, str(_tm.get_total_days_elapsed())])
	return "\n".join(lines) + "\n"


func _row() -> String:
	var elapsed := int(_tm.get_total_days_elapsed())
	var live: Dictionary = {}
	if _gd != null:
		var raw: Variant = _gd.peace_state.get("interactive_multi_ai_day", {})
		if raw is Dictionary:
			live = raw
	var wars: Dictionary = {}
	var raw_w: Variant = _gd.peace_state.get("campaign_wars", {}) if _gd != null else {}
	if raw_w is Dictionary:
		wars = raw_w
	var today: Array = []
	var log: Array = wars.get("log", []) if wars.get("log") is Array else []
	for entry in log:
		if entry is Dictionary and int((entry as Dictionary).get("day", -1)) == elapsed:
			today.append(entry)
	var battles: Array = []
	if _bm != null and _bm.has_method("get_open_land_battles"):
		battles = _bm.get_open_land_battles()
	var aar: Dictionary = {}
	if _bm != null and _bm.has_method("peek_last_land_aar"):
		var raw_aar: Variant = _bm.peek_last_land_aar()
		if raw_aar is Dictionary:
			aar = raw_aar
	var caps: Array = []
	var raw_c: Variant = _gd.peace_state.get("campaign_capitulation", {}) if _gd != null else {}
	if raw_c is Dictionary:
		var cap_map: Variant = (raw_c as Dictionary).get("capitulated", {})
		if cap_map is Dictionary:
			caps = (cap_map as Dictionary).keys()
			caps.sort()
	var settlements: Array = []
	var raw_s: Variant = _gd.peace_state.get("peace_settlements", []) if _gd != null else []
	if raw_s is Array:
		settlements = raw_s
	var end := ""
	var raw_e: Variant = _gd.peace_state.get("campaign_end", {}) if _gd != null else {}
	if raw_e is Dictionary:
		end = str((raw_e as Dictionary).get("outcome", ""))
	return "d=%d prod=%s soft=%s pn=%s sn=%s player=%s events=%s justifies=%s truces=%s battles=%s aar=%s caps=%s settlements=%s end=%s hash=%s" % [
		elapsed,
		str(live.get("prod_tags", [])),
		str(live.get("soft_tag", "")),
		str(live.get("production_n", 0)),
		str(live.get("soft_n", 0)),
		str(live.get("player_tag", "")),
		_canon(today),
		_canon(wars.get("justifies", {})),
		_canon(wars.get("truces", {})),
		_canon(battles),
		_canon(aar),
		_canon(caps),
		_canon(settlements),
		end,
		_hash_now(),
	]


func _compare_traces(label: String, a: String, b: String) -> void:
	var ma := _md5(a)
	var mb := _md5(b)
	print("TRACE_MD5 %s a=%s b=%s" % [label, ma, mb])
	if a == b:
		_pass("%s trace byte-identical md5=%s" % [label, ma])
		return
	_fail("%s trace diverged md5 %s vs %s" % [label, ma, mb])
	var la := a.split("\n")
	var lb := b.split("\n")
	var n := mini(la.size(), lb.size())
	for i in n:
		if la[i] != lb[i]:
			print("TRACE_DIFF line %d" % i)
			print("A ", la[i].substr(0, 400))
			print("B ", lb[i].substr(0, 400))
			return


func _hash_now() -> String:
	return str(_Hash.state_hash(_sl._gather_save_data()))


func _print_digest(label: String, data: Dictionary, hash_hex: String) -> void:
	var sections: Dictionary = _Hash.section_hashes(data)
	var keys: Array = sections.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append(str(k))
	var joined := ",".join(parts)
	print("DIGEST_COVERS label=%s hash=%s n=%d keys=%s" % [label, hash_hex, keys.size(), joined])
	print("DIGEST_STRIPS %s" % _DIGEST_MISS)
	for k in keys:
		print("DIGEST_SECTION %s %s=%s" % [label, str(k), str(sections[k])])


func _print_identity_diff(before: Dictionary, after: Dictionary) -> void:
	var hs_b: Dictionary = _Hash.section_hashes(before)
	var hs_a: Dictionary = _Hash.section_hashes(after)
	var keys: Array = hs_b.keys()
	for k in hs_a.keys():
		if k not in keys:
			keys.append(k)
	keys.sort()
	for k2 in keys:
		if str(hs_b.get(k2, "")) != str(hs_a.get(k2, "")):
			var sec_diff := str(_Hash.first_diff(before.get(k2, null), after.get(k2, null)))
			print("IDENTITY_SECTION %s before=%s after=%s first=%s" % [
				str(k2), str(hs_b.get(k2, "MISSING")), str(hs_a.get(k2, "MISSING")), sec_diff.substr(0, 400)
			])
	var diff := str(_Hash.first_diff(_Hash._strip(before), _Hash._strip(after)))
	print("IDENTITY_DIFF %s" % diff.substr(0, 800))


func _midwar_ready(data: Dictionary) -> bool:
	var lw: Variant = data.get("land_war", {})
	var marches: Dictionary = {}
	var battles: Array = []
	if lw is Dictionary:
		var raw_m: Variant = (lw as Dictionary).get("marches", {})
		if raw_m is Dictionary:
			marches = raw_m
		var raw_b: Variant = (lw as Dictionary).get("open_battles", [])
		if raw_b is Array:
			battles = raw_b
	var wars: Dictionary = _campaign_wars(data)
	if marches.is_empty():
		_fail("mid-war fixture has no land_war.marches")
		return false
	if battles.is_empty():
		_fail("mid-war fixture has no open land battles")
		return false
	if wars.is_empty():
		_fail("mid-war fixture has no campaign_wars.wars")
		return false
	_pass("mid-war fixture marches=%d battles=%d wars=%d" % [marches.size(), battles.size(), wars.size()])
	return true


func _campaign_wars(data: Dictionary) -> Dictionary:
	var gd: Variant = data.get("game_data", {})
	if not (gd is Dictionary):
		return {}
	var cw: Variant = (gd as Dictionary).get("campaign_wars", {})
	if not (cw is Dictionary):
		return {}
	var wars: Variant = (cw as Dictionary).get("wars", {})
	return wars if wars is Dictionary else {}


func _fresh_session() -> bool:
	var lm := get_root().get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("clear_all_formations"):
		lm.call("clear_all_formations")
	var mw := load("res://scripts/core/SaveReload1Mw200.gd") as GDScript
	if mw == null or not bool(mw._fresh_boot()):
		_fail("fresh-session boot failed")
		return false
	_tm.run_seed = 0
	return true


func _assert_mutant_bites(kind: String, h0: String, before: Dictionary) -> void:
	var slot := "sr1test_id_mut_%s" % kind
	if not _write_mutant_slot("sr1test_id_mid", slot, kind):
		return
	if not _fresh_session():
		return
	var loaded: Dictionary = _sl.load_game_detailed(slot)
	if not bool(loaded.get("ok", false)):
		_fail("mutant %s load failed: %s" % [kind, str(loaded.get("error", ""))])
		return
	_tm.paused = false
	var mutant_data: Dictionary = _sl._gather_save_data()
	var h_mut := str(_Hash.state_hash(mutant_data))
	if h_mut == h0:
		_fail("mutant %s did not change identity hash (test does not bite)" % kind)
		return
	var diff := str(_Hash.first_diff(_Hash._strip(before), _Hash._strip(mutant_data)))
	_pass("mutant %s identity hash diverged %s vs %s first=%s" % [kind, h0, h_mut, diff.substr(0, 200)])
	print("MUTANT_FAIL %s before=%s after=%s" % [kind, h0, h_mut])


func _write_mutant_slot(src_slot: String, dest_slot: String, kind: String) -> bool:
	var src_path := str(_sl.get_save_path(src_slot))
	if not FileAccess.file_exists(src_path):
		_fail("mutant source missing %s" % src_path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(src_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("mutant source is not an object")
		return false
	var blob: Dictionary = parsed
	if kind == "drop_marches":
		if blob.get("land_war") is Dictionary:
			(blob["land_war"] as Dictionary).erase("marches")
		else:
			_fail("mutant drop_marches: land_war missing")
			return false
	elif kind == "drop_wars":
		if blob.get("game_data") is Dictionary:
			(blob["game_data"] as Dictionary).erase("campaign_wars")
		else:
			_fail("mutant drop_wars: game_data missing")
			return false
	else:
		_fail("unknown mutant %s" % kind)
		return false
	var dest_path := str(_sl.get_save_path(dest_slot))
	var f := FileAccess.open(dest_path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write mutant slot %s" % dest_path)
		return false
	f.store_string(JSON.stringify(blob, "\t"))
	f.close()
	_track(dest_slot)
	return true


func _write_trace(text: String) -> void:
	var path := OS.get_environment("SR1_TRACE").strip_edges()
	if path.is_empty():
		path = _Io.evidence_file("det_trace.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write trace %s" % path)
		return
	f.store_string(text)
	f.close()
	print("TRACE_FILE %s md5=%s" % [path, _md5(text)])


func _md5(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _canon(v: Variant) -> String:
	var t := typeof(v)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = d.keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		var parts: PackedStringArray = []
		for k in keys:
			parts.append("%s=%s" % [str(k), _canon(d[k])])
		return "{" + ",".join(parts) + "}"
	if t == TYPE_ARRAY:
		var items: Array = v
		var parts2: PackedStringArray = []
		for item in items:
			parts2.append(_canon(item))
		return "[" + ",".join(parts2) + "]"
	if t == TYPE_FLOAT:
		var fv := float(v)
		if not is_nan(fv) and not is_inf(fv) and abs(fv) < 9007199254740992.0 and fv == floor(fv):
			return str(int(fv))
		return "%.6f" % fv
	return str(v)


func _track(slot: String) -> void:
	var safe := slot
	_created.append(ProjectSettings.globalize_path("user://saves/%s.eoasave" % safe))
	_created.append(ProjectSettings.globalize_path("user://saves/%s.eoasave.bak" % safe))
	_created.append(ProjectSettings.globalize_path("user://saves/%s.eoasave.tmp" % safe))
	_created.append(ProjectSettings.globalize_path("user://saves/%s.json" % safe))


func _cleanup() -> void:
	var mode := OS.get_environment("SR1_DET_MODE").strip_edges()
	# The ref process must leave sr1test_det200 for the fresh load process.
	var keep: PackedStringArray = []
	if mode == "ref":
		keep.append(ProjectSettings.globalize_path("user://saves/sr1test_det200.json"))
		keep.append(ProjectSettings.globalize_path("user://saves/sr1test_det200.eoasave"))
	if mode == "diag_ref":
		keep.append(ProjectSettings.globalize_path("user://saves/sr1test_diag200.json"))
		keep.append(ProjectSettings.globalize_path("user://saves/sr1test_diag200.eoasave"))
	if mode == "diag_pick_ref":
		keep.append(ProjectSettings.globalize_path("user://saves/sr1test_diagpick.json"))
		keep.append(ProjectSettings.globalize_path("user://saves/sr1test_diagpick.eoasave"))
	for path in _created:
		if path in keep:
			continue
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _finish() -> void:
	if _failures == 0:
		print("HeadlessSaveReload1DeterminismTest: RESULT=PASS")
		quit(0)
	else:
		print("HeadlessSaveReload1DeterminismTest: RESULT=FAIL")
		quit(1)
