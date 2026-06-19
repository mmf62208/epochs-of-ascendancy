# Godot EventGraph Addon Specification

This document summarizes the specifications and usage of **EventGraph**, a node-based visual scripting addon built for Godot 4.

## 1. System Architecture

This addon follows a design that completely separates data/logic (**Resource**) from the UI (**GraphNode / GraphEdit**). This ensures stable data persistence and efficient runtime execution.

### Core Components
*   **EventGraphResource** (`event_graph_resource.gd`):
	*   A top-level Resource file (`.tres` or `.res`) that holds the data for the entire graph.
	*   Manages the list of nodes and connection information, ensuring reliable saving and restoration via serialization.
*   **EventNodeResource** (`event_node_resource.gd`):
	*   The base Resource class for all nodes.
	*   Contains node execution logic, port definitions, and display settings (title, category color, etc.). This class is inherited when creating custom nodes.
*   **EventNodeRegistry** (`event_node_registry.gd`):
	*   A registry that automatically scans directories under `addons/event_graph/core/nodes/` (specifically `event`, `flow`, `logic`, `action`, `data`, and `utility`) and registers the list of available nodes.
*   **EventGraphProcessor** (`event_graph_processor.gd`):
	*   The graph execution engine (Runtime).
	*   Monitors `trigger_fired` signals and controls execution propagation (triggers) and variable dependency resolution (data flow).

---

## 2. Execution Model

EventGraph operates by combining two mechanisms: **Trigger-based Execution Flow** and **Variable-based Data Flow**.

### Execution Flow (Triggers)
1.  Execution starts when the processor calls `trigger_input("Start")` on a `Start` node (or similar entry point).
2.  Each node performs its processing in the `_execute(port_name)` method.
3.  Upon completion, the node calls `trigger_output(port_name)`.
4.  This emits a `trigger_fired` signal, which the processor detects to propagate execution to the next connected node.

### Data Flow (Variable Resolution)
*   Just before the processor executes a node (via a Trigger), it **resolves the node's input variables**.
*   It traces data connections backwards to retrieve values from source nodes.
*   **Pure Data Nodes** (nodes where `is_pure()` returns `true`): These are recursively resolved and evaluated via `evaluate()`.
*   **Impure Nodes**: For nodes that carry state or side effects, the cached value (`get_variable_value()`) is used.

---

## 3. Node Categories

Nodes are categorized based on their purpose, which determines their grouping in the palette and the color of their title in the editor.

*   **Flow (Cyan)**: Nodes that control execution flow (e.g., Branch, Sequence, Reroute).
*   **Logic (Blue)**: Logical operations and comparisons (e.g., And, Or, Compare).
*   **Action (Green)**: Nodes that execute specific processes or side effects (e.g., Print, Move, Play Animation).
*   **Event (Red)**: Entry points for execution (e.g., Start, OnTick, Signal Handlers).
*   **Data (Grey)**: Nodes that provide constant values or variable references (e.g., Float Value, Get Variable).
*   **Utility**: Other helpful auxiliary nodes.

---

## 4. Creating Custom Nodes

To add a new node, create a script inheriting from `EventNodeResource` in the appropriate directory (e.g., `addons/event_graph/core/nodes/action/`). The `EventNodeRegistry` will automatically recognize it.

### Action Node Template (Stateful/Impure)
```gdscript
@tool
extends EventNodeResource

# Required: Initialize basic node information
func _init() -> void:
    super()
    node_name = "MyCustomNode" # Unique internal name
    title = "My Custom Node"   # Display name in editor
    category = "Action"        # Category for color/grouping
    description = "Description of what this node does."

# Define input trigger ports
func get_trigger_inputs() -> Array[String]:
    return ["In"]

# Define output trigger ports
func get_trigger_outputs() -> Array[String]:
    return ["Out"]

# Define input variable ports
func get_variable_inputs() -> Array[Dictionary]:
    return [
        {"name": "Value1", "type": TYPE_FLOAT},
        {"name": "Value2", "type": TYPE_FLOAT}
    ]

# Define output variable ports
func get_variable_outputs() -> Array[Dictionary]:
    return [{"name": "Result", "type": TYPE_FLOAT}]

# Execution logic
func _execute(processor: EventGraphProcessor, port_name: String) -> void:
    # 1. Fetch input variables (already resolved by the processor)
    var val1 = get_input_value(0)
    var val2 = get_input_value(1)
    
    # 2. Process
    var result = val1 + val2
    
    # 3. Store result for output
    properties["Result"] = result
    
    # 4. Pass execution to the next node
    processor.execute_output(self, 0)
```

### Pure Data Node Template
For "Value nodes" or "Math nodes" that return results without triggers:
```gdscript
@tool
extends EventNodeResource

func _init() -> void:
    super()
    node_name = "FloatValue"
    title = "Float Value"
    category = "Data"

# Return empty for trigger ports
func get_trigger_inputs() -> Array[String]: return []
func get_trigger_outputs() -> Array[String]: return []

func get_variable_outputs() -> Array[Dictionary]:
    return [{"name": "Value", "type": TYPE_FLOAT}]

# Initialize properties so they appear in the inspector
func _ready():
    if not properties.has("Value"):
        properties["Value"] = 0.0

# Required: Inform the processor this is a pure data node
func is_pure() -> bool:
    return true

# Required: Processing when a value is requested by the processor
func evaluate(port_name: String) -> Variant:
    return properties.get("Value", 0.0)
```

---

## 5. Important Notes
*   The `properties` dictionary is not only displayed in the inspector but also serves as a cache for output variables.
*   When adding or modifying custom node scripts, reload the editor or ensure `EventNodeRegistry.rebuild()` is triggered to reflect changes.
