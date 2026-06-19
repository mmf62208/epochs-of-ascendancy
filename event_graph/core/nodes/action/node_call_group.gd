@tool
extends EventNodeResource

## Call Group: Executes a function on all members of a scene group.

func _init() -> void:
	ensure_node_id()
	node_name   = "CallGroup"
	title       = "Call Group"
	category    = "Action"
	description = "Calls a method on all nodes in a specific group."
	properties  = {
		"group_name": "",
		"method_name": ""
	}

func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	return ["Out"]

func get_variable_inputs() -> Array[Dictionary]:
	return [
		{"name": "group_name", "type": TYPE_STRING},
		{"name": "method_name", "type": TYPE_STRING},
	]

func _execute(_port_name: String) -> void:
	var group: String = properties.get("group_name", "")
	var method: String = properties.get("method_name", "")
	
	if not group.is_empty() and not method.is_empty():
		if owner_node and owner_node.is_inside_tree():
			owner_node.get_tree().call_group(group, method)
		else:
			# Fallback if owner_node is not available or not in tree
			# Try Engine main loop (SceneTree)
			var tree = Engine.get_main_loop() as SceneTree
			if tree:
				tree.call_group(group, method)
			else:
				push_error("[EventGraph] CallGroup: Cannot access SceneTree.")
	
	trigger_output("Out")
