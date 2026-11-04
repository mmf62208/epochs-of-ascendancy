# scripts/core/VictoryPathsDomain.gd
## 1936 victory paths. Thresholds live in data/campaign/victory_paths.json.
## Inactive unless GameData.victory_paths_enabled() (campaign toggle, or EOA_VICTORY_PATHS=1).
## Flag off: no state, no save key, no RNG, no war/tech/production writes.
## The daily tick only reads clocks, listed capitals, existing wars, and factory
## owner tags. It does not boot WarStateDomain or create tech country state.
class_name VictoryPathsDomain
extends RefCounted

const RULES_PATH := "res://data/campaign/victory_paths.json"
const KEY := "victory_paths"
const OFF_SEED_BASELINE := "20fe9063de285f19d4f9b8a105abfd31"

static var _rules_cache: Dictionary = {}
static var _rules_loaded: bool = false
static var _override: Dictionary = {}
static var _session_elapsed: int = -1000001


static func enabled() -> bool:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("victory_paths_enabled"):
		return false
	return bool(GameData.victory_paths_enabled())


static func reset_for_test() -> void:
	_rules_loaded = false
	_rules_cache = {}
	_override = {}
	_session_elapsed = -1000001
	_erase()


static func set_snapshot_override(snapshot: Dictionary) -> void:
	_override = snapshot.duplicate(true)


static func clear_snapshot_override() -> void:
	_override = {}


static func load_rules() -> Dictionary:
	if _rules_loaded:
		return _rules_cache
	_rules_loaded = true
	_rules_cache = {}
	if not FileAccess.file_exists(RULES_PATH):
		return _rules_cache
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		return _rules_cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_rules_cache = parsed
	return _rules_cache


static func has_state() -> bool:
	return _has_state()


static func clear_state() -> void:
	_erase()


static func progress_text() -> String:
	if not enabled():
		return ""
	var rules := load_rules()
	if rules.is_empty():
		return ""
	var snap := _current_snapshot(rules)
	var prog := _read() if _has_state() else {}
	return _lines(snap, rules, prog)


## Pure. snapshot carries forced metrics. progress is the previous blob.
## Returning won does not write state and does not open the end screen.
static func evaluate(snapshot: Dictionary, rules: Dictionary, progress: Dictionary) -> Dictionary:
	var prog := _blank_progress(progress)
	var player := str(snapshot.get("player_tag", "")).strip_edges().to_upper()
	var empty := {
		"won": false,
		"winner": "",
		"path_id": "",
		"title": "",
		"reason": "",
		"stats": "",
		"outcome": "",
		"player_tag": player,
		"progress": prog,
	}
	if bool(prog.get("latched", false)) or not bool(rules.get("enabled", false)):
		return empty
	var paths := _paths(rules)
	var text := _text(rules)
	var tags := _eval_tags(rules, snapshot)
	_advance_holds(snapshot, rules, prog, tags)
	var order := _priority(rules, paths)
	for pid_v in order:
		var pid := str(pid_v)
		if not paths.has(pid):
			continue
		var path_v: Variant = paths[pid]
		if not (path_v is Dictionary):
			continue
		var path: Dictionary = path_v
		if not _path_enabled(path):
			continue
		var found := _path_winner(pid, path, snapshot, rules, prog, tags, player)
		var winner := str(found.get("winner", ""))
		if winner.is_empty():
			continue
		var row := _tag_row(snapshot, winner)
		var title := str(path.get("title", pid))
		var outcome := "win" if winner == player and not player.is_empty() else "loss"
		var reason := ""
		if outcome == "loss":
			reason = _fill(str(text.get("defeat_reason", "{winner} won {title} first.")), {
				"winner": winner,
				"title": title,
			})
		else:
			reason = _win_reason(pid, path, row, snapshot, prog, text, title, found)
		return {
			"won": true,
			"winner": winner,
			"path_id": pid,
			"title": title,
			"reason": reason,
			"stats": _stats_line(pid, path, row, snapshot, prog, text),
			"outcome": outcome,
			"player_tag": player,
			"progress": prog,
		}
	return empty


