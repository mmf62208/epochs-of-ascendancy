extends SceneTree

## ORIDIOM-1b: FormationMovement.hop_days must use the real terrain/kind
## strings (GDScript `or` is a bool). Matrix must match Python
## unit_own_land_march_product.hop_days within 1%. Must FAIL on main
## 61a80433 (`str(terrain or "plains")` / `str(template_kind or "infantry")`
## both become "true") and PASS after the strip/lower + empty fallbacks.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessOrIdiom1bMarchCostTest.gd

const SRC_MV := "res://scripts/formations/FormationMovement.gd"
const INFRA := 0.5
const SPEED := 1.0
const REL_TOL := 0.01

const TERRAINS: Array[String] = [
	"plains", "hills", "forest", "desert", "urban", "jungle", "marsh", "mountain",
]
const KINDS: Array[String] = [
	"infantry", "mountain_infantry", "armor", "motorized",
]

## hop_days(t, 0.5, INFANTRY_SPEED, k) from unit_own_land_march_product.py
const PY_HOP: Dictionary = {
	"plains|infantry": 1.25,
	"plains|mountain_infantry": 1.25,
	"plains|armor": 1.25,
	"plains|motorized": 1.25,
	"hills|infantry": 1.50,
	"hills|mountain_infantry": 1.50,
	"hills|armor": 1.50,
	"hills|motorized": 1.50,
	"forest|infantry": 1.5625,
	"forest|mountain_infantry": 1.5625,
	"forest|armor": 1.5625,
	"forest|motorized": 1.5625,
	"desert|infantry": 1.625,
	"desert|mountain_infantry": 1.625,
	"desert|armor": 1.625,
	"desert|motorized": 1.625,
	"urban|infantry": 1.4375,
	"urban|mountain_infantry": 1.4375,
	"urban|armor": 1.4375,
	"urban|motorized": 1.4375,
	"jungle|infantry": 1.875,
	"jungle|mountain_infantry": 1.875,
	"jungle|armor": 1.875,
	"jungle|motorized": 1.875,
	"marsh|infantry": 2.00,
	"marsh|mountain_infantry": 2.00,
	"marsh|armor": 2.00,
	"marsh|motorized": 2.00,
	"mountain|infantry": 2.25,
	"mountain|mountain_infantry": 1.575,
	"mountain|armor": 3.00,
	"mountain|motorized": 3.00,
}

var _failures := 0
var _mv: Script = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessOrIdiom1bMarchCostTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessOrIdiom1bMarchCostTest: ", msg)


func _within_pct(got: float, exp: float) -> bool:
	var denom := maxf(absf(exp), 1e-9)
	return absf(got - exp) / denom <= REL_TOL


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt_a := src.find("\nfunc ", i + needle.length())
	var nxt_b := src.find("\nstatic func ", i + needle.length())
	var nxt := -1
	if nxt_a >= 0 and nxt_b >= 0:
		nxt = mini(nxt_a, nxt_b)
	elif nxt_a >= 0:
		nxt = nxt_a
	else:
		nxt = nxt_b
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessOrIdiom1bMarchCostTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessOrIdiom1bMarchCostTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_needles()
	_mv = load(SRC_MV) as Script
	if _mv == null:
		_fail("FormationMovement.gd missing")
		return
	_test_b1_matrix_within_1pct()
	_test_b1_mountain_infantry_1_8x_plains()
	_test_b1_mountain_infantry_discount()
	_test_b1_armor_mountain_penalty()
	_test_b2_empty_defaults()


func _test_source_needles() -> void:
	var src := _read(SRC_MV)
	var hop := _slice_func(src, "hop_days")
	if hop.is_empty():
		_fail("src_hop_days_missing: hop_days not found")
		return
	if "terrain or" in hop:
		_fail("src_no_terrain_or: hop_days still uses `terrain or` (GDScript or → bool \"true\")")
	else:
		_pass("src_no_terrain_or")
	if "template_kind or" in hop:
		_fail("src_no_template_kind_or: hop_days still uses `template_kind or` (GDScript or → bool \"true\")")
	else:
		_pass("src_no_template_kind_or")
	if "str(terrain).strip_edges().to_lower()" not in hop:
		_fail("src_terrain_strip_lower: hop_days must strip/lower the real terrain string")
	else:
		_pass("src_terrain_strip_lower")
	if "str(template_kind).strip_edges().to_lower()" not in hop:
		_fail("src_kind_strip_lower: hop_days must strip/lower the real template_kind string")
	else:
		_pass("src_kind_strip_lower")
	if "if terr.is_empty()" not in hop or "terr = \"plains\"" not in hop:
		_fail("src_empty_terrain_default: empty terrain must fall back to plains")
	else:
		_pass("src_empty_terrain_default")
	if "if kind.is_empty()" not in hop or "kind = \"infantry\"" not in hop:
		_fail("src_empty_kind_default: empty kind must fall back to infantry")
	else:
		_pass("src_empty_kind_default")
	if "ARMOR_MOUNTAIN_PENALTY" not in hop or "_is_armor_motor" not in hop:
		_fail("src_armor_mountain_penalty_branch: hop_days missing armour mountain penalty")
	else:
		_pass("src_armor_mountain_penalty_branch")


