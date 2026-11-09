extends SceneTree

## Writes tests/fixtures/campaign_save_1/near_capitulation.json for Play.
## GER is at war with FRA; France already holds enough 1936 German land that
## the next daily check_all will capitulate Germany. Not a shipped user save.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessCampaignSave1NearCapitulationFixture.gd

const OUT_PATH := "res://tests/fixtures/campaign_save_1/near_capitulation.json"
const SLOT := "cs1_near_capitulation"
const PLAYER := "GER"
const ENEMY := "FRA"


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _run() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var sl := root.get_node_or_null("SaveLoadManager")
	var lm := root.get_node_or_null("LeaderManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var war: GDScript = load("res://scripts/core/WarStateDomain.gd") as GDScript
	var cap: GDScript = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	var end: GDScript = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if mm == null or sl == null or lm == null or boot == null or war == null or cap == null:
		push_error("near-capitulation fixture: autoloads missing")
		quit(1)
		return
	if not bool(boot.call("boot", mm, sm, PLAYER)):
		push_error("near-capitulation fixture: boot failed")
		quit(1)
		return
	cap.call("apply_economy_factories_to_map")
	war.call("reset_for_test")
	cap.call("reset_for_test")
	if end != null and end.has_method("reset_for_test"):
		end.call("reset_for_test")
	war.call("clear_rule_overrides")
	lm.call("set_player_country_tag", PLAYER)
	var declared: Dictionary = war.call("declare_war", PLAYER, ENEMY, "near_capitulation_fixture")
	if not bool(declared.get("ok", false)):
		push_error("near-capitulation fixture: declare failed %s" % str(declared))
		quit(1)
		return
	cap.call("ensure_snapshot")
	var thresh := float(cap.call("threshold", PLAYER))
	_hold_until_threshold(mm, sm, cap, PLAYER, ENEMY, thresh)
	var prog := float(cap.call("progress", PLAYER))
	if prog + 0.0000001 < thresh:
		push_error("near-capitulation fixture: progress %.4f < threshold %.4f" % [prog, thresh])
		quit(1)
		return
	if bool(cap.call("is_capitulated", PLAYER)):
		push_error("near-capitulation fixture: GER already capitulated (do not check_all before save)")
		quit(1)
		return
	var saved: Dictionary = sl.call("save_game_detailed", SLOT)
	if not bool(saved.get("ok", false)):
		push_error("near-capitulation fixture: save failed %s" % str(saved.get("error", "")))
		quit(1)
		return
	var src := str(saved.get("absolute_path", ""))
	if src.is_empty() or not FileAccess.file_exists(src):
		src = ProjectSettings.globalize_path("user://saves/%s.json" % SLOT)
	if not FileAccess.file_exists(src):
		push_error("near-capitulation fixture: save file missing %s" % src)
		quit(1)
		return
	var out_abs := ProjectSettings.globalize_path(OUT_PATH)
	var dir_path := out_abs.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var err := DirAccess.copy_absolute(src, out_abs)
	if err != OK:
		var f := FileAccess.open(src, FileAccess.READ)
		if f == null:
			push_error("near-capitulation fixture: copy failed %s" % str(err))
			quit(1)
			return
		var text := f.get_as_text()
		f.close()
		var out := FileAccess.open(out_abs, FileAccess.WRITE)
		if out == null:
			push_error("near-capitulation fixture: write failed %s" % out_abs)
			quit(1)
			return
		out.store_string(text)
		out.close()
	var verify := FileAccess.get_file_as_string(out_abs)
	var parsed: Variant = JSON.parse_string(verify)
	if not (parsed is Dictionary):
		push_error("near-capitulation fixture: saved JSON did not parse")
		quit(1)
		return
	var gd: Dictionary = (parsed as Dictionary).get("game_data", {}) as Dictionary
	var wars: Dictionary = ((gd.get("campaign_wars", {}) as Dictionary).get("wars", {}) as Dictionary)
	if wars.is_empty():
		push_error("near-capitulation fixture: saved JSON has no campaign_wars")
		quit(1)
		return
	var cap_blob: Dictionary = gd.get("campaign_capitulation", {}) as Dictionary
	if not bool(cap_blob.get("snapshotted", false)):
		push_error("near-capitulation fixture: saved JSON missing capitulation snapshot")
		quit(1)
		return
	print("NEAR_CAPITULATION_FIXTURE path=%s progress=%.4f threshold=%.4f bytes=%d wars=%d" % [
		out_abs,
		prog,
		thresh,
		FileAccess.get_file_as_bytes(out_abs).size(),
		wars.size(),
	])
	quit(0)


func _hold_until_threshold(mm: Node, sm: Node, cap: GDScript, tag: String, holder: String, thresh: float) -> void:
	var pids: Array = mm.call("get_provinces_by_owner", tag)
	pids.sort()
	if sm != null and sm.has_method("begin_control_batch"):
		sm.call("begin_control_batch")
	for pid_v in pids:
		var pid := int(pid_v)
		var p: Object = mm.call("get_province", pid)
		if p == null:
			continue
		var owner := str(p.get("owner_tag")).strip_edges().to_upper()
		var ctrl := str(p.get("controller_tag")).strip_edges().to_upper()
		if ctrl == holder:
			continue
		mm.call("update_province_owner", pid, owner, holder, true, true)
		if float(cap.call("progress", tag)) + 0.0000001 >= thresh:
			break
	if sm != null and sm.has_method("end_control_batch"):
		sm.call("end_control_batch")
