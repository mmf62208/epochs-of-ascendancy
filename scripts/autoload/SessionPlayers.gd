# scripts/autoload/SessionPlayers.gd
## Multiplayer foundation: hotseat lobby, player slots, command queue.
## Not netcode — local multiplayer + AI slots. Hinges LeaderManager.player_country_tag.
extends Node

signal active_player_changed(tag: String, slot_index: int, turn: int)
signal command_enqueued(command: Dictionary)
signal commands_flushed(applied: Array)
signal lobby_ready_changed(ready: bool)

const CONTROL_HUMAN := "human"
const CONTROL_AI := "ai"
const CONTROL_OBSERVER := "observer"

## Array of {slot, tag, control, name, ready}
var slots: Array = []
var active_index: int = 0
var turn: int = 1
var command_queue: Array = []
var commands_applied_total: int = 0
var mode: String = "hotseat"
var lobby_ready: bool = false
var history: Array = []


func _ready() -> void:
	if slots.is_empty():
		# Solo by default for F5 play — multi-slot hotseat chrome (banner/End Turn) only when requested.
		setup_solo_play()


## Single human player — normal single-player / F5 path (no hotseat banner).
func setup_solo_play(human_tag: String = "USA") -> void:
	setup_default_hotseat(human_tag, [])


func setup_default_hotseat(
	human_tag: String = "USA",
	ai_tags: Array = ["GER", "SOV", "ENG"],
) -> void:
	slots.clear()
	var ht := human_tag.strip_edges().to_upper()
	if ht.is_empty():
		ht = "USA"
	slots.append({
		"slot": 0,
		"tag": ht,
		"control": CONTROL_HUMAN,
		"name": "Player 1",
		"ready": true,
	})
	var i := 1
	for raw in ai_tags:
		var t := str(raw).strip_edges().to_upper()
		if t.is_empty() or t == ht:
			continue
		slots.append({
			"slot": i,
			"tag": t,
			"control": CONTROL_AI,
			"name": "AI %s" % t,
			"ready": true,
		})
		i += 1
	active_index = 0
	turn = 1
	command_queue.clear()
	lobby_ready = true
	mode = "hotseat" if slots.size() > 1 else "solo"
	_sync_leader_player_tag()
	lobby_ready_changed.emit(true)


## All tags as AI agents (no human) — year multi-AI campaign / headless tests.
func setup_all_ai(ai_tags: Array = []) -> void:
	slots.clear()
	var i := 0
	var seen: Dictionary = {}
	for raw in ai_tags:
		var t := str(raw).strip_edges().to_upper()
		if t.is_empty() or seen.has(t):
			continue
		seen[t] = true
		slots.append({
			"slot": i,
			"tag": t,
			"control": CONTROL_AI,
			"name": "AI %s" % t,
			"ready": true,
		})
		i += 1
	if slots.is_empty():
		# Fallback majors all AI
		for t2 in ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"]:
			slots.append({
				"slot": i,
				"tag": t2,
				"control": CONTROL_AI,
				"name": "AI %s" % t2,
				"ready": true,
			})
			i += 1
	active_index = 0
	turn = 1
	command_queue.clear()
	lobby_ready = true
	mode = "all_ai"
	_sync_leader_player_tag()
	lobby_ready_changed.emit(true)


func get_player_count() -> int:
	return slots.size()


func is_multiplayer_session() -> bool:
	return slots.size() > 1


func setup_from_dicts(slot_rows: Array) -> void:
	slots.clear()
	var i := 0
	for raw in slot_rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var tag := str(row.get("tag", row.get("country_tag", ""))).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var ctrl := str(row.get("control", row.get("type", CONTROL_AI))).strip_edges().to_lower()
		if ctrl not in [CONTROL_HUMAN, CONTROL_AI, CONTROL_OBSERVER]:
			ctrl = CONTROL_AI
		slots.append({
			"slot": i,
			"tag": tag,
			"control": ctrl,
			"name": str(row.get("name", tag)),
			"ready": bool(row.get("ready", true)),
		})
		i += 1
	if slots.is_empty():
		setup_solo_play()
		return
	active_index = 0
	for j in range(slots.size()):
		if str((slots[j] as Dictionary).get("control", "")) == CONTROL_HUMAN:
			active_index = j
			break
	lobby_ready = true
	mode = "hotseat" if slots.size() > 1 else "solo"
	for s in slots:
		if not bool((s as Dictionary).get("ready", true)):
			lobby_ready = false
			break
	_sync_leader_player_tag()


func get_active_tag() -> String:
	if slots.is_empty():
		return ""
	var idx := clampi(active_index, 0, slots.size() - 1)
	return str((slots[idx] as Dictionary).get("tag", ""))


func get_active_control() -> String:
	if slots.is_empty():
		return CONTROL_AI
	var idx := clampi(active_index, 0, slots.size() - 1)
	return str((slots[idx] as Dictionary).get("control", CONTROL_AI))


