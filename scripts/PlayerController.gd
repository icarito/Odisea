extends KinematicBody

func set_is_replaying(value: bool):
	is_replaying = value
	_sync_camera_mode()

func _sync_camera_mode():
	   var cam = get_node_or_null("CameraRig")
	   if cam:
		   # Prefer explicit method if the node offers it
		   if cam.has_method("set_is_playback"):
			   cam.call("set_is_playback", is_replaying)
		   elif ("is_playback" in cam):
			   cam.is_playback = is_replaying
		   else:
			   # Last resort: try to set the property if it exists
			   if cam.get("is_playback") != null:
				   cam.set("is_playback", is_replaying)

var playback_target_pos = null # New variable for the target
const CORRECTION_STRENGTH = 2.0 # Magnet strength (adjustable: 1.0 is soft, 5.0 is strong)
const FIXED_DELTA = 1.0 / 60.0

const FixedVec3 = preload("res://scripts/utils/FVec3.gd")

# Placeholder: Elias controller based on PlayerTemplate
# Note: Advanced logic and animation references will be moved according to the refactor

export (NodePath) var PlayerAnimationTree 
export onready var animation_tree = get_node(PlayerAnimationTree)
onready var playback = animation_tree.get("parameters/playback")

export (NodePath) var PlayerCharacterMesh
export onready var player_mesh = get_node(PlayerCharacterMesh)


const ReplayUtils = preload("res://scripts/replay/ReplayUtils.gd")

export var gravity = 9.8
export var jump_force = 9.0
export var turn_speed = 2.0
export var dash_power = 12.0


# External velocity applied by platforms/conveyors (now in fixed-point)
var platform_velocity_fixed: Dictionary = FixedVec3.zero()
var platform_is_static_surface = false
var last_platform_velocity_fixed: Dictionary = FixedVec3.zero()
export var snap_len = 0.5 # TODO: migrar a fixed si es relevante
var snap_enabled = true

export(float, 0.0, 1.0, 0.01) var strafe_mode_influence = 1.0 # 1.0 = full strafe preferred, 0.0 = full tank turn

var strafe_cooldown = 0.0 # Prevents sudden turn after strafe ends

# Components
onready var external_velocity: ExternalVelocity = $ExternalVelocity if has_node("ExternalVelocity") else null
onready var jump_comp: PlayerJump = $PlayerJump if has_node("PlayerJump") else null
onready var movement_comp: PlayerMovement = $PlayerMovement if has_node("PlayerMovement") else null
# Use global InputState as input source
onready var InputState = get_node("/root/InputState")
onready var player_input = $PlayerInput if has_node("PlayerInput") else null

# Local flag to block automatic alignments during replay
var is_replaying = false

# NEW: Multiplayer support
var player_id = 1

# Legacy variables (some may be moved to components)
var airborne_inherited_fixed: Dictionary = FixedVec3.zero()
var was_on_floor = false
export var max_platform_up_follow = 5.0
export var inherit_vertical_platform_jump = true
var just_jumped = false
var time_since_jump = 1.0
var time_since_input = 1.0

export var debug_movement = false
export var debug_shadow = false
export var debug_input = false
export var debug_enabled = false # bandera global para desactivar todos los logs por defecto
export var debug_force_direct_move = false

export var floating_after_jump_delay = 0.25
export var floating_no_input_delay = 0.3
export var floating_vertical_speed_threshold = 0.35 # deprecated: use enter/exit thresholds below
export var floating_enter_vspeed_threshold = 0.4
export var floating_exit_vspeed_threshold = 1.0
export var floating_vspeed_smooth = 0.35
var _vspeed_smoothed = 0.0
export var floating_enter_accel_threshold = 2.0
export var floating_exit_accel_threshold = 3.5
export var floating_accel_smooth = 0.3
var _vaccel_smoothed = 0.0
var _prev_vy = 0.0
export var floating_from_jump_delay = 1.0
var time_in_jump_state = 0.0
export var floating_without_jump_delay = 0.5
export var floating_without_jump_requires_no_input = false
export var floating_move_speed_max = 4.8
export var floating_move_accel = 6.0
export var floating_horizontal_damping = 1.0

var roll_node_name = "Roll"
var idle_node_name = "Idle"
var walk_node_name = "Walk"
var run_node_name = "Run"
var jump_node_name = "Jump"
var attack1_node_name = "Attack1"
var attack2_node_name = "Attack2"
var bigattack_node_name = "BigAttack"

var is_attacking = false
var is_rolling = false

var aim_turn = 0.0
var velocity_fixed: Dictionary = FixedVec3.zero() # Replaces 'movement' and 'vertical_velocity' for move_and_slide
var pre_move_velocity_for_replay_fixed: Dictionary = FixedVec3.zero()

# Touch camera control
export var touch_sensitivity = 0.1

var angular_acceleration = 10
export(float, 0.0, 10.0, 0.1) var tank_turn_speed = 0.3
export(float, 0.0, 10.0, 0.1) var advancing_turn_speed = 0.3
export(float, 0.0, 1.0, 0.01) var analog_turn_multiplier = 1.0
export(float, 0.0, 1.0, 0.01) var sprint_threshold = 0.7
export(float, 0.0, 2000.0, 10.0) var mouse_active_timeout_ms = 500.0
var is_tank_turning = false
export(float, 0.0, 50.0, 0.5) var max_rise_speed = 20.0
export(float, 0.0, 50.0, 0.5) var max_fall_speed = 30.0
export(float, 0.0, 1.0, 0.01) var air_control_multiplier = 0.2
export var cam_yaw_offset = 0.0 # radians to compensate for camera offset
export var swap_input_axes = false # swap X/Z if the mapping is 90° off
export var invert_forward = false # inverts the Z axis if the mesh faces -Z
export var mesh_yaw_offset = 0.0 # fixed offset if the mesh has an offset (e.g. 45°)
export var debug_yaw = false # prints YawAlign/Dir each frame for diagnosis
export(float, 0.0, 2.0, 0.01) var debug_interval = 0.4 # seconds between traces (unified)
var debug_timer = Timer.new()
var debug_ready: bool = true
var _debug_t = 0.0
var _last_debug_ms = 0
var _last_tag_ms = {}
var _last_cam_yaw = -999.0
var _last_dir = Vector3.ZERO
export(float, 0.0, 1.0, 0.01) var debug_yaw_threshold = 0.05 # rad (~3°)
export(float, 0.0, 1.0, 0.01) var debug_dir_threshold = 0.05 # vector length change
export var invert_joy_x = false
export var invert_joy_y = false
var _last_anim_node = ""
var _last_is_floating = false
var has_seen_floor_once = false
var time_since_start = 0.0
export var startup_floating_block_time = 0.6
var _debug_input_last = 0.0

