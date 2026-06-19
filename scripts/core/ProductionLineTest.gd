class_name ProductionLineTest
extends RefCounted

## Headless checks for the production line system. Call from TestRunner or the Godot CLI.

const ENV_FULL_LEADER_ROSTER_TESTS := "EOA_RUN_FULL_LEADER_TESTS"


static func _get_leader_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	return tree.root.get_node_or_null("LeaderManager")


static func _run_full_leader_roster_tests() -> bool:
	return OS.get_environment(ENV_FULL_LEADER_ROSTER_TESTS) == "1"


static func run_all(design_data: DesignDataLoader) -> bool:
	var ok := true
	ok = _test_data_loaded(design_data) and ok
	ok = _test_retooling_similarity(design_data) and ok
	ok = _test_production_and_tooling(design_data) and ok
	ok = _test_new_design_reliability_debuff(design_data) and ok
	ok = _test_refinement(design_data) and ok
	ok = _test_refinement_tradeoffs(design_data) and ok
	ok = _test_production_manager() and ok
	ok = _test_equipment_shortages() and ok
	ok = _test_national_equipment_stockpile() and ok
	ok = _test_infantry_equipment_stats(design_data) and ok
	ok = _test_priority_reinforcement() and ok
	ok = _test_sustainment_equipment(design_data) and ok
	ok = _test_combat_resolver(design_data) and ok
	ok = _test_phase_combat_resolution() and ok
	ok = _test_battle_manager_assault() and ok
	ok = _test_combat_width() and ok
	ok = _test_leader_manager() and ok
	ok = _test_formation_spawner() and ok
	ok = _test_assignment_screen_backends() and ok
	ok = _test_cargo_logistics(design_data) and ok
	ok = _test_armed_cargo_penalty(design_data) and ok
	ok = _test_armed_merchant_template(design_data) and ok
	return ok


static func _get_production_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	return tree.root.get_node_or_null("ProductionManager")


static func _test_production_manager() -> bool:
	var pm := _get_production_manager()
	if pm == null:
		print("  [SKIP] ProductionManager autoload not available (headless CLI)")
		return true

	pm.remove_line("mgr_test_a")
	pm.remove_line("mgr_test_b")

	pm.set_production_stance("quantity")
	pm.apply_doctrine("land_mass_production")

	var line_a = pm.create_line("mgr_test_a")
	var line_b = pm.create_line("mgr_test_b")
	line_a != null and line_b != null

	pm.set_line_template("mgr_test_a", "m3_stuart_light")
	pm.set_line_template("mgr_test_b", "m4_sherman_medium")

	var report: Dictionary = pm.advance_days(150.0)
	var units := int(report.get("total_units_completed", 0))
	var family_units: int = pm.get_family_units_produced("us_armored_ww2")

	pm.set_production_stance("balanced")
	pm.revoke_doctrine("land_mass_production")
	pm.remove_line("mgr_test_a")
	pm.remove_line("mgr_test_b")

	var passed := units >= 1 and family_units >= 1
	if passed:
		print("  [PASS] ProductionManager units=", units, " family=", family_units)
	else:
		print("  [FAIL] ProductionManager units=", units, " family=", family_units)
	return passed


static func _test_data_loaded(design_data: DesignDataLoader) -> bool:
	var modules_ok := design_data.modules.size() >= 6
	var templates_ok := design_data.templates.has("m3_stuart_light") and design_data.templates.has("m4_sherman_medium")
	var rules_ok := not design_data.production_rules.is_empty()
	if modules_ok and templates_ok and rules_ok:
		print("  [PASS] design data loaded")
		return true
	print("  [FAIL] design data loaded (modules=", design_data.modules.size(), " templates=", design_data.templates.keys(), ")")
	return false


static func _test_retooling_similarity(design_data: DesignDataLoader) -> bool:
	var stuart: UnitTemplate = design_data.get_template("m3_stuart_light")
	var sherman: UnitTemplate = design_data.get_template("m4_sherman_medium")
	var rules := design_data.production_rules
	var similarity := RetoolingCalculator.compute_similarity(stuart, sherman, rules)
	var days := RetoolingCalculator.compute_retooling_days(similarity, rules)
	# Shared engine + same base_type → partial similarity, not full retool.
	var passed := similarity > 0.3 and similarity < 1.0 and days > 3.0 and days < 42.0
	if passed:
		print("  [PASS] retooling similarity=", similarity, " days=", days)
	else:
		print("  [FAIL] retooling similarity=", similarity, " days=", days)
	return passed


static func _test_production_and_tooling(design_data: DesignDataLoader) -> bool:
	var line := ProductionLine.new(design_data, "test_line")
	line.set_template("m3_stuart_light")
	var initial_reliability := line.get_effective_reliability()
	var report := line.advance_days(120.0)
	var tooling := line.get_tooling_efficiency()
	var passed: bool = (
		int(report.get("units_completed", 0)) >= 1
		and tooling > 0.0
		and line.get_effective_reliability() >= initial_reliability
	)
	if passed:
		print("  [PASS] production units=", report["units_completed"], " tooling=", tooling)
	else:
		print("  [FAIL] production report=", report, " tooling=", tooling)
	return passed


static func _test_new_design_reliability_debuff(design_data: DesignDataLoader) -> bool:
	var line := ProductionLine.new(design_data, "immature_line")
	line.set_template("m4_sherman_medium")
	var profile := line.get_reliability_profile()
	var passed := (
		profile.design_maturity < 0.05
		and profile.effective_reliability < profile.paper_reliability * 0.72
		and profile.maintenance_index > 0.25
		and profile.combat_readiness < 0.85
	)
	if passed:
		print(
			"  [PASS] new design debuff reliability=",
			profile.effective_reliability,
			" maintenance=",
			profile.maintenance_index,
		)
	else:
		print("  [FAIL] new design profile ", profile.effective_reliability, profile.maintenance_index)
	return passed


static func _test_refinement(design_data: DesignDataLoader) -> bool:
	var line := ProductionLine.new(design_data, "refine_line")
	line.set_template("m4_sherman_medium")
	var before := line.get_reliability_profile()
	if not line.start_refinement("quality_control"):
		print("  [FAIL] could not start refinement project")
		return false
	line.advance_days(30.0)
	var after := line.get_reliability_profile()
	var passed := after.effective_reliability > before.effective_reliability
	if passed:
		print("  [PASS] refinement raised reliability ", before.effective_reliability, " -> ", after.effective_reliability)
	else:
		print("  [FAIL] refinement reliability ", before.effective_reliability, " -> ", after.effective_reliability)
	return passed


static func _test_cargo_logistics(design_data: DesignDataLoader) -> bool:
	var line := ProductionLine.new(design_data, "cargo_line")
	line.set_template("container_ship_2026_transport")
	var profile := line.get_reliability_profile()
	var passed := (
		profile.base_cargo_capacity > 40000.0
		and profile.effective_cargo_capacity > profile.base_cargo_capacity * 0.95
		and profile.armed_weapon_slots == 0
		and profile.logistics_supply_demand > 0.0
	)
	if passed:
		print(
			"  [PASS] cargo logistics capacity=",
			profile.effective_cargo_capacity,
			" supply_demand=",
			profile.logistics_supply_demand,
		)
	else:
		print(
			"  [FAIL] cargo logistics base=",
			profile.base_cargo_capacity,
			" effective=",
			profile.effective_cargo_capacity,
		)
	return passed


static func _test_armed_cargo_penalty(design_data: DesignDataLoader) -> bool:
	var line := ProductionLine.new(design_data, "armed_cargo_line")
	line.set_template("gmc_6x6_cargo_truck")
	var unarmed := line.get_reliability_profile()

	line.set_slot_module("MainWeapon", "bm13_katyusha_rack")
	var armed := line.get_reliability_profile()

	var passed := (
		unarmed.effective_cargo_capacity > armed.effective_cargo_capacity
		and armed.armed_weapon_slots == 1
		and armed.combat_soft_attack > unarmed.combat_soft_attack
		and armed.maintenance_index >= unarmed.maintenance_index
	)
	if passed:
		print(
			"  [PASS] armed truck cargo ",
			unarmed.effective_cargo_capacity,
			" -> ",
			armed.effective_cargo_capacity,
			" soft_atk=",
			armed.combat_soft_attack,
		)
	else:
		print(
			"  [FAIL] armed cargo penalty unarmed=",
			unarmed.effective_cargo_capacity,
			" armed=",
			armed.effective_cargo_capacity,
			" slots=",
			armed.armed_weapon_slots,
		)
	return passed