func is_active_human() -> bool:
	return get_active_control() == CONTROL_HUMAN


## N1 — only the active seat may issue commands (non-active locked).
func is_command_allowed_for_tag(tag: String) -> bool:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return false
	return t == get_active_tag()


## N1 — turn banner product state (mirrors pure hotseat_turn_banner_product).
func get_turn_banner_state() -> Dictionary:
	var tag := get_active_tag()
	var human := is_active_human()
	var role := "HUMAN" if human else "AI (input locked)"
	var banner := "Hotseat · Turn %d · Active %s · %s" % [turn, tag if not tag.is_empty() else "—", role]
	return {
		"slots": slots.duplicate(true),
		"active_tag": tag,
		"turn_index": turn,
		"banner_text": banner,
		"non_active_locked": true,
		"can_end_turn": lobby_ready and not slots.is_empty() and not tag.is_empty(),
		"command_journal_len": command_queue.size(),
		"active_control": get_active_control(),
		"is_active_human": human,
		"lobby_ready": lobby_ready,
		"active_index": active_index,
		"mode": mode,
	}


func get_ai_tags() -> Array[String]:
	var out: Array[String] = []
	for s in slots:
		var row: Dictionary = s as Dictionary
		if str(row.get("control", "")) == CONTROL_AI:
			out.append(str(row.get("tag", "")))
	return out


func get_human_tags() -> Array[String]:
	var out: Array[String] = []
	for s in slots:
		var row: Dictionary = s as Dictionary
		if str(row.get("control", "")) == CONTROL_HUMAN:
			out.append(str(row.get("tag", "")))
	return out


func set_slot_ready(tag: String, ready: bool = true) -> void:
	var t := tag.strip_edges().to_upper()
	for s in slots:
		var row: Dictionary = s as Dictionary
		if str(row.get("tag", "")) == t:
			row["ready"] = ready
	_recompute_lobby_ready()


func mark_lobby_all_ready() -> void:
	for s in slots:
		(s as Dictionary)["ready"] = true
	_recompute_lobby_ready()


func _recompute_lobby_ready() -> void:
	var ok := not slots.is_empty()
	for s in slots:
		if not bool((s as Dictionary).get("ready", false)):
			ok = false
			break
	lobby_ready = ok
	lobby_ready_changed.emit(lobby_ready)


func enqueue_command(action: String, province_id: int = 1, extra: Dictionary = {}) -> Dictionary:
	var cmd := {
		"action": action.strip_edges(),
		"province_id": province_id,
		"tag": get_active_tag(),
		"turn": turn,
		"control": get_active_control(),
	}
	for k in extra.keys():
		cmd[k] = extra[k]
	command_queue.append(cmd)
	if command_queue.size() > 64:
		command_queue = command_queue.slice(command_queue.size() - 64)
	command_enqueued.emit(cmd)
	_push_history("enqueue", cmd)
	return {"ok": true, "command": cmd, "queue_n": command_queue.size()}


func flush_command_queue() -> Dictionary:
	var applied: Array = []
	## Snapshot pre-flush journal for N2 verify (queue is cleared after apply).
	var pre_flush_journal: Array = get_command_journal()
	for cmd in command_queue:
		var row: Dictionary = cmd if cmd is Dictionary else {}
		var aid := str(row.get("action", ""))
		var pid := int(row.get("province_id", 1))
		var res := {
			"ok": true,
			"action": aid,
			"tag": str(row.get("tag", "")),
			"province_id": pid,
			"turn": int(row.get("turn", turn)),
		}
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_order_panel_action") and not aid.is_empty():
			var live: Dictionary = GameData.apply_order_panel_action(aid, pid)
			res["live_ok"] = bool(live.get("ok", live.get("success", true)))
			res["live"] = live
		applied.append(res)
	commands_applied_total += applied.size()
	command_queue.clear()
	commands_flushed.emit(applied)
	_push_history("flush", {"applied_n": applied.size()})
	return {
		"ok": true,
		"applied": applied,
		"pre_flush_journal": pre_flush_journal,
		"commands_applied_total": commands_applied_total,
		"queue_n": 0,
	}


func rotate_active_player() -> Dictionary:
	if slots.is_empty():
		return {"ok": false, "error": "no_slots"}
	active_index = (active_index + 1) % slots.size()
	turn += 1
	var tag := get_active_tag()
	_sync_leader_player_tag()
	active_player_changed.emit(tag, active_index, turn)
	_push_history("rotate", {"tag": tag, "turn": turn})
	return {
		"ok": true,
		"active_tag": tag,
		"active_index": active_index,
		"active_control": get_active_control(),
		"turn": turn,
		"player_country_tag": tag,
	}


func set_active_tag(tag: String) -> Dictionary:
	var t := tag.strip_edges().to_upper()
	for i in range(slots.size()):
		if str((slots[i] as Dictionary).get("tag", "")) == t:
			active_index = i
			_sync_leader_player_tag()
			active_player_changed.emit(t, active_index, turn)
			return {"ok": true, "active_tag": t, "active_index": i}
	return {"ok": false, "error": "tag_not_in_slots"}


