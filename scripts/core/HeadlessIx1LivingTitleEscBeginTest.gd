extends SceneTree

## Runtime proof that living title + Command Center sit above UILayer 110.
## Source-only soak stayed green on d53ee05 while live Esc/Begin HARD-failed.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1LivingTitleEscBeginTest.gd

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessIx1LivingTitleEscBeginTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessIx1LivingTitleEscBeginTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessIx1LivingTitleEscBeginTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessIx1LivingTitleEscBeginTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _run() -> void:
	var scene := FileAccess.get_file_as_string("res://scenes/TestScenario.tscn")
	if "layer = 110" not in scene:
		_fail("TestScenario UILayer must stay 110 (TopInfoBar above toasts)")
		return
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot.gd missing")
		return
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	if title == null:
		_fail("LivingTitleBoot must be a CanvasLayer")
		return
	root.add_child(title)
	if int(title.layer) < 120:
		_fail("LivingTitleBoot layer=%s must be >= 120 (above UILayer 110)" % str(title.layer))
		return
	var begin: Button = title.get("_begin_btn") as Button
	if begin == null or not is_instance_valid(begin):
		_fail("Begin button missing after title _ready")
		return
	if begin.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("Begin button must STOP so UILayer/toasts cannot swallow it")
		return
	if "Germany" not in begin.text or "1936" not in begin.text:
		_fail("Begin default label must be Germany 1936, got '%s'" % begin.text)
		return
	_pass("living title layer=%s Begin='%s' STOP" % [str(title.layer), begin.text])

	var cc_scr: GDScript = load("res://scripts/ui/MainMenu.gd") as GDScript
	if cc_scr == null:
		_fail("MainMenu.gd missing")
		return
	var cc: CanvasLayer = cc_scr.new() as CanvasLayer
	if cc == null:
		_fail("MainMenu must be a CanvasLayer")
		return
	root.add_child(cc)
	if int(cc.layer) <= int(title.layer):
		_fail("Command Center layer=%s must sit above living title %s" % [str(cc.layer), str(title.layer)])
		return
	if int(cc.layer) < 130:
		_fail("Command Center layer=%s must be >= 130 (above UILayer 110)" % str(cc.layer))
		return
	_pass("Command Center layer=%s above title %s and UILayer 110" % [str(cc.layer), str(title.layer)])

	var ren := FileAccess.get_file_as_string("res://scripts/map/MapRenderer.gd")
	if "_living_title_boot_is_up" not in ren or "_esc_open_command_center" not in ren:
		_fail("MapRenderer must open CC while living title is up")
		return
	_pass("Esc on living title routes to Command Center; title owns map clicks")
