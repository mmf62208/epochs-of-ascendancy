@tool
class_name EventNodeConstBool2
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "ConstBool"
	title       = "Bool"
	category    = "Data"
	description = "Pure Node: Outputs a constant boolean value."
	properties  = { "value": false }

func get_trigger_inputs() -> Array[String]: return []
func get_trigger_outputs() -> Array[String]: return []

func get_variable_inputs() -> Array[Dictionary]: return []
func get_variable_outputs() -> Array[Dictionary]:
	return [{"name": "Value", "type": TYPE_BOOL}]

func is_pure() -> bool: return true

func evaluate(port_name: String) -> Variant:
	if port_name == "Value":
		return bool(properties.get("value", false))
	return null

func _execute(_port_name: String) -> void: pass
