extends PropBaseV2
class_name IndustrialFan

# IndustrialFan.gd
# Deterministic fan that pushes objects in its forward direction (-Z).

export(float) var rotation_speed := 15.0 # Radians per second
export(float) var wind_force := 10.0

var _blade: Spatial
var _area: Area

func _ready():
	_blade = get_node_or_null("Housing/Blade")
	_area = get_node_or_null("WindArea")
	_update_visuals()

func _physics_process(delta):
	# Fan logic runs in physics step for determinism
	step(delta)

	if is_active and _blade:
		_blade.rotate_y(rotation_speed * delta)

	if is_active and _area:
		var bodies = _area.get_overlapping_bodies()
		for body in bodies:
			if body == self: continue

			# Direction: Forward (-Z)
			var dir = - global_transform.basis.z

			if body.has_method("set_external_velocity"):
				# PlayerControllerV2 or compatible actor
				body.set_external_velocity(dir * wind_force)
			elif body is RigidBody:
				# Physics object
				body.apply_central_impulse(dir * wind_force * delta)

func _update_visuals():
	# Could change light color or sound if implemented
	pass
