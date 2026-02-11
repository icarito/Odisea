extends KinematicBody

const InputProviderV2 = preload("../input/InputProviderV2.gd")
const InputDataV2 = preload("../input/InputDataV2.gd")
const PlayerJumpV2 = preload("PlayerJumpV2.gd")
const PlayerMovementV2 = preload("PlayerMovementV2.gd")

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP

var is_replay_mode := false

# State para drift correction
var _was_touching_rigid := false
signal rigid_contact_ended() # Emitida cuando dejamos de tocar un RigidBody
var initial_transform: Transform

# --- EXPORTED TUNING ---
export(float) var mouse_sensitivity := 0.005
export(float) var snap_length := 0.25
export(float) var push_force := 1.0
export(float) var min_pitch := -85.0
export(float) var max_pitch := 85.0
export(float) var interact_distance := 3.0

# Stair-stepping Configuration
export(float) var step_height := 0.4
export(float) var step_depth := 0.5
export(bool) var enable_step_up := true
export(float) var step_grounded_grace := 0.15

var _step_grounded_timer := 0.0
var _just_stepped := false

# Platform Transform Tracking
var _platform_collider: Spatial = null
var _platform_last_transform: Transform = Transform.IDENTITY
var _platform_velocity: Vector3 = Vector3.ZERO
var _was_on_platform := false

# Camera State
var base_fov := 75.0
var _cached_cam: Camera = null
var _cached_spring_arm: SpringArm = null
var base_spring_length := 7.0
var base_spring_length_3d := 7.0
var current_spring_length := 7.0
var base_rig_y := 0.0
var base_collision_mask := 0

# State
var velocity := Vector3()
var yaw := 0.0
var pitch := 0.0
var yaw_deg := 0.0
var pitch_deg := 0.0
var external_input: InputDataV2 = null
var external_input_provided := false

# Cinematic Zone State
var _active_cinematic_zone: Node = null
var _prev_active_cinematic_zone: Node = null
var _terminal_ui_active := false

# Signals
signal jumped
signal acrobatic_jumped
signal hit_ceiling
signal interactable_in_range(text)
signal interactable_out_of_range

# Acrobatic State
const ACROBATIC_WINDOW_FRAMES := 15
var frames_since_last_snap := ACROBATIC_WINDOW_FRAMES + 1
var last_input_vector := Vector3.ZERO
var is_acrobatic_ready := false

var _current_interactable: Node = null

# Input
var input_provider
var camera_input_locked := false

func set_camera_input_locked(locked: bool):
	camera_input_locked = locked
	if input_provider:
		input_provider.hardware_input_enabled = not locked

func ensure_input_provider():
	if not input_provider or not is_instance_valid(input_provider):
		input_provider = InputProviderV2.new()

var jump_logic: PlayerJumpV2
var movement_logic: PlayerMovementV2
var _created_jump_logic := false
var _created_movement_logic := false

