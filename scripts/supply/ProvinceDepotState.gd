class_name ProvinceDepotState
extends RefCounted

var province_id: int = -1
var storage_capacity: float = 0.0
var stockpile: float = 0.0
var throughput_capacity: float = 0.0
var inbound_per_day: float = 0.0
var outbound_per_day: float = 0.0

## Sabotage state from daily agent network pressure (supply_disruption focus).
## 0.0 = normal; higher values = more disrupted logistics (set by AgentManager daily effects).
## Decays slowly over days in SupplyManager; counter-intel sweeps can zero it immediately via clear_daily_sabotage_effects.
## Makes per-province supply disruption "targeted" and visible in state (beyond one-shot temp hits).
var sabotage_level: float = 0.0
## Local fuel from oil refineries (simplified depot-side tracking).
var fuel_stockpile: float = 0.0


func _init(pid: int = -1, capacity: float = 0.0) -> void:
	province_id = pid
	storage_capacity = capacity
	throughput_capacity = capacity * 0.15
	stockpile = capacity * 0.65


func apply_inflow(tons: float) -> float:
	var room := maxf(storage_capacity - stockpile, 0.0)
	var accepted := minf(tons, room)
	stockpile += accepted
	inbound_per_day = accepted
	return tons - accepted


func pull_outflow(requested: float) -> float:
	var effective_throughput := throughput_capacity
	if sabotage_level > 0.0:
		# Further targeted reduction: sabotaged depots have reduced flow (up to ~55% penalty)
		effective_throughput *= maxf(0.0, 1.0 - sabotage_level * 0.55)
	var sent := minf(minf(requested, stockpile), effective_throughput)
	stockpile -= sent
	outbound_per_day = sent
	return sent


func fill_ratio() -> float:
	if storage_capacity <= 0.0:
		return 0.0
	return clampf(stockpile / storage_capacity, 0.0, 1.0)
