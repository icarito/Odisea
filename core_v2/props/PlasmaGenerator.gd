extends SlidingObjectV2

# PlasmaGenerator.gd - Pulsing core with light intensity modulation

onready var light = get_node_or_null("OmniLight")

func _update_visuals() -> void:
	._update_visuals()

	if light:
		# Energy pulses between 1.0 and 4.0 based on progress
		light.light_energy = 1.0 + (anim_progress * 3.0)
