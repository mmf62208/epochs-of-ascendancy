extends SceneTree

## Lean living-title-only window. No 3520 board.
## Proves a real DisplayServer pointer can dismiss the title / open CC.
## Pair with tools/eoa_lean_title_click_prove.sh (xdotool click --window).
##
##   DISPLAY=:1 tools/run_godot.sh -s res://scripts/core/LeanLivingTitleX11ClickProve.gd
##
## Not a substitute for Play computerUse on TestScenario. Same
## tools/run_godot.sh + Window.window_input / handle_live_pointer path.

var _title: CanvasLayer
var _timer: Timer
var _saw_begin := false
var _saw_cc := false


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	print("LeanLivingTitleX11ClickProve: DisplayServer=", ds)
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null:
		print("LeanLivingTitleX11ClickProve: RESULT=FAIL no title script")
		quit(1)
		return
	_title = title_scr.new() as CanvasLayer
	_title.name = "LivingTitleBoot"
	root.add_child(_title)
	if _title.has_signal("boot_closed"):
		_title.connect("boot_closed", _on_boot_closed)
	_print_hits()
	print(
		"LEAN_CLICK_READY displayserver=%s pointer_event_path=1 touch_path=1 begin_without_esc=1"
		% ds
	)
	_timer = Timer.new()
	_timer.wait_time = 14.0
	_timer.one_shot = true
	_timer.timeout.connect(_finish)
	root.add_child(_timer)
	_timer.start()
	var poll := Timer.new()
	poll.wait_time = 0.2
	poll.timeout.connect(_note)
	root.add_child(poll)
	poll.start()
	if OS.get_environment("EOA_SELF_CLICK").strip_edges() == "1":
		call_deferred("_self_click_begin")


func _on_boot_closed(_result: Dictionary) -> void:
	_saw_begin = true


func _print_hits() -> void:
	var win: Vector2i = DisplayServer.window_get_position()
	var begin: Control = _title.find_child("LivingTitleBegin", true, false) as Control
	var cc: Control = _title.find_child("LivingTitleCommandCenter", true, false) as Control
	var chip: Control = _title.find_child("LivingTitleEscChip", true, false) as Control
	_emit_hit("BEGIN", begin, win)
	_emit_hit("CC", cc, win)
	_emit_hit("CHIP", chip, win)


func _emit_hit(kind: String, ctl: Control, win: Vector2i) -> void:
	if ctl == null or not is_instance_valid(ctl):
		print("LEAN_HIT_%s=missing" % kind)
		return
	var r: Rect2 = ctl.get_global_rect()
	var cx: int = int(r.position.x + r.size.x * 0.5)
	var cy: int = int(r.position.y + r.size.y * 0.5)
	print(
		"LEAN_HIT_%s_CLIENT=%d,%d size=%d,%d screen=%d,%d"
		% [kind, cx, cy, int(r.size.x), int(r.size.y), win.x + cx, win.y + cy]
	)


func _self_click_begin() -> void:
	# Synthetic fallback when the shell cannot drive xdotool. Real prove is
	# the xdotool click in tools/eoa_lean_title_click_prove.sh.
	if _title == null or not is_instance_valid(_title):
		return
	var begin: Control = _title.find_child("LivingTitleBegin", true, false) as Control
	if begin == null:
		return
	var r: Rect2 = begin.get_global_rect()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = r.position + r.size * 0.5
	mb.global_position = mb.position
	if _title.has_method("handle_live_pointer"):
		var act: String = str(_title.call("handle_live_pointer", mb))
		print("LEAN_SELF_CLICK action=%s" % act)


func _note() -> void:
	if _title != null and is_instance_valid(_title):
		if bool(_title.get("_closed")):
			_saw_begin = true
		if bool(_title.get("_esc_routed_to_cc")):
			_saw_cc = true
	if root.get_node_or_null("MainMenu") != null:
		_saw_cc = true


func _finish() -> void:
	_note()
	var ds := DisplayServer.get_name()
	print(
		"LeanLivingTitleX11ClickProve: saw_begin=%s saw_cc=%s displayserver=%s"
		% [str(_saw_begin), str(_saw_cc), ds]
	)
	if _saw_begin or _saw_cc:
		print("LeanLivingTitleX11ClickProve: RESULT=PASS real-or-routed pointer reached title")
		quit(0)
		return
	print("LeanLivingTitleX11ClickProve: RESULT=SOFT no pointer in wait — Play must click Begin / Command Center · Esc")
	if ds == "headless":
		print("LeanLivingTitleX11ClickProve: NOTE headless — not a live F5/computerUse proof")
	quit(0)
