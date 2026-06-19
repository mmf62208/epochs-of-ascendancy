@tool
class_name EventNodeBranch
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Branch"
	title       = "Branch"
	category    = "Logic"
	description = "Evaluates a boolean condition and routes to True or False output."
	properties  = {
		"condition_method": "",   # method name on owner that returns bool
		"condition_value":  true  # fallback static value if method is empty
	}


func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	return ["True", "False"]

func get_variable_inputs() -> Array[Dictionary]:
	return [{"name": "Condition", "type": TYPE_BOOL}]

func get_variable_outputs() -> Array[Dictionary]:
	return []


func _execute(_port_name: String) -> void:
	var result: bool = bool(properties.get("condition_value", true))

	# If a Condition variable was connected and set, use it
	if properties.has("Condition"):
		result = bool(properties.get("Condition", true))

	if result:
		trigger_output("True")
	else:
		trigger_output("False")
