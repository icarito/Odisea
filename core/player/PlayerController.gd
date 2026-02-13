extends KinematicBody

const InputProvider = preload("../input/InputProvider.gd")
const InputData = preload("../input/InputData.gd")
const PlayerJump = preload("PlayerJump.gd")
const PlayerMovement = preload("PlayerMovement.gd")

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
export(float) var push_offset := 0.71 # Relaxed to 0.71m to close visual gap (User Request).
# Stair-stepping Configuration
export(float) var step_height := 0.5
export(float) var step_depth := 0.6
export(bool) var enable_step_up := true
export(float) var step_grounded_grace := 0.22
export(float) var stair_ground_probe_extra := 0.2
export(bool) var debug_stair_state := false

var _step_grounded_timer := 0.0
var _just_stepped := false
var _ground_contact_grace_timer := 0.0
var _last_debug_effective_grounded := true
var _last_debug_on_floor := true

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
var is_pushing: bool = false
var is_crouching: bool = false
var _was_pushing: bool = false
var push_normal: Vector3 = Vector3.BACK
var yaw := 0.0
var pitch := 0.0
var yaw_deg := 0.0
var pitch_deg := 0.0
var external_input = null
var external_input_provided := false
# Visual Anchoring (Hysteresis)
# Stores strictly visual offset to keep hands aligned when physics collider is closer than 0.9m
var visual_push_correction: float = 0.0

var _push_target: Spatial = null


# Cinematic Zone State
var _active_cinematic_zone: Node = null
var _prev_active_cinematic_zone: Node = null
const PushableBoxV2Script = preload("res://core/components/PushableBox.gd")

var _terminal_ui_active := false
var _restore_spring_length: float = -1.0
var _restore_fov: float = -1.0
var _exit_log_frames := 0

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
		input_provider = InputProvider.new()

var jump_logic: PlayerJump
var movement_logic: PlayerMovement
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
	input_provider = InputProvider.new()

	if has_node("Logic/Jump"):
		jump_logic = get_node("Logic/Jump")
		_created_jump_logic = false
	else:
		jump_logic = PlayerJump.new()
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
		movement_logic = PlayerMovement.new()
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

func _get_camera_to_rig_basis() -> Basis:
	if not camera_rig or not _cached_cam: return Basis.IDENTITY
	var b = Basis.IDENTITY
	var curr = _cached_cam
	while curr and curr != camera_rig and curr != self:
		b = curr.transform.basis * b
		curr = curr.get_parent()
	return b

func _get_rig_child_offset() -> Vector3:
	# Returns the local translation from CameraRig node to the start of the SpringArm
	if not camera_rig: return Vector3.ZERO
	var l_pos = Vector3.ZERO
	var arm = _find_spring_arm(camera_rig)
	var curr = arm
	while curr and curr != camera_rig:
		l_pos = curr.transform.basis * l_pos + curr.transform.origin
		curr = curr.get_parent()
	return l_pos

