extends KinematicBody

class_name CargolDroneV2

# Cargol Drone V2 - Logic & Programmability Spec
# Implements "Command Queue" architecture and deterministic replay compatibility.

# --- EXPORTED CONFIGURATION ---
export(float) var max_speed := 15.0
export(float) var acceleration := 20.0
export(float) var braking_distance := 2.5
export(float) var max_lift_capacity := 500.0 # Mass limit for cargo

# --- SIGNALS ---
signal obstacle_detected(normal, distance)
signal cargo_lost
signal low_battery_threshold
signal goal_reached

# --- STATE VARIABLES (Snapshotted) ---
var velocity := Vector3.ZERO
var target_position := Vector3.ZERO
var is_moving := false
var cargo_uid := "" # Path of attached cargo
var command_index := 0 # Current step in script/mission queue

# Internal state for path following
var _current_path_node: Path = null
var _path_offset := 0.0
var _is_following_path := false

# Deterministic input buffer from agents
var _intended_velocity := Vector3.ZERO
var _has_intended_velocity := false

# --- NODES ---
onready var cargo_anchor: RemoteTransform = null

func _init():
	add_to_group("replay_sync")
	# Group for SessionManager to find easily if needed
	add_to_group("cargol_drone")

func _ready():
	if has_node("CargoAnchor"):
		cargo_anchor = get_node("CargoAnchor")
	else:
		# Create anchor if not present in scene (fallback)
		var anchor = RemoteTransform.new()
		anchor.name = "CargoAnchor"
		add_child(anchor)
		cargo_anchor = anchor

# --- CORE API (Programmable Interface) ---

func move_to(position: Vector3) -> void:
	target_position = position
	is_moving = true
	_is_following_path = false
	_has_intended_velocity = false
	# print("[Cargol] Moving to: ", target_position)

func follow_path(path_nodepath: NodePath) -> void:
	var node = get_node_or_null(path_nodepath)
	if node and node is Path:
		_current_path_node = node
		_path_offset = 0.0
		_is_following_path = true
		is_moving = true
		_has_intended_velocity = false
		# print("[Cargol] Following path: ", path_nodepath)
	else:
		printerr("[Cargol] Invalid path node: ", path_nodepath)

func set_velocity(vector: Vector3) -> void:
	_intended_velocity = vector
	_has_intended_velocity = true
	is_moving = true # Active movement state
	_is_following_path = false

func stop() -> void:
	is_moving = false
	_is_following_path = false
	_has_intended_velocity = false
	velocity = Vector3.ZERO

func pickup(target_node_path) -> void:
	# Support string or NodePath
	var path_str = str(target_node_path)
	var target = get_node_or_null(path_str)

	if not target:
		# Try searching in current scene if relative path fails
		if get_tree().current_scene:
			target = get_tree().current_scene.find_node(path_str, true, false)

	if target and target is Spatial:
		if target == self:
			return

		if target is RigidBody:
			if target.mass > max_lift_capacity:
				printerr("[Cargol] Cargo too heavy: ", target.mass)
				return

			# Align transform to anchor
			target.global_transform = cargo_anchor.global_transform

			# Set to "Managed" state
			target.mode = RigidBody.MODE_KINEMATIC
			target.collision_layer = 0
			target.collision_mask = 0

			cargo_anchor.remote_path = target.get_path()
			cargo_uid = str(target.get_path())

			# print("[Cargol] Picked up: ", target.name)
	else:
		printerr("[Cargol] Pickup failed, invalid target: ", path_str)

func release(impulse: Vector3) -> void:
	if cargo_uid != "":
		var target = get_node_or_null(cargo_uid)
		if target and target is RigidBody:
			cargo_anchor.remote_path = ""

			# Restore physics
			target.mode = RigidBody.MODE_RIGID
			target.collision_layer = 1
			target.collision_mask = 1

			target.apply_central_impulse(impulse)
			target.linear_velocity += velocity

			# print("[Cargol] Released: ", target.name)

		cargo_uid = ""

func query_cargo() -> Dictionary:
	if cargo_uid != "":
		var target = get_node_or_null(cargo_uid)
		if target and target is RigidBody:
			return {
				"attached": true,
				"mass": target.mass,
				"name": target.name,
				"type": "RigidBody"
			}
	return {"attached": false}

# --- PHYSICS / DETERMINISM ---

