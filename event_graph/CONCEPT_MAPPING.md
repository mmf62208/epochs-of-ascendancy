# EventGraph Concept to Code Mapping

This document maps user-facing concepts to their implementation in the codebase.

| Concept | Implementation Location | Logic / Implementation Details |
| :--- | :--- | :--- |
| **Graph (グラフ)** | `event_graph_resource.gd` | Extends `Resource`. Manages the lifecycle of node data and wires. |
| **Node (ノード)** | `event_node_resource.gd` | The fundamental logic unit. Every `.gd` in `nodes/` inherits this. |
| **Trigger (実行フロー)** | `EventNodeResource.trigger_fired` signal | Handled in `event_graph_processor.gd` via signal connections. |
| **Variable (データフロー)** | `EventNodeResource.get_variable_value` | Resolved in `event_graph_processor.gd` before execution. |
| **Pure Node (計算ノード)** | `EventNodeResource.is_pure()` | Returns `true` for nodes like 'Add' or 'Float Value' that have no execution pins. |
| **Registry (ノード登録)** | `event_node_registry.gd` | Uses `DirAccess` to scan folders and `ClassDB` or manual scripts to register types. |
| **Port (ポート)** | `EventNodeResource.get_..._inputs()` | Defined as Strings (Triggers) or Dictionaries (Variables). |
| **Visual Node (見た目)** | `event_graph_node.gd` | A `GraphNode` that populates slots based on the Resource's port definitions. |
| **Palette (パレット)** | `node_palette.gd` | A `Tree` UI that displays nodes grouped by the `category` defined in the Resource. |
| **Connection (接続)** | `EventGraphResource.connections` | A list of dictionaries: `{from_node, from_port, to_node, to_port}`. |
| **Execution (実行開始)** | `EventGraphProcessor.start_graph()` | Usually searches for an "Event" category node like "Start" to begin flow. |
| **Inspector (設定)** | `EventNodeResource.properties` | An exported `Dictionary` that Godot's Inspector displays for easy tuning. |
