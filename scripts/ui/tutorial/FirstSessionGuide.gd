# scripts/ui/tutorial/FirstSessionGuide.gd
## Autoload. First-session guide owner. CanvasLayer 118. No fenced writes.
extends Node

const LAYER := 118
const TICK_S := 0.25
const FLASH_S := 0.6
const CARD_GAP := 12.0
const JUSTIFY_CANDIDATES: PackedStringArray = [
	"POL", "CZE", "FRA", "BEL", "NLD", "DEN", "AUT", "LIT", "ENG", "SOV", "ITA", "USA", "HUN",
]

var _layer: CanvasLayer
var _host: Control
var _spotlight: ColorRect
var _highlight: Control
var _leader: Control
var _card: TutorialCard
var _prompt: TutorialPrompt
var _blocker: ColorRect
var _progress: Dictionary = {}
var _tick_accum: float = 0.0
var _flash_left: float = 0.0
var _flash_id: String = ""
var _confirm_skip: bool = false
var _dont_show: bool = false
var _force_start: bool = false
var _loaded_save: bool = false
var _title_closed: bool = false
var _begin_msec: int = 0
var _map_mode_at_step: String = ""
var _step_log_mark: int = 0
var _saw_day_unpaused: bool = false
var _paused_for_justify: bool = false
var _target_tag: String = "POL"
var _battle_player: bool = false
var _press_next: bool = false
var _press_got_it: bool = false
var _boot_connected: Dictionary = {}
var _pulse: float = 0.0
var _active_step: String = ""
var _highlight_rect: Rect2 = Rect2()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_progress = TutorialGuideDomain.load_cfg()
	_build_layer()
	var tree := get_tree()
	if tree != null:
		if not tree.node_added.is_connected(_on_node_added):
			tree.node_added.connect(_on_node_added)
	_connect_signals()
	_scan_existing_title()
	set_process(true)


func _scan_existing_title() -> void:
	var boot := _find_open_title()
	if boot != null:
		_hook_title(boot)


func replay(from_title: bool) -> void:
	_progress = TutorialGuideDomain.reset_for_replay(_progress)
	TutorialGuideDomain.save_cfg(_progress)
	_reset_session(true)
	_force_start = true
	_loaded_save = false
	if from_title:
		var boot := _find_open_title()
		if boot != null and boot.has_method("start_tutorial_from_title"):
			boot.call("start_tutorial_from_title")
			return
	_hide_prompt()
	_eval_now()


func set_guide_enabled(on: bool) -> void:
	_progress["enabled"] = on
	_progress["answered"] = true
	if on:
		_progress["completed"] = false
		_progress["done_steps"] = []
		_progress["skipped_steps"] = []
		_progress["reshow_welcome"] = true
	else:
		_hide_card()
		_hide_prompt()
		_force_start = false
	TutorialGuideDomain.save_cfg(_progress)


func is_guide_enabled() -> bool:
	return bool(_progress.get("enabled", false))


func restart_now() -> void:
	replay(_find_open_title() != null)


func _build_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "FirstSessionLayer"
	_layer.layer = LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	_host = Control.new()
	_host.name = "GuideHost"
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_host)
	_spotlight = ColorRect.new()
	_spotlight.name = "Spotlight"
	_spotlight.color = Color(0.02, 0.03, 0.08, 0.45)
	_spotlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spotlight.visible = false
	_host.add_child(_spotlight)
	_highlight = Control.new()
	_highlight.name = "TargetHighlight"
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_highlight.visible = false
	_highlight.draw.connect(_draw_highlight)
	_host.add_child(_highlight)
	_leader = Control.new()
	_leader.name = "LeaderLine"
	_leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leader.set_anchors_preset(Control.PRESET_FULL_RECT)
	_leader.visible = false
	_leader.draw.connect(_draw_leader)
	_host.add_child(_leader)
	_blocker = ColorRect.new()
	_blocker.name = "PromptBlocker"
	_blocker.color = Color(0.02, 0.03, 0.08, 0.55)
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	_host.add_child(_blocker)
	_card = TutorialCard.new()
	_card.name = "TutorialCard"
	_card.next_pressed.connect(func() -> void: _press_next = true; _eval_now())
	_card.back_pressed.connect(_on_back)
	_card.skip_step_pressed.connect(_on_skip_step)
	_card.skip_tutorial_pressed.connect(func() -> void: _confirm_skip = true; _eval_now())
	_card.skip_off_pressed.connect(_turn_off)
	_card.skip_keep_pressed.connect(func() -> void: _confirm_skip = false; _eval_now())
	_card.close_pressed.connect(func() -> void: _confirm_skip = true; _eval_now())
	_card.got_it_pressed.connect(_on_got_it)
	_card.dont_show_again_toggled.connect(func(on: bool) -> void: _dont_show = on)
	_host.add_child(_card)
	_prompt = TutorialPrompt.new()
	_prompt.name = "TutorialPrompt"
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.show_basics.connect(_on_show_basics)
	_prompt.know_game.connect(_on_know_game)
	_host.add_child(_prompt)