static func tick_day() -> Dictionary:
	if not enabled():
		return {"ok": true, "skipped": true, "created": false, "presented": false}
	var rules := load_rules()
	if not bool(rules.get("enabled", false)):
		return {"ok": true, "skipped": true, "created": false, "presented": false}
	var snap := _current_snapshot(rules)
	var elapsed := int(snap.get("elapsed", _live_elapsed()))
	if _session_elapsed == elapsed:
		return {"ok": true, "skipped": true, "created": _has_state(), "presented": false, "duplicate": true}
	_session_elapsed = elapsed
	var had := _has_state()
	var prev := _read() if had else {}
	var result := evaluate(snap, rules, prev)
	var prog: Dictionary = result.get("progress", {})
	prog["last_elapsed"] = elapsed
	var presented := false
	if bool(result.get("won", false)) and not bool(prog.get("latched", false)):
		presented = _present(result)
		if presented:
			prog["latched"] = true
			prog["winner"] = str(result.get("winner", ""))
			prog["path_id"] = str(result.get("path_id", ""))
			result["progress"] = prog
	if _worth_saving(prog):
		_write(prog)
	elif had:
		_erase()
		_session_elapsed = elapsed
	return {
		"ok": true,
		"skipped": false,
		"created": _has_state(),
		"presented": presented,
		"won": bool(result.get("won", false)),
		"winner": str(result.get("winner", "")),
		"path_id": str(result.get("path_id", "")),
		"outcome": str(result.get("outcome", "")),
	}


static func export_save_blob() -> Dictionary:
	if not enabled() or not _has_state():
		return {}
	var st := _read()
	if not _worth_saving(st):
		return {}
	return st.duplicate(true)


static func import_save_blob(data: Dictionary) -> void:
	if not enabled():
		return
	var st := _normalize(data)
	_write(st)
	_session_elapsed = int(st.get("last_elapsed", -1000001))


static func load_missing_save() -> void:
	if not enabled():
		return
	_erase()


static func _present(result: Dictionary) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for n in tree.get_nodes_in_group("campaign_ink_end_screen"):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				return false
	var scr: Script = load("res://scripts/ui/CampaignInkEndScreen.gd") as Script
	if scr == null:
		return false
	var detail := {
		"path_title": str(result.get("title", "")),
		"path_id": str(result.get("path_id", "")),
		"winner": str(result.get("winner", "")),
		"stats": str(result.get("stats", "")),
	}
	var tag := str(result.get("player_tag", ""))
	var reason := str(result.get("reason", ""))
	if str(result.get("outcome", "")) == "loss":
		if scr.has_method("present_loss"):
			scr.call("present_loss", tag, reason, detail)
			return true
		return false
	if scr.has_method("present_win"):
		scr.call("present_win", tag, reason, detail)
		return true
	return false


static func _path_winner(pid: String, path: Dictionary, snapshot: Dictionary, rules: Dictionary, progress: Dictionary, tags: Array, player: String) -> Dictionary:
	if pid == "score":
		return _score_winner(path, snapshot, rules, tags)
	var met: Array = []
	var how: Dictionary = {}
	for tag_v in tags:
		var tag := str(tag_v)
		var row := _tag_row(snapshot, tag)
		var gate := _gate(pid, path, row, snapshot, progress)
		if bool(gate.get("met", false)):
			met.append(tag)
			how[tag] = gate
	if met.is_empty():
		return {}
	var winner := ""
	if not player.is_empty() and player in met:
		winner = player
	else:
		met.sort()
		winner = str(met[0])
	var gate_v: Variant = how.get(winner, {})
	var gate_d: Dictionary = gate_v if gate_v is Dictionary else {}
	gate_d["winner"] = winner
	return gate_d


static func _score_winner(path: Dictionary, snapshot: Dictionary, rules: Dictionary, tags: Array) -> Dictionary:
	if not _date_reached(snapshot, rules, path):
		return {}
	var best_tag := ""
	var best := 0.0
	var tie := false
	var have := false
	for tag_v in tags:
		var tag := str(tag_v)
		var sc := _score_value(path, _tag_row(snapshot, tag))
		if not have or sc > best:
			best_tag = tag
			best = sc
			have = true
			tie = false
		elif have and is_equal_approx(sc, best):
			tie = true
	if not have or tie or best_tag.is_empty():
		return {}
	return {"winner": best_tag, "met": true, "score": best}