static func _test_armed_merchant_template(design_data: DesignDataLoader) -> bool:
	var line := ProductionLine.new(design_data, "merchant_line")
	line.set_template("armed_merchant_2026_armed")
	var armed := line.get_reliability_profile()

	line.set_template("container_ship_2026_transport")
	var transport := line.get_reliability_profile()

	var passed := (
		armed.armed_weapon_slots >= 2
		and armed.effective_cargo_capacity < armed.base_cargo_capacity * 0.5
		and armed.combat_anti_ship > 0.0
		and transport.effective_cargo_capacity > armed.effective_cargo_capacity * 2.0
	)
	if passed:
		print(
			"  [PASS] armed merchant cargo=",
			armed.effective_cargo_capacity,
			" vs container=",
			transport.effective_cargo_capacity,
		)
	else:
		print(
			"  [FAIL] armed merchant effective=",
			armed.effective_cargo_capacity,
			" slots=",
			armed.armed_weapon_slots,
		)
	return passed


static func _test_equipment_shortages() -> bool:
	var tracker := EquipmentShortageTracker.new()
	var required := {"rifle": 100, "m4_sherman_medium": 10}
	var stock := {"rifle": 80, "m4_sherman_medium": 10}
	var shortages := tracker.calculate_shortages(required, stock)
	if shortages.get("rifle", 0) != 20 or shortages.has("m4_sherman_medium"):
		print("  [FAIL] equipment shortage calculation: ", shortages)
		return false

	var readiness := tracker.get_readiness_from_shortages(shortages, required)
	if readiness <= 0.3 or readiness >= 1.0:
		print("  [FAIL] readiness penalty out of range: ", readiness)
		return false

	var pm := _get_production_manager()
	if pm == null:
		print("  [PASS] equipment shortages (tracker only; no autoload)")
		return true

	pm.set_national_equipment_stockpile({})
	pm.clear_unit_equipment_stock("test_div_1")
	pm.set_unit_equipment_stock("test_div_1", stock)
	var report: Dictionary = pm.get_shortage_report("test_div_1", required)
	if int(report.get("missing_equipment", {}).get("rifle", 0)) != 20:
		print("  [FAIL] ProductionManager shortage report: ", report)
		return false

	var modified: float = pm.apply_equipment_shortage_modifiers("test_div_1", 1.0, required)
	if absf(modified - readiness) > 0.001:
		print("  [FAIL] apply_equipment_shortage_modifiers: ", modified, " vs ", readiness)
		return false

	pm.clear_unit_equipment_stock("test_div_1")
	print("  [PASS] equipment shortages and readiness penalties")
	return true


static func _test_national_equipment_stockpile() -> bool:
	var pm := _get_production_manager()
	if pm == null:
		print("  [SKIP] national equipment stockpile (no autoload)")
		return true

	pm.set_national_equipment_stockpile({})
	pm.clear_unit_equipment_stock("stock_test_unit")

	pm.add_to_national_stockpile("m4_sherman_medium", 5)
	if pm.get_national_stockpile_amount("m4_sherman_medium") != 5:
		print("  [FAIL] add_to_national_stockpile")
		return false

	var taken: int = pm.take_from_national_stockpile("m4_sherman_medium", 2)
	if taken != 2 or pm.get_national_stockpile_amount("m4_sherman_medium") != 3:
		print("  [FAIL] take_from_national_stockpile: taken=", taken)
		return false

	pm.add_to_national_stockpile("rifle", 100)
	var required := {"rifle": 80, "m4_sherman_medium": 2}
	# Shortages use unit + national totals (50 + 30 = 80 available → 20 short of 100)
	pm.set_national_equipment_stockpile({"rifle": 30, "m4_sherman_medium": 3})
	pm.set_unit_equipment_stock("stock_test_unit", {"rifle": 50})
	var pre_shortages: Dictionary = pm.get_unit_shortages("stock_test_unit", {"rifle": 100})
	if int(pre_shortages.get("rifle", 0)) != 20:
		print("  [FAIL] national-aware shortages: ", pre_shortages)
		return false

	var fulfilled: Dictionary = pm.auto_reinforce_unit_from_stockpile("stock_test_unit", required)
	if int(fulfilled.get("rifle", 0)) != 80 or int(fulfilled.get("m4_sherman_medium", 0)) != 2:
		print("  [FAIL] auto_reinforce_unit_from_stockpile: ", fulfilled)
		return false

	var stock_report: Dictionary = pm.get_shortage_report("stock_test_unit", required)
	if not stock_report.get("missing_equipment", {}).is_empty():
		print("  [FAIL] unit should be fully reinforced: ", stock_report)
		return false

	pm.clear_unit_equipment_stock("stock_test_unit")
	pm.set_national_equipment_stockpile({})
	print("  [PASS] national equipment stockpile and unit reinforcement")
	return true


static func _test_infantry_equipment_stats(design_data: DesignDataLoader) -> bool:
	var garand := design_data.get_template("infantry_m1_garand")
	if garand == null:
		print("  [FAIL] infantry_m1_garand template missing")
		return false
	var stats := garand.get_infantry_stats()
	if float(stats.get("soft_attack", 0.0)) < 1.4:
		print("  [FAIL] garand soft_attack too low: ", stats)
		return false

	var tree := Engine.get_main_loop()
	var sm: Node = tree.root.get_node_or_null("/root/SupplyManager") if tree else null
	if tree == null or sm == null:
		print("  [PASS] infantry equipment stats (templates only)")
		return true

	if sm.has_method("get_division_template") or sm.get("division_templates") != null:
		sm.division_templates.load_all()
		var div: DivisionTemplate = sm.division_templates.get_division("us_infantry_div_ww2")
		if div == null:
			print("  [PASS] infantry equipment stats (no division template)")
			return true

		var agg := div.get_aggregated_infantry_stats(design_data)
		if float(agg.get("soft_attack", 0.0)) <= 0.0:
			print("  [FAIL] division aggregated infantry stats: ", agg)
			return false

		var german_mixed: DivisionTemplate = sm.division_templates.get_division(
			"german_infantry_division_1943_mixed",
		)
		if german_mixed == null:
			print("  [FAIL] german_infantry_division_1943_mixed missing")
			return false
		var mixed_stats: Dictionary = german_mixed.get_aggregated_infantry_stats(design_data)
		if int(mixed_stats.get("generation", mixed_stats.get("average_generation", 0))) < 2:
			print("  [FAIL] mixed division generation too low: ", mixed_stats)
			return false

		var pm := _get_production_manager()
		if pm != null:
			var via_pm: Dictionary = pm.get_division_infantry_stats("german_infantry_division_1943")
			if via_pm.is_empty():
				print("  [FAIL] ProductionManager.get_division_infantry_stats")
				return false

		print("  [PASS] infantry equipment type/generation stats")
		return true
	print("  [PASS] infantry equipment stats (no full SupplyManager in this context)")
	return true


static func _test_priority_reinforcement() -> bool:
	var pm := _get_production_manager()
	if pm == null:
		print("  [SKIP] priority reinforcement (no autoload)")
		return true

	pm.set_national_equipment_stockpile({"rifle": 50})
	pm.clear_unit_equipment_stock("priority_unit")
	pm.clear_unit_equipment_stock("normal_unit")
	pm.set_unit_priority_reinforcement("priority_unit", false)
	pm.set_unit_priority_reinforcement("normal_unit", false)

	var required := {"rifle": 40}
	var required_map := {
		"normal_unit": required,
		"priority_unit": required,
	}

	pm.set_unit_priority_reinforcement("priority_unit", true)
	pm.reinforce_all_units(required_map)

	var priority_stock: Dictionary = pm.get_unit_equipment_stock("priority_unit")
	var normal_stock: Dictionary = pm.get_unit_equipment_stock("normal_unit")
	if int(priority_stock.get("rifle", 0)) != 40:
		print("  [FAIL] priority unit should be fully reinforced: ", priority_stock)
		return false
	if int(normal_stock.get("rifle", 0)) != 10:
		print("  [FAIL] normal unit should get remainder: ", normal_stock)
		return false
	if not pm.is_unit_priority_reinforced("priority_unit"):
		print("  [FAIL] priority flag not set")
		return false

	pm.set_unit_priority_reinforcement("priority_unit", false)
	pm.set_national_equipment_stockpile({})
	pm.clear_unit_equipment_stock("priority_unit")
	pm.clear_unit_equipment_stock("normal_unit")
	print("  [PASS] priority reinforcement ordering")
	return true


