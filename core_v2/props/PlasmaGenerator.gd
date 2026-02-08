extends Spatial

# PlasmaGenerator.gd
# Controls the visual representation of the Plasma Generator, pulsing light based on core height.

func interact():
	if has_node("Core"):
		var core = $Core
		if core.has_method("set_active"):
			core.set_active(not core.is_active)

func _process(_delta):
	var core = $Core
	var light = $Core/OmniLight
	if core and light and core.get("start_position") != null:
		# Calculate height ratio (0 to 1) relative to movement
		var start_y = core.start_position.y
		var end_y = core.end_position.y
		var current_y = core.global_transform.origin.y
		var range_y = end_y - start_y
		
		# Avoid div by zero
		if abs(range_y) > 0.001:
			var t = (current_y - start_y) / range_y
			# Pulse intensity
			light.light_energy = 1.0 + abs(t) * 3.0
