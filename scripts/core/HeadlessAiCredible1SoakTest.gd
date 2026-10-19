extends SceneTree

## AI-only 1936 soak. Player tag OBS owns nothing, so every major is AI.
## Length and seed label come from EOA_AIC_SOAK_DAYS and EOA_AIC_SOAK_SEED.
## Decisions do not read the seed: there is no RNG. The seed labels the run
## so two processes of the same settings can be compared.

var _failures := 0
var _war: GDScript
var _ai: GDScript
var _cap: GDScript
var _end: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	if OS.get_environment("EOA_AI_CREDIBLE").strip_edges().is_empty():
		OS.set_environment("EOA_AI_CREDIBLE", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAiCredible1SoakTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAiCredible1SoakTest: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm == null or boot == null or tm == null:
		_fail("autoloads missing")
		_finish({})
		return
	var seed := int(OS.get_environment("EOA_AIC_SOAK_SEED") if not OS.get_environment("EOA_AIC_SOAK_SEED").is_empty() else "193601")
	var days := int(OS.get_environment("EOA_AIC_SOAK_DAYS") if not OS.get_environment("EOA_AIC_SOAK_DAYS").is_empty() else "1461")
	if days < 1:
		days = 1
	if not boot.boot(mm, sm, "OBS"):
		_fail("campaign boot failed")
		_finish({})
		return
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_ai = load("res://scripts/core/AiCredibleDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if _war == null or _ai == null:
		_fail("domain scripts failed to load")
		_finish({})
		return
	_pass("boot spectator=OBS seed=%d days=%d credible=%s" % [seed, days, OS.get_environment("EOA_AI_CREDIBLE")])
	_war.reset_for_test()
	_war.clear_rule_overrides()
	_ai.reset_for_test()
	if _cap != null:
		_cap.reset_for_test()
	var wall0 := Time.get_ticks_msec()
	var cursor := 0
	var max_chunk_ms := 0
	var stalled := false
	while cursor < days:
		var step := mini(20, days - cursor)
		var chunk0 := Time.get_ticks_msec()
		var before := int(tm.total_days_elapsed)
		var advanced: Dictionary = tm.call("advance_live_f5_equivalent_days", step)
		var after := int(tm.total_days_elapsed)
		var chunk_ms := int(Time.get_ticks_msec() - chunk0)
		if chunk_ms > max_chunk_ms:
			max_chunk_ms = chunk_ms
		if after <= before:
			stalled = true
			_fail("stall at day %d advance=%s" % [before, str(advanced)])
			break
		if chunk_ms > 600000:
			_fail("month chunk %d ms at day %d" % [chunk_ms, after])
			break
		cursor = after
		if _end != null and _end.latched():
			_pass("campaign end latched at day %d" % after)
			break
		if _war.ai_stopped():
			_pass("ai_stopped at day %d" % after)
			break
	var wall_ms := int(Time.get_ticks_msec() - wall0)
	var summary := _score(seed, days, int(tm.total_days_elapsed), wall_ms, max_chunk_ms)
	if stalled:
		summary["stalled"] = true
	_finish(summary)


func _score(seed: int, asked: int, reached: int, wall_ms: int, max_chunk_ms: int) -> Dictionary:
	var trace: String = str(_ai.trace_text())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(trace.to_utf8_buffer())
	var trace_md5 := ctx.finish().hex_encode()
	var declares: Array = []
	var justifies: Dictionary = {}
	var peaces: Array = []
	var nonsense: Array = []
	for line in trace.split("\n"):
		if line.is_empty():
			continue
		if line.begins_with("JUSTIFY "):
			var att := _field(line, "att")
			var defender := _field(line, "def")
			var day := int(_field(line, "day"))
			justifies["%s>%s" % [att, defender]] = day
			var second := int(_field(line, "second"))
			var ratio := float(_field(line, "ratio"))
			if second >= 1 and ratio + 0.0000001 < 2.25:
				nonsense.append("second_front %s" % line)
		elif line.begins_with("DECLARE "):
			var att2 := _field(line, "att")
			var def2 := _field(line, "def")
			var day2 := int(_field(line, "day"))
			var ok := _field(line, "ok")
			declares.append({"day": day2, "att": att2, "def": def2, "ok": ok})
			if day2 < 180:
				nonsense.append("early_declare %s" % line)
			var key := "%s>%s" % [att2, def2]
			if not justifies.has(key) or day2 - int(justifies[key]) < 30:
				nonsense.append("no_justify %s" % line)
		elif line.begins_with("PEACE "):
			peaces.append(line)
	var log: Array = _war.event_log()
	var wars: Array = []
	for raw in log:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if str(row.get("action", "")) != "declare":
			continue
		wars.append({
			"day": int(row.get("day", -1)),
			"att": str(row.get("a", "")),
			"def": str(row.get("b", "")),
			"reason": str(row.get("reason", "")),
		})
	var hist := _history(wars, reached)
	var empty_caps: int = int(_ai.counter_get("capital_empty_days"))
	var research_idle: int = int(_ai.counter_get("research_idle_breaches"))
	var prod_idle: int = int(_ai.counter_get("production_idle_breaches"))
	if not nonsense.is_empty():
		_fail("nonsense %s" % str(nonsense))
	else:
		_pass("no nonsense declares")
	if empty_caps != 0:
		_fail("capital_empty_days=%d" % empty_caps)
	else:
		_pass("capital_empty_days=0")
	if research_idle != 0 or prod_idle != 0:
		_fail("idle research=%d production=%d" % [research_idle, prod_idle])
	else:
		_pass("no research or production idle breach")
	var expect := OS.get_environment("EOA_AIC_EXPECT_TRACE").strip_edges()
	if expect == "empty" and not trace.is_empty():
		_fail("expected an empty killswitch trace")
	elif expect == "empty":
		_pass("killswitch trace empty")
	return {
		"seed": seed,
		"asked_days": asked,
		"reached_day": reached,
		"wall_ms": wall_ms,
		"max_chunk_ms": max_chunk_ms,
		"trace_md5": trace_md5,
		"trace_lines": trace.split("\n").size() if not trace.is_empty() else 0,
		"declares": declares,
		"peaces": peaces.size(),
		"wars": wars,
		"capitulations": _capitulation_count(),
		"capital_empty_days": empty_caps,
		"research_idle_breaches": research_idle,
		"production_idle_breaches": prod_idle,
		"nonsense": nonsense,
		"history": hist,
		"credible": OS.get_environment("EOA_AI_CREDIBLE"),
	}


func _history(wars: Array, reached: int) -> Dictionary:
	var ger := false
	var jap_day := -1
	var sov_bad := false
	var west_off := 0
	var ita_first := ""
	var ita_weaker := false
	var long_open: Array = []
	var ita_seen := false
	for raw in wars:
		var row: Dictionary = raw
		var day := int(row.get("day", -1))
		var att := str(row.get("att", ""))
		var defender := str(row.get("def", ""))
		var reason := str(row.get("reason", ""))
		if att == "GER" and defender in ["POL", "CZE", "FRA"] and day <= 1461:
			ger = true
		if att == "JAP" and defender == "CHI":
			jap_day = day if jap_day < 0 else mini(jap_day, day)
		if att == "SOV" and day < 1461 and _is_major(defender):
			if _war.military_strength(defender) > _war.military_strength("SOV"):
				sov_bad = true
		if att in ["FRA", "ENG", "USA"] and day < 1461 and reason != "call_to_arms":
			west_off += 1
		if att == "ITA" and not ita_seen and reason != "call_to_arms":
			ita_seen = true
			ita_first = defender
			ita_weaker = _war.military_strength(defender) < _war.military_strength("ITA")
		if reached >= 1461 and day >= 0 and reached - day > 730 and reason != "call_to_arms":
			if _war.is_at_war(att, defender):
				long_open.append("%s-%s@%d" % [att, defender, day])
	var jap_ok := jap_day >= 0 and jap_day <= 731
	return {
		"ger_neighbour": ger,
		"jap_chi_day": jap_day,
		"jap_by_1938": jap_ok,
		"sov_stronger_major": sov_bad,
		"west_offensive": west_off,
		"ita_first": ita_first,
		"ita_weaker": ita_weaker,
		"long_open": long_open,
	}


func _is_major(tag: String) -> bool:
	var majors: Variant = _war.rules().get("scenario_majors", [])
	return majors is Array and (majors as Array).has(tag)


func _capitulation_count() -> int:
	if _cap == null:
		return 0
	var gd := get_root().get_node_or_null("GameData")
	if gd == null or not ("peace_state" in gd):
		return 0
	var st: Variant = gd.peace_state.get("campaign_capitulation", {})
	if not (st is Dictionary):
		return 0
	var rows: Variant = (st as Dictionary).get("capitulated", {})
	if rows is Dictionary:
		return (rows as Dictionary).size()
	if rows is Array:
		return (rows as Array).size()
	return 0


func _field(line: String, key: String) -> String:
	var needle := key + "="
	var parts := line.split(" ")
	for part in parts:
		if str(part).begins_with(needle):
			return str(part).substr(needle.length())
	return ""


func _finish(summary: Dictionary) -> void:
	var line := JSON.stringify(summary)
	print("TRACE_MD5=", str(summary.get("trace_md5", "")))
	print("AIC_SOAK_JSON=", line)
	var ok := _failures == 0
	print("HeadlessAiCredible1SoakTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAiCredible1SoakTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