var _touch_camera_connected := false

var direction_fixed: Dictionary = FixedVec3.zero()
var direction = Vector3.ZERO
var horizontal_velocity = Vector3.ZERO
var velocity = Vector3.ZERO
var pre_move_velocity_for_replay = Vector3.ZERO
var _last_replay_corr = Vector3.ZERO
var platform_velocity = Vector3.ZERO
var airborne_inherited = Vector3.ZERO
var last_platform_velocity = Vector3.ZERO
var horizontal_velocity_fixed: Dictionary = FixedVec3.zero()
var vertical_velocity_fixed: Dictionary = FixedVec3.zero()
var movement_speed = 0.0
var acceleration = 15.0

var is_walking := false
var is_running := false

onready var ground_ray: RayCast = $GroundRay
onready var fake_shadow: MeshInstance = $PilotMesh/FakeShadow

# Local gravity override from zones (WindZone)
var local_gravity_override := Vector3.ZERO

func set_gravity_override(g: Vector3) -> void:
	local_gravity_override = g

func clear_gravity_override() -> void:
	local_gravity_override = Vector3.ZERO

# Public interface for platforms/conveyors to transfer velocity (now in fixed-point)
func set_external_velocity_fixed(v: Dictionary) -> void:
	if external_velocity:
		external_velocity.set_external_velocity(FixedVec3.to_vec3(v))
	else:
		platform_velocity_fixed = v

func _ready():
	process_priority = 0  # Ensure player physics runs after replay and camera
	# Connect to GameGlobals for debug mode
	if GameGlobals:
		debug_enabled = GameGlobals.debug_mode
		GameGlobals.connect("debug_mode_changed", self, "_on_debug_mode_changed")
		# Set mouse capture immediately
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if UIManager:
		UIManager.connect("overlay_shown", self, "_on_UIManager_overlay_shown")
		UIManager.connect("overlay_hidden", self, "_on_UIManager_overlay_hidden")

	# Align initial direction with the front of the mesh and the camera
	var yaw_node = get_node_or_null("CameraRig/Yaw")
	var yaw_angle = 0.0
	if yaw_node:
		yaw_angle = yaw_node.global_transform.basis.get_euler().y + cam_yaw_offset
	# Use front of the mesh for animation consistency at the beginning
	var initial_direction = Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	# If the camera exists, rotate the direction by its yaw for camera-relative input
	initial_direction = initial_direction.rotated(Vector3.UP, yaw_angle)
	if movement_comp:
		movement_comp.direction = initial_direction
	if ground_ray:
		ground_ray.enabled = true
		ground_ray.add_exception(self)

	if debug_movement or debug_shadow:
		debug_timer.wait_time = 0.5
		debug_timer.wait_time = 0.5
		debug_timer.one_shot = false
		debug_timer.connect("timeout", self, "_on_debug_timer_timeout")
		add_child(debug_timer)
		debug_timer.start()

	# Initialize AnimationTree conditions to avoid entering Swim at the start
	if animation_tree:
		animation_tree["parameters/conditions/IsOnFloor"] = true
		animation_tree["parameters/conditions/IsInAir"] = false
		animation_tree["parameters/conditions/IsFloating"] = false
	# Simple initialization: nothing to smooth from the body's yaw
	_sync_camera_mode()
	

func _connect_touch_camera():
	var current_scene = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return # Scene is not ready, try again next frame.
	var touch_controls = current_scene.find_node("TouchControls", true, false)
	if touch_controls:
		var camera_input = touch_controls.get_node_or_null("CameraInput")
		if camera_input:
			if not camera_input.is_connected("camera_vector_changed", self, "_on_CameraInput_camera_vector_changed"):
				var err = camera_input.connect("camera_vector_changed", self, "_on_CameraInput_camera_vector_changed")
				if err == OK:
					_touch_camera_connected = true

func _on_CameraInput_camera_vector_changed(vector):
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig and cam_rig.has_method("process_camera_rotation"):
		cam_rig.process_camera_rotation(vector * touch_sensitivity)

func _on_debug_mode_changed(enabled: bool):
	debug_enabled = enabled

func set_player_id(id: int) -> void:
	"""Set player ID from outside and propagate to components."""
	player_id = id
	
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig and cam_rig.has_method("set_player_id"):
		cam_rig.set_player_id(id)
	else:
		if id == 2:
			push_warning("CameraRig node not found or it's missing the set_player_id method.")
	
func set_external_source_is_static(is_static: bool) -> void:
	platform_is_static_surface = is_static

var _is_ui_overlay_active = false
func _on_UIManager_overlay_shown():
	_is_ui_overlay_active = true
func _on_UIManager_overlay_hidden():
	_is_ui_overlay_active = false

func _input(event):
	# InputState manages input globally. Here only overlays and camera synchronization.
	if _is_ui_overlay_active:
		return
	if event.is_action_pressed("aim"):
		var cam_rig = get_node_or_null("CameraRig")
		if cam_rig and cam_rig.has_method("sync_to_body_yaw"):
			cam_rig.sync_to_body_yaw(rotation.y, cam_yaw_offset)
		direction = $CameraRig/Yaw.global_transform.basis.z
	if event.is_action_released("aim"):
		player_mesh.rotation.y = rotation.y + mesh_yaw_offset

func _process(_delta):
	if has_node("FPSLabel"):
		$FPSLabel.text = "FPS: " + str(Engine.get_frames_per_second())

func roll():
	if InputState and InputState.is_action_pressed("roll"):
		if !roll_node_name in playback.get_current_node() and !jump_node_name in playback.get_current_node() and !bigattack_node_name in playback.get_current_node():
			playback.start(roll_node_name)
			horizontal_velocity_fixed = FixedVec3.from_vec3(direction * dash_power)

