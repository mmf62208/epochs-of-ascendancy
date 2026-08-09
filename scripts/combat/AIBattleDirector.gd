# scripts/combat/AIBattleDirector.gd
## Lightweight AI battle initiation — non-player countries launch limited province assaults.
## Complements BattleManager (player Ctrl+click / Attack button). Autoload: AIBattleDirector.
extends Node

signal ai_assault_launched(attacker_tag: String, target_province_id: int, result: Dictionary)

const ASSAULT_INTERVAL_DAYS := 3
const MAX_ASSAULTS_PER_TICK := 2

var _day_counter: int = 0
var _enabled: bool = true


func _ready() -> void:
	call_deferred("_try_connect_time")


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func _try_connect_time() -> void:
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)
		print("AIBattleDirector: connected to daily tick.")


func _on_game_day_advanced(_year: int, _month: int, _day: int) -> void:
	if not _enabled:
		return
	_day_counter += 1
	if _day_counter % ASSAULT_INTERVAL_DAYS != 0:
		return
	run_ai_assault_pass()


## Public entry for tests / debug.
func run_ai_assault_pass() -> int:
	if typeof(BattleManager) == TYPE_NIL or typeof(MapManager) == TYPE_NIL:
		return 0
	if typeof(SupplyManager) == TYPE_NIL:
		return 0

	var player := _player_tag()
	var launched := 0
	var candidates := _collect_assault_candidates(player)
	candidates.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))

	for entry in candidates:
		if launched >= MAX_ASSAULTS_PER_TICK:
			break
		var attacker := str(entry.get("attacker_tag", ""))
		var target_pid := int(entry.get("target_province_id", -1))
		var from_pid := int(entry.get("from_province_id", -1))
		var fid := str(entry.get("formation_id", ""))
		if attacker.is_empty() or target_pid < 0:
			continue
		var assault: Dictionary = BattleManager.execute_province_assault(
			attacker, target_pid, from_pid, fid
		)
		if not bool(assault.get("success", false)):
			continue
		launched += 1
		var result: Dictionary = assault.get("result", {}) as Dictionary
		ai_assault_launched.emit(attacker, target_pid, result)
		_announce(attacker, target_pid, result)

	if launched > 0:
		print("AIBattleDirector: launched %d AI assault(s)." % launched)
	return launched


func _collect_assault_candidates(player_tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var deployments: Dictionary = {}
	if "division_deployments" in SupplyManager:
		deployments = SupplyManager.division_deployments

	if deployments.is_empty():
		return _collect_via_province_scan(player_tag)

	for key in deployments.keys():
		var entry: Variant = deployments[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dep: Dictionary = entry
		var fid := str(dep.get("formation_id", key))
		var province_id := int(dep.get("province_id", -1))
		var country_tag := str(dep.get("country_tag", dep.get("owner_tag", ""))).to_upper()
		if country_tag.is_empty() or country_tag == player_tag:
			continue
		if province_id < 0:
			continue
		_append_targets_from_staging(out, country_tag, province_id, fid)
	return out


func _collect_via_province_scan(player_tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen_tags: Dictionary = {}
	for pid in MapManager.get_all_provinces().keys():
		var p: Province = MapManager.get_province(int(pid))
		if p == null:
			continue
		var tag := p.controller_tag.strip_edges().to_upper()
		if tag.is_empty():
			tag = p.owner_tag.strip_edges().to_upper()
		if tag.is_empty() or tag == player_tag:
			continue
		if seen_tags.has(tag) and int(seen_tags[tag]) > 4:
			continue
		var divisions: Array = BattleManager.get_divisions_at_province(int(pid), tag)
		if divisions.is_empty():
			continue
		seen_tags[tag] = int(seen_tags.get(tag, 0)) + 1
		var fid := str(divisions[0].get("formation_id", ""))
		_append_targets_from_staging(out, tag, int(pid), fid)
	return out


func _append_targets_from_staging(
	out: Array[Dictionary],
	attacker_tag: String,
	from_pid: int,
	formation_id: String,
) -> void:
	for nid in MapManager.get_adjacent_provinces(from_pid):
		var target_pid := int(nid)
		var preview := BattleManager.can_assault_province(attacker_tag, target_pid, from_pid)
		if not bool(preview.get("ok", false)):
			continue
		var atk_power := float(preview.get("attack_power", 0.0))
		var def_tag := str(preview.get("defender_tag", ""))
		# Prefer attacking the human player; still allow AI vs AI at lower priority
		var player := _player_tag()
		var score := atk_power
		if def_tag == player:
			score *= 1.35
		# Soft filter: skip hopeless attacks
		if atk_power < 1.0:
			continue
		out.append({
			"attacker_tag": attacker_tag,
			"from_province_id": from_pid,
			"target_province_id": target_pid,
			"formation_id": formation_id,
			"attack_power": atk_power,
			"score": score,
			"defender_tag": def_tag,
		})


func _announce(attacker: String, target_pid: int, result: Dictionary) -> void:
	if typeof(LeaderEventUI) == TYPE_NIL:
		return
	var name := str(target_pid)
	var p: Province = MapManager.get_province(target_pid) if typeof(MapManager) != TYPE_NIL else null
	if p != null:
		name = p.name
	var captured := bool(result.get("province_control_change", false))
	var outcome := str(result.get("outcome", result.get("winner", "battle")))
	var title := "AI offensive" if not captured else "AI capture"
	var body := "%s attacks %s — %s" % [attacker, name, outcome]
	if LeaderEventUI.has_method("post_news"):
		LeaderEventUI.post_news(title, body)
	elif LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("%s: %s" % [title, body], 3.0, false)


func _player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var t := str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
		if not t.is_empty():
			return t
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.get("player_tag"):
		return str(SupplyManager.player_tag).strip_edges().to_upper()
	return "USA"