static func _test_sustainment_equipment(design_data: DesignDataLoader) -> bool:
	design_data.load_sustainment_equipment()
	var basic := design_data.get_sustainment_equipment("basic_sustainment")
	if basic.is_empty():
		print("  [FAIL] basic_sustainment template missing")
		return false

	var tree2 := Engine.get_main_loop()
	var sm2: Node = tree2.root.get_node_or_null("/root/SupplyManager") if tree2 else null
	if tree2 == null or sm2 == null:
		print("  [PASS] sustainment equipment (data only)")
		return true

	sm2.division_templates.load_all()
	var us_div: DivisionTemplate = sm2.division_templates.get_division("us_infantry_division_1943")
	if us_div == null:
		print("  [FAIL] us_infantry_division_1943 missing")
		return false
	if us_div.get_sustainment_equipment_template() != "improved_sustainment":
		print("  [FAIL] sustainment template on division")
		return false
	var required := us_div.get_required_equipment(design_data)
	if not required.has("improved_sustainment"):
		print("  [FAIL] sustainment not in required equipment: ", required)
		return false
	if float(us_div.get_sustainment_consumption_multiplier(design_data)) >= 1.0:
		print("  [FAIL] improved sustainment should reduce consumption multiplier")
		return false

	var marine: DivisionTemplate = sm2.division_templates.get_division("us_marine_division_ww2")
	if marine == null:
		print("  [FAIL] us_marine_division_ww2 missing")
		return false
	var marine_required := marine.get_required_equipment(design_data)
	if not marine_required.has("marine_amphibious_sustainment"):
		print("  [FAIL] marine sustainment not required: ", marine_required)
		return false
	if marine.get_specialized_sustainment_demand() < 180.0:
		print("  [FAIL] marine division should add amphibious sustainment demand")
		return false

	var combat := marine.get_combined_combat_modifiers(design_data)
	if float(combat.get("supply_consumption", 0.0)) <= 0.0:
		print("  [FAIL] combined combat modifiers missing supply: ", combat)
		return false

	var full_stats := marine.get_final_combat_stats({}, design_data)
	if float(full_stats.get("readiness", 0.0)) < 1.0:
		print("  [FAIL] marine final readiness should be boosted: ", full_stats)
		return false

	var pm := _get_production_manager()
	if pm != null:
		pm.set_national_equipment_stockpile({
			"infantry_m1_garand": 5000,
			"marine_amphibious_sustainment": 5000,
		})
		pm.clear_unit_equipment_stock("marine_test")
		var marine_req := marine.get_required_equipment(design_data)
		var fulfilled: Dictionary = pm.auto_reinforce_unit_from_stockpile("marine_test", marine_req)
		if fulfilled.is_empty():
			print("  [FAIL] marine reinforcement fulfilled nothing: ", marine_req)
			return false
		var final_stats: Dictionary = pm.get_division_final_combat_stats(
			"us_marine_division_ww2",
			"marine_test",
		)
		if not bool(final_stats.get("has_shortages", false)):
			print("  [FAIL] marine_test should still have shortages with partial stockpile")
			return false
		if float(final_stats.get("readiness", 1.0)) >= float(full_stats.get("readiness", 1.0)):
			print("  [FAIL] shortages should reduce readiness: ", final_stats)
			return false

		pm.add_to_national_stockpile("infantry_m1_garand", 20000)
		pm.add_to_national_stockpile("marine_amphibious_sustainment", 20000)
		pm.auto_reinforce_unit_from_stockpile("marine_test", marine_req)
		var stocked_stats: Dictionary = pm.get_division_final_combat_stats(
			"us_marine_division_ww2",
			"marine_test",
		)
		if bool(stocked_stats.get("has_shortages", true)):
			print("  [FAIL] marine_test should be fully stocked: ", stocked_stats)
			return false

		pm.clear_unit_equipment_stock("marine_test")
		pm.set_national_equipment_stockpile({})

	print("  [PASS] sustainment equipment templates and division support")
	return true


static func _test_combat_resolver(design_data: DesignDataLoader) -> bool:
	var tree5 := Engine.get_main_loop()
	var gd: Node = tree5.root.get_node_or_null("/root/GameData") if tree5 else null
	if tree5 == null or gd == null or (gd.get("design_data") == null):
		print("  [SKIP] CombatResolver (SupplyManager / GameData not available)")
		return true

	var tree3 := Engine.get_main_loop()
	var sm3: Node = tree3.root.get_node_or_null("/root/SupplyManager") if tree3 else null
	if sm3:
		sm3.division_templates.load_all()
	var resolver := CombatResolver.new()
	var power: Dictionary = resolver.get_effective_combat_power("us_marine_division_ww2")

	if power.is_empty():
		resolver.free()
		print("  [FAIL] CombatResolver marine effective power empty")
		return false
	if float(power.get("soft_attack", 0.0)) <= 0.0:
		resolver.free()
		print("  [FAIL] CombatResolver soft_attack: ", power)
		return false
	if float(power.get("readiness", 0.0)) < 1.0:
		resolver.free()
		print("  [FAIL] marine effective readiness should be boosted: ", power)
		return false

	var pm := _get_production_manager()
	if pm != null:
		pm.set_national_equipment_stockpile({
			"infantry_m1_garand": 50000,
			"marine_amphibious_sustainment": 50000,
		})
		pm.clear_unit_equipment_stock("combat_resolver_test")
		var marine_div: DivisionTemplate = sm3.division_templates.get_division(
			"us_marine_division_ww2",
		) if sm3 else null
		if marine_div:
			pm.auto_reinforce_unit_from_stockpile(
				"combat_resolver_test",
				marine_div.get_required_equipment(design_data),
			)
		var stocked: Dictionary = resolver.get_effective_combat_power(
			"us_marine_division_ww2",
			"combat_resolver_test",
		)
		if bool(stocked.get("has_shortages", true)):
			resolver.free()
			pm.clear_unit_equipment_stock("combat_resolver_test")
			pm.set_national_equipment_stockpile({})
			print("  [FAIL] stocked marine should have no shortages: ", stocked)
			return false
		pm.clear_unit_equipment_stock("combat_resolver_test")
		pm.set_national_equipment_stockpile({})

	if Engine.get_main_loop() != null and _get_leader_manager() != null:
		var rommel: Leader = LeaderManager.get_leader("ger_rommel")
		if rommel != null:
			var base_power: Dictionary = resolver.get_effective_combat_power(
				"german_infantry_division_1943",
			)
			LeaderManager.assign_leader_to_army("ger_rommel", "panzer_army_africa_test")
			var led_power: Dictionary = resolver.get_effective_combat_power(
				"german_infantry_division_1943",
				"",
				"panzer_army_africa_test",
			)
			var plains_power: Dictionary = resolver.get_effective_combat_power(
				"german_infantry_division_1943",
				"",
				"panzer_army_africa_test",
				"plains",
			)
			var desert_power: Dictionary = resolver.get_effective_combat_power(
				"german_infantry_division_1943",
				"",
				"panzer_army_africa_test",
				"desert",
				-1,  # province_id (optional for dev lookup)
				5,   # province_dev example (Phase 1: real dev now used for org/readiness)
				3,   # province_infra
			)
			rommel.assigned_army_id = ""
			if str(led_power.get("leader_name", "")) != "Erwin Rommel":
				resolver.free()
				print("  [FAIL] leader name in combat power: ", led_power)
				return false
			if float(led_power.get("leader_attack_bonus", 0.0)) <= 0.0:
				resolver.free()
				print("  [FAIL] Rommel attack bonus missing: ", led_power)
				return false
			if float(led_power.get("soft_attack", 0.0)) <= float(base_power.get("soft_attack", 0.0)):
				resolver.free()
				print(
					"  [FAIL] leader should boost soft_attack: base=",
					base_power.get("soft_attack"),
					" led=",
					led_power.get("soft_attack"),
				)
				return false
			if float(desert_power.get("terrain_bonus_applied", 0.0)) <= 0.0:
				resolver.free()
				print("  [FAIL] Rommel desert terrain bonus: ", desert_power)
				return false
			if float(desert_power.get("soft_attack", 0.0)) <= float(plains_power.get("soft_attack", 0.0)):
				resolver.free()
				print(
					"  [FAIL] desert should beat plains for Rommel: plains=",
					plains_power.get("soft_attack"),
					" desert=",
					desert_power.get("soft_attack"),
				)
				return false

			var rommel_xp_before := rommel.experience
			LeaderManager.assign_leader_to_army("ger_rommel", "panzer_army_africa_test")
			resolver.resolve_combat_experience("panzer_army_africa_test", "", 1.0)
			rommel.assigned_army_id = ""
			if rommel.experience <= rommel_xp_before:
				resolver.free()
				print("  [FAIL] combat XP not awarded: ", rommel.experience)
				return false

		var path_leader := Leader.new()
		path_leader.leader_id = "usa_path_combat_test"
		path_leader.name = "Path Combat Test"
		path_leader.country_tag = "USA"
		LeaderManager.register_leader(path_leader)
		LeaderManager.assign_leader_to_army("usa_path_combat_test", "path_combat_army_test")
		path_leader.clear_training_path()
		var power_no_path: Dictionary = resolver.get_effective_combat_power(
			"us_marine_division_ww2",
			"",
			"path_combat_army_test",
		)
		path_leader.set_training_path("school_of_maneuver", 3)
		var power_with_path: Dictionary = resolver.get_effective_combat_power(
			"us_marine_division_ww2",
			"",
			"path_combat_army_test",
		)
		var path_mods: Dictionary = LeaderManager.get_leader_training_path_combat_modifiers(
			"usa_path_combat_test",
		)
		LeaderManager.leaders.erase("usa_path_combat_test")
		if path_mods.is_empty():
			resolver.free()
			print("  [FAIL] maneuver school combat modifiers empty at level 3")
			return false
		if float(power_with_path.get("training_path_soft_bonus", 0.0)) <= 0.0:
			resolver.free()
			print("  [FAIL] training path soft bonus missing: ", power_with_path)
			return false
		if float(power_with_path.get("soft_attack", 0.0)) <= float(
			power_no_path.get("soft_attack", 0.0)
		):
			resolver.free()
			print(
				"  [FAIL] training path should boost soft_attack: no_path=",
				power_no_path.get("soft_attack"),
				" with_path=",
				power_with_path.get("soft_attack"),
			)
			return false

	resolver.free()
	print("  [PASS] CombatResolver effective combat power")
	return true


