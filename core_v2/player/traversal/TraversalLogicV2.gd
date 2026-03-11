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
var ledge_anchor_point := Vector3.ZERO
var ledge_normal := Vector3.BACK
var ladder_anchor_point := Vector3.ZERO
var ladder_normal := Vector3.BACK
var swing_anchor_point := Vector3.ZERO
var swing_radius := 3.0
var rope_start := Vector3.ZERO
var rope_end := Vector3.ZERO

# Visual Interpolation
var anim_progress := 0.0 # 0.0 to 1.0 for visuals

# Internal Counters
var _swing_time := 0.0
var _mantle_time := 0.0

# --- TUNING ---
export(float) var climb_speed := 2.5
export(float) var shimmy_speed := 2.0
export(float) var mantle_duration := 0.6
export(float) var swing_frequency := 1.5
export(float) var rope_slide_speed := 8.0

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

# --- CORE STEP ---
func step(dt: float, input: Vector2, current_pos: Vector3) -> Vector3:
	if current_state == TraversalState.NONE:
		return current_pos

	match current_state:
		TraversalState.CLIMBING:
			return _step_climbing(dt, input, current_pos)
		TraversalState.HANGING:
			return _step_hanging(dt, input, current_pos)
		TraversalState.MANTLING:
			return _step_mantling(dt, current_pos)
		TraversalState.SWINGING:
			return _step_swinging(dt, input, current_pos)
		TraversalState.ROPE_SLIDING:
			return _step_rope_sliding(dt, current_pos)

	return current_pos

func _step_climbing(dt: float, input: Vector2, pos: Vector3) -> Vector3:
	# 2D Surface (Up/Down/Left/Right)
	# input.y: -1 is Forward (Up on ladder), 1 is Backward (Down on ladder)
	# input.x: -1 is Left, 1 is Right

	var up_dir = Vector3.UP
	var right_dir = ladder_normal.cross(up_dir).normalized()

	var input_x = 0.0 if is_1d_ladder else input.x
	var move_vec = (up_dir * -input.y + right_dir * input_x) * climb_speed * dt
	var next_pos = pos + move_vec

	# Strict Plane Snapping (Mandate: mathematically reconstructible)
	var to_pos = next_pos - ladder_anchor_point
	var dist_from_plane = to_pos.dot(ladder_normal)
	next_pos -= ladder_normal * dist_from_plane

	anim_progress = fposmod(anim_progress + move_vec.length() * 0.5, 1.0)
	return next_pos

func _step_hanging(dt: float, input: Vector2, pos: Vector3) -> Vector3:
	# Ledge Traversal: Constrained to ledge tangent
	var tangent = ledge_normal.cross(Vector3.UP).normalized()
	var move_h = input.x * shimmy_speed * dt

	var next_pos = pos + tangent * move_h

	# Strict Tangent Snapping
	var to_pos = next_pos - ledge_anchor_point
	var dist_from_ledge = to_pos.dot(ledge_normal)
	next_pos -= ledge_normal * dist_from_ledge

	# Update anim_progress for shimmy visuals
	anim_progress = fposmod(anim_progress + abs(input.x) * dt, 1.0)

	# Transition to Mantle if Up is pressed
	if input.y < -0.5:
		start_mantle()

	return next_pos

func _step_mantling(dt: float, pos: Vector3) -> Vector3:
	_mantle_time += dt
	anim_progress = clamp(_mantle_time / mantle_duration, 0.0, 1.0)

	# Deterministic Mantle Path: simple L-shape with constant steps
	# target_top is approx the standing position on the platform
	var target_top = ledge_anchor_point + Vector3.UP * 1.8 - ledge_normal * 0.8

	var next_pos = pos
	var phase_duration = mantle_duration * 0.5
	var step_speed = 1.8 / phase_duration # meters per second

	if anim_progress < 0.5:
		# Vertical phase
		next_pos = pos.move_toward(ledge_anchor_point + Vector3.UP * 1.8, step_speed * dt)
	else:
		# Forward phase
		var forward_step_speed = 0.8 / phase_duration
		next_pos = pos.move_toward(target_top, forward_step_speed * dt)

	return next_pos

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
func enter_climbing(anchor: Vector3, normal: Vector3, start_pos: Vector3, p_is_1d: bool = true):
	current_state = TraversalState.CLIMBING
	is_1d_ladder = p_is_1d
	is_active = true
	is_climbing = true
	is_hanging = false
	is_swinging = false
	is_mantling = false
	ladder_anchor_point = anchor
	ladder_normal = normal
	anim_progress = 0.0

func enter_hanging(anchor: Vector3, normal: Vector3):
	current_state = TraversalState.HANGING
	is_active = true
	is_climbing = false
	is_hanging = true
	is_swinging = false
	is_mantling = false
	ledge_anchor_point = anchor
	ledge_normal = normal
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

# --- SNAPSHOTS ---
func get_full_snapshot() -> Dictionary:
	return {
		"state": current_state,
		"anim_progress": anim_progress,
		"swing_time": _swing_time,
		"mantle_time": _mantle_time,
		"anchor": [ledge_anchor_point.x, ledge_anchor_point.y, ledge_anchor_point.z]
	}

func restore_snapshot(data: Dictionary):
	current_state = data.get("state", TraversalState.NONE)
	anim_progress = data.get("anim_progress", 0.0)
	_swing_time = data.get("swing_time", 0.0)
	_mantle_time = data.get("mantle_time", 0.0)
	var a = data.get("anchor", [0, 0, 0])
	ledge_anchor_point = Vector3(a[0], a[1], a[2])

	is_active = current_state != TraversalState.NONE
	is_climbing = current_state == TraversalState.CLIMBING
	is_hanging = current_state == TraversalState.HANGING
	is_swinging = current_state == TraversalState.SWINGING
	is_mantling = current_state == TraversalState.MANTLING
	is_rope_sliding = current_state == TraversalState.ROPE_SLIDING
