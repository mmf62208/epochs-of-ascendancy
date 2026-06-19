@tool
class_name EventNodeAnd2
extends EventNodeResource

var _fired_inputs: Dictionary = {}

func _init() -> void:
	ensure_node_id()
	node_name   = "And"
	title       = "And"
	category    = "Logic"
	description = "Waits for all inputs to fire before firing the output."
	properties  = { "_input_count": 2 }


func get_trigger_inputs() -> Array[String]:
	var count: int = properties.get("_input_count", 2)
	var inputs: Array[String] = []
	for i in range(count):
		inputs.append("In " + str(i + 1))
	return inputs

func get_trigger_outputs() -> Array[String]:
	return ["Out"]

func get_variable_inputs() -> Array[Dictionary]:
	return []

func get_variable_outputs() -> Array[Dictionary]:
	return []


func get_custom_actions() -> Array:
	return [
		{"label": "Add Input", "method": "add_input_port"},
		{"label": "Remove Input", "method": "remove_input_port"}
	]

func add_input_port() -> void:
	var count: int = properties.get("_input_count", 2)
	properties["_input_count"] = count + 1

func remove_input_port() -> void:
	var count: int = properties.get("_input_count", 2)
	if count > 2:
		properties["_input_count"] = count - 1
		_fired_inputs.clear() # Clear firing state as port count changed


func _execute(port_name: String) -> void:
	_fired_inputs[port_name] = true
	
	var count: int = properties.get("_input_count", 2)
	var all_fired := true
	for i in range(count):
		if not _fired_inputs.has("In " + str(i + 1)):
			all_fired = false
			break
			
	if all_fired:
		_fired_inputs.clear()
		trigger_output("Out")
