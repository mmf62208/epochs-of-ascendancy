extends SceneTree

## STARTUP-PARITY (test-only): empty-board 1936 garrison seed vs occupied skip.
## Does not launch TestScenario / living title. That live path is WindowedStartupParityTest.
## Proves the required 575 baseline is seed_1936_start_garrisons on an empty formation
## table (same world_accurate board files as F5). One occupied Berlin hex skips 1.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessStartupParityGarrisonTest.gd

const BERLIN := 710300
const EXPECT_PROVINCES := 3596
const EXPECT_GARRISONS := 575
const TAGS := ["GER", "FRA", "ENG", "SOV", "ITA", "JAP", "USA", "POL", "CZE"]

var _failures := 0
var _boot: GDScript
var _out: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessStartupParityGarrisonTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessStartupParityGarrisonTest: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm == null or lm == null or _boot == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.call("boot", mm, sm, "GER"):
		_fail("board boot failed")
		_finish()
		return
	var n := 0
	if mm.has_method("get_province_count"):
		n = int(mm.call("get_province_count"))
	var berlin_owner := ""
	if mm.has_method("get_province_owner"):
		berlin_owner = str(mm.call("get_province_owner", BERLIN))
	print(
		"EOA_STARTUP_PARITY who=empty_board provinces=%d berlin_owner=%s expect_provinces=%d"
		% [n, berlin_owner, EXPECT_PROVINCES]
	)
	if n != EXPECT_PROVINCES:
		_fail("province_n=%d want %d" % [n, EXPECT_PROVINCES])
	else:
		_pass("empty-board provinces=%d" % n)
	if berlin_owner != "GER":
		_fail("berlin_owner=%s want GER" % berlin_owner)
	else:
		_pass("berlin_710300_owner=GER")
	_clear(lm)
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("seed_1936_start_garrisons missing")
		_finish()
		return
	var empty: Dictionary = lm.call("seed_1936_start_garrisons", true)
	_out["empty_board"] = _seed_row(empty)
	_assert_empty_seed(empty)
	_clear(lm)
	_boot.call("make_division", "occ_berlin", "GER", BERLIN)
	var occupied: Dictionary = lm.call("seed_1936_start_garrisons", true)
	_out["occupied_berlin"] = _seed_row(occupied)
	_assert_occupied_skip(occupied)
	_finish()


func _assert_empty_seed(seeded: Dictionary) -> void:
	var placed := int(seeded.get("placed", -1))
	var skipped := int(seeded.get("skipped_occupied", -1))
	var targets := int(seeded.get("targets", -1))
	print(
		"EOA_STARTUP_PARITY who=empty_seed placed=%d skipped_occupied=%d targets=%d counts=%s target_counts=%s skipped_counts=%s"
		% [
			placed,
			skipped,
			targets,
			str(seeded.get("counts", {})),
			str(seeded.get("target_counts", {})),
			str(seeded.get("skipped_counts", {})),
		]
	)
	if placed != EXPECT_GARRISONS or skipped != 0 or targets != EXPECT_GARRISONS:
		_fail(
			"empty board placed=%d skipped=%d targets=%d want placed=targets=%d skipped=0"
			% [placed, skipped, targets, EXPECT_GARRISONS]
		)
		return
	if placed + skipped != targets:
		_fail("empty identity placed+skipped=%d != targets=%d" % [placed + skipped, targets])
		return
	_pass("empty-board 575 garrisons, 0 occupied skips, 575 targets")


func _assert_occupied_skip(seeded: Dictionary) -> void:
	var placed := int(seeded.get("placed", -1))
	var skipped := int(seeded.get("skipped_occupied", -1))
	var targets := int(seeded.get("targets", -1))
	print(
		"EOA_STARTUP_PARITY who=occupied_berlin placed=%d skipped_occupied=%d targets=%d"
		% [placed, skipped, targets]
	)
	if targets != EXPECT_GARRISONS:
		_fail("occupied-berlin targets=%d want %d" % [targets, EXPECT_GARRISONS])
		return
	if skipped < 1 or placed + skipped != targets:
		_fail("occupied Berlin placed=%d skipped=%d targets=%d" % [placed, skipped, targets])
		return
	if placed != EXPECT_GARRISONS - skipped:
		_fail("occupied identity placed=%d != 575-skipped=%d" % [placed, EXPECT_GARRISONS - skipped])
		return
	_pass(
		"occupied hex skipped (placed %d + skipped %d = targets %d). Live F5 535 is this skip class, not a second board."
		% [placed, skipped, targets]
	)


func _seed_row(seeded: Dictionary) -> Dictionary:
	return {
		"placed": int(seeded.get("placed", -1)),
		"skipped_occupied": int(seeded.get("skipped_occupied", -1)),
		"targets": int(seeded.get("targets", -1)),
		"counts": seeded.get("counts", {}),
		"target_counts": seeded.get("target_counts", {}),
		"skipped_counts": seeded.get("skipped_counts", {}),
	}


func _clear(lm: Node) -> void:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		lm.formations.clear()
	if lm != null and "_garrisons_1936_seeded" in lm:
		lm._garrisons_1936_seeded = false


func _finish() -> void:
	var ok := _failures == 0
	_out["ok"] = ok
	_out["expect_garrisons"] = EXPECT_GARRISONS
	_out["expect_provinces"] = EXPECT_PROVINCES
	_out["tags"] = TAGS
	_out["note"] = "575 is empty-board seed_1936_start_garrisons. Live F5 skips OOB-occupied border/capital hexes."
	var out_dir := OS.get_environment("EOA_STARTUP_PARITY_OUT").strip_edges()
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open("%s/empty_board_garrison.json" % out_dir, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(_out, "\t"))
			f.close()
	print("HeadlessStartupParityGarrisonTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
