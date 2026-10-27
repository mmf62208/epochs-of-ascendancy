# scripts/core/SaveReload1Mw200.gd
## Shared mid-war day-200 fixture for SAVE-RELOAD-1.
## run_seed 193601. Player justifies on POL at day 150 and declares when ready.
## A second justify is still counting at day 200. One minor (LUX) is capitulated
## through the daily hook after a real declare and an ownership flip.
## AI-AI war and truce are real WarStateDomain declare_war / make_peace calls.
class_name SaveReload1Mw200
extends RefCounted

const RUN_SEED := 193601
const POL_CAPITAL := 711112
const LUX_PID := 710977
const TARGET_DAY := 200
const JUSTIFY_DAY := 150
const SECOND_JUSTIFY_DAY := 194


static func build(pristine_slot: String = "sr1test_pristine") -> Dictionary:
	var report := {
		"ok": false,
		"error": "",
		"day": 0,
		"player_wars": 0,
		"ai_wars": 0,
		"justify_left": -1,
		"justify_tag": "",
		"battles": 0,
		"marches": 0,
		"truces": 0,
		"settlements": 0,
		"lux_capitulated": false,
		"ai_pair": "",
		"truce_pair": "",
	}
	if not _restore_or_boot(pristine_slot, report):
		return report
	if not _advance_to(JUSTIFY_DAY):
		report["error"] = "clock locked before justify"
		return report
	var just: Dictionary = WarStateDomain.begin_player_justify_from_province(POL_CAPITAL)
	if not bool(just.get("ok", false)):
		report["error"] = "POL justify failed: %s" % str(just)
		return report
	if not _advance_to(int(TimeManager.get_total_days_elapsed()) + int(WarStateDomain.player_justify_days_left("POL"))):
		report["error"] = "clock locked before declare"
		return report
	var declared: Dictionary = WarStateDomain.player_declare_from_province(POL_CAPITAL)
	if not bool(declared.get("ok", false)):
		report["error"] = "POL declare failed: %s" % str(declared)
		return report
	_force_ai_war_and_truce(report)
	var lux: Dictionary = WarStateDomain.declare_war("GER", "LUX", "fixture")
	if not bool(lux.get("ok", false)):
		report["error"] = "LUX declare failed: %s" % str(lux)
		return report
	if not _advance_to(int(TimeManager.get_total_days_elapsed()) + 1):
		report["error"] = "clock locked before LUX snapshot"
		return report
	_flip_owned("LUX", "GER")
	if not _advance_to(int(TimeManager.get_total_days_elapsed()) + 1):
		report["error"] = "clock locked before LUX capitulation"
		return report
	report["lux_capitulated"] = CapitulationDomain.is_capitulated("LUX")
	if not _advance_to(SECOND_JUSTIFY_DAY):
		report["error"] = "clock locked before second justify"
		return report
	var second := _justify_someone_else()
	report["justify_tag"] = str(second.get("tag", ""))
	if not bool(second.get("ok", false)):
		report["error"] = "second justify failed: %s" % str(second)
		return report
	if not _advance_to(TARGET_DAY):
		report["error"] = "clock locked before day 200"
		return report
	_open_battle(report)
	_open_march(report)
	_fill_counts(report)
	report["day"] = int(TimeManager.get_total_days_elapsed())
	report["ok"] = (
		report["day"] == TARGET_DAY
		and int(report["player_wars"]) >= 1
		and int(report["ai_wars"]) >= 1
		and int(report["justify_left"]) > 0
		and int(report["battles"]) >= 1
		and int(report["marches"]) >= 1
		and int(report["truces"]) >= 1
		and int(report["settlements"]) >= 1
		and bool(report["lux_capitulated"])
	)
	if not bool(report["ok"]) and str(report["error"]).is_empty():
		report["error"] = "day-200 conditions missing"
	return report


static func _restore_or_boot(slot: String, report: Dictionary) -> bool:
	var slm := _slm()
	if slm != null and slm.has_method("slot_status"):
		var st: Dictionary = slm.call("slot_status", slot)
		if not bool(st.get("missing", true)) and not bool(st.get("damaged", false)):
			var loaded: Dictionary = slm.call("load_game_detailed", slot)
			if bool(loaded.get("ok", false)):
				TimeManager.paused = false
				TimeManager.run_seed = RUN_SEED
				return true
			report["error"] = "pristine load failed: %s" % str(loaded.get("error", ""))
			return false
	if not _fresh_boot():
		report["error"] = "boot failed"
		return false
	if slm == null:
		report["error"] = "SaveLoadManager missing"
		return false
	var saved: Dictionary = slm.call("save_game_detailed", slot)
	if not bool(saved.get("ok", false)):
		report["error"] = "pristine save failed: %s" % str(saved.get("error", ""))
		return false
	return true


