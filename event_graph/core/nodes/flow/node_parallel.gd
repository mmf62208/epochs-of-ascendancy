@tool
class_name EventNodeParallel2
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Parallel"
	title       = "Parallel"
	category    = "Flow"
	description = "Executes multiple output triggers simultaneously (sequentially in immediate order)."
	properties  = { "_output_count": 2 }


func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	var count: int = properties.get("_output_count", 2)
	var outputs: Array[String] = []
	for i in range(count):
		outputs.append("Out " + str(i + 1))
	return outputs

func get_variable_inputs() -> Array[Dictionary]:
	return []

func get_variable_outputs() -> Array[Dictionary]:
	return []


func get_custom_actions() -> Array:
	return [
		{"label": "Add Output", "method": "add_output_port"},
		{"label": "Remove Output", "method": "remove_output_port"}
	]

func add_output_port() -> void:
	var count: int = properties.get("_output_count", 2)
	properties["_output_count"] = count + 1

func remove_output_port() -> void:
	var count: int = properties.get("_output_count", 2)
	if count > 2:
		properties["_output_count"] = count - 1


func _execute(_port_name: String) -> void:
	var count: int = properties.get("_output_count", 2)
	for i in range(count):
		trigger_output("Out " + str(i + 1))
