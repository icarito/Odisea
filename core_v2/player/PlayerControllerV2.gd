extends KinematicBody

const InputProviderV2 = preload("../input/InputProviderV2.gd")
const InputDataV2 = preload("../input/InputDataV2.gd")
const PlayerJumpV2 = preload("PlayerJumpV2.gd")
const PlayerMovementV2 = preload("PlayerMovementV2.gd")
const ZeroGravitySettingsV2 = preload("ZeroGravitySettings.gd")
const TraversalLogicV2 = preload("traversal/TraversalLogicV2.gd")

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP
const PLAYER_REQUIRED_COLLISION_MASK := 1 << 6 # Layer 7
const STEP_SUPPORT_COLLISION_MASK := (1 << 0) | (1 << 1) | (1 << 6) # Worldspawn, gameplay floors and structural props.
const PLAYER_WEAK_VISUAL_REAPPLY_FRAMES := 24
const HARDWARE_PROFILE_LOW := 1
const HYPER_LOW_ANIMATOR_STEP_INTERVAL_FRAMES := 5
const PLATFORM_TRACKING_MAX_DELTA := 120.0

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
var traversal_jump_vertical_multiplier := 1.05
var traversal_jump_push_force := 2.8
var traversal_jump_detach_distance := 0.18
var traversal_camera_collision_grace := 0.22
var ledge_regrab_cooldown_time_above := 0.7
var ledge_regrab_cooldown_time_below := 0.4
var hang_drop_push_force := 1.2
var hang_drop_vertical_velocity := 0.35
var ladder_regrab_cooldown_time := 0.2
export(bool) var enable_auto_align := true
export(float) var auto_align_speed := 2.0
export(float) var auto_align_delay := 1.0
export(bool) var enable_cinematic_zoom := true
export(float) var cinematic_zoom_speed := 1.0
export(float) var cinematic_zoom_lerp_speed := 8.0
export(float) var cinematic_zoom_min_fov := 20.0
export(float) var cinematic_zoom_max_fov := 110.0
export(float) var orbit_zoom_min_length := 0.75
export(float) var orbit_zoom_max_length := 50.0
export(int, LAYERS_3D_PHYSICS) var camera_collision_mask := 129 # Entorno + CameraCollision
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
var _platform_tracking_key := ""

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

# Camera Rig Vertical Follow (smooth Y-lag during jumps)
export(float, 0.5, 12.0, 0.1) var camera_rig_y_follow_speed := 2.5   # lerp weight when airborne while rising (lower = more lag)
export(float, 1.0, 40.0, 0.5) var camera_rig_y_ground_snap_speed := 18.0 # lerp weight when grounded (fast catch-up)
export(float, 0.5, 20.0, 0.1) var camera_rig_y_fall_follow_speed := 4.5
export(float, 0.5, 6.0, 0.1) var camera_rig_y_max_lag := 2.0  # max Y-offset the rig can lag behind target
export(float, 0.5, 20.0, 0.1) var camera_rig_step_snap_speed := 7.5 # gentler catch-up immediately after stair-step motion
export(float, 0.0, 0.5, 0.01) var camera_rig_jump_lazy_delay := 0.16
export(float, 0.0, 2.0, 0.01) var camera_rig_jump_lazy_deadzone := 0.85
export(float) var ots_camera_follow_start_length := 3.2
export(float) var ots_camera_follow_full_length := 1.0
export(float, 1.0, 40.0, 0.5) var ots_camera_follow_speed := 18.0
export(float, 0.5, 20.0, 0.1) var ots_camera_follow_blend_speed := 8.0
var _camera_rig_y_smoothed_global := 0.0 # smoothed global-Y for the camera pivot
var _camera_rig_y_initialized := false
var _camera_rig_airborne_anchor_global := 0.0
var _camera_rig_airborne_rise_time := 0.0
var _camera_rig_was_grounded := true
var _ots_camera_follow_weight := 0.0

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
var _push_correction_smoothed: float = 0.0

var _push_target: Spatial = null
var _ledge_regrab_cooldown := 0.0
var _ladder_regrab_cooldown := 0.0
var _jump_was_pressed := false
var _crouch_was_pressed := false
var _camera_collision_grace_left := 0.0
var _traversal_strafe_latch_active := false
var _traversal_strafe_release_coyote_left := 0.0
var _traversal_exit_yaw_target := 0.0
var _traversal_exit_yaw_target_active := false


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
var _post_teleport_snap_frames := 0
var _transition_airlock_placed := false
var _transition_snap_suppressed_until := 0  # physics frame counter
var _ots_snap_on_arrival := false
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
var _current_interaction_prompt := ""
var _nearby_interactables: Array = []
var _cached_all_interactables: Array = []
var _interactables_cache_frames: int = 30
onready var interact_config = get_node_or_null("Logic/Interact")

const INTERACT_ACTION_NAME := "interact"
const FOCUS_ACTION_NAME := "focus"
const DEFAULT_ACTION_HINTS := {
	"interact": "[F]",
	"focus": "[Z]"
}

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

func snap_camera_to_current_state() -> void:
	# If AirlockManager already placed the player, suppress full camera snaps
	# until SessionManager has restored yaw/pitch/spring from transition state.
	# Use a frame counter so ALL calls within the same physics frame are suppressed
	# (SessionManager may call snap multiple times per transition).
	if _transition_airlock_placed:
		if Engine.get_physics_frames() <= _transition_snap_suppressed_until:
			return
		snap_ots_on_arrival_if_pending()
		_transition_airlock_placed = false
	# Called after scene transition + teleport so every lerp-based camera system
	# starts from the correct final position rather than drifting from defaults.

	# Re-anchor camera rig Y to the player's post-teleport world position.
	if camera_rig and _camera_rig_y_initialized:
		_camera_rig_y_smoothed_global = global_transform.origin.y + base_rig_y
		_camera_rig_airborne_anchor_global = _camera_rig_y_smoothed_global
		_camera_rig_airborne_rise_time = 0.0
		_camera_rig_was_grounded = true
		camera_rig.transform.origin.y = _camera_rig_y_smoothed_global - global_transform.origin.y

	# Snap spring arm to target length. If collision grace is active (airlock
	# transition), skip the collision cast — the arm starts at full length and
	# physics_process handles retraction with collision mask zeroed for the grace
	# period, avoiding a snap-to-wall yank when the player is inside the airlock.
	if _cached_spring_arm:
		current_spring_length = base_spring_length_3d
		_cached_spring_arm.spring_length = base_spring_length_3d
		# Stamp current_length directly — never call snap_collision_to_scene here.
		# On scene entry the scene geometry may not be stable yet, so a collision
		# cast returns hit=-1 (open horizon) or hits a stale occluder, both of
		# which would yank the arm to an incorrect length in a single frame.
		# physics_process lerp handles gradual retraction once the scene settles.
		if "current_length" in _cached_spring_arm:
			_cached_spring_arm.current_length = base_spring_length_3d

	# Snap camera FOV.
	if _cached_cam:
		_cached_cam.fov = base_fov

	# OTS arrival snap is handled by SessionManager after it restores the
	# transition spring arm length. This function keeps a fallback for later calls
	# after the suppression window has lifted.

func snap_ots_on_arrival_if_pending() -> void:
	if not _ots_snap_on_arrival:
		return
	var ots = get_node_or_null("Logic/OverTheShoulder")
	if is_instance_valid(ots) and ots.has_method("snap_to_current_state"):
		ots.snap_to_current_state()
	_ots_snap_on_arrival = false

func ensure_input_provider():
	if not input_provider or not is_instance_valid(input_provider):
		input_provider = InputProviderV2.new()