func snap_rig_to_camera_orbit(target_cam_pos: Vector3, target_fov: float = 70.0) -> void:
	"""
	Robustly calculates and sets yaw/pitch to place the player camera at target_cam_pos.
	Also synchronizes FOV and SpringArm length.
	"""
	# 1. Clean mouse buffer
	if input_provider and input_provider.has_method("clear_buffer"):
		input_provider.clear_buffer()

	# 2. Sync FOV
	base_fov = target_fov
	
	# 3. Find the pivot center (the world position of the SpringArm root)
	var rig_origin = camera_rig.global_transform.origin if camera_rig else global_transform.origin + Vector3.UP * base_rig_y
	var l_pivot = _get_rig_child_offset()
	var pivot_world_pos = rig_origin + global_transform.basis.xform(l_pivot)
	
	var dir_to_cam = (target_cam_pos - pivot_world_pos)
	var dist = dir_to_cam.length()
	if dist < 0.01: return
	dir_to_cam /= dist
	
	# 3. Calculate desired WORLD basis (Z points to camera)
	var z_axis = dir_to_cam
	var x_axis = Vector3.UP.cross(z_axis).normalized()
	if x_axis.length_squared() < 0.001: x_axis = Vector3.RIGHT
	var y_axis = z_axis.cross(x_axis).normalized()
	var desired_world_basis = Basis(x_axis, y_axis, z_axis)
	
	# 4. Convert World Basis to local Rig Basis (Target = GlobalPlayer * Rig * Children)
	# RigTarget = Player.inv * Target * Children.inv
	var inherent_b = _get_camera_to_rig_basis()
	var rig_local_basis = global_transform.basis.inverse() * desired_world_basis * inherent_b.inverse()
	
	# 5. Extract Yaw and Pitch using Godot's Euler YXZ (which matches our R_y * R_x)
	var euler = rig_local_basis.get_euler()
	yaw = euler.y
	pitch = euler.x
	
	# 6. Apply immediately to prevent ANY discrepancy in Frame 1
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var arm = _find_spring_arm(camera_rig)
		if arm:
			arm.spring_length = clamp(dist, 1.0, 50.0)
			base_spring_length_3d = arm.spring_length
			current_spring_length = arm.spring_length
		camera_rig.force_update_transform()
		if _cached_cam:
			_cached_cam.fov = base_fov

	yaw_deg = rad2deg(yaw)
	pitch_deg = rad2deg(pitch)

func _get_move_direction(input_vector: Vector2, mode = -1, camera_basis = null) -> Vector3:
	# print("[PlayerController] _get_move_direction called with mode: %d" % mode)
	if mode == -1:
		mode = CinematicManager.get_control_mode()
		
	if camera_basis == null:
		var camera = CinematicManager.get_active_camera()
		if camera == null:
			# Fallback if no camera found
			return Vector3(input_vector.x, 0, input_vector.y)
		camera_basis = camera.global_transform.basis

	
	var res = Vector3.ZERO
	match mode:
		CinematicManager.ControlMode.FREE:
			# Relative to camera (Standard Third Person)
			var fwd = - camera_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			
			var rt = camera_basis.x
			rt.y = 0.0
			rt = rt.normalized()
			
			# mapping: Right (+X), Forward (-Y)
			res = (rt.normalized() * input_vector.x + fwd.normalized() * (-input_vector.y))

		
		CinematicManager.ControlMode.LOCKED_VIEW:
			# Relative to camera depth (Up = Into screen)
			var forward = - camera_basis.z
			forward.y = 0
			forward = forward.normalized()
			var right = camera_basis.x
			right.y = 0
			right = right.normalized()
			
			# mapping: Right (+X), Forward (-Y)
			res = (right * input_vector.x + forward * (-input_vector.y))

		CinematicManager.ControlMode.FIXED_AXIS:
			# Absolute World Axis
			res = Vector3(input_vector.x, 0, input_vector.y)
		
		_:
			res = Vector3(input_vector.x, 0, input_vector.y)

	if res.length_squared() > 0.001:
		var raw_fwd = - camera_basis.z
		raw_fwd.y = 0
		# print("[MoveDir] mode=%d in_y=%.3f fwd_basis_z=%s raw_fwd=%s fwd_norm=%s res=%s" % [mode, input_vector.y, camera_basis.z, raw_fwd, raw_fwd.normalized(), res])
	return res

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
	box.extents = Vector3(1.5, 1.0, interact_distance / 2.0) # Widened to maintain contact when off-center
	shape.shape = box
	shape.transform.origin = Vector3(0, 1.0, -interact_distance / 2.0)
	_interact_area.add_child(shape)
	if animator:
		animator.add_child(_interact_area)
	else:
		add_child(_interact_area)

func _process_interaction(input: InputData):
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
	var input = InputData.new()
	input.from_dict(data)
	if external_input_provided and external_input != null:
		_accumulate_input(external_input, input)
	else:
		external_input = input
		external_input_provided = true

