@tool
class_name EventGraphResource
extends Resource

## The top-level resource storing an entire EventGraph.
## Save as .tres to disk; load to restore all nodes, connections, and state.
## This is the single source of truth for the graph.

@export var graph_name: String = "NewEventGraph"
@export var nodes: Array[Resource] = []
@export var connections: Array[Dictionary] = []

## Serialized backup for reliable persistence
## (Godot's Array[Resource] sub-resource loading can lose subclass types)
@export var serialized_nodes: Array[Dictionary] = []
@export var serialized_connections: Array[Dictionary] = []


# ── Node Helpers ─────────────────────────────────────────────────────────────

func get_node_by_id(id: String) -> EventNodeResource:
	for n in nodes:
		if n and n.get("node_id") == id:
			return n as EventNodeResource
	return null


func get_start_node() -> EventNodeResource:
	for n in nodes:
		if n and n.get("node_name") == "Start":
			return n as EventNodeResource
	return null


func add_node(node_res: EventNodeResource) -> void:
	if node_res == null:
		return
	node_res.ensure_node_id()
	_ensure_unique_node_id(node_res)
	nodes.append(node_res)
	_sync_serialized_data()
	emit_changed()


func remove_node(node_id: String) -> void:
	for i in nodes.size():
		if nodes[i] is EventNodeResource and nodes[i].node_id == node_id:
			nodes.remove_at(i)
			break
	# Also remove any connections referencing this node
	var new_conns: Array[Dictionary] = []
	for c in connections:
		if c.get("from_node_id", "") != node_id and c.get("to_node_id", "") != node_id:
			new_conns.append(c)
	connections = new_conns
	_sync_serialized_data()
	emit_changed()


# ── Connection Helpers ───────────────────────────────────────────────────────

func add_connection(from_node_id: String, from_port: String,
		to_node_id: String, to_port: String) -> void:
	if from_node_id.is_empty() or to_node_id.is_empty():
		return
	# Prevent duplicates
	for c in connections:
		if c.get("from_node_id", "") == from_node_id \
				and c.get("from_port", "") == from_port \
				and c.get("to_node_id", "") == to_node_id \
				and c.get("to_port", "") == to_port:
			return
	connections.append({
		"from_node_id": from_node_id,
		"from_port": from_port,
		"to_node_id": to_node_id,
		"to_port": to_port
	})
	_sync_serialized_data()
	emit_changed()


func remove_connection(from_node_id: String, from_port: String,
		to_node_id: String, to_port: String) -> void:
	for i in connections.size():
		var c = connections[i]
		if c.get("from_node_id", "") == from_node_id \
				and c.get("from_port", "") == from_port \
				and c.get("to_node_id", "") == to_node_id \
				and c.get("to_port", "") == to_port:
			connections.remove_at(i)
			break
	_sync_serialized_data()
	emit_changed()


## Remove all connections from a specific output port (for single-connection rule).
func remove_connections_from_port(node_id: String, port_name: String) -> void:
	var new_conns: Array[Dictionary] = []
	for c in connections:
		if c.get("from_node_id", "") == node_id and c.get("from_port", "") == port_name:
			continue
		new_conns.append(c)
	connections = new_conns
	_sync_serialized_data()


## Remove all connections to a specific input port (for single-connection rule).
func remove_connections_to_port(node_id: String, port_name: String) -> void:
	var new_conns: Array[Dictionary] = []
	for c in connections:
		if c.get("to_node_id", "") == node_id and c.get("to_port", "") == port_name:
			continue
		new_conns.append(c)
	connections = new_conns
	_sync_serialized_data()


## Returns all connections leaving a given node's output port.
func get_connections_from(node_id: String, port_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in connections:
		if c.get("from_node_id", "") == node_id and c.get("from_port", "") == port_name:
			result.append(c)
	return result


## Returns all connections arriving at a given node's input port.
func get_connections_to(node_id: String, port_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in connections:
		if c.get("to_node_id", "") == node_id and c.get("to_port", "") == port_name:
			result.append(c)
	return result


## Returns all connections from any output port of a node.
func get_all_connections_from_node(node_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in connections:
		if c.get("from_node_id", "") == node_id:
			result.append(c)
	return result


# ── Sanitize & Persist ───────────────────────────────────────────────────────

func sanitize() -> void:
	var seen_ids: Dictionary = {}
	for n in nodes:
		var data := n as EventNodeResource
		if data == null:
			continue
		data.ensure_node_id()
		if seen_ids.has(data.node_id):
			data.node_id = EventNodeResource.generate_node_id()
		seen_ids[data.node_id] = true

	var repaired: Array[Dictionary] = []
	for c in connections:
		var from_id: String = c.get("from_node_id", "")
		var to_id: String = c.get("to_node_id", "")
		if from_id.is_empty() or to_id.is_empty():
			continue
		if not seen_ids.has(from_id) or not seen_ids.has(to_id):
			continue
		var normalized := {
			"from_node_id": from_id,
			"from_port": str(c.get("from_port", "")),
			"to_node_id": to_id,
			"to_port": str(c.get("to_port", ""))
		}
		var duplicate := false
		for existing in repaired:
			if existing["from_node_id"] == normalized["from_node_id"] \
					and existing["from_port"] == normalized["from_port"] \
					and existing["to_node_id"] == normalized["to_node_id"] \
					and existing["to_port"] == normalized["to_port"]:
				duplicate = true
				break
		if not duplicate:
			repaired.append(normalized)
	connections = repaired
	_sync_serialized_data()
	emit_changed()


func prepare_for_save() -> void:
	sanitize()
	_sync_serialized_data()


func restore_after_load() -> void:
	# Always prefer serialized_nodes as source of truth.
	if not serialized_nodes.is_empty():
		var rebuilt: Array[Resource] = []
		for rec in serialized_nodes:
			var node_res := _node_from_record(rec)
			if node_res:
				rebuilt.append(node_res)
		nodes = rebuilt

	# Restore connections from backup if the main array is empty
	if connections.is_empty() and not serialized_connections.is_empty():
		connections = serialized_connections.duplicate(true)

	sanitize()


# ── Internal Serialization ───────────────────────────────────────────────────

func _ensure_unique_node_id(node_res: EventNodeResource) -> void:
	for n in nodes:
		var existing := n as EventNodeResource
		if existing and existing != node_res and existing.node_id == node_res.node_id:
			node_res.node_id = EventNodeResource.generate_node_id()
			return


func _sync_serialized_data() -> void:
	var records: Array[Dictionary] = []
	for n in nodes:
		var data := n as EventNodeResource
		if data == null:
			continue
		records.append(_node_to_record(data))
	serialized_nodes = records
	serialized_connections = connections.duplicate(true)


func _node_to_record(data: EventNodeResource) -> Dictionary:
	return {
		"node_id": data.node_id,
		"node_name": data.node_name,
		"title": data.title,
		"graph_pos": data.graph_pos,
		"properties": data.properties.duplicate(true),
		"category": data.category,
		"description": data.description
	}


func _node_from_record(rec: Dictionary) -> EventNodeResource:
	var name_key: String = rec.get("node_name", "")
	var node_res := _make_node_by_name(name_key)
	if node_res == null:
		return null

	node_res.node_id = rec.get("node_id", "")
	node_res.ensure_node_id()
	node_res.node_name = name_key if not name_key.is_empty() else node_res.node_name
	node_res.title = rec.get("title", node_res.title)
	node_res.graph_pos = rec.get("graph_pos", Vector2.ZERO)
	node_res.properties = rec.get("properties", node_res.properties)
	node_res.category = rec.get("category", node_res.category)
	node_res.description = rec.get("description", node_res.description)
	return node_res


func _make_node_by_name(name_key: String) -> EventNodeResource:
	# Look up in the NodeRegistry first (supports custom nodes)
	var registry := EventNodeRegistry.get_registry()
	if registry.has(name_key):
		var info: Dictionary = registry[name_key]
		var script_path: String = info.get("script", "")
		if not script_path.is_empty():
			var script := load(script_path) as GDScript
			if script:
				return script.new() as EventNodeResource

	push_error("[EventGraphResource] Unknown node type key during deserialization: " + name_key)
	return null
