extends Node

# TraversalLogicV2.gd - Deterministic Traversal State Machine for Odisea

enum TraversalState {
	NONE,
	CLIMBING,
	HANGING,
	SWINGING,
	MANTLING,
	ROPE_SLIDING
}

# --- STATE ---
var current_state = TraversalState.NONE
var is_active := false

# Logic Flags for PilotAnimatorV2
var is_climbing := false
var is_hanging := false
var is_swinging := false
var is_mantling := false
var is_rope_sliding := false

# Simulation Variables (Logic)
var is_1d_ladder := true
var ladder_min_offset := -1.5
var ladder_max_offset := 1.5
var ledge_anchor_point := Vector3.ZERO
var ledge_normal := Vector3.BACK
var ledge_half_width := 0.85
var hang_lateral_offset := 0.0
var _hang_attach_active := false
var _hang_attach_target := Vector3.ZERO
var _mantle_target_vertical := Vector3.ZERO
var _mantle_target_top := Vector3.ZERO
var ladder_anchor_point := Vector3.ZERO
var ladder_normal := Vector3.BACK
var _ladder_attach_active := false
var _ladder_attach_target := Vector3.ZERO
var swing_anchor_point := Vector3.ZERO
var swing_radius := 3.0
var rope_start := Vector3.ZERO
var rope_end := Vector3.ZERO

# Visual Interpolation
var anim_progress := 0.0 # 0.0 to 1.0 for visuals

# Internal Counters
var _swing_time := 0.0
var _mantle_time := 0.0
var _hang_crouch_drop_grace_left := 0.0
var _hang_mantle_input_grace_left := 0.0
var crouch_just_pressed := false

# --- TUNING ---
export(float) var climb_speed := 2.5
export(float) var shimmy_speed := 2.0
export(float) var mantle_duration := 0.6
export(float) var mantle_up_offset := 0.95
export(float) var mantle_forward_offset := 0.8
export(float) var traversal_jump_vertical_multiplier := 1.05
export(float) var traversal_jump_push_force := 2.8
export(float) var traversal_jump_detach_distance := 0.18
export(float) var traversal_camera_collision_grace := 0.22
export(float) var ledge_regrab_cooldown_time_above := 0.7
export(float) var ledge_regrab_cooldown_time_below := 0.4
export(float) var hang_drop_push_force := 1.2
export(float) var hang_drop_vertical_velocity := 0.35
export(float) var ladder_regrab_cooldown_time := 0.2
export(float) var swing_frequency := 1.5
export(float) var rope_slide_speed := 8.0
export(float) var hang_body_down_offset := 1.15
export(float) var hang_body_back_offset := 0.45
export(float) var hang_crouch_drop_grace := 0.25
export(float) var hang_mantle_input_grace := 0.18
export(float) var hang_attach_speed := 8.5
export(float) var ladder_attach_speed := 5.2
export(float) var ladder_auto_enter_vertical_below_margin := 0.45
export(float) var ladder_auto_enter_vertical_above_margin := 0.7
export(float) var ladder_auto_enter_lateral_limit := 0.68
export(float) var ladder_auto_enter_depth_limit := 0.68
export(float) var ladder_crouch_top_margin := 0.35
export(float) var ladder_crouch_vertical_below_margin := 0.8
export(float) var ladder_crouch_vertical_above_margin := 1.0
export(float) var ladder_crouch_lateral_limit := 0.9
export(float) var ladder_crouch_depth_limit := 0.9
export(float) var ledge_crouch_min_vertical_from_above := 0.05
export(float) var ledge_crouch_max_vertical_from_above := 2.6
export(float) var ledge_crouch_lateral_margin := 0.35
export(float) var ledge_crouch_depth_limit := 1.35
export(float) var ledge_auto_hang_min_height := 0.75
export(float) var ledge_auto_hang_min_height_ratio := 0.42
export(float) var ledge_auto_hang_max_height := 1.6
export(float) var ledge_auto_hang_max_height_ratio := 0.9
export(float) var ledge_auto_hang_band_padding := 0.2
export(float) var ledge_auto_hang_max_rising_velocity := 0.05
export(float) var ledge_auto_hang_lateral_margin := 0.28
export(float) var ledge_auto_hang_depth_limit := 0.75
export(float) var post_traversal_strafe_latch_deadzone := 0.1
export(float) var post_traversal_strafe_release_coyote_time := 0.14
export(float) var post_traversal_face_wall_speed := 8.0

# --- DETERMINISTIC TRIGONOMETRY (LUT) ---
# Prevents floating-point drift across different CPU architectures for replays.
var _sin_lut := []
const LUT_SIZE := 360

func _ready():
	_init_trig_lut()

func _init_trig_lut():
	_sin_lut.resize(LUT_SIZE)
	for i in range(LUT_SIZE):
		_sin_lut[i] = sin(deg2rad(float(i)))

