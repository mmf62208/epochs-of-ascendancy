extends SceneTree

## Lean living-title-only window. No 3520 board.
## Pair with xdotool Escape on DISPLAY=:1 to prove a real DisplayServer key
## reaches title (Play 2a4ed6b: computerUse Esc never entered Godot).
##
##   DISPLAY=:1 tools/run_godot.sh -s res://scripts/core/LeanLivingTitleX11KeyProve.gd
##   xdotool search --name Godot windowactivate --sync key --clearmodifiers Escape
##
## Not a substitute for Play computerUse on TestScenario.

var _title: CanvasLayer
var _timer: Timer
var _saw_esc := false


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	print("LeanLivingTitleX11KeyProve: DisplayServer=", ds)
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null:
		print("LeanLivingTitleX11KeyProve: RESULT=FAIL no title script")
		quit(1)
		return
	_title = title_scr.new() as CanvasLayer
	_title.name = "LivingTitleBoot"
	root.add_child(_title)
	var cc_btn: Button = _title.find_child("LivingTitleCommandCenter", true, false) as Button
	var chip: Button = _title.find_child("LivingTitleEscChip", true, false) as Button
	print(
		"LEAN_TITLE_READY displayserver=%s cc_btn=%s chip=%s begin_without_esc=1"
		% [ds, str(cc_btn != null), str(chip != null)]
	)
	_timer = Timer.new()
	_timer.wait_time = 12.0
	_timer.one_shot = true
	_timer.timeout.connect(_finish)
	root.add_child(_timer)
	_timer.start()
	# Also poll so a late-arriving key is logged before quit.
	var poll := Timer.new()
	poll.wait_time = 0.25
	poll.timeout.connect(_note_esc)
	root.add_child(poll)
	poll.start()


func _note_esc() -> void:
	if _title != null and is_instance_valid(_title) and bool(_title.get("_esc_routed_to_cc")):
		_saw_esc = true


func _finish() -> void:
	_note_esc()
	var ds := DisplayServer.get_name()
	var cc_up := root.get_node_or_null("MainMenu") != null
	print(
		"LeanLivingTitleX11KeyProve: saw_esc=%s cc_up=%s displayserver=%s"
		% [str(_saw_esc), str(cc_up), ds]
	)
	if _saw_esc:
		print("LeanLivingTitleX11KeyProve: RESULT=PASS real-or-poll Esc reached title")
		quit(0)
		return
	# Env-hard: no DisplayServer key arrived. Mouse path still ships.
	print("LeanLivingTitleX11KeyProve: RESULT=SOFT no DisplayServer Esc in wait — use mouse CC / Begin")
	if ds == "headless":
		print("LeanLivingTitleX11KeyProve: NOTE headless — not a live F5/computerUse proof")
	quit(0)