func _connect_signals() -> void:
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_signal("game_day_advanced"):
		if not TimeManager.game_day_advanced.is_connected(_on_day):
			TimeManager.game_day_advanced.connect(_on_day)
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_signal("battle_started"):
		if not BattleManager.battle_started.is_connected(_on_battle):
			BattleManager.battle_started.connect(_on_battle)


func _on_node_added(n: Node) -> void:
	if n == null:
		return
	var nm := str(n.name)
	if nm.begins_with("LivingTitleBoot"):
		_hook_title(n)
	elif nm == "WorldMap":
		call_deferred("_eval_now")


func _hook_title(boot: Node) -> void:
	_title_closed = false
	if _boot_connected.has(boot):
		return
	_boot_connected[boot] = true
	if boot.has_signal("boot_closed"):
		boot.boot_closed.connect(_on_boot_closed)


func _on_boot_closed(result: Dictionary) -> void:
	_title_closed = true
	_loaded_save = str(result.get("mode", "")) == "load"
	if _loaded_save:
		_hide_card()
		_hide_prompt()
		_force_start = false
		return
	_begin_msec = Time.get_ticks_msec()
	_progress["reshow_welcome"] = true
	_reset_runtime_flags()
	if TutorialGuideDomain.should_show_prompt(_snapshot_now(), _progress):
		_show_prompt()
		return
	if TutorialGuideDomain.should_auto_start(_snapshot_now(), _progress) or _force_start:
		_eval_now()


func _reset_session(keep_force: bool) -> void:
	_confirm_skip = false
	_dont_show = false
	_flash_left = 0.0
	_flash_id = ""
	_target_tag = "POL"
	_paused_for_justify = false
	_battle_player = false
	_press_next = false
	_press_got_it = false
	_reset_runtime_flags()
	if not keep_force:
		_force_start = false


func _reset_runtime_flags() -> void:
	_map_mode_at_step = ""
	_step_log_mark = _log_len()
	_saw_day_unpaused = false
	_active_step = ""


func _process(delta: float) -> void:
	_pulse += delta
	_tick_accum += delta
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_finish_flash()
		_redraw_chrome()
		return
	if _tick_accum < TICK_S:
		_redraw_chrome()
		return
	_tick_accum = 0.0
	_eval_now()
	_redraw_chrome()


func _eval_now() -> void:
	if _end_screen_open() or _title_is_open():
		_hide_card()
		if _title_is_open():
			_hide_prompt()
		return
	var snap := _snapshot_now()
	if TutorialGuideDomain.should_show_prompt(snap, _progress) and not _prompt.visible and not _force_start:
		_show_prompt()
		return
	if _prompt.visible:
		return
	if not TutorialGuideDomain.should_auto_start(snap, _progress) and not _force_start:
		_hide_card()
		return
	snap["guide_active"] = true
	var result: Dictionary = TutorialGuideDomain.evaluate(snap, _progress)
	_apply_result(result)


func _apply_result(result: Dictionary) -> void:
	if not bool(result.get("visible", false)):
		_hide_card()
		return
	var sid := str(result.get("step_id", ""))
	if sid != _active_step:
		_on_step_enter(sid)
	var state := str(result.get("state", "active"))
	if state == "auto_skip":
		_present_card(result)
		_play_step_sfx()
		_flash_id = sid
		_flash_left = FLASH_S
		return
	if state == "done":
		_present_card(result)
		_play_step_sfx()
		if sid == "justify_wait":
			_pause_clock_once()
			_play_sfx("justify_ready")
		_flash_id = sid
		_flash_left = FLASH_S
		return
	result["confirm_skip"] = _confirm_skip
	_present_card(result)
	_place_card(result)


