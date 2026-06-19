@tool
class_name EventNodeStart
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Start"
	title       = "Start"
	category    = "Flow"
	description = "Entry point of the flow graph. Execution begins here."


func get_trigger_inputs() -> Array[String]:
	return []

func get_trigger_outputs() -> Array[String]:
	return ["Out"]

func get_variable_inputs() -> Array[Dictionary]:
	return []

func get_variable_outputs() -> Array[Dictionary]:
	return []


func _execute(_port_name: String) -> void:
	trigger_output("Out")
