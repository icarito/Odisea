extends KinematicBody

const InputProviderV2 = preload("../input/InputProviderV2.gd")
const InputDataV2 = preload("../input/InputDataV2.gd")
const PlayerJumpV2 = preload("PlayerJumpV2.gd")
const PlayerMovementV2 = preload("PlayerMovementV2.gd")

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP
const PLAYER_REQUIRED_COLLISION_MASK := 1 << 6 # Layer 7
const PLAYER_WEAK_VISUAL_REAPPLY_FRAMES := 24
const HARDWARE_PROFILE_LOW := 1
const HYPER_LOW_ANIMATOR_STEP_INTERVAL_FRAMES := 3

var is_replay_mode := false

# State para drift correction
var _was_touching_rigid := false
signal rigid_contact_ended() # Emitida cuando dejamos de tocar un RigidBody
var initial_transform: Transform

# --- EXPORTED TUNING ---
export(float) var mouse_sensitivity := 0.005
export(bool) var invert_mouse_y := false
export(float) var joy_look_sensitivity := 15.0
export(float) var joy_move_sensitivity := 1.0
export(float) var snap_length := 0.25
export(float) var push_force := 1.0
export(float) var min_pitch := -85.0
export(float) var max_pitch := 85.0
export(float) var interact_distance := 3.0
export(float) var push_offset := 0.71 # Relaxed to 0.71m to close visual gap (User Request).
export(bool) var enable_auto_align := true
export(float) var auto_align_speed := 2.0
export(float) var auto_align_delay := 1.0
export(bool) var enable_cinematic_zoom := true
export(float) var cinematic_zoom_speed := 1.0
export(float) var cinematic_zoom_lerp_speed := 8.0
export(float) var cinematic_zoom_min_fov := 20.0
export(float) var cinematic_zoom_max_fov := 110.0
export(int, LAYERS_3D_PHYSICS) var camera_collision_mask := 1 # Entorno only (pisos/paredes del nivel)
# Stair-stepping Configuration
export(float) var step_height := 0.5
export(float) var step_depth := 0.6
export(bool) var enable_step_up := true
export(float) var step_grounded_grace := 0.22
export(float) var stair_ground_probe_extra := 0.2
export(bool) var debug_stair_state := false
export(float, 0.2, 1.0) var crouch_collider_height_ratio := 0.55
export(float) var crouch_headroom_margin := 0.03

var _step_grounded_timer := 0.0
var _just_stepped := false
var _ground_contact_grace_timer := 0.0
var _last_debug_effective_grounded := true
var _last_debug_on_floor := true
var _body_collision_shape: CollisionShape = null
var _body_capsule_shape: CapsuleShape = null
var _standing_capsule_height := 0.0
var _crouched_capsule_height := 0.0
var _standing_capsule_total_height := 0.0
var _crouched_capsule_total_height := 0.0
var _standing_collision_origin := Vector3.ZERO
var _crouched_collision_origin := Vector3.ZERO

# Platform Transform Tracking
var _platform_collider: Spatial = null
var _platform_last_transform: Transform = Transform.IDENTITY
var _platform_velocity: Vector3 = Vector3.ZERO
var _was_on_platform := false

# Camera State
var base_fov := 75.0
var _cached_cam: Camera = null
var _cached_spring_arm = null
var base_spring_length := 7.0
var base_spring_length_3d := 7.0
var current_spring_length := 7.0
var base_rig_y := 0.0
var base_collision_mask := 0
var _cinematic_zoom_target_fov := -1.0
var _cinematic_zoom_target_cam: Camera = null

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
var _current_zone_request_id: int = -1
const CINEMATIC_ZONE_EXIT_GRACE_TIME := 0.12
var _cinematic_zone_exit_grace_left := 0.0
const CINEMATIC_ZONE_SWITCH_GRACE_TIME := 0.18
var _cinematic_zone_switch_grace_left := 0.0
const PushableBoxV2Script = preload("res://core_v2/components/PushableBoxV2.gd")

var _terminal_ui_active := false
var _restore_spring_length: float = -1.0
var _restore_fov: float = -1.0
var _exit_log_frames := 0
var _perf_disable_interaction_scan := false
var _perf_disable_cinematic_zone_scan := false
var _rl_mode := false
var _rl_fast_controller := false
var _rl_skip_animator := false
var _rl_skip_camera_updates := false
var _rl_skip_platform_tracking := false
var _rl_skip_rigidbody_push := false
var _rl_strip_visual_rig := false
var _rl_step_profile_enabled: bool = false
var _rl_step_profile_every: int = 200
var _rl_step_profile_file: String = "user://anna_rl_step_profile.log"
var _rl_step_profile_count: int = 0
var _rl_step_profile_us_total: int = 0
var _rl_step_profile_us_control: int = 0
var _rl_step_profile_us_move: int = 0
var _rl_step_profile_us_post: int = 0
var _hyper_low_animator_throttle := false
var _hyper_low_animator_tick := 0

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
var _nearby_interactables: Array = []
onready var interact_config = get_node_or_null("Logic/Interact")

# Input
var input_provider
var camera_input_locked := false

func set_camera_input_locked(locked: bool):
	camera_input_locked = locked
	if input_provider:
		input_provider.hardware_input_enabled = not locked

func force_camera_current(_reset_orientation := false):
	if _cached_cam:
		_cached_cam.current = true