func _on_step_enter(sid: String) -> void:
	_active_step = sid
	_press_next = false
	_press_got_it = false
	_map_mode_at_step = _current_map_mode()
	_step_log_mark = _log_len()
	_saw_day_unpaused = false
	if sid == "justify_wait":
		_paused_for_justify = false


func _finish_flash() -> void:
	var ids: Array = []
	if not _flash_id.is_empty():
		ids.append(_flash_id)
	var snap := _snapshot_now()
	snap["guide_active"] = true
	var result: Dictionary = TutorialGuideDomain.evaluate(snap, _progress)
	for extra in result.get("auto_skip_ids", []):
		var e := str(extra)
		if not ids.has(e):
			ids.append(e)
	var done: Array = TutorialGuideDomain.string_ids(_progress.get("done_steps", []))
	for idv in ids:
		if not done.has(str(idv)):
			done.append(str(idv))
	_progress["done_steps"] = done
	if _flash_id == "welcome":
		_progress["reshow_welcome"] = false
	if _flash_id == "justify":
		var tag := str(snap.get("justify_tag", "")).strip_edges().to_upper()
		if not tag.is_empty():
			_target_tag = tag
	TutorialGuideDomain.save_cfg(_progress)
	_flash_id = ""
	_eval_now()


func _present_card(result: Dictionary) -> void:
	if _card == null:
		return
	_card.present(result)
	_card.set_dont_show_again(_dont_show)
	_spotlight.visible = bool(result.get("spotlight", false))
	_update_highlight(result)


func _hide_card() -> void:
	if _card != null:
		_card.visible = false
	if _spotlight != null:
		_spotlight.visible = false
	if _highlight != null:
		_highlight.visible = false
	if _leader != null:
		_leader.visible = false


func _show_prompt() -> void:
	_hide_card()
	if _blocker != null:
		_blocker.visible = true
	if _prompt != null:
		_prompt.present(_nation_line())
		_center_prompt()


func _hide_prompt() -> void:
	if _prompt != null:
		_prompt.dismiss()
	if _blocker != null:
		_blocker.visible = false


func _center_prompt() -> void:
	if _prompt == null or _host == null:
		return
	var size := _host.size
	if size.x < 8.0:
		size = Vector2(1280, 800)
	_prompt.reset_size()
	var cs := _prompt.get_combined_minimum_size()
	_prompt.position = Vector2((size.x - cs.x) * 0.5, (size.y - cs.y) * 0.5)


func _on_show_basics() -> void:
	_progress = TutorialGuideDomain.mark_answered(_progress, true)
	_progress["reshow_welcome"] = true
	TutorialGuideDomain.save_cfg(_progress)
	_force_start = true
	_hide_prompt()
	_eval_now()


func _on_know_game() -> void:
	_progress = TutorialGuideDomain.mark_answered(_progress, false)
	TutorialGuideDomain.save_cfg(_progress)
	_force_start = false
	_hide_prompt()
	_hide_card()


func _on_got_it() -> void:
	_press_got_it = true
	var done: Array = TutorialGuideDomain.string_ids(_progress.get("done_steps", []))
	if not done.has("ending"):
		done.append("ending")
	_progress["done_steps"] = done
	_progress["completed"] = true
	if _dont_show:
		_progress["enabled"] = false
	TutorialGuideDomain.save_cfg(_progress)
	_play_step_sfx()
	_hide_card()
	_force_start = false


func _on_skip_step() -> void:
	var sid := _active_step
	if sid.is_empty():
		return
	var done: Array = TutorialGuideDomain.string_ids(_progress.get("done_steps", []))
	var skipped: Array = TutorialGuideDomain.string_ids(_progress.get("skipped_steps", []))
	if not done.has(sid):
		done.append(sid)
	if not skipped.has(sid):
		skipped.append(sid)
	_progress["done_steps"] = done
	_progress["skipped_steps"] = skipped
	if sid == "welcome":
		_progress["reshow_welcome"] = false
	TutorialGuideDomain.save_cfg(_progress)
	_eval_now()


func _on_back() -> void:
	var done: Array = TutorialGuideDomain.string_ids(_progress.get("done_steps", []))
	if done.is_empty():
		return
	done.pop_back()
	_progress["done_steps"] = done
	_progress["reshow_welcome"] = true
	TutorialGuideDomain.save_cfg(_progress)
	_eval_now()