func deterministic_sin(angle_rad: float) -> float:
	var deg = int(rad2deg(angle_rad)) % LUT_SIZE
	if deg < 0: deg += LUT_SIZE
	return _sin_lut[deg]

func deterministic_cos(angle_rad: float) -> float:
	# cos(x) = sin(x + pi/2)
	var deg = (int(rad2deg(angle_rad)) + 90) % LUT_SIZE
	if deg < 0: deg += LUT_SIZE
	return _sin_lut[deg]

func apply_to_controller(controller) -> void:
	if controller == null:
		return
	if "traversal_jump_vertical_multiplier" in controller:
		controller.traversal_jump_vertical_multiplier = traversal_jump_vertical_multiplier
	if "traversal_jump_push_force" in controller:
		controller.traversal_jump_push_force = traversal_jump_push_force
	if "traversal_jump_detach_distance" in controller:
		controller.traversal_jump_detach_distance = traversal_jump_detach_distance
	if "traversal_camera_collision_grace" in controller:
		controller.traversal_camera_collision_grace = traversal_camera_collision_grace
	if "ledge_regrab_cooldown_time_above" in controller:
		controller.ledge_regrab_cooldown_time_above = ledge_regrab_cooldown_time_above
	if "ledge_regrab_cooldown_time_below" in controller:
		controller.ledge_regrab_cooldown_time_below = ledge_regrab_cooldown_time_below
	if "hang_drop_push_force" in controller:
		controller.hang_drop_push_force = hang_drop_push_force
	if "hang_drop_vertical_velocity" in controller:
		controller.hang_drop_vertical_velocity = hang_drop_vertical_velocity
	if "ladder_regrab_cooldown_time" in controller:
		controller.ladder_regrab_cooldown_time = ladder_regrab_cooldown_time

# --- CORE STEP ---
func step(dt: float, input: Vector2, current_pos: Vector3, crouch_pressed: bool = false) -> Vector3:
	if current_state == TraversalState.NONE:
		return current_pos

	match current_state:
		TraversalState.CLIMBING:
			return _step_climbing(dt, input, current_pos, crouch_pressed)
		TraversalState.HANGING:
			return _step_hanging(dt, input, current_pos, crouch_just_pressed)
		TraversalState.MANTLING:
			return _step_mantling(dt, current_pos)
		TraversalState.SWINGING:
			return _step_swinging(dt, input, current_pos)
		TraversalState.ROPE_SLIDING:
			return _step_rope_sliding(dt, current_pos)

	return current_pos

func _step_climbing(dt: float, input: Vector2, pos: Vector3, crouch_pressed: bool = false) -> Vector3:
	# 2D Surface (Up/Down/Left/Right)
	# input.y: -1 is Forward (Up on ladder), 1 is Backward (Down on ladder)
	# input.x: -1 is Left, 1 is Right

	var up_dir = Vector3.UP
	var right_dir = ladder_normal.cross(up_dir).normalized()
	if _ladder_attach_active:
		var attach_pos = pos.move_toward(_ladder_attach_target, ladder_attach_speed * dt)
		if attach_pos.distance_squared_to(_ladder_attach_target) <= 0.0004:
			attach_pos = _ladder_attach_target
			_ladder_attach_active = false
		return attach_pos
	var climb_input_y = input.y
	if crouch_pressed and climb_input_y < 0.5:
		climb_input_y = 1.0

	var input_x = 0.0 if is_1d_ladder else input.x
	var move_vec = (up_dir * -climb_input_y + right_dir * input_x) * climb_speed * dt
	var next_pos = pos + move_vec

	# Constrain climbing to the ladder plane and finite ladder height.
	var next_local = next_pos - ladder_anchor_point
	var clamped_y = clamp(next_local.dot(up_dir), ladder_min_offset, ladder_max_offset)
	var local_x = 0.0 if is_1d_ladder else next_local.dot(right_dir)
	next_pos = ladder_anchor_point + up_dir * clamped_y + right_dir * local_x

	# Auto-release at the top when the player keeps pushing upward.
	if climb_input_y < -0.1 and clamped_y >= ladder_max_offset - 0.02:
		next_pos += ladder_normal * 0.9 + Vector3.UP * 0.05
		exit()
		anim_progress = 0.0
		return next_pos

	# Auto-release at the bottom when the player keeps pushing downward.
	if climb_input_y > 0.1 and clamped_y <= ladder_min_offset + 0.02:
		next_pos -= ladder_normal * 0.45
		exit()
		anim_progress = 0.0
		return next_pos

	anim_progress = fposmod(anim_progress + move_vec.length() * 0.5, 1.0)
	return next_pos

