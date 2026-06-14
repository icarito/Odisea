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
signal goal_reached

# --- STATE VARIABLES (Snapshotted) ---
var velocity := Vector3.ZERO
var target_position := Vector3.ZERO
var is_moving := false
var cargo_uid := "" # Path of attached cargo (original path)
var command_index := 0 # Current step in script/mission queue

# Internal state for path following
var _current_path_node: Path = null
var _path_offset := 0.0
var _is_following_path := false

# Follow Target state
var _follow_target: Node = null
var _follow_distance := 3.0
var _is_following_target := false

# Deterministic input buffer from agents
var _intended_velocity := Vector3.ZERO
var _has_intended_velocity := false
var _canonical_velocity := Vector3.ZERO # Velocity snapshot before move_and_slide()

# Parenting Logic State
var _original_parent_path := ""
var _attached_node: Spatial = null

# --- NODES ---
onready var cargo_anchor: Position3D = null
var _perf_monitor = null

func _init():
	add_to_group("replay_sync")
	# Group for SessionManager to find easily if needed
	add_to_group("cargol_drone")

func _ready():
	# CargoAnchor must live outside the KinematicBody so cargo inherits the
	# canonical logical transform, not an interpolated visual one.
	var parent_node = get_parent()
	
	# Reuse existing anchor from scene if present, otherwise create one.
	if has_node("CargoAnchor"):
		cargo_anchor = get_node("CargoAnchor")
		remove_child(cargo_anchor)
	else:
		cargo_anchor = Position3D.new()
		cargo_anchor.name = "CargoAnchor"
	
	if parent_node:
		parent_node.add_child(cargo_anchor)
	else:
		add_child(cargo_anchor)  # fallback for headless / tests

	# Register as OYS Actor
	var sm = get_node_or_null("/root/SessionManager")
	if sm:
		if sm.has_method("register_oys_actor"):
			sm.register_oys_actor("CargolDrone", self)
		if sm.has_signal("oys_registry_reset"):
			sm.connect("oys_registry_reset", self, "_on_oys_registry_reset")

	# Register with Performance Monitor
	if Engine.has_singleton("PerformanceMonitor") or has_node("/root/PerformanceMonitor"):
		_perf_monitor = get_node("/root/PerformanceMonitor")
		if _perf_monitor and _perf_monitor.has_method("register_monitored_node"):
			_perf_monitor.register_monitored_node(self)

# --- CORE API (Programmable Interface) ---

func move_to(position: Vector3) -> void:
	target_position = position
	is_moving = true
	_is_following_path = false
	_has_intended_velocity = false
	print("[Cargol] Moving to: ", target_position, " from ", global_transform.origin)

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
	_is_following_target = false

func follow_target(target: Node, distance: float = 3.0) -> void:
	# Enter follow-target mode. The drone will continuously track the target.
	if not target or not is_instance_valid(target):
		printerr("[Cargol] follow_target: Invalid target")
		return
	_follow_target = target
	_follow_distance = distance
	_is_following_target = true
	_is_following_path = false
	_has_intended_velocity = false
	is_moving = true
	_update_led(Color(0.2, 0.4, 1.0)) # Blue LED = following
	print("[Cargol] Following target: ", target.name, " at distance ", distance)

func return_to(position: Vector3) -> void:
	# Clear follow state and move to a specific position (home).
	_is_following_target = false
	_follow_target = null
	_update_led(Color(0.2, 1.0, 0.4)) # Green LED = returning
	move_to(position)
	print("[Cargol] Returning to home: ", position)

func stop() -> void:
	is_moving = false
	_is_following_path = false
	_is_following_target = false
	_follow_target = null
	_has_intended_velocity = false
	velocity = Vector3.ZERO
	_update_led(Color(0.2, 1.0, 0.4)) # Green LED = idle

func pickup(target_node_path) -> void:
	# Support string or NodePath
	var path_str = str(target_node_path)
	var target = get_node_or_null(path_str)

	if not target:
		# Try searching in current scene if relative path fails
		if get_tree().current_scene:
			target = get_tree().current_scene.find_node(path_str, true, false)

	if not target:
		# Fallback: search in parent (common for siblings)
		var p = get_parent()
		if p:
			target = p.find_node(path_str, true, false)

	if target and target is Spatial:
		if target == self:
			return

		if target is RigidBody:
			if target.mass > max_lift_capacity:
				printerr("[Cargol] Cargo too heavy: ", target.mass)
				return

			# -- Parenting Logic --
			var original_parent = target.get_parent()
			_original_parent_path = original_parent.get_path()
			cargo_uid = str(target.get_path()) # Path before move

			# Align transform to anchor globally BEFORE reparenting?
			# No, we want to snap it to anchor.

			original_parent.remove_child(target)
			cargo_anchor.add_child(target)
			target.transform = Transform.IDENTITY # Snap to anchor local 0,0,0

			# Set to "Managed" state (Kinematic + No Collision)
			target.mode = RigidBody.MODE_KINEMATIC
			target.collision_layer = 0
			target.collision_mask = 0

			_attached_node = target

			print("[Cargol] Picked up: ", target.name, " (Reparented to Anchor)")
	else:
		printerr("[Cargol] Pickup failed, invalid target: ", path_str)