static func _gate(pid: String, path: Dictionary, row: Dictionary, snapshot: Dictionary, progress: Dictionary) -> Dictionary:
	if pid == "conquest":
		return _conquest_gate(path, row)
	if pid == "atomic":
		var tag := str(row.get("tag", ""))
		var hold := _counter(progress, "atomic_hold", tag)
		var need := int(path.get("hold_days", 0))
		return {"met": need > 0 and hold >= need, "hold": hold, "need": need}
	if pid == "arsenal":
		var tag_a := str(row.get("tag", ""))
		var streak := _counter(progress, "arsenal_streak", tag_a)
		var need_a := int(path.get("sustain_days", 0))
		var world := int(snapshot.get("world_factories", 0))
		var fac := int(row.get("factories", 0))
		return {
			"met": need_a > 0 and streak >= need_a,
			"streak": streak,
			"need": need_a,
			"pct": _pct(fac, world),
		}
	return {}


static func _conquest_gate(path: Dictionary, row: Dictionary) -> Dictionary:
	var total := int(row.get("target_total", 0))
	if total <= 0:
		total = _target_ids(path).size()
	var held := int(row.get("controlled_targets", 0))
	var by_ratio := _meets_ratio(held, total, float(path.get("capital_ratio", 1.0)))
	var by_caps := false
	if bool(path.get("or_all_major_enemies_capitulated", false)):
		by_caps = _all_capitulated(row)
	return {"met": by_ratio or by_caps, "by_ratio": by_ratio, "by_caps": by_caps, "held": held, "total": total}


static func _advance_holds(snapshot: Dictionary, rules: Dictionary, progress: Dictionary, tags: Array) -> void:
	var paths := _paths(rules)
	var atomic_v: Variant = paths.get("atomic", {})
	var arsenal_v: Variant = paths.get("arsenal", {})
	for tag_v in tags:
		var tag := str(tag_v)
		var row := _tag_row(snapshot, tag)
		row["tag"] = tag
		if atomic_v is Dictionary and _path_enabled(atomic_v):
			var ready := _atomic_ready(atomic_v, row)
			var hold := _counter(progress, "atomic_hold", tag)
			if ready:
				hold += 1
			elif bool((atomic_v as Dictionary).get("reset_if_lost", true)):
				hold = 0
			_set_counter(progress, "atomic_hold", tag, hold)
		if arsenal_v is Dictionary and _path_enabled(arsenal_v):
			var world := int(snapshot.get("world_factories", 0))
			var fac := int(row.get("factories", 0))
			var share := float((arsenal_v as Dictionary).get("industry_share", 1.0))
			var streak := _counter(progress, "arsenal_streak", tag)
			if _meets_ratio(fac, world, share):
				streak += 1
			elif bool((arsenal_v as Dictionary).get("reset_if_below", true)):
				streak = 0
			_set_counter(progress, "arsenal_streak", tag, streak)


static func _atomic_ready(path: Dictionary, row: Dictionary) -> bool:
	if row.has("atomic_ready"):
		return bool(row.get("atomic_ready", false))
	if bool(row.get("atomic_project", false)):
		return true
	var need := int(row.get("atomic_tech_need", 0))
	var done := int(row.get("atomic_tech_done", 0))
	if need <= 0:
		var ids: Variant = path.get("tech_ids", [])
		if ids is Array:
			need = (ids as Array).size()
	if need <= 0:
		return false
	var match := str(path.get("tech_match", "all"))
	if match == "any":
		return done > 0
	return done >= need


static func _win_reason(pid: String, path: Dictionary, row: Dictionary, snapshot: Dictionary, progress: Dictionary, text: Dictionary, title: String, found: Dictionary) -> String:
	var vars := _vars(pid, path, row, snapshot, progress, title)
	if pid == "conquest" and bool(found.get("by_caps", false)) and not bool(found.get("by_ratio", false)):
		return _fill(str(text.get("conquest_cap_reason", "{title}: every major enemy has capitulated.")), vars)
	if pid == "conquest":
		return _fill(str(text.get("conquest_reason", "{title}: {held} of {total} target capitals.")), vars)
	if pid == "atomic":
		return _fill(str(text.get("atomic_reason", "{title}: the atomic project held.")), vars)
	if pid == "arsenal":
		return _fill(str(text.get("arsenal_reason", "{title}: world industry share held.")), vars)
	if pid == "score":
		return _fill(str(text.get("score_reason", "{title}: highest score on {date}.")), vars)
	return title


