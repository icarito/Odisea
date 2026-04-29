# OLCS - Logic Circuit System

## Overview

The OLCS (Odisea Logic Circuit System) provides deterministic signal propagation between interactive elements in the game world. It connects props, terminals, and other interactive objects through a tick-based logic execution model.

## Architecture

```
LogicCircuitManager (591 lines)
    │
    ├── CircuitGraphResource (77 lines)
    │   ├── nodes: Dictionary
    │   └── connections: Array
    │
    ├── CircuitCable (visual)
    │
    ├── CircuitUINode (NEW)
    │   └── Connects UI → circuit
    │
    └── CircuitTerminalBridge (NEW)
        └── Bidirectional UI ↔ circuit
```

## Core Components

### CircuitGraphResource

Resource that stores circuit topology.

```gdscript
# nodes: Dictionary { node_id -> NodeData }
# NodeData: {
#   "type": "PROP" | "GATE",
#   "position": Vector2,
#   "scene_path": NodePath,
#   "gate_type": "AND" | "OR" | "XOR" | "NOT" | "DELAY",
#   "delay_time": float
# }

# connections: Array of Dictionary
# {
#   "from": node_id,
#   "from_port": int,
#   "to": node_id,
#   "to_port": int,
#   "type": "WIRED" | "WIRELESS"
# }
```

### LogicCircuitManager

Executes tick-based signal propagation.

- Uses `_physics_process(delta)` with `_output_queue` and `_input_queue`
- Has `MAX_LOGIC_STEPS = 100` to prevent infinite loops
- Tick-based execution ensures deterministic behavior
- Supports PROP and GATE node types

## API

### CircuitGraphResource

```gdscript
var graph = CircuitGraphResource.new()

# Add nodes
graph.add_node("door_main", {
  "type": "PROP",
  "scene_path": NodePath("Doors/MainDoor"),
})

graph.add_node("logic_and", {
  "type": "GATE",
  "gate_type": "AND",
})

# Connect nodes
graph.connect_nodes("button_1", 0, "door_main", 0, "WIRED")

# Validate circuit
var validation = graph.validate()
# Returns: { valid: bool, errors: [], warnings: [], node_count: int, connection_count: int }

# Get nodes by type
var props = graph.get_node_by_type("PROP")
var gates = graph.get_node_by_gate_type("AND")
```

### CircuitUINode

UI node that connects to circuit.

```gdscript
var circuit_ui = CircuitUINode.new()
circuit_ui.connect_to_circuit_manager(circuit_manager)
circuit_ui.node_id = "terminal_button_1"

# Send signals to circuit
circuit_ui.send_output(true)
circuit_ui.send_input("input_1", false)
```

### CircuitTerminalBridge

Bidirectional bridge between Terminal and circuits.

```gdscript
var bridge = CircuitTerminalBridge.new()
bridge.connect_to_circuit_manager(circuit_manager)
bridge.connect_output("terminal_1", "door_main")

# Terminal command → circuit
bridge.send_terminal_command("activate")
bridge.send_terminal_command("toggle")

# Get snapshot for replay
var snapshot = bridge.get_snapshot()
bridge.restore_snapshot(snapshot)
```

## Gate Types

| Gate | Description | Truth Table |
|------|-------------|--------------|
| AND | All inputs must be true | Outputs true if ALL inputs true |
| OR | Any input can trigger | Outputs true if ANY input true |
| XOR | Odd number of inputs | Outputs true if ODD count true |
| NOT | Inverts input | Outputs inverse of input |
| DELAY | Delays signal | Outputs after delay_time |

## Integration

### With InteractableBaseV2

Props emit `activated` and `deactivated` signals that LogicCircuitManager listens to:

```gdscript
# In LogicCircuitManager._build_runtime_logic():
if r_data.type == "PROP":
    if node.has_signal("activated"):
        node.connect("activated", self, "_on_prop_activated", [id])
    if node.has_signal("deactivated"):
        node.connect("deactivated", self, "_on_prop_deactivated", [id])
```

### With TerminalUI

Use CircuitTerminalBridge for terminal → circuit connections:

```gdscript
# Setup in scene
var bridge = CircuitTerminalBridge.new()
bridge.circuit_manager_path = NodePath("/root/LogicCircuitManager")
bridge.terminal_node_id = "terminal_1"
bridge.output_node_id = "door_main"

# Terminal button clicked → circuit
bridge.send_terminal_command("activate")
```

## Replay Determinism

All circuit components implement `get_snapshot()` and `restore_snapshot()`:

- CircuitTerminalBridge queues commands with timestamps
- LogicCircuitManager uses deterministic tick order
- Animation uses step() pattern from InteractableBaseV2

## Testing

```bash
./runtest.sh -a ./core_v2/tests/test_circuit_integration.gd
./runtest.sh -a ./core_v2/tests/test_terminal_circuit_bridge.gd
```