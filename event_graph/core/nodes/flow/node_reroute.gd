@tool
class_name EventNodeReroute2
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Reroute"
	title       = "Reroute"
	category    = "Flow"
	description = "Passes execution through unchanged. Useful for organizing graph connections."

func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	return ["Out"]

func get_variable_inputs() -> Array[Dictionary]:
	return []

func get_variable_outputs() -> Array[Dictionary]:
	return []

func _execute(_port_name: String) -> void:
	trigger_output("Out")