func _step_hanging(dt: float, input: Vector2, pos: Vector3, crouch_just_pressed: bool) -> Vector3:
	# Ledge Traversal: Constrained to ledge tangent
	var tangent = ledge_normal.cross(Vector3.UP).normalized()
	_hang_crouch_drop_grace_left = max(0.0, _hang_crouch_drop_grace_left - dt)
	_hang_mantle_input_grace_left = max(0.0, _hang_mantle_input_grace_left - dt)

	# Keep the body in a stable hanging pose under and slightly away from the ledge.
	var hang_origin = ledge_anchor_point + Vector3.DOWN * hang_body_down_offset - ledge_normal * hang_body_back_offset
	if not _hang_attach_active:
		var move_h = input.x * shimmy_speed * dt
		hang_lateral_offset = clamp(hang_lateral_offset + move_h, -ledge_half_width, ledge_half_width)
	_hang_attach_target = hang_origin + tangent * hang_lateral_offset
	var next_pos = _hang_attach_target

	if input.y > 0.5 or (crouch_just_pressed and _hang_crouch_drop_grace_left <= 0.0):
		exit()
		anim_progress = 0.0
		return next_pos

	if _hang_attach_active:
		next_pos = pos.move_toward(_hang_attach_target, hang_attach_speed * dt)
		if next_pos.distance_squared_to(_hang_attach_target) <= 0.0004:
			next_pos = _hang_attach_target
			_hang_attach_active = false

	# Update anim_progress for shimmy visuals
	anim_progress = fposmod(anim_progress + abs(input.x) * dt, 1.0)

	return next_pos

func _step_mantling(dt: float, pos: Vector3) -> Vector3:
	_mantle_time += dt
	anim_progress = clamp(_mantle_time / mantle_duration, 0.0, 1.0)

	# Deterministic Mantle Path: simple L-shape with constant steps
	# target_top is approx the standing position on the platform
	var target_vertical = get_mantle_target_vertical()
	var target_top = get_mantle_target_top()

	var next_pos = pos
	var phase_duration = mantle_duration * 0.5
	var step_speed = mantle_up_offset / phase_duration # meters per second

	if anim_progress < 0.5:
		# Vertical phase
		next_pos = pos.move_toward(target_vertical, step_speed * dt)
	else:
		# Forward phase
		var forward_step_speed = mantle_forward_offset / phase_duration
		next_pos = pos.move_toward(target_top, forward_step_speed * dt)

	return next_pos

func get_mantle_target_vertical() -> Vector3:
	if _mantle_target_vertical != Vector3.ZERO:
		return _mantle_target_vertical
	var tangent = ledge_normal.cross(Vector3.UP).normalized()
	return ledge_anchor_point + tangent * hang_lateral_offset + Vector3.UP * mantle_up_offset

func get_mantle_target_top() -> Vector3:
	if _mantle_target_top != Vector3.ZERO:
		return _mantle_target_top
	return get_mantle_target_vertical() + ledge_normal * mantle_forward_offset

func configure_mantle_targets(target_vertical: Vector3, target_top: Vector3) -> void:
	_mantle_target_vertical = target_vertical
	_mantle_target_top = target_top

func _step_swinging(dt: float, _input: Vector2, _pos: Vector3) -> Vector3:
	_swing_time += dt
	var angle = deterministic_sin(_swing_time * swing_frequency) * 0.8 # +/- 45 degrees approx

	var offset_x = deterministic_sin(angle) * swing_radius
	var offset_y = -deterministic_cos(angle) * swing_radius

	# Align swing with some orientation if needed, for now X-Y plane
	anim_progress = (deterministic_sin(_swing_time * swing_frequency) + 1.0) * 0.5
	return swing_anchor_point + Vector3(offset_x, offset_y, 0)

func _step_rope_sliding(dt: float, pos: Vector3) -> Vector3:
	var rope_dir = (rope_end - rope_start).normalized()
	var next_pos = pos + rope_dir * rope_slide_speed * dt

	# Exit if reached end
	if (next_pos - rope_start).length() >= (rope_end - rope_start).length():
		exit()
		return rope_end

	return next_pos

# --- TRANSITIONS ---
func enter_climbing(anchor: Vector3, normal: Vector3, start_pos: Vector3, p_is_1d: bool = true, p_min_y: float = -1.5, p_max_y: float = 1.5):
	current_state = TraversalState.CLIMBING
	is_1d_ladder = p_is_1d
	is_active = true
	is_climbing = true
	is_hanging = false
	is_swinging = false
	is_mantling = false
	ladder_anchor_point = anchor
	ladder_normal = normal
	ladder_min_offset = p_min_y
	ladder_max_offset = p_max_y
	var up_dir = Vector3.UP
	var right_dir = ladder_normal.cross(up_dir).normalized()
	var rel = start_pos - ladder_anchor_point
	var clamped_y = clamp(rel.dot(up_dir), ladder_min_offset, ladder_max_offset)
	var local_x = 0.0 if is_1d_ladder else rel.dot(right_dir)
	_ladder_attach_target = ladder_anchor_point + up_dir * clamped_y + right_dir * local_x
	_ladder_attach_active = start_pos.distance_squared_to(_ladder_attach_target) > 0.0025
	anim_progress = 0.0

