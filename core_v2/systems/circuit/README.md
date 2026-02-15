# Odyssey Logic Circuit System (OLCS)

The Odyssey Logic Circuit System (OLCS) is a node-based visual scripting environment for defining logic connections between interactable objects (`InteractableV2`) in the game world. It supports complex logic gates, destructible physical cables, and a custom editor interface.

## Quick Start

1.  **Activate Plugin:** Go to Project Settings -> Plugins and enable "Odyssey Logic Circuit Editor".
2.  **Add the Manager:** Create a `LogicCircuitManager` node in your scene root.
3.  **Create a Graph:** Assign a new `CircuitGraphResource` to the `circuit_data` property of the manager.
4.  **Open the Editor:** Select the `LogicCircuitManager` node. The "Circuit Board" panel will appear in the bottom dock.
5.  **Add Nodes:**
    *   **Props:** Use the editor to add references to scene objects (must inherit `InteractableV2`).
    *   **Gates:** Add logic gates (AND, OR, XOR, NOT, DELAY) to process signals.
6.  **Connect:** Drag connections between ports.
    *   **Green Port:** Activate/Input.
    *   **Red Port:** Output (Activated/Deactivated).
    *   **Blue Port:** Logic Gate Input.

## Example Scene

An example scene demonstrating basic prop connection and cable generation is available at:
`core_v2/systems/circuit/examples/CircuitExample.tscn`

## Core Components

### LogicCircuitManager (`core_v2/systems/circuit/LogicCircuitManager.gd`)
The brain of the system. It executes the logic defined in the `CircuitGraphResource` at runtime.
*   **Tick-Based Logic:** Uses `_physics_process` to propagate signals, preventing infinite loop crashes and enabling `DELAY` gates.
*   **Cable Generation:** Procedurally generates `CircuitCable` instances for wired connections.

### CircuitGraphResource (`core_v2/systems/circuit/CircuitGraphResource.gd`)
A Resource that stores the topology of the circuit (nodes and connections). It can be saved to disk or embedded in the scene.

### CircuitCable (`core_v2/systems/circuit/CircuitCable.gd`)
A procedurally generated cable connecting two objects.
*   **Visuals:** Supports both **CSGPolygon** (prototyping) and **ArrayMesh** (performance/production) via the `use_csg` property.
*   **Destructibility:** Includes a `Hurtbox` area. If the cable takes damage (health <= 0), the connection is logically broken.

## Logic Gates

*   **AND:** Output is true only if ALL inputs are true.
*   **OR:** Output is true if ANY input is true.
*   **XOR:** Output is true if an ODD number of inputs are true.
*   **NOT:** Inverts the input signal.
*   **DELAY:** Delays the signal propagation by a specified time (`delay_time`).

## Editor Plugin

The custom editor plugin is located in `addons/odyssey_circuit_editor/`.
*   **Drag & Drop:** Move nodes around the board.
*   **Connections:** Click and drag from output ports to input ports.
*   **Properties:** (Planned) Inspect and modify node properties (like Delay time) directly in the graph.

## API Usage

### Setting up a Prop
Ensure your interactive object inherits from `InteractableBaseV2`. The system automatically listens for `activated` and `deactivated` signals and calls `set_active(bool)` on the target.

### Custom Cable Anchors
To control where the cable connects to an object, add a `Position3D` (or Spatial) child node named `CableAnchor` to your prop. The system will use this position instead of the object's origin.

### Runtime Manipulation
You can access the `LogicCircuitManager` at runtime to modify the circuit or debug connections.
```gdscript
var manager = $LogicCircuitManager
manager.circuit_data.disconnect_nodes("node_a", 0, "node_b", 0)
```