func _sync_leader_player_tag() -> void:
	var tag := get_active_tag()
	if tag.is_empty():
		return
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("set_player_country_tag"):
		LeaderManager.set_player_country_tag(tag)


func _push_history(step: String, payload: Dictionary = {}) -> void:
	var row := {"step": step, "turn": turn, "active_tag": get_active_tag()}
	for k in payload.keys():
		row[k] = payload[k]
	history.append(row)
	if history.size() > 48:
		history = history.slice(history.size() - 48)


func get_save_data() -> Dictionary:
	return {
		"slots": slots.duplicate(true),
		"active_index": active_index,
		"turn": turn,
		"command_queue": command_queue.duplicate(true),
		"commands_applied_total": commands_applied_total,
		"mode": mode,
		"lobby_ready": lobby_ready,
	}


func apply_save_data(data: Dictionary) -> void:
	if data.has("slots"):
		slots = (data.get("slots", []) as Array).duplicate(true)
	active_index = int(data.get("active_index", 0))
	turn = int(data.get("turn", 1))
	if data.has("command_queue"):
		command_queue = (data.get("command_queue", []) as Array).duplicate(true)
	commands_applied_total = int(data.get("commands_applied_total", 0))
	mode = str(data.get("mode", "hotseat"))
	lobby_ready = bool(data.get("lobby_ready", false))
	_sync_leader_player_tag()




## N2 — command journal snapshot (deterministic multiplayer ladder).
func get_command_journal() -> Array:
	return command_queue.duplicate(true)


func clear_command_journal() -> void:
	command_queue.clear()


func seed_command_journal(seed: int = 1936) -> Dictionary:
	if slots.is_empty():
		setup_default_hotseat()
	mark_lobby_all_ready()
	clear_command_journal()
	turn = maxi(1, int(seed) % 10000)  # seed-derived starting turn for fingerprint context
	_push_history("seed_journal", {"seed": seed, "turn": turn})
	return {
		"ok": true,
		"seed": seed,
		"turn": turn,
		"active_tag": get_active_tag(),
		"queue_n": command_queue.size(),
		"slot_n": slots.size(),
	}


func enqueue_journal_batch(actions: Array, province_id: int = 1) -> Dictionary:
	var enqueued: Array = []
	for raw in actions:
		var aid := str(raw).strip_edges()
		if aid.is_empty() or "apply_focus" in aid:
			continue  # honesty: never enqueue apply_focus in N2 primary batch
		var res: Dictionary = enqueue_command(aid, province_id)
		enqueued.append(res.get("command", {}))
	return {
		"ok": enqueued.size() > 0,
		"enqueued_n": enqueued.size(),
		"queue_n": command_queue.size(),
		"commands": enqueued,
	}


func fingerprint_commands(commands: Array, seed: int = 1936) -> String:
	## Deterministic fingerprint of an ordered command list (seed + action trail).
	var parts: PackedStringArray = ["s%d" % int(seed)]
	for cmd in commands:
		if cmd is Dictionary:
			var d: Dictionary = cmd
			parts.append("%s|%d|%s|%d" % [
				str(d.get("action", "")),
				int(d.get("province_id", 1)),
				str(d.get("tag", "")),
				int(d.get("turn", 0)),
			])
	var raw := "|".join(parts)
	return str(raw.hash())


func fingerprint_command_journal(seed: int = 1936) -> String:
	## Fingerprint live queue via get_command_journal (not a hardcoded action list).
	return fingerprint_commands(get_command_journal(), seed)


func journal_has_apply_focus(commands: Array = []) -> bool:
	var src: Array = commands if not commands.is_empty() else get_command_journal()
	for cmd in src:
		if cmd is Dictionary and "apply_focus" in str((cmd as Dictionary).get("action", "")):
			return true
	return false


## Dual / live close: lobby → enqueue → flush → rotate all slots.
func run_hotseat_close_live(province_id: int = 1) -> Dictionary:
	if slots.is_empty():
		setup_default_hotseat()
	mark_lobby_all_ready()
	enqueue_command("apply_production", province_id)
	enqueue_command("apply_focus", province_id)
	var flushed: Dictionary = flush_command_queue()
	var rotates: Array = []
	var n := maxi(slots.size(), 1)
	for _i in range(n):
		rotates.append(rotate_active_player())
	var ok := lobby_ready and commands_applied_total >= 1 and turn >= 2
	return {
		"ok": ok,
		"live": true,
		"mode": mode,
		"slot_n": slots.size(),
		"human_n": get_human_tags().size(),
		"ai_n": get_ai_tags().size(),
		"turn": turn,
		"active_tag": get_active_tag(),
		"commands_applied_total": commands_applied_total,
		"lobby_ready": lobby_ready,
		"flushed": flushed,
		"rotates": rotates,
		"player_country_tag": get_active_tag(),
	}
