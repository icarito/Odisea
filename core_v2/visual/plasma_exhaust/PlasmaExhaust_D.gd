extends "res://core_v2/visual/plasma_exhaust/PlasmaExhaustBase.gd"

# Performance Cost: High (Option A + Option C)
# LOD Support: Yes

onready var option_a = $PlasmaExhaust_A
onready var option_c = $PlasmaExhaust_C

func _update_active_state():
	if option_a: option_a.set_active(is_active)
	if option_c: option_c.set_active(is_active)

func _update_intensity():
	if option_a: option_a.set_intensity(intensity)
	if option_c: option_c.set_intensity(intensity)

func _update_color_phase():
	if option_a: option_a.set_color_phase(color_phase)
	if option_c: option_c.set_color_phase(color_phase)
