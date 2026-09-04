# scripts/map/AgentPresenceLayer.gd
## On-mission player agents as map tokens. Cap 8. Node2D _draw only — no pulse.

class_name AgentPresenceLayer
extends Node2D

const MAX_TOKENS := 8
const _CAPITALS := {
	"GER": 710300,
	"FRA": 710739,
	"ENG": 711414,
	"USA": 800792,
	"SOV": 903534,
	"ITA": 710963,
	"JAP": 903981,
	"POL": 711112,
}

@export var max_tokens: int = MAX_TOKENS
@export var token_radius: float = 8.0

var _centroids: Dictionary = {}
var _tokens: Array = []
var _player_tag: String = "GER"


func _ready() -> void:
	z_index = 7
	add_to_group("agent_presence")
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_signal("game_day_advanced"):
		if not TimeManager.game_day_advanced.is_connected(_on_day):
			TimeManager.game_day_advanced.connect(_on_day)
	if typeof(AgentManager) != TYPE_NIL and AgentManager.has_signal("agent_assigned_to_mission"):
		if not AgentManager.agent_assigned_to_mission.is_connected(_on_mission):
			AgentManager.agent_assigned_to_mission.connect(_on_mission)


func setup(centroids: Dictionary, player_tag: String = "") -> void:
	_centroids = centroids
	var tag := player_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = _living_player_tag()
	_player_tag = tag if not tag.is_empty() else "GER"
	rebuild()


func rebuild() -> void:
	_tokens = _collect_on_mission()
	queue_redraw()


func token_count() -> int:
	return _tokens.size()


func _on_day(_a: int = 0, _b: int = 0, _c: int = 0) -> void:
	rebuild()


func _on_mission(_agent_id: String = "", _mission_id: String = "") -> void:
	rebuild()


func _collect_on_mission() -> Array:
	var out: Array = []
	if typeof(AgentManager) == TYPE_NIL or not AgentManager.has_method("get_agents_for_country"):
		return out
	var roster: Array = AgentManager.get_agents_for_country(_player_tag)
	for ag in roster:
		if out.size() >= max_tokens:
			break
		if ag == null:
			continue
		var on := false
		var pid := 0
		var mid := ""
		var target := ""
		var st := ""
		if ag is Dictionary:
			st = str(ag.get("status", ""))
			mid = str(ag.get("current_mission_id", ""))
			pid = int(ag.get("assigned_province_id", 0))
			target = str(ag.get("assigned_target_tag", ""))
		else:
			st = str(ag.status)
			mid = str(ag.current_mission_id)
			pid = int(ag.assigned_province_id)
			target = str(ag.assigned_target_tag)
		if st.strip_edges().to_lower() == "on_mission" or not mid.strip_edges().is_empty():
			on = true
		if not on:
			continue
		if pid <= 0:
			pid = int(_CAPITALS.get(target.strip_edges().to_upper(), 0))
		if pid <= 0:
			pid = int(_CAPITALS.get(_player_tag, 0))
		if pid <= 0:
			continue
		out.append({"pid": pid, "missing_key": "", "on_mission": true})
	return out


func _living_player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		return str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	return "GER"


func _draw() -> void:
	if _tokens.is_empty():
		return
	for row_v in _tokens:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var pid := int(row.get("pid", -1))
		if pid <= 0 or not _centroids.has(pid):
			continue
		var c: Vector2 = _centroids[pid]
		var col := Color(0.62, 0.42, 0.95, 0.95)
		draw_arc(c + Vector2(10, -10), token_radius, 0.0, TAU, 16, col, 2.0, true)
		draw_circle(c + Vector2(10, -10), token_radius - 2.0, Color(0.12, 0.08, 0.18, 0.8))
		draw_circle(c + Vector2(10, -10), 2.4, col)
