@tool
class_name EventNodePrint
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Print"
	title       = "Print"
	category    = "Action"
	description = "Prints a message to the Godot console."
	properties  = { "message": "Hello from EventGraph!" }


func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	return ["Out"]

func get_variable_inputs() -> Array[Dictionary]:
	return [{"name": "message", "type": TYPE_STRING}]

func get_variable_outputs() -> Array[Dictionary]:
	return []


func _execute(_port_name: String) -> void:
	print("[EventGraph] ", properties.get("message", ""))
	trigger_output("Out")