static func _stats_line(pid: String, path: Dictionary, row: Dictionary, snapshot: Dictionary, progress: Dictionary, text: Dictionary) -> String:
	var vars := _vars(pid, path, row, snapshot, progress, str(path.get("title", pid)))
	if pid == "conquest":
		return _fill(str(text.get("stats_conquest", "Capitals {held}/{total}")), vars)
	if pid == "atomic":
		return _fill(str(text.get("stats_atomic", "Hold {hold}/{need}")), vars)
	if pid == "arsenal":
		return _fill(str(text.get("stats_arsenal", "Share {pct}% · {streak}/{need}")), vars)
	if pid == "score":
		return _fill(str(text.get("stats_score", "Score {score}")), vars)
	return ""


static func _lines(snapshot: Dictionary, rules: Dictionary, progress: Dictionary) -> String:
	var player := str(snapshot.get("player_tag", _player_tag())).strip_edges().to_upper()
	var row := _tag_row(snapshot, player)
	row["tag"] = player
	var paths := _paths(rules)
	var text := _text(rules)
	var lines: PackedStringArray = PackedStringArray()
	for pid_v in _priority(rules, paths):
		var pid := str(pid_v)
		if not paths.has(pid):
			continue
		var path_v: Variant = paths[pid]
		if not (path_v is Dictionary):
			continue
		var path: Dictionary = path_v
		var title := str(path.get("title", pid))
		if not _path_enabled(path):
			var label := str(path.get("progress_label", "")).strip_edges()
			if label.is_empty():
				continue
			lines.append(_fill(str(text.get("line_off", "{label}")), {"label": label, "title": title}))
			continue
		var vars := _vars(pid, path, row, snapshot, progress, title)
		var key := "line_%s" % pid
		var tmpl := str(text.get(key, "{title}"))
		lines.append(_fill(tmpl, vars))
	return "\n".join(lines)


static func _vars(pid: String, path: Dictionary, row: Dictionary, snapshot: Dictionary, progress: Dictionary, title: String) -> Dictionary:
	var tag := str(row.get("tag", ""))
	var held := int(row.get("controlled_targets", 0))
	var total := int(row.get("target_total", 0))
	if total <= 0:
		total = _live_target_count()
	var world := int(snapshot.get("world_factories", 0))
	var fac := int(row.get("factories", 0))
	var hold := _counter(progress, "atomic_hold", tag)
	var streak := _counter(progress, "arsenal_streak", tag)
	var need := int(path.get("hold_days", 0))
	if pid == "arsenal":
		need = int(path.get("sustain_days", 0))
	var score := _score_value(path, row) if pid == "score" else _display_score(row)
	return {
		"title": title,
		"tag": tag,
		"held": held,
		"total": total,
		"hold": hold,
		"need": need,
		"streak": streak,
		"pct": _pct(fac, world),
		"score": _num(score),
		"territory": _num(float(row.get("territory", held))),
		"industry": _num(float(row.get("industry", fac))),
		"wars": int(row.get("wars_won", 0)),
		"date": str(snapshot.get("date", "")),
		"winner": tag,
	}


static func _display_score(row: Dictionary) -> float:
	var rules := load_rules()
	var paths := _paths(rules)
	var score_v: Variant = paths.get("score", {})
	if not (score_v is Dictionary):
		return 0.0
	return _score_value(score_v, row)


static func _live_target_count() -> int:
	var rules := load_rules()
	return _target_ids(rules).size()


static func _score_value(path: Dictionary, row: Dictionary) -> float:
	var weights_v: Variant = path.get("weights", {})
	var weights: Dictionary = weights_v if weights_v is Dictionary else {}
	var territory := float(row.get("territory", row.get("controlled_targets", 0)))
	var industry := float(row.get("industry", row.get("factories", 0)))
	var wars := float(row.get("wars_won", 0))
	return (
		float(weights.get("territory", 0.0)) * territory
		+ float(weights.get("industry", 0.0)) * industry
		+ float(weights.get("wars_won", 0.0)) * wars
	)


static func _date_reached(snapshot: Dictionary, rules: Dictionary, path: Dictionary) -> bool:
	var end := str(path.get("end_date", rules.get("end_date", ""))).strip_edges()
	var today := str(snapshot.get("date", "")).strip_edges()
	if end.is_empty() or today.is_empty():
		return false
	return today >= end