func attack1():
	if (idle_node_name in playback.get_current_node() or walk_node_name in playback.get_current_node()) and is_on_floor():
		if InputState and InputState.is_action_pressed("attack"):
			if (is_attacking == false):
				playback.travel(attack1_node_name)

func attack2():
	if attack1_node_name in playback.get_current_node():
		if InputState and InputState.is_action_pressed("attack"):
			playback.travel(attack2_node_name)

func attack3():
	if attack1_node_name in playback.get_current_node():
		if InputState.is_action_pressed("attack"):
			pass

func rollattack():
	if roll_node_name in playback.get_current_node():
		if InputState and InputState.is_action_pressed("attack"):
			playback.travel(bigattack_node_name)

func bigattack():
	if run_node_name in playback.get_current_node():
		if InputState and InputState.is_action_pressed("attack"):
			horizontal_velocity_fixed = FixedVec3.from_vec3(direction * dash_power)
			playback.travel(bigattack_node_name)

func _on_debug_timer_timeout():
	debug_ready = true
	# Debounce logs

func _can_log() -> bool:
	var now := OS.get_ticks_msec()
	var interval_ms := int(debug_interval * 1000.0)
	if now - _last_debug_ms >= interval_ms:
		_last_debug_ms = now
		return true
	return false

func _can_log_tag(tag: String) -> bool:
	var now := OS.get_ticks_msec()
	var interval_ms := int(debug_interval * 1000.0)
	var last := int(_last_tag_ms.get(tag, 0))
	if now - last >= interval_ms:
		_last_tag_ms[tag] = now
		return true
	return false

func print_debug(msg: String) -> void:
	# Simple and centralized debounce for any debug output
	if not debug_enabled:
		return
	if _can_log():
		print(msg)

func print_debug_tag(tag: String, msg: String) -> void:
	if not debug_enabled:
		return
	if _can_log_tag(tag):
		print(msg)

func _debug_input_snapshot() -> Dictionary:
	   if not InputState:
		   return { "move_x": 0.0, "move_y": 0.0, "run": false, "jump": false }
	   return {
		   "move_x": InputState.get_axis("move_x"),
		   "move_y": InputState.get_axis("move_y"),
		   "run": InputState.is_action_pressed("run"),
		   "jump": InputState.is_action_pressed("jump")
	   }

func _align_camera_to_body():
	"""
	Called deferred from PlayerManager after spawn to correctly initialize camera yaw.
	"""
	# Respect local replay flag first to ensure PlayerManager/ReplayPlayback
	# can control camera restore deterministically.
	if is_replaying or (GameGlobals and GameGlobals.is_replaying):
		print("[PlayerController] _align_camera_to_body: Skipping auto-align because replay active (is_replaying=", is_replaying, ")")
		return

	var cam_rig = get_node_or_null("CameraRig")
	if not cam_rig or not cam_rig.has_method("sync_to_body_yaw"):
		print("[PlayerController] _align_camera_to_body: CameraRig or sync_to_body_yaw not found.")
		return

	# Prefer recorded yaw/pitch when a replay is loaded. Use ReplayManager/playback
	# detection instead of relying solely on GameGlobals to handle timing issues
	# during scene/spawn ordering.
	var rm = get_node_or_null("/root/ReplayManager")
	if rm:
		var pb = null
		if rm.has_method("get_playback_node"):
			pb = rm.get_playback_node()
		else:
			pass
			pb = rm.get_node_or_null("ReplayPlayback")
		if pb and pb.current_replay:
			var initials = pb.current_replay.initial_states
			if initials and typeof(initials) == TYPE_DICTIONARY:
				# 1) Prefer explicit camera_yaw/camera_pitch shortcuts
				if initials.has("camera_yaw") and initials.has("camera_pitch"):
					var state = {"yaw": initials["camera_yaw"], "pitch": initials["camera_pitch"]}
					if cam_rig.has_method("set_replay_state"):
						cam_rig.set_replay_state(state)
						print("[PlayerController] _align_camera_to_body: Applied recorded camera_yaw/pitch from initial_states")
						return
				# 2) Direct camera dict
				if initials.has("camera") and cam_rig.has_method("set_replay_state"):
					cam_rig.set_replay_state(initials["camera"])
					print("[PlayerController] _align_camera_to_body: Applied recorded camera dict from initial_states")
					return
				# 3) Search for camera-like keys (CameraRig, camera_node_name, etc.)
				for key in initials.keys():
					var kl = str(key).to_lower()
					if kl.find("camera") != -1 or kl.find("camerarig") != -1:
						var camdict = initials[key]
						if camdict and cam_rig.has_method("set_replay_state"):
							cam_rig.set_replay_state(camdict)
							print("[PlayerController] _align_camera_to_body: Applied recorded camera from key: " + str(key))
							return
			# If replay is present but we couldn't find camera data, skip forcing the PI offset.
			print("[PlayerController] _align_camera_to_body: Replay active but no recorded camera state found; skipping auto-offset")
			return

	# If we're in replay mode but the ReplayPlayback node or current_replay
	# isn't available yet (spawn ordering), avoid applying the live PI offset
	# so the playback system can set the camera state later when it's ready.
	if GameGlobals and GameGlobals.is_replaying:
		print("[PlayerController] _align_camera_to_body: Replay mode active but no playback-ready camera data yet; skipping auto-offset until playback applies camera.")
		return

	# Normal live path: align behind the body using PI offset
	var body_yaw = global_transform.basis.get_euler().y
	# Use PI as offset to look from behind, consistent with respawn logic.
	var offset = PI
	cam_rig.sync_to_body_yaw(body_yaw, offset)
	print("[PlayerController] _align_camera_to_body: Synced camera to body yaw ", rad2deg(body_yaw), " with offset ", rad2deg(offset))

func _check_and_align_camera() -> void:
	# Wrapper called deferred by PlayerManager. Delegate to _align_camera_to_body
	# The _align_camera_to_body implementation already handles replay vs live.
	# Give the engine a couple of idle frames to let ReplayPlayback/startup set
	# global replay flags and for the playback system to apply initial camera state.
	if get_tree():
		yield(get_tree(), "idle_frame")
		yield(get_tree(), "idle_frame")
	_align_camera_to_body()

