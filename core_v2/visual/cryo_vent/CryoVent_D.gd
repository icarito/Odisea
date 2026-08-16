extends "res://core_v2/visual/cryo_vent/CryoVentBase.gd"

# Performance Cost: High (Option A + Option C)
# LOD Support: Yes

# A single shared palette so the volumetric shell (A) and the particles (C)
# blend instead of clashing. core_color is the cool base, hot_color the bright
# core; both children are driven from these.
# Cian por defecto: este es el crioenfriador del sistema de criocoolant (FD-256),
# no plasma. El color dice qué sistema falla antes de que el fallo dañe.
export(Color) var core_color := Color(0.0, 0.55, 0.68, 1.0) setget set_core_color
export(Color) var hot_color := Color(0.35, 0.92, 0.98, 1.0) setget set_hot_color

onready var option_a = $CryoVent_A
onready var option_c = $CryoVent_C

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
		# Softer, more diffuse shell so it melds with the particles instead of
		# reading as a separate crisp cone.
		option_a.set_flame_sharpness(0.2)
	if option_c:
		# C tints its (additive) flipbook by a single color; use the hot core so
		# the particles read as the bright heart of the same plume as A.
		option_c.set_core_color(hot_color)
		# Lower additive punch so particles blend into A's shell.
		option_c.set_softness(0.45)

func _update_active_state():
	if option_a: option_a.set_active(is_active)
	if option_c: option_c.set_active(is_active)

func _update_intensity():
	if option_a: option_a.set_intensity(intensity)
	if option_c: option_c.set_intensity(intensity)

func _update_color_phase():
	if option_a: option_a.set_color_phase(color_phase)
	if option_c: option_c.set_color_phase(color_phase)