func release(impulse: Vector3) -> void:
	if _attached_node:
		var target = _attached_node

		# -- Restore Parent --
		cargo_anchor.remove_child(target)

		var original_parent = get_node_or_null(_original_parent_path)
		if not original_parent:
			# Fallback to current scene if original parent lost
			original_parent = get_tree().current_scene

		if original_parent:
			# Capture launch point from anchor (which is where we are)
			var launch_transform = cargo_anchor.global_transform
			
			original_parent.add_child(target)
			
			# Force transform update
			target.global_transform = launch_transform

		if target is RigidBody:
			# Restore physics
			target.mode = RigidBody.MODE_RIGID
			target.collision_layer = 1
			target.collision_mask = 1

			# Reset physics state to avoid inherited momentum from kinematic mode or weirdness
			target.linear_velocity = Vector3.ZERO
			target.angular_velocity = Vector3.ZERO
			
			# Use canonical velocity (pre-move_and_slide) for deterministic throw momentum.
			target.apply_central_impulse(impulse + _canonical_velocity)

		print("[Cargol] Released: ", target.name)

		_attached_node = null
		cargo_uid = ""
		_original_parent_path = ""

func query_cargo() -> Dictionary:
	if _attached_node:
		var target = _attached_node
		var mass = 0.0
		if target is RigidBody:
			mass = target.mass
		return {
			"attached": true,
			"mass": mass,
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
	if _perf_monitor and _perf_monitor.has_method("measure_start"):
		_perf_monitor.measure_start(self, "step")

	var wish_velocity := Vector3.ZERO
	var arrived := false

	if _has_intended_velocity:
		wish_velocity = _intended_velocity
	elif _is_following_target and _follow_target and is_instance_valid(_follow_target):
		# Follow Target Logic: move toward target keeping follow_distance
		var target_pos = _follow_target.global_transform.origin
		var my_pos = global_transform.origin
		var to_target = target_pos - my_pos
		var dist = to_target.length()
		
		if dist > _follow_distance + 0.5:
			# Too far — move toward target
			var desired_speed = max_speed
			if dist < braking_distance + _follow_distance:
				desired_speed = max_speed * ((dist - _follow_distance) / braking_distance)
			wish_velocity = to_target.normalized() * max(desired_speed, 0.5)
		elif dist < _follow_distance - 0.5:
			# Too close — back away slightly
			wish_velocity = - to_target.normalized() * max_speed * 0.3
		# else: within deadzone, hover in place (wish_velocity stays ZERO)
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
				print("[Cargol] Reached goal: ", global_transform.origin)
				emit_signal("goal_reached")
			else:
				var desired_speed = max_speed
				if dist < braking_distance:
					desired_speed = max_speed * (dist / braking_distance)

				wish_velocity = to_target.normalized() * desired_speed

	# Acceleration / Deceleration
	var current_vel = velocity
	# Use lerp for smoother, less brusque movement
	var lerp_weight = clamp(acceleration * dt * 0.1, 0.05, 1.0)
	current_vel = current_vel.linear_interpolate(wish_velocity, lerp_weight)
	
	velocity = current_vel

	if _perf_monitor and _perf_monitor.has_method("measure_end"):
		_perf_monitor.measure_end(self, "step")

	# Capture canonical velocity BEFORE move_and_slide() can alter it via collision response.
	# release() uses this so thrown cargo momentum is deterministic across runs.
	_canonical_velocity = velocity

	_apply_movement_and_rotation()

	# Keep anchor in sync with the logical (canonical) transform, not the visual one.
	if cargo_anchor and cargo_anchor.get_parent() != self:
		cargo_anchor.global_transform = global_transform


func _apply_movement_and_rotation() -> void:
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
			# look_at points -Z towards target.
			var target_look = global_transform.origin + horiz_vel.normalized()
			if not target_look.is_equal_approx(global_transform.origin):
				look_at(target_look, Vector3.UP)

func _on_oys_registry_reset() -> void:
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("register_oys_actor"):
		sm.register_oys_actor("CargolDrone", self)

# --- VISUAL FEEDBACK ---

func _update_led(color: Color) -> void:
	# Update the drone's mesh color to indicate current mode.
	var mesh = get_node_or_null("MeshInstance")
	if mesh and mesh is MeshInstance:
		var mat = mesh.get_surface_material(0)
		if not mat or not mat is SpatialMaterial:
			mat = SpatialMaterial.new()
			mat.resource_local_to_scene = true
			mesh.set_surface_material(0, mat)
		if mat is SpatialMaterial:
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy = 0.5

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
		"path_follow": _is_following_path,
		"orig_parent": _original_parent_path,
		"follow_target": _is_following_target,
		"follow_dist": _follow_distance
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

	_original_parent_path = data.get("orig_parent", "")

	_is_following_target = data.get("follow_target", false)
	_follow_distance = data.get("follow_dist", 3.0)
	# Note: _follow_target node ref can't be serialized; must be re-established externally

	# Restoring _attached_node is tricky in replay if hierarchy changed.
	# Usually we re-resolve cargo_uid.
	# If parenting is used, the node is now a child of cargo_anchor.
	if cargo_anchor.get_child_count() > 0:
		_attached_node = cargo_anchor.get_child(0) as Spatial
