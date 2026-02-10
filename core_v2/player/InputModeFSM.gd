# InputModeFSM.gd — Centralized Input Mode State Machine
# Owns input interpretation mode, direction latch state, and cinematic zone detection.
# Decouples input mode from camera transitions.
extends Node

# --- MODE ENUM ---
enum Mode {
	THIRD_PERSON,
	CINEMATIC,
	SIDESCROLL
}

# --- STATE ---
var current_mode: int = Mode.THIRD_PERSON

# Cinematic rig tracking (moved from PlayerControllerV2)
var cinematic_rig: Node = null # Current active cinematic rig
var _prev_cinematic_rig: Node = null # Previous frame's cinematic rig
var active_cinematic_zone = null # The zone that owns the current rig

# Direction Latch System — prevents abrupt direction changes on zone enter/exit
var _direction_latch_active := false
var _latched_dir_fwd := Vector3.FORWARD
var _latched_dir_rt := Vector3.LEFT
var _latched_sidescroll_active := false
var _latched_sidescroll_basis := Basis.IDENTITY
var _latched_cinematic_mode := -1 # CinematicManager.ControlMode or -1
var _latched_input_vec := Vector2.ZERO

# Forward Latch (2.5D specific)
var _forward_latch_active := false
var _forward_latch_sign := 1.0

# Previous-frame tracking for context change detection
var _prev_sidescroll_active := false
var _prev_sidescroll_zone: Node = null
var _prev_camera_basis := Basis.IDENTITY

# Terminal UI state (blocks movement when focused)
var _terminal_ui_active := false

# --- REFERENCES (set by PlayerControllerV2) ---
var _player = null # KinematicBody (PlayerControllerV2)
var _sidescroll_logic = null # SideScrollLogicV2 reference


# =========================================================================
# INITIALIZATION
# =========================================================================

func init(player, sidescroll_logic) -> void:
	_player = player
	_sidescroll_logic = sidescroll_logic


# =========================================================================
# MAIN UPDATE — Called once per physics frame from PlayerControllerV2.step()
# =========================================================================

func update(_dt: float, input, camera_basis: Basis) -> void:
	"""
	Runs zone detection, context change detection, latch activation/release.
	Must be called AFTER sidescroll_logic.step(dt) but BEFORE input interpretation.
	"""
	# --- Forward Latch Release ---
	if input.move_vec.y >= -0.1:
		_forward_latch_active = false

	# --- Cinematic Zone Detection ---
	_detect_cinematic_zones()

	# --- Context Change Detection + Latch Logic ---
	_update_context_and_latch(input, camera_basis)

	# --- Latch Release Check ---
	_check_latch_release(input)


# =========================================================================
# CINEMATIC ZONE DETECTION (extracted from PlayerControllerV2 lines 933-964)
# =========================================================================

func _detect_cinematic_zones() -> void:
	cinematic_rig = null
	active_cinematic_zone = null
	var candidate_zones := []

	var all_zones = _player.get_tree().get_nodes_in_group("CinematicCameraZoneV2")
	for zone in all_zones:
		var zone_node = zone as CinematicCameraZoneV2
		if zone_node and zone_node.is_zone_active:
			var in_zone = zone_node.is_body_in_zone(_player)
			if in_zone and zone_node._rig_node:
				candidate_zones.append(zone_node)

	if candidate_zones.size() > 0:
		active_cinematic_zone = candidate_zones[0]
		cinematic_rig = active_cinematic_zone._rig_node

	# Check if active cinematic zone belongs to a HoloTerminal in UI mode
	_terminal_ui_active = false
	if active_cinematic_zone:
		var terminal = active_cinematic_zone.get_parent()
		if terminal and terminal.get_parent():
			terminal = terminal.get_parent()
		if terminal and terminal.has_method("is_focused"):
			_terminal_ui_active = terminal.is_focused()