func _physics_process(delta: float) -> void:
	# Only run if not managed by external replay/recording system that calls step() manually
	# For now, we assume standard behavior unless specifically told otherwise via logic
	# SessionManager usually disables _physics_process during recording/replay on 'replay_sync' nodes
	step(delta)

func step(dt: float) -> void:
	var wish_velocity := Vector3.ZERO
	var arrived := false

	if _has_intended_velocity:
		wish_velocity = _intended_velocity
	elif is_moving:
		if _is_following_path and _current_path_node:
			# Path Following Logic
			var curve = _current_path_node.curve
			var path_length = curve.get_baked_length()

			# Determine look-ahead point
			var look_ahead = 1.0
			var target_offset = _path_offset + look_ahead

			if target_offset > path_length:
				target_offset = path_length
				if _path_offset >= path_length - 0.1:
					arrived = true

			var target_pos_world = _current_path_node.to_global(curve.interpolate_baked(target_offset))
			var to_target = target_pos_world - global_transform.origin

			if to_target.length() > 0.1:
				wish_velocity = to_target.normalized() * max_speed

				# Advance offset roughly based on speed
				# For better precision we should project actual movement onto curve
				_path_offset += velocity.length() * dt
			else:
				if arrived:
					is_moving = false
					velocity = Vector3.ZERO
					emit_signal("goal_reached")

		else:
			# Direct Movement Logic
			var to_target = target_position - global_transform.origin
			var dist = to_target.length()

			if dist < 0.2:
				arrived = true
				is_moving = false
				velocity = Vector3.ZERO
				emit_signal("goal_reached")
			else:
				var desired_speed = max_speed
				if dist < braking_distance:
					desired_speed = max_speed * (dist / braking_distance)

				wish_velocity = to_target.normalized() * desired_speed

	# Acceleration / Deceleration
	var current_vel = velocity
	var diff = wish_velocity - current_vel
	var max_delta = acceleration * dt

	if diff.length() > max_delta:
		current_vel += diff.normalized() * max_delta
	else:
		current_vel = wish_velocity

	velocity = current_vel

	# Move and Slide
	if velocity.length() > 0.001:
		velocity = move_and_slide(velocity, Vector3.UP)

		# Collision Feedback
		for i in range(get_slide_count()):
			var collision = get_slide_collision(i)
			# Only report significant obstacles
			if collision.collider is StaticBody or collision.collider is CSGShape:
				emit_signal("obstacle_detected", collision.normal, global_transform.origin.distance_to(collision.position))

		# Rotation (Face forward)
		# Only rotate if moving significantly
		var horiz_vel = Vector3(velocity.x, 0, velocity.z)
		if horiz_vel.length() > 0.1:
			var look_dir = -horiz_vel.normalized() # Look at checks -Z, so -velocity? No, look_at target.
			# look_at points -Z towards target.
			# If we want front (+Z or -Z?) to face movement.
			# Usually models face -Z (Godot standard).
			# So we look at (pos + velocity).
			var target_look = global_transform.origin + horiz_vel.normalized()
			if not target_look.is_equal_approx(global_transform.origin):
				look_at(target_look, Vector3.UP)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"tf_origin": var2str(global_transform.origin),
		"tf_basis": var2str(global_transform.basis),
		"velocity": var2str(velocity),
		"target_pos": var2str(target_position),
		"is_moving": is_moving,
		"cargo_uid": cargo_uid,
		"cmd_idx": command_index,
		"has_intent": _has_intended_velocity,
		"intent_vel": var2str(_intended_velocity),
		"path_off": _path_offset,
		"path_follow": _is_following_path
	}

func restore_snapshot(data: Dictionary) -> void:
	if data.has("tf_origin"):
		var o = str2var(data["tf_origin"])
		var b = str2var(data["tf_basis"])
		global_transform = Transform(b, o)

	velocity = str2var(data.get("velocity", "Vector3(0,0,0)"))
	target_position = str2var(data.get("target_pos", "Vector3(0,0,0)"))
	is_moving = data.get("is_moving", false)
	cargo_uid = data.get("cargo_uid", "")
	command_index = data.get("cmd_idx", 0)

	_has_intended_velocity = data.get("has_intent", false)
	_intended_velocity = str2var(data.get("intent_vel", "Vector3(0,0,0)"))

	_path_offset = data.get("path_off", 0.0)
	_is_following_path = data.get("path_follow", false)

	if cargo_anchor:
		cargo_anchor.remote_path = cargo_uid
