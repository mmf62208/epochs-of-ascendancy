@tool
class_name EventNodeFinish
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Finish"
	title       = "Finish"
	category    = "Flow"
	description = "Terminates the flow graph execution."


func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	return []

func get_variable_inputs() -> Array[Dictionary]:
	return []

func get_variable_outputs() -> Array[Dictionary]:
	return []


func _execute(_port_name: String) -> void:
	# No trigger_output  Ethis ends the flow.
	pass
