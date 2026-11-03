# scripts/core/StabilityJusticeDomain.gd
## Player-only stability and war justification.
## Inactive unless GameData.stability_justice_enabled() (campaign toggle, or EOA_STABILITY_JUSTICE=1).
## The flag-off path must not create this state, draw RNG, or add save keys.
class_name StabilityJusticeDomain
extends RefCounted

const KEY := "stability_justice"

## Tunables (v1). Player country only. AI is not consulted.
const JUSTIFY_DAYS := 30
const UNJUSTIFIED_HIT := 0.15
const SLOWDOWN_BELOW := 0.5
const SLOWDOWN_AT_ZERO := 0.25
const EXHAUSTION_FULL_DAYS := 200.0
const DRIFT_EXHAUSTION_FULL := 0.004
const DRIFT_UNREST_FULL := 0.006
const DRIFT_UNJUSTIFIED := 0.003
const DRIFT_RECOVERY := 0.002

## Pinned perf4 decisions digest with the feature off. The gate recomputes it.
const OFF_SEED_BASELINE := "20fe9063de285f19d4f9b8a105abfd31"


static func enabled() -> bool:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("stability_justice_enabled"):
		return false
	return bool(GameData.stability_justice_enabled())


static func player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var raw := str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
		if not raw.is_empty():
			return raw
	return "GER"


static func output_multiplier(stability: float) -> float:
	## 1.0 at or above 0.5. Linear down to 0.75 at stability 0.
	if stability >= SLOWDOWN_BELOW:
		return 1.0
	var t := clampf(stability / SLOWDOWN_BELOW, 0.0, 1.0)
	return 1.0 - SLOWDOWN_AT_ZERO * (1.0 - t)


static func output_multiplier_for_tag(country_tag: String) -> float:
	if not enabled():
		return 1.0
	if country_tag.strip_edges().to_upper() != player_tag():
		return 1.0
	return output_multiplier(stability())


static func supply_scale() -> Dictionary:
	if not enabled():
		return {"apply": false, "multiplier": 1.0, "tag": ""}
	var mult := output_multiplier(stability())
	if mult >= 1.0:
		return {"apply": false, "multiplier": 1.0, "tag": ""}
	return {"apply": true, "multiplier": mult, "tag": player_tag()}


static func stability() -> float:
	if not _has_state():
		return 1.0
	return clampf(float(_read().get("stability", 1.0)), 0.0, 1.0)


static func justify_status() -> Dictionary:
	if not _has_state():
		return _inactive_justify()
	var raw: Variant = _read().get("justify", {})
	if not (raw is Dictionary):
		return _inactive_justify()
	return _normalize_justify(raw as Dictionary)


static func has_state() -> bool:
	return _has_state()


static func chip_line() -> String:
	if not enabled():
		return ""
	# One decimal so a day's drift (about 0.2 points) is visible.
	var pct := "%.1f" % snappedf(stability() * 100.0, 0.1)
	var just := justify_status()
	if bool(just.get("active", false)) and bool(just.get("complete", false)):
		return "Stability %s%% · Justified" % pct
	if bool(just.get("active", false)):
		return "Stability %s%% · Justify %d/%d" % [pct, int(just.get("days_done", 0)), JUSTIFY_DAYS]
	return "Stability %s%%" % pct


static func note_justify(province_id: int) -> Dictionary:
	if not enabled():
		return {"ok": false, "skipped": true}
	var st := _read_or_default()
	var just := _normalize_justify(st.get("justify", {}) as Dictionary)
	var pid := int(province_id)
	if not bool(just.get("active", false)) or int(just.get("province_id", 0)) != pid:
		just = _inactive_justify()
		just["active"] = true
		just["province_id"] = pid
		just["days_done"] = 1
		just["complete"] = false
	st["justify"] = just
	st["stability"] = clampf(float(st.get("stability", 1.0)), 0.0, 1.0)
	_write(st)
	return _note_from_justify(just, false)


static func note_execute(province_id: int) -> Dictionary:
	if not enabled():
		return {"ok": false, "skipped": true, "penalized": false, "stability_delta": 0.0}
	var st := _read_or_default()
	var just := _normalize_justify(st.get("justify", {}) as Dictionary)
	var pid := int(province_id)
	var matched := bool(just.get("active", false)) and int(just.get("province_id", -1)) == pid
	var ready := matched and bool(just.get("complete", false))
	var before := clampf(float(st.get("stability", 1.0)), 0.0, 1.0)
	var delta := 0.0
	if ready:
		just = _inactive_justify()
	else:
		delta = -UNJUSTIFIED_HIT
		st["unjustified_active"] = true
		just = _inactive_justify()
	var after := clampf(before + delta, 0.0, 1.0)
	st["stability"] = after
	st["justify"] = just
	_write(st)
	return {
		"ok": true,
		"skipped": false,
		"penalized": not ready,
		"justified": ready,
		"stability_before": before,
		"stability": after,
		"stability_delta": after - before,
		"province_id": pid,
		"progress": "Justified war · no stability loss" if ready else "Unjustified war · stability -%.2f" % UNJUSTIFIED_HIT,
	}


