@tool
class_name EventNodeCallMethod
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "CallMethod"
	title       = "Call Method"
	category    = "Action"
	description = "Calls a method on the owning Node, with an optional argument."
	properties  = {
		"method_name": "",
		"argument":    "",
		"use_argument": false,
	}


func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	return ["Out"]

func get_variable_inputs() -> Array[Dictionary]:
	return [
		{"name": "method_name", "type": TYPE_STRING},
		{"name": "argument", "type": TYPE_STRING},
	]

func get_variable_outputs() -> Array[Dictionary]:
	return []


func _execute(_port_name: String) -> void:
	var method: String = properties.get("method_name", "")
	if not method.is_empty():
		if owner_node:
			if properties.get("use_argument", false):
				owner_node.call(method, properties.get("argument"))
			else:
				owner_node.call(method)
		else:
			push_error("[EventGraph] CallMethod: owner_node is null.")
	trigger_output("Out")
