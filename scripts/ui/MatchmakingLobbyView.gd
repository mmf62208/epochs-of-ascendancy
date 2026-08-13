# scripts/ui/MatchmakingLobbyView.gd
## Player-facing thin matchmaking lobby (not full NAT/WebRTC).
class_name MatchmakingLobbyView
extends Window

const TAG_FALLBACK := "USA"

var _player_tag: String = TAG_FALLBACK
var _title: Label
var _queue_body: RichTextLabel
var _status: Label
var _tag_a: LineEdit
var _tag_b: LineEdit
var _region: LineEdit
var _enqueue_a_btn: Button
var _enqueue_b_btn: Button
var _match_btn: Button
var _smoke_btn: Button
var _refresh_btn: Button
var _close_btn: Button
var _last_match: Dictionary = {}


func _ready() -> void:
	title = "Matchmaking Lobby"
	size = Vector2i(640, 420)
	unresizable = false
	_resolve_player()
	_build_ui()
	refresh_lobby()


func _resolve_player() -> void:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		_player_tag = str(LeaderManager.get_player_country_tag())
	if _player_tag.is_empty():
		_player_tag = TAG_FALLBACK


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	root.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_title = Label.new()
	_title.text = "Matchmaking — queue · pair · dedicated session"
	_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_title)
	var form := HBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	vbox.add_child(form)
	_tag_a = LineEdit.new()
	_tag_a.placeholder_text = "Tag A"
	_tag_a.text = _player_tag
	_tag_a.custom_minimum_size = Vector2(80, 0)
	form.add_child(_tag_a)
	_tag_b = LineEdit.new()
	_tag_b.placeholder_text = "Tag B"
	_tag_b.text = "GER"
	_tag_b.custom_minimum_size = Vector2(80, 0)
	form.add_child(_tag_b)
	_region = LineEdit.new()
	_region.placeholder_text = "region"
	_region.text = "global"
	_region.custom_minimum_size = Vector2(100, 0)
	form.add_child(_region)
	_enqueue_a_btn = Button.new()
	_enqueue_a_btn.text = "Enqueue A"
	_enqueue_a_btn.pressed.connect(_on_enqueue_a)
	form.add_child(_enqueue_a_btn)
	_enqueue_b_btn = Button.new()
	_enqueue_b_btn.text = "Enqueue B"
	_enqueue_b_btn.pressed.connect(_on_enqueue_b)
	form.add_child(_enqueue_b_btn)
	_match_btn = Button.new()
	_match_btn.text = "Try Match"
	_match_btn.pressed.connect(_on_try_match)
	form.add_child(_match_btn)
	_queue_body = RichTextLabel.new()
	_queue_body.bbcode_enabled = true
	_queue_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_queue_body.custom_minimum_size = Vector2(0, 180)
	_queue_body.scroll_active = true
	vbox.add_child(_queue_body)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Not full NAT/WebRTC — OfflineMultiplayerPeer dedicated path."
	vbox.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(row)
	_smoke_btn = Button.new()
	_smoke_btn.text = "Smoke"
	_smoke_btn.pressed.connect(_on_smoke)
	row.add_child(_smoke_btn)
	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.pressed.connect(refresh_lobby)
	row.add_child(_refresh_btn)
	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.pressed.connect(hide)
	row.add_child(_close_btn)


func refresh_lobby() -> void:
	if typeof(NetSessionManager) == TYPE_NIL:
		if _queue_body:
			_queue_body.text = "[i]NetSessionManager unavailable.[/i]"
		return
	var q: Array = []
	if NetSessionManager.has_method("get_match_queue"):
		q = NetSessionManager.get_match_queue()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Queue (%d)[/b]" % q.size())
	if q.is_empty():
		lines.append("  (empty)")
	for e in q:
		if e is Dictionary:
			var row: Dictionary = e as Dictionary
			lines.append("  • %s · %s · region=%s · skill=%s" % [
				str(row.get("queue_id", "")),
				str(row.get("tag", "")),
				str(row.get("region", "")),
				str(row.get("skill", "")),
			])
	if not _last_match.is_empty():
		lines.append("")
		lines.append("[b]Last match[/b]")
		lines.append("  ok=%s peers=%s tags=%s dedicated=%s" % [
			str(_last_match.get("ok", false)),
			str(_last_match.get("peer_n", 0)),
			str(_last_match.get("tags", [])),
			str(_last_match.get("dedicated_server_ready", false)),
		])
	if _queue_body:
		_queue_body.text = "\n".join(lines)


func _on_enqueue_a() -> void:
	_enqueue_tag(_tag_a.text if _tag_a else _player_tag)


func _on_enqueue_b() -> void:
	_enqueue_tag(_tag_b.text if _tag_b else "GER")


func _enqueue_tag(tag: String) -> void:
	if typeof(NetSessionManager) == TYPE_NIL or not NetSessionManager.has_method("enqueue_matchmaking"):
		return
	var region := _region.text if _region else "global"
	var res: Dictionary = NetSessionManager.enqueue_matchmaking(tag, {"region": region})
	if _status:
		_status.text = "Enqueue %s → %s" % [tag, str(res.get("ok", false))]
	refresh_lobby()


func _on_try_match() -> void:
	if typeof(NetSessionManager) == TYPE_NIL or not NetSessionManager.has_method("try_matchmake"):
		return
	var res: Dictionary = NetSessionManager.try_matchmake({"seed": 2200})
	_last_match = res.duplicate(true)
	if _status:
		_status.text = "Match ok=%s dedicated=%s" % [
			str(res.get("ok", false)), str(res.get("dedicated_server_ready", false)),
		]
	refresh_lobby()


func _on_smoke() -> void:
	if typeof(NetSessionManager) == TYPE_NIL or not NetSessionManager.has_method("run_matchmaking_smoke"):
		return
	var res: Dictionary = NetSessionManager.run_matchmaking_smoke()
	_last_match = res.get("match", {}) as Dictionary if res.get("match") is Dictionary else res.duplicate(true)
	if _status:
		_status.text = "Smoke ok=%s (not full NAT/WebRTC)" % str(res.get("ok", false))
	refresh_lobby()


## Dual/live helper: full lobby path without click simulation.
func apply_lobby_match_path(tag_a: String = "USA", tag_b: String = "GER", region: String = "global") -> Dictionary:
	if typeof(NetSessionManager) == TYPE_NIL:
		return {"ok": false, "error": "no_net", "ui": "MatchmakingLobbyView"}
	if NetSessionManager.has_method("clear_match_queue"):
		NetSessionManager.clear_match_queue()
	var e1: Dictionary = NetSessionManager.enqueue_matchmaking(tag_a, {"region": region})
	var e2: Dictionary = NetSessionManager.enqueue_matchmaking(tag_b, {"region": region})
	var m: Dictionary = NetSessionManager.try_matchmake({"seed": 2210})
	_last_match = m.duplicate(true)
	var ok: bool = bool(e1.get("ok", false)) and bool(e2.get("ok", false)) \
		and bool(m.get("ok", false)) and bool(m.get("dedicated_server_ready", false))
	return {
		"ok": ok,
		"enqueue_a": e1,
		"enqueue_b": e2,
		"match": m,
		"ui": "MatchmakingLobbyView",
		"lobby_surface": true,
		"not_full_nat_webrtc": true,
	}


func show_lobby(tag: String = "") -> void:
	if not tag.is_empty():
		_player_tag = tag.strip_edges().to_upper()
		if _tag_a:
			_tag_a.text = _player_tag
	popup_centered()
	refresh_lobby()
