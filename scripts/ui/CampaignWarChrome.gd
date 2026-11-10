# scripts/ui/CampaignWarChrome.gd
## Inspector "Declare war" button. Mounted from MapRenderer with one call.
##
## Declare is only for the nation whose justification is ready. Other
## neighbours stay on Justify (N days) or a disabled state — a ready POL
## claim must not relabel every border inspector as Declare.
##
## FIRST20-UX-WAR: inspector Justify is offered on land provinces of POL
## plus the player's land neighbours — the same nation set Diplomacy
## always lists besides majors. Interior hexes of those nations still
## count (no borders_tag province gate). WarStateDomain is unchanged.
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


const BORDER_NOT_REQUIRED_HINT := "Border not required — claim is on the nation."


## True when `other` is the player's own nation (tag or display name).
static func is_self_nation(player: String, other: String) -> bool:
	var p := player.strip_edges().to_upper()
	var o := other.strip_edges().to_upper()
	if p.is_empty() or o.is_empty():
		return false
	if p == o:
		return true
	var pn := display_name_for_tag(p).strip_edges().to_upper()
	var on := display_name_for_tag(o).strip_edges().to_upper()
	if not pn.is_empty() and (pn == o or pn == on):
		return true
	if not on.is_empty() and on == p:
		return true
	return false


## POL plus live land neighbours of the player. Diplomacy lists this set
## alongside majors; the inspector Justify button uses only this set.
static func inspector_justify_tags(player: String) -> Array:
	var p := player.strip_edges().to_upper()
	var found: Dictionary = {}
	if not is_self_nation(p, "POL"):
		found["POL"] = true
	if typeof(WarStateDomain) != TYPE_NIL:
		for n in WarStateDomain.land_neighbours(p):
			var nt := str(n).strip_edges().to_upper()
			if nt.is_empty() or is_self_nation(p, nt):
				continue
			found[nt] = true
	var keys: Array = found.keys()
	keys.sort()
	return keys


static func inspector_offers_justify(player: String, owner: String) -> bool:
	var o := owner.strip_edges().to_upper()
	var p := player.strip_edges().to_upper()
	if o.is_empty() or is_self_nation(p, o):
		return false
	for tag_v in inspector_justify_tags(p):
		if str(tag_v) == o:
			return true
	return false


## Live diplomatic band for toasts. War outranks RelationsManager "Neutral".
static func relation_label_for(player: String, other: String, fallback: String = "Neutral") -> String:
	var p := player.strip_edges().to_upper()
	var o := other.strip_edges().to_upper()
	if p.is_empty() or o.is_empty():
		return fallback.strip_edges() if not fallback.strip_edges().is_empty() else "Neutral"
	if typeof(WarStateDomain) != TYPE_NIL and WarStateDomain.is_at_war(p, o):
		return "At war"
	var band := fallback.strip_edges()
	if band.is_empty():
		return "Neutral"
	return band


static func display_name_for_tag(tag: String) -> String:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("country_display_name"):
		var nm := str(MapManager.country_display_name(t)).strip_edges()
		if not nm.is_empty():
			return nm
	if typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("ensure_country_stub"):
			MapManager.ensure_country_stub(t)
		if MapManager.has_method("get_country"):
			var c: Variant = MapManager.get_country(t)
			if c is Dictionary:
				var dn := str((c as Dictionary).get("name", "")).strip_edges()
				if not dn.is_empty() and dn.to_upper() != t:
					return dn
	if typeof(WarStateDomain) != TYPE_NIL:
		var wn := str(WarStateDomain.tag_name(t)).strip_edges()
		if not wn.is_empty() and wn.to_upper() != t:
			return wn
	if typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("nation_display_name"):
		var sn := str(SaveLoadManager.nation_display_name(t)).strip_edges()
		if not sn.is_empty() and sn.to_upper() != t:
			return sn
	return t


static func button_state_for_owner(player: String, owner: String) -> Dictionary:
	var p := player.strip_edges().to_upper()
	var o := owner.strip_edges().to_upper()
	if o.is_empty() or is_self_nation(p, o):
		return {"visible": false, "disabled": true, "text": "", "tooltip": ""}
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return {"visible": false, "disabled": true, "text": "", "tooltip": ""}
	if WarStateDomain.is_at_war(p, o):
		return {"visible": false, "disabled": true, "text": "", "tooltip": ""}
	var name := display_name_for_tag(o)
	if WarStateDomain.in_truce(p, o):
		return {
			"visible": true,
			"disabled": true,
			"text": "Truce with %s" % name,
			"tooltip": BORDER_NOT_REQUIRED_HINT,
		}
	var left := WarStateDomain.player_justify_days_left(o)
	if WarStateDomain.player_justify_is_ready_for(o):
		return {
			"visible": true,
			"disabled": false,
			"text": "Declare war on %s" % name,
			"tooltip": BORDER_NOT_REQUIRED_HINT,
		}
	if WarStateDomain.player_has_justify(o) or WarStateDomain.player_justify_is_ready():
		return {
			"visible": true,
			"disabled": true,
			"text": "Justify (%d days)" % left,
			"tooltip": BORDER_NOT_REQUIRED_HINT,
		}
	return {
		"visible": true,
		"disabled": false,
		"text": "Justify war on %s" % name,
		"tooltip": BORDER_NOT_REQUIRED_HINT,
	}


static func apply_button(btn: Button, state: Dictionary) -> void:
	if btn == null:
		return
	btn.visible = bool(state.get("visible", false))
	btn.disabled = bool(state.get("disabled", true))
	btn.text = str(state.get("text", ""))
	btn.tooltip_text = str(state.get("tooltip", ""))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP


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
	if not inspector_offers_justify(player, owner):
		btn.visible = false
		return
	apply_button(btn, button_state_for_owner(player, owner))
	if btn.visible:
		btn.set_meta("declare_pid", int(province.id))


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
		refresh_top_bar_war_readout()
	else:
		WarStateDomain.begin_player_justify_from_province(pid)
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_war_goal_live"):
			GameData.apply_war_goal_live("justify", pid)
		_toast("Justification started")
	mount(host, p)


static func refresh_top_bar_war_readout() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var bar := tree.get_first_node_in_group("top_info_bar")
	if bar != null and is_instance_valid(bar) and bar.has_method("refresh_campaign_war_readout"):
		bar.call("refresh_campaign_war_readout")


static func _toast(text: String) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(text, 2.5)