# =========================================================================
# CONTEXT CHANGE + LATCH LOGIC (extracted from PlayerControllerV2 lines 966-1137)
# =========================================================================

func _update_context_and_latch(input, camera_basis: Basis) -> void:
	var ss_active = _sidescroll_logic.is_active if is_instance_valid(_sidescroll_logic) else false

	# --- Rig Activation (BEFORE latch detection) ---
	if cinematic_rig != _prev_cinematic_rig:
		if cinematic_rig:
			# Force camera update for smooth transition start
			if ss_active:
				_player._force_snap_to_sidescroll_camera()
			if _player.camera_rig:
				_player.camera_rig.force_update_transform()
			var viewport_cam = _player.get_viewport().get_camera()
			if viewport_cam:
				viewport_cam.force_update_transform()

			var control_mode = active_cinematic_zone.control_mode if active_cinematic_zone and "control_mode" in active_cinematic_zone else CinematicManager.ControlMode.FREE
			CinematicManager.activate_rig_direct(cinematic_rig, control_mode)
		else:
			CinematicManager.deactivate_rig()

	# Fallback to CinematicManager's active rig if none detected via zones
	var active_rig = cinematic_rig if cinematic_rig else CinematicManager.active_rig

	# --- Context Change Detection ---
	var context_changed := false
	if ss_active != _prev_sidescroll_active:
		context_changed = true
	if active_rig != _prev_cinematic_rig:
		context_changed = true

	var entering = (ss_active and not _prev_sidescroll_active) or (active_rig != null and _prev_cinematic_rig == null)
	var exiting = (not ss_active and _prev_sidescroll_active) or (active_rig == null and _prev_cinematic_rig != null)

	# --- Latch Activation ---
	var has_movement_input = input.move_vec.length() > 0.1
	if context_changed and has_movement_input and (not _direction_latch_active or exiting):
		var zone_latch_on_enter := true
		var zone_latch_on_exit := true

		# Query zone for latch overrides
		if ss_active:
			if not _player.active_25d_zones.empty():
				var new_zone = _player.active_25d_zones.back()
				if "latch_on_enter" in new_zone:
					zone_latch_on_enter = new_zone.latch_on_enter
				if "latch_on_exit" in new_zone:
					zone_latch_on_exit = new_zone.latch_on_exit
		elif exiting and _prev_sidescroll_active:
			if _prev_sidescroll_zone:
				if "latch_on_enter" in _prev_sidescroll_zone:
					zone_latch_on_enter = _prev_sidescroll_zone.latch_on_enter
				if "latch_on_exit" in _prev_sidescroll_zone:
					zone_latch_on_exit = _prev_sidescroll_zone.latch_on_exit

		# For cinematic zones, find the zone that owns the rig
		var cinematic_zone = null
		var rig_to_check = active_rig
		if rig_to_check == null and exiting:
			rig_to_check = _prev_cinematic_rig
		if rig_to_check != null:
			for zone in _player.get_tree().get_nodes_in_group("CinematicCameraZoneV2"):
				var zone_rig = zone.get_node_or_null(zone.cinematic_rig_path)
				if zone_rig == rig_to_check:
					cinematic_zone = zone
					break
		if cinematic_zone != null and cinematic_zone is Node:
			if "latch_on_enter" in cinematic_zone:
				zone_latch_on_enter = cinematic_zone.latch_on_enter
			if "latch_on_exit" in cinematic_zone:
				zone_latch_on_exit = cinematic_zone.latch_on_exit

		# Activate latch if zone flags permit
		if (zone_latch_on_enter and entering) or (zone_latch_on_exit and exiting):
			if exiting and _direction_latch_active:
				# Already latched on exit — keep previous context
				pass
			else:
				var active_mode = CinematicManager.get_control_mode() if _prev_cinematic_rig else CinematicManager.ControlMode.FREE
				var fwd := Vector3.ZERO
				var rt := Vector3.ZERO

				if active_mode == CinematicManager.ControlMode.LOCKED_VIEW:
					fwd = - _prev_camera_basis.z
					rt = _prev_camera_basis.x
				else:
					fwd = - _prev_camera_basis.z
					rt = _prev_camera_basis.x

				fwd.y = 0
				rt.y = 0
				_latched_dir_fwd = fwd.normalized()
				_latched_dir_rt = rt.normalized()
				_latched_cinematic_mode = active_mode

			_latched_input_vec = input.move_vec
			_direction_latch_active = true
			_latched_sidescroll_active = _prev_sidescroll_active
			if _latched_sidescroll_active and is_instance_valid(_sidescroll_logic):
				_latched_sidescroll_basis = _sidescroll_logic.get_target_basis()

	# --- Update prev-frame references ---
	_prev_sidescroll_active = ss_active
	if ss_active and not _player.active_25d_zones.empty():
		_prev_sidescroll_zone = _player.active_25d_zones.back()
	elif not ss_active:
		_prev_sidescroll_zone = null

	_prev_cinematic_rig = cinematic_rig
	_prev_camera_basis = camera_basis

	# --- Update current mode ---
	if active_rig:
		current_mode = Mode.CINEMATIC
	elif ss_active:
		current_mode = Mode.SIDESCROLL
	else:
		current_mode = Mode.THIRD_PERSON