func _accumulate_input(target: InputData, source: InputData) -> void:
	target.move_vec += source.move_vec
	if target.move_vec.length() > 1.0: target.move_vec = target.move_vec.normalized()
	target.mouse_delta += source.mouse_delta
	target.zoom_delta += source.zoom_delta
	if source.fov_override > 0.0: target.fov_override = source.fov_override
	target.jump = target.jump or source.jump
	target.sprint = target.sprint or source.sprint
	target.crouch = target.crouch or source.crouch
	target.interact = target.interact or source.interact

func _update_push_state(_dt: float, input: InputData):
	_was_pushing = is_pushing
	is_pushing = false
	visual_push_correction = 0.0
	_push_target = null
	# Push is strictly grounded-only. Never activate or persist while airborne.
	if not is_on_floor() or velocity.y > 0.05:
		return
	if not _interact_area: return

	var bodies = _interact_area.get_overlapping_bodies()
	var best_target = null
	var min_dist = 999.0

	for body in bodies:
		if is_instance_valid(body) and body is PushableBoxV2Script:
			var dist = global_transform.origin.distance_squared_to(body.global_transform.origin)
			if dist < min_dist:
				min_dist = dist
				best_target = body

	if best_target:
		# Check intention: Are we trying to move towards it?
		var world_input = _get_move_direction(input.move_vec)
		var dir_to_box = (best_target.global_transform.origin - global_transform.origin)
		dir_to_box.y = 0 # Ignore vertical diff
		dir_to_box = dir_to_box.normalized()

		if world_input.length_squared() > 0.01:
			var dot = world_input.normalized().dot(dir_to_box)
			if dot > 0.5: # Approx 45 degrees
				var space_state = get_world().direct_space_state
				var from = global_transform.origin + Vector3(0, 1.0, 0)
				var input_dir = world_input.normalized()
				var to_input = from + input_dir * 2.0
				var result = space_state.intersect_ray(from, to_input, [self])
				
				if not result or result.collider != best_target:
					var to_center = best_target.global_transform.origin
					result = space_state.intersect_ray(from, to_center, [self])
				
				if result and result.collider == best_target:
					push_normal = result.normal
					var p_pos = global_transform.origin
					var h_pos = result.position
					# Project distance onto the push normal for consistent depth check (handles corners/edges)
					# surf_dist is the distance along the push axis
					var rel_vec = h_pos - p_pos
					var surf_dist = rel_vec.dot(-push_normal)
					
					# Contact Gate: Apply animation if within reasonable reach (1.25m)
					# We decouple the LOGICAL push state from the VISUAL anchor point.
					if surf_dist < 1.25:
						is_pushing = true
						# Visual Anchoring: Calculate discrepancy from ideal push_offset (0.71m)
						# Positive = Too Close (Move Back)
						# Negative = Too Far (e.g. just starting contact), clamp to 0 for now.
						visual_push_correction = max(0.0, push_offset - surf_dist)
					else:
						visual_push_correction = 0.0
				else:
					push_normal = - dir_to_box
					visual_push_correction = 0.0
				
				_push_target = best_target