func _hop(terrain: String, kind: String) -> float:
	return float(_mv.call("hop_days", terrain, INFRA, SPEED, kind))


func _test_b1_matrix_within_1pct() -> void:
	var mismatches := 0
	for t in TERRAINS:
		for k in KINDS:
			var key := "%s|%s" % [t, k]
			if not PY_HOP.has(key):
				_fail("b1_matrix_within_1pct: missing py fixture %s" % key)
				return
			var exp := float(PY_HOP[key])
			var got := _hop(t, k)
			if not _within_pct(got, exp):
				mismatches += 1
				_fail(
					"b1_matrix_within_1pct: %s got=%.6f py=%.6f"
					% [key, got, exp]
				)
	if mismatches == 0:
		_pass(
			"b1_matrix_within_1pct: 8 terrains × 4 kinds within 1%% of py hop_days"
		)


func _test_b1_mountain_infantry_1_8x_plains() -> void:
	var plains := _hop("plains", "infantry")
	var mountain := _hop("mountain", "infantry")
	if plains <= 1e-9:
		_fail("b1_mountain_infantry_1_8x_plains: plains hop_days is 0")
		return
	var ratio := mountain / plains
	if not _within_pct(ratio, 1.8):
		_fail(
			"b1_mountain_infantry_1_8x_plains: mountain/plains=%.6f want 1.8 (mountain=%.6f plains=%.6f)"
			% [ratio, mountain, plains]
		)
		return
	_pass("b1_mountain_infantry_1_8x_plains: ratio=%.6f" % ratio)


func _test_b1_mountain_infantry_discount() -> void:
	var inf_mtn := _hop("mountain", "infantry")
	var mtn_inf := _hop("mountain", "mountain_infantry")
	var exp := 1.575
	if not _within_pct(mtn_inf, exp):
		_fail(
			"b1_mountain_infantry_discount: mountain/mountain_infantry=%.6f py=%.6f (infantry=%.6f)"
			% [mtn_inf, exp, inf_mtn]
		)
		return
	if mtn_inf >= inf_mtn:
		_fail(
			"b1_mountain_infantry_discount: mountain infantry %.6f not faster than infantry %.6f"
			% [mtn_inf, inf_mtn]
		)
		return
	_pass("b1_mountain_infantry_discount: %.6f < infantry %.6f" % [mtn_inf, inf_mtn])


func _test_b1_armor_mountain_penalty() -> void:
	var inf_mtn := _hop("mountain", "infantry")
	var arm_mtn := _hop("mountain", "armor")
	var mot_mtn := _hop("mountain", "motorized")
	if not _within_pct(arm_mtn, 3.0):
		_fail(
			"b1_armor_mountain_penalty: mountain/armor=%.6f py=3.0 (clamped; infantry=%.6f)"
			% [arm_mtn, inf_mtn]
		)
		return
	if not _within_pct(mot_mtn, 3.0):
		_fail(
			"b1_armor_mountain_penalty: mountain/motorized=%.6f py=3.0"
			% mot_mtn
		)
		return
	if arm_mtn < inf_mtn:
		_fail(
			"b1_armor_mountain_penalty: armor %.6f faster than infantry %.6f on mountain"
			% [arm_mtn, inf_mtn]
		)
		return
	_pass("b1_armor_mountain_penalty: armor=%.6f motorized=%.6f" % [arm_mtn, mot_mtn])


func _test_b2_empty_defaults() -> void:
	var plains_inf := _hop("plains", "infantry")
	var empty_t := _hop("", "infantry")
	var empty_k := _hop("plains", "")
	var both := _hop("", "")
	var mtn_empty_k := _hop("mountain", "")
	var mtn_inf := _hop("mountain", "infantry")
	if not _within_pct(empty_t, plains_inf):
		_fail(
			"b2_empty_terrain_defaults_plains: empty terrain=%.6f plains=%.6f"
			% [empty_t, plains_inf]
		)
	else:
		_pass("b2_empty_terrain_defaults_plains")
	if not _within_pct(empty_k, plains_inf):
		_fail(
			"b2_empty_kind_defaults_infantry: empty kind plains=%.6f infantry=%.6f"
			% [empty_k, plains_inf]
		)
	else:
		_pass("b2_empty_kind_defaults_infantry")
	if not _within_pct(both, plains_inf):
		_fail(
			"b2_empty_kind_defaults_infantry: empty terrain+kind=%.6f plains/infantry=%.6f"
			% [both, plains_inf]
		)
	if not _within_pct(mtn_empty_k, mtn_inf):
		_fail(
			"b2_empty_kind_defaults_infantry: empty kind mountain=%.6f infantry=%.6f"
			% [mtn_empty_k, mtn_inf]
		)
	else:
		_pass("b2_empty_kind_defaults_infantry mountain=infantry")
