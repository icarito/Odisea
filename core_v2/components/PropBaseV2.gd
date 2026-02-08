tool
extends InteractableBaseV2
class_name PropBaseV2

# PropBaseV2.gd
# Base class for Props in the validation pipeline.
# Adheres to SPEC_PROP_PIPELINE.md (inferred).

# --- EXPORTS ---
# Automatic linking: If null, checks for parent/children in _ready
export(NodePath) var linked_switch_path
export(Array, NodePath) var visual_parts_paths = []

# --- DEBUG & VALIDATION ---
export(bool) var debug_draw = false

# --- PRIVATE VARS ---
var _linked_switch: Node = null
var _visual_parts: Array = []

func _ready():
	# Note: InteractableBaseV2._ready() is called automatically in Godot 3
	_auto_wire_switches()

	# Cache visual parts
	_visual_parts.clear()
	for path in visual_parts_paths:
		var node = get_node_or_null(path)
		if node:
			_visual_parts.append(node)

	# Initial visual update
	_update_visuals()

func _auto_wire_switches():
	if linked_switch_path:
		_linked_switch = get_node_or_null(linked_switch_path)
		if _linked_switch:
			_connect_switch_signals(_linked_switch)
		return

	# Fallback: Check parent
	var parent = get_parent()
	if parent:
		if parent.has_signal("state_changed") or parent.has_signal("activated"):
			_linked_switch = parent
			_connect_switch_signals(parent)

func _connect_switch_signals(node: Node):
	# Spec preferred signal
	if node.has_signal("state_changed"):
		if not node.is_connected("state_changed", self, "_on_switch_toggle"):
			node.connect("state_changed", self, "_on_switch_toggle")
	
	# Robustness backups (common in codebase)
	if node.has_signal("activated"):
		if not node.is_connected("activated", self, "_on_switch_activated"):
			node.connect("activated", self, "_on_switch_activated")
	if node.has_signal("deactivated"):
		if not node.is_connected("deactivated", self, "_on_switch_deactivated"):
			node.connect("deactivated", self, "_on_switch_deactivated")
	if node.has_signal("toggled"):
		if not node.is_connected("toggled", self, "_on_switch_toggle"):
			node.connect("toggled", self, "_on_switch_toggle")

# --- EVENT HANDLERS ---

func _on_switch_toggle(value):
	# Handle both bool (state_changed) and void (legacy) signatures safely
	if typeof(value) == TYPE_BOOL:
		set_active(value)
	else:
		# If signal didn't send a bool, we might need to query state or toggle
		# For "state_changed(bool)", it fits. 
		pass

func _on_switch_activated():
	set_active(true)

func _on_switch_deactivated():
	set_active(false)

func _on_switch_toggled(state: bool):
	set_active(state)

# --- VIRTUAL METHODS ---

func _update_visuals() -> void:
    # VentilationTurbine specific logic
    # We iterate over _visual_parts, but we know what we added in the scene:
    # 0 -> FanBlades, 1 -> WindTunnel
    # Simple logic: If progress > 0, they should be active. 
    # Or we can map progress to rotation speed or wind strength if they supported it.
    var active = (anim_progress > 0.01)
    
    for part in _visual_parts:
        if part and "is_active" in part:
            part.is_active = active