func enter_hanging(anchor: Vector3, normal: Vector3, p_half_width: float = 0.85, start_pos: Vector3 = Vector3.ZERO):
	current_state = TraversalState.HANGING
	is_active = true
	is_climbing = false
	is_hanging = true
	is_swinging = false
	is_mantling = false
	ledge_anchor_point = anchor
	ledge_normal = normal
	ledge_half_width = max(0.2, p_half_width)
	var tangent = ledge_normal.cross(Vector3.UP).normalized()
	var rel = start_pos - ledge_anchor_point
	hang_lateral_offset = clamp(rel.dot(tangent), -ledge_half_width, ledge_half_width)
	var hang_origin = ledge_anchor_point + Vector3.DOWN * hang_body_down_offset - ledge_normal * hang_body_back_offset
	_hang_attach_target = hang_origin + tangent * hang_lateral_offset
	configure_mantle_targets(
		ledge_anchor_point + tangent * hang_lateral_offset + Vector3.UP * mantle_up_offset,
		ledge_anchor_point + tangent * hang_lateral_offset + Vector3.UP * mantle_up_offset + ledge_normal * mantle_forward_offset
	)
	_hang_attach_active = start_pos.distance_squared_to(_hang_attach_target) > 0.0025
	_hang_crouch_drop_grace_left = hang_crouch_drop_grace
	_hang_mantle_input_grace_left = hang_mantle_input_grace
	anim_progress = 0.0

func start_mantle():
	current_state = TraversalState.MANTLING
	is_mantling = true
	_mantle_time = 0.0
	anim_progress = 0.0

func enter_swinging(anchor: Vector3, radius: float):
	current_state = TraversalState.SWINGING
	is_active = true
	is_climbing = false
	is_hanging = false
	is_swinging = true
	is_mantling = false
	is_rope_sliding = false
	swing_anchor_point = anchor
	swing_radius = radius
	_swing_time = 0.0
	anim_progress = 0.5

func enter_rope_sliding(start: Vector3, end: Vector3):
	current_state = TraversalState.ROPE_SLIDING
	is_active = true
	is_climbing = false
	is_hanging = false
	is_swinging = false
	is_mantling = false
	is_rope_sliding = true
	rope_start = start
	rope_end = end
	anim_progress = 0.0

func exit():
	current_state = TraversalState.NONE
	is_active = false
	is_climbing = false
	is_hanging = false
	is_swinging = false
	is_mantling = false
	is_rope_sliding = false
	hang_lateral_offset = 0.0
	_ladder_attach_active = false
	_ladder_attach_target = Vector3.ZERO
	_hang_attach_active = false
	_hang_attach_target = Vector3.ZERO
	_mantle_target_vertical = Vector3.ZERO
	_mantle_target_top = Vector3.ZERO
	_hang_mantle_input_grace_left = 0.0

# --- SNAPSHOTS ---
func get_full_snapshot() -> Dictionary:
	return {
		"state": current_state,
		"anim_progress": anim_progress,
		"swing_time": _swing_time,
		"mantle_time": _mantle_time,
		"anchor": [ledge_anchor_point.x, ledge_anchor_point.y, ledge_anchor_point.z],
		"hang_lateral_offset": hang_lateral_offset,
		"hang_attach_active": _hang_attach_active,
		"hang_attach_target": [_hang_attach_target.x, _hang_attach_target.y, _hang_attach_target.z]
	}

func restore_snapshot(data: Dictionary):
	current_state = data.get("state", TraversalState.NONE)
	anim_progress = data.get("anim_progress", 0.0)
	_swing_time = data.get("swing_time", 0.0)
	_mantle_time = data.get("mantle_time", 0.0)
	var a = data.get("anchor", [0, 0, 0])
	ledge_anchor_point = Vector3(a[0], a[1], a[2])
	hang_lateral_offset = data.get("hang_lateral_offset", 0.0)
	_hang_attach_active = data.get("hang_attach_active", false)
	var attach = data.get("hang_attach_target", [0, 0, 0])
	_hang_attach_target = Vector3(attach[0], attach[1], attach[2])

	is_active = current_state != TraversalState.NONE
	is_climbing = current_state == TraversalState.CLIMBING
	is_hanging = current_state == TraversalState.HANGING
	is_swinging = current_state == TraversalState.SWINGING
	is_mantling = current_state == TraversalState.MANTLING
	is_rope_sliding = current_state == TraversalState.ROPE_SLIDING