var _last_input_state = {}



func _physics_process(delta: float):
	# Physics logic for REPLAY mode. Uses fixed-point and fixed delta.
	var has_input := false
	var movement_this_frame := Vector3.ZERO
	var is_replaying = GameGlobals and GameGlobals.is_replaying
	var is_test_mode = GameGlobals and GameGlobals.is_test_mode
	var replay_manager = get_node_or_null("/root/ReplayManager")
	var effective_delta = delta # This will be FIXED_DELTA

	# To ensure determinism, we use a fixed delta in all relevant modes.
	# This is CRITICAL for recording and playback to be identical.
	if is_replaying or is_test_mode or (InputState and InputState.mode == InputState.Mode.RECORD) or (GameGlobals and GameGlobals.is_recording):
		effective_delta = 1.0 / 60.0

	# Don't connect touch camera in replay

	time_since_jump += effective_delta
	time_since_input += effective_delta
	time_since_start += effective_delta

	var on_floor = is_on_floor() # Estado físico real
	var effective_on_floor = on_floor # Por defecto, usar el estado real

	# Force Full Traction: During replay, use the recorded 'is_on_floor' state.
	if is_replaying and InputState.mode == InputState.Mode.PLAYBACK and InputState.replay_frame < InputState.recorded_frames.size():
		var frame_data = InputState.recorded_frames[InputState.replay_frame]
		effective_on_floor = frame_data.get("is_on_floor", on_floor)

	# Declare input variables
	var input_vector := Vector2.ZERO
	var mouse_motion = null
	var is_sprinting = false
	var jump_pressed = false

	# Process player input desde InputState (both normal and replay)
	if InputState:
		input_vector = Vector2(
			-InputState.get_axis("move_x") if InputState.get_axis("move_x") != null else 0.0,
			InputState.get_axis("move_y") if InputState.get_axis("move_y") != null else 0.0
		)
		mouse_motion = InputState.get_mouse_delta()
		is_sprinting = InputState.is_action_pressed("run")
		jump_pressed = InputState.is_action_pressed("jump")
	has_input = input_vector.length() > 0.1

	# Reset strafe_cooldown if there is input, only decrement if there is NO input
	if input_vector.length() > 0.1:
		strafe_cooldown = 0.0
	else:
		strafe_cooldown = max(0.0, strafe_cooldown - effective_delta)

	# --- MOVEMENT LOGIC: RUNS FOR BOTH NORMAL AND REPLAY ---

	# Process attacks and rolls that can affect movement
	rollattack()
	bigattack()
	attack1()
	attack2()
	roll()

	# Measure time in the Jump state of the AnimationTree
	var in_jump_state = (playback and (playback.get_current_node() == jump_node_name))
	if in_jump_state:
		time_in_jump_state += effective_delta
	else:
		time_in_jump_state = 0.0

	# Mark that we have seen the ground at least once to enable floating after the start
	if effective_on_floor:
		has_seen_floor_once = true
	
	# Reset movement parameters
	movement_speed = 0
	angular_acceleration = 10
	acceleration = 15

	# Effective gravity: use override if it exists
	var effective_gravity_vector = local_gravity_override if (local_gravity_override.length() > 0.01) else (Vector3.DOWN * gravity)
	var effective_gravity_mag = effective_gravity_vector.length()
	var effective_gravity_dir = effective_gravity_vector.normalized() if (effective_gravity_mag > 0.01) else Vector3.DOWN

	# --- GRAVITY: use fixed-point math only ---
	var gravity_fixed = FixedPoint.to_fixed(effective_gravity_vector.y)
	var gravity_dt_fixed = FixedPoint.to_fixed(effective_delta)

	if not effective_on_floor:
		var gravity_impulse = FixedPoint.fixed_mul(gravity_fixed, gravity_dt_fixed)
		vertical_velocity_fixed.y = FixedPoint.fixed_add(vertical_velocity_fixed.y, gravity_impulse)
	else:
		# When standing on floor, reset vertical velocity to zero
		vertical_velocity_fixed.y = 0

	# Clamp vertical velocity to avoid spikes (fixed-point)
	var max_fall_fixed_pos = FixedPoint.to_fixed(max_fall_speed)
	var max_rise_fixed = FixedPoint.to_fixed(max_rise_speed)
	if vertical_velocity_fixed.y < -max_fall_fixed_pos:
		vertical_velocity_fixed["y"] = -max_fall_fixed_pos
	if vertical_velocity_fixed.y > max_rise_fixed:
		vertical_velocity_fixed["y"] = max_rise_fixed
	# Debug clamp

	# Check for attack/roll states that modify acceleration
	if (attack1_node_name in playback.get_current_node()) or (attack2_node_name in playback.get_current_node()) or (bigattack_node_name in playback.get_current_node()):
		is_attacking = true
	else:
		is_attacking = false

	if bigattack_node_name in playback.get_current_node():
		acceleration = 3

	if roll_node_name in playback.get_current_node():
		is_rolling = true
		acceleration = 2
		angular_acceleration = 2
	else:
		is_rolling = false
	

	# Movement and rotation control

	# Handle Jump (fixed-point)
	if jump_pressed and ((is_attacking != true) and (is_rolling != true)) and effective_on_floor:
		if AudioSystem: AudioSystem.play_sfx("res://assets/sfx/jump.wav")
		var jump_force_fixed = FixedPoint.to_fixed(jump_force)
		vertical_velocity_fixed = {"x": 0, "y": jump_force_fixed, "z": 0}

		if inherit_vertical_platform_jump and platform_velocity_fixed.y > 0:
			var max_up_follow_fixed = FixedPoint.to_fixed(max_platform_up_follow)
			var platform_y_clamped = min(platform_velocity_fixed.y, max_up_follow_fixed)
			var new_y_fixed = FixedPoint.fixed_add(vertical_velocity_fixed.y, platform_y_clamped)
			vertical_velocity_fixed = {"x": 0, "y": new_y_fixed, "z": 0}

		snap_enabled = false
		# Store inherited horizontal impulse from platform in fixed-point.
		airborne_inherited_fixed = {"x": platform_velocity_fixed.x, "y": 0, "z": platform_velocity_fixed.z}
		airborne_inherited = Vector3.ZERO # Clear the float version to avoid confusion
		just_jumped = true
		time_since_jump = 0.0

	if has_input:
		time_since_input = 0.0

	# Camera Control (runs for both normal and replay)
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig:
		if cam_rig.has_method("process_camera_rotation"):
			   if mouse_motion != null:
				   # cam_rig.process_camera_rotation(mouse_motion) # Desactivado: la cámara gestiona su propio input en _physics_process
				   pass
		# Removed mouse_active_timer logic, now handled in InputState
		
		if movement_comp:
			# --- Strafe Mode Logic ---
			# The strafing state is managed centrally by InputState.gd. Only update
			# the strafing timer when in LIVE or RECORD modes (user input present).
			if InputState.mode == InputState.Mode.LIVE or InputState.mode == InputState.Mode.RECORD:
				if InputState.mouse_delta.length() > 0.0:
					InputState.is_strafing_mode_active = true
					InputState.strafing_timer = 5.0
				elif InputState.is_strafing_mode_active:
					if InputState.mouse_delta.length() > 0.0:
						InputState.strafing_timer = 5.0
					else:
						InputState.strafing_timer -= effective_delta
						if InputState.strafing_timer <= 0.0:
							InputState.is_strafing_mode_active = false
							strafe_cooldown = 0.5 # Prevent sudden turn after strafe
			
			var strafe_mode_active = InputState.is_strafing_mode_active
			if GameGlobals and GameGlobals.is_replaying:
				strafe_mode_active = InputState.is_strafing_mode_active
			# Set strafe mode in movement component (always) so the component
			# behaves consistently in PLAYBACK too.
			if movement_comp:
				movement_comp.strafe_mode = strafe_mode_active
			
			var turn_input_val = input_vector.x
			var movement_input_vec = input_vector
			var yaw_delta = 0.0
			if strafe_mode_active:
				# In strafe mode, block body rotation (Yaw): DO NOT modify rotation.y
				turn_input_val = 0.0
				yaw_delta = 0.0
			else:
				# In tank mode, allow normal turning
				turn_input_val = input_vector.x
				movement_input_vec.x = 0.0
				var effective_tank_speed = tank_turn_speed
				yaw_delta = turn_input_val * effective_tank_speed * effective_delta
				rotation.y += yaw_delta
				if cam_rig.has_method("apply_external_yaw_delta"): cam_rig.apply_external_yaw_delta(yaw_delta)

			# Prevent sudden turn after strafe ends
			if strafe_cooldown > 0.0:
				# Block turning during cooldown
				yaw_delta = 0.0

			# 2. Process movement with the modified input vector
			var basis := Basis()
			var yaw_node_local = get_node_or_null("CameraRig/Yaw")
			if yaw_node_local:
				basis = yaw_node_local.global_transform.basis # 3. El PlayerController lee la cámara DESPUÉS de que el Replay la haya rotado
				# Always call process_input_vector so the movement component can
				# compute its internal velocities from recorded input during PLAYBACK.
				movement_comp.process_input_vector(effective_delta, basis, movement_input_vec, is_sprinting if is_sprinting != null else false, effective_on_floor if effective_on_floor != null else false)

			# 3. Get results from movement component
			direction = movement_comp.direction
			var new_horiz = movement_comp.get_horizontal_velocity()
			# Preserve inertia: if on floor or movement component provides a non-trivial
			# horizontal velocity, accept it; otherwise keep previous horizontal_velocity
			# which may include airborne_inherited from a recent jump.
			if effective_on_floor or new_horiz.length() > 0.01:
				horizontal_velocity = new_horiz
			# else: keep existing horizontal_velocity (preserves inherited/platform impulse)
			is_walking = movement_comp.is_walking
			is_running = movement_comp.is_running
		else:
			is_walking = false; is_running = false; direction = Vector3.ZERO; horizontal_velocity = Vector3.ZERO
	
	# Platform velocity logic (fixed-point)
		var zero_fixed = FixedVec3.zero()
		# Friction-like slowdown for platform velocity
		if not is_replaying:
			var lerp_factor_fixed = FixedPoint.fixed_mul(FixedPoint.to_fixed(6.0), FixedPoint.to_fixed(effective_delta))
			platform_velocity_fixed = FixedVec3.lerp(platform_velocity_fixed, zero_fixed, lerp_factor_fixed)

		if effective_on_floor:
			last_platform_velocity_fixed = platform_velocity_fixed
			airborne_inherited_fixed = FixedVec3.zero()
			airborne_inherited = Vector3.ZERO

			if platform_velocity_fixed.y > 0 and not just_jumped:
				var max_up_follow_fixed = FixedPoint.to_fixed(max_platform_up_follow)
				var platform_y_clamped = min(platform_velocity_fixed.y, max_up_follow_fixed)
				vertical_velocity_fixed = {"x": 0, "y": platform_y_clamped, "z": 0}
			else:
				# If standing on floor and not inheriting upward platform impulse, this is handled by the main gravity logic
				pass
		elif was_on_floor:
			# Set inherited impulse when leaving a platform
			airborne_inherited_fixed = {"x": last_platform_velocity_fixed.x, "y": 0, "z": last_platform_velocity_fixed.z}

		# Build horizontal movement in fixed-point.
		var movement_comp_h_fixed = FixedVec3.from_vec3(movement_comp.get_horizontal_velocity() if movement_comp else Vector3.ZERO)
		
		var movement_contrib_fixed = movement_comp_h_fixed
		if not effective_on_floor:
			var air_control_fixed = FixedPoint.to_fixed(air_control_multiplier)
			movement_contrib_fixed = FixedVec3.mul(movement_contrib_fixed, air_control_fixed)

		var platform_part_fixed = FixedVec3.zero()
		if effective_on_floor and platform_is_static_surface:
			platform_part_fixed = {"x": platform_velocity_fixed.x, "y": 0, "z": platform_velocity_fixed.z}

		var inherited_part_fixed = FixedVec3.zero()
		if not effective_on_floor:
			inherited_part_fixed = airborne_inherited_fixed

		var target_fixed = FixedVec3.add(movement_contrib_fixed, FixedVec3.add(platform_part_fixed, inherited_part_fixed))

		# Inertia rule (lerp)
		if effective_on_floor:
			horizontal_velocity_fixed = target_fixed
		else:
			var t_float = acceleration * 0.2 * effective_delta
			var t_fixed = FixedPoint.to_fixed(min(t_float, 1.0))
			horizontal_velocity_fixed = FixedVec3.lerp(horizontal_velocity_fixed, target_fixed, t_fixed)

		# For downstream logic that might still use the float version (e.g. debug prints)
		horizontal_velocity = FixedVec3.to_vec3(horizontal_velocity_fixed)
		# combined_horizontal_fixed is the authoritative horizontal in fixed domain
		var combined_horizontal_fixed = horizontal_velocity_fixed
		var movement_this_frame_fixed = FixedVec3.add(combined_horizontal_fixed, vertical_velocity_fixed)
		movement_this_frame = FixedVec3.to_vec3(movement_this_frame_fixed)


	# --- LOGIC THAT RUNS IN BOTH MODES ---

	# Rotate mesh towards movement direction
	if direction != Vector3.ZERO:
		var target_y = atan2(direction.x, direction.z) + mesh_yaw_offset
		var parent_y = rotation.y
		var local_target_y = target_y - parent_y
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, local_target_y, effective_delta * angular_acceleration)

	var h_rot := 0.0
	var yaw_node2 = get_node_or_null("CameraRig/Yaw")
	if yaw_node2: h_rot = yaw_node2.global_transform.basis.get_euler().y + cam_yaw_offset

	# print("[PlayerController] Pre-move: velocity=%s, on_floor=%s" % [movement_this_frame, on_floor])
	pre_move_velocity_for_replay = movement_this_frame
	
	# Snap to ground
	var snap_vec = Vector3.ZERO
	if effective_on_floor and snap_enabled:
		snap_vec = -get_floor_normal() * snap_len
	elif on_floor:
		snap_enabled = true

	# --- THE ACTUAL PHYSICS STEP ---
	var pos_before = global_transform.origin


	if GameGlobals and GameGlobals.is_replaying and debug_force_direct_move:
		# Modo de diagnóstico: aplicar movimiento directamente (no física)
		global_transform.origin = global_transform.origin + movement_this_frame * effective_delta
		velocity = Vector3(movement_this_frame.x, movement_this_frame.y, movement_this_frame.z)
	else:
		velocity = move_and_slide_with_snap(movement_this_frame, snap_vec, Vector3.UP, false)
		var pos_after = global_transform.origin
		var disp = pos_after - pos_before

	# print("[PlayerController] Post-move Pos (Simulated): %s" % [global_transform.origin])
	# print("[PlayerController POST-SLIDE] Velocity: %s" % [velocity])
	
		# Update velocity components from the result for the next frame
		horizontal_velocity = velocity - Vector3(0, velocity.y, 0)
		horizontal_velocity_fixed = FixedVec3.from_vec3(horizontal_velocity)
		if movement_comp:
			movement_comp.horizontal_velocity = horizontal_velocity
		# If we're on the floor in replay, reset vertical fixed velocity to zero to avoid residuals
		if effective_on_floor:
			vertical_velocity_fixed = FixedVec3.zero()
		else:
			vertical_velocity_fixed = FixedVec3.from_vec3(Vector3(0, velocity.y, 0))
	
	# Snapping to zero to prevent numerical drift
	if effective_on_floor and horizontal_velocity.length_squared() < 0.0001:
		horizontal_velocity = Vector3.ZERO
		horizontal_velocity_fixed = FixedVec3.zero()
		velocity.x = 0.0
		velocity.z = 0.0
		if movement_comp:
			movement_comp.horizontal_velocity = Vector3.ZERO
	
	was_on_floor = on_floor # was_on_floor debe usar el estado real para la lógica del siguiente frame
	just_jumped = false # Reset one-frame flag

	# --- FAKE SHADOW & ANIMATIONS ---
	_update_animations_and_fx(effective_on_floor, is_walking, is_running, effective_delta)

func _update_animations_and_fx(on_floor: bool, is_walking: bool, is_running: bool, delta: float):
	# Animation and visual effects logic that is common to both modes.
	if ground_ray.is_colliding():
		var hit = ground_ray.get_collision_point()
		fake_shadow.global_transform.origin = Vector3(hit.x, hit.y + 0.01, hit.z)
		var dist = global_transform.origin.y - hit.y
		var s = clamp(0.6 + dist * 0.4, 0.5, 2.0)
		fake_shadow.scale = Vector3(s, 1.0, s)
		var mat = fake_shadow.get_surface_material(0)
		if mat: mat.albedo_color.a = clamp(1.0 - dist * 0.4, 0.2, 0.9)
		fake_shadow.visible = true
	else:
		fake_shadow.visible = false

	# Animation Tree Updates
	animation_tree["parameters/conditions/IsOnFloor"] = on_floor
	animation_tree["parameters/conditions/IsInAir"] = !on_floor
	animation_tree["parameters/conditions/IsWalking"] = is_walking
	animation_tree["parameters/conditions/IsNotWalking"] = !is_walking
	animation_tree["parameters/conditions/IsRunning"] = is_running
	animation_tree["parameters/conditions/IsNotRunning"] = !is_running

	# Floating state logic (uses vertical_velocity_fixed, which is now post-slide)
	var vertical_velocity_y_float = FixedPoint.from_fixed(vertical_velocity_fixed.y)
	var v_accel = 0.0
	if delta > 0.0: v_accel = (vertical_velocity_y_float - _prev_vy) / delta
	_prev_vy = vertical_velocity_y_float
	_vaccel_smoothed = lerp(_vaccel_smoothed, v_accel, floating_accel_smooth)
	var vertical_accel = abs(_vaccel_smoothed)
	var vspeed_raw = abs(vertical_velocity_y_float)
	_vspeed_smoothed = lerp(_vspeed_smoothed, vspeed_raw, floating_vspeed_smooth)
	var vertical_speed = _vspeed_smoothed

	var falling_without_jump = (!on_floor) and (time_since_jump > floating_without_jump_delay)
	var no_input_ok = (not floating_without_jump_requires_no_input) or (time_since_input > floating_no_input_delay)
	var accel_ok = (_last_is_floating and (vertical_accel <= floating_exit_accel_threshold)) or ((not _last_is_floating) and (vertical_accel <= floating_enter_accel_threshold))
	var vspeed_ok = (_last_is_floating and (vertical_speed < floating_exit_vspeed_threshold)) or ((not _last_is_floating) and (vertical_speed < floating_enter_vspeed_threshold))
	var startup_block_clear = has_seen_floor_once or (time_since_start > startup_floating_block_time)
	var should_float = startup_block_clear and (!on_floor) and (accel_ok or (falling_without_jump and vspeed_ok)) and (not is_attacking) and (not is_rolling) and (
		((time_since_jump > floating_after_jump_delay) and (time_since_input > floating_no_input_delay))
		or (time_in_jump_state > floating_from_jump_delay)
		or (falling_without_jump and no_input_ok)
	)
	animation_tree["parameters/conditions/IsFloating"] = should_float
	_last_is_floating = should_float