static func _test_phase_combat_resolution() -> bool:
	var resolver := CombatResolver.new()
	var phases: Array[String] = []
	resolver.combat_phase_advanced.connect(
		func(phase: String, _data: Dictionary) -> void:
			phases.append(phase)
	)

	var battle := Province.new()
	battle.id = 99999
	battle.name = "Phase Combat Test"
	battle.owner_tag = "YUG"
	battle.controller_tag = "YUG"
	battle.terrain = "plains"
	battle.infrastructure = 2
	battle.development_level = 3

	var attacker := Formation.new()
	attacker.formation_id = "german_infantry_division_1943"
	attacker.country_tag = "GER"
	attacker.organization = 1.0
	attacker.readiness = 1.0
	attacker.strength = 1.0

	var defender := Formation.new()
	defender.formation_id = "german_infantry_division_1943_mixed"
	defender.country_tag = "YUG"
	defender.organization = 1.0
	defender.readiness = 1.0
	defender.strength = 1.0

	var result: Dictionary = resolver.resolve_combat(attacker, defender, battle)
	resolver.free()

	var expected := [
		CombatResolver.PHASE_POSITIONING,
		CombatResolver.PHASE_ENGAGEMENT,
		CombatResolver.PHASE_ATTRITION,
		CombatResolver.PHASE_RESOLUTION,
	]
	for phase_name in expected:
		if phase_name not in phases:
			print("  [FAIL] phased combat missing phase ", phase_name, " got ", phases)
			return false
	if not result.has("province_control_change"):
		print("  [FAIL] phased combat result missing province_control_change: ", result)
		return false
	if phases.size() != expected.size():
		print("  [FAIL] phased combat expected 4 phases, got ", phases.size(), ": ", phases)
		return false

	print("  [PASS] phased combat resolution (4 phases + capture flag)")
	return true


static func _test_battle_manager_assault() -> bool:
	if typeof(BattleManager) == TYPE_NIL or typeof(MapManager) == TYPE_NIL:
		print("  [SKIP] battle manager assault (autoloads unavailable)")
		return true

	var from_pid := 1
	var to_pid := -1
	var attacker_tag := "GER"
	var defender_tag := "FRA"

	var from_prov: Province = MapManager.get_province(from_pid)
	if from_prov == null:
		print("  [SKIP] battle manager assault (province 1 missing)")
		return true

	for nid in MapManager.get_adjacent_provinces(from_pid):
		var neighbor: Province = MapManager.get_province(int(nid))
		if neighbor == null or neighbor.owner_tag.is_empty():
			continue
		if neighbor.owner_tag.strip_edges().to_upper() != attacker_tag:
			to_pid = int(nid)
			defender_tag = neighbor.owner_tag.strip_edges().to_upper()
			break

	if to_pid < 0:
		print("  [SKIP] battle manager assault (no adjacent hostile province from pid 1)")
		return true

	MapManager.update_province_owner(from_pid, attacker_tag, attacker_tag, true)
	MapManager.update_province_owner(to_pid, defender_tag, defender_tag, true)

	var tree4 := Engine.get_main_loop()
	var sm4: Node = tree4.root.get_node_or_null("/root/SupplyManager") if tree4 else null
	if sm4 != null:
		sm4.move_formation_to_province("german_infantry_division_1943", from_pid, attacker_tag)

	var assault: Dictionary = BattleManager.execute_province_assault(attacker_tag, to_pid, from_pid)
	if not bool(assault.get("success", false)):
		print("  [FAIL] battle manager assault: ", assault.get("reason", "unknown"))
		return false

	var result: Dictionary = assault.get("result", {}) as Dictionary
	if not result.has("winner"):
		print("  [FAIL] battle manager assault missing winner: ", result)
		return false

	print(
		"  [PASS] battle manager province assault (winner=%s capture=%s)"
		% [str(result.get("winner", "")), str(result.get("province_control_change", false))]
	)
	return true


static func _test_combat_width() -> bool:
	var calculator := CombatWidthCalculator.new()
	calculator.ensure_rules_loaded()
	if calculator.rules.is_empty():
		calculator.free()
		print("  [FAIL] combat width rules not loaded")
		return false

	var plains_width := calculator.get_combat_width(2, "plains")
	var jungle_width := calculator.get_combat_width(2, "jungle")
	if plains_width <= 0.0 or jungle_width >= plains_width:
		calculator.free()
		print("  [FAIL] combat width terrain modifiers: plains=", plains_width, " jungle=", jungle_width)
		return false

	var effective := calculator.get_effective_combat_width(2, 4, "mountain")
	if effective <= 0.0:
		calculator.free()
		print("  [FAIL] effective combat width: ", effective)
		return false

	var resolver := CombatResolver.new()
	var battle_width := resolver.get_combat_width_for_battle(2, 3, "plains")
	resolver.free()
	calculator.free()
	if battle_width <= 0.0:
		print("  [FAIL] CombatResolver battle width: ", battle_width)
		return false

	print("  [PASS] combat width (plains=", plains_width, " effective=", effective, ")")
	return true


static func _test_formation_spawner() -> bool:
	var lm := _get_leader_manager()
	if lm == null:
		print("  [SKIP] formation spawner (LeaderManager autoload not available)")
		return true

	lm.clear_all_formations()

	var spawner := FormationSpawner.new()
	spawner.spawn_test_formations_for_country("GER", 6)

	var ger_available: Array[Dictionary] = LeaderManager.get_available_formations("GER")
	if ger_available.size() < 6:
		print("  [FAIL] expected at least 6 GER formations, got ", ger_available.size())
		return false

	var general := Leader.new()
	general.leader_id = "ger_test_general"
	general.name = "Test General"
	general.country_tag = "GER"
	general.leader_type = "general"
	LeaderManager.register_leader(general)

	var division_id := ""
	for entry in ger_available:
		if str(entry.get("type", "")) == Formation.TYPE_DIVISION:
			division_id = str(entry.get("formation_id", ""))
			break

	if division_id.is_empty():
		print("  [FAIL] no division formation found for GER")
		LeaderManager.leaders.erase("ger_test_general")
		return false

	if not LeaderManager.assign_leader_to_formation("ger_test_general", division_id):
		print("  [FAIL] assign general to division")
		LeaderManager.leaders.erase("ger_test_general")
		return false

	var admiral := Leader.new()
	admiral.leader_id = "ger_test_admiral"
	admiral.name = "Test Admiral"
	admiral.country_tag = "GER"
	admiral.leader_type = "admiral"
	LeaderManager.register_leader(admiral)

	if LeaderManager.assign_leader_to_formation("ger_test_admiral", division_id):
		print("  [FAIL] admiral should not lead a land division")
		LeaderManager.leaders.erase("ger_test_admiral")
		LeaderManager.unassign_leader_from_army("ger_test_general")
		LeaderManager.leaders.erase("ger_test_general")
		return false

	LeaderManager.unassign_leader_from_army("ger_test_general")
	LeaderManager.leaders.erase("ger_test_general")
	LeaderManager.leaders.erase("ger_test_admiral")

	print("  [PASS] formation spawner and leader type validation")
	return true


