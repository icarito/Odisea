extends PushableBoxV2
class_name SteelPlate

# SteelPlate.gd - Thin pushable plate.
# Extends PushableBoxV2 to reuse its hybrid physics logic.

# export(float) var weight := 20.0 setget set_weight

func set_weight(v: float) -> void:
	weight = v
	mass = v

func _ready():
	._ready()
	mass = weight
	# Default size for SteelPlate if not overridden
	if size == Vector3(2, 2, 2): # Default from PushableBoxV2
		set_size(Vector3(2.0, 0.1, 1.0))