# Respawn-safe reset of transient movement state
func reset_state_for_respawn(new_transform: Transform) -> void:
	"""
	Completely resets the player's state for a respawn.
	Sets the new position/rotation and clears all speeds,
	action states and residual inputs.
	"""
	# 1. Set new position and orientation
	global_transform = new_transform

	# 1.5. Reset mesh rotation to look forward
	if player_mesh:
		# The rotation of the body (KinematicBody) is already set with global_transform.
		# The mesh, being a child node, only needs its local rotation offset.
		player_mesh.rotation.y = mesh_yaw_offset

	# 2. Reset camera orientation
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig:
		# The cause of the problems is the smoothing loop in PlayerSpringCam.gd,
		# which reverts changes if its `target_yaw` is not updated.
		# The sync_to_body_yaw() function does this, but it fails on respawn for state reasons.
		# The solution is a manual and direct reimplementation here.
		var yaw_node = cam_rig.get_node_or_null("Yaw")
		if yaw_node and cam_rig.has_method("set"):
			# The camera rig is aligned with the body. It is assumed that the SpringArm handles the position "behind".
			var final_cam_yaw = new_transform.basis.get_euler().y + PI
			
			# 1. Set the rotation of the node directly
			yaw_node.rotation.y = final_cam_yaw
			
			# 2. Set the TARGET of the smoothing so that it does not revert the change
			cam_rig.set("target_yaw", final_cam_yaw)

			# 3. Reset the pitch in the same way
			var pitch_node = yaw_node.get_node_or_null("Pitch")
			if pitch_node:
				pitch_node.rotation.x = 0.0
				cam_rig.set("target_pitch", 0.0)
			
		else:
			pass

	# 3. Reset residual mouse input (if applicable, delegate to InputState or camera)
	if InputState.has_method("reset_mouse_motion"):
		InputState.reset_mouse_motion()

	# 4. Reset speeds and movement status
	if has_node("GroundRay"):
		$GroundRay.force_raycast_update()
	horizontal_velocity = Vector3.ZERO
	horizontal_velocity_fixed = FixedVec3.zero()
	vertical_velocity_fixed = FixedVec3.zero()
	platform_velocity_fixed = FixedVec3.zero()
	last_platform_velocity = Vector3.ZERO
	airborne_inherited = Vector3.ZERO
	
	# Resets the direction of movement so that the character does not try to move.
	# The orientation of the body is already established by global_transform.
	direction = Vector3.ZERO
	if is_instance_valid(movement_comp):
		movement_comp.direction = Vector3.ZERO
		movement_comp.horizontal_velocity = Vector3.ZERO

	# 5. Clear action flags
	is_rolling = false
	is_attacking = false
	just_jumped = false
	snap_enabled = true