# =========================================================================
# LATCH RELEASE (extracted from PlayerControllerV2 lines 1108-1137)
# =========================================================================

func _check_latch_release(input) -> void:
	if not _direction_latch_active:
		return

	var should_release := false

	# Full release: player stopped input
	if input.move_vec.length() < 0.1:
		should_release = true
	else:
		# Direction change: input deviates > ~45° from latched direction
		var latched_dir = _latched_input_vec.normalized()
		var current_dir = input.move_vec.normalized()
		var dot = latched_dir.dot(current_dir)
		if dot < 0.7:
			should_release = true

	if should_release:
		_direction_latch_active = false
		_latched_dir_fwd = Vector3.FORWARD
		_latched_dir_rt = Vector3.LEFT
		_latched_sidescroll_active = false
		_latched_sidescroll_basis = Basis.IDENTITY
		_latched_cinematic_mode = -1
		_latched_input_vec = Vector2.ZERO


# =========================================================================
# INPUT INTERPRETATION (extracted from PlayerControllerV2 lines 1170-1264)
# =========================================================================

func interpret_input(move_vec: Vector2, camera_basis: Basis, input_move_vec: Vector2) -> Dictionary:
	"""
	Returns { basis: Basis, move_vec: Vector2 } for PlayerMovementV2.process_movement().
	Replaces the if/elif cascade in step().
	"""
	var active_rig = cinematic_rig if cinematic_rig else CinematicManager.active_rig
	var ss_active = _sidescroll_logic.is_active if is_instance_valid(_sidescroll_logic) else false
	var alpha = _sidescroll_logic.transition_alpha if is_instance_valid(_sidescroll_logic) else 0.0
	var in_transition = alpha > 0.0 and alpha < 1.0

	var result_basis = camera_basis
	var result_move = move_vec

	if active_rig or _direction_latch_active:
		var mode = CinematicManager.get_control_mode()

		var ref_cam = null
		if active_rig and active_rig.has_method("get_camera"):
			ref_cam = active_rig.get_camera()

		if _direction_latch_active:
			# LATCHED: Use stored forward/right vectors
			result_basis = Basis(_latched_dir_rt, Vector3.UP, -_latched_dir_fwd)
			result_move = input_move_vec
		else:
			# UNLATCHED: Use target camera basis
			var world_dir = _player._get_move_direction(input_move_vec, mode, ref_cam)
			if world_dir.length() > 0.01:
				var b_z = - world_dir.normalized()
				result_basis = Basis(Vector3.UP.cross(b_z), Vector3.UP, b_z)
				result_move = Vector2(0, -world_dir.length())

	elif _forward_latch_active and not _sidescroll_logic.allow_depth and not active_rig:
		# FORWARD LATCH: Force controls to follow strict 2.5D path
		result_basis = _sidescroll_logic.get_target_basis()
		var target_right = result_basis.x
		var world_dir = Vector3.ZERO

		if _sidescroll_logic.lock_axis == 2:
			world_dir.x = _forward_latch_sign
		elif _sidescroll_logic.lock_axis == 1:
			world_dir.z = _forward_latch_sign

		var input_x = sign(world_dir.dot(target_right))
		if abs(input_x) == 0:
			input_x = 1.0

		result_move = Vector2(input_x, 0.0)

	elif ss_active and not in_transition and not active_rig:
		# STRICT 2.5D: Use target basis + constraints
		result_basis = _sidescroll_logic.get_target_basis()
		result_move = _sidescroll_logic.get_constrained_input(result_move)

		# Invert Horizontal for Lock X mode
		if _sidescroll_logic.lock_axis == 1:
			result_move.x = - result_move.x

		# Invert Depth (Forward/Backward) in SideScroll mode
		result_move.y = - result_move.y

	return {"basis": result_basis, "move_vec": result_move}


