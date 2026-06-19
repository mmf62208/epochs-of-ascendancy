@tool
class_name EventNodeOr2
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Or"
	title       = "Or"
	category    = "Logic"
	description = "Fires the output whenever ANY of its inputs are triggered."
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


func _execute(_port_name: String) -> void:
	# Orノードはいずれかのインプットが呼ばれたら即座にアウトプットを発火します。
	trigger_output("Out")