var jump_logic: PlayerJumpV2
var movement_logic: PlayerMovementV2
var traversal_logic: TraversalLogicV2
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
	var cm = get_node_or_null("ControllerManager")
	if cm:
		snapshot["controller_mode"] = cm.current_mode
	if has_node("/root/GravityWorld"):
		var gravity_world = get_node("/root/GravityWorld")
		if gravity_world and gravity_world.has_method("get_gravity_mode_at"):
			snapshot["gravity_mode"] = gravity_world.get_gravity_mode_at(global_transform.origin)
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
		
	if data.has("controller_mode"):
		var cm = get_node_or_null("ControllerManager")
		if cm and cm.has_method("switch_to"):
			cm.switch_to(data["controller_mode"])
	if data.has("gravity_mode") and has_node("/root/GravityWorld"):
		var gravity_world = get_node("/root/GravityWorld")
		if gravity_world and gravity_world.has_method("set_gravity_mode"):
			gravity_world.set_gravity_mode(int(data["gravity_mode"]))
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
		camera_rig.transform.basis = camera_basis_prefix * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.transform.origin.y = base_rig_y
		camera_rig.force_update_transform()
		_camera_rig_y_smoothed_global = global_transform.origin.y + base_rig_y
		_camera_rig_y_initialized = true
		_camera_rig_airborne_anchor_global = _camera_rig_y_smoothed_global
		_camera_rig_airborne_rise_time = 0.0
		_camera_rig_was_grounded = true

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
		camera_rig.transform.basis = camera_basis_prefix * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.transform.origin.y = base_rig_y
		camera_rig.force_update_transform()
		_camera_rig_y_smoothed_global = global_transform.origin.y + base_rig_y
		_camera_rig_y_initialized = true
		_camera_rig_airborne_anchor_global = _camera_rig_y_smoothed_global
		_camera_rig_airborne_rise_time = 0.0
		_camera_rig_was_grounded = true

func _sync_movement_state_after_traversal(horizontal_velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_instance_valid(movement_logic):
		return
	movement_logic.horizontal_velocity = Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z)
	movement_logic.wish_direction = Vector3.ZERO

func _begin_post_traversal_strafe_latch(surface_normal: Vector3, exit_input: Vector2) -> void:
	var face_dir = surface_normal.normalized() if surface_normal.length_squared() > 0.001 else Vector3.ZERO
	if face_dir != Vector3.ZERO:
		_traversal_exit_yaw_target = atan2(-face_dir.x, -face_dir.z)
		_traversal_exit_yaw_target_active = true
	if is_instance_valid(movement_logic):
		movement_logic.is_tank_turn_mode = false
		movement_logic.camera_input_timer = 0.0
		movement_logic.current_turn_time = 0.0
		movement_logic._mouse_used_this_move = false
	var release_coyote := traversal_logic.post_traversal_strafe_release_coyote_time if traversal_logic else 0.14
	_traversal_strafe_latch_active = true
	_traversal_strafe_release_coyote_left = release_coyote

func _update_post_traversal_strafe_latch(dt: float, input: InputDataV2) -> void:
	if not _traversal_strafe_latch_active:
		return
	var deadzone := traversal_logic.post_traversal_strafe_latch_deadzone if traversal_logic else 0.1
	var release_coyote := traversal_logic.post_traversal_strafe_release_coyote_time if traversal_logic else 0.14
	if input == null or input.move_vec.length() <= deadzone:
		_traversal_strafe_release_coyote_left = max(0.0, _traversal_strafe_release_coyote_left - dt)
		if _traversal_strafe_release_coyote_left <= 0.0:
			_traversal_strafe_latch_active = false
		return
	_traversal_strafe_release_coyote_left = release_coyote
	if is_instance_valid(movement_logic):
		movement_logic.is_tank_turn_mode = false
		movement_logic.camera_input_timer = 0.0
		movement_logic.current_turn_time = 0.0
		movement_logic._mouse_used_this_move = false

func _update_post_traversal_exit_alignment(dt: float) -> void:
	if not _traversal_exit_yaw_target_active:
		return
	var align_speed := traversal_logic.post_traversal_face_wall_speed if traversal_logic else 8.0
	yaw = lerp_angle(yaw, _traversal_exit_yaw_target, clamp(align_speed * dt, 0.0, 1.0))
	yaw_deg = rad2deg(yaw)
	if abs(wrapf(_traversal_exit_yaw_target - yaw, -PI, PI)) <= 0.02:
		yaw = _traversal_exit_yaw_target
		yaw_deg = rad2deg(yaw)
		_traversal_exit_yaw_target_active = false

func _exit_tree() -> void:
	# Ensure we never leave dangling camera requests when player is respawned/freed.
	_clear_cinematic_zone_request()

func _clear_cinematic_zone_request() -> void:
	if _current_zone_request_id != -1 and is_instance_valid(CinematicManager):
		CinematicManager.release_camera_request(_current_zone_request_id)
	_current_zone_request_id = -1

onready var camera_rig = $CameraRig
var camera_basis_prefix: Basis = Basis.IDENTITY
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
		var dust = _get_camera_space_dust()
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
	if _should_disable_auto_align_for_profile():
		enable_auto_align = false
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

	if has_node("Logic/Traversal"):
		traversal_logic = get_node("Logic/Traversal")
	else:
		traversal_logic = TraversalLogicV2.new()
		traversal_logic.name = "Traversal"
		if has_node("Logic"):
			get_node("Logic").add_child(traversal_logic)
		else:
			add_child(traversal_logic)

	if traversal_logic and traversal_logic.has_method("apply_to_controller"):
		traversal_logic.apply_to_controller(self)

	if not has_node("Logic/ZeroGravity"):
		var zero_g_settings = ZeroGravitySettingsV2.new()
		zero_g_settings.name = "ZeroGravity"
		if has_node("Logic"):
			get_node("Logic").add_child(zero_g_settings)
		else:
			add_child(zero_g_settings)

	if not has_node("ZeroGravityController"):
		var zgc = load("res://core_v2/player/ZeroGravityController.gd").new()
		zgc.name = "ZeroGravityController"
		add_child(zgc)

	if not has_node("ControllerManager"):
		var cm = load("res://core_v2/player/ControllerManager.gd").new()
		cm.name = "ControllerManager"
		add_child(cm)
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
		_camera_rig_y_smoothed_global = global_transform.origin.y + base_rig_y
		_camera_rig_y_initialized = true
		_camera_rig_airborne_anchor_global = _camera_rig_y_smoothed_global
		_camera_rig_airborne_rise_time = 0.0
		_camera_rig_was_grounded = true
	
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
	return false

func _should_reduce_camera_particles() -> bool:
	return false

func _should_disable_auto_align_for_profile() -> bool:
	return false

func _should_throttle_animator_for_profile() -> bool:
	return false

func _apply_camera_particle_policy() -> void:
	var dust = _get_camera_space_dust()
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
	var dust = _get_camera_space_dust()
	if dust:
		if "emitting" in dust:
			dust.emitting = false
		dust.queue_free()
	if animator:
		animator.set_process(false)
		animator.set_physics_process(false)

func _get_camera_space_dust() -> Node:
	var cam := _cached_cam
	if not is_instance_valid(cam) and camera_rig:
		cam = _find_camera(camera_rig)
	if not is_instance_valid(cam):
		return null
	return cam.get_node_or_null("SpaceDust")

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
		camera_rig.transform.basis = camera_basis_prefix * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
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
		camera_rig.transform.basis = camera_basis_prefix * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
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