func step(dt: float, input: InputData) -> void:
	if input == null: return
	
	_update_push_state(dt, input)
	var motion_grounded := is_effectively_grounded()
	var physics_grounded := is_on_floor() or _just_stepped or _step_grounded_timer > 0.0
	if debug_stair_state:
		var on_floor_now := is_on_floor()
		if motion_grounded != _last_debug_effective_grounded or on_floor_now != _last_debug_on_floor:
			print("[STAIR] floor=", on_floor_now,
				" effective=", motion_grounded,
				" vy=", String(velocity.y),
				" stepped=", _just_stepped,
				" step_timer=", String(step_grounded_grace),
				" step_grace_left=", String(_step_grounded_timer),
				" contact_grace_left=", String(_ground_contact_grace_timer))
		_last_debug_effective_grounded = motion_grounded
		_last_debug_on_floor = on_floor_now

	# if input.move_vec.length_squared() > 0.001:
		# var mode = CinematicManager.get_control_mode()
		# var cam = CinematicManager.get_active_camera()
		# var cam_name = cam.name if cam else "null"
		# var cam_basis_z = cam.global_transform.basis.z if cam else Vector3.ZERO
		# print("[PlayerController] step: move_vec=%s yaw=%.4f actual_cam=%s basis.z=%s mode=%d" % [input.move_vec, yaw, cam_name, cam_basis_z, mode])
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

	if physics_grounded and velocity.y < 0 and movement_logic.get_horizontal_velocity().y <= 0:
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
		base_spring_length_3d = clamp(base_spring_length_3d + input.zoom_delta, 2.0, 50.0)

	if input.fov_override > 0.0:
		base_fov = input.fov_override

	# Update Rig (Player's Rig)
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.force_update_transform()
		# Also force update children (SpringArm and Camera) if possible
		# They should be updated by parent force_update_transform() though.

	
	yaw_deg = rad2deg(yaw)
	pitch_deg = rad2deg(pitch)

	if is_on_floor():
		jump_logic.reset_on_floor()
	else:
		jump_logic.on_air_tick(dt)

	if input.jump:
		jump_logic.buffer_jump()

	# --- CINEMATIC ZONE DETECTION ---
	_update_cinematic_zone_detection(input)
	
	# --- MOVEMENT ---
	var move_vec = input.move_vec
	# Calculate World Direction based on Control Mode (or Latch)
	var world_dir: Vector3
	if CinematicManager.latch_active:
		if move_vec.length() < 0.1:
			CinematicManager.latch_active = false
			world_dir = _get_move_direction(move_vec)
		else:
			world_dir = _get_move_direction(move_vec, CinematicManager.latched_control_mode, CinematicManager.latched_camera_basis)
	else:
		world_dir = _get_move_direction(move_vec)

	# --- ACROBATIC SNAP DETECTION (Legacy) ---
	# Uses input.move_vec directly to capture raw intent before processing
	var current_input_3d = Vector3(input.move_vec.x, 0, input.move_vec.y).normalized()
	if current_input_3d.length() > 0.1 and last_input_vector.length() > 0.1:
		var dot_product = current_input_3d.dot(last_input_vector)
		if dot_product < -0.6: # Detección de giro 180°
			if is_acrobatic_ready:
				# Si ya estábamos listos y giramos OTRA VEZ (Double Snap), cancelamos.
				# Esto evita el backflip "al revés" cuando rectificas la dirección muy rápido.
				is_acrobatic_ready = false
				frames_since_last_snap = ACROBATIC_WINDOW_FRAMES + 1
			else:
				# Primer snap detectado
				frames_since_last_snap = 0
				is_acrobatic_ready = true
	
	# Manage acrobatic window counter
	frames_since_last_snap += 1
	if frames_since_last_snap > ACROBATIC_WINDOW_FRAMES and is_acrobatic_ready:
		is_acrobatic_ready = false
	
	if current_input_3d.length() > 0.1:
		last_input_vector = current_input_3d
	
	var basis = Basis.IDENTITY
	
	if world_dir.length() > 0.01:
		var b_z = - world_dir.normalized()
		# Construct basis looking at the movement direction
		basis = Basis(Vector3.UP.cross(b_z), Vector3.UP, b_z)
		# Simplify input to just "forward" magnitude for the logic
		move_vec = Vector2(0, -world_dir.length())
	
	is_crouching = input.crouch and physics_grounded
	var effective_sprint = input.sprint and not is_crouching

	movement_logic.process_movement(dt, move_vec, basis, effective_sprint, physics_grounded, is_crouching)
	
	var h_vel = movement_logic.get_horizontal_velocity()
	velocity.x = h_vel.x
	velocity.z = h_vel.z
	if physics_grounded:
		velocity.y = h_vel.y

	# _apply_push_constraint() # Removed for legacy physics restoration

	# --- ACROBATIC JUMP CHECK (before normal jump) ---
	if is_acrobatic_ready and is_on_floor() and jump_logic.jump_buffer_timer > 0 and not CinematicManager.latch_active:
		var force = jump_logic.acrobatic_jump_force
		velocity.y = force
		
		# 1. FRENADO EN SECO: Eliminamos la inercia actual para justificar el cambio de dirección
		velocity.x *= jump_logic.acrobatic_brake_factor
		velocity.z *= jump_logic.acrobatic_brake_factor
		
		# 2. IMPULSO HACIA ATRÁS: Usamos el vector de intención actual.
		if last_input_vector.length() > 0.1:
			var move_dir = last_input_vector.normalized()
			# Kick: Base impulse + boost.
			velocity.x += move_dir.x * jump_logic.acrobatic_backward_impulse
			velocity.z += move_dir.z * jump_logic.acrobatic_backward_impulse
			
			# Camera Visual Impact
			# (Skipped: sidescroll_logic not available in V2 controller yet)
			# if is_instance_valid(sidescroll_logic) and sidescroll_logic.is_active:
			# 	var push_val = 0.0
			# 	if sidescroll_logic.lock_axis == 2: push_val = move_dir.x
			# 	elif sidescroll_logic.lock_axis == 1: push_val = move_dir.z
			# 	sidescroll_logic.manual_yaw += push_val * jump_logic.acrobatic_camera_push
		
		jump_logic.consume_jump()
		jump_logic.set_internal_velocity(force)
		is_acrobatic_ready = false
		emit_signal("acrobatic_jumped")
	else:
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
			if debug_stair_state:
				print("[STAIR] step_up success: pos=", step_result.position, " vy=", velocity.y)
	
	velocity = move_and_slide_with_snap(velocity, snap_vec, UP, true, 4, deg2rad(45), false)
	
	_update_floor_info()
	_update_platform_tracking(dt)

	# Keep a short ground-contact grace to avoid false air states on tiny stair gaps.
	if is_on_floor():
		_ground_contact_grace_timer = step_grounded_grace
	else:
		_ground_contact_grace_timer = max(0.0, _ground_contact_grace_timer - dt)
	
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
	
	if _cached_cam and abs(_cached_cam.fov - base_fov) > 0.01:
		_cached_cam.fov = lerp(_cached_cam.fov, base_fov, 4.0 * dt)
		