func _string_to_vector3(s: String) -> Vector3:
	s = s.trim_prefix("(").trim_suffix(")")
	var parts = s.split(",")
	if parts.size() == 3:
		return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return Vector3.ZERO

func dump_state() -> Dictionary:
	var state = {
		"global_transform_origin": global_transform.origin,
		"velocity": velocity,
		"is_on_floor": is_on_floor(),
		"just_jumped": just_jumped,
		"airborne_inherited": airborne_inherited,
		"platform_velocity_fixed": FixedVec3.to_vec3(platform_velocity_fixed),
		"rotation": rotation,
		"basis": global_transform.basis,
		"horizontal_velocity": horizontal_velocity,
		"horizontal_velocity_fixed": FixedVec3.to_vec3(horizontal_velocity_fixed),
		"vertical_velocity_fixed": FixedVec3.to_vec3(vertical_velocity_fixed),
		"direction": direction,
		"time_since_jump": time_since_jump,
		"time_since_input": time_since_input,
		"was_on_floor": was_on_floor,
		"snap_enabled": snap_enabled,
		"collisions": []
	}
	
	# Dump all slide collisions
	for i in range(get_slide_count()):
		var collision = get_slide_collision(i)
		state["collisions"].append({
			"collider": collision.collider.name if collision.collider else "null",
			"normal": collision.normal,
			"position": collision.position,
			"remainder": collision.remainder
		})
	
	return state

func _roundf(v: float) -> float:
	return round(v * 1000.0) / 1000.0

func _vec3_to_dict_round(v: Vector3) -> Dictionary:
	return {"x": _roundf(v.x), "y": _roundf(v.y), "z": _roundf(v.z)}

func _basis_to_dict_round(b: Basis) -> Dictionary:
	return {"x": _vec3_to_dict_round(b.x), "y": _vec3_to_dict_round(b.y), "z": _vec3_to_dict_round(b.z)}