func _get_support_normal() -> Vector3:
	if is_instance_valid(movement_logic) and movement_logic.has_method("get_floor_normal"):
		var floor_normal = movement_logic.get_floor_normal()
		if floor_normal is Vector3 and floor_normal.length_squared() > 0.25:
			return floor_normal.normalized()
	return Vector3.UP

func _project_vector_onto_support_plane(vector: Vector3) -> Vector3:
	var support_normal := _get_support_normal()
	var projected := vector - support_normal * vector.dot(support_normal)
	return projected

func _get_push_plane_direction(vector: Vector3, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var projected := _project_vector_onto_support_plane(vector)
	if projected.length_squared() > 0.0001:
		return projected.normalized()
	if fallback.length_squared() > 0.0001:
		var fallback_projected := _project_vector_onto_support_plane(fallback)
		if fallback_projected.length_squared() > 0.0001:
			return fallback_projected.normalized()
	return Vector3.ZERO

func _update_camera_orbit_state(dt: float, input: InputDataV2, allow_auto_align: bool = true, allow_move_turn_input: bool = true) -> void:
	# Camera Orbit Logic (Third Person)
	if _rl_fast_controller:
		if input and input.mouse_delta:
			yaw -= input.mouse_delta.x * mouse_sensitivity
			var mouse_y_fast = - input.mouse_delta.y if invert_mouse_y else input.mouse_delta.y
			pitch -= mouse_y_fast * mouse_sensitivity
		pitch = clamp(pitch, deg2rad(min_pitch), deg2rad(max_pitch))
		_apply_orbit_zoom_delta(input.zoom_delta)
		if input.fov_override > 0.0:
			base_fov = input.fov_override
	else:
		var active_zone_mode = CinematicManager.get_control_mode()
		if active_zone_mode == CinematicManager.ControlMode.FREE:
			if input:
				var orbit_move_vec = input.move_vec if allow_move_turn_input else Vector2.ZERO
				if _traversal_strafe_latch_active:
					orbit_move_vec = Vector2.ZERO
					movement_logic.is_tank_turn_mode = false
					movement_logic.camera_input_timer = 0.0
					movement_logic.current_turn_time = 0.0
				movement_logic.update_tank_mode(dt, input.mouse_delta, orbit_move_vec, input.jump, input.sprint, input.hardware_mouse_active)
				yaw -= input.mouse_delta.x * mouse_sensitivity
				var mouse_y = - input.mouse_delta.y if invert_mouse_y else input.mouse_delta.y
				pitch -= mouse_y * mouse_sensitivity
				yaw += movement_logic.get_tank_yaw_delta(dt, orbit_move_vec)
				if allow_auto_align and enable_auto_align and not movement_logic.is_tank_turn_mode:
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
			_apply_orbit_zoom_delta(input.zoom_delta)

		if input.fov_override > 0.0:
			base_fov = input.fov_override

	if camera_rig:
		camera_rig.transform.basis = camera_basis_prefix * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.force_update_transform()

	yaw_deg = rad2deg(yaw)
	pitch_deg = rad2deg(pitch)

func _update_camera_view(dt: float) -> void:
	if (not _rl_skip_camera_updates) and _cached_spring_arm:
		current_spring_length = lerp(current_spring_length, base_spring_length_3d, 4.0 * dt)
		_cached_spring_arm.spring_length = current_spring_length

	if (not _rl_skip_camera_updates) and _cached_cam and abs(_cached_cam.fov - base_fov) > 0.01:
		_cached_cam.fov = lerp(_cached_cam.fov, base_fov, 4.0 * dt)

	_update_camera_rig_vertical(dt)

func _update_camera_rig_vertical(dt: float) -> void:
	if not camera_rig or _rl_skip_camera_updates:
		return
	if not _camera_rig_y_initialized:
		_camera_rig_y_smoothed_global = global_transform.origin.y + base_rig_y
		_camera_rig_y_initialized = true
		_camera_rig_airborne_anchor_global = _camera_rig_y_smoothed_global
		_camera_rig_airborne_rise_time = 0.0
		_camera_rig_was_grounded = true
		return

	var target_global_y := global_transform.origin.y + base_rig_y
	var ots_follow_weight := _update_ots_camera_follow_weight(dt)
	var grounded := is_on_floor() or _just_stepped or _step_grounded_timer > 0.0
	var step_transition := _just_stepped or _step_grounded_timer > 0.0
	var rising := not grounded and velocity.y > 0.05
	if grounded:
		_camera_rig_airborne_anchor_global = target_global_y
		_camera_rig_airborne_rise_time = 0.0
		_camera_rig_was_grounded = true
	elif _camera_rig_was_grounded:
		_camera_rig_airborne_anchor_global = _camera_rig_y_smoothed_global
		_camera_rig_airborne_rise_time = 0.0
		_camera_rig_was_grounded = false

	if rising:
		_camera_rig_airborne_rise_time += dt
		var effective_lazy_delay: float = lerp(camera_rig_jump_lazy_delay, 0.0, ots_follow_weight)
		var effective_lazy_deadzone: float = lerp(camera_rig_jump_lazy_deadzone, 0.0, ots_follow_weight)
		if _camera_rig_airborne_rise_time < effective_lazy_delay:
			target_global_y = min(target_global_y, _camera_rig_airborne_anchor_global)
		else:
			target_global_y = max(
				_camera_rig_airborne_anchor_global,
				target_global_y - effective_lazy_deadzone
			)
	else:
		_camera_rig_airborne_rise_time = 0.0 if grounded else _camera_rig_airborne_rise_time

	var speed := camera_rig_y_ground_snap_speed if grounded else (camera_rig_y_follow_speed if rising else camera_rig_y_fall_follow_speed)
	if step_transition:
		speed = camera_rig_step_snap_speed
	if not grounded:
		speed = lerp(speed, ots_camera_follow_speed, ots_follow_weight)
	var t := clamp(speed * dt, 0.0, 1.0)
	_camera_rig_y_smoothed_global = lerp(_camera_rig_y_smoothed_global, target_global_y, t)

	# Clamp max lag so camera doesn't get left behind excessively
	var lag := target_global_y - _camera_rig_y_smoothed_global
	if abs(lag) > camera_rig_y_max_lag:
		_camera_rig_y_smoothed_global = target_global_y - sign(lag) * camera_rig_y_max_lag

	# Convert smoothed global Y back to local offset
	camera_rig.transform.origin.y = _camera_rig_y_smoothed_global - global_transform.origin.y

func _update_ots_camera_follow_weight(dt: float) -> float:
	var start_len := max(ots_camera_follow_start_length, ots_camera_follow_full_length + 0.001)
	var full_len := max(ots_camera_follow_full_length, 0.001)
	var effective_len := _get_effective_camera_arm_length()
	var raw_weight := 1.0 - clamp((effective_len - full_len) / (start_len - full_len), 0.0, 1.0)
	_ots_camera_follow_weight = lerp(
		_ots_camera_follow_weight,
		raw_weight,
		1.0 - exp(-max(ots_camera_follow_blend_speed, 0.0) * max(dt, 0.0))
	)
	return _ots_camera_follow_weight

func _get_effective_camera_arm_length() -> float:
	var target_len := current_spring_length
	if _cached_spring_arm and is_instance_valid(_cached_spring_arm):
		var spring_len = _cached_spring_arm.get("spring_length")
		if spring_len != null:
			target_len = float(spring_len)
		var current_len = _cached_spring_arm.get("current_length")
		if current_len != null:
			return min(float(current_len), target_len)
	return target_len

func _is_camera_zoom_out_blocked() -> bool:
	return (
		_cached_spring_arm
		and is_instance_valid(_cached_spring_arm)
		and _cached_spring_arm.has_method("is_zoom_out_blocked")
		and _cached_spring_arm.is_zoom_out_blocked()
	)

func _apply_orbit_zoom_delta(zoom_delta: float) -> void:
	if abs(zoom_delta) <= 0.01:
		return
	if zoom_delta > 0.0 and _is_camera_zoom_out_blocked():
		return
	base_spring_length_3d = clamp(
		base_spring_length_3d + zoom_delta,
		max(orbit_zoom_min_length, 0.1),
		max(orbit_zoom_max_length, orbit_zoom_min_length)
	)

func _update_camera_collision_mask_state(dt: float) -> void:
	if not _cached_spring_arm:
		return
	var suppress_collision := false
	if traversal_logic and traversal_logic.is_active:
		var state = traversal_logic.current_state
		suppress_collision = state == traversal_logic.TraversalState.HANGING or state == traversal_logic.TraversalState.MANTLING
	if suppress_collision:
		_camera_collision_grace_left = max(_camera_collision_grace_left, traversal_camera_collision_grace)
	else:
		_camera_collision_grace_left = max(0.0, _camera_collision_grace_left - dt)
	_cached_spring_arm.collision_mask = 0 if _camera_collision_grace_left > 0.0 else base_collision_mask

func _get_traversal_detach_normal() -> Vector3:
	if not traversal_logic:
		return -global_transform.basis.z
	if traversal_logic.current_state == traversal_logic.TraversalState.CLIMBING:
		if traversal_logic.ladder_normal.length_squared() > 0.001:
			return -traversal_logic.ladder_normal.normalized()
	elif traversal_logic.current_state == traversal_logic.TraversalState.HANGING or traversal_logic.current_state == traversal_logic.TraversalState.MANTLING:
		if traversal_logic.ledge_normal.length_squared() > 0.001:
			return -traversal_logic.ledge_normal.normalized()
	return -global_transform.basis.z

func _find_nearby_ladder_for_crouch() -> Node:
	if _ladder_regrab_cooldown > 0.0:
		return null
	var top_margin = traversal_logic.ladder_crouch_top_margin if traversal_logic else 0.35
	var below_margin = traversal_logic.ladder_crouch_vertical_below_margin if traversal_logic else 0.8
	var above_margin = traversal_logic.ladder_crouch_vertical_above_margin if traversal_logic else 1.0
	var lateral_limit := traversal_logic.ladder_crouch_lateral_limit if traversal_logic else 0.9
	var depth_limit := traversal_logic.ladder_crouch_depth_limit if traversal_logic else 0.9
	var ladders = get_tree().get_nodes_in_group("ladder")
	var best_ladder: Node = null
	var best_score := INF
	var player_pos = global_transform.origin
	for ladder in ladders:
		if not is_instance_valid(ladder):
			continue
		if "is_interactable" in ladder and not ladder.is_interactable:
			continue
		var anchor = ladder.get_climb_anchor() if ladder.has_method("get_climb_anchor") else ladder.global_transform.origin
		var normal = -ladder.global_transform.basis.z
		var right = normal.cross(Vector3.UP).normalized()
		var rel = player_pos - anchor
		var lateral = abs(rel.dot(right))
		var depth = abs(rel.dot(normal))
		var limits = ladder.get_climb_limits() if ladder.has_method("get_climb_limits") else Vector2(-1.5, 1.5)
		var vertical = rel.y
		if vertical < limits.y - top_margin:
			continue
		var within_vertical = vertical >= limits.x - below_margin and vertical <= limits.y + above_margin
		var within_lateral = lateral <= lateral_limit
		var within_depth = depth <= depth_limit
		if not within_vertical or not within_lateral or not within_depth:
			continue
		var clamped_vertical = clamp(vertical, limits.x, limits.y)
		var score = lateral * lateral + depth * depth + abs(vertical - clamped_vertical) * 0.25
		if score < best_score:
			best_score = score
			best_ladder = ladder
	return best_ladder

func _can_auto_enter_ladder(ladder: Node) -> bool:
	if not is_instance_valid(ladder):
		return false
	var anchor = ladder.get_climb_anchor() if ladder.has_method("get_climb_anchor") else ladder.global_transform.origin
	var normal = -ladder.global_transform.basis.z
	var right = normal.cross(Vector3.UP).normalized()
	var rel = global_transform.origin - anchor
	var limits = ladder.get_climb_limits() if ladder.has_method("get_climb_limits") else Vector2(-1.5, 1.5)
	var below_margin := traversal_logic.ladder_auto_enter_vertical_below_margin if traversal_logic else 0.35
	var above_margin := traversal_logic.ladder_auto_enter_vertical_above_margin if traversal_logic else 0.55
	var lateral_limit := traversal_logic.ladder_auto_enter_lateral_limit if traversal_logic else 0.55
	var depth_limit := traversal_logic.ladder_auto_enter_depth_limit if traversal_logic else 0.55
	var vertical = rel.y
	var lateral = abs(rel.dot(right))
	var depth = abs(rel.dot(normal))
	return (
		vertical >= limits.x - below_margin
		and vertical <= limits.y + above_margin
		and lateral <= lateral_limit
		and depth <= depth_limit
	)

func _find_nearby_ledge_for_crouch() -> Node:
	if _ledge_regrab_cooldown > 0.0:
		return null
	var min_vertical_from_above := traversal_logic.ledge_crouch_min_vertical_from_above if traversal_logic else 0.05
	var max_vertical_from_above := traversal_logic.ledge_crouch_max_vertical_from_above if traversal_logic else 2.6
	var lateral_margin := traversal_logic.ledge_crouch_lateral_margin if traversal_logic else 0.35
	var depth_limit := traversal_logic.ledge_crouch_depth_limit if traversal_logic else 1.35
	var ledges = get_tree().get_nodes_in_group("ledge")
	var best_ledge: Node = null
	var best_score := INF
	var player_pos = global_transform.origin
	for ledge in ledges:
		if not is_instance_valid(ledge):
			continue
		if not (ledge is PhysicsBody):
			continue
		if not ledge.has_method("get_hang_half_width"):
			continue
		if "is_interactable" in ledge and not ledge.is_interactable:
			continue
		var anchor = ledge.global_transform.origin
		var normal = -ledge.global_transform.basis.z
		var tangent = normal.cross(Vector3.UP).normalized()
		var rel = player_pos - anchor
		var half_width = ledge.get_hang_half_width() if ledge.has_method("get_hang_half_width") else 0.85
		var lateral = abs(rel.dot(tangent))
		var depth = abs(rel.dot(normal))
		var vertical = rel.y
		if vertical < min_vertical_from_above:
			continue
		var within_lateral = lateral <= half_width + lateral_margin
		var within_depth = depth <= depth_limit
		var within_vertical = vertical >= min_vertical_from_above and vertical <= max_vertical_from_above
		if not within_lateral or not within_depth or not within_vertical:
			continue
		var clamped_vertical = clamp(vertical, -0.1, 1.8)
		var score = lateral * lateral + depth * depth + abs(vertical - clamped_vertical) * 0.35
		if vertical > 0.5:
			score -= 0.15
		if score < best_score:
			best_score = score
			best_ledge = ledge
	return best_ledge

func _start_ledge_regrab_cooldown(player_y: float, ledge_y: float) -> void:
	if player_y > ledge_y + 0.1:
		_ledge_regrab_cooldown = max(_ledge_regrab_cooldown, ledge_regrab_cooldown_time_above)
	else:
		_ledge_regrab_cooldown = max(_ledge_regrab_cooldown, ledge_regrab_cooldown_time_below)

func _update_input_edge_state(input: InputDataV2) -> void:
	if input == null:
		_jump_was_pressed = false
		_crouch_was_pressed = false
		return
	_jump_was_pressed = input.jump
	_crouch_was_pressed = input.crouch

func _should_auto_hang_ledge(best_target: Node, input: InputDataV2) -> bool:
	if not best_target or _ledge_regrab_cooldown > 0.0:
		return false
	var max_rising_velocity := traversal_logic.ledge_auto_hang_max_rising_velocity if traversal_logic else 0.05
	if is_effectively_grounded() and velocity.y >= -max_rising_velocity:
		return false
	var anchor = best_target.global_transform.origin
	var normal = -best_target.global_transform.basis.z
	var tangent = normal.cross(Vector3.UP).normalized()
	var rel = global_transform.origin - anchor
	var half_width = best_target.get_hang_half_width() if best_target.has_method("get_hang_half_width") else 0.85
	var lateral_margin := traversal_logic.ledge_auto_hang_lateral_margin if traversal_logic else 0.28
	var depth_limit := traversal_logic.ledge_auto_hang_depth_limit if traversal_logic else 0.75
	var lateral = abs(rel.dot(tangent))
	var depth = abs(rel.dot(normal))
	var vertical = global_transform.origin.y - anchor.y
	var ledge_height_above_feet = -vertical
	var min_grab_height = max(
		traversal_logic.ledge_auto_hang_min_height if traversal_logic else 0.75,
		_standing_capsule_total_height * (traversal_logic.ledge_auto_hang_min_height_ratio if traversal_logic else 0.42)
	)
	var max_grab_height = max(
		min_grab_height + (traversal_logic.ledge_auto_hang_band_padding if traversal_logic else 0.2),
		min(
			traversal_logic.ledge_auto_hang_max_height if traversal_logic else 1.6,
			_standing_capsule_total_height * (traversal_logic.ledge_auto_hang_max_height_ratio if traversal_logic else 0.9)
		)
	)
	# Auto-hang should only happen when the ledge is within arm/torso reach.
	# If the ledge is too low relative to the feet, the player should keep falling
	# under gravity instead of getting "pulled" down into a hang from the hips/feet.
	if ledge_height_above_feet < min_grab_height:
		return false
	if velocity.y > max_rising_velocity:
		return false
	if lateral > half_width + lateral_margin:
		return false
	if depth > depth_limit:
		return false
	return ledge_height_above_feet >= min_grab_height and ledge_height_above_feet <= max_grab_height

func _can_start_mantle() -> bool:
	var mantle_targets = _get_mantle_target_points()
	if mantle_targets.empty():
		return false
	var target_top = mantle_targets["top"]
	if not traversal_logic:
		return false
	if traversal_logic.current_state != traversal_logic.TraversalState.HANGING:
		return false
	var space_state = get_world().direct_space_state

	if not _body_capsule_shape:
		return true
	var stand_shape = CapsuleShape.new()
	stand_shape.radius = _body_capsule_shape.radius
	stand_shape.height = max(0.1, _standing_capsule_height)
	var params = PhysicsShapeQueryParameters.new()
	params.set_shape(stand_shape)
	params.transform = Transform(global_transform.basis, target_top) * Transform(Basis.IDENTITY, _standing_collision_origin)
	params.exclude = [self]
	params.collision_mask = collision_mask
	var hits = space_state.intersect_shape(params, 1)
	return hits.empty()

func _get_mantle_target_points() -> Dictionary:
	if not traversal_logic:
		return {}
	if traversal_logic.current_state != traversal_logic.TraversalState.HANGING:
		return {}
	var tangent = traversal_logic.ledge_normal.cross(Vector3.UP).normalized()
	var nominal_vertical = traversal_logic.ledge_anchor_point + tangent * traversal_logic.hang_lateral_offset + Vector3.UP * traversal_logic.mantle_up_offset
	var nominal_top = nominal_vertical + traversal_logic.ledge_normal * traversal_logic.mantle_forward_offset
	var space_state = get_world().direct_space_state
	var support_offsets = [
		Vector3.ZERO,
		tangent * 0.18,
		-tangent * 0.18
	]
	var best_hit = {}
	for offset in support_offsets:
		var from = nominal_top + offset + Vector3.UP * 0.3
		var to = nominal_top + offset + Vector3.DOWN * 1.4
		var hit = space_state.intersect_ray(from, to, [self], collision_mask)
		if hit.empty():
			continue
		if hit.normal.y < 0.45:
			continue
		best_hit = hit
		break
	if best_hit.empty():
		return {}
	var support_y = best_hit.position.y
	var target_vertical = Vector3(nominal_vertical.x, support_y, nominal_vertical.z)
	var target_top = Vector3(nominal_top.x, support_y, nominal_top.z)
	return {
		"vertical": target_vertical,
		"top": target_top
	}

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

func _resolve_interactable_root(node: Node) -> Node:
	var current = node
	while current and is_instance_valid(current):
		if current.is_in_group("interactable") and current.has_method("get_climb_anchor"):
			return current
		if current.is_in_group("interactable") and current.has_method("get_hang_half_width"):
			return current
		if current.get("is_interactable") != null and current.get("is_interactable"):
			return current
		if current.get("is_focusable") != null and current.get("is_focusable"):
			return current
		if current.is_in_group("focusable"):
			return current
		current = current.get_parent()
	return node

func _candidate_can_interact(candidate: Node) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if candidate.get("is_interactable") != null:
		return bool(candidate.get("is_interactable"))
	return candidate.is_in_group("interactable")

func _candidate_can_focus(candidate: Node) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if candidate.has_method("can_focus"):
		return bool(candidate.call("can_focus"))
	if candidate.get("is_focusable") != null:
		return bool(candidate.get("is_focusable"))
	return candidate.is_in_group("focusable")

func _candidate_is_actionable(candidate: Node) -> bool:
	return _candidate_can_interact(candidate) or _candidate_can_focus(candidate)

func _get_interaction_prompt(candidate: Node) -> String:
	if candidate == null or not is_instance_valid(candidate):
		return ""
	if candidate.has_method("get_interaction_prompt"):
		return str(candidate.call("get_interaction_prompt"))
	var parts := PoolStringArray()
	if _candidate_can_interact(candidate):
		var action_text = candidate.get("interaction_text")
		parts.append("%s %s" % [_get_action_hint_label(INTERACT_ACTION_NAME), str(action_text) if action_text else "Interact"])
	if _candidate_can_focus(candidate):
		var focus_text = candidate.get("focus_text")
		parts.append("%s %s" % [_get_action_hint_label(FOCUS_ACTION_NAME), str(focus_text) if focus_text else "Focus"])
	return parts.join(" / ")

func _get_action_hint_label(action_name: String) -> String:
	return String(DEFAULT_ACTION_HINTS.get(action_name, "[?]"))

func _show_interaction_prompt(text: String) -> void:
	if text.strip_edges() == "":
		return
	var hints = get_node_or_null("/root/PlayerHintManager")
	if hints and hints.has_method("show_interaction_hint"):
		hints.show_interaction_hint(text)

func _process_interaction(input: InputDataV2):
	if _perf_disable_interaction_scan:
		_clear_interactable()
		return
	if not _interact_area: return
	var bodies = _interact_area.get_overlapping_bodies()
	var best_target = null
	var crouch_ledge_target = null
	var crouch_ladder_target = null
	var min_dist = 999.0
	for body in bodies:
		var candidate = _resolve_interactable_root(body)
		if is_instance_valid(candidate) and _candidate_is_actionable(candidate):
			var dist = global_transform.origin.distance_squared_to(candidate.global_transform.origin)
			if dist < min_dist:
				min_dist = dist
				best_target = candidate
	if input.crouch and (best_target == null or best_target.is_in_group("ledge")):
		crouch_ledge_target = _find_nearby_ledge_for_crouch()
		if crouch_ledge_target:
			best_target = crouch_ledge_target
	if input.crouch and (best_target == null or best_target.is_in_group("ladder")):
		crouch_ladder_target = _find_nearby_ladder_for_crouch()
		if crouch_ladder_target:
			best_target = crouch_ladder_target
	var h_color = Color.cyan
	var p_color = Color(0, 1, 1, 0.15)
	var p_radius_sq = 36.0 # 6m default
	if interact_config:
		h_color = interact_config.highlight_color
		p_color = interact_config.proximity_color
		p_radius_sq = interact_config.proximity_radius * interact_config.proximity_radius

	if best_target:
		var text = _get_interaction_prompt(best_target)
		if _current_interactable != best_target:
			# Clear highlight from previous target
			if _current_interactable and is_instance_valid(_current_interactable):
				if _current_interactable.has_method("set_highlighted"):
					_current_interactable.set_highlighted(false)
			
			_current_interactable = best_target
			_current_interaction_prompt = text
			emit_signal("interactable_in_range", text)
			_show_interaction_prompt(text)
			
			# Apply full highlight to new target
			if best_target.has_method("set_highlighted"):
				best_target.set_highlighted(true, h_color)
			# Ensure it doesn't have proximity glow if it's the main target
			if best_target.has_method("set_proximity_highlight"):
				best_target.set_proximity_highlight(false)
			
			var can_auto_trigger = not best_target.get("_auto_triggered") or not best_target.get("one_off")
			if _candidate_can_interact(best_target) and best_target.get("auto_interact") and not best_target.is_active and can_auto_trigger:
				if best_target.has_method("set_active"):
					best_target.set_active(true)
					best_target._auto_triggered = true
		elif text != _current_interaction_prompt:
			_current_interaction_prompt = text
			emit_signal("interactable_in_range", text)
			_show_interaction_prompt(text)
		if input.interact and _candidate_can_interact(best_target) and best_target.has_method("interact"):
			best_target.interact()
		if input.focus and _candidate_can_focus(best_target):
			if best_target.has_method("focus"):
				best_target.call("focus")
			elif best_target.has_method("_enter_focus_mode"):
				best_target.call("_enter_focus_mode")

		# Traversal Entry Logic
		var ladder_forward_entry = best_target.is_in_group("ladder") and input.move_vec.y < -0.1 and _can_auto_enter_ladder(best_target)
		var ladder_crouch_entry = best_target.is_in_group("ladder") and input.crouch and best_target == crouch_ladder_target
		if best_target.is_in_group("ladder") and traversal_logic and _ladder_regrab_cooldown <= 0.0 and (ladder_forward_entry or ladder_crouch_entry):
			var anchor = best_target.get_climb_anchor() if best_target.has_method("get_climb_anchor") else best_target.global_transform.origin
			var normal = -best_target.global_transform.basis.z # Assuming -Z is ladder forward
			var is_1d = best_target.get("is_1d_ladder") if "is_1d_ladder" in best_target else true
			var climb_limits = best_target.get_climb_limits() if best_target.has_method("get_climb_limits") else Vector2(-1.5, 1.5)
			traversal_logic.enter_climbing(anchor, normal, global_transform.origin, is_1d, climb_limits.x, climb_limits.y)
			_sync_movement_state_after_traversal()
			if jump_logic:
				jump_logic.set_internal_velocity(0.0)
		elif best_target.is_in_group("ledge") and traversal_logic and ((_should_auto_hang_ledge(best_target, input) and input.move_vec.y <= 0.2) or (input.crouch and best_target == crouch_ledge_target)):
			var anchor = best_target.global_transform.origin
			var normal = -best_target.global_transform.basis.z
			var half_width = best_target.get_hang_half_width() if best_target.has_method("get_hang_half_width") else 0.85
			traversal_logic.enter_hanging(anchor, normal, half_width, global_transform.origin)
			_sync_movement_state_after_traversal()
			if jump_logic:
				jump_logic.set_internal_velocity(0.0)
	else:
		_clear_interactable()

	# --- Proximity Glow Logic ---
	# Handle objects that are nearby but not the current best_target
	_interactables_cache_frames += 1
	if _interactables_cache_frames >= 30:
		_interactables_cache_frames = 0
		_cached_all_interactables = get_tree().get_nodes_in_group("interactable")
		var dict = {}
		for obj in _cached_all_interactables:
			dict[obj] = true
		for focusable in get_tree().get_nodes_in_group("focusable"):
			if not dict.has(focusable):
				_cached_all_interactables.append(focusable)
				dict[focusable] = true

	var new_nearby = []
	for obj in _cached_all_interactables:
		if not is_instance_valid(obj) or obj == _current_interactable:
			continue
		
		if not _candidate_is_actionable(obj):
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
	if _current_interactable != null and is_instance_valid(_current_interactable):
		if "_auto_triggered" in _current_interactable and not _current_interactable.get("one_off"):
			_current_interactable._auto_triggered = false
		
		# Remove highlight when going out of range
		if _current_interactable.has_method("set_highlighted"):
			_current_interactable.set_highlighted(false)
		
		# Restore proximity glow if still nearby
		if interact_config and is_instance_valid(_current_interactable):
			var d_sq = global_transform.origin.distance_squared_to(_current_interactable.global_transform.origin)
			if d_sq < (interact_config.proximity_radius * interact_config.proximity_radius):
				if _current_interactable.has_method("set_proximity_highlight"):
					_current_interactable.set_proximity_highlight(true, interact_config.proximity_color)

		_current_interactable = null
		_current_interaction_prompt = ""
		emit_signal("interactable_out_of_range")
		var hints = get_node_or_null("/root/PlayerHintManager")
		if hints and hints.has_method("clear_interaction_hint"):
			hints.clear_interaction_hint()

func _input(event):
	var session_recording = false
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.player == self and sm.is_recording:
		session_recording = true
	if (is_replay_mode and not session_recording) or camera_input_locked: return
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
	target.focus = target.focus or source.focus

func _update_push_state(dt: float, input: InputDataV2):
	_was_pushing = is_pushing
	is_pushing = false
	var raw_push_correction := 0.0
	_push_target = null
	# Push is strictly grounded-only. Never activate or persist while airborne.
	if not is_on_floor() or velocity.y > 0.05:
		_apply_visual_push_correction(raw_push_correction, dt)
		return
	if not _interact_area:
		_apply_visual_push_correction(raw_push_correction, dt)
		return

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
		var dir_to_box = _get_push_plane_direction(
			best_target.global_transform.origin - global_transform.origin
		)

		if world_input.length_squared() > 0.01 and dir_to_box.length_squared() > 0.01:
			var input_push_dir := _get_push_plane_direction(world_input, dir_to_box)
			var dot = input_push_dir.dot(dir_to_box)
			if dot > 0.5: # Approx 45 degrees
				var space_state = get_world().direct_space_state
				var from = global_transform.origin + _get_support_normal() * 1.0
				var input_dir = input_push_dir
				var to_input = from + input_dir * 2.0
				var result = space_state.intersect_ray(from, to_input, [ self ])
				
				if not result or result.collider != best_target:
					var to_center = best_target.global_transform.origin
					result = space_state.intersect_ray(from, to_center, [ self ])
				
				if result and result.collider == best_target:
					var push_axis := _get_push_plane_direction(-result.normal, dir_to_box)
					if push_axis.length_squared() <= 0.0001:
						push_axis = dir_to_box
					push_normal = -push_axis
					var p_pos = global_transform.origin
					var h_pos = result.position
					# Project distance onto the push normal for consistent depth check (handles corners/edges)
					# surf_dist is the distance along the push axis
					var rel_vec = h_pos - p_pos
					var surf_dist = rel_vec.dot(push_axis)
					
					# Contact Gate: Apply animation if within reasonable reach (1.25m)
					# We decouple the LOGICAL push state from the VISUAL anchor point.
					if surf_dist < 1.25:
						is_pushing = true
						# Pro-actively wake up the box if it has settled into Kinematic mode
						if best_target.has_method("wake_up"):
							best_target.wake_up()
						if surf_dist <= push_offset + 0.08:
							var desired_push_speed := max(0.5, movement_logic.move_speed * input.move_vec.length())
							if best_target.has_method("set_external_velocity"):
								best_target.set_external_velocity(push_axis * desired_push_speed)
							elif best_target is RigidBody:
								var rigid_target := best_target as RigidBody
								rigid_target.apply_central_impulse(push_axis * push_force * dt)
							
						# Visual Anchoring: Calculate discrepancy from ideal push_offset (0.71m)
						raw_push_correction = max(0.0, push_offset - surf_dist)
					else:
						raw_push_correction = 0.0
				else:
					push_normal = - dir_to_box
					raw_push_correction = 0.0
				
				_push_target = best_target
	_apply_visual_push_correction(raw_push_correction, dt)

func _apply_visual_push_correction(raw_correction: float, dt: float) -> void:
	_push_correction_smoothed = lerp(_push_correction_smoothed, raw_correction, clamp(15.0 * dt, 0.0, 1.0))
	visual_push_correction = _push_correction_smoothed

func _apply_push_constraint(dt: float) -> void:
	if not is_pushing or not is_instance_valid(_push_target):
		return
	if push_normal.length_squared() <= 0.0001:
		return

	var away_from_box := push_normal.normalized()
	var toward_box := -away_from_box
	var support_normal := _get_support_normal()
	var space_state = get_world().direct_space_state
	var from = global_transform.origin + support_normal * 1.0
	var cast_to = from + toward_box * (interact_distance + 0.5)
	var result = space_state.intersect_ray(from, cast_to, [self])
	if not result or result.collider != _push_target:
		return

	var rel_vec = result.position - global_transform.origin
	var surf_dist = rel_vec.dot(toward_box)
	if surf_dist >= push_offset:
		return

	var penetration = push_offset - surf_dist
	var correction_dist = min(penetration, max(0.02, 6.0 * dt))
	global_transform.origin += away_from_box * correction_dist

	var into_box_speed = velocity.dot(away_from_box)
	if into_box_speed < 0.0:
		velocity -= away_from_box * into_box_speed

	if is_instance_valid(movement_logic):
		var h_vel = movement_logic.get_horizontal_velocity()
		var h_into_box_speed = h_vel.dot(away_from_box)
		if h_into_box_speed < 0.0:
			h_vel -= away_from_box * h_into_box_speed
			movement_logic.horizontal_velocity = h_vel

func step(dt: float, input: InputDataV2) -> void:
	var cm = get_node_or_null("ControllerManager")
	if cm and cm.current_mode == cm.Mode.ZERO_GRAVITY:
		var zgc = cm.zero_gravity_controller
		if zgc and zgc.has_method("step_zero_g"):
			zgc.step_zero_g(dt, input)
			_update_input_edge_state(input)
			return

	if input == null:
		_update_input_edge_state(null)
		return
	_update_post_traversal_strafe_latch(dt, input)
	_update_post_traversal_exit_alignment(dt)
	var jump_just_pressed = input.jump and not _jump_was_pressed
	var crouch_just_pressed = input.crouch and not _crouch_was_pressed
	_ledge_regrab_cooldown = max(0.0, _ledge_regrab_cooldown - dt)
	_ladder_regrab_cooldown = max(0.0, _ladder_regrab_cooldown - dt)

	# --- TRAVERSAL STATE CHECK ---
	if traversal_logic and traversal_logic.is_active:
		var current_traversal_state = traversal_logic.current_state
		var was_climbing = current_traversal_state == traversal_logic.TraversalState.CLIMBING
		var was_hanging = current_traversal_state == traversal_logic.TraversalState.HANGING
		var was_mantling = current_traversal_state == traversal_logic.TraversalState.MANTLING
		var traversal_surface_normal := Vector3.ZERO
		if current_traversal_state == traversal_logic.TraversalState.CLIMBING and traversal_logic.ladder_normal.length_squared() > 0.001:
			traversal_surface_normal = traversal_logic.ladder_normal.normalized()
		elif (current_traversal_state == traversal_logic.TraversalState.HANGING or current_traversal_state == traversal_logic.TraversalState.MANTLING) and traversal_logic.ledge_normal.length_squared() > 0.001:
			traversal_surface_normal = traversal_logic.ledge_normal.normalized()
		var ledge_y_before = traversal_logic.ledge_anchor_point.y if traversal_logic else global_transform.origin.y
		var old_pos = global_transform.origin
		traversal_logic.crouch_just_pressed = crouch_just_pressed
		var next_pos = traversal_logic.step(dt, input.move_vec, old_pos, input.crouch)
		global_transform.origin = next_pos
		var traversal_jump_velocity = null
		var traversal_drop_velocity = null

		if was_climbing and not traversal_logic.is_active:
			_ladder_regrab_cooldown = max(_ladder_regrab_cooldown, ladder_regrab_cooldown_time)
			_begin_post_traversal_strafe_latch(traversal_surface_normal, input.move_vec)
		if was_hanging and not traversal_logic.is_active and not input.jump:
			_start_ledge_regrab_cooldown(global_transform.origin.y, ledge_y_before)
			var detach_normal = _get_traversal_detach_normal()
			global_transform.origin += detach_normal * 0.08
			traversal_drop_velocity = detach_normal * hang_drop_push_force
			traversal_drop_velocity.y = hang_drop_vertical_velocity
			if jump_logic:
				jump_logic.set_internal_velocity(traversal_drop_velocity.y)
			_sync_movement_state_after_traversal(traversal_drop_velocity)
			_begin_post_traversal_strafe_latch(traversal_surface_normal, input.move_vec)
		if was_mantling and not traversal_logic.is_active:
			_start_ledge_regrab_cooldown(global_transform.origin.y, ledge_y_before)
			_sync_movement_state_after_traversal()
			_begin_post_traversal_strafe_latch(traversal_surface_normal, input.move_vec)

		if traversal_logic.current_state == traversal_logic.TraversalState.HANGING and input.move_vec.y < -0.5 and not crouch_just_pressed and traversal_logic._hang_attach_active == false and traversal_logic._hang_mantle_input_grace_left <= 0.0:
			var mantle_targets = _get_mantle_target_points()
			if not mantle_targets.empty() and _can_start_mantle():
				traversal_logic.configure_mantle_targets(mantle_targets["vertical"], mantle_targets["top"])
				traversal_logic.start_mantle()

		# Mantle auto-exit
		if traversal_logic.current_state == traversal_logic.TraversalState.MANTLING and traversal_logic.anim_progress >= 1.0:
			traversal_logic.exit()
			_start_ledge_regrab_cooldown(global_transform.origin.y, ledge_y_before)
			if traversal_logic.ledge_normal.length_squared() > 0.001:
				global_transform.origin += traversal_logic.ledge_normal.normalized() * 0.12

		# Jump to exit traversal
		if jump_just_pressed:
			var detach_normal = _get_traversal_detach_normal()
			var upward_force = jump_logic.jump_force * traversal_jump_vertical_multiplier if jump_logic else 12.0
			traversal_logic.exit()
			if current_traversal_state == traversal_logic.TraversalState.CLIMBING:
				_ladder_regrab_cooldown = max(_ladder_regrab_cooldown, ladder_regrab_cooldown_time)
			if current_traversal_state == traversal_logic.TraversalState.HANGING or current_traversal_state == traversal_logic.TraversalState.MANTLING:
				_start_ledge_regrab_cooldown(global_transform.origin.y, ledge_y_before)
			if jump_logic:
				jump_logic.consume_jump()
				jump_logic.set_internal_velocity(upward_force)
			velocity = detach_normal * traversal_jump_push_force
			velocity.y = upward_force
			traversal_jump_velocity = velocity
			_sync_movement_state_after_traversal(traversal_jump_velocity)
			_begin_post_traversal_strafe_latch(traversal_surface_normal, input.move_vec)
			global_transform.origin += detach_normal * traversal_jump_detach_distance + Vector3.UP * min(0.12, upward_force * dt)
			emit_signal("jumped")

		# Sync visual velocity for animator
		var delta_pos = global_transform.origin - old_pos
		if traversal_jump_velocity != null:
			velocity = traversal_jump_velocity
		elif traversal_drop_velocity != null:
			velocity = traversal_drop_velocity
		else:
			velocity = delta_pos / dt if dt > 0 else Vector3.ZERO

		_update_camera_orbit_state(dt, input, false, false)
		_update_camera_collision_mask_state(dt)

		# Update animator with traversal state
		if animator and animator.has_method("step_animator"):
			animator.step_animator(dt, velocity)
		_update_camera_view(dt)
		_update_input_edge_state(input)
		return
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
		_push_correction_smoothed = 0.0
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

	_update_camera_orbit_state(dt, input)

	if not _rl_fast_controller:
		_process_interaction(input)

	if physics_grounded and velocity.y < 0 and movement_logic.get_horizontal_velocity().y <= 0:
		velocity.y = 0
		if is_instance_valid(jump_logic):
			jump_logic.set_internal_velocity(0.0)

	if physics_grounded:
		jump_logic.reset_on_floor()
	else:
		jump_logic.on_air_tick(dt)

	if jump_just_pressed and not (traversal_logic and traversal_logic.is_active):
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

	_apply_push_constraint(dt)

	# --- ACROBATIC JUMP CHECK (before normal jump) ---
	if is_acrobatic_ready and physics_grounded and jump_logic.jump_buffer_timer > 0 and not CinematicManager.latch_active:
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
		velocity.y = jump_logic.step(dt, input.jump, velocity.y, physics_grounded)
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

	var _effective_snap := snap_length
	if _post_teleport_snap_frames > 0:
		_post_teleport_snap_frames -= 1
		_effective_snap = max(snap_length, 1.0)
	var snap_vec = Vector3.DOWN * _effective_snap if (velocity.y <= 0 and not input.jump) else Vector3.ZERO
	
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
				if is_pushing and body == _push_target:
					continue
				if body is RigidBody:
					var push_dir := _get_push_plane_direction(-collision.normal, velocity)
					if push_dir.length_squared() > 0.0001:
						var impulse = push_dir * push_force * dt
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

	_update_camera_collision_mask_state(dt)
	_update_camera_view(dt)
	if prof_enabled:
		_rl_step_profile_add(prof_t0, prof_t_control, prof_t_move, OS.get_ticks_usec())
	_update_input_edge_state(input)

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
	# During post-teleport snap frames, force grounded to prevent animation state flicker.
	if _post_teleport_snap_frames > 0:
		return true
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
		var hit = space_state.intersect_ray(from, to, [ self ], _get_step_support_collision_mask())
		near_ground = not hit.empty()
	return is_on_floor() or _just_stepped or _step_grounded_timer > 0.0 or recent_floor_contact or near_ground

func _get_step_support_collision_mask() -> int:
	var support_mask := collision_mask & STEP_SUPPORT_COLLISION_MASK
	return support_mask if support_mask != 0 else collision_mask

func _update_platform_tracking(dt: float) -> void:
	var new_platform: Spatial = null
	var new_platform_key := ""
	if is_on_floor():
		for i in get_slide_count():
			var collision = get_slide_collision(i)
			if collision.normal.y > 0.7:
				var collider = collision.collider
				if _is_trackable_platform_collider(collider):
					new_platform = collider
					new_platform_key = _get_platform_tracking_key(collider)
					break
	
	if new_platform != _platform_collider or new_platform_key != _platform_tracking_key:
		if _platform_collider != null and new_platform == null:
			if _platform_velocity.length() > 0.1:
				velocity += _platform_velocity
		
		_platform_collider = new_platform
		_platform_tracking_key = new_platform_key
		if new_platform:
			_platform_last_transform = new_platform.global_transform
		_was_on_platform = new_platform != null
	
	if _platform_collider != null and is_instance_valid(_platform_collider):
		var current_transform = _platform_collider.global_transform
		var old_local_pos = _platform_last_transform.affine_inverse().xform(global_transform.origin)
		var new_global_pos = current_transform.xform(old_local_pos)
		var delta_pos = new_global_pos - global_transform.origin
		if delta_pos.length() <= PLATFORM_TRACKING_MAX_DELTA:
			global_transform.origin += delta_pos
			_platform_velocity = delta_pos / dt if dt > 0 else Vector3.ZERO
		else:
			_platform_velocity = Vector3.ZERO
		_platform_last_transform = current_transform
	else:
		_platform_velocity = Vector3.ZERO
		_platform_tracking_key = ""

func _is_trackable_platform_collider(collider: Object) -> bool:
	if not collider is Spatial:
		return false
	if collider is StaticBody:
		return collider.has_meta("world_rotator_collision")
	return true

func _get_platform_tracking_key(collider: Object) -> String:
	if collider == null:
		return ""
	var key := str(collider.get_instance_id())
	if collider.has_meta("spiral_index") and collider.has_meta("plate_index"):
		key += ":%s:%s" % [str(collider.get_meta("spiral_index")), str(collider.get_meta("plate_index"))]
	return key

func _try_step_up(motion: Vector3) -> Dictionary:
	var old_mask = collision_mask
	collision_mask = _get_step_support_collision_mask()
	
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
	# Pequeña velocidad negativa para que snap_vec se active en el primer physics frame
	# y move_and_slide_with_snap adhiera al suelo sin el micro-salto de velocity.y=0.
	velocity.y = -0.001
	_post_teleport_snap_frames = 8
	if is_instance_valid(animator) and animator.has_method("freeze"):
		animator.call("freeze", 8)
	
	# Reset yaw/pitch to match target orientation to avoid state bleeding
	var euler = target_transform.basis.get_euler()
	yaw = euler.y
	pitch = euler.x
	yaw_deg = rad2deg(yaw)
	pitch_deg = rad2deg(pitch)
	# print("[PlayerController] teleport_to finished. Yaw: ", yaw, " Pitch: ", pitch)
	
	if camera_rig:
		camera_rig.transform.basis = camera_basis_prefix * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.transform.origin.y = base_rig_y
		camera_rig.force_update_transform()
		_camera_rig_y_smoothed_global = target_transform.origin.y + base_rig_y
		_camera_rig_y_initialized = true
		_camera_rig_airborne_anchor_global = _camera_rig_y_smoothed_global
		_camera_rig_airborne_rise_time = 0.0
		_camera_rig_was_grounded = true

	ensure_input_provider()
	set_camera_input_locked(false)
	if input_provider and input_provider.has_method("clear_buffer"):
		input_provider.clear_buffer()
