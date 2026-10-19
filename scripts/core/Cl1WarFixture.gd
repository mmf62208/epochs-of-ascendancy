# scripts/core/Cl1WarFixture.gd
## Test-only: put a pair at war through WarStateDomain (CL1 combat gate).
## Does not disable the campaign loop and does not touch BattleManager.
class_name Cl1WarFixture
extends RefCounted


static func declare(attacker: String, defender: String, goal: String = "test") -> Dictionary:
	var a := attacker.strip_edges().to_upper()
	var b := defender.strip_edges().to_upper()
	if a.is_empty() or b.is_empty():
		return {"ok": false, "reason": "bad pair"}
	if WarStateDomain.is_at_war(a, b):
		return {"ok": true, "already": true, "pair": WarStateDomain.pair_key(a, b)}
	return WarStateDomain.declare_war(a, b, goal)


static func declare_pairs(pairs: Array) -> Dictionary:
	var last: Dictionary = {"ok": true}
	for raw in pairs:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 2:
			return {"ok": false, "reason": "bad pair"}
		var row: Array = raw
		last = declare(str(row[0]), str(row[1]), "test")
		if not bool(last.get("ok", false)):
			return last
	return last
