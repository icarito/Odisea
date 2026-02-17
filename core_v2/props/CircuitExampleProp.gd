extends PropBaseV2
class_name CircuitExampleProp

# CircuitExampleProp.gd
# Circuit example demonstrating XOR logic: Light turns on when exactly ONE switch is active.
# 
# Circuit Topology:
#   SwitchA ----> XOR Gate ----> Light
#   SwitchB ----> (port 1)
#
# XOR Logic: Light = SwitchA XOR SwitchB (on when exactly one is on)
#
# Interaction:
#   - Click prop to toggle SwitchA
#   - interact_switch_a() to toggle SwitchA
#   - interact_switch_b() to toggle SwitchB

func _ready():
	# Wait for circuit manager to initialize
	call_deferred("_connect_to_circuit")

func _connect_to_circuit():
	# Find the circuit manager
	var circuit = get_node_or_null("LogicCircuitManager")
	if circuit:
		# Give it time to build
		yield(get_tree(), "idle_frame")
		yield(get_tree(), "idle_frame")
	_update_visual_feedback()

func _update_visuals():
	"""Override from PropBaseV2 - called when is_active changes."""
	_update_visual_feedback()

func interact():
	"""Default interaction toggles SwitchA (for test pipeline)."""
	interact_switch_a()

func interact_switch_a() -> bool:
	"""Toggle SwitchA."""
	var switch_a = get_node_or_null("SwitchA")
	if switch_a and switch_a.has_method("interact"):
		switch_a.interact()
		_update_visual_feedback()
		return true
	return false

func interact_switch_b() -> bool:
	"""Toggle SwitchB."""
	var switch_b = get_node_or_null("SwitchB")
	if switch_b and switch_b.has_method("interact"):
		switch_b.interact()
		_update_visual_feedback()
		return true
	return false

func _update_visual_feedback():
	# SwitchA and SwitchB are Levers - they handle their own visuals via RotatingObjectV2
	# Light is SciFiHangingLightV2 - it handles its own visuals via _update_visuals
	# We just need to ensure the circuit connection is working
	# The circuit manager will call set_active on the Light when XOR output changes
	pass

func _get_switch_material(is_on: bool) -> SpatialMaterial:
	# Levers handle their own visuals
	return null

func _get_light_material(is_on: bool) -> SpatialMaterial:
	# SciFiHangingLightV2 handles its own visuals
	return null

func _is_light_on() -> bool:
	"""Check if the light should be on (via XOR logic from circuit)."""
	var light = get_node_or_null("Light")
	if light and "is_active" in light:
		return light.is_active
	
	# Fallback: calculate XOR manually if circuit hasn't updated yet
	var switch_a = get_node_or_null("SwitchA")
	var switch_b = get_node_or_null("SwitchB")
	var a = switch_a.is_active if switch_a else false
	var b = switch_b.is_active if switch_b else false
	return (a and not b) or (not a and b)  # XOR

func _physics_process(_delta: float):
	# Poll visual feedback to reflect circuit changes
	_update_visual_feedback()
