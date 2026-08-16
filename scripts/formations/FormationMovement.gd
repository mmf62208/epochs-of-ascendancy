class_name FormationMovement
extends RefCounted

## Bridge for division map movement orders. Engineer repair deployment uses the same path
## as future general formation movement (move_to_province order type).

const ORDER_MOVE_TO_PROVINCE := "move_to_province"

## Move any land division to a province (registers presence + updates stationed_province_id).
## Template-backed primitive (engineer / known division ids). OOB fids may fail — use
## BattleManager.station_formation_on_province for capture/march hops.
static func move_formation_to_province(
	formation_id: String,
	province_id: int,
	country_tag: String = "",
) -> Dictionary:
	if typeof(SupplyManager) == TYPE_NIL:
		return {"ok": false, "error": "SupplyManager unavailable"}
	return SupplyManager.move_formation_to_province(formation_id, province_id, country_tag)


## Player multi-day own-land march (BattleManager.issue_march_order).
static func issue_march(
	formation_id: String,
	dest_pid: int,
	country_tag: String = "",
	instant: bool = false,
) -> Dictionary:
	if typeof(BattleManager) == TYPE_NIL or not BattleManager.has_method("issue_march_order"):
		return {"ok": false, "error": "BattleManager unavailable"}
	return BattleManager.issue_march_order(formation_id, dest_pid, country_tag, instant)


## Engineer-capable divisions only — same movement pipeline, validates engineer brigades.
static func move_engineer_formation_to_province(
	formation_id: String,
	province_id: int,
	country_tag: String = "",
) -> Dictionary:
	if typeof(SupplyManager) == TYPE_NIL:
		return {"ok": false, "error": "SupplyManager unavailable"}
	return SupplyManager.deploy_engineer_formation_to_province(formation_id, province_id, country_tag)
