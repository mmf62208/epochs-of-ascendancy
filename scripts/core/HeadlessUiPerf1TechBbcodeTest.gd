extends SceneTree

## UI-PERF-1: Technology footer is a Label. The map legend is BBCode.
## Strip every [tag] and keep the unlocked name (refinery on GER 1936).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessUiPerf1TechBbcodeTest.gd
##
## Headless is NOT live Play.

const LEGEND := "[color=#8899aa]🔬 Unlocks: [/color][color=#6ec8ff]refinery[/color]"
const SRC_SCREEN := "res://scripts/ui/TechnologyScreen.gd"
const SRC_CTX := "res://scripts/map/MapTechnologyContext.gd"

var _failures: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	_test_scripts_compile()
	_test_strip_keeps_refinery()
	_test_footer_uses_strip()
	var ok := _failures == 0
	print("HeadlessUiPerf1TechBbcodeTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessUiPerf1TechBbcodeTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessUiPerf1TechBbcodeTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessUiPerf1TechBbcodeTest: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _load_script(path: String) -> GDScript:
	var scr: Variant = load(path)
	if scr == null or not (scr is GDScript):
		_fail("did not load %s" % path)
		return null
	var gs := scr as GDScript
	if not gs.can_instantiate():
		_fail("did not compile %s" % path)
		return null
	return gs


func _test_scripts_compile() -> void:
	var paths := [
		"res://scripts/map/MapRenderer.gd",
		"res://scripts/map/MapManager.gd",
		"res://scripts/map/ProvinceInsight.gd",
		"res://scripts/map/InfrastructureOverlayLayer.gd",
		"res://scripts/technology/TechnologyManager.gd",
		"res://scripts/ui/TechnologyScreen.gd",
		"res://scripts/core/WindowedUiPerf1Probe.gd",
	]
	var bad := false
	for path in paths:
		if _load_script(path) == null:
			bad = true
	if not bad:
		_pass("edited scripts compile")


func _test_strip_keeps_refinery() -> void:
	var gs := _load_script(SRC_SCREEN)
	if gs == null:
		return
	var screen: Node = gs.new()
	var plain := str(screen.call("_strip_bbcode_tags", LEGEND))
	screen.free()
	if plain.find("[color=") >= 0 or plain.find("[/color]") >= 0:
		_fail("strip left a color tag: %s" % plain)
		return
	if plain.find("refinery") < 0:
		_fail("strip dropped refinery: %s" % plain)
		return
	if plain.find("Unlocks:") < 0:
		_fail("strip dropped Unlocks label: %s" % plain)
		return
	_pass("plain footer keeps refinery without [color=]")


func _test_footer_uses_strip() -> void:
	var src := _read(SRC_SCREEN)
	var ctx := _read(SRC_CTX)
	if src.find("footer_label.text = footer") < 0:
		_fail("footer_label.text assignment missing")
		return
	if src.find("footer += \" · \" + _strip_bbcode_tags(current_data.map_legend_bbcode)") < 0:
		_fail("footer appends raw map_legend_bbcode")
		return
	if ctx.find("[color=#6ec8ff]%s[/color]") < 0:
		_fail("legend source lost the refinery color wrap")
		return
	_pass("footer strips legend; source still wraps the unlock name")