func _turn_off() -> void:
	_progress["enabled"] = false
	_progress["answered"] = true
	TutorialGuideDomain.save_cfg(_progress)
	_confirm_skip = false
	_force_start = false
	_hide_card()
	_hide_prompt()


func _pause_clock_once() -> void:
	if _paused_for_justify:
		return
	var clock := _clock()
	if clock == null:
		return
	var paused := false
	if clock.has_method("is_paused"):
		paused = bool(clock.call("is_paused"))
	elif "is_paused" in clock:
		paused = bool(clock.get("is_paused"))
	if not paused and clock.has_method("pause"):
		clock.call("pause")
		_paused_for_justify = true


func _clock() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var bar := TopInfoBar.find_in_tree(tree)
	if bar != null:
		return bar
	return tree.get_first_node_in_group("top_info_bar")


func _on_day(_y: int, _m: int, _d: int) -> void:
	var paused := false
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_paused"):
		paused = bool(TimeManager.is_paused())
	if not paused:
		_saw_day_unpaused = true


func _on_battle(context: Dictionary) -> void:
	var player := _player_tag()
	var atk := str(context.get("attacker", context.get("attacker_tag", ""))).to_upper()
	var dfn := str(context.get("defender", context.get("defender_tag", ""))).to_upper()
	if atk == player or dfn == player:
		_battle_player = true


func _snapshot_now() -> Dictionary:
	var player := _player_tag()
	var year := 1936
	if typeof(TimeManager) != TYPE_NIL and "scenario_start_year" in TimeManager:
		year = int(TimeManager.scenario_start_year)
	var paused := true
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_paused"):
		paused = bool(TimeManager.is_paused())
	var justify_tag := _find_justify_tag(player)
	var target := _target_tag
	if not justify_tag.is_empty():
		target = justify_tag
	var at_war_target := bool(WarStateDomain.is_at_war(player, target))
	var at_war_any := false
	var enemy := ""
	var foes: Array = WarStateDomain.enemies_of(player)
	at_war_any = not foes.is_empty()
	if not foes.is_empty():
		enemy = str(foes[0])
		if not at_war_target:
			target = enemy
	var days_left := 14
	var days_total := 14
	var ready := false
	var has_j := not justify_tag.is_empty()
	var rules: Dictionary = WarStateDomain.rules()
	days_total = int(rules.get("player_justify_days", 14))
	if has_j:
		days_left = int(WarStateDomain.player_justify_days_left(target))
		ready = bool(WarStateDomain.player_justify_is_ready_for(target))
	var log_new := _log_since(_step_log_mark)
	var minutes := 0.0
	if _begin_msec > 0:
		minutes = float(Time.get_ticks_msec() - _begin_msec) / 60000.0
	var mode := _current_map_mode()
	return {
		"guide_active": bool(_progress.get("enabled", false)) or _force_start or TutorialGuideDomain.env_tutorial() == 1,
		"world_map_present": _find_named("WorldMap") != null,
		"title_open": _title_is_open(),
		"title_closed": _title_closed or not _title_is_open(),
		"player_tag": player,
		"start_year": year,
		"headless": TutorialGuideDomain.is_headless_runtime(),
		"qa_run": TutorialGuideDomain.is_qa_or_harness(),
		"has_saves": TutorialGuideDomain.user_has_saves(),
		"loaded_save": _loaded_save,
		"time_paused": paused,
		"day_advanced_then_paused": _saw_day_unpaused and paused,
		"map_mode": mode,
		"map_mode_changed": not _map_mode_at_step.is_empty() and mode != _map_mode_at_step,
		"inspector_visible": _inspector_visible(),
		"inspector_on_target": _inspector_on_tag(target),
		"own_unit_card_visible": _own_unit_card_visible(),
		"at_war_with_target": at_war_target,
		"at_war_any": at_war_any,
		"war_enemy_tag": enemy,
		"war_enemy_name": _display_name(enemy),
		"player_has_justify": has_j,
		"justify_tag": justify_tag,
		"target_tag": target,
		"target_name": _display_name(target),
		"player_justify_ready": ready,
		"player_justify_days_left": days_left,
		"player_justify_days": days_total,
		"player_unit_adjacent_enemy": _unit_adjacent(player, target),
		"cue_order_move": log_new.has("order_move"),
		"cue_order_attack": log_new.has("order_attack"),
		"cue_save_ok": log_new.has("save_ok"),
		"battle_started_player": _battle_player,
		"minutes_since_begin": minutes,
		"press_next": _press_next,
		"press_got_it": _press_got_it,
		"campaign_end_open": _end_screen_open(),
	}