func sync_camera_to_rig() -> void:
	if _cached_spring_arm:
		_cached_spring_arm.spring_length = base_spring_length_3d
		current_spring_length = base_spring_length_3d
	if _cached_cam:
		_cached_cam.fov = base_fov
	_cinematic_zoom_target_fov = -1.0

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
		"position": [ self.global_transform.origin.x, self.global_transform.origin.y, self.global_transform.origin.z],
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
	yaw_deg = 0.0
	pitch_deg = 0.0
	rotation = Vector3.ZERO
	
	if is_instance_valid(movement_logic):
		movement_logic.horizontal_velocity = Vector3.ZERO
		movement_logic.wish_direction = Vector3.ZERO
		
	if is_instance_valid(jump_logic):
		jump_logic.internal_velocity = 0.0
		jump_logic.coyote_timer = 0.0
		jump_logic.jump_buffer_timer = 0.0
		jump_logic._is_jumping = false

	if is_instance_valid(animator) and animator.has_method("reset_state"):
		animator.reset_state()

	_clear_cinematic_zone_request()
	_active_cinematic_zone = null
	_prev_active_cinematic_zone = null
	_cinematic_zone_exit_grace_left = 0.0
	_cinematic_zone_switch_grace_left = 0.0
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.force_update_transform()

func _exit_tree() -> void:
	# Ensure we never leave dangling camera requests when player is respawned/freed.
	_clear_cinematic_zone_request()

func _clear_cinematic_zone_request() -> void:
	if _current_zone_request_id != -1 and is_instance_valid(CinematicManager):
		CinematicManager.release_camera_request(_current_zone_request_id)
	_current_zone_request_id = -1

onready var camera_rig = $CameraRig
onready var animator = $Visual/Pivot
onready var _audio_listener = get_node_or_null("AudioListener")

func _env_enabled(name: String, default_value: bool = false) -> bool:
	var raw := OS.get_environment(name)
	if raw == "":
		return default_value
	return raw.to_lower() in ["1", "true", "yes", "on"]

func _ready():
	_rl_mode = _env_enabled("ANNA_RL_MODE", false)
	_rl_fast_controller = _rl_mode and _env_enabled("ANNA_RL_FAST_CONTROLLER", false)
	_rl_strip_visual_rig = _rl_mode and _env_enabled("ANNA_RL_STRIP_VISUAL_RIG", false)
	if _rl_mode:
		_rl_step_profile_enabled = _env_enabled("ANNA_RL_STEP_PROFILE", false)
		var step_profile_every_env = OS.get_environment("ANNA_RL_STEP_PROFILE_EVERY")
		if step_profile_every_env.is_valid_integer():
			var raw_every = int(step_profile_every_env)
			if raw_every < 50: raw_every = 50
			_rl_step_profile_every = raw_every
		var step_profile_file_env = OS.get_environment("ANNA_RL_STEP_PROFILE_FILE")
		if step_profile_file_env.strip_edges() != "":
			_rl_step_profile_file = step_profile_file_env
		if _rl_step_profile_enabled:
			_append_profile_line(_rl_step_profile_file, "[RL_STEP_PROFILE] start")
	if _rl_fast_controller:
		_rl_skip_animator = _env_enabled("ANNA_RL_FAST_DISABLE_ANIMATOR", true)
		_rl_skip_camera_updates = _env_enabled("ANNA_RL_FAST_DISABLE_CAMERA_UPDATES", true)
		_rl_skip_platform_tracking = _env_enabled("ANNA_RL_FAST_DISABLE_PLATFORM_TRACKING", true)
		_rl_skip_rigidbody_push = _env_enabled("ANNA_RL_FAST_DISABLE_RIGID_PUSH", true)
	else:
		# Independent opt-in knobs for RL throughput without changing controller behavior.
		_rl_skip_animator = _rl_mode and _env_enabled("ANNA_RL_SKIP_ANIMATOR", false)
		_rl_skip_camera_updates = _rl_mode and _env_enabled("ANNA_RL_SKIP_CAMERA_UPDATES", false)
		_rl_skip_platform_tracking = _rl_mode and _env_enabled("ANNA_RL_SKIP_PLATFORM_TRACKING", false)
		_rl_skip_rigidbody_push = _rl_mode and _env_enabled("ANNA_RL_SKIP_RIGID_PUSH", false)

	var disable_interaction_env := OS.get_environment("ODISEA_DISABLE_INTERACTION_SCAN").to_lower()
	_perf_disable_interaction_scan = disable_interaction_env in ["1", "true", "yes", "on"]
	var disable_camera_zone_env := OS.get_environment("ODISEA_DISABLE_CAMERAZONE_SCAN").to_lower()
	_perf_disable_cinematic_zone_scan = disable_camera_zone_env in ["1", "true", "yes", "on"]
	if _rl_fast_controller:
		_perf_disable_interaction_scan = true
		_perf_disable_cinematic_zone_scan = true
		enable_step_up = false
		var dust = get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera/SpaceDust")
		if dust and "emitting" in dust:
			dust.emitting = false
		if _rl_skip_animator:
			var anim_tree = get_node_or_null("Visual/Pivot/AnimationTree")
			if anim_tree:
				anim_tree.active = false
	elif _rl_skip_animator:
		var anim_tree_rl = get_node_or_null("Visual/Pivot/AnimationTree")
		if anim_tree_rl:
			anim_tree_rl.active = false
	if _rl_strip_visual_rig:
		_rl_skip_animator = true
		_disable_visual_rig_for_rl()
	if _should_disable_expensive_scans_for_profile():
		_perf_disable_interaction_scan = true
		_perf_disable_cinematic_zone_scan = true
	if _should_disable_step_up_for_profile():
		enable_step_up = false
	_hyper_low_animator_throttle = _should_throttle_animator_for_profile()

	initial_transform = global_transform
	_ensure_required_player_collision_mask()
	add_to_group("player")
	_ensure_player_audio_listener()
	if not is_instance_valid(input_provider):
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
		call_deferred("_ensure_primary_camera_current")
	
	_cached_spring_arm = _find_spring_arm(camera_rig)
	if _cached_spring_arm:
		base_spring_length = _cached_spring_arm.spring_length
		base_spring_length_3d = _cached_spring_arm.spring_length
		current_spring_length = _cached_spring_arm.spring_length
		base_collision_mask = camera_collision_mask if camera_collision_mask > 0 else _cached_spring_arm.collision_mask
		_cached_spring_arm.collision_mask = base_collision_mask
	
	if camera_rig:
		base_rig_y = camera_rig.transform.origin.y
	
	_setup_interact_area()
	_setup_crouch_collision()
	call_deferred("_apply_weak_visual_policy_if_needed_deferred")
	call_deferred("_apply_camera_particle_policy")

