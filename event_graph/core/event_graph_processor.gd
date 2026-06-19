class_name EventGraphProcessor
extends Node

## Runtime execution engine for a EventGraphResource.
## Implements the spec's trigger propagation and variable resolution:
## 1. trigger_output(port_name) is called by a node after processing
## 2. Processor intercepts via the trigger_fired signal
## 3. Searches connections for the target node_id and to_port
## 4. Resolves all variable_input dependencies on the target
## 5. Calls target's trigger_input(to_port)

signal flow_started
signal flow_finished
signal node_executed(node_id: String)
signal flow_error(message: String)

@export var graph: EventGraphResource = null
@export var owner_node: Node = null
@export var auto_start: bool = false

var _running: bool = false
var _stop_requested: bool = false
var _node_lookup: Dictionary = {}  # node_id -> EventNodeResource


func _init(p_graph: EventGraphResource = null, p_owner: Node = null) -> void:
	graph      = p_graph.duplicate(true)
	owner_node = p_owner


func _ready() -> void:
	if auto_start:
		if owner_node == null:
			owner_node = get_parent()
		execute()


# ── Public API ────────────────────────────────────────────────────────────────

func is_running() -> bool:
	return _running


func stop() -> void:
	_stop_requested = true
	if _running:
		_running = false
		_disconnect_all()
		flow_finished.emit()


func execute() -> void:
	if _running:
		push_warning("[EventGraphProcessor] Already running.")
		return
	if graph == null:
		push_error("[EventGraphProcessor] No graph assigned.")
		return

	graph.sanitize()
	_build_lookup()

	var start := graph.get_start_node()
	if start == null:
		push_error("[EventGraphProcessor] Graph has no Start node.")
		flow_error.emit("No Start node found.")
		return

	_running        = true
	_stop_requested = false
	flow_started.emit()

	# Connect trigger signals for all nodes
	for nid in _node_lookup:
		var node_res: EventNodeResource = _node_lookup[nid]
		if not node_res.trigger_fired.is_connected(_on_trigger_fired):
			node_res.trigger_fired.connect(_on_trigger_fired)
			
		# Allow nodes to initialize/reset themselves before the flow starts
		node_res.owner_node = owner_node
		if node_res.has_method("on_flow_start"):
			node_res.on_flow_start()

	# Start execution from the Start node
	_fire_trigger_input(start, "Start")


# ── Internal ─────────────────────────────────────────────────────────────────

func _build_lookup() -> void:
	_node_lookup.clear()
	for n in graph.nodes:
		var node_res := n as EventNodeResource
		if node_res:
			_node_lookup[node_res.node_id] = node_res


func _on_trigger_fired(source_node_id: String, output_port_name: String) -> void:
	if _stop_requested or not _running:
		return

	# Find connections from this trigger output
	var conns := graph.get_connections_from(source_node_id, output_port_name)
	if conns.is_empty():
		# No outgoing connections  Ethis branch is done, but don't finish the whole flow!
		return

	for conn in conns:
		var target_id: String = conn.get("to_node_id", "")
		var target_port: String = conn.get("to_port", "")
		var target_node: EventNodeResource = _node_lookup.get(target_id)
		if target_node == null:
			continue

		# Resolve variable inputs BEFORE triggering (spec requirement)
		_resolve_variable_inputs(target_node)

		# Fire the trigger
		_fire_trigger_input(target_node, target_port)


func _fire_trigger_input(node_res: EventNodeResource, port_name: String) -> void:
	if _stop_requested or not _running:
		return

	node_executed.emit(node_res.node_id)
	node_res.trigger_input(port_name)

	# If it's an explicit Finish node, terminate the flow graph
	if node_res.node_name == "Finish":
		_finish_flow()


## Resolve all variable inputs for a node before it executes.
func _resolve_variable_inputs(target_node: EventNodeResource) -> void:
	var var_inputs := target_node.get_variable_inputs()
	for input_def in var_inputs:
		var input_name: String = input_def.get("name", "")
		if input_name.is_empty():
			continue

		# Find connection to this variable input
		var conns := graph.get_connections_to(target_node.node_id, input_name)
		if conns.is_empty():
			continue

		# Take the first connection (variable input allows only 1)
		var conn: Dictionary = conns[0]
		var source_id: String = conn.get("from_node_id", "")
		var source_port: String = conn.get("from_port", "")

		var value: Variant = _evaluate_port(source_id, source_port)
		target_node.set_variable_value(input_name, value)


func _evaluate_port(node_id: String, port_name: String) -> Variant:
	var node_res: EventNodeResource = _node_lookup.get(node_id)
	if node_res == null:
		return null
		
	# If this is a pure data node, resolve its inputs recursively and evaluate
	if node_res.has_method("is_pure") and node_res.is_pure():
		_resolve_variable_inputs(node_res)
		if node_res.has_method("evaluate"):
			return node_res.evaluate(port_name)
			
	# Otherwise, return the cached value (for stateful trigger nodes)
	return node_res.get_variable_value(port_name)


func _finish_flow() -> void:
	if _running:
		_running = false
		_disconnect_all()
		flow_finished.emit()


func _disconnect_all() -> void:
	for nid in _node_lookup:
		var node_res: EventNodeResource = _node_lookup[nid]
		if node_res.trigger_fired.is_connected(_on_trigger_fired):
			node_res.trigger_fired.disconnect(_on_trigger_fired)
