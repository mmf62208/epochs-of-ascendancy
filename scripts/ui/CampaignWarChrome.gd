# scripts/ui/CampaignWarChrome.gd
## Inspector "Declare war" button. Mounted from MapRenderer with one call.
##
## Declare is only for the nation whose justification is ready. A neighbour
## with no claim stays on "Justify war on {name}". While that claim is in
## progress the button is a live countdown ("Justifying Poland — N days left").
## Once a different claim is ready, other neighbours say "Justify unavailable"
## so the full duration is not mistaken for a countdown.
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
		btn.tooltip_text = "A truce blocks a new war against %s." % WarStateDomain.tag_name(owner)
		btn.set_meta("declare_pid", int(province.id))
		_style_disabled(btn)
		_ensure_day_hook(btn)
		return
	btn.visible = true
	btn.set_meta("declare_pid", int(province.id))
	_apply_war_button(btn, owner)
	_ensure_day_hook(btn)


static func _apply_war_button(btn: Button, owner: String) -> void:
	var nation_name := WarStateDomain.tag_name(owner)
	if WarStateDomain.player_justify_is_ready_for(owner):
		btn.disabled = false
		btn.text = "Declare war on %s" % nation_name
		btn.tooltip_text = "Justification ready. Declare war on %s." % nation_name
		_style_enabled(btn)
	elif WarStateDomain.player_has_justify(owner):
		btn.disabled = true
		var phrase := WarStateDomain.day_count_phrase(WarStateDomain.player_justify_days_left(owner))
		btn.text = "Justifying %s — %s left" % [nation_name, phrase]
		btn.tooltip_text = "Justification in progress against %s. %s left." % [nation_name, phrase]
		_style_disabled(btn)
	elif WarStateDomain.player_justify_is_ready():
		btn.disabled = true
		btn.text = "Justify unavailable"
		var ready_name := "Another nation"
		var suggested: Dictionary = WarStateDomain.suggest_player_target()
		var suggested_name := str(suggested.get("name", "")).strip_edges()
		if not suggested_name.is_empty():
			ready_name = suggested_name
		btn.tooltip_text = "%s is already justified. This button is not a countdown." % ready_name
		_style_disabled(btn)
	else:
		btn.disabled = false
		btn.text = "Justify war on %s" % nation_name
		btn.tooltip_text = "Start a justification against %s." % nation_name
		_style_enabled(btn)


static func _style_disabled(btn: Button) -> void:
	if typeof(RetrowaveTheme) != TYPE_NIL:
		btn.add_theme_color_override("font_disabled_color", RetrowaveTheme.TEXT_DIM)
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0.06, 0.07, 0.1, 0.95)
	dim.border_color = Color(0.45, 0.5, 0.58, 0.7)
	dim.set_border_width_all(1)
	dim.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("disabled", dim)


static func _style_enabled(btn: Button) -> void:
	btn.remove_theme_color_override("font_disabled_color")
	btn.remove_theme_stylebox_override("disabled")


static var _justify_buttons: Array = []
static var _day_hooked: bool = false


static func _ensure_day_hook(btn: Button) -> void:
	# bind() does not make a second connection distinct, so one day signal
	# refreshes every open justify button.
	if not btn.has_meta("eoa_justify_day_hook"):
		btn.set_meta("eoa_justify_day_hook", true)
		_justify_buttons.append(btn)
		btn.tree_exiting.connect(func():
			_justify_buttons.erase(btn)
		)
	if _day_hooked:
		return
	if typeof(TimeManager) == TYPE_NIL or not TimeManager.has_signal("game_day_advanced"):
		return
	_day_hooked = true
	TimeManager.game_day_advanced.connect(_on_justify_day_all)


static func _on_justify_day_all(_year: int, _month: int, _day: int) -> void:
	var live: Array = []
	for raw in _justify_buttons:
		if is_instance_valid(raw):
			live.append(raw)
	_justify_buttons = live
	if typeof(MapManager) == TYPE_NIL:
		return
	for raw in live:
		var btn := raw as Button
		if btn == null:
			continue
		var host := btn.get_parent()
		if host == null:
			continue
		var pid := int(btn.get_meta("declare_pid", -1))
		if pid <= 0:
			continue
		mount(host, MapManager.get_province(pid))


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