static func _all_capitulated(row: Dictionary) -> bool:
	var enemies_v: Variant = row.get("major_enemies", [])
	if not (enemies_v is Array) or (enemies_v as Array).is_empty():
		return false
	var caps_v: Variant = row.get("capitulated_enemies", [])
	for e in enemies_v as Array:
		if not _array_has(caps_v, str(e).strip_edges().to_upper()):
			return false
	return true


static func _array_has(raw: Variant, needle: String) -> bool:
	if not (raw is Array):
		return false
	for item in raw as Array:
		if str(item).strip_edges().to_upper() == needle:
			return true
	return false


static func _meets_ratio(have: int, total: int, ratio: float) -> bool:
	if total <= 0 or ratio <= 0.0:
		return false
	var scaled := int(round(ratio * 1000000.0))
	return have * 1000000 >= scaled * total


static func _pct(have: int, total: int) -> int:
	if total <= 0:
		return 0
	return int(round(float(have) * 100.0 / float(total)))


static func _num(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value


static func _counter(progress: Dictionary, bucket: String, tag: String) -> int:
	if tag.is_empty():
		return 0
	var raw: Variant = progress.get(bucket, {})
	if not (raw is Dictionary):
		return 0
	return int((raw as Dictionary).get(tag, 0))


static func _set_counter(progress: Dictionary, bucket: String, tag: String, value: int) -> void:
	if tag.is_empty():
		return
	var raw: Variant = progress.get(bucket, {})
	var dict: Dictionary = (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	if value <= 0:
		dict.erase(tag)
	else:
		dict[tag] = value
	progress[bucket] = dict


static func _blank_progress(progress: Dictionary) -> Dictionary:
	return {
		"latched": bool(progress.get("latched", false)),
		"winner": str(progress.get("winner", "")),
		"path_id": str(progress.get("path_id", "")),
		"last_elapsed": int(progress.get("last_elapsed", -1000001)),
		"atomic_hold": _int_dict(progress.get("atomic_hold", {})),
		"arsenal_streak": _int_dict(progress.get("arsenal_streak", {})),
	}


static func _normalize(data: Dictionary) -> Dictionary:
	return _blank_progress(data)


static func _int_dict(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for k in (raw as Dictionary).keys():
		var n := int((raw as Dictionary)[k])
		if n > 0:
			out[str(k).strip_edges().to_upper()] = n
	return out


static func _worth_saving(progress: Dictionary) -> bool:
	if bool(progress.get("latched", false)):
		return true
	if not str(progress.get("winner", "")).is_empty():
		return true
	if not _int_dict(progress.get("atomic_hold", {})).is_empty():
		return true
	if not _int_dict(progress.get("arsenal_streak", {})).is_empty():
		return true
	return false


static func _current_snapshot(rules: Dictionary) -> Dictionary:
	if not _override.is_empty():
		return _override.duplicate(true)
	return _live_snapshot(rules)


static func _live_snapshot(rules: Dictionary) -> Dictionary:
	var targets := _target_ids(rules)
	var majors := _string_list(rules.get("majors", []))
	var tags := _string_list(rules.get("tags", []))
	var wars := _wars_dict()
	var caps := _capitulated_tags()
	var factories := _factory_counts()
	var by_tag: Dictionary = factories.get("by_tag", {})
	var world := int(factories.get("world", 0))
	var rows := {}
	for tag_v in tags:
		var tag := str(tag_v)
		var held := 0
		for pid in targets:
			if _controller(int(pid)) == tag:
				held += 1
		var enemies := _major_enemies(tag, majors, wars)
		var beaten: Array = []
		for e in enemies:
			if caps.has(str(e)):
				beaten.append(str(e))
		var path_atomic: Dictionary = {}
		var atomic_v: Variant = _paths(rules).get("atomic", {})
		if atomic_v is Dictionary:
			path_atomic = atomic_v
		rows[tag] = {
			"tag": tag,
			"controlled_targets": held,
			"target_total": targets.size(),
			"major_enemies": enemies,
			"capitulated_enemies": beaten,
			"atomic_ready": _live_atomic_ready(tag, path_atomic),
			"factories": int(by_tag.get(tag, 0)),
			"territory": held,
			"industry": int(by_tag.get(tag, 0)),
			"wars_won": beaten.size(),
		}
	return {
		"date": _today_iso(),
		"elapsed": _live_elapsed(),
		"player_tag": _player_tag(),
		"world_factories": world,
		"tags": rows,
	}


static func _live_atomic_ready(tag: String, path: Dictionary) -> bool:
	if path.is_empty():
		return false
	if _project_marked(tag, path):
		return true
	var ids: Variant = path.get("tech_ids", [])
	if not (ids is Array) or (ids as Array).is_empty():
		return false
	var done := 0
	var need := 0
	for id_v in ids as Array:
		need += 1
		if _tech_done(tag, str(id_v)):
			done += 1
	if str(path.get("tech_match", "all")) == "any":
		return done > 0
	return need > 0 and done >= need


static func _project_marked(tag: String, path: Dictionary) -> bool:
	var key := str(path.get("project_state_key", "")).strip_edges()
	if key.is_empty() or typeof(GameData) == TYPE_NIL or not ("peace_state" in GameData):
		return false
	var raw: Variant = GameData.peace_state.get(key, null)
	if not (raw is Dictionary) or not (raw as Dictionary).has(tag):
		return false
	var mark: Variant = (raw as Dictionary)[tag]
	var pid := str(path.get("project_id", "")).strip_edges()
	if mark is bool:
		return bool(mark)
	if mark is String:
		var text := str(mark).strip_edges()
		return text == "done" or (not pid.is_empty() and text == pid)
	if mark is Dictionary:
		if bool((mark as Dictionary).get("complete", false)):
			return true
		return not pid.is_empty() and bool((mark as Dictionary).get(pid, false))
	return false


static func _tech_done(tag: String, tech_id: String) -> bool:
	if tech_id.is_empty() or typeof(TechnologyManager) == TYPE_NIL:
		return false
	if not ("country_state" in TechnologyManager):
		return false
	var all: Variant = TechnologyManager.country_state
	if not (all is Dictionary) or not (all as Dictionary).has(tag):
		return false
	var state_v: Variant = (all as Dictionary)[tag]
	if not (state_v is Dictionary):
		return false
	var completed_v: Variant = (state_v as Dictionary).get("completed", {})
	if not (completed_v is Dictionary):
		return false
	return bool((completed_v as Dictionary).get(tech_id, false))


static func _factory_counts() -> Dictionary:
	var by_tag := {}
	var world := 0
	if typeof(FactoryManager) == TYPE_NIL or not ("factories" in FactoryManager):
		return {"by_tag": by_tag, "world": world}
	var facts: Variant = FactoryManager.factories
	if not (facts is Dictionary):
		return {"by_tag": by_tag, "world": world}
	for fid in (facts as Dictionary).keys():
		var factory: Variant = (facts as Dictionary)[fid]
		if factory == null:
			continue
		var owner := ""
		if "owner_tag" in factory:
			owner = str(factory.owner_tag).strip_edges().to_upper()
		world += 1
		if owner.is_empty():
			continue
		by_tag[owner] = int(by_tag.get(owner, 0)) + 1
	return {"by_tag": by_tag, "world": world}


static func _controller(province_id: int) -> String:
	if province_id <= 0 or typeof(MapManager) == TYPE_NIL:
		return ""
	if MapManager.has_method("get_province_controller"):
		return str(MapManager.get_province_controller(province_id)).strip_edges().to_upper()
	return ""


static func _wars_dict() -> Dictionary:
	if typeof(GameData) == TYPE_NIL or not ("peace_state" in GameData):
		return {}
	var raw: Variant = GameData.peace_state.get("campaign_wars", null)
	if not (raw is Dictionary):
		return {}
	var wars_v: Variant = (raw as Dictionary).get("wars", null)
	if wars_v is Dictionary:
		return wars_v
	return {}


static func _capitulated_tags() -> Dictionary:
	var out := {}
	if typeof(GameData) == TYPE_NIL or not ("peace_state" in GameData):
		return out
	var raw: Variant = GameData.peace_state.get("campaign_capitulation", null)
	if not (raw is Dictionary):
		return out
	var caps_v: Variant = (raw as Dictionary).get("capitulated", null)
	if not (caps_v is Dictionary):
		return out
	for k in (caps_v as Dictionary).keys():
		var tag := str(k).strip_edges().to_upper()
		if not tag.is_empty():
			out[tag] = true
	return out


static func _major_enemies(tag: String, majors: Array, wars: Dictionary) -> Array:
	var out: Array = []
	for m in majors:
		var other := str(m).strip_edges().to_upper()
		if other.is_empty() or other == tag:
			continue
		if wars.has(_pair(tag, other)):
			out.append(other)
	out.sort()
	return out


static func _pair(a: String, b: String) -> String:
	var x := a.strip_edges().to_upper()
	var y := b.strip_edges().to_upper()
	if x.is_empty() or y.is_empty() or x == y:
		return ""
	if x > y:
		var swap := x
		x = y
		y = swap
	return "%s|%s" % [x, y]


static func _target_ids(node: Dictionary) -> Array:
	var raw: Variant = node.get("targets", [])
	if not (raw is Array):
		var rules := load_rules()
		raw = rules.get("targets", [])
	var out: Array = []
	if not (raw is Array):
		return out
	for item in raw as Array:
		if item is Dictionary:
			var pid := int((item as Dictionary).get("id", 0))
			if pid > 0:
				out.append(pid)
		else:
			var n := int(item)
			if n > 0:
				out.append(n)
	return out


static func _string_list(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for item in raw as Array:
		var tag := str(item).strip_edges().to_upper()
		if not tag.is_empty() and tag not in out:
			out.append(tag)
	return out


static func _eval_tags(rules: Dictionary, snapshot: Dictionary) -> Array:
	var out := _string_list(rules.get("tags", []))
	if not out.is_empty():
		return out
	var tags_v: Variant = snapshot.get("tags", {})
	if tags_v is Dictionary:
		for k in (tags_v as Dictionary).keys():
			var tag := str(k).strip_edges().to_upper()
			if not tag.is_empty():
				out.append(tag)
		out.sort()
	return out


static func _priority(rules: Dictionary, paths: Dictionary) -> Array:
	var out: Array = []
	var listed: Variant = rules.get("priority", [])
	if listed is Array:
		for item in listed as Array:
			var pid := str(item).strip_edges()
			if pid.is_empty() or pid in out:
				continue
			if paths.has(pid):
				out.append(pid)
	for k in paths.keys():
		var pid2 := str(k)
		if pid2 not in out:
			out.append(pid2)
	return out


static func _paths(rules: Dictionary) -> Dictionary:
	var raw: Variant = rules.get("paths", {})
	if raw is Dictionary:
		return raw
	return {}


static func _text(rules: Dictionary) -> Dictionary:
	var raw: Variant = rules.get("text", {})
	if raw is Dictionary:
		return raw
	return {}


static func _path_enabled(path: Dictionary) -> bool:
	if bool(path.get("disabled", false)):
		return false
	return bool(path.get("enabled", false))


static func _tag_row(snapshot: Dictionary, tag: String) -> Dictionary:
	var tags_v: Variant = snapshot.get("tags", {})
	if not (tags_v is Dictionary):
		return {"tag": tag}
	var raw: Variant = (tags_v as Dictionary).get(tag, {})
	if raw is Dictionary:
		var row: Dictionary = (raw as Dictionary).duplicate(true)
		row["tag"] = tag
		return row
	return {"tag": tag}


static func _fill(template: String, vars: Dictionary) -> String:
	var out := template
	for k in vars.keys():
		out = out.replace("{%s}" % str(k), str(vars[k]))
	return out


static func _has_state() -> bool:
	if typeof(GameData) == TYPE_NIL or not ("peace_state" in GameData):
		return false
	return GameData.peace_state.get(KEY, null) is Dictionary


static func _read() -> Dictionary:
	if not _has_state():
		return {}
	return _normalize(GameData.peace_state[KEY])


static func _write(state: Dictionary) -> void:
	if typeof(GameData) == TYPE_NIL or not ("peace_state" in GameData):
		return
	GameData.peace_state[KEY] = _normalize(state)


static func _erase() -> void:
	_session_elapsed = -1000001
	if typeof(GameData) == TYPE_NIL or not ("peace_state" in GameData):
		return
	if GameData.peace_state.has(KEY):
		GameData.peace_state.erase(KEY)


static func _today_iso() -> String:
	if typeof(TimeManager) == TYPE_NIL:
		return ""
	return "%04d-%02d-%02d" % [
		int(TimeManager.current_year),
		int(TimeManager.current_month),
		int(TimeManager.current_day),
	]


static func _live_elapsed() -> int:
	if typeof(TimeManager) == TYPE_NIL or not ("total_days_elapsed" in TimeManager):
		return 0
	return int(TimeManager.total_days_elapsed)


static func _player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var raw := str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
		if not raw.is_empty():
			return raw
	return "GER"
