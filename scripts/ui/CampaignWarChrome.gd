# scripts/ui/CampaignWarChrome.gd
## Inspector "Declare war" button. Mounted from MapRenderer with one call.
class_name CampaignWarChrome
extends RefCounted


static func mount(host: Node, province: Province) -> void:
	if host == null:
		return
	var btn := host.get_node_or_null("BtnDeclareWar") as Button
	if btn == null:
		btn = Button.new()
		btn.name = "BtnDeclareWar"
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		btn.offset_left = 8.0
		btn.offset_top = 96.0
		btn.offset_right = 280.0
		btn.offset_bottom = 120.0
		btn.pressed.connect(_on_pressed.bind(host))
		host.add_child(btn)
	if province == null or bool(province.is_sea):
		btn.visible = false
		return
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		btn.visible = false
		return
	var player := "GER"
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		player = str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	var owner := str(province.owner_tag).strip_edges().to_upper()
	if owner.is_empty() or owner == player or not WarStateDomain.borders_tag(int(province.id), player):
		btn.visible = false
		return
	if WarStateDomain.is_at_war(player, owner):
		btn.visible = false
		return
	if WarStateDomain.in_truce(player, owner):
		btn.visible = true
		btn.disabled = true
		btn.text = "Truce with %s" % WarStateDomain.tag_name(owner)
		btn.set_meta("declare_pid", int(province.id))
		return
	btn.disabled = false
	btn.set_meta("declare_pid", int(province.id))
	var left := WarStateDomain.player_justify_days_left(owner)
	var ready := WarStateDomain.player_justify_is_ready()
	var name := WarStateDomain.tag_name(owner)
	if ready:
		btn.text = "Declare war on %s" % name
	elif WarStateDomain.player_has_justify(owner):
		btn.text = "Justifying war on %s (%d)" % [name, left]
	else:
		btn.text = "Justify war on %s" % name
	btn.visible = true


static func _on_pressed(host: Node) -> void:
	var btn := host.get_node_or_null("BtnDeclareWar") as Button
	if btn == null:
		return
	var pid := int(btn.get_meta("declare_pid", -1))
	if pid <= 0 or typeof(WarStateDomain) == TYPE_NIL:
		return
	if WarStateDomain.player_justify_is_ready():
		var declared: Dictionary = WarStateDomain.player_declare_from_province(pid)
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_war_goal_live"):
			GameData.apply_war_goal_live("execute", pid)
		_toast(str(declared.get("reason", "War declared")))
	else:
		WarStateDomain.begin_player_justify_from_province(pid)
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_war_goal_live"):
			GameData.apply_war_goal_live("justify", pid)
		_toast("Justification started")
	var p: Province = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
	mount(host, p)


static func _toast(text: String) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(text, 2.5)