static func merge_justify(result: Dictionary, note: Dictionary) -> Dictionary:
	if bool(note.get("skipped", false)):
		return result
	var progress := str(note.get("progress", "")).strip_edges()
	if not progress.is_empty():
		var summary := str(result.get("summary", "")).strip_edges()
		result["summary"] = progress if summary.is_empty() else "%s · %s" % [summary, progress]
	result["justify_days_done"] = int(note.get("days_done", 0))
	result["justify_days_needed"] = int(note.get("days_needed", JUSTIFY_DAYS))
	result["justify_complete"] = bool(note.get("complete", false))
	result["stability"] = stability()
	return result


static func merge_execute(result: Dictionary, note: Dictionary) -> Dictionary:
	if bool(note.get("skipped", false)):
		return result
	var progress := str(note.get("progress", "")).strip_edges()
	if not progress.is_empty():
		var summary := str(result.get("summary", "")).strip_edges()
		result["summary"] = progress if summary.is_empty() else "%s · %s" % [summary, progress]
	result["stability"] = float(note.get("stability", stability()))
	result["stability_delta"] = float(note.get("stability_delta", 0.0))
	result["stability_penalized"] = bool(note.get("penalized", false))
	result["stability_justified"] = bool(note.get("justified", false))
	return result


static func tick_day() -> Dictionary:
	if not enabled():
		return {"ok": true, "skipped": true, "created": false}
	var had := _has_state()
	var prev := _read_or_default()
	var st := prev.duplicate(true)
	var at_war := _player_at_war(player_tag())
	var wars_known := _campaign_wars_known()
	var war_days := int(st.get("war_days", 0))
	if at_war:
		war_days += 1
	else:
		war_days = maxi(0, war_days - 1)
	st["war_days"] = war_days
	if bool(st.get("unjustified_active", false)) and wars_known and not at_war:
		st["unjustified_active"] = false
	var exhaustion := clampf(float(war_days) / EXHAUSTION_FULL_DAYS, 0.0, 1.0)
	var unrest := _occupation_unrest()
	var unjust := bool(st.get("unjustified_active", false))
	var before := clampf(float(st.get("stability", 1.0)), 0.0, 1.0)
	var after := clampf(before + drift_delta(exhaustion, unrest, unjust), 0.0, 1.0)
	st["stability"] = after
	var just := _normalize_justify(st.get("justify", {}) as Dictionary)
	if bool(just.get("active", false)) and not bool(just.get("complete", false)):
		just["days_done"] = int(just.get("days_done", 0)) + 1
		if int(just.get("days_done", 0)) >= JUSTIFY_DAYS:
			just["days_done"] = JUSTIFY_DAYS
			just["complete"] = true
		st["justify"] = just
	var prev_just := _normalize_justify(prev.get("justify", {}) as Dictionary)
	var changed := (
		not is_equal_approx(after, before)
		or war_days != int(prev.get("war_days", 0))
		or bool(st.get("unjustified_active", false)) != bool(prev.get("unjustified_active", false))
		or bool(just.get("active", false)) != bool(prev_just.get("active", false))
		or int(just.get("days_done", 0)) != int(prev_just.get("days_done", 0))
		or bool(just.get("complete", false)) != bool(prev_just.get("complete", false))
	)
	if not had and not changed:
		return {"ok": true, "skipped": true, "created": false, "stability": 1.0, "drift": 0.0}
	_write(st)
	return {
		"ok": true,
		"skipped": false,
		"created": true,
		"stability": after,
		"drift": after - before,
		"exhaustion": exhaustion,
		"unrest": unrest,
		"unjustified": unjust,
		"justify": just,
	}


static func drift_delta(exhaustion: float, unrest: float, unjustified: bool) -> float:
	var down := 0.0
	down += DRIFT_EXHAUSTION_FULL * clampf(exhaustion, 0.0, 1.0)
	down += DRIFT_UNREST_FULL * clampf(unrest, 0.0, 1.0)
	if unjustified:
		down += DRIFT_UNJUSTIFIED
	if down <= 0.0:
		return DRIFT_RECOVERY
	return -down


static func export_save_blob() -> Dictionary:
	if not enabled() or not _has_state():
		return {}
	var st := _read()
	var just := _normalize_justify(st.get("justify", {}) as Dictionary)
	return {
		"stability": clampf(float(st.get("stability", 1.0)), 0.0, 1.0),
		"war_days": int(st.get("war_days", 0)),
		"unjustified_active": bool(st.get("unjustified_active", false)),
		"justify": just,
	}


static func import_save_blob(data: Dictionary) -> void:
	if not enabled():
		return
	var st := _default_state()
	st["stability"] = clampf(float(data.get("stability", 1.0)), 0.0, 1.0)
	st["war_days"] = maxi(0, int(data.get("war_days", 0)))
	st["unjustified_active"] = bool(data.get("unjustified_active", false))
	var just_raw: Variant = data.get("justify", {})
	if just_raw is Dictionary:
		st["justify"] = _normalize_justify(just_raw as Dictionary)
	else:
		st["justify"] = _inactive_justify()
	_write(st)


