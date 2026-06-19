@tool
class_name EventNodeResource
extends Resource

## Base class for all EventGraph node data/logic.
## Subclass this to create custom node types.
## All node information is stored as Resource (.tres) for persistence.

# ── Identity ─────────────────────────────────────────────────────────────────
## Unique ID assigned on creation (UUID-like).
@export_storage var node_id: String = ""
## Identifier for the source script/scene that created this node.
@export_storage var node_name: String = ""
## Position on the graph editor canvas.
@export_storage var graph_pos: Vector2 = Vector2.ZERO
# ── Runtime Context ──────────────────────────────────────────────────────────
## The node that owns the processor executing this graph. 
## Set by EventGraphProcessor at runtime.
var owner_node: Node = null

# ── Display ──────────────────────────────────────────────────────────────────
@export_storage var title: String = "Node"
## Category used for palette grouping and title-bar colour.
@export_storage var category: String = "Flow"  # Flow | Logic | Action | Event
@export var description: String = ""

# ── Arbitrary per-node properties (shown in Inspector) ───────────────────────
@export var properties: Dictionary = {}

static var _id_counter: int = 0


func _init() -> void:
	ensure_node_id()


func ensure_node_id() -> void:
	if node_id.is_empty():
		node_id = generate_node_id()


# ── Port Definition (Override in subclasses) ─────────────────────────────────

## Trigger (execution flow) input port names.
## Override to return e.g. ["In"]
func get_trigger_inputs() -> Array[String]:
	return []

## Trigger (execution flow) output port names.
## Override to return e.g. ["Out"]
func get_trigger_outputs() -> Array[String]:
	return []

## Variable (data flow) input ports.
## Override to return e.g. [{"name": "Value", "type": TYPE_FLOAT}]
func get_variable_inputs() -> Array[Dictionary]:
	return []

## Variable (data flow) output ports.
## Override to return e.g. [{"name": "Result", "type": TYPE_FLOAT}]
func get_variable_outputs() -> Array[Dictionary]:
	return []


# ── Execution API ────────────────────────────────────────────────────────────

## Called by GraphProcessor when execution reaches this node via a trigger port.
## @param port_name: The trigger input port name that was activated.
func trigger_input(port_name: String) -> void:
	_execute(port_name)

## Called by the node's own logic to propagate execution to the next node.
## GraphProcessor intercepts this to look up connections and call the
## target node's trigger_input().
## @param port_name: The trigger output port name to fire.
func trigger_output(port_name: String) -> void:
	# This is called from within _execute().
	# GraphProcessor hooks into this via the signal below.
	trigger_fired.emit(node_id, port_name)

## Signal emitted when trigger_output() is called.
## GraphProcessor connects to this to propagate execution.
signal trigger_fired(source_node_id: String, output_port_name: String)

## Override in subclasses to implement the node's logic.
## Called when trigger_input() is received.
## After processing, call trigger_output("PortName") to continue the flow.
func _execute(_port_name: String) -> void:
	# Default: pass through to first trigger output
	var outputs := get_trigger_outputs()
	if outputs.size() > 0:
		trigger_output(outputs[0])


# ── Variable Value Access ────────────────────────────────────────────────────

## Get the current value of a variable output port.
## Override in subclasses that produce data.
func get_variable_value(port_name: String) -> Variant:
	return properties.get(port_name, null)

## Set the value of a variable input port (called by GraphProcessor before
## trigger_input to resolve data dependencies).
func set_variable_value(port_name: String, value: Variant) -> void:
	properties[port_name] = value


# ── Display ──────────────────────────────────────────────────────────────────

## Return the display colour for this node's title bar.
func get_color() -> Color:
	match category:
		"Flow":   return Color(0.20, 0.55, 0.90)
		"Logic":  return Color(0.90, 0.65, 0.10)
		"Action": return Color(0.20, 0.75, 0.45)
		"Event":  return Color(0.80, 0.25, 0.25)
		_:        return Color(0.45, 0.45, 0.45)


# ── Utility ──────────────────────────────────────────────────────────────────

static func generate_node_id() -> String:
	_id_counter += 1
	return "%d-%d-%d" % [
		Time.get_unix_time_from_system(),
		Time.get_ticks_usec(),
		_id_counter
	]