# =========================================================================
# FORWARD LATCH CHECK (extracted from PlayerControllerV2 lines 1584-1608)
# =========================================================================

func check_forward_latch(axis: int) -> void:
	var projected_vel = 0.0
	if axis == 2:
		projected_vel = _player.velocity.x
	elif axis == 1:
		projected_vel = _player.velocity.z

	var forward_pressed = Input.is_action_pressed("move_forward")

	if forward_pressed:
		if abs(projected_vel) > 0.1:
			_forward_latch_active = true
			_forward_latch_sign = sign(projected_vel)
		else:
			var facing = - _player.global_transform.basis.z
			var free_axis_facing = facing.x if axis == 2 else facing.z
			if abs(free_axis_facing) > 0.1:
				_forward_latch_active = true
				_forward_latch_sign = sign(free_axis_facing)
	else:
		_forward_latch_active = false


# =========================================================================
# SNAPSHOT / RESTORE (for deterministic replays)
# =========================================================================

func get_full_snapshot() -> Dictionary:
	var snapshot = {
		"current_mode": current_mode,
		"direction_latch_active": _direction_latch_active,
		"latched_dir_fwd": [_latched_dir_fwd.x, _latched_dir_fwd.y, _latched_dir_fwd.z],
		"latched_dir_rt": [_latched_dir_rt.x, _latched_dir_rt.y, _latched_dir_rt.z],
		"latched_sidescroll_active": _latched_sidescroll_active,
		"latched_sidescroll_basis": {
			"x": [_latched_sidescroll_basis.x.x, _latched_sidescroll_basis.x.y, _latched_sidescroll_basis.x.z],
			"y": [_latched_sidescroll_basis.y.x, _latched_sidescroll_basis.y.y, _latched_sidescroll_basis.y.z],
			"z": [_latched_sidescroll_basis.z.x, _latched_sidescroll_basis.z.y, _latched_sidescroll_basis.z.z]
		},
		"latched_cinematic_mode": _latched_cinematic_mode,
		"latched_input_vec": [_latched_input_vec.x, _latched_input_vec.y],
		"prev_sidescroll_active": _prev_sidescroll_active,
		"prev_camera_basis": {
			"x": [_prev_camera_basis.x.x, _prev_camera_basis.x.y, _prev_camera_basis.x.z],
			"y": [_prev_camera_basis.y.x, _prev_camera_basis.y.y, _prev_camera_basis.y.z],
			"z": [_prev_camera_basis.z.x, _prev_camera_basis.z.y, _prev_camera_basis.z.z]
		},
		"fwd_latch_active": _forward_latch_active,
		"fwd_latch_sign": _forward_latch_sign,
	}

	if _prev_cinematic_rig and is_instance_valid(_prev_cinematic_rig):
		snapshot["prev_cinematic_rig_path"] = _prev_cinematic_rig.get_path()
	else:
		snapshot["prev_cinematic_rig_path"] = ""

	if cinematic_rig and is_instance_valid(cinematic_rig):
		snapshot["cinematic_rig_path"] = cinematic_rig.get_path()
	else:
		snapshot["cinematic_rig_path"] = ""

	return snapshot