func _player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		return str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	return "GER"


func _display_name(tag: String) -> String:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return ""
	var nm := str(CampaignWarChrome.display_name_for_tag(t)).strip_edges()
	if not nm.is_empty() and nm.to_upper() != t:
		return nm
	return t


func _find_justify_tag(player: String) -> String:
	var tags: Array = []
	for t in JUSTIFY_CANDIDATES:
		tags.append(str(t))
	for n in WarStateDomain.land_neighbours(player):
		var nt := str(n).to_upper()
		if not tags.has(nt):
			tags.append(nt)
	for t in tags:
		if t == player:
			continue
		if bool(WarStateDomain.player_has_justify(t)):
			return t
	return ""


func _current_map_mode() -> String:
	var mr := _map_renderer()
	if mr != null and "current_map_mode" in mr:
		return str(mr.get("current_map_mode"))
	return "political"


func _inspector_visible() -> bool:
	var panel := _info_panel()
	return panel != null and panel.visible


func _inspector_on_tag(tag: String) -> bool:
	if not _inspector_visible():
		return false
	var mr := _map_renderer()
	if mr == null or not ("selected_province_id" in mr):
		return false
	var pid := int(mr.get("selected_province_id"))
	if pid <= 0 or typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return false
	var p: Variant = MapManager.get_province(pid)
	if p == null:
		return false
	return str(p.get("owner_tag")).strip_edges().to_upper() == tag.to_upper()


func _own_unit_card_visible() -> bool:
	return _find_named("BtnMarchArm") != null or _find_named("BtnOpenFight") != null


func _unit_adjacent(player: String, target: String) -> bool:
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formations_for_country"):
		return false
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_adjacent_provinces"):
		return false
	var forms: Array = LeaderManager.get_formations_for_country(player)
	for f in forms:
		if f == null:
			continue
		var pid := int(f.get("stationed_province_id")) if "stationed_province_id" in f else -1
		if pid <= 0:
			continue
		var adj: Array = MapManager.get_adjacent_provinces(pid, true)
		for ap in adj:
			var p: Variant = MapManager.get_province(int(ap)) if MapManager.has_method("get_province") else null
			if p != null and str(p.get("owner_tag")).to_upper() == target.to_upper():
				return true
	return false


func _log_len() -> int:
	if typeof(AudioManager) != TYPE_NIL and AudioManager.has_method("request_log"):
		return AudioManager.request_log().size()
	return 0


func _log_since(mark: int) -> Dictionary:
	var found := {}
	if typeof(AudioManager) == TYPE_NIL or not AudioManager.has_method("request_log"):
		return found
	var rows: Array = AudioManager.request_log()
	var i := mark
	while i < rows.size():
		found[str(rows[i])] = true
		i += 1
	return found


func _play_step_sfx() -> void:
	_play_sfx("tutorial_step")


func _play_sfx(key: String) -> void:
	if typeof(AudioManager) != TYPE_NIL and AudioManager.has_method("play"):
		AudioManager.play(key)


func _nation_line() -> String:
	var name := _display_name(_player_tag())
	if name.is_empty():
		name = "Germany"
	return "%s · 1 January 1936" % name


func _end_screen_open() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for g in ["campaign_end_screen", "campaign_ink_end_screen"]:
		for n in tree.get_nodes_in_group(g):
			if n != null and is_instance_valid(n) and not n.is_queued_for_deletion():
				if str(n.name).ends_with("_dying"):
					continue
				return true
	return false


func _title_is_open() -> bool:
	if _title_closed:
		return false
	var boot := _find_open_title()
	return boot != null


func _find_open_title() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return _find_open_title_in(tree.root)


func _find_open_title_in(n: Node) -> Node:
	if n != null and str(n.name).begins_with("LivingTitleBoot"):
		if n.is_queued_for_deletion() or bool(n.get("_closed")):
			return null
		return n
	for c in n.get_children():
		var found := _find_open_title_in(c)
		if found != null:
			return found
	return null


func _map_renderer() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var mr := tree.get_first_node_in_group("map_renderer")
	if mr != null:
		return mr
	return _find_named("MapRenderer")


