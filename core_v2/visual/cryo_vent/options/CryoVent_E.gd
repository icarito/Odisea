extends "res://core_v2/visual/cryo_vent/CryoVentBase.gd"

# Performance Cost: Medium (Option A volumetric shell + Option B billboard flame)
# LOD Support: Yes

# Combines A (procedural plasma shell on a cylinder) with B (camera-facing
# flipbook flame), sharing one palette so the two layers read as a single plume.
export(Color) var core_color := Color(0.1, 0.4, 1.0, 1.0) setget set_core_color
export(Color) var hot_color := Color(0.6, 0.85, 1.0, 1.0) setget set_hot_color

onready var option_a = $CryoVent_A
onready var option_b = $CryoVent_B

func _ready():
	_apply_palette()

func set_core_color(val: Color):
	core_color = val
	_apply_palette()

func set_hot_color(val: Color):
	hot_color = val
	_apply_palette()

func _apply_palette():
	if option_a:
		option_a.set_base_color(core_color)
		option_a.set_hot_color(hot_color)
		# Soft shell so the billboard flame sits inside it without a hard edge.
		option_a.set_flame_sharpness(0.25)
	if option_b:
		# B tints its flipbook; feed it the hot core as the bright flame body.
		option_b.set_tint_color(hot_color)

func _update_active_state():
	if option_a: option_a.set_active(is_active)
	if option_b: option_b.set_active(is_active)

func _update_intensity():
	if option_a: option_a.set_intensity(intensity)
	if option_b: option_b.set_intensity(intensity)

func _update_color_phase():
	if option_a: option_a.set_color_phase(color_phase)
	if option_b: option_b.set_color_phase(color_phase)
