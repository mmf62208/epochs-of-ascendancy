# scripts/combat/LandBattleAar.gd
## After-action line + next-hex offer. Engagement, not a full HOI AAR screen.
class_name LandBattleAar
extends RefCounted


static func format_line(
	winner: String,
	place: String,
	days: int,
	loss_plain: String = "",
	next_place: String = "",
) -> String:
	var w := str(winner or "").strip_edges().to_lower()
	var name := place.strip_edges()
	if name.is_empty():
		name = "the hex"
	var day_n := maxi(0, int(days))
	var loss := loss_plain.strip_edges()
	if w == "attacker":
		var s := "Took %s · %d day%s" % [name, day_n, "s" if day_n != 1 else ""]
		if not loss.is_empty() and loss != "no stock to lose":
			s += " · %s" % loss
		if not next_place.strip_edges().is_empty():
			s += " — Press %s next?" % next_place.strip_edges()
		else:
			s += " — Hold and recover?"
		return s
	if w == "defender" or w == "draw":
		var s2 := "Held at %s · %d day%s" % [name, day_n, "s" if day_n != 1 else ""]
		if not loss.is_empty() and loss != "no stock to lose":
			s2 += " · %s" % loss
		s2 += " — Recover or try again?"
		return s2
	return "Battle ended at %s" % name


## One captured pid only. Era-visible oil/steel/coal via harvest scale; occupied ×0.65.
static func economy_sentence(
	resources: Dictionary,
	year: int = 1936,
	owner: String = "",
	controller: String = "",
) -> String:
	if resources.is_empty():
		return ""
	var scaled: Dictionary = ResourceHarvestCalculator.scale_deposits_for_year(resources, year)
	var best := ""
	var best_amt := 0.0
	for k in ["oil", "steel", "coal"]:
		var amt := float(scaled.get(k, 0.0))
		if amt > best_amt:
			best = k
			best_amt = amt
	if best.is_empty():
		return ""
	var verb := "pumping" if best == "oil" else "mining"
	var occ := float(ResourceHarvestCalculator.occupation_harvest_mult(owner, controller))
	if occ < 0.999:
		return "Now %s %s (occupied ×%.2f)." % [verb, best, occ]
	return "Now %s %s." % [verb, best]


static func pick_next_enemy_hex(from_id: int, attacker_tag: String) -> int:
	if from_id <= 0 or typeof(MapManager) == TYPE_NIL:
		return -1
	var tag := attacker_tag.strip_edges().to_upper()
	if not MapManager.has_method("get_adjacent_provinces"):
		return -1
	var best := -1
	var best_n := 999
	for nb in MapManager.get_adjacent_provinces(from_id, true):
		var pid := int(nb)
		var p: Province = MapManager.get_province(pid) if MapManager.has_method("get_province") else null
		if p == null or bool(p.is_sea):
			continue
		var ctrl := str(p.controller_tag).strip_edges().to_upper()
		if ctrl.is_empty():
			ctrl = str(p.owner_tag).strip_edges().to_upper()
		if ctrl == tag or ctrl.is_empty():
			continue
		# Prefer a hex that still has a defender (a real fight), else any enemy.
		var n := 0
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("get_divisions_at_province"):
			n = BattleManager.get_divisions_at_province(pid, ctrl).size()
		if best < 0 or n < best_n:
			best = pid
			best_n = n
			if n > 0:
				return pid
	return best