func get_replay_state() -> Dictionary:
	if not is_inside_tree():
		return {}
	# Produce a JSON-safe, canonical representation with rounded floats

	var state = {
		"global_transform": {
			"basis": _basis_to_dict_round(global_transform.basis),
			"origin": _vec3_to_dict_round(global_transform.origin)
		},
		"player_position": _vec3_to_dict_round(global_transform.origin),
		"platform_velocity_fixed": ReplayUtils.vector3_to_dict(FixedVec3.to_vec3(platform_velocity_fixed)),
		"airborne_inherited": _vec3_to_dict_round(airborne_inherited),
		"just_jumped": bool(just_jumped),
		"time_since_jump": _roundf(time_since_jump),
		"time_since_input": _roundf(time_since_input),
		"was_on_floor": bool(was_on_floor),
		"snap_enabled": bool(snap_enabled),
		"rotation": _vec3_to_dict_round(rotation),
		"basis": _basis_to_dict_round(global_transform.basis),
		"velocity": _vec3_to_dict_round(velocity), # final velocity AFTER move_and_slide
		"pre_move_velocity": _vec3_to_dict_round(pre_move_velocity_for_replay),
		"calculated_direction": _vec3_to_dict_round(direction),

		# Fixed-point representations (retain for deterministic restore)
		"player_position_fixed": ReplayUtils.vector3_to_fixed_dict(global_transform.origin),
		"velocity_fixed": ReplayUtils.vector3_to_fixed_dict(velocity),
		"basis_fixed": ReplayUtils.basis_to_fixed_dict(global_transform.basis)
	}
	if jump_comp:
		state["coyote_timer"] = jump_comp.coyote_timer
		state["jump_buffer_timer"] = jump_comp.jump_buffer_timer
		state["should_jump_buffered"] = jump_comp.should_jump_buffered
	return state

func set_replay_state(state: Dictionary) -> void:
	var deserialized_state = ReplayUtils.from_json_safe(state)
	var is_replaying = GameGlobals and GameGlobals.is_replaying
	var replay_manager = get_node_or_null("/root/ReplayManager")

	# Restore state from the replay file - USE FIXED-POINT DATA FOR DETERMINISTIC PLAYBACK
	if state.has("player_position_fixed"):
		var pos_fixed = state["player_position_fixed"]
		if pos_fixed is Dictionary:
			global_transform.origin = ReplayUtils.fixed_dict_to_vector3(pos_fixed)
		else:
			global_transform.origin = deserialized_state.get("player_position", global_transform.origin)
	else:
		global_transform.origin = deserialized_state.get("player_position", global_transform.origin)
	
	if state.has("basis_fixed"):
		var basis_fixed = state["basis_fixed"]
		if basis_fixed is Dictionary:
			global_transform.basis = ReplayUtils.fixed_dict_to_basis(basis_fixed)
	elif deserialized_state.has("basis"):
		var basis_dict = deserialized_state["basis"]
		if basis_dict is Dictionary and basis_dict.has("x") and basis_dict.has("y") and basis_dict.has("z"):
			var basis_x = basis_dict["x"]
			var basis_y = basis_dict["y"]
			var basis_z = basis_dict["z"]
			if basis_x is Vector3 and basis_y is Vector3 and basis_z is Vector3:
				global_transform.basis = Basis(basis_x, basis_y, basis_z)
	
	var platform_velocity_vec = deserialized_state.get("platform_velocity_fixed", FixedVec3.to_vec3(platform_velocity_fixed))
	platform_velocity_fixed = FixedVec3.from_vec3(platform_velocity_vec)
	airborne_inherited = deserialized_state.get("airborne_inherited", Vector3.ZERO)
	just_jumped = deserialized_state.get("just_jumped", false)
	time_since_jump = deserialized_state.get("time_since_jump", 1.0)
	time_since_input = deserialized_state.get("time_since_input", 1.0)
	was_on_floor = deserialized_state.get("was_on_floor", false)
	snap_enabled = deserialized_state.get("snap_enabled", true)
	if deserialized_state.has("rotation"):
		rotation = deserialized_state["rotation"]

	# Restore velocity from fixed-point data for deterministic playback
	if state.has("velocity_fixed"):
		var vel_fixed = state["velocity_fixed"]
		if vel_fixed is Dictionary:
			velocity = ReplayUtils.fixed_dict_to_vector3(vel_fixed)
	else:
		velocity = deserialized_state.get("velocity", Vector3.ZERO)
	
	# CORRECCIÓN FINAL: Reset total y explícito de TODAS las velocidades al cargar estado de replay.
	# La velocidad debe ser generada por los inputs grabados, no restaurada de un snapshot.
	# Esto previene la inyección de velocidades finales acumuladas que causan la "flotación".
	velocity = Vector3.ZERO
	horizontal_velocity = Vector3.ZERO
	platform_velocity = Vector3.ZERO # Resetea la velocidad de la plataforma
	airborne_inherited = Vector3.ZERO # Resetea la inercia heredada en el aire
	horizontal_velocity_fixed = FixedVec3.zero() # Resetea la velocidad horizontal de punto fijo
	vertical_velocity_fixed = FixedVec3.zero() # Resetea la velocidad vertical de punto fijo
	platform_velocity_fixed = FixedVec3.zero() # Resetea la velocidad de plataforma de punto fijo
	airborne_inherited_fixed = FixedVec3.zero() # Resetea la inercia de punto fijo

	if jump_comp and deserialized_state.has("coyote_timer") and deserialized_state["coyote_timer"] != null:
		jump_comp.coyote_timer = deserialized_state["coyote_timer"]
	if jump_comp and deserialized_state.has("jump_buffer_timer") and deserialized_state["jump_buffer_timer"] != null:
		jump_comp.jump_buffer_timer = deserialized_state["jump_buffer_timer"]
	if jump_comp and deserialized_state.has("should_jump_buffered") and deserialized_state["should_jump_buffered"] != null:
		jump_comp.should_jump_buffered = deserialized_state["should_jump_buffered"]

	# Eliminado: limpieza de mouse_delta_x en replay para evitar conflicto con la cámara

func playback_process(frame_data_state: Dictionary, _delta: float) -> void:
	# During replay, state is now set directly by ReplayPlayback, so no physics simulation here
	# Just update derived variables if needed
	if frame_data_state.has("velocity"):
		velocity = ReplayUtils.dict_to_vector3(frame_data_state["velocity"])
		horizontal_velocity = velocity - Vector3(0, velocity.y, 0)
		if movement_comp:
			movement_comp.horizontal_velocity = horizontal_velocity
		vertical_velocity_fixed = FixedVec3.from_vec3(Vector3(0, velocity.y, 0))
		pre_move_velocity_for_replay = velocity