func restore_snapshot(data: Dictionary) -> void:
	current_mode = data.get("current_mode", Mode.THIRD_PERSON)

	_direction_latch_active = data.get("direction_latch_active", false)
	_prev_sidescroll_active = data.get("prev_sidescroll_active", false)
	_latched_sidescroll_active = data.get("latched_sidescroll_active", false)
	_latched_cinematic_mode = data.get("latched_cinematic_mode", -1)

	var ldf = data.get("latched_dir_fwd", [0, 0, 1])
	_latched_dir_fwd = Vector3(ldf[0], ldf[1], ldf[2])
	var ldr = data.get("latched_dir_rt", [1, 0, 0])
	_latched_dir_rt = Vector3(ldr[0], ldr[1], ldr[2])

	if data.has("latched_sidescroll_basis"):
		var lsb = data["latched_sidescroll_basis"]
		_latched_sidescroll_basis = Basis(
			Vector3(lsb["x"][0], lsb["x"][1], lsb["x"][2]),
			Vector3(lsb["y"][0], lsb["y"][1], lsb["y"][2]),
			Vector3(lsb["z"][0], lsb["z"][1], lsb["z"][2])
		)
	else:
		_latched_sidescroll_basis = Basis.IDENTITY

	if data.has("latched_input_vec"):
		var liv = data["latched_input_vec"]
		_latched_input_vec = Vector2(liv[0], liv[1])
	else:
		_latched_input_vec = Vector2.ZERO

	if data.has("prev_camera_basis"):
		var pcb = data["prev_camera_basis"]
		_prev_camera_basis = Basis(
			Vector3(pcb["x"][0], pcb["x"][1], pcb["x"][2]),
			Vector3(pcb["y"][0], pcb["y"][1], pcb["y"][2]),
			Vector3(pcb["z"][0], pcb["z"][1], pcb["z"][2])
		)
	else:
		_prev_camera_basis = Basis.IDENTITY

	_forward_latch_active = data.get("fwd_latch_active", false)
	_forward_latch_sign = data.get("fwd_latch_sign", 1.0)

	var prev_rig_path = data.get("prev_cinematic_rig_path", "")
	if prev_rig_path != "" and _player.has_node(prev_rig_path):
		_prev_cinematic_rig = _player.get_node(prev_rig_path)
	else:
		_prev_cinematic_rig = null

	var rig_path = data.get("cinematic_rig_path", "")
	if rig_path != "" and _player.has_node(rig_path):
		cinematic_rig = _player.get_node(rig_path)
	else:
		cinematic_rig = null


# =========================================================================
# FULL RESET (for deterministic test initialization)
# =========================================================================

func full_reset() -> void:
	current_mode = Mode.THIRD_PERSON
	cinematic_rig = null
	_prev_cinematic_rig = null
	active_cinematic_zone = null

	_direction_latch_active = false
	_latched_dir_fwd = Vector3.FORWARD
	_latched_dir_rt = Vector3.LEFT
	_latched_sidescroll_active = false
	_latched_sidescroll_basis = Basis.IDENTITY
	_latched_cinematic_mode = -1
	_latched_input_vec = Vector2.ZERO

	_forward_latch_active = false
	_forward_latch_sign = 1.0

	_prev_sidescroll_active = false
	_prev_sidescroll_zone = null
	_prev_camera_basis = Basis.IDENTITY
	_terminal_ui_active = false