static func load_missing_save() -> void:
	## Flag-on load of a save that has no stability key. Drop stale runtime state.
	## Getters then return stability 1.0 and no justification in progress.
	if not enabled():
		return
	_erase()


static func clear_state() -> void:
	_erase()


static func _default_state() -> Dictionary:
	return {
		"stability": 1.0,
		"war_days": 0,
		"unjustified_active": false,
		"justify": _inactive_justify(),
	}


static func _inactive_justify() -> Dictionary:
	return {
		"active": false,
		"province_id": 0,
		"days_done": 0,
		"days_needed": JUSTIFY_DAYS,
		"complete": false,
	}


static func _normalize_justify(raw: Dictionary) -> Dictionary:
	var just := _inactive_justify()
	just["active"] = bool(raw.get("active", false))
	just["province_id"] = int(raw.get("province_id", 0))
	just["days_done"] = clampi(int(raw.get("days_done", 0)), 0, JUSTIFY_DAYS)
	just["days_needed"] = JUSTIFY_DAYS
	just["complete"] = bool(raw.get("complete", false)) or int(just["days_done"]) >= JUSTIFY_DAYS and bool(just["active"])
	if not bool(just["active"]):
		just["complete"] = false
		just["days_done"] = 0
		just["province_id"] = 0
	return just


static func _note_from_justify(just: Dictionary, skipped: bool) -> Dictionary:
	var done := int(just.get("days_done", 0))
	var complete := bool(just.get("complete", false))
	var progress := "Justify %d/%d" % [done, JUSTIFY_DAYS]
	if complete:
		progress = "Justified %d/%d" % [JUSTIFY_DAYS, JUSTIFY_DAYS]
	return {
		"ok": true,
		"skipped": skipped,
		"days_done": done,
		"days_needed": JUSTIFY_DAYS,
		"complete": complete,
		"province_id": int(just.get("province_id", 0)),
		"progress": progress,
		"stability": stability(),
	}


static func _has_state() -> bool:
	if typeof(GameData) == TYPE_NIL or not ("peace_state" in GameData):
		return false
	return GameData.peace_state.get(KEY, null) is Dictionary


static func _read() -> Dictionary:
	if not _has_state():
		return {}
	return (GameData.peace_state[KEY] as Dictionary).duplicate(true)


static func _read_or_default() -> Dictionary:
	if not _has_state():
		return _default_state()
	var st := _read()
	if not st.has("stability"):
		st["stability"] = 1.0
	if not st.has("war_days"):
		st["war_days"] = 0
	if not st.has("unjustified_active"):
		st["unjustified_active"] = false
	var just_raw: Variant = st.get("justify", {})
	if just_raw is Dictionary:
		st["justify"] = _normalize_justify(just_raw as Dictionary)
	else:
		st["justify"] = _inactive_justify()
	return st


static func _write(st: Dictionary) -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	GameData.peace_state[KEY] = st.duplicate(true)


static func _erase() -> void:
	if typeof(GameData) == TYPE_NIL or not ("peace_state" in GameData):
		return
	GameData.peace_state.erase(KEY)


static func _campaign_wars_known() -> bool:
	if typeof(GameData) == TYPE_NIL:
		return false
	var cw: Variant = GameData.peace_state.get("campaign_wars", null)
	if not (cw is Dictionary):
		return false
	return (cw as Dictionary).get("wars", null) is Dictionary


static func _player_at_war(player: String) -> bool:
	if not _campaign_wars_known():
		return false
	var cw: Dictionary = GameData.peace_state.get("campaign_wars", {}) as Dictionary
	var wars: Dictionary = cw.get("wars", {}) as Dictionary
	var p := player.strip_edges().to_upper()
	if p.is_empty():
		return false
	for k in wars.keys():
		var row_v: Variant = wars[k]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var a := str(row.get("a", "")).strip_edges().to_upper()
		var b := str(row.get("b", "")).strip_edges().to_upper()
		if a == p or b == p:
			return true
	return false


static func _occupation_unrest() -> float:
	## Read the existing occupation store. Do not create entries.
	if typeof(GameData) == TYPE_NIL:
		return 0.0
	var raw: Variant = GameData.peace_state.get("occupation_province", null)
	if not (raw is Dictionary):
		return 0.0
	var store: Dictionary = raw
	if store.is_empty():
		return 0.0
	var sum := 0.0
	var n := 0
	for k in store.keys():
		var row_v: Variant = store[k]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var r := 0.0
		if row.has("resistance_level"):
			r = float(row.get("resistance_level", 0.0))
		elif row.has("resistance"):
			r = float(row.get("resistance", 0.0))
		sum += clampf(r, 0.0, 1.0)
		n += 1
	if n <= 0:
		return 0.0
	return clampf(sum / float(n), 0.0, 1.0)