# --- SNAPSHOT SERIALIZATION ---
func get_full_snapshot() -> Dictionary:
	var snapshot = {
		"position": [self.global_transform.origin.x, self.global_transform.origin.y, self.global_transform.origin.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"yaw": yaw,
		"pitch": pitch,
		"base_spring_length_3d": base_spring_length_3d,
		"movement_state": movement_logic.get_full_snapshot() if is_instance_valid(movement_logic) else {}
	}
	if is_instance_valid(jump_logic):
		snapshot["jump_state"] = {
			"coyote_timer": jump_logic.coyote_timer,
			"jump_buffer_timer": jump_logic.jump_buffer_timer,
			"is_jumping": jump_logic._is_jumping
		}
	return snapshot

func restore_snapshot(data: Dictionary) -> void:
	if data.has("position"):
		var pos = data["position"]
		var t = self.global_transform
		t.origin = Vector3(pos[0], pos[1], pos[2])
		self.global_transform = t
	if data.has("velocity"):
		var vel = data["velocity"]
		velocity = Vector3(vel[0], vel[1], vel[2])

	yaw = data.get("yaw", 0.0)
	pitch = data.get("pitch", 0.0)
	base_spring_length_3d = data.get("base_spring_length_3d", base_spring_length_3d)
	
	if data.has("movement_state") and is_instance_valid(movement_logic):
		movement_logic.restore_snapshot(data["movement_state"])

	if data.has("jump_state") and is_instance_valid(jump_logic):
		var js = data["jump_state"]
		jump_logic.coyote_timer = js.get("coyote_timer", 0.0)
		jump_logic.jump_buffer_timer = js.get("jump_buffer_timer", 0.0)
		jump_logic._is_jumping = js.get("is_jumping", false)

	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

func full_reset() -> void:
	velocity = Vector3.ZERO
	frames_since_last_snap = ACROBATIC_WINDOW_FRAMES + 1
	last_input_vector = Vector3.ZERO
	is_acrobatic_ready = false
	yaw = 0.0
	pitch = 0.0
	rotation = Vector3.ZERO
	
	if is_instance_valid(movement_logic):
		movement_logic.horizontal_velocity = Vector3.ZERO
		movement_logic.wish_direction = Vector3.ZERO
		
	if is_instance_valid(jump_logic):
		jump_logic.internal_velocity = 0.0
		jump_logic.coyote_timer = 0.0
		jump_logic.jump_buffer_timer = 0.0
		jump_logic._is_jumping = false

	_active_cinematic_zone = null
	_prev_active_cinematic_zone = null

onready var camera_rig = $CameraRig
onready var animator = $Visual/Pivot

func _ready():
	initial_transform = global_transform
	add_to_group("player")
	input_provider = InputProviderV2.new()

	if has_node("Logic/Jump"):
		jump_logic = get_node("Logic/Jump")
		_created_jump_logic = false
	else:
		jump_logic = PlayerJumpV2.new()
		_created_jump_logic = true
		jump_logic.name = "Jump"
		if has_node("Logic"):
			get_node("Logic").add_child(jump_logic)
		else:
			add_child(jump_logic)

	if has_node("Logic/Movement"):
		movement_logic = get_node("Logic/Movement")
		_created_movement_logic = false
	else:
		movement_logic = PlayerMovementV2.new()
		_created_movement_logic = true
		movement_logic.name = "Movement"
		if has_node("Logic"):
			get_node("Logic").add_child(movement_logic)
		else:
			add_child(movement_logic)
	
	_cached_cam = _find_camera(camera_rig)
	if _cached_cam:
		base_fov = _cached_cam.fov
	
	_cached_spring_arm = _find_spring_arm(camera_rig)
	if _cached_spring_arm:
		base_spring_length = _cached_spring_arm.spring_length
		base_collision_mask = _cached_spring_arm.collision_mask
	
	if camera_rig:
		base_rig_y = camera_rig.transform.origin.y
	
	_setup_interact_area()

func _find_camera(node: Node) -> Camera:
	if node is Camera:
		return node as Camera
	for i in range(node.get_child_count()):
		var cam = _find_camera(node.get_child(i))
		if cam:
			return cam
	return null

func _find_spring_arm(node: Node) -> SpringArm:
	if node is SpringArm:
		return node as SpringArm
	for i in range(node.get_child_count()):
		var arm = _find_spring_arm(node.get_child(i))
		if arm:
			return arm
	return null

func _get_move_direction(input_vector: Vector2) -> Vector3:
	var mode = CinematicManager.get_control_mode()
	var camera = CinematicManager.get_active_camera()
	
	if not camera:
		# Fallback to absolute
		return Vector3(input_vector.x, 0, input_vector.y)
	
	match mode:
		CinematicManager.ControlMode.FREE:
			# Relative to camera (Standard Third Person)
			var fwd = - camera.global_transform.basis.z
			var rt = camera.global_transform.basis.x
			fwd.y = 0
			rt.y = 0
			return (fwd.normalized() * (-input_vector.y) + rt.normalized() * input_vector.x)
		
		CinematicManager.ControlMode.LOCKED_VIEW:
			# Relative to camera depth (Up = Into screen)
			var forward = - camera.global_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
			var right = camera.global_transform.basis.x
			right.y = 0
			right = right.normalized()
			return (right * (-input_vector.x) + forward * input_vector.y)

		CinematicManager.ControlMode.FIXED_AXIS:
			# Absolute World Axis
			return Vector3(input_vector.x, 0, input_vector.y)

		_:
			return Vector3(input_vector.x, 0, input_vector.y)

var _interact_area: Area = null

func _setup_interact_area():
	if _interact_area: return
	if animator and animator.has_node("InteractArea"):
		_interact_area = animator.get_node("InteractArea")
		return

	_interact_area = Area.new()
	_interact_area.name = "InteractArea"
	_interact_area.monitorable = false
	_interact_area.monitoring = true
	_interact_area.collision_mask = 1
	var shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(0.5, 1.0, interact_distance / 2.0)
	shape.shape = box
	shape.transform.origin = Vector3(0, 1.0, -interact_distance / 2.0)
	_interact_area.add_child(shape)
	if animator:
		animator.add_child(_interact_area)
	else:
		add_child(_interact_area)

func _process_interaction(input: InputDataV2):
	if not _interact_area: return
	var bodies = _interact_area.get_overlapping_bodies()
	var best_target = null
	var min_dist = 999.0
	for body in bodies:
		if is_instance_valid(body) and body.is_in_group("interactable"):
			var dist = global_transform.origin.distance_squared_to(body.global_transform.origin)
			if dist < min_dist:
				min_dist = dist
				best_target = body

	if best_target:
		if _current_interactable != best_target:
			_current_interactable = best_target
			var text = best_target.interaction_text if best_target.get("interaction_text") else "Interact"
			emit_signal("interactable_in_range", text)
			var can_auto_trigger = not best_target.get("_auto_triggered") or not best_target.get("one_off")
			if best_target.get("auto_interact") and not best_target.is_active and can_auto_trigger:
				if best_target.has_method("set_active"):
					best_target.set_active(true)
					best_target._auto_triggered = true
		if input.interact and best_target.has_method("interact"):
			best_target.interact()
	else:
		_clear_interactable()

func _clear_interactable():
	if _current_interactable != null:
		if not _current_interactable.get("one_off"):
			_current_interactable._auto_triggered = false
		_current_interactable = null
		emit_signal("interactable_out_of_range")

func _input(event):
	if is_replay_mode or camera_input_locked: return
	if _terminal_ui_active: return
	
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if input_provider:
				input_provider.mouse_delta_accum += event.relative

	if event.is_action_pressed("zoom_in"):
		if input_provider: input_provider.zoom_delta_accum -= 1.0
	elif event.is_action_pressed("zoom_out"):
		if input_provider: input_provider.zoom_delta_accum += 1.0

# --- OYS HOOKS ---
func play_anim(anim_name: String):
	if has_node("Visual/Pivot"):
		get_node("Visual/Pivot").play_override_animation(anim_name)

func inject_input(data: Dictionary) -> void:
	if data == null: return
	var input = InputDataV2.new()
	input.from_dict(data)
	if external_input_provided and external_input != null:
		_accumulate_input(external_input, input)
	else:
		external_input = input
		external_input_provided = true

func _accumulate_input(target: InputDataV2, source: InputDataV2) -> void:
	target.move_vec += source.move_vec
	if target.move_vec.length() > 1.0: target.move_vec = target.move_vec.normalized()
	target.mouse_delta += source.mouse_delta
	target.zoom_delta += source.zoom_delta
	if source.fov_override > 0.0: target.fov_override = source.fov_override
	target.jump = target.jump or source.jump
	target.sprint = target.sprint or source.sprint
	target.interact = target.interact or source.interact

func step(dt: float, input: InputDataV2) -> void:
	if input == null: return
	
	if is_instance_valid(movement_logic) and input_provider:
		input_provider.move_response_curve = movement_logic.move_response_curve
		input_provider.camera_response_curve = movement_logic.camera_response_curve

	if camera_input_locked and input_provider:
		input_provider.hardware_input_enabled = false
	if _terminal_ui_active:
		input.move_vec = Vector2.ZERO
		input.jump = false
		input.sprint = false

	_process_interaction(input)

	if is_on_floor() and velocity.y < 0 and movement_logic.get_horizontal_velocity().y <= 0:
		velocity.y = 0
		if is_instance_valid(jump_logic):
			jump_logic.set_internal_velocity(0.0)

	# Camera Orbit Logic (Third Person)
	# Only update orbit if NOT in a camera zone (or if using FREE mode inside a zone)
	var active_zone_mode = CinematicManager.get_control_mode()
	if active_zone_mode == CinematicManager.ControlMode.FREE:
		if input and input.mouse_delta:
			movement_logic.update_tank_mode(dt, input.mouse_delta, input.move_vec, input.jump, input.sprint)
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or is_replay_mode:
				yaw -= input.mouse_delta.x * mouse_sensitivity
				pitch -= input.mouse_delta.y * mouse_sensitivity
			yaw += movement_logic.get_tank_yaw_delta(dt, input.move_vec)
		pitch = clamp(pitch, deg2rad(min_pitch), deg2rad(max_pitch))

	if abs(input.zoom_delta) > 0.01:
		base_spring_length_3d = clamp(base_spring_length_3d + input.zoom_delta, 2.0, 20.0)

	if input.fov_override > 0.0:
		base_fov = input.fov_override

	# Update Rig (Player's Rig)
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	
	yaw_deg = rad2deg(yaw)
	pitch_deg = rad2deg(pitch)

	if is_on_floor():
		jump_logic.reset_on_floor()
	else:
		jump_logic.on_air_tick(dt)

	if input.jump:
		jump_logic.buffer_jump()

	# --- CINEMATIC ZONE DETECTION ---
	_update_cinematic_zone_detection()
	
	# --- MOVEMENT ---
	var move_vec = input.move_vec
	# Calculate World Direction based on Control Mode
	var world_dir = _get_move_direction(move_vec)
	var basis = Basis.IDENTITY
	
	if world_dir.length() > 0.01:
		var b_z = -world_dir.normalized()
		# Construct basis looking at the movement direction
		basis = Basis(Vector3.UP.cross(b_z), Vector3.UP, b_z)
		# Simplify input to just "forward" magnitude for the logic
		move_vec = Vector2(0, -world_dir.length())
	
	movement_logic.process_movement(dt, move_vec, basis, input.sprint, is_on_floor())
	
	var h_vel = movement_logic.get_horizontal_velocity()
	velocity.x = h_vel.x
	velocity.z = h_vel.z
	if is_on_floor():
		velocity.y = h_vel.y

	# --- JUMP ---
	var old_vy = velocity.y
	velocity.y = jump_logic.step(dt, input.jump, velocity.y, is_on_floor())
	if velocity.y == jump_logic.jump_force and old_vy != jump_logic.jump_force:
		emit_signal("jumped")

	# --- EXTERNAL VELOCITY ---
	var external_vel = Vector3.ZERO
	if not is_on_floor() or not movement_logic.external_source_is_static:
		external_vel = movement_logic.integrate_external_velocity(dt)
	velocity += external_vel

	if _step_grounded_timer > 0:
		_step_grounded_timer -= dt
	_just_stepped = false

	var snap_vec = Vector3.DOWN * snap_length if (velocity.y <= 0 and not input.jump) else Vector3.ZERO
	
	if enable_step_up and is_on_floor() and velocity.y <= 0:
		var step_motion = movement_logic.wish_direction if movement_logic.wish_direction.length() > 0.1 else velocity
		var step_result = _try_step_up(step_motion)
		if step_result.stepped:
			global_transform.origin = step_result.position
			_just_stepped = true
			_step_grounded_timer = step_grounded_grace
	
	velocity = move_and_slide_with_snap(velocity, snap_vec, UP, true, 4, deg2rad(45), false)
	
	_update_floor_info()
	_update_platform_tracking(dt)
	
	if is_on_ceiling() and velocity.y > 0:
		velocity.y = 0
		if is_instance_valid(jump_logic):
			jump_logic.set_internal_velocity(0.0)
		emit_signal("hit_ceiling")

	# Rigid body push
	var touched_rigid = false
	for i in get_slide_count():
		var collision = get_slide_collision(i)
		var body = collision.collider
		if is_instance_valid(body) and body is RigidBody:
			touched_rigid = true
			if body.mode == RigidBody.MODE_RIGID:
				if abs(collision.normal.y) < 0.5:
					var impulse = - collision.normal * push_force * dt
					body.apply_central_impulse(impulse)
	
	if _was_touching_rigid and not touched_rigid:
		emit_signal("rigid_contact_ended")
	_was_touching_rigid = touched_rigid
					
	if animator:
		var anim_vel = velocity
		if not movement_logic.external_source_is_static:
			anim_vel = velocity - movement_logic.external_velocity
		animator.step_animator(dt, anim_vel)
		
	movement_logic.external_source_is_static = true

	# Update Camera SpringArm (for Third Person view)
	# Even if not active, we keep it updated
	if _cached_spring_arm:
		current_spring_length = lerp(current_spring_length, base_spring_length_3d, 4.0 * dt)
		_cached_spring_arm.spring_length = current_spring_length

func _update_cinematic_zone_detection():
	var all_zones = get_tree().get_nodes_in_group("CinematicCameraZoneV2")
	var best_zone = null
	var min_volume = INF

	for zone in all_zones:
		if zone.is_zone_active and zone.is_body_in_zone(self):
			# Simple volume comparison for priority (smaller = higher priority)
			var vol = zone.get_volume() if zone.has_method("get_volume") else 1000.0
			if vol < min_volume:
				min_volume = vol
				best_zone = zone

	_active_cinematic_zone = best_zone

	if _active_cinematic_zone != _prev_active_cinematic_zone:
		if _active_cinematic_zone:
			# Enter Zone
			var rig = _active_cinematic_zone._rig_node
			if rig:
				CinematicManager.activate_rig_direct(rig, _active_cinematic_zone.control_mode)
		else:
			# Exit Zone (Return to Player Camera)
			CinematicManager.deactivate_rig()

	_prev_active_cinematic_zone = _active_cinematic_zone

	# Update Terminal UI active state
	_terminal_ui_active = false
	if _active_cinematic_zone:
		var terminal = _active_cinematic_zone.get_parent()
		if terminal and terminal.get_parent():
			terminal = terminal.get_parent()
		if terminal and terminal.has_method("is_focused"):
			_terminal_ui_active = terminal.is_focused()

# Helpers
func _update_floor_info() -> void:
	if not is_on_floor():
		movement_logic.set_floor_normal(Vector3.UP)
		return
	for i in get_slide_count():
		var collision = get_slide_collision(i)
		if collision.normal.y > 0.7:
			movement_logic.set_floor_normal(collision.normal)
			return
	movement_logic.set_floor_normal(Vector3.UP)

func _update_platform_tracking(dt: float) -> void:
	var new_platform: Spatial = null
	if is_on_floor():
		for i in get_slide_count():
			var collision = get_slide_collision(i)
			if collision.normal.y > 0.7:
				var collider = collision.collider
				if collider is Spatial and not collider is StaticBody:
					new_platform = collider
					break
	
	if new_platform != _platform_collider:
		if _platform_collider != null and new_platform == null:
			if _platform_velocity.length() > 0.1:
				velocity += _platform_velocity
		
		_platform_collider = new_platform
		if new_platform:
			_platform_last_transform = new_platform.global_transform
		_was_on_platform = new_platform != null
	
	if _platform_collider != null and is_instance_valid(_platform_collider):
		var current_transform = _platform_collider.global_transform
		var old_local_pos = _platform_last_transform.affine_inverse().xform(global_transform.origin)
		var new_global_pos = current_transform.xform(old_local_pos)
		var delta_pos = new_global_pos - global_transform.origin
		_platform_velocity = delta_pos / dt if dt > 0 else Vector3.ZERO
		_platform_last_transform = current_transform
	else:
		_platform_velocity = Vector3.ZERO

func _try_step_up(motion: Vector3) -> Dictionary:
	var result = {"stepped": false, "position": global_transform.origin}
	if motion.length_squared() < 0.0001: return result
	var horizontal_motion = Vector3(motion.x, 0, motion.z)
	if horizontal_motion.length_squared() < 0.0001: return result
	var move_dir = horizontal_motion.normalized()
	var origin = global_transform.origin
	var probe_distance = clamp(motion.length(), 0.05, step_depth)
	var foot_collision = move_and_collide(move_dir * probe_distance, true, true, true)
	if foot_collision == null: return result
	if foot_collision.normal.y > 0.7: return result
	var head_collision = move_and_collide(Vector3.UP * step_height, true, true, true)
	if head_collision != null: return result
	var step_up_pos = origin + Vector3.UP * step_height
	var old_pos = global_transform.origin
	global_transform.origin = step_up_pos
	var forward_test = move_and_collide(move_dir * probe_distance, true, true, true)
	var advanced_x = move_dir * probe_distance
	if forward_test: advanced_x = forward_test.travel
	var check_pos = step_up_pos + advanced_x
	global_transform.origin = check_pos
	var down_collision = move_and_collide(Vector3.DOWN * (step_height + 0.1), true, true, true)
	global_transform.origin = old_pos
	if down_collision != null:
		if down_collision.normal.y > 0.7:
			var step_surface_y = check_pos.y - down_collision.travel.length()
			var height_gain = step_surface_y - origin.y
			if height_gain > 0.01 and height_gain <= step_height:
				result.stepped = true
				result.position = Vector3(origin.x + advanced_x.x, step_surface_y, origin.z + advanced_x.z)
	return result

func _physics_process(_delta):
	if is_replay_mode:
		if external_input_provided and external_input:
			external_input_provided = false
			step(FIXED_DT, external_input)
			external_input = null
		return

	if external_input_provided and external_input:
		external_input_provided = false
		var input = external_input
		step(FIXED_DT, input)
	else:
		var input = input_provider.get_input()
		step(FIXED_DT, input)

func set_external_velocity(v: Vector3) -> void:
	if is_instance_valid(movement_logic):
		movement_logic.set_external_velocity(v)

func set_external_source_is_static(is_static: bool) -> void:
	if is_instance_valid(movement_logic):
		movement_logic.set_external_source_is_static(is_static)

func get_wish_direction() -> Vector3:
	return movement_logic.wish_direction

func reconnect_input_provider():
	if not input_provider: ensure_input_provider()

func get_camera_basis() -> Basis:
	return camera_rig.global_transform.basis if camera_rig else Basis.IDENTITY

func teleport_to(target_transform: Transform) -> void:
	global_transform = target_transform
	velocity = Vector3.ZERO
	ensure_input_provider()
	set_camera_input_locked(false)
	if input_provider and input_provider.has_method("clear_buffer"):
		input_provider.clear_buffer()
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig:
		cam_rig.global_transform = target_transform