func _ensure_required_player_collision_mask() -> void:
	if (collision_mask & PLAYER_REQUIRED_COLLISION_MASK) == 0:
		collision_mask |= PLAYER_REQUIRED_COLLISION_MASK

func _ensure_player_audio_listener() -> void:
	if not (_audio_listener and is_instance_valid(_audio_listener)):
		_audio_listener = Listener.new()
		_audio_listener.name = "AudioListener"
		_audio_listener.transform.origin = Vector3(0, 1.6, 0)
		add_child(_audio_listener)
	if _audio_listener.has_method("make_current"):
		_audio_listener.make_current()

func _should_force_unshaded_player_visuals() -> bool:
	var hp = get_node_or_null("/root/HardwareProfile")
	if hp and hp.has_method("is_weak_hardware") and bool(hp.is_weak_hardware()):
		return true
	if hp and hp.has_method("get_profile"):
		return int(hp.get_profile()) == HARDWARE_PROFILE_LOW
	return false

func _should_reduce_camera_particles() -> bool:
	var hp = get_node_or_null("/root/HardwareProfile")
	if hp and hp.has_method("should_use_reduced_particles"):
		return bool(hp.should_use_reduced_particles())
	if hp and hp.has_method("is_weak_hardware"):
		return bool(hp.is_weak_hardware())
	return false

func _should_disable_step_up_for_profile() -> bool:
	var hp = get_node_or_null("/root/HardwareProfile")
	if hp and hp.has_method("is_hyper_low_mode"):
		return bool(hp.is_hyper_low_mode())
	return false

func _should_disable_expensive_scans_for_profile() -> bool:
	var hp = get_node_or_null("/root/HardwareProfile")
	if hp and hp.has_method("is_hyper_low_mode"):
		return bool(hp.is_hyper_low_mode())
	return false

func _should_throttle_animator_for_profile() -> bool:
	var hp = get_node_or_null("/root/HardwareProfile")
	if hp and hp.has_method("is_hyper_low_mode"):
		return bool(hp.is_hyper_low_mode())
	return false

func _apply_camera_particle_policy() -> void:
	var dust = get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera/SpaceDust")
	if not is_instance_valid(dust):
		return
	var should_reduce = _should_reduce_camera_particles()
	if "emitting" in dust:
		dust.emitting = not should_reduce

func _apply_weak_visual_policy_if_needed_deferred() -> void:
	if not _should_force_unshaded_player_visuals():
		return
	var fake_shadow = get_node_or_null("Visual/Pivot/FakeShadow")
	if fake_shadow and fake_shadow is MeshInstance:
		fake_shadow.visible = true
		fake_shadow.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		if fake_shadow.has_method("set_process"):
			fake_shadow.set_process(true)
		if fake_shadow.has_method("set_physics_process"):
			fake_shadow.set_physics_process(false)
	var pass_count = max(1, PLAYER_WEAK_VISUAL_REAPPLY_FRAMES)
	for i in range(pass_count):
		_force_unshaded_meshes_recursive(get_node_or_null("Visual"))
		if i < pass_count - 1:
			yield(get_tree(), "idle_frame")

