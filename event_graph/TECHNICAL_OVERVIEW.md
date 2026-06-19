# EventGraph Technical Overview

## 🏗️ Overall Architecture
EventGraph uses a Resource-based architecture that strictly separates data/logic from visual representation.

### Core Classes
- **EventGraphResource** (`core/event_graph_resource.gd`)
    - The top-level data container. Stores `nodes` (Array of EventNodeResource) and `connections` (Array of Dictionaries).
- **EventNodeResource** (`core/event_node_resource.gd`)
    - The base class for all node logic. Defines ports and the `_execute` method.
- **EventGraphProcessor** (`core/event_graph_processor.gd`)
    - The execution engine. Handles signal propagation (triggers) and pull-based variable resolution.
- **EventNodeRegistry** (`core/event_node_registry.gd`)
    - Scans the `nodes/` directory and registers available node types for the editor.

### UI Classes
- **EventGraphEditor** (`editor/event_graph_editor.gd`)
    - The main workspace UI. Handles node spawning, connection requests, and saving/loading.
- **EventGraphNode** (`editor/event_graph_node.gd`)
    - The visual representation (`GraphNode`). Syncs its properties and connections to the underlying Resource.
- **EventNodePalette** (`editor/node_palette.gd`)
    - The searchable list of nodes used for adding new nodes.

---

## ⚡ Execution & Data Flow

### 1. Trigger Flow (Execution)
- Execution starts when a node's `trigger_input(port_name)` is called.
- This invokes the internal `_execute(port_name)` logic.
- Upon completion, the node calls `trigger_output(port_name)`, which emits the `trigger_fired` signal.
- **EventGraphProcessor** intercepts this signal, finds the connected target node, and calls its `trigger_input`.

### 2. Variable Flow (Data Resolution)
- Variable resolution is **pull-based** and occurs immediately before a node's execution.
- The Processor looks at the connected variable input ports.
- If the source is an **Impure Node**, it takes the value from the source node's `properties` cache.
- If the source is a **Pure Node** (`is_pure() == true`), the Processor calls `evaluate()` on the source node recursively.

---

## 🛠️ Port Definition API
Subclasses of `EventNodeResource` define their interface by overriding:
- `get_trigger_inputs() -> Array[String]`
- `get_trigger_outputs() -> Array[String]`
- `get_variable_inputs() -> Array[Dictionary]` (e.g. `{"name": "X", "type": TYPE_FLOAT}`)
- `get_variable_outputs() -> Array[Dictionary]`
