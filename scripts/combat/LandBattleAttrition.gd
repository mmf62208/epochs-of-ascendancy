# scripts/combat/LandBattleAttrition.gd
class_name LandBattleAttrition
extends RefCounted

## Daily land-battle equipment + strength write-off. Offline SOT:
## tools/map_generation/lib/land_battle_attrition_product.py
##
## CombatLoop / start_land_battle seed (BattleManager is file-locked):
##   ProductionManager.ensure_demo_combat_stock(fid, tag)
## Daily tick (is_winner_lean = this side is the current lean):
##   var sev := LandBattleAttrition.daily_severity(is_winner_lean, days_elapsed)
##   var report := LandBattleAttrition.apply_daily_to_formation(fid, sev)

const WINNER_LEAN := 0.06
const LOSER_EVEN := 0.10
const DAY3_EXTRA := 0.01
const SEV_MIN := 0.05
const SEV_MAX := 0.22
const STRENGTH_DRAIN_FACTOR := 0.5
const MINUS := "−"
const DOT := " · "
const NO_STOCK := "no stock to lose"


static func daily_severity(is_winner_lean: bool, days_elapsed: int) -> float:
	# winner lean 0.06, loser/even 0.10; +0.01 per day after day 3; clamp 0.05–0.22
	var base := WINNER_LEAN if is_winner_lean else LOSER_EVEN
	var extra := maxi(0, days_elapsed - 3) * DAY3_EXTRA
	return clampf(base + extra, SEV_MIN, SEV_MAX)


static func format_loss_plain(removed: Dictionary) -> String:
	if removed.is_empty():
		return NO_STOCK
	var rows: Array = []
	for raw_id in removed.keys():
		var n := int(removed[raw_id])
		if n <= 0:
			continue
		rows.append([_short_name(str(raw_id)), n])
	if rows.is_empty():
		return NO_STOCK
	rows.sort_custom(func(a, b):
		var ia := _preferred_rank(str(a[0]))
		var ib := _preferred_rank(str(b[0]))
		if ia != ib:
			return ia < ib
		return str(a[0]) < str(b[0])
	)
	var parts: PackedStringArray = PackedStringArray()
	for row in rows:
		parts.append("%s %s%d" % [str(row[0]), MINUS, int(row[1])])
	return DOT.join(parts)


static func apply_daily_to_formation(formation_id: String, severity: float) -> Dictionary:
	var fid := formation_id.strip_edges()
	var removed: Dictionary = {}
	if (
		not fid.is_empty()
		and typeof(ProductionManager) != TYPE_NIL
		and ProductionManager.has_method("apply_combat_equipment_loss")
	):
		var raw: Variant = ProductionManager.apply_combat_equipment_loss(fid, severity)
		if typeof(raw) == TYPE_DICTIONARY:
			removed = raw
	var strength_after := -1.0
	if not fid.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		var form: Formation = LeaderManager.get_formation(fid)
		if form != null and "strength" in form:
			var drain := STRENGTH_DRAIN_FACTOR * severity
			form.strength = clampf(float(form.strength) - drain, 0.0, 1.0)
			strength_after = float(form.strength)
			if drain >= 0.08 and "combat_experience" in form:
				form.combat_experience = LandCombatPower.dilute_xp_heavy_loss(
					float(form.combat_experience), drain
				)
	var plain := format_loss_plain(removed)
	print(
		"[LAND BATTLE ATTRITION] %s %s str=%.2f sev=%.2f"
		% [fid, plain, strength_after, severity]
	)
	return {
		"removed": removed,
		"strength_after": strength_after,
		"plain": plain,
	}


static func _short_name(equipment_id: String) -> String:
	var key := equipment_id.strip_edges().to_lower()
	if key.is_empty():
		return "equip"
	if "rifle" in key or "infantry" in key or "small_arms" in key:
		return "rifles"
	if "truck" in key or "motorized" in key:
		return "trucks"
	if "support" in key:
		return "support"
	if "artillery" in key:
		return "artillery"
	if "tank" in key or "armor" in key or "armour" in key or "panzer" in key:
		return "tanks"
	return key.replace("_", " ")


static func _preferred_rank(name: String) -> int:
	match name:
		"rifles":
			return 0
		"support":
			return 1
		"trucks":
			return 2
		"artillery":
			return 3
		"tanks":
			return 4
		_:
			return 99
