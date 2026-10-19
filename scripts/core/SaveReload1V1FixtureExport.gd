extends SceneTree

## Write the committed v1 day-0 fixture. Same slim JSON as
## tools/generate_sr1_v1_fixture.py (pinned timestamps, one GER hex).
##
##   EOA_CAMPAIGN_LOOP=1 EOA_SCENARIO_EARLY_WARS=0 EOA_CALENDAR_AUTOSAVE=0 \
##     tools/run_godot.sh --headless --path . -s res://scripts/core/SaveReload1V1FixtureExport.gd

const _Io = preload("res://scripts/core/SaveReload1Io.gd")
const OUT := "res://tests/fixtures/save_reload_1/sr1test_v1_day0.json"


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm == null or boot == null or not bool(boot.boot(mm, sm, "GER")):
		print("SaveReload1V1FixtureExport: RESULT=FAIL boot")
		quit(1)
		return
	var body := _slim_v1()
	var dest := ProjectSettings.globalize_path(OUT)
	var parent := dest.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		print("SaveReload1V1FixtureExport: RESULT=FAIL write ", dest)
		quit(1)
		return
	f.store_string(JSON.stringify(body, "\t"))
	f.store_string("\n")
	f.close()
	print("SaveReload1V1FixtureExport: wrote ", dest, " bytes=", FileAccess.get_file_as_bytes(dest).size())
	print("SaveReload1V1FixtureExport: res=", _Io.V1_DAY0)
	print("SaveReload1V1FixtureExport: RESULT=PASS")
	quit(0)


func _slim_v1() -> Dictionary:
	return {
		"save_version": 1,
		"game_data": {
			"campaign_capitulation": {},
			"campaign_end": {},
			"campaign_wars": {
				"booted": true,
				"justifies": {},
				"log": [],
				"truces": {},
				"wars": {},
			},
			"peace_last_settlement": {},
			"peace_settlement_count": 0,
			"peace_settlements": [],
			"war_goal_tick_count": 0,
			"war_goals": {},
		},
		"infrastructure_projects": {"active_projects": {}, "version": 1},
		"land_war": {
			"last_aar": {},
			"marches": {},
			"next_seq": 1,
			"open_battles": [],
			"version": 1,
		},
		"map": {
			"provinces": [
				{
					"built_rail_neighbors": [],
					"built_road_neighbors": [],
					"controller_tag": "GER",
					"development_level": 3,
					"id": 710173,
					"infrastructure": 4,
					"owner_tag": "GER",
					"settlement_level": 0,
				}
			]
		},
		"metadata": {
			"game_date": "1936-01-01 00:00",
			"game_version": "0.2-dev",
			"last_played": "1936-01-01T00:00:00",
			"nation_name": "Germany",
			"play_time_seconds": 0,
			"player_tag": "GER",
			"scenario_id": "1936",
			"timestamp": "1936-01-01T00:00:00",
		},
		"time": {
			"accumulated_days": 0.0,
			"accumulated_hours": 0.0,
			"current_date": {"day": 1, "month": 1, "year": 1936},
			"current_hour": 0,
			"paused": true,
			"run_seed": 193601,
			"scenario_start_date": "1936-01-01",
			"time_scale": 1.0,
			"total_days_elapsed": 0,
		},
	}
