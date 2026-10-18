# scripts/ui/CampaignWarChrome.gd
## Inspector "Declare war" button. Mounted from MapRenderer with one call.
##
## Declare is only for the nation whose justification is ready. Other
## neighbours stay on Justify (N days) or a disabled state — a ready POL
## claim must not relabel every border inspector as Declare.
##
## Press-on-down matches Prod-1: leftover MapRenderer left-up swallow must
## not eat ACTION_MODE_BUTTON_RELEASE.
##
## Declare is diplomatic only: WarStateDomain.player_declare_from_province
## changes war state and nothing else. No apply_war_goal_live("execute"),
## no assault, no march. Player units hold until the player orders them.
## AI offensives stay on BattleManager.try_ai_start_land_battles (player skipped).
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
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		btn.offset_left = 8.0
		btn.offset_top = 96.0
		btn.offset_right = 280.0
		btn.offset_bottom = 120.0
		btn.pressed.connect(_on_pressed.bind(host))
		host.add_child(btn)
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
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
	btn.visible = true
	btn.set_meta("declare_pid", int(province.id))
	var left := WarStateDomain.player_justify_days_left(owner)
	var name := WarStateDomain.tag_name(owner)
	if WarStateDomain.player_justify_is_ready_for(owner):
		btn.disabled = false
		btn.text = "Declare war on %s" % name
	elif WarStateDomain.player_has_justify(owner):
		btn.disabled = true
		btn.text = "Justify (%d days)" % left
	elif WarStateDomain.player_justify_is_ready():
		btn.disabled = true
		btn.text = "Justify (%d days)" % left
	else:
		btn.disabled = false
		btn.text = "Justify war on %s" % name


static func _on_pressed(host: Node) -> void:
	var btn := host.get_node_or_null("BtnDeclareWar") as Button
	if btn == null:
		return
	var pid := int(btn.get_meta("declare_pid", -1))
	if pid <= 0 or typeof(WarStateDomain) == TYPE_NIL:
		return
	var p: Province = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
	var owner := ""
	if p != null:
		owner = str(p.owner_tag).strip_edges().to_upper()
	if WarStateDomain.player_justify_is_ready_for(owner):
		var declared: Dictionary = WarStateDomain.player_declare_from_province(pid)
		_toast(str(declared.get("reason", "War declared")))
	else:
		WarStateDomain.begin_player_justify_from_province(pid)
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_war_goal_live"):
			GameData.apply_war_goal_live("justify", pid)
		_toast("Justification started")
	mount(host, p)


static func _toast(text: String) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(text, 2.5)
