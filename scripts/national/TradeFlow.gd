class_name TradeFlow
extends RefCounted

## TradeFlow — Lightweight representation of an ongoing trade delivery stream.
##
## Created when a TradeOffer containing ongoing goods (RESOURCE, EQUIPMENT, SUPPLY, etc.)
## is accepted. Represents the "pipe" of goods moving from one nation to another over time.
##
## This is the architectural foundation for:
## - Trade transit (routing flows along SupplyRoutePlans)
## - Interdiction (submarines, air power, surface fleets, espionage can target flows)
## - Supply integration (trade cargo contributes to national stockpiles or depots)
##
## Design goals:
## - Extremely lightweight (no simulation logic here)
## - Decoupled from actual cargo movement (SupplyMultimodalRouter / SupplyRoutePlan do the heavy lifting)
## - Rich extension points via metadata and signals
##
## A single accepted deal can create multiple TradeFlows (one per item type/quantity that makes sense as ongoing).

var flow_id: String = ""
var offer_id: String = ""

var from_tag: String = ""
var to_tag: String = ""

# The goods being delivered on this flow
var item_type: String = ""          # e.g. TradeItemType.RESOURCE, .EQUIPMENT
var item_id: String = ""            # "steel", "rubber", specific equipment_id, etc.
var quantity_per_turn: float = 0.0  # How much moves per game turn (or month)

var delivery_cadence: int = 1       # 1 = every turn, 3 = every 3 turns, etc. (future flexibility)

# Optional link into the Supply system
var route_plan_id: String = ""      # Reference to a SupplyRoutePlan if one has been assigned
var preferred_mode: String = ""     # "land", "sea", "air" — hint for routing

var created_turn: int = 0
var last_delivery_turn: int = -1
var total_delivered: float = 0.0

var active: bool = true
var suspended_reason: String = ""   # e.g. "interdicted", "route_blocked", "diplomatic_suspension"
## Freeform metadata — diplomatic_package_id, priority, interdiction_resistance, ...
## Map / supply: route_total_days, route_interdiction_chance (see _try_assign_supply_route_to_flow).
## Future interdiction: last_interdiction_loss, alternate_route_candidate, blockade flags, etc.
var metadata: Dictionary = {}

func get_display_name() -> String:
	return "%s → %s : %.1f %s / turn" % [from_tag, to_tag, quantity_per_turn, item_id]

func is_ongoing() -> bool:
	return active and quantity_per_turn > 0.0