func _info_panel() -> Control:
	var n := _find_named("InfoPanel")
	return n as Control


func _find_named(node_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.find_child(node_name, true, false)


func _place_card(result: Dictionary) -> void:
	if _card == null or _host == null:
		return
	var host_size := _host.size
	if host_size.x < 8.0:
		host_size = Vector2(1280, 800)
	var card_size := _card.get_combined_minimum_size()
	if card_size.x < 8.0:
		card_size = Vector2(380, 220)
	var target := _target_rect(result)
	_highlight_rect = target
	var pos := Vector2(host_size.x - card_size.x - 24.0, 96.0)
	if target.size.x > 4.0:
		pos = Vector2(target.end.x + CARD_GAP, target.position.y)
		if pos.x + card_size.x > host_size.x - 8.0:
			pos.x = target.position.x - card_size.x - CARD_GAP
		if pos.x < 8.0:
			pos.x = 8.0
		if pos.y + card_size.y > host_size.y - 8.0:
			pos.y = host_size.y - card_size.y - 8.0
		if pos.y < 64.0:
			pos.y = 64.0
	_card.position = pos
	if _leader != null:
		_leader.visible = target.size.x > 4.0
		_leader.queue_redraw()
	if _highlight != null:
		_highlight.visible = target.size.x > 4.0
		_highlight.queue_redraw()


func _target_rect(result: Dictionary) -> Rect2:
	var spec_t: Variant = result.get("target", {})
	if not (spec_t is Dictionary):
		return Rect2()
	var t: Dictionary = spec_t
	var kind := str(t.get("kind", ""))
	match kind:
		"node":
			var path := str(t.get("path", ""))
			var node := _node_from_path(path)
			if node is Control:
				return (node as Control).get_global_rect()
			if node is CanvasItem:
				return Rect2((node as CanvasItem).get_global_transform_with_canvas().origin, Vector2(48, 48))
		"node_in_unit_card":
			var nm := str(t.get("name", ""))
			var btn := _find_named(nm)
			if btn is Control:
				return (btn as Control).get_global_rect()
		_:
			pass
	var dipl := _find_named("DiplomacyButton")
	if dipl is Control and str(result.get("step_id", "")) == "justify":
		return (dipl as Control).get_global_rect()
	return Rect2()


func _node_from_path(path: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var last := path.get_file()
	if last.is_empty():
		last = path
	if last.find(" ") >= 0:
		last = last.split(" ")[0]
	return _find_named(last)


func _update_highlight(result: Dictionary) -> void:
	_highlight_rect = _target_rect(result)
	if _highlight != null:
		_highlight.visible = _highlight_rect.size.x > 4.0 and str(result.get("state", "")) != "done"
		_highlight.queue_redraw()


func _draw_highlight() -> void:
	if _highlight_rect.size.x < 4.0:
		return
	var a := 0.45 + 0.55 * (0.5 + 0.5 * sin(_pulse * TAU))
	var col := RetrowaveTheme.CYAN
	if _card != null and str(_card._current.get("accent", "")) == "magenta":
		col = RetrowaveTheme.MAGENTA
	col.a = a
	var r := _highlight_rect.grow(4.0)
	_highlight.draw_rect(r, col, false, 2.0)
	var glow := col
	glow.a = a * 0.35
	_highlight.draw_rect(r.grow(8.0), glow, false, 8.0)


func _draw_leader() -> void:
	if _card == null or not _card.visible or _highlight_rect.size.x < 4.0:
		return
	var from_pt := _card.position + Vector2(0, 28)
	var to_pt := _highlight_rect.get_center()
	var col := RetrowaveTheme.CYAN
	if str(_card._current.get("accent", "")) == "magenta":
		col = RetrowaveTheme.MAGENTA
	_draw_dash(_leader, from_pt, to_pt, col, 2.0)


func _draw_dash(c: Control, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 2.0:
		return
	var dir := delta / length
	var step := 10.0
	var gap := 6.0
	var d := 0.0
	while d < length:
		var p0 := a + dir * d
		var p1 := a + dir * minf(d + step, length)
		c.draw_line(p0, p1, col, width)
		d += step + gap


func _redraw_chrome() -> void:
	if _highlight != null and _highlight.visible:
		_highlight.queue_redraw()
	if _leader != null and _leader.visible:
		_leader.queue_redraw()