func _update_cinematic_zone_detection(input: InputData):
	var all_zones = get_tree().get_nodes_in_group("CinematicCameraZone")
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
		# Capture PREVIOUS camera state for Latch
		var prev_cam = CinematicManager.get_active_camera()
		var p_basis = prev_cam.global_transform.basis if prev_cam else Basis.IDENTITY
		var p_mode = CinematicManager.get_control_mode()
		var has_input = input.move_vec.length() > 0.1 if input else false

		if _active_cinematic_zone:
			# Enter Zone
			# Enter Zone
			# Save current camera state for restore on exit (only if we haven't saved it yet or we just fully exited)
			# We check _restore_spring_length < 0 to ensure we capture the *original* player state, not an intermediate one if switching zones immediately.
			if _restore_spring_length < 0.0:
				_restore_spring_length = base_spring_length_3d
				_restore_fov = base_fov

			var rig = _active_cinematic_zone._rig_node
			if rig:
				CinematicManager.activate_rig_direct(rig, _active_cinematic_zone.control_mode)
			
			if _active_cinematic_zone.get("latch_on_enter") and has_input:
				CinematicManager.latched_camera_basis = p_basis
				CinematicManager.latched_control_mode = p_mode
				CinematicManager.latch_active = true
				# print("[PlayerController] LATCHED Basis on ENTER: ", p_basis)
				
				# Record for determinism!
				SessionManager.record_custom_event("LATCH_BASIS", {
						"basis": [
								[p_basis.x.x, p_basis.x.y, p_basis.x.z],
								[p_basis.y.x, p_basis.y.y, p_basis.y.z],
								[p_basis.z.x, p_basis.z.y, p_basis.z.z]
						],
						"mode": p_mode
				})
		else:
			# Exit Zone (Return to Player Camera)
			var cur_cam = CinematicManager.get_active_camera()
			if cur_cam:
				_exit_log_frames = 60 # Log first 60 frames (~1s) of exit to capture full transition
				print("[CameraExit] STARTING EXIT at cam_pos=", cur_cam.global_transform.origin, " fov=", cur_cam.fov)
				# 1. Snap player camera
				snap_rig_to_camera_orbit(cur_cam.global_transform.origin, cur_cam.fov)
				# 2. Deactivate cinematic rig
				CinematicManager.deactivate_rig()
				
				# 3. Restore intended player settings (smooth transition will handle the rest in _physics_process)
				if _restore_spring_length > 0.0:
					base_spring_length_3d = _restore_spring_length
					base_fov = _restore_fov
					# Reset backup so next time we capture fresh
					_restore_spring_length = -1.0
					_restore_fov = -1.0
				
				print("[CameraExit] SNAP DONE: yaw=", yaw, " pitch=", pitch, " dist=", base_spring_length_3d, " fov=", base_fov)
			else:
				CinematicManager.deactivate_rig()
			
			if _prev_active_cinematic_zone and _prev_active_cinematic_zone.get("latch_on_exit") and has_input:
				# Only latch if not ALREADY latched (e.g. from entry, maintaining continuity)
				if not CinematicManager.latch_active:
					CinematicManager.latched_camera_basis = p_basis
					CinematicManager.latched_control_mode = p_mode
					CinematicManager.latch_active = true
	
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