static func _fresh_boot() -> bool:
	WarStateDomain.reset_for_test()
	CapitulationDomain.reset_for_test()
	CampaignEndDomain.reset_for_test()
	if typeof(GameData) != TYPE_NIL and GameData.has_method("clear_for_load"):
		GameData.clear_for_load()
	FormationMovement.apply_save_data({})
	if typeof(BattleManager) != TYPE_NIL:
		BattleManager._open_land_battles.clear()
	var mm := _root().get_node_or_null("MapManager") if _root() != null else null
	var sm := _root().get_node_or_null("SupplyManager") if _root() != null else null
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if boot == null or mm == null or not bool(boot.boot(mm, sm, "GER")):
		return false
	TimeManager.run_seed = RUN_SEED
	TimeManager.paused = false
	CapitulationDomain.apply_economy_factories_to_map()
	return true


static func _advance_to(target: int) -> bool:
	var guard := 0
	while int(TimeManager.get_total_days_elapsed()) < target and guard < 40:
		guard += 1
		if CampaignEndDomain.clock_locked():
			return false
		TimeManager.paused = false
		var step := mini(20, target - int(TimeManager.get_total_days_elapsed()))
		var adv: Dictionary = TimeManager.advance_live_f5_equivalent_days(step)
		if not bool(adv.get("ok", false)):
			return false
	return int(TimeManager.get_total_days_elapsed()) >= target


static func _force_ai_war_and_truce(report: Dictionary) -> void:
	var war_pairs := [["ITA", "FRA"], ["SOV", "FIN"], ["JAP", "CHI"], ["ITA", "ETH"], ["HUN", "ROM"]]
	for pair in war_pairs:
		var res: Dictionary = WarStateDomain.declare_war(str(pair[0]), str(pair[1]), "fixture")
		if bool(res.get("ok", false)) and not bool(res.get("already", false)):
			report["ai_pair"] = "%s-%s" % [pair[0], pair[1]]
			break
	var truce_pairs := [["SOV", "FIN"], ["JAP", "CHI"], ["ITA", "ETH"], ["HUN", "ROM"], ["ENG", "ITA"]]
	for pair2 in truce_pairs:
		var key := "%s-%s" % [pair2[0], pair2[1]]
		if key == str(report["ai_pair"]):
			continue
		var declared: Dictionary = WarStateDomain.declare_war(str(pair2[0]), str(pair2[1]), "fixture")
		if not bool(declared.get("ok", false)):
			continue
		var peace: Dictionary = WarStateDomain.make_peace(str(pair2[0]), str(pair2[1]), "fixture")
		if bool(peace.get("ok", false)):
			report["truce_pair"] = key
			break


static func _justify_someone_else() -> Dictionary:
	var tags := ["FRA", "CZE", "AUS", "DEN", "BEL", "LIT", "SWI"]
	for tag in tags:
		if WarStateDomain.is_at_war("GER", tag) or WarStateDomain.in_truce("GER", tag):
			continue
		var pid := _pid_owned(tag)
		if pid <= 0:
			continue
		var res: Dictionary = WarStateDomain.begin_player_justify_from_province(pid)
		res["tag"] = tag
		if bool(res.get("ok", false)):
			return res
	return {"ok": false, "reason": "no second target"}


static func _open_battle(report: Dictionary) -> void:
	var border := _border_pair("POL", "GER")
	if border.is_empty():
		report["battle_error"] = "no POL-GER border"
		return
	var to_id := int(border["to"])
	var from_id := int(border["from"])
	CampaignLoopTestBoot.make_division("sr1_pol_def", "POL", to_id)
	CampaignLoopTestBoot.make_division("sr1_ger_att", "GER", from_id)
	var bm := _root().get_node_or_null("BattleManager")
	if bm == null:
		report["battle_error"] = "BattleManager missing"
		return
	var started: Dictionary = bm.call("start_land_battle", "GER", to_id, from_id, "sr1_ger_att")
	report["battle_result"] = started
	if not bool(started.get("success", false)) or bool(started.get("instant", false)):
		report["battle_error"] = str(started)


static func _open_march(report: Dictionary) -> void:
	var pair := _own_neighbor_pair("GER", "sr1_ger_att")
	if pair.is_empty():
		report["march_error"] = "no GER march pair"
		return
	CampaignLoopTestBoot.make_division("sr1_ger_march", "GER", int(pair["from"]))
	var marched: Dictionary = FormationMovement.enqueue_own_land_march("sr1_ger_march", int(pair["to"]), "GER")
	report["march_result"] = marched
	if not bool(marched.get("ok", false)):
		report["march_error"] = str(marched)


