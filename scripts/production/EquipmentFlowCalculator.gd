# scripts/production/EquipmentFlowCalculator.gd
## Pure helpers for equipment_flow_compact_ledger (CP1).
## Modes, risk, symbols, interdict math — no autoload required.
class_name EquipmentFlowCalculator
extends RefCounted

const MODES: PackedStringArray = [
	"rail", "road", "airlift", "helicopter", "sealift", "river",
	"drone_logistics", "orbital",
]

const MODE_SYMBOL: Dictionary = {
	"rail": "train",
	"road": "truck",
	"airlift": "transport_plane",
	"helicopter": "helicopter",
	"sealift": "merchant",
	"river": "barge",
	"drone_logistics": "drone_convoy",
	"orbital": "orbital_loft",
}

const MODE_BASE_RISK: Dictionary = {
	"rail": 0.06,
	"road": 0.1,
	"airlift": 0.14,
	"helicopter": 0.12,
	"sealift": 0.16,
	"river": 0.08,
	"drone_logistics": 0.11,
	"orbital": 0.18,
}

const MODE_DAYS_PER_HOP: Dictionary = {
	"rail": 1.0,
	"road": 1.5,
	"airlift": 0.5,
	"helicopter": 0.75,
	"sealift": 2.0,
	"river": 1.25,
	"drone_logistics": 0.35,
	"orbital": 0.12,
}


static func normalize_mode(mode: String) -> String:
	var m := mode.strip_edges().to_lower()
	if m in MODES:
		return m
	return "rail"


static func symbol_for_mode(mode: String) -> String:
	var m := normalize_mode(mode)
	return str(MODE_SYMBOL.get(m, "train"))


static func base_corridor_risk(mode: String) -> float:
	var m := normalize_mode(mode)
	return float(MODE_BASE_RISK.get(m, 0.1))


static func transit_days(mode: String, hops: int = 1) -> float:
	var m := normalize_mode(mode)
	var per := float(MODE_DAYS_PER_HOP.get(m, 1.0))
	return maxf(0.25, per * float(maxi(1, hops)))


static func effective_interdict_loss(base_loss: float, corridor_risk: float, escorted: bool = false) -> float:
	var loss := clampf(float(base_loss), 0.0, 1.0)
	var risk := clampf(float(corridor_risk), 0.0, 1.0)
	var effective := clampf(loss * 0.65 + risk * 0.35, 0.05, 0.95)
	if escorted:
		effective *= 0.55
	return clampf(effective, 0.02, 0.95)


static func amount_after_interdict(amount: int, loss_fraction: float) -> Dictionary:
	var amt := maxi(0, int(amount))
	var loss := clampf(float(loss_fraction), 0.0, 1.0)
	var lost := int(floor(float(amt) * loss + 1e-6))
	if lost >= amt and amt > 0 and loss < 1.0:
		lost = amt - 1
	if loss >= 0.999:
		lost = amt
	var delivered := maxi(0, amt - lost)
	return {"amount": amt, "lost": lost, "delivered": delivered, "loss_fraction": loss}


static func attribution_plain(cause: String, mode: String, equipment_id: String, from_label: String, to_label: String, lost: int, amount: int) -> String:
	var c := cause.strip_edges()
	if c.is_empty():
		c = "interdiction"
	var sym := symbol_for_mode(mode)
	var pct := 0
	if amount > 0:
		pct = int(round(100.0 * float(lost) / float(amount)))
	return "%s hit a %s EquipmentFlow (%s); %d%% of %s en route %s → %s lost." % [
		c, sym, equipment_id, pct, equipment_id, from_label, to_label,
	]


static func stock_units_on_complete(design_class: String, completes: int = 1, batch_size: int = -1) -> int:
	## Mirror pure product scale table (identity-weighted hybrid). CP4: missile 1:1, drone swarm batch.
	var c := maxi(0, completes)
	if batch_size >= 1:
		return c * batch_size
	var key := design_class.strip_edges().to_lower()
	var b := 1
	match key:
		"truck", "light_vehicle", "apc":
			b = 4
		"artillery_towed":
			b = 2
		"drone_swarm", "drone", "uav":
			b = 6
		"rocket_artillery":
			b = 4
		"missile", "missile_system", "tactical_missile", "strategic_missile", "cruise_missile":
			b = 1  # 1 stock unit = 1 ready munition
		"munition", "shell", "ammo_stock":
			b = 10  # bulk ammo crates (abstract)
		"tank", "fighter", "ship", "helicopter":
			b = 1
		_:
			b = 1
	return c * b


## CP4: fire mission / sortie burns munitions or drone stock.
static func munitions_consume_amount(design_class: String, volleys: int = 1, intensity: float = 1.0) -> int:
	var v := maxi(1, volleys)
	var inten := clampf(intensity, 0.25, 3.0)
	var key := design_class.strip_edges().to_lower()
	var per := 1
	match key:
		"missile", "missile_system", "tactical_missile", "strategic_missile", "cruise_missile":
			per = 1
		"munition", "shell", "rocket_artillery":
			per = 4
		"drone_swarm", "drone":
			# Sortie attrition burns fractional swarm stock (round up)
			per = 1
		_:
			per = 1
	return maxi(1, int(ceil(float(per * v) * inten)))
