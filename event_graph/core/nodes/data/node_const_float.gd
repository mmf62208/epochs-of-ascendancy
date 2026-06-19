@tool
class_name EventNodeConstFloat2
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "ConstFloat"
	title       = "Float"
	category    = "Data"
	description = "Pure Node: Outputs a constant float value."
	properties  = { "value": 0.0 }

func get_trigger_inputs() -> Array[String]: return []
func get_trigger_outputs() -> Array[String]: return []

func get_variable_inputs() -> Array[Dictionary]: return []
func get_variable_outputs() -> Array[Dictionary]:
	return [{"name": "Value", "type": TYPE_FLOAT}]

func is_pure() -> bool: return true

func evaluate(port_name: String) -> Variant:
	if port_name == "Value":
		return float(properties.get("value", 0.0))
	return null

func _execute(_port_name: String) -> void: pass