func is_effectively_grounded() -> bool:
	# Stair stepping can lose floor contact for one frame; keep grounded briefly to avoid air-state flicker.
	var jump_in_progress := false
	if is_instance_valid(jump_logic):
		jump_in_progress = jump_logic._is_jumping
	var recent_floor_contact := _ground_contact_grace_timer > 0.0 and not jump_in_progress
	var near_ground := false
	if not jump_in_progress:
		var space_state = get_world().direct_space_state
		var from = global_transform.origin + Vector3.UP * 0.05
		var to = from + Vector3.DOWN * (step_height + stair_ground_probe_extra)
		var hit = space_state.intersect_ray(from, to, [self], collision_mask)
		near_ground = not hit.empty()
	return is_on_floor() or _just_stepped or _step_grounded_timer > 0.0 or recent_floor_contact or near_ground

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
			# Allow a tiny tolerance for collision rounding around configured step height.
			if height_gain > 0.01 and height_gain <= step_height + 0.02:
				result.stepped = true
				result.position = Vector3(origin.x + advanced_x.x, step_surface_y, origin.z + advanced_x.z)
	return result

func _physics_process(_delta):
	if _exit_log_frames > 0:
		_exit_log_frames -= 1
		var view_cam = get_viewport().get_camera()
		var rig_cam = _cached_cam
		if view_cam and rig_cam:
			print("[CameraExit] Frame ", 60 - _exit_log_frames,
				" VIEW=", view_cam.global_transform.origin,
				" RIG=", rig_cam.global_transform.origin,
				" DELTA=", view_cam.global_transform.origin.distance_to(rig_cam.global_transform.origin))
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
	# print("[PlayerController] teleport_to called. Target: ", target_transform.origin, " Rot: ", target_transform.basis.get_euler())
	global_transform = target_transform
	velocity = Vector3.ZERO
	
	# Reset yaw/pitch to match target orientation to avoid state bleeding
	var euler = target_transform.basis.get_euler()
	yaw = euler.y
	pitch = euler.x
	yaw_deg = rad2deg(yaw)
	pitch_deg = rad2deg(pitch)
	# print("[PlayerController] teleport_to finished. Yaw: ", yaw, " Pitch: ", pitch)
	
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.force_update_transform()

	ensure_input_provider()
	set_camera_input_locked(false)
	if input_provider and input_provider.has_method("clear_buffer"):
		input_provider.clear_buffer()
