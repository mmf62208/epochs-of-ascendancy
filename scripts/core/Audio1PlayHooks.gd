# scripts/core/Audio1PlayHooks.gd
## Dev-only Play hook. Off unless this is a debug build and
## EOA_AUDIO1_READY_WAR=1. Grants the player a ready war justification so
## Declare can be clicked immediately. Does not advance the clock and does
## not touch the random seed. Normal play never calls grant.
##
##   EOA_AUDIO1_READY_WAR=1 tools/run_godot.sh --path . res://scenes/TestScenario.tscn
##
## Begin (GER 1936 is the default). Open a French border province — the log
## line EOA_AUDIO1_READY_WAR prints pid= — and click Declare war on France.
## That plays the alert. Ctrl+click that province with a German land unit
## selected to open a fight and hear the combat clash.
class_name Audio1PlayHooks
extends RefCounted

const ENV := "EOA_AUDIO1_READY_WAR"


static func enabled() -> bool:
	if not OS.is_debug_build():
		return false
	return OS.get_environment(ENV).strip_edges() == "1"


static func maybe_run() -> Dictionary:
	if not enabled():
		return {"ok": false, "ran": false, "reason": "off"}
	var result: Dictionary = WarStateDomain.grant_ready_player_justify("")
	result["ran"] = true
	return result