static func _fill_counts(report: Dictionary) -> void:
	var player := "GER"
	var wars: Dictionary = {}
	var raw: Variant = GameData.peace_state.get("campaign_wars", {})
	if raw is Dictionary:
		var w: Variant = (raw as Dictionary).get("wars", {})
		if w is Dictionary:
			wars = w
	var player_n := 0
	var ai_n := 0
	for k in wars.keys():
		var row: Variant = wars[k]
		if not (row is Dictionary):
			continue
		var a := str((row as Dictionary).get("attacker", ""))
		var b := str((row as Dictionary).get("defender", ""))
		if a == player or b == player:
			player_n += 1
		else:
			ai_n += 1
	report["player_wars"] = player_n
	report["ai_wars"] = ai_n
	report["justify_left"] = int(WarStateDomain.player_justify_days_left(str(report["justify_tag"])))
	var bm := _root().get_node_or_null("BattleManager")
	var battles: Variant = bm.get("_open_land_battles") if bm != null else []
	report["battles"] = (battles as Array).size() if battles is Array else 0
	var march_blob: Dictionary = FormationMovement.get_save_data()
	var marches: Variant = march_blob.get("marches", {})
	report["marches"] = (marches as Dictionary).size() if marches is Dictionary else 0
	var truces: Variant = (raw as Dictionary).get("truces", {}) if raw is Dictionary else {}
	report["truces"] = (truces as Dictionary).size() if truces is Dictionary else 0
	var settlements: Variant = GameData.peace_state.get("peace_settlements", [])
	report["settlements"] = (settlements as Array).size() if settlements is Array else 0


static func _flip_owned(tag: String, holder: String) -> void:
	var mm := _root().get_node_or_null("MapManager")
	if mm == null or not mm.has_method("get_provinces_by_owner"):
		return
	var pids: Array = mm.call("get_provinces_by_owner", tag)
	for pid_v in pids:
		mm.call("update_province_owner", int(pid_v), holder, holder, true, true)


static func _border_pair(def_tag: String, att_tag: String) -> Dictionary:
	var mm := _root().get_node_or_null("MapManager")
	if mm == null:
		return {}
	var owned: Array = mm.call("get_provinces_by_owner", def_tag)
	for pid_v in owned:
		var pid := int(pid_v)
		var target: Object = mm.call("get_province", pid)
		if target == null or bool(target.get("is_sea")):
			continue
		for nid_v in mm.call("get_adjacent_provinces", pid):
			var nid := int(nid_v)
			var src: Object = mm.call("get_province", nid)
			if src == null or bool(src.get("is_sea")):
				continue
			if str(src.get("owner_tag")).strip_edges().to_upper() == att_tag:
				return {"from": nid, "to": pid}
	return {}


static func _own_neighbor_pair(tag: String, avoid_fid_province_owner_check: String) -> Dictionary:
	var mm := _root().get_node_or_null("MapManager")
	if mm == null:
		return {}
	var owned: Array = mm.call("get_provinces_by_owner", tag)
	var avoid := -1
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.formations.has(avoid_fid_province_owner_check):
		var f: Variant = LeaderManager.formations[avoid_fid_province_owner_check]
		if f != null:
			avoid = int(f.get("stationed_province_id"))
	for pid_v in owned:
		var pid := int(pid_v)
		if pid == avoid:
			continue
		var src: Object = mm.call("get_province", pid)
		if src == null or bool(src.get("is_sea")):
			continue
		for nid_v in mm.call("get_adjacent_provinces", pid):
			var nid := int(nid_v)
			if nid == avoid:
				continue
			var dst: Object = mm.call("get_province", nid)
			if dst == null or bool(dst.get("is_sea")):
				continue
			if str(dst.get("owner_tag")).strip_edges().to_upper() == tag:
				return {"from": pid, "to": nid}
	return {}


static func _pid_owned(tag: String) -> int:
	var mm := _root().get_node_or_null("MapManager")
	if mm == null:
		return -1
	var owned: Array = mm.call("get_provinces_by_owner", tag)
	for pid_v in owned:
		var p: Object = mm.call("get_province", int(pid_v))
		if p != null and not bool(p.get("is_sea")):
			return int(pid_v)
	return -1


static func _slm() -> Node:
	return _root().get_node_or_null("SaveLoadManager") if _root() != null else null


static func _root() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null