func _force_unshaded_meshes_recursive(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is MeshInstance:
		_apply_unshaded_mesh_policy(node as MeshInstance)
	for child in node.get_children():
		if child is Node:
			_force_unshaded_meshes_recursive(child)

func _apply_unshaded_mesh_policy(mesh_node: MeshInstance) -> void:
	if not is_instance_valid(mesh_node):
		return
	var surface_count := mesh_node.get_surface_material_count()
	if surface_count <= 0 and mesh_node.mesh:
		surface_count = mesh_node.mesh.get_surface_count()
	for i in range(surface_count):
		var mat = mesh_node.get_surface_material(i)
		if mat == null and mesh_node.mesh:
			mat = mesh_node.mesh.surface_get_material(i)
		if mat is SpatialMaterial:
			var spatial_mat = mat as SpatialMaterial
			if not spatial_mat.resource_local_to_scene:
				var duplicated = spatial_mat.duplicate()
				if duplicated is SpatialMaterial:
					spatial_mat = duplicated
			spatial_mat.flags_unshaded = true
			spatial_mat.flags_do_not_receive_shadows = true
			mesh_node.set_surface_material(i, spatial_mat)
	mesh_node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF

func _disable_visual_rig_for_rl() -> void:
	var anim_tree = get_node_or_null("Visual/Pivot/AnimationTree")
	if anim_tree and "active" in anim_tree:
		anim_tree.active = false
	var skeleton = get_node_or_null("Visual/Pivot/Skeleton")
	if skeleton:
		skeleton.queue_free()
	var fake_shadow = get_node_or_null("Visual/Pivot/FakeShadow")
	if fake_shadow:
		fake_shadow.queue_free()
	var jump_sfx = get_node_or_null("Visual/Pivot/JumpSFX")
	if jump_sfx:
		jump_sfx.queue_free()
	var footstep = get_node_or_null("Visual/Pivot/FootstepDetector")
	if footstep:
		footstep.queue_free()
	var omni = get_node_or_null("Visual/OmniLight")
	if omni:
		omni.queue_free()
	var dust = get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera/SpaceDust")
	if dust:
		if "emitting" in dust:
			dust.emitting = false
		dust.queue_free()
	if animator:
		animator.set_process(false)
		animator.set_physics_process(false)

func _find_camera(node: Node) -> Camera:
	if node is Camera:
		return node as Camera
	for i in range(node.get_child_count()):
		var cam = _find_camera(node.get_child(i))
		if cam:
			return cam
	return null

func _ensure_primary_camera_current() -> void:
	if not _cached_cam or not is_instance_valid(_cached_cam):
		return
	var viewport_cam = get_viewport().get_camera() if get_viewport() else null
	if viewport_cam == null:
		_cached_cam.current = true
		return
	if viewport_cam == _cached_cam:
		return
	var cam_path = String(viewport_cam.get_path())
	if cam_path.find("/CameraTransition/Camera") != -1 or cam_path.find("/ShaderCacheManager") != -1:
		_cached_cam.current = true

func _find_spring_arm(node: Node) -> Node:
	if node is SpringArm or node.has_method("get_hit_length"):
		return node
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


func align_exit_from_cinematic(target_cam: Camera) -> void:
	"""
	Aligns player rig heading from the cinematic camera but restores the
	player's pitch and zoom (FOV/spring) to third-person defaults.
	"""
	if not target_cam or not is_instance_valid(target_cam):
		return

	var preserved_pitch := pitch
	var preserved_base_fov := base_fov
	var preserved_base_spring := base_spring_length_3d

	# Reuse robust yaw solving from orbit snap.
	snap_rig_to_camera_orbit(target_cam.global_transform.origin, target_cam.fov)

	# Restore player defaults (prefer explicitly saved pre-cinematic values when available).
	var restored_spring := preserved_base_spring
	var restored_fov := preserved_base_fov
	if _restore_spring_length > 0.0:
		restored_spring = _restore_spring_length
	if _restore_fov > 0.0:
		restored_fov = _restore_fov

	base_spring_length_3d = restored_spring
	base_fov = restored_fov

	# Keep cinematic-aligned yaw, but restore player's vertical look.
	pitch = preserved_pitch
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.force_update_transform()
	if _cached_spring_arm:
		current_spring_length = base_spring_length_3d
		_cached_spring_arm.spring_length = base_spring_length_3d
	if _cached_cam:
		_cached_cam.fov = base_fov

	yaw_deg = rad2deg(yaw)
	pitch_deg = rad2deg(pitch)

func _get_move_direction(input_vector: Vector2, mode = -1, camera_basis = null) -> Vector3:
	# print("[PlayerController] _get_move_direction called with mode: %d" % mode)
	if mode == -1:
		if CinematicManager.is_input_latched():
			mode = CinematicManager.latched_control_mode
		else:
			mode = CinematicManager.get_control_mode()
		
	if camera_basis == null:
		# Pass input magnitude to allow Latch release check
		camera_basis = CinematicManager.get_movement_basis(input_vector.length())

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
	_interact_area.collision_mask = 255
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

func _setup_crouch_collision() -> void:
	var body_shape = get_node_or_null("CollisionShape")
	if body_shape == null:
		for child in get_children():
			if child is CollisionShape:
				body_shape = child
				break
	if body_shape == null:
		return
	if not (body_shape.shape is CapsuleShape):
		return
	var unique_shape = body_shape.shape.duplicate()
	body_shape.shape = unique_shape
	_body_collision_shape = body_shape
	_body_capsule_shape = body_shape.shape as CapsuleShape
	if not _body_capsule_shape:
		return
	_standing_capsule_height = max(0.1, _body_capsule_shape.height)
	_crouched_capsule_height = max(0.1, _standing_capsule_height * clamp(crouch_collider_height_ratio, 0.2, 1.0))
	_standing_capsule_total_height = _standing_capsule_height + (_body_capsule_shape.radius * 2.0)
	_crouched_capsule_total_height = _crouched_capsule_height + (_body_capsule_shape.radius * 2.0)
	_standing_collision_origin = _body_collision_shape.transform.origin
	var half_delta = (_standing_capsule_total_height - _crouched_capsule_total_height) * 0.5
	_crouched_collision_origin = _standing_collision_origin + Vector3(0, -half_delta, 0)
	_apply_crouch_collision_state(false)

func _apply_crouch_collision_state(crouched: bool) -> void:
	if not _body_capsule_shape or not _body_collision_shape:
		return
	var target_height = _crouched_capsule_height if crouched else _standing_capsule_height
	var target_origin = _crouched_collision_origin if crouched else _standing_collision_origin
	if abs(_body_capsule_shape.height - target_height) <= 0.0001:
		var same_origin = _body_collision_shape.transform.origin.distance_squared_to(target_origin) <= 0.000001
		if same_origin:
			return
	_body_capsule_shape.height = target_height
	var shape_transform = _body_collision_shape.transform
	shape_transform.origin = target_origin
	_body_collision_shape.transform = shape_transform

func _resolve_crouch_state(wants_crouch: bool) -> bool:
	if wants_crouch:
		return true
	if is_crouching and not _has_headroom_to_stand():
		return true
	return false

func _has_headroom_to_stand() -> bool:
	if not _body_capsule_shape or not _body_collision_shape:
		return true
	var stand_total = _standing_capsule_total_height
	if stand_total <= 0.0:
		stand_total = _standing_capsule_height + (_body_capsule_shape.radius * 2.0)
	var crouch_total = _crouched_capsule_total_height
	if crouch_total <= 0.0:
		crouch_total = _crouched_capsule_height + (_body_capsule_shape.radius * 2.0)
	var extra_height = stand_total - crouch_total
	if extra_height <= 0.001:
		return true
	var world_shape: Transform = global_transform * _body_collision_shape.transform
	var center = world_shape.origin
	var horizontal_radius = max(0.02, _body_capsule_shape.radius - crouch_headroom_margin)
	var start_y = center.y + (crouch_total * 0.5) - crouch_headroom_margin
	var end_y = start_y + extra_height + crouch_headroom_margin
	var space_state = get_world().direct_space_state
	var offsets = [
		Vector3.ZERO,
		global_transform.basis.x * horizontal_radius,
		-global_transform.basis.x * horizontal_radius,
		global_transform.basis.z * horizontal_radius,
		-global_transform.basis.z * horizontal_radius
	]
	for offset in offsets:
		var from = Vector3(center.x + offset.x, start_y, center.z + offset.z)
		var to = Vector3(center.x + offset.x, end_y, center.z + offset.z)
		var hit = space_state.intersect_ray(from, to, [ self ], collision_mask)
		if not hit.empty():
			return false
	return true

func _process_interaction(input: InputDataV2):
	if _perf_disable_interaction_scan:
		_clear_interactable()
		return
	if not _interact_area: return
	var bodies = _interact_area.get_overlapping_bodies()
	var best_target = null
	var min_dist = 999.0
	for body in bodies:
		if is_instance_valid(body) and body.is_in_group("interactable"):
			if "is_interactable" in body and not body.is_interactable:
				continue
			var dist = global_transform.origin.distance_squared_to(body.global_transform.origin)
			if dist < min_dist:
				min_dist = dist
				best_target = body

	var h_color = Color.cyan
	var p_color = Color(0, 1, 1, 0.15)
	var p_radius_sq = 36.0 # 6m default
	if interact_config:
		h_color = interact_config.highlight_color
		p_color = interact_config.proximity_color
		p_radius_sq = interact_config.proximity_radius * interact_config.proximity_radius

	if best_target:
		if _current_interactable != best_target:
			# Clear highlight from previous target
			if _current_interactable and is_instance_valid(_current_interactable):
				_current_interactable.set_highlighted(false)
			
			_current_interactable = best_target
			var text = best_target.interaction_text if best_target.get("interaction_text") else "Interact"
			emit_signal("interactable_in_range", text)
			
			# Apply full highlight to new target
			best_target.set_highlighted(true, h_color)
			# Ensure it doesn't have proximity glow if it's the main target
			if best_target.has_method("set_proximity_highlight"):
				best_target.set_proximity_highlight(false)
			
			var can_auto_trigger = not best_target.get("_auto_triggered") or not best_target.get("one_off")
			if best_target.get("auto_interact") and not best_target.is_active and can_auto_trigger:
				if best_target.has_method("set_active"):
					best_target.set_active(true)
					best_target._auto_triggered = true
		if input.interact and best_target.has_method("interact"):
			best_target.interact()
	else:
		_clear_interactable()

	# --- Proximity Glow Logic ---
	# Handle objects that are nearby but not the current best_target
	var all_interactables = get_tree().get_nodes_in_group("interactable")
	var new_nearby = []
	for obj in all_interactables:
		if not is_instance_valid(obj) or obj == _current_interactable:
			continue
		
		if "is_interactable" in obj and not obj.is_interactable:
			continue
		
		# Proximity check
		var d_sq = global_transform.origin.distance_squared_to(obj.global_transform.origin)
		if d_sq < p_radius_sq:
			new_nearby.append(obj)
			if not obj in _nearby_interactables:
				if obj.has_method("set_proximity_highlight"):
					obj.set_proximity_highlight(true, p_color)
	
	# Clear proximity from objects no longer nearby
	for obj in _nearby_interactables:
		if is_instance_valid(obj) and not obj in new_nearby and obj != _current_interactable:
			if obj.has_method("set_proximity_highlight"):
				obj.set_proximity_highlight(false)
	
	_nearby_interactables = new_nearby

func _clear_interactable():
	if _current_interactable != null:
		if not _current_interactable.get("one_off"):
			_current_interactable._auto_triggered = false
		
		# Remove highlight when going out of range
		_current_interactable.set_highlighted(false)
		
		# Restore proximity glow if still nearby
		if interact_config and is_instance_valid(_current_interactable):
			var d_sq = global_transform.origin.distance_squared_to(_current_interactable.global_transform.origin)
			if d_sq < (interact_config.proximity_radius * interact_config.proximity_radius):
				if _current_interactable.has_method("set_proximity_highlight"):
					_current_interactable.set_proximity_highlight(true, interact_config.proximity_color)

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
	target.crouch = target.crouch or source.crouch
	target.interact = target.interact or source.interact

func _update_push_state(_dt: float, input: InputDataV2):
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
		if is_instance_valid(body) and body.is_in_group("pushable"):
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
				var result = space_state.intersect_ray(from, to_input, [ self ])
				
				if not result or result.collider != best_target:
					var to_center = best_target.global_transform.origin
					result = space_state.intersect_ray(from, to_center, [ self ])
				
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
						# Pro-actively wake up the box if it has settled into Kinematic mode
						if best_target.has_method("wake_up"):
							best_target.wake_up()
							
						# Visual Anchoring: Calculate discrepancy from ideal push_offset (0.71m)
						visual_push_correction = max(0.0, push_offset - surf_dist)
					else:
						visual_push_correction = 0.0
				else:
					push_normal = - dir_to_box
					visual_push_correction = 0.0
				
				_push_target = best_target

func step(dt: float, input: InputDataV2) -> void:
	if input == null: return
	var prof_enabled := _rl_step_profile_enabled
	var prof_t0 := 0
	var prof_t_control := 0
	var prof_t_move := 0
	if prof_enabled:
		prof_t0 = OS.get_ticks_usec()

	if _rl_fast_controller and _rl_skip_rigidbody_push:
		_was_pushing = is_pushing
		is_pushing = false
		visual_push_correction = 0.0
		_push_target = null
	else:
		_update_push_state(dt, input)
	var motion_grounded := is_effectively_grounded()
	if _rl_fast_controller:
		motion_grounded = is_on_floor() or _just_stepped or _step_grounded_timer > 0.0
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
		input_provider.joy_look_sensitivity = joy_look_sensitivity
		input_provider.joy_move_sensitivity = joy_move_sensitivity
		# hardware_look_sensitivity can be 1.0 or tied to mouse_sensitivity if needed

	if camera_input_locked and input_provider:
		input_provider.hardware_input_enabled = false
	if _terminal_ui_active:
		input.move_vec = Vector2.ZERO
		input.jump = false
		input.sprint = false

	if not _rl_fast_controller:
		_process_interaction(input)

	if physics_grounded and velocity.y < 0 and movement_logic.get_horizontal_velocity().y <= 0:
		velocity.y = 0
		if is_instance_valid(jump_logic):
			jump_logic.set_internal_velocity(0.0)

	# Camera Orbit Logic (Third Person)
	# In fast RL mode, skip CinematicManager checks and use a direct yaw/pitch update path.
	if _rl_fast_controller:
		if input and input.mouse_delta:
			yaw -= input.mouse_delta.x * mouse_sensitivity
			var mouse_y_fast = - input.mouse_delta.y if invert_mouse_y else input.mouse_delta.y
			pitch -= mouse_y_fast * mouse_sensitivity
		pitch = clamp(pitch, deg2rad(min_pitch), deg2rad(max_pitch))
		if abs(input.zoom_delta) > 0.01:
			base_spring_length_3d = clamp(base_spring_length_3d + input.zoom_delta, 2.0, 50.0)
		if input.fov_override > 0.0:
			base_fov = input.fov_override
	else:
		# Only update orbit if NOT in a camera zone (or if using FREE mode inside a zone)
		var active_zone_mode = CinematicManager.get_control_mode()
		if active_zone_mode == CinematicManager.ControlMode.FREE:
			if input:
				movement_logic.update_tank_mode(dt, input.mouse_delta, input.move_vec, input.jump, input.sprint, input.hardware_mouse_active)
				# Apply hardware input directly
				yaw -= input.mouse_delta.x * mouse_sensitivity
				var mouse_y = - input.mouse_delta.y if invert_mouse_y else input.mouse_delta.y
				pitch -= mouse_y * mouse_sensitivity
				yaw += movement_logic.get_tank_yaw_delta(dt, input.move_vec)
				
				# Auto-align camera behind player if strafing without mouse input
				if enable_auto_align and not movement_logic.is_tank_turn_mode:
					if movement_logic.camera_input_timer > auto_align_delay:
						var wish_dir = movement_logic.wish_direction
						if wish_dir.length_squared() > 0.5:
							var target_yaw = atan2(-wish_dir.x, -wish_dir.z)
							yaw = lerp_angle(yaw, target_yaw, auto_align_speed * dt)
							
			pitch = clamp(pitch, deg2rad(min_pitch), deg2rad(max_pitch))

		var active_cam = CinematicManager.get_active_camera()
		var can_zoom_cinematic = enable_cinematic_zoom and active_cam and is_instance_valid(active_cam) and active_cam != _cached_cam
		if can_zoom_cinematic:
			if _cinematic_zoom_target_cam != active_cam:
				_cinematic_zoom_target_cam = active_cam
				_cinematic_zoom_target_fov = active_cam.fov

			if abs(input.zoom_delta) > 0.01:
				_cinematic_zoom_target_fov = clamp(
					_cinematic_zoom_target_fov + (input.zoom_delta * cinematic_zoom_speed),
					cinematic_zoom_min_fov,
					cinematic_zoom_max_fov
				)

			var zoom_t = clamp(cinematic_zoom_lerp_speed * dt, 0.0, 1.0)
			active_cam.fov = lerp(active_cam.fov, _cinematic_zoom_target_fov, zoom_t)
		else:
			_cinematic_zoom_target_cam = null
			_cinematic_zoom_target_fov = -1.0
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
	if not _rl_fast_controller and not _perf_disable_cinematic_zone_scan:
		_update_cinematic_zone_detection(input, dt)
	
	# --- MOVEMENT ---
	if prof_enabled:
		prof_t_control = OS.get_ticks_usec()
	var move_vec = input.move_vec
	# Calculate World Direction based on Control Mode (or Latch)
	# Logic delegated to CinematicManager (FSM)
	var world_dir: Vector3 = _get_move_direction(move_vec)
	if _rl_fast_controller:
		world_dir = _get_move_direction_rl_fast(move_vec)

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
	
	var wants_crouch = input.crouch and physics_grounded
	is_crouching = _resolve_crouch_state(wants_crouch)
	_apply_crouch_collision_state(is_crouching)
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
	
	if enable_step_up and (not _rl_fast_controller) and is_on_floor() and velocity.y <= 0:
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
	if _rl_fast_controller and _rl_skip_platform_tracking:
		_platform_velocity = Vector3.ZERO
	else:
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
	if not (_rl_fast_controller and _rl_skip_rigidbody_push):
		for i in get_slide_count():
			var collision = get_slide_collision(i)
			var body = collision.collider
			if is_instance_valid(body) and body is RigidBody:
				touched_rigid = true
				if body is RigidBody:
					if abs(collision.normal.y) < 0.5:
						var impulse = - collision.normal * push_force * dt
						body.apply_central_impulse(impulse)
	
	if _was_touching_rigid and not touched_rigid:
		emit_signal("rigid_contact_ended")
	_was_touching_rigid = touched_rigid
	if prof_enabled:
		prof_t_move = OS.get_ticks_usec()

	var should_step_animator := true
	var animator_dt := dt
	if _hyper_low_animator_throttle:
		_hyper_low_animator_tick += 1
		if _hyper_low_animator_tick >= HYPER_LOW_ANIMATOR_STEP_INTERVAL_FRAMES:
			_hyper_low_animator_tick = 0
			animator_dt = dt * float(HYPER_LOW_ANIMATOR_STEP_INTERVAL_FRAMES)
		else:
			should_step_animator = false

	if should_step_animator and (not _rl_skip_animator) and animator and animator.has_method("step_animator"):
		var anim_vel = velocity
		if not movement_logic.external_source_is_static:
			anim_vel = velocity - movement_logic.external_velocity
		animator.step_animator(animator_dt, anim_vel)
		
	movement_logic.external_source_is_static = true

	# Update Camera SpringArm (for Third Person view)
	# Even if not active, we keep it updated
	if (not _rl_skip_camera_updates) and _cached_spring_arm:
		current_spring_length = lerp(current_spring_length, base_spring_length_3d, 4.0 * dt)
		_cached_spring_arm.spring_length = current_spring_length
	
	if (not _rl_skip_camera_updates) and _cached_cam and abs(_cached_cam.fov - base_fov) > 0.01:
		_cached_cam.fov = lerp(_cached_cam.fov, base_fov, 4.0 * dt)
	if prof_enabled:
		_rl_step_profile_add(prof_t0, prof_t_control, prof_t_move, OS.get_ticks_usec())

func _rl_step_profile_add(t0: int, t_control: int, t_move: int, t_end: int) -> void:
	if t0 <= 0:
		return
	if t_control <= 0:
		t_control = t0
	if t_move <= 0:
		t_move = t_control
	_rl_step_profile_count += 1
	var diff_total = t_end - t0
	if diff_total < 0: diff_total = 0
	_rl_step_profile_us_total += diff_total

	var diff_control = t_control - t0
	if diff_control < 0: diff_control = 0
	_rl_step_profile_us_control += diff_control

	var diff_move = t_move - t_control
	if diff_move < 0: diff_move = 0
	_rl_step_profile_us_move += diff_move

	var diff_post = t_end - t_move
	if diff_post < 0: diff_post = 0
	_rl_step_profile_us_post += diff_post
	if _rl_step_profile_count % _rl_step_profile_every != 0:
		return
	var n := float(_rl_step_profile_every)
	var line = "[RL_STEP_PROFILE] control=%.1fus move=%.1fus post=%.1fus total=%.1fus" % [
		_rl_step_profile_us_control / n,
		_rl_step_profile_us_move / n,
		_rl_step_profile_us_post / n,
		_rl_step_profile_us_total / n
	]
	_append_profile_line(_rl_step_profile_file, line)
	_rl_step_profile_us_total = 0
	_rl_step_profile_us_control = 0
	_rl_step_profile_us_move = 0
	_rl_step_profile_us_post = 0

func _append_profile_line(path: String, line: String) -> void:
	var f := File.new()
	var err = ERR_CANT_OPEN
	if f.file_exists(path):
		err = f.open(path, File.READ_WRITE)
		if err == OK:
			f.seek_end()
	else:
		err = f.open(path, File.WRITE)
	if err != OK:
		return
	f.store_line(line)
	f.close()
		
func _update_cinematic_zone_detection(_input: InputDataV2, dt: float = 1.0 / 60.0):
	var all_zones = get_tree().get_nodes_in_group("CameraZoneV2")
	var best_zone: Node = null
	var min_volume = INF
	var current_zone: Node = _active_cinematic_zone

	for zone in all_zones:
		if zone.is_zone_active and zone.is_body_in_zone(self ):
			# Simple volume comparison for priority (smaller = higher priority)
			var vol = zone.get_volume() if zone.has_method("get_volume") else 1000.0
			if vol < min_volume:
				min_volume = vol
				best_zone = zone
			elif abs(vol - min_volume) <= 0.0001:
				# Deterministic tie-break: prefer current zone if still valid,
				# then stable lexical NodePath (instance_id is not deterministic across reloads).
				if zone == current_zone and best_zone != current_zone:
					best_zone = zone
				elif best_zone != current_zone:
					var zone_path = str(zone.get_path()) if zone.is_inside_tree() else zone.name
					var best_path = str(best_zone.get_path()) if best_zone and best_zone.is_inside_tree() else (best_zone.name if best_zone else "")
					if zone_path < best_path:
						best_zone = zone

	var resolved_zone: Node = best_zone
	if resolved_zone != null:
		_cinematic_zone_exit_grace_left = CINEMATIC_ZONE_EXIT_GRACE_TIME
		var current_still_inside: bool = (
			current_zone != null
			and is_instance_valid(current_zone)
			and current_zone.is_zone_active
			and current_zone.is_body_in_zone(self )
		)
		if current_still_inside and resolved_zone != current_zone:
			# Hold current zone briefly to avoid ping-pong between overlapping boundaries.
			if _cinematic_zone_switch_grace_left > 0.0:
				_cinematic_zone_switch_grace_left = max(0.0, _cinematic_zone_switch_grace_left - dt)
				resolved_zone = current_zone
			else:
				# Allow switch now, and prime grace for next border crossing.
				_cinematic_zone_switch_grace_left = CINEMATIC_ZONE_SWITCH_GRACE_TIME
		else:
			_cinematic_zone_switch_grace_left = CINEMATIC_ZONE_SWITCH_GRACE_TIME
	elif _active_cinematic_zone != null and _cinematic_zone_exit_grace_left > 0.0:
		# Keep the previous zone briefly to prevent enter/exit flicker near bounds.
		_cinematic_zone_exit_grace_left = max(0.0, _cinematic_zone_exit_grace_left - dt)
		resolved_zone = _active_cinematic_zone
		_cinematic_zone_switch_grace_left = max(0.0, _cinematic_zone_switch_grace_left - dt)
	else:
		_cinematic_zone_exit_grace_left = 0.0
		_cinematic_zone_switch_grace_left = 0.0

	_active_cinematic_zone = resolved_zone

	if _active_cinematic_zone != _prev_active_cinematic_zone:
		# FSM-based Transition Logic
		if _active_cinematic_zone:
			# If we switched zones, release the previous request first.
			# Otherwise stale requests remain active and can keep the camera locked
			# after leaving the latest zone.
			if _current_zone_request_id != -1:
				CinematicManager.release_camera_request(_current_zone_request_id)
				_current_zone_request_id = -1

			# Enter Zone
			var rig = _active_cinematic_zone._rig_node
			if rig:
				var trans_time = rig.transition_time if "transition_time" in rig else 0.0
				var payload = {
					"rig": rig,
					"transition_time": trans_time,
					"latch_on_enter": _active_cinematic_zone.get("latch_on_enter"),
					"latch_on_exit": _active_cinematic_zone.get("latch_on_exit")
				}
				_current_zone_request_id = CinematicManager.request_camera_mode(
					_active_cinematic_zone.control_mode,
					payload,
					"zone_" + _active_cinematic_zone.name,
					5
				)
		else:
			# Exit Zone
			if _current_zone_request_id != -1:
				CinematicManager.release_camera_request(_current_zone_request_id)
				_current_zone_request_id = -1
			
			# Recovery of local spring/fov state
			if _restore_spring_length > 0.0:
				base_spring_length_3d = _restore_spring_length
				base_fov = _restore_fov
				_restore_spring_length = -1.0
				_restore_fov = -1.0
		
	# --- CINEMATIC RECOVERY FALLBACK ---
	# If no zone is current, but CinematicManager is still active (and we don't have a request),
	# it means something else (script/system) is controlling it, OR we are in a bad state.
	# We only force deactivate if WE think we should be in control (FREE mode) but CinematicManager is stuck.
	# With the new Request system, this fallback is less critical as releasing requests handles it.
	# We retain a basic check: If we have no active zone request, and CinematicManager is active,
	# we assume it's valid (another system). We don't force deactivate anymore.
	
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
		var hit = space_state.intersect_ray(from, to, [ self ], 1) # Terrain only (Mask 1)
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
	var old_mask = collision_mask
	collision_mask = 1 # Force terrain-only detection (Mask 1)
	
	var result = {"stepped": false, "position": global_transform.origin}
	var can_try_step := motion.length_squared() >= 0.0001
	var horizontal_motion := Vector3.ZERO
	var move_dir := Vector3.ZERO
	var origin := global_transform.origin
	var probe_distance := 0.0
	var advanced_x := Vector3.ZERO
	var check_pos := origin

	if can_try_step:
		horizontal_motion = Vector3(motion.x, 0, motion.z)
		if horizontal_motion.length_squared() < 0.0001:
			can_try_step = false

	if can_try_step:
		move_dir = horizontal_motion.normalized()
		probe_distance = clamp(motion.length(), 0.05, step_depth)
		var foot_collision = move_and_collide(move_dir * probe_distance, true, true, true)
		if foot_collision == null or foot_collision.normal.y > 0.7:
			can_try_step = false

	if can_try_step:
		var head_collision = move_and_collide(Vector3.UP * step_height, true, true, true)
		if head_collision != null:
			can_try_step = false

	if can_try_step:
		var step_up_pos = origin + Vector3.UP * step_height
		var old_pos = global_transform.origin
		global_transform.origin = step_up_pos
		var forward_test = move_and_collide(move_dir * probe_distance, true, true, true)
		advanced_x = move_dir * probe_distance
		if forward_test:
			advanced_x = forward_test.travel
		check_pos = step_up_pos + advanced_x
		global_transform.origin = check_pos
		var down_collision = move_and_collide(Vector3.DOWN * (step_height + 0.1), true, true, true)
		global_transform.origin = old_pos
		if down_collision != null and down_collision.normal.y > 0.7:
			var step_surface_y = check_pos.y - down_collision.travel.length()
			var height_gain = step_surface_y - origin.y
			# Allow a tiny tolerance for collision rounding around configured step height.
			if height_gain > 0.01 and height_gain <= step_height + 0.02:
				result.stepped = true
				result.position = Vector3(origin.x + advanced_x.x, step_surface_y, origin.z + advanced_x.z)
		
	collision_mask = old_mask # Restore original mask
	return result

func _physics_process(_delta):
	if _exit_log_frames > 0:
		_exit_log_frames -= 1
	if is_replay_mode:
		# During SessionManager-driven recording/replay, physics stepping is centralized there.
		# For standalone tests with manual external_input, keep local stepping enabled.
		var sm = get_node_or_null("/root/SessionManager")
		if sm and sm.player == self:
			if sm.is_recording:
				return
			if sm.is_replaying and not external_input_provided:
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

func _get_move_direction_rl_fast(input_vector: Vector2) -> Vector3:
	var basis_fast = camera_rig.global_transform.basis if camera_rig else global_transform.basis
	var forward = - basis_fast.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3.FORWARD
	var right = basis_fast.x
	right.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()
	else:
		right = Vector3.RIGHT
	return right * input_vector.x + forward * (-input_vector.y)

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
