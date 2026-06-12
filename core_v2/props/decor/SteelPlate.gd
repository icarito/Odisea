extends PushableBoxV2
class_name SteelPlate
tool

# SteelPlate.gd - Thin pushable plate.
# Inherits from PushableBoxV2 to reuse hybrid deterministic physics.

func _ready():
	# Default size for SteelPlate if not overridden from default PushableBoxV2 size
	if size == Vector3(2, 2, 2):
		set_size(Vector3(2.0, 0.1, 1.0))

	._ready()

	# Set a default heavy mass if it's still at RigidBody default or the previous light value
	if mass == 1.0 or mass == 20.0:
		mass = 200.0