static func _test_leader_manager() -> bool:
	var lm := _get_leader_manager()
	if lm == null:
		print("  [SKIP] LeaderManager autoload not available")
		return true

	var patton := Leader.new()
	patton.leader_id = "usa_patton_test"
	patton.name = "George S. Patton"
	patton.country_tag = "USA"
	patton.leader_type = "general"
	patton.attack_skill = 4
	patton.defense_skill = 2
	patton.organization_skill = 3
	patton.traits = ["aggressive", "logistics_wizard"]

	LeaderManager.register_leader(patton)
	if not LeaderManager.assign_leader_to_army("usa_patton_test", "third_army_test"):
		print("  [FAIL] could not assign leader to army")
		return false
	if LeaderManager.get_leader_for_army("third_army_test") != patton:
		print("  [FAIL] army leader lookup")
		return false

	var marshall := Leader.new()
	marshall.leader_id = "usa_marshall_test"
	marshall.name = "George C. Marshall"
	marshall.country_tag = "USA"
	marshall.leader_type = "general"
	marshall.attack_skill = 6
	marshall.defense_skill = 6
	marshall.planning_skill = 7
	marshall.initiative_skill = 5
	LeaderManager.register_leader(marshall)
	LeaderManager.pending_leader_replacements.clear()
	LeaderManager.pending_retirements.append("usa_patton_test")
	if not LeaderManager.resolve_retirement("usa_patton_test", true, false):
		print("  [FAIL] resolve_retirement for replacement test")
		return false
	var formation_request: Dictionary = {}
	for req in LeaderManager.get_pending_leader_replacements("USA"):
		if str(req.get("target_id", "")) == "third_army_test":
			formation_request = req
	if formation_request.is_empty():
		print("  [FAIL] retiring field commander should enqueue formation replacement")
		return false
	var replacement_request_id := str(formation_request.get("request_id", ""))
	if replacement_request_id.is_empty():
		print("  [FAIL] formation replacement missing request_id")
		return false
	if not LeaderManager.resolve_leader_replacement(replacement_request_id, "usa_marshall_test"):
		print("  [FAIL] resolve_leader_replacement for Third Army")
		return false
	if LeaderManager.get_leader_for_army("third_army_test") != marshall:
		print("  [FAIL] replacement leader should command Third Army")
		return false
	LeaderManager.pending_leader_replacements.clear()
	LeaderManager.leaders.erase("usa_marshall_test")

	# AI countries auto-resolve vacancies without leaving player pending decisions.
	LeaderManager.set_player_country_tag("USA")
	LeaderManager.register_division_formations_for_country("GER")
	var ger_formations: Variant = LeaderManager.get_available_formations("GER")
	if ger_formations.is_empty():
		print("  [FAIL] need GER formation for AI replacement test")
		return false
	var ger_formation_id := str(ger_formations[0].get("formation_id", ""))
	var ger_vacancy := Leader.new()
	ger_vacancy.leader_id = "ger_auto_repl_test"
	ger_vacancy.name = "GER Auto Repl"
	ger_vacancy.country_tag = "GER"
	ger_vacancy.leader_type = "general"
	LeaderManager.register_leader(ger_vacancy)
	if not LeaderManager.assign_leader_to_army("ger_auto_repl_test", ger_formation_id):
		print("  [FAIL] could not assign GER leader for AI replacement test")
		return false
	var ai_pending_before: Variant = LeaderManager.get_pending_replacement_count("GER")
	LeaderManager.pending_retirements.append("ger_auto_repl_test")
	if not LeaderManager.resolve_retirement("ger_auto_repl_test", true, false):
		print("  [FAIL] GER resolve_retirement for AI replacement test")
		return false
	if LeaderManager.get_pending_replacement_count("GER") > ai_pending_before:
		print("  [FAIL] AI country should not keep pending replacement requests")
		return false
	LeaderManager.pending_leader_replacements.clear()

	# Captured commander: formation still exists leaderless → enqueue replacement.
	LeaderManager.set_player_country_tag("USA")
	var got_capture_vacancy := false
	for _attempt in 60:
		var pow_leader := Leader.new()
		pow_leader.leader_id = "usa_pow_test"
		pow_leader.name = "POW Candidate"
		pow_leader.country_tag = "USA"
		pow_leader.leader_type = "general"
		LeaderManager.register_leader(pow_leader)
		if not LeaderManager.assign_leader_to_army("usa_pow_test", "third_army_test"):
			print("  [FAIL] assign leader for formation_destroyed capture test")
			return false
		LeaderManager.pending_leader_replacements.clear()
		var captured_result: Variant = LeaderManager.handle_formation_destroyed("third_army_test")
		if str(captured_result.get("type", "")) == "captured":
			got_capture_vacancy = LeaderManager.get_pending_replacement_count("USA") >= 1
			break
		LeaderManager.leaders.erase("usa_pow_test")
	if not got_capture_vacancy:
		print("  [FAIL] captured commander should leave Third Army vacancy for player")
		return false
	LeaderManager.pending_leader_replacements.clear()
	LeaderManager.leaders.erase("usa_pow_test")

	patton = Leader.new()
	patton.leader_id = "usa_patton_test"
	patton.name = "George S. Patton"
	patton.country_tag = "USA"
	patton.leader_type = "general"
	patton.attack_skill = 4
	patton.defense_skill = 2
	patton.organization_skill = 3
	patton.traits = ["aggressive", "logistics_wizard"]
	LeaderManager.register_leader(patton)
	if not LeaderManager.assign_leader_to_army("usa_patton_test", "third_army_test"):
		print("  [FAIL] could not reassign Patton after replacement test")
		return false

	if patton.get_attack_modifier() <= 0.07:
		print("  [FAIL] leader attack modifier too low: ", patton.get_attack_modifier())
		return false
	var assign_check: Dictionary = LeaderManager.can_assign_national_position(
		"USA",
		LeaderManager.POSITION_CHIEF_OF_ARMY,
		"usa_patton_test",
	)
	if not bool(assign_check.get("can_assign", false)):
		print("  [FAIL] can_assign_national_position: ", assign_check)
		return false
	if float((assign_check.get("cost", {}) as Dictionary).get("stability", 0.0)) <= 0.0:
		print("  [FAIL] national position cost preview missing stability")
		return false

	if not LeaderManager.set_country_position(
		"USA",
		LeaderManager.POSITION_CHIEF_OF_ARMY,
		"usa_patton_test",
		false,
	):
		print("  [FAIL] set chief of army position")
		return false
	if LeaderManager.get_country_position_leader("USA", LeaderManager.POSITION_CHIEF_OF_ARMY) != patton:
		print("  [FAIL] country position leader lookup")
		return false

	var bonuses: Dictionary = LeaderManager.get_national_bonuses("USA")
	if float(bonuses.get("army_attack", 0.0)) <= 0.0:
		print("  [FAIL] national bonuses from chief of army: ", bonuses)
		return false

	var rommel: Leader = LeaderManager.get_leader("ger_rommel")
	if rommel == null or not rommel.has_trait("desert_fox"):
		print("  [FAIL] historical leader Rommel not loaded")
		return false
	if rommel.get_trait_level("desert_fox") < 3:
		print("  [FAIL] Rommel should have Desert Fox III: ", rommel.get_trait_level("desert_fox"))
		return false
	if rommel.get_attack_modifier() <= 0.0:
		print("  [FAIL] Rommel attack modifier: ", rommel.get_attack_modifier())
		return false

	var doenitz: Leader = LeaderManager.get_leader("ger_doenitz")
	if doenitz == null or not doenitz.has_trait("sea_wolf"):
		print("  [FAIL] historical leader Dönitz not loaded")
		return false
	if doenitz.leader_type != "admiral":
		print("  [FAIL] Dönitz should be admiral: ", doenitz.leader_type)
		return false

	var manstein := Leader.new()
	manstein.leader_id = "ger_manstein_test"
	manstein.name = "Erich von Manstein"
	manstein.country_tag = "GER"
	manstein.leader_type = "general"
	manstein.attack_skill = 8
	manstein.defense_skill = 7
	manstein.add_trait("arctic_bear", 1)
	LeaderManager.register_leader(manstein)
	if not manstein.has_trait("arctic_bear"):
		print("  [FAIL] Manstein arctic_bear trait")
		return false
	if manstein.get_defense_modifier() <= 0.1:
		print("  [FAIL] arctic_bear defense bonus: ", manstein.get_defense_modifier())
		return false
	LeaderManager.leaders.erase("ger_manstein_test")

	var generated: Leader = LeaderManager.create_and_register_new_leader("FRA", "general")
	if generated == null or generated.country_tag != "FRA":
		print("  [FAIL] generated leader: ", generated)
		return false
	if generated.attack_skill < 1 or generated.attack_skill > 6:
		print("  [FAIL] generated attack skill out of range: ", generated.attack_skill)
		LeaderManager.leaders.erase(generated.leader_id)
		return false
	LeaderManager.leaders.erase(generated.leader_id)

	var exp_before := patton.experience
	var total_before := patton.total_experience_earned
	LeaderManager.award_xp_to_leader("usa_patton_test", 50, "combat")
	if patton.experience != exp_before + 50 or patton.total_experience_earned != total_before + 50:
		print(
			"  [FAIL] award_xp_to_leader: exp=",
			patton.experience,
			" total=",
			patton.total_experience_earned,
		)
		return false
	if patton.battles_fought < 1 or patton.last_xp_source != "combat":
		print("  [FAIL] combat XP should count as battle: ", patton.battles_fought, patton.last_xp_source)
		return false
	if not patton.spend_experience(10) or patton.get_experience() != exp_before + 40:
		print("  [FAIL] spend_experience")
		return false

	var combat_xp: Variant = LeaderManager.calculate_combat_xp_from_result({"is_major_victory": true})
	if combat_xp < 12 + 60:
		print("  [FAIL] major victory combat XP: ", combat_xp)
		return false
	LeaderManager.award_combat_xp("usa_patton_test", {"is_major_victory": true, "success": true})
	if patton.battles_fought < 2:
		print("  [FAIL] award_combat_xp should increment battles_fought")
		return false

	patton.add_trait_unchecked("bold", 1)
	if LeaderManager.get_trait_level_cost(1) != 150:
		print("  [FAIL] get_trait_level_cost(1) should be 150")
		return false
	var bold_cost: Variant = LeaderManager.get_trait_level_up_cost(patton, "bold")
	if bold_cost != 150:
		print("  [FAIL] trait level-up cost at level 1 should be 150: ", bold_cost)
		return false
	if LeaderManager.can_level_trait("usa_patton_test", "bold"):
		print("  [FAIL] can_level_trait should be false without XP")
		return false
	patton.experience = bold_cost + 350
	if not LeaderManager.can_level_trait("usa_patton_test", "bold"):
		print("  [FAIL] can_level_trait should be true with enough XP")
		return false
	if not LeaderManager.level_trait("usa_patton_test", "bold"):
		print("  [FAIL] level_trait")
		return false
	if patton.get_trait_level("bold") < 2:
		print("  [FAIL] bold trait should be level 2: ", patton.get_trait_level("bold"))
		return false
	var spend_result: Dictionary = LeaderManager.spend_xp_on_trait("usa_patton_test", "bold")
	if not bool(spend_result.get("success", false)):
		print("  [FAIL] spend_xp_on_trait level 2→3: ", spend_result)
		return false
	if patton.get_trait_level("bold") < 3:
		print("  [FAIL] bold trait should be level 3: ", patton.get_trait_level("bold"))
		return false

	patton.attack_skill = 9
	if not LeaderManager.promote_leader("usa_patton_test"):
		print("  [FAIL] promote_leader")
		return false
	if patton.attack_skill != 10:
		print("  [FAIL] promote should cap at 10: ", patton.attack_skill)
		return false

	if LeaderManager.get_training_path_definition("school_of_maneuver").is_empty():
		print("  [FAIL] doctrine training path definitions not loaded")
		return false
	if LeaderManager.training_path_definitions.size() < 14:
		print(
			"  [FAIL] expected at least 14 training paths, got ",
			LeaderManager.training_path_definitions.size(),
		)
		return false
	patton.clear_training_path()
	patton.experience = 500
	LeaderManager.set_country_military_doctrine("USA", "mobile_warfare", true)
	if LeaderManager.can_invest_training_path("usa_patton_test", "school_of_maneuver"):
		pass
	else:
		print("  [FAIL] should be able to invest with doctrine + XP")
		return false
	if not LeaderManager.invest_xp_in_training_path("usa_patton_test", "school_of_maneuver"):
		print("  [FAIL] invest training path level 1")
		return false
	if patton.training_path_id != "school_of_maneuver" or patton.training_path_level != 1:
		print(
			"  [FAIL] training path after invest: ",
			patton.training_path_id,
			patton.training_path_level,
		)
		return false
	var path_effects: Dictionary = LeaderManager.get_leader_training_path_effects(patton)
	if int(path_effects.get("initiative", 0)) < 1:
		print("  [FAIL] maneuver school level 1 initiative: ", path_effects)
		return false
	if not LeaderManager.invest_xp_in_training_path("usa_patton_test", "school_of_maneuver"):
		print("  [FAIL] invest training path level 2")
		return false
	LeaderManager.set_country_military_doctrine("USA", "mass_assault", true)
	var switch_cost: Variant = LeaderManager.get_training_path_switch_cost(
		"usa_patton_test",
		"school_of_layered_defense",
	)
	if switch_cost != 700:
		print("  [FAIL] training path switch cost at level 2 (expected 700): ", switch_cost)
		return false
	patton.experience = 600
	if LeaderManager.can_switch_training_path("usa_patton_test", "school_of_layered_defense"):
		print("  [FAIL] switch should fail without enough XP (need ", switch_cost, ")")
		return false
	patton.experience = switch_cost + 200
	if not LeaderManager.switch_training_path("usa_patton_test", "school_of_layered_defense"):
		print("  [FAIL] switch training path")
		return false
	if (
		patton.training_path_id != "school_of_layered_defense"
		or patton.training_path_level != 1
	):
		print(
			"  [FAIL] after switch path=",
			patton.training_path_id,
			" level=",
			patton.training_path_level,
		)
		return false
	if patton.previous_training_path_id != "school_of_maneuver":
		print("  [FAIL] previous_training_path_id after switch: ", patton.previous_training_path_id)
		return false
	var available: Array = LeaderManager.get_available_training_paths_for_leader("usa_patton_test")
	if available.is_empty():
		print("  [FAIL] available training paths empty")
		return false
	var doctrine_paths: Array = LeaderManager.get_available_training_paths("usa_patton_test")
	if doctrine_paths.size() < 2:
		print("  [FAIL] get_available_training_paths should list unlocked doctrines: ", doctrine_paths)
		return false
	LeaderManager.set_country_military_doctrine("USA", "mobile_warfare", false)
	LeaderManager.set_country_military_doctrine("USA", "mass_assault", false)

	patton.set_training_path("school_of_layered_defense", 2)
	var supply_mods: Dictionary = LeaderManager.get_leader_training_path_supply_modifiers(
		"usa_patton_test",
	)
	if not supply_mods.has("supply_consumption"):
		print("  [FAIL] layered defense should reduce supply consumption: ", supply_mods)
		return false
	var base_stats := {"supply_consumption": 1.0, "readiness": 1.0}
	var boosted: Dictionary = LeaderManager.apply_training_path_supply_to_stats(
		base_stats,
		"usa_patton_test",
	)
	if float(boosted.get("supply_consumption", 1.0)) >= 1.0:
		print("  [FAIL] supply path should lower consumption: ", boosted)
		return false

	var daily_supply: Variant = LeaderManager.apply_supply_consumption_for_leader(10.0, "usa_patton_test")
	if daily_supply >= 10.0:
		print("  [FAIL] daily supply should be reduced by layered defense: ", daily_supply)
		return false
	if daily_supply < 0.1:
		print("  [FAIL] daily supply floor violated: ", daily_supply)
		return false

	patton.set_training_path("logistics_mastery_track", 3)
	var logistics_mods: Variant = LeaderManager.get_leader_training_path_supply_modifiers("usa_patton_test")
	if not logistics_mods.has("attrition_reduction"):
		print("  [FAIL] logistics track should grant attrition_reduction: ", logistics_mods)
		return false
	var reduced_attrition: Variant = LeaderManager.apply_attrition_for_leader(100.0, "usa_patton_test")
	if reduced_attrition >= 100.0:
		print("  [FAIL] attrition_reduction should lower attrition: ", reduced_attrition)
		return false
	if LeaderManager.apply_reinforcement_rate_for_leader(1.0, "usa_patton_test") <= 1.0:
		print("  [FAIL] reinforcement_speed should boost rate: ", logistics_mods)
		return false

	var suitability: Variant = LeaderManager.get_officer_training_suitability("usa_patton_test")
	if suitability < 40:
		print("  [FAIL] Patton should be a viable training mentor: ", suitability)
		return false
	var base_suitability: float = float(suitability)
	LeaderManager.try_add_trait_to_leader(patton, "reckless", 1)
	if LeaderManager.get_officer_training_suitability("usa_patton_test") >= base_suitability:
		print("  [FAIL] reckless trait should lower training suitability")
		return false

	if not LeaderManager.assign_leader_to_officer_training("usa_patton_test"):
		print("  [FAIL] assign_leader_to_officer_training")
		return false
	if LeaderManager.get_officer_training_leader("USA") != patton:
		print("  [FAIL] get_officer_training_leader should return Patton")
		return false
	var usa_positions: Dictionary = LeaderManager.country_positions.get("USA", {}) as Dictionary
	if str(usa_positions.get(LeaderManager.POSITION_OFFICER_TRAINING, "")) != "usa_patton_test":
		print("  [FAIL] officer training not stored in national positions")
		return false
	if not patton.is_assigned_to_training() or patton.duty_post != "training":
		print("  [FAIL] officer training flags not set on mentor")
		return false
	if patton.is_available_for_command():
		print("  [FAIL] mentor should not be available for field command while training")
		return false

	var cadet: Variant = LeaderManager.generate_and_register_leader_from_training("USA")
	if cadet == null:
		print("  [FAIL] generate_and_register_leader_from_training")
		return false
	if cadet.leader_type not in ["general", "admiral", "air_marshal", "field_marshal"]:
		print("  [FAIL] cadet leader_type invalid: ", cadet.leader_type)
		return false
	if cadet.name.contains("Cadet") or cadet.name.contains("Commander"):
		print("  [FAIL] cadet should use roster-style name: ", cadet.name)
		return false
	if cadet.experience < 30:
		print("  [FAIL] mentored cadet should receive baseline XP: ", cadet.experience)
		return false

	LeaderManager.officer_training_quality["USA"] = 75.0
	var quality_cadet: Variant = LeaderManager.generate_new_leader_from_training("USA")
	if quality_cadet.experience < 85:
		print("  [FAIL] high training quality should boost cadet XP: ", quality_cadet.experience)
		return false
	if quality_cadet.planning_skill < 7:
		print("  [FAIL] high training quality should boost planning skill: ", quality_cadet.planning_skill)
		return false

	LeaderManager.advance_officer_training_progress("USA")
	if LeaderManager.get_officer_training_quality("USA") <= 0.0:
		print("  [FAIL] advance_officer_training_progress should increase quality")
		return false

	LeaderManager.officer_training_quality["USA"] = 74.0
	LeaderManager.advance_officer_training_progress("USA")
	if LeaderManager.get_officer_training_quality("USA") < 75.0:
		print("  [FAIL] training should reach excellent threshold")
		return false

	LeaderManager.try_add_trait_to_leader(patton, "reckless", 1)
	var flaw_cadet: Variant = LeaderManager.generate_new_leader_from_training("USA")
	var forced_flaw := false
	for _i in 20:
		if flaw_cadet != null and flaw_cadet.has_trait("reckless"):
			forced_flaw = true
			break
		flaw_cadet = LeaderManager.generate_new_leader_from_training("USA")
	if not forced_flaw:
		print("  [FAIL] officer training should sometimes inherit mentor flaws")
		return false
	LeaderManager.unassign_officer_training_leader()
	if patton.is_in_officer_training:
		print("  [FAIL] unassign_officer_training_leader")
		return false
	LeaderManager.leaders.erase(cadet.leader_id)

	LeaderManager.leaders.erase("usa_patton_test")
	if LeaderManager.country_positions.has("USA"):
		(LeaderManager.country_positions["USA"] as Dictionary).erase(LeaderManager.POSITION_CHIEF_OF_ARMY)

	# Skip 1918/2026/1936 full roster reloads unless explicitly requested (slow on F5; OOM in headless CI).
	if not _run_full_leader_roster_tests():
		print(
			"  [PASS] LeaderManager core tests (skipping 1918/2026/1936 roster reload; set %s=1 for full suite)"
			% ENV_FULL_LEADER_ROSTER_TESTS
		)
		return true

	var loaded_1918: Variant = LeaderManager.load_leaders_for_scenario("1918", 1918)
	if loaded_1918 < 60:
		print("  [FAIL] 1918 historical leaders load count: ", loaded_1918)
		return false
	if LeaderManager.get_leader("ger_rommel") != null:
		print("  [FAIL] Rommel must not be active in 1918 scenario year")
		return false
	if not LeaderManager.leader_pool.has("irn_reza"):
		print("  [FAIL] Reza Khan (start 1921) should be in 1918 leader pool")
		return false
	var hindenburg: Leader = LeaderManager.get_leader("ger_hindenburg")
	if hindenburg == null or hindenburg.get_trait_level("methodical") < 2:
		print("  [FAIL] 1918 Hindenburg not loaded with traits")
		return false
	var pershing: Leader = LeaderManager.get_leader("usa_pershing")
	if pershing == null:
		print("  [FAIL] 1918 Pershing not loaded")
		return false

	var loaded_2026: Variant = LeaderManager.load_leaders_for_scenario("2026", 2026)
	if loaded_2026 < 80:
		print("  [FAIL] 2026 scenario leaders load count: ", loaded_2026)
		return false
	if LeaderManager.get_leader("usa_patton") != null:
		print("  [FAIL] Patton must not appear in 2026 scenario roster")
		return false
	if LeaderManager.get_leader("ger_rommel") != null:
		print("  [FAIL] Rommel must not appear in 2026 scenario roster")
		return false
	if LeaderManager.get_leader("tur_kemal") != null:
		print("  [FAIL] WW1 veteran tur_kemal must not appear in 2026 roster")
		return false
	var modern_usa: Leader = LeaderManager.get_leader("usa_richardson_2026")
	if modern_usa == null:
		print("  [FAIL] 2026 USA commander usa_richardson_2026 not loaded")
	var cjcs: Leader = LeaderManager.get_leader("usa_chairman_joint_chiefs_2026")
	if cjcs == null:
		print("  [FAIL] 2026 USA CJCS usa_chairman_joint_chiefs_2026 not loaded")
	if LeaderManager.get_leader("usa_navy_chief_2026") == null:
		print("  [FAIL] 2026 USA Navy chief usa_navy_chief_2026 not loaded")
	if LeaderManager.get_leader("usa_air_force_chief_2026") == null:
		print("  [FAIL] 2026 USA Air Force chief usa_air_force_chief_2026 not loaded")
		return false
	if LeaderManager.get_leader_age(modern_usa) < 40 or LeaderManager.get_leader_age(modern_usa) > 65:
		print("  [FAIL] 2026 leader age out of range: ", LeaderManager.get_leader_age(modern_usa))
		return false

	var loaded_1936: Variant = LeaderManager.load_leaders_for_scenario("1936", 1936)
	if loaded_1936 < 60:
		print("  [FAIL] 1936 merged roster load count: ", loaded_1936)
		return false
	if LeaderManager.get_leader("usa_patton") == null:
		print("  [FAIL] Patton should be active at 1936 scenario start")
		return false
	if LeaderManager.get_leader("ger_guderian") != null:
		print("  [FAIL] Guderian should be pooled until 1939 at 1936 start")
		return false
	if LeaderManager.get_leader("tur_kemal") == null:
		print("  [FAIL] 1936 should include WW1 veteran tur_kemal from 1918 roster")
		return false
	if LeaderManager.get_leader("usa_pershing") != null:
		print("  [FAIL] Pershing should not be active in 1936 (ended 1924)")
		return false
	if LeaderManager.get_leader("fin_mannerheim") == null:
		print("  [FAIL] Mannerheim should be active in 1936 merged roster")
		return false
	if not LeaderManager.leader_pool.has("ger_guderian"):
		print("  [FAIL] Guderian missing from 1936 leader pool")
		return false
	LeaderManager.set_current_year(1939)
	if LeaderManager.introduce_eligible_leaders_for_year(1939) < 1:
		print("  [FAIL] Guderian should enter in 1939")
		return false
	if LeaderManager.get_leader("ger_guderian") == null:
		print("  [FAIL] Guderian not introduced in 1939")
		return false

	var mannerheim_1936: Variant = LeaderManager.get_leader("fin_mannerheim")
	if mannerheim_1936 == null:
		print("  [FAIL] Mannerheim missing for mortality checks")
		return false
	var death_chance: Variant = LeaderManager.get_yearly_death_chance(mannerheim_1936)
	var retire_chance: Variant = LeaderManager.get_yearly_retirement_chance(mannerheim_1936)
	if death_chance <= 0.0 or retire_chance <= 0.0:
		print("  [FAIL] mortality chances for elderly leader: ", death_chance, retire_chance)
		return false

	var rommel_combat: Variant = LeaderManager.get_leader("ger_rommel")
	if rommel_combat != null:
		rommel_combat.assigned_army_id = "test_combat_formation"
		var per_battle: Variant = LeaderManager.get_combat_death_chance_per_battle(rommel_combat)
		if absf(per_battle - 0.0003) > 0.0001:
			print("  [FAIL] combat death chance should be ~0.03%: ", per_battle)
			return false
		var destroyed_chance: Variant = LeaderManager.get_formation_destroyed_fate_chance(rommel_combat)
		if absf(destroyed_chance - 0.30) > 0.05:
			print("  [FAIL] formation destroyed fate chance: ", destroyed_chance)
			return false
		rommel_combat.assigned_army_id = ""

	rommel = LeaderManager.get_leader("ger_rommel")
	if rommel == null:
		print("  [FAIL] Rommel not loaded via load_historical_leaders")
		return false
	if rommel.get_trait_level("desert_fox") < 3:
		print("  [FAIL] Rommel Desert Fox level: ", rommel.get_trait_level("desert_fox"))
		return false
	var rommel_effects: Dictionary = LeaderManager.get_leader_trait_effects(rommel)
	if float(rommel_effects.get("desert_attack", 0.0)) <= 0.0:
		print("  [FAIL] Rommel trait effects missing desert_attack: ", rommel_effects)
		return false

	print("  [PASS] LeaderManager registration and assignment")
	return true


