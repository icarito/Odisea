tool
extends PropBaseV2
class_name TrackerBase

# TrackerBase.gd - Base class for tracking props (Searchlights, Cameras, etc.)

export(float) var rotation_speed := 30.0          # degrees per second for sweep
export(float) var pan_angle := 90.0                # total sweep width (degrees)
export(float) var tilt_angle := 0.0                # total vertical sweep height (degrees)
export(float) var initial_offset := 0.0            # degrees offset from forward for sweep center
export(float) var home_angle := 0.0                # rest position Y when idle
export(bool) var track_player := false             # if true, follow player instead of sweep
export(float) var track_smooth := 5.0              # lerp speed when tracking
export(float) var detection_range := 30.0 setget set_detection_range
export(float) var detection_cone := 60.0           # field of view degrees
export(float) var lost_target_delay := 2.0         # seconds to wait before returning to sweep

var _head_node: Spatial = null
var _detection_area: Area = null
var _target_player: Spatial = null
var _time := 0.0
var _lost_target_timer := 0.0
var _is_tracking := false

func _ready():
	_head_node = get_node_or_null("Head")
	if not _head_node:
		_head_node = find_node("Head", true, false)

	_detection_area = get_node_or_null("DetectionArea")
	if not _detection_area:
		_detection_area = find_node("DetectionArea", true, false)

	if _detection_area:
		if not _detection_area.is_connected("body_entered", self, "_on_body_entered"):
			_detection_area.connect("body_entered", self, "_on_body_entered")
		if not _detection_area.is_connected("body_exited", self, "_on_body_exited"):
			_detection_area.connect("body_exited", self, "_on_body_exited")
		_update_detection_shape()

	._ready()

func set_detection_range(v: float) -> void:
	detection_range = v
	if is_inside_tree():
		_update_detection_shape()

func _update_detection_shape():
	if not _detection_area: return
	var collision = _detection_area.get_node_or_null("CollisionShape")
	if collision and collision.shape is SphereShape:
		collision.shape.radius = detection_range

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		_target_player = body

func _on_body_exited(body: Node):
	if body == _target_player:
		# Don't null immediately, wait for delay
		pass

func step(dt: float) -> void:
	.step(dt)

	if not _head_node: return

	var active = anim_progress > 0.01
	if not active:
		# Return to home
		var target_rot = Vector3(0, deg2rad(home_angle), 0)
		_head_node.rotation.y = lerp_angle(_head_node.rotation.y, target_rot.y, track_smooth * dt)
		_head_node.rotation.x = lerp_angle(_head_node.rotation.x, target_rot.x, track_smooth * dt)
		return

	if track_player:
		_process_tracking(dt)
	else:
		_is_tracking = false
		_process_sweep(dt)

func _process_tracking(dt: float):
	var can_see_player = false
	if is_instance_valid(_target_player):
		var to_player = _target_player.global_transform.origin - _head_node.global_transform.origin
		var dist = to_player.length()

		if dist <= detection_range:
			var forward = -global_transform.basis.z
			# Normalize for angle calculation
			var angle = rad2deg(forward.angle_to(to_player.normalized()))

			if angle <= detection_cone * 0.5:
				can_see_player = true

	if can_see_player:
		_is_tracking = true
		_lost_target_timer = 0.0

		# Look at player
		var look_target = _target_player.global_transform.origin
		# We want smooth rotation
		var current_transform = _head_node.global_transform

		# In Godot 3 looking_at -Z is forward.
		# If origins are same, looking_at fails.
		if look_target.distance_to(current_transform.origin) > 0.01:
			var target_transform = current_transform.looking_at(look_target, Vector3.UP)
			_head_node.global_transform = current_transform.interpolate_with(target_transform, track_smooth * dt)

		# Constraint: only use Y and X rotation, zero out Z roll
		var rot = _head_node.rotation
		rot.z = 0
		_head_node.rotation = rot
	else:
		if _is_tracking:
			_lost_target_timer += dt
			if _lost_target_timer >= lost_target_delay:
				_is_tracking = false

		if _is_tracking:
			# Keep looking where it last saw player (or just stay still)
			pass
		else:
			_process_sweep(dt)

func _process_sweep(dt: float):
	_time += dt
	var speed_mod = rotation_speed * 0.1 # Arbitrary scale for smooth sweep

	# Sinusoidal sweep
	var pan_rad = deg2rad(pan_angle * 0.5)
	var tilt_rad = deg2rad(tilt_angle * 0.5)

	var target_pan = deg2rad(initial_offset) + sin(_time * speed_mod) * pan_rad
	var target_tilt = sin(_time * speed_mod * 1.5) * tilt_rad # Faster tilt for wobble

	_head_node.rotation.y = lerp_angle(_head_node.rotation.y, target_pan, track_smooth * dt)
	_head_node.rotation.x = lerp_angle(_head_node.rotation.x, target_tilt, track_smooth * dt)

func _update_visuals():
	._update_visuals()
	# TrackerBase doesn't have specific visuals, but subclasses will.