static func _test_assignment_screen_backends() -> bool:
	var pm := _get_production_manager()
	if pm == null or Engine.get_main_loop() == null:
		print("  [SKIP] assignment screen backends (autoloads not available)")
		return true

	var test_factory_id := Factory.make_id(9999, 1)
	var test_factory := Factory.new()
	test_factory.factory_id = test_factory_id
	test_factory.province_id = 9999
	test_factory.owner_tag = "GER"
	test_factory.current_production_design = "m3_stuart_light"
	test_factory.max_production_lines = 2
	FactoryManager.register_factory(test_factory)

	var overview: Dictionary = pm.get_country_production_overview("GER")
	if int(overview.get("total_factories", 0)) < 1:
		_cleanup_test_factory(FactoryManager, test_factory_id)
		print("  [FAIL] production overview missing GER factories: ", overview)
		return false

	var screen_data: ProductionScreenData = pm.get_production_screen_data("GER")
	if screen_data.total_factories < 1 or screen_data.factories.is_empty():
		_cleanup_test_factory(FactoryManager, test_factory_id)
		print("  [FAIL] production screen data: ", screen_data.total_factories)
		return false
	if not screen_data.designs_in_production.has("m3_stuart_light"):
		_cleanup_test_factory(FactoryManager, test_factory_id)
		print("  [FAIL] designs in production: ", screen_data.designs_in_production)
		return false
	if screen_data.estimated_daily_output <= 0.0:
		_cleanup_test_factory(FactoryManager, test_factory_id)
		print("  [FAIL] estimated daily output: ", screen_data.estimated_daily_output)
		return false
	if not screen_data.factories_by_status.has("producing"):
		_cleanup_test_factory(FactoryManager, test_factory_id)
		print("  [FAIL] factories_by_status: ", screen_data.factories_by_status.keys())
		return false
	print(
		"  [INFO] GER production screen: factories=",
		screen_data.total_factories,
		" output=",
		screen_data.estimated_daily_output,
		" avg_eff=",
		screen_data.average_efficiency,
	)

	var summary: Dictionary = pm.get_factory_summary(test_factory_id)
	if str(summary.get("current_design", "")) != "m3_stuart_light":
		_cleanup_test_factory(FactoryManager, test_factory_id)
		print("  [FAIL] factory summary: ", summary)
		return false

	var producing: Array = pm.get_factories_producing_design("m3_stuart_light")
	if test_factory_id not in producing:
		_cleanup_test_factory(FactoryManager, test_factory_id)
		print("  [FAIL] factories producing design: ", producing)
		return false

	var rommel: Leader = LeaderManager.get_leader("ger_rommel")
	if rommel != null:
		var available: Array[Leader] = LeaderManager.get_available_leaders("GER")
		var rommel_listed := false
		for leader in available:
			if leader.leader_id == "ger_rommel":
				rommel_listed = true
				break
		if rommel.assigned_army_id.is_empty() and not rommel_listed:
			_cleanup_test_factory(FactoryManager, test_factory_id)
			print("  [FAIL] Rommel should be available when unassigned")
			return false

		var leader_screen: LeaderScreenData = LeaderManager.get_leader_screen_data("GER")
		if leader_screen.total_leaders < 1:
			_cleanup_test_factory(FactoryManager, test_factory_id)
			print("  [FAIL] leader screen data: ", leader_screen.total_leaders)
			return false
		if leader_screen.leaders.is_empty() or not leader_screen.leaders_by_type.has("general"):
			_cleanup_test_factory(FactoryManager, test_factory_id)
			print("  [FAIL] leaders_by_type: ", leader_screen.leaders_by_type.keys())
			return false
		if not leader_screen.national_position_bonuses.has("army_attack"):
			_cleanup_test_factory(FactoryManager, test_factory_id)
			print("  [FAIL] national_position_bonuses: ", leader_screen.national_position_bonuses)
			return false
		print(
			"  [INFO] GER leader screen: total=",
			leader_screen.total_leaders,
			" available=",
			leader_screen.available_leaders,
			" no_chief_army=",
			leader_screen.has_no_chief_of_army,
		)

		var leader_overview: Dictionary = LeaderManager.get_country_leader_overview("GER")
		if int(leader_overview.get("total_leaders", 0)) < 1:
			_cleanup_test_factory(FactoryManager, test_factory_id)
			print("  [FAIL] leader overview: ", leader_overview)
			return false

		var rommel_summary: Dictionary = LeaderManager.get_leader_summary("ger_rommel")
		if not rommel_summary.has("traits") or str(rommel_summary.get("name", "")).is_empty():
			_cleanup_test_factory(FactoryManager, test_factory_id)
			print("  [FAIL] leader summary: ", rommel_summary)
			return false

	_cleanup_test_factory(FactoryManager, test_factory_id)
	print("  [PASS] Production and Leader assignment screen backends")
	return true


static func _cleanup_test_factory(fm: Node, factory_id: int) -> void:
	fm.factories.erase(factory_id)
	var pid := Factory.province_from_id(factory_id)
	if fm.province_to_factories.has(pid):
		var ids: Array = fm.province_to_factories[pid]
		ids.erase(factory_id)
		if ids.is_empty():
			fm.province_to_factories.erase(pid)


static func _test_refinement_tradeoffs(design_data: DesignDataLoader) -> bool:
	var line := ProductionLine.new(design_data, "tradeoff_line")
	line.set_template("m3_stuart_light")
	var before := line.get_reliability_profile()
	if not line.start_refinement("pilot_shakedown"):
		print("  [FAIL] could not start shakedown")
		return false
	line.advance_days(15.0)
	var after := line.get_reliability_profile()
	var passed := (
		after.effective_reliability > before.effective_reliability
		and after.maintenance_index < before.maintenance_index
		and after.design_maturity > before.design_maturity
	)
	if passed:
		print("  [PASS] shakedown improved reliability and lowered maintenance burden")
	else:
		print("  [FAIL] shakedown tradeoff before/after ", before.maintenance_index, after.maintenance_index)
	return passed
