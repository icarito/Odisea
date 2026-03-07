extends Node

# CinematicManager.gd - Autoload for managing cinematic rigs and transitions
# Simplified to use CameraTransition plugin.

enum ControlMode {
	FREE,
	SIDESCROLL, # Legacy, keeping for compatibility but might be unused
	LOCKED_VIEW,
	FIXED_AXIS
}

# --- New FSM Architecture (Phase 1) ---
enum CameraModeState {
	FREE_ACTIVE,
	TRANSITION_TO_CINEMATIC,
	CINEMATIC_ACTIVE,
	TRANSITION_TO_VCAM,
	VCAM_ACTIVE,
	VCAM_BLENDING,
	TRANSITION_VCAM_TO_FREE,
	TRANSITION_TO_FREE,
	RECOVERY
}

enum InputState {
	INPUT_DIRECT,
	INPUT_LATCHED,
	INPUT_BLOCKED
}

class CameraRequest:
	var id: int
	var mode: int # ControlMode
	var payload: Dictionary
	var source: String
	var priority: int

	func _init(_id: int, _mode: int, _payload: Dictionary, _source: String, _priority: int):
		id = _id
		mode = _mode
		payload = _payload
		source = _source
		priority = _priority

# FSM State
var _current_state: int = CameraModeState.FREE_ACTIVE
var _input_state: int = InputState.INPUT_DIRECT
var _active_requests: Dictionary = {} # id -> CameraRequest
var _active_payload: Dictionary = {}
var _request_counter: int = 0
var _latch_timer: float = 0.0
const LATCH_TIMEOUT: float = 0.25
const LATCH_DEADZONE: float = 0.1

# Legacy / Compatibility Variables
var active_rig = null
var current_control_mode = ControlMode.FREE
var latched_camera_basis = Basis.IDENTITY
var latched_control_mode = ControlMode.FREE
var latch_active := false # Use _input_state == INPUT_LATCHED instead
var _transition_active := false
var _transition_start_time := 0.0
var _transition_duration := 0.0
var _transition_elapsed := 0.0
var _transition_purpose := "" # "to_cinematic" | "to_free"
var _transition_from_cam: Camera = null
var _transition_to_cam: Camera = null
var _transition_start_transform: Transform
var _transition_start_fov: float
var transition_debug_enabled := false
var _transition_debug_events: Array = []
const TRANSITION_DEBUG_MAX_EVENTS := 256

var _shake_active := false
var _shake_duration := 0.0
var _shake_elapsed := 0.0
var _shake_amplitude := 0.08
var _shake_frequency := 28.0
var _shake_roll_degrees := 1.0
var _shake_seed := 0.0
var _shake_cam: Camera = null
var _shake_base_h_offset := 0.0
var _shake_base_v_offset := 0.0
var _shake_base_roll_degrees := 0.0

# --- VCamera System ---
var _vcam_brain: Node = null
var _vcam_active_camera: Node = null
var _vcam_blend_duration: float = 1.0
var _vcam_blend_elapsed: float = 0.0
var _vcam_source: String = "vcamera"
const MODE_TRANSITION_SPEED_MULT := 1.0
const MIN_TRANSITION_DURATION := 0.08

signal cinematic_started(rig_id)
signal cinematic_stopped
signal control_mode_changed(mode)

func _scaled_mode_transition_duration(duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return max(MIN_TRANSITION_DURATION, duration / MODE_TRANSITION_SPEED_MULT)

func _ready():
	var env_debug = OS.get_environment("ODISEA_CAMERA_DEBUG").to_lower()
	if env_debug == "":
		transition_debug_enabled = false
	else:
		transition_debug_enabled = env_debug in ["1", "true", "yes", "on"]

func set_transition_debug(enabled: bool) -> void:
	transition_debug_enabled = enabled

func clear_transition_debug_events() -> void:
	_transition_debug_events.clear()

func get_transition_debug_events() -> Array:
	return _transition_debug_events.duplicate(true)

func _camera_debug_name(cam: Camera) -> String:
	if not cam or not is_instance_valid(cam):
		return "<null>"
	var p = str(cam.get_path()) if cam.is_inside_tree() else "<detached>"
	return "%s@%s" % [cam.name, p]

func _log_transition(event: String, data: Dictionary = {}) -> void:
	var entry = {
		"t_ms": OS.get_ticks_msec(),
		"event": event,
		"data": data
	}
	_transition_debug_events.append(entry)
	if _transition_debug_events.size() > TRANSITION_DEBUG_MAX_EVENTS:
		_transition_debug_events.pop_front()
	if transition_debug_enabled:
		print("[CinematicManager][TRACE] ", entry)

# --- Request API ---

func request_camera_mode(mode: int, payload := {}, source := "system", priority := 0) -> int:
	_request_counter += 1
	var id = _request_counter
	var req = CameraRequest.new(id, mode, payload, source, priority)
	_active_requests[id] = req
	_log_transition("request_add", {
		"id": id,
		"source": source,
		"priority": priority,
		"mode": mode,
		"rig": str(payload.get("rig", null))
	})
	# print("[CinematicManager] Request %d: %s (Pri: %d) Source: %s" % [id, ControlMode.keys()[mode], priority, source])
	return id

func release_camera_request(request_id: int) -> void:
	if _active_requests.has(request_id):
		_log_transition("request_release", {
			"id": request_id
		})
		_active_requests.erase(request_id)
		# print("[CinematicManager] Released request %d" % request_id)

func activate_rig(rig_id: String, control_mode: int = ControlMode.FREE):
	var rigs = get_tree().get_nodes_in_group("cinematic_rigs")
	var target_rig = null
	for rig in rigs:
		if rig.name == rig_id:
			target_rig = rig
			break
		if rig.get("rig_id") == rig_id:
			target_rig = rig
			break

	if not target_rig:
		printerr("[CinematicManager] Rig not found: ", rig_id)
		return

	activate_rig_direct(target_rig, control_mode)

func activate_rig_direct(target_rig: Spatial, control_mode: int = ControlMode.FREE, old_camera: Camera = null):
	"""Activate a rig directly by reference (preferred over string ID)."""
	if not target_rig:
		printerr("[CinematicManager] activate_rig_direct called with null rig")
		return

	# Compatibility Wrapper: Create a high-priority request
	# We use a distinct source "legacy_direct" so we can find it later in deactivate_rig
	
	# Clean up any previous legacy request to avoid stacking
	var to_remove = []
	for id in _active_requests:
		if _active_requests[id].source == "legacy_direct":
			to_remove.append(id)
	for id in to_remove:
		release_camera_request(id)

	var trans_time = target_rig.transition_time if "transition_time" in target_rig else 0.0
	var payload = {
		"rig": target_rig,
		"transition_time": trans_time,
		"old_camera": old_camera # Optional hint
	}
	
	request_camera_mode(control_mode, payload, "legacy_direct", 10)

func deactivate_rig():
	# Compatibility Wrapper: Release the legacy request
	var to_remove = []
	for id in _active_requests:
		if _active_requests[id].source == "legacy_direct":
			to_remove.append(id)
	
	for id in to_remove:
		release_camera_request(id)

# --- VCamera API ---

func find_vcamera(vcam_name: String) -> Node:
	var vcams = get_tree().get_nodes_in_group("vcamera")
	for vcam in vcams:
		if vcam.name == vcam_name:
			return vcam
	return null

func get_active_vcamera() -> Node:
	return _vcam_active_camera

func activate_vcamera(vcam: Node, duration: float = 1.0, ease_type: float = -2.0) -> int:
	if not vcam:
		printerr("[CinematicManager] activate_vcamera called with null VCamera")
		return -1
	
	_find_or_create_vcam_brain()
	
	var to_remove = []
	for id in _active_requests:
		if _active_requests[id].source == _vcam_source:
			to_remove.append(id)
	for id in to_remove:
		release_camera_request(id)
	
	var payload = {
		"vcamera": vcam,
		"duration": duration,
		"ease": ease_type,
		"transition_time": duration
	}
	
	_log_transition("vcamera_activate", {
		"vcam": vcam.name,
		"duration": duration
	})
	
	return request_camera_mode(ControlMode.FREE, payload, _vcam_source, 15)

func blend_to_vcamera(vcam: Node, duration: float = 1.0) -> void:
	if not vcam:
		printerr("[CinematicManager] blend_to_vcamera called with null VCamera")
		return
	
	if _current_state != CameraModeState.VCAM_ACTIVE and _current_state != CameraModeState.VCAM_BLENDING:
		printerr("[CinematicManager] blend_to_vcamera: Not in VCAM state (current: %s)" % CameraModeState.keys()[_current_state])
		return
	
	var scaled_duration := _scaled_mode_transition_duration(duration)
	_vcam_blend_duration = scaled_duration
	_vcam_blend_elapsed = 0.0
	
	if _vcam_active_camera and is_instance_valid(_vcam_active_camera):
		_vcam_active_camera.priority = 0
	
	vcam.enabled = true
	vcam.priority = 100
	vcam.transition_time = scaled_duration
	
	_current_state = CameraModeState.VCAM_BLENDING
	_vcam_active_camera = vcam
	if scaled_duration <= 0.0:
		_current_state = CameraModeState.VCAM_ACTIVE
		_vcam_blend_elapsed = _vcam_blend_duration
		_snap_vcamera_brain_to_active()
	
	_log_transition("vcamera_blend", {
		"to": vcam.name,
		"duration": scaled_duration,
		"duration_requested": duration
	})

	# Keep the active VCamera request in sync so FSM target switches to the new VCamera.
	var updated_request := false
	for id in _active_requests:
		var req = _active_requests[id]
		if req and req.source == _vcam_source:
			req.payload["vcamera"] = vcam
			req.payload["transition_time"] = duration
			req.payload["duration"] = duration
			updated_request = true
			break
	if not updated_request:
		var payload = {
			"vcamera": vcam,
			"duration": duration,
			"ease": - 2.0,
			"transition_time": duration
		}
		request_camera_mode(ControlMode.FREE, payload, _vcam_source, 15)

func deactivate_vcamera(duration: float = 1.0) -> void:
	var scaled_duration := _scaled_mode_transition_duration(duration)
	var hard_cut := duration <= 0.0
	var from_cam: Camera = null
	if _vcam_brain and is_instance_valid(_vcam_brain) and _vcam_brain is Camera:
		from_cam = _vcam_brain as Camera

	var to_remove = []
	for id in _active_requests:
		if _active_requests[id].source == _vcam_source:
			to_remove.append(id)
	for id in to_remove:
		release_camera_request(id)
	
	if _vcam_active_camera and is_instance_valid(_vcam_active_camera):
		_vcam_active_camera.enabled = false
		_vcam_active_camera.priority = 0
	_vcam_active_camera = null

	_current_state = CameraModeState.TRANSITION_VCAM_TO_FREE
	_log_transition("vcamera_deactivate", {
		"duration": scaled_duration,
		"duration_requested": duration
	})

	# Respect any higher-level cinematic request still active (e.g. camera zone rig).
	var resume_req := _evaluate_requests()
	if resume_req and resume_req.payload.has("rig"):
		var resume_rig = resume_req.payload.get("rig", null)
		if is_instance_valid(resume_rig):
			var resume_mode := int(resume_req.mode)
			var resume_payload := resume_req.payload
			var resume_transition := 0.0 if hard_cut else float(resume_payload.get("transition_time", duration))
			if not hard_cut and resume_transition <= 0.0 and "transition_time" in resume_rig:
				resume_transition = float(resume_rig.transition_time)
			resume_transition = _scaled_mode_transition_duration(resume_transition)

			active_rig = resume_rig
			current_control_mode = resume_mode
			_active_payload = resume_payload

			if active_rig.has_method("activate"):
				active_rig.activate(false)

			var rig_cam: Camera = null
			if active_rig.has_method("get_camera"):
				rig_cam = active_rig.get_camera()

			if _vcam_brain and is_instance_valid(_vcam_brain):
				_vcam_brain.current = false

			if from_cam and is_instance_valid(from_cam) and rig_cam and is_instance_valid(rig_cam) and resume_transition > 0.0 and from_cam != rig_cam:
				_start_dynamic_transition(from_cam, rig_cam, resume_transition, "to_cinematic")
			elif rig_cam and is_instance_valid(rig_cam):
				rig_cam.current = true

			_current_state = CameraModeState.CINEMATIC_ACTIVE
			emit_signal("control_mode_changed", resume_mode)
			return

	if _vcam_brain and is_instance_valid(_vcam_brain):
		_vcam_brain.current = false

	var player_cam = _find_player_camera()
	if player_cam:
		if from_cam and is_instance_valid(from_cam):
			_align_player_rig_to_camera(from_cam, player_cam)
			_start_dynamic_transition(from_cam, player_cam, scaled_duration, "to_free")
		else:
			player_cam.current = true
	
	_current_state = CameraModeState.FREE_ACTIVE
	emit_signal("cinematic_stopped")
	emit_signal("control_mode_changed", ControlMode.FREE)

func _find_or_create_vcam_brain() -> Node:
	if _vcam_brain and is_instance_valid(_vcam_brain):
		return _vcam_brain
	
	var brains = get_tree().get_nodes_in_group("vcamera_brain")
	if brains.size() > 0:
		_vcam_brain = brains[0]
		return _vcam_brain
	
	var existing = get_tree().root.find_node("VCameraBrain", true, false)
	if existing:
		_vcam_brain = existing
		return _vcam_brain
	
	printerr("[CinematicManager] No VCameraBrain found in scene. Add one to use VCamera system.")
	return null

func _find_player_camera() -> Camera:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		# Primary PlayerControllerV2 camera path.
		if p.has_node("CameraRig/Yaw/Pitch/SpringArm/Camera"):
			return p.get_node("CameraRig/Yaw/Pitch/SpringArm/Camera") as Camera
		# Legacy path fallback.
		if p.has_node("CameraRig/SpringArm/Camera"):
			return p.get_node("CameraRig/SpringArm/Camera") as Camera
		var rig = p.get_node_or_null("CameraRig")
		if rig:
			var rig_cam = _search_camera(rig)
			if rig_cam:
				return rig_cam
		var cam = _search_camera(p)
		if cam: return cam
	return null

func _search_camera(node: Node) -> Camera:
	if node is Camera:
		return node as Camera
	for i in range(node.get_child_count()):
		var cam = _search_camera(node.get_child(i))
		if cam:
			return cam
	return null

func get_active_camera() -> Camera:
	var cam_transition = get_node_or_null("/root/CameraTransition")
	if _transition_active and cam_transition and is_instance_valid(cam_transition.camera3D):
		return cam_transition.camera3D

	if _vcam_brain and is_instance_valid(_vcam_brain) and _vcam_brain is Camera:
		if _current_state in [CameraModeState.VCAM_ACTIVE, CameraModeState.VCAM_BLENDING,
			CameraModeState.TRANSITION_TO_VCAM, CameraModeState.TRANSITION_VCAM_TO_FREE]:
			return _vcam_brain as Camera

	if active_rig and is_instance_valid(active_rig):
		if active_rig.has_method("get_camera"):
			var rig_cam = active_rig.get_camera()
			if rig_cam and is_instance_valid(rig_cam):
				return rig_cam
	else:
		active_rig = null
	return get_viewport().get_camera() if get_viewport() else null

func get_control_mode() -> int:
	return current_control_mode

func is_active() -> bool:
	return active_rig != null or not _active_requests.empty() or _transition_active or _shake_active or _vcam_active_camera != null

# Compatibility for PlayerController or other systems calling step/force_finish
func force_finish_transition():
	var state_before := _current_state
	var dynamic_was_active := _transition_active
	var vcam_was_blending := _current_state in [
		CameraModeState.TRANSITION_TO_VCAM,
		CameraModeState.VCAM_BLENDING
	]

	if _transition_active:
		_transition_elapsed = _transition_duration
		var cam_transition = get_node_or_null("/root/CameraTransition")
		if is_instance_valid(_transition_to_cam) and cam_transition and is_instance_valid(cam_transition.camera3D):
			cam_transition.camera3D.global_transform = _transition_to_cam.global_transform
			cam_transition.camera3D.fov = _transition_to_cam.fov
		_finish_dynamic_transition()

	if vcam_was_blending and _vcam_active_camera and is_instance_valid(_vcam_active_camera):
		_vcam_blend_elapsed = _vcam_blend_duration
		_current_state = CameraModeState.VCAM_ACTIVE
		_vcam_active_camera.enabled = true
		_vcam_active_camera.priority = max(100, int(_vcam_active_camera.priority))
		_snap_vcamera_brain_to_active()

	_cancel_plugin_transition()
	_log_transition("force_finish", {
		"state_before": state_before,
		"state_after": _current_state,
		"dynamic_was_active": dynamic_was_active,
		"vcam_was_blending": vcam_was_blending
	})

func _cancel_plugin_transition() -> void:
	var cam_transition = get_node_or_null("/root/CameraTransition")
	if cam_transition and cam_transition.has_method("cancel_transition"):
		_log_transition("plugin_cancel", {})
		cam_transition.cancel_transition()

func _cancel_dynamic_transition(reason: String = "") -> void:
	if _transition_active:
		_log_transition("dynamic_cancel", {
			"reason": reason,
			"purpose": _transition_purpose,
			"from": _camera_debug_name(_transition_from_cam),
			"to": _camera_debug_name(_transition_to_cam)
		})
	_transition_active = false
	_transition_elapsed = 0.0
	_transition_purpose = ""
	_transition_from_cam = null
	_transition_to_cam = null

func _start_dynamic_transition(from: Camera, to: Camera, duration: float, purpose: String = "to_free"):
	_cancel_dynamic_transition("restart_dynamic")
	_cancel_plugin_transition()
	_log_transition("dynamic_start", {
		"from": _camera_debug_name(from),
		"to": _camera_debug_name(to),
		"duration": duration,
		"purpose": purpose
	})
	_transition_active = true
	_transition_start_time = OS.get_ticks_msec() / 1000.0
	_transition_duration = duration
	_transition_elapsed = 0.0
	_transition_purpose = purpose
	_transition_from_cam = from
	_transition_to_cam = to
	_transition_start_transform = from.global_transform
	_transition_start_fov = from.fov
	
	# Ensure the 'to' camera is NOT current yet, but we need a camera to render
	# We can use the 'from' camera or a temporary one. 
	# Actually, CameraTransition uses a dedicated internal camera. 
	# Here we will manipulate the 'to' camera but keep it 'current' from the start?
	# No, if we make 'to' current, it will jump to its position unless we override its transform.
	# Better approach: Use CameraTransition's camera3D but control it ourselves?
	# Or clearer: We hijack the 'from' camera (if possible) or just use the Viewport's current.
	
	# Let's use CameraTransition's singleton camera for the blend
	var cam_transition = get_node_or_null("/root/CameraTransition")
	if cam_transition and cam_transition.camera3D:
		cam_transition.camera3D.current = true
		cam_transition.camera3D.global_transform = _start_dynamic_transform()
		cam_transition.camera3D.fov = _transition_start_fov

	# Duration zero is used by OYS fast-forward and should cut immediately.
	if _transition_duration <= 0.0:
		if cam_transition and cam_transition.camera3D and is_instance_valid(_transition_to_cam):
			cam_transition.camera3D.global_transform = _transition_to_cam.global_transform
			cam_transition.camera3D.fov = _transition_to_cam.fov
		_finish_dynamic_transition()

func _start_dynamic_transform() -> Transform:
	return _transition_start_transform

func _process(delta: float):
	pass

func _update_dynamic_transition(dt: float) -> void:
	if not _transition_active:
		return

	_transition_elapsed += max(0.0, dt)
	if _transition_duration <= 0.0 or _transition_elapsed >= _transition_duration:
		# Snap transition camera to the latest target pose before handoff to avoid
		# a final-frame mismatch when the destination camera is moving with the player.
		var cam_transition = get_node_or_null("/root/CameraTransition")
		if is_instance_valid(_transition_to_cam) and cam_transition and cam_transition.camera3D:
			cam_transition.camera3D.global_transform = _transition_to_cam.global_transform
			cam_transition.camera3D.fov = _transition_to_cam.fov
		_finish_dynamic_transition()
		return

	var t = _transition_elapsed / _transition_duration
	# Ease InOut Cubic
	t = -0.5 * (cos(PI * t) - 1)

	var cam_transition = get_node_or_null("/root/CameraTransition")
	if is_instance_valid(_transition_to_cam) and cam_transition and cam_transition.camera3D:
		# Interpolate from Fixed Start to Moving Target
		var target_tx = _transition_to_cam.global_transform
		var target_fov = _transition_to_cam.fov
		var new_tx = _transition_start_transform.interpolate_with(target_tx, t)
		var new_fov = lerp(_transition_start_fov, target_fov, t)
		cam_transition.camera3D.global_transform = new_tx
		cam_transition.camera3D.fov = new_fov

func _finish_dynamic_transition():
	var target_cam: Camera = _transition_to_cam
	var cam_transition = get_node_or_null("/root/CameraTransition")
	var blend_cam: Camera = cam_transition.camera3D if cam_transition and is_instance_valid(cam_transition.camera3D) else null
	var purpose := _transition_purpose

	_transition_active = false
	_transition_purpose = ""
	_transition_from_cam = null
	_transition_to_cam = null

	if is_instance_valid(target_cam):
		var pos_err := 0.0
		var ang_err_deg := 0.0
		var aligned := false
		# Exit transitions are sensitive because player camera keeps moving with gameplay.
		if purpose == "to_free" and is_instance_valid(blend_cam):
			pos_err = blend_cam.global_transform.origin.distance_to(target_cam.global_transform.origin)
			var blend_fwd := (-blend_cam.global_transform.basis.z).normalized()
			var target_fwd := (-target_cam.global_transform.basis.z).normalized()
			var dot_fwd := clamp(blend_fwd.dot(target_fwd), -1.0, 1.0)
			ang_err_deg = rad2deg(acos(dot_fwd))
			if pos_err > 0.02 or ang_err_deg > 0.5:
				_align_player_rig_to_camera(blend_cam, target_cam)
				_sync_player_cam_hierarchy(target_cam)
				aligned = true
		_log_transition("dynamic_finish", {
			"purpose": purpose,
			"target": _camera_debug_name(target_cam),
			"blend": _camera_debug_name(blend_cam),
			"pos_err": pos_err,
			"ang_err_deg": ang_err_deg,
			"aligned": aligned
		})
		target_cam.current = true
	if purpose == "to_free":
		emit_signal("cinematic_stopped")

func trigger_camera_shake(duration: float = 0.35, amplitude: float = 0.08, frequency: float = 28.0, roll_degrees: float = 1.0) -> void:
	if duration <= 0.0:
		stop_camera_shake()
		return
	_shake_active = true
	_shake_duration = duration
	_shake_elapsed = 0.0
	_shake_amplitude = max(0.0, amplitude)
	_shake_frequency = max(0.1, frequency)
	_shake_roll_degrees = roll_degrees
	_shake_seed = float(OS.get_ticks_usec() % 1000000) * 0.00001
	var cam = get_active_camera()
	if cam and is_instance_valid(cam):
		_bind_shake_camera(cam)

func stop_camera_shake() -> void:
	_shake_active = false
	_shake_duration = 0.0
	_shake_elapsed = 0.0
	_restore_shake_camera()

func _bind_shake_camera(cam: Camera) -> void:
	if _shake_cam == cam:
		return
	_restore_shake_camera()
	_shake_cam = cam
	_shake_base_h_offset = float(cam.get("h_offset"))
	_shake_base_v_offset = float(cam.get("v_offset"))
	_shake_base_roll_degrees = cam.rotation_degrees.z

func _restore_shake_camera() -> void:
	if _shake_cam and is_instance_valid(_shake_cam):
		_shake_cam.set("h_offset", _shake_base_h_offset)
		_shake_cam.set("v_offset", _shake_base_v_offset)
		var rot = _shake_cam.rotation_degrees
		rot.z = _shake_base_roll_degrees
		_shake_cam.rotation_degrees = rot
	_shake_cam = null

func _update_camera_shake(dt: float) -> void:
	if not _shake_active:
		return
	var cam = get_active_camera()
	if not cam or not is_instance_valid(cam):
		stop_camera_shake()
		return
	_bind_shake_camera(cam)
	_shake_elapsed += max(0.0, dt)
	if _shake_elapsed >= _shake_duration:
		stop_camera_shake()
		return
	var t = _shake_elapsed / _shake_duration
	var fade = 1.0 - t
	fade *= fade
	var phase = _shake_seed + _shake_elapsed * _shake_frequency * TAU
	var x = sin(phase)
	var y = cos(phase * 1.13 + 1.7)
	var r = sin(phase * 0.79 + 2.3)
	cam.set("h_offset", _shake_base_h_offset + x * _shake_amplitude * fade)
	cam.set("v_offset", _shake_base_v_offset + y * _shake_amplitude * fade)
	var rot = cam.rotation_degrees
	rot.z = _shake_base_roll_degrees + r * _shake_roll_degrees * fade
	cam.rotation_degrees = rot

func step(dt: float):
	_update_dynamic_transition(dt)

	# 1. Evaluate Requests
	var best_req = _evaluate_requests()

	# 2. Update Mode FSM
	_update_mode_fsm(dt, best_req)

	# 3. Update Input FSM (Latch Timer)
	_update_input_fsm(dt)
	_update_camera_shake(dt)

func _evaluate_requests() -> CameraRequest:
	if _active_requests.empty():
		return null

	var invalid_ids := []
	var best: CameraRequest = null
	for id in _active_requests:
		var req = _active_requests[id]
		if req == null:
			invalid_ids.append(id)
			continue
		var req_rig = req.payload.get("rig", null)
		if req_rig != null and not is_instance_valid(req_rig):
			invalid_ids.append(id)
			continue
		var req_vcam = req.payload.get("vcamera", null)
		if req_vcam != null and not is_instance_valid(req_vcam):
			invalid_ids.append(id)
			continue

		if best == null:
			best = req
			continue

		if req.priority > best.priority:
			best = req
		elif req.priority == best.priority:
			if req.id > best.id:
				best = req

	for id in invalid_ids:
		_active_requests.erase(id)

	return best

func _update_mode_fsm(_dt: float, target_req: CameraRequest):
	var target_mode = ControlMode.FREE
	var target_rig = null
	var target_vcam = null
	var transition_time = 0.0

	if target_req:
		target_mode = target_req.mode
		target_rig = target_req.payload.get("rig")
		target_vcam = target_req.payload.get("vcamera")
		transition_time = target_req.payload.get("transition_time", 0.0)
		if target_rig != null and not is_instance_valid(target_rig):
			target_rig = null
		if target_vcam != null and not is_instance_valid(target_vcam):
			target_vcam = null

	# Handle VCamera requests
	if target_vcam and target_req and target_req.source == _vcam_source:
		_handle_vcam_request(target_vcam, target_req.payload, transition_time)
		return

	# Detect Change
	if active_rig != target_rig:
		# State Transition Logic
		var old_cam = get_active_camera()
		_log_transition("target_change", {
			"from_rig": str(active_rig),
			"to_rig": str(target_rig),
			"old_cam": _camera_debug_name(old_cam),
			"target_mode": target_mode
		})
		# If we retarget while returning to FREE, stop that dynamic blend first.
		_cancel_dynamic_transition("retarget_change")

		# Update State
		if target_rig and is_instance_valid(target_rig):
			_active_payload = target_req.payload
			_current_state = CameraModeState.TRANSITION_TO_CINEMATIC
			active_rig = target_rig
			current_control_mode = target_mode
			emit_signal("control_mode_changed", target_mode)

			if active_rig and is_instance_valid(active_rig) and active_rig.has_method("activate"):
				active_rig.activate(false)

			var new_cam = null
			if active_rig and is_instance_valid(active_rig) and active_rig.has_method("get_camera"):
				new_cam = active_rig.get_camera()
				if new_cam and is_instance_valid(new_cam):
					if transition_time > 0.0 and old_cam and old_cam != new_cam:
						var enter_transition_time := _scaled_mode_transition_duration(transition_time)
						_log_transition("to_cinematic_blend", {
							"from": _camera_debug_name(old_cam),
							"to": _camera_debug_name(new_cam),
							"duration": enter_transition_time,
							"duration_requested": transition_time
						})
						# Use dynamic target so the blend keeps following the rig camera
						# while player movement keeps updating it.
						_start_dynamic_transition(old_cam, new_cam, enter_transition_time, "to_cinematic")
					else:
						_cancel_plugin_transition()
						_log_transition("to_cinematic_snap", {
							"to": _camera_debug_name(new_cam)
						})
						new_cam.current = true

			emit_signal("cinematic_started", active_rig.name if active_rig else "")
			_current_state = CameraModeState.CINEMATIC_ACTIVE # Assuming instant for logic flow if handled by plugin

			if _active_payload.get("latch_on_enter", true):
				_engage_input_latch(old_cam)

		else:
			# Returning to Free
			_current_state = CameraModeState.TRANSITION_TO_FREE
			var prev_rig = active_rig
			var exit_transition_time: float = float(transition_time)
			# When exiting because the request was released, target_req is null and transition_time
			# comes as 0. In that path, reuse the active payload/rig transition to avoid hard snaps.
			if exit_transition_time <= 0.0:
				exit_transition_time = float(_active_payload.get("transition_time", 0.0))
			if exit_transition_time <= 0.0 and prev_rig and is_instance_valid(prev_rig):
				if "transition_time" in prev_rig:
					exit_transition_time = prev_rig.transition_time
			exit_transition_time = _scaled_mode_transition_duration(exit_transition_time)

			active_rig = null
			current_control_mode = ControlMode.FREE
			emit_signal("control_mode_changed", ControlMode.FREE)

			if prev_rig and is_instance_valid(prev_rig) and prev_rig.has_method("deactivate"):
				prev_rig.deactivate(false)

			var player_cam = _find_player_camera()
			if player_cam:
				# Align player rig to the current cinematic POV before blending back.
				# This avoids large sweeps to the old pre-cinematic angle on zone exit.
				if old_cam and is_instance_valid(old_cam):
					_align_player_rig_to_camera(old_cam, player_cam)
					if exit_transition_time > 0.0 and old_cam and old_cam != player_cam:
						# Use custom dynamic transition for return
						_start_dynamic_transition(old_cam, player_cam, exit_transition_time, "to_free")
					else:
						_cancel_plugin_transition()
						_log_transition("to_free_snap", {
							"to": _camera_debug_name(player_cam)
						})
						player_cam.current = true
						_sync_player_cam_hierarchy(player_cam)

			emit_signal("cinematic_stopped")
			_current_state = CameraModeState.FREE_ACTIVE

			if _active_payload.get("latch_on_exit", true):
				_engage_input_latch(old_cam)
			_active_payload = {}

	else:
		# Steady State
		if active_rig and is_instance_valid(active_rig):
			_current_state = CameraModeState.CINEMATIC_ACTIVE
		elif _vcam_active_camera and is_instance_valid(_vcam_active_camera):
			if _current_state == CameraModeState.VCAM_BLENDING:
				_vcam_blend_elapsed += _dt
				if _vcam_blend_elapsed >= _vcam_blend_duration:
					_current_state = CameraModeState.VCAM_ACTIVE
					_vcam_blend_elapsed = 0.0
			else:
				_current_state = CameraModeState.VCAM_ACTIVE
		else:
			active_rig = null
			_current_state = CameraModeState.FREE_ACTIVE

func _handle_vcam_request(vcam: Node, payload: Dictionary, duration: float) -> void:
	var old_cam = get_active_camera()
	var scaled_duration := _scaled_mode_transition_duration(duration)
	_find_or_create_vcam_brain()

	# Idempotent guard: avoid re-running activation every frame for the same active target.
	if _vcam_active_camera == vcam and _current_state in [
		CameraModeState.TRANSITION_TO_VCAM,
		CameraModeState.VCAM_BLENDING,
		CameraModeState.VCAM_ACTIVE
	]:
		if vcam and is_instance_valid(vcam):
			vcam.transition_time = scaled_duration
			vcam.enabled = true
			vcam.priority = max(100, int(vcam.priority))
		if _vcam_brain and is_instance_valid(_vcam_brain):
			if not _vcam_brain.current:
				_vcam_brain.current = true
				_log_transition("vcam_reassert_current", {
					"vcam": vcam.name,
					"state": _current_state
				})
		_vcam_blend_duration = max(0.0, scaled_duration)
		return

	if not _vcam_brain:
		printerr("[CinematicManager] Cannot activate VCamera: no VCameraBrain found")
		return

	# If we are overriding a zone/cinematic dynamic blend, stop it now so it doesn't
	# hand back control to the rig camera at dynamic_finish.
	_cancel_dynamic_transition("vcam_override")
	_cancel_plugin_transition()
	
	_current_state = CameraModeState.TRANSITION_TO_VCAM
	_active_payload = payload
	
	if _vcam_active_camera and is_instance_valid(_vcam_active_camera):
		_vcam_active_camera.priority = 0
		_vcam_active_camera.enabled = false
	
	vcam.enabled = true
	vcam.priority = 100
	vcam.transition_time = scaled_duration

	_vcam_active_camera = vcam
	_vcam_blend_duration = max(0.0, scaled_duration)
	_vcam_blend_elapsed = 0.0
	
	# Initialize VCameraBrain position:
	# - smooth blend from old camera when duration > 0
	# - hard cut to target vcam when duration <= 0
	if scaled_duration > 0.0 and old_cam and is_instance_valid(old_cam):
		_vcam_brain.global_transform = old_cam.global_transform
		_vcam_brain.fov = old_cam.fov
	else:
		# Snap to VCamera pose immediately for fast-forward/hard cuts.
		_snap_vcamera_brain_to_active()
	
	_vcam_brain.current = true

	_log_transition("vcam_activate", {
		"vcam": vcam.name,
		"duration": scaled_duration,
		"duration_requested": duration
	})
	
	_engage_input_latch(old_cam)
	
	_current_state = CameraModeState.VCAM_BLENDING if scaled_duration > 0.0 else CameraModeState.VCAM_ACTIVE
	emit_signal("cinematic_started", vcam.name)
	emit_signal("control_mode_changed", ControlMode.FREE)

func _refresh_vcamera_pose(vcam: Node) -> void:
	if not vcam or not is_instance_valid(vcam):
		return

	# Follow/LookAt modifiers run in physics and may be one-frame stale when skip
	# is requested from input. Tick them once before snapping brain pose.
	var follow_mod = vcam.get_node_or_null("Follow")
	if follow_mod and is_instance_valid(follow_mod) and follow_mod.has_method("_physics_process"):
		follow_mod.call("_physics_process", 0.0)

	var look_mod = vcam.get_node_or_null("LookAt")
	if look_mod and is_instance_valid(look_mod) and look_mod.has_method("_physics_process"):
		look_mod.call("_physics_process", 0.0)

	if vcam is Spatial:
		(vcam as Spatial).force_update_transform()

func _snap_vcamera_brain_to_active() -> void:
	if not (_vcam_brain and is_instance_valid(_vcam_brain)):
		return
	if not (_vcam_active_camera and is_instance_valid(_vcam_active_camera)):
		return

	_refresh_vcamera_pose(_vcam_active_camera)

	if _vcam_brain.has_method("snap_transition"):
		_vcam_brain.call("snap_transition", _vcam_active_camera)
	else:
		if _vcam_brain is Camera and _vcam_active_camera is Camera:
			(_vcam_brain as Camera).global_transform = (_vcam_active_camera as Camera).global_transform
			(_vcam_brain as Camera).fov = (_vcam_active_camera as Camera).fov

	if _vcam_brain.has_method("set"):
		_vcam_brain.set("last_active_vcamera", _vcam_active_camera)

	_vcam_brain.current = true

func _sync_player_cam_hierarchy(cam: Camera):
	var parent = cam.get_parent()
	while parent != null:
		if parent.has_method("sync_camera_to_rig"):
			parent.call("sync_camera_to_rig")
			break
		parent = parent.get_parent()


func _align_player_rig_to_camera(target_cam: Camera, player_cam: Camera) -> void:
	if not target_cam or not is_instance_valid(target_cam):
		return
	if not player_cam or not is_instance_valid(player_cam):
		return

	var parent = player_cam.get_parent()
	while parent != null:
		if parent.has_method("align_exit_from_cinematic"):
			parent.call("align_exit_from_cinematic", target_cam)
			return
		if parent.has_method("snap_rig_to_camera_orbit"):
			parent.call("snap_rig_to_camera_orbit", target_cam.global_transform.origin, target_cam.fov)
			return
		parent = parent.get_parent()

func _engage_input_latch(ref_cam: Camera):
	if not ref_cam: return

	latched_camera_basis = ref_cam.global_transform.basis
	latched_control_mode = current_control_mode # Capture mode at moment of latch?
	# Actually, if we are transitioning TO cinematic, we want the OLD mode (FREE usually).
	# If we are transitioning FROM cinematic, we want the OLD mode (CINEMATIC).
	# So current_control_mode is already updated?
	# Wait, in _update_mode_fsm, I update current_control_mode BEFORE calling this.
	# So for "To Cinematic", current is CINEMATIC. We want the OLD one?
	# Spec: "latched_control_mode" captured.
	# If I am moving freely, I want to keep moving freely relative to the OLD camera.
	# So the mode should probably be implicit or FREE?
	# Actually, get_movement_basis uses latched_control_mode to interpret the vector.
	# If I was in FREE mode, my input is relative to Camera.
	# If I was in LOCKED mode, my input is relative to Screen.
	# So yes, we need the *previous* mode.
	# I'll rely on the caller to handle this? Or just assume FREE if we came from player?

	# Correction: The latch ensures we keep moving in the *Same World Direction*.
	# get_move_direction calculates World Dir from Input + Mode + Basis.
	# So we need the Basis and Mode that generated the *current* world direction.
	# If we just switched mode, `latched_control_mode` should be the OLD mode.

	# But I updated `current_control_mode` already.
	# I will just force FREE for now as it's the 99% case for latching (player moving).
	latched_control_mode = ControlMode.FREE

	_input_state = InputState.INPUT_LATCHED
	_latch_timer = LATCH_TIMEOUT
	latch_active = true
	# print("[CinematicManager] Latch Engaged. Basis: ", latched_camera_basis.get_euler())

func _update_input_fsm(dt: float):
	if _input_state == InputState.INPUT_LATCHED:
		_latch_timer -= dt
		if _latch_timer <= 0.0:
			_release_latch("timeout")

func _release_latch(reason: String):
	if _input_state != InputState.INPUT_LATCHED: return
	_input_state = InputState.INPUT_DIRECT
	latch_active = false
	# print("[CinematicManager] Latch Released: ", reason)

func get_movement_basis(input_magnitude: float = 1.0) -> Basis:
	# Check for Neutral Input release
	if _input_state == InputState.INPUT_LATCHED:
		if input_magnitude < LATCH_DEADZONE:
			_release_latch("neutral_input")

	if _input_state == InputState.INPUT_LATCHED:
		return latched_camera_basis

	# Direct Mode
	var cam = get_active_camera()
	if cam:
		return cam.global_transform.basis
	return Basis.IDENTITY

func is_input_latched() -> bool:
	return _input_state == InputState.INPUT_LATCHED

func get_full_snapshot() -> Dictionary:
	var snapshot = {
		"current_control_mode": current_control_mode,
		"latched_camera_basis": [
			latched_camera_basis.x.x, latched_camera_basis.x.y, latched_camera_basis.x.z,
			latched_camera_basis.y.x, latched_camera_basis.y.y, latched_camera_basis.y.z,
			latched_camera_basis.z.x, latched_camera_basis.z.y, latched_camera_basis.z.z
		],
		"latched_control_mode": latched_control_mode,
		"latch_active": latch_active,
		"camera_mode_state": _current_state
	}
	if active_rig:
		snapshot["active_rig_path"] = active_rig.get_path()
	else:
		snapshot["active_rig_path"] = ""
	
	if _vcam_active_camera and is_instance_valid(_vcam_active_camera):
		snapshot["vcam_active_path"] = _vcam_active_camera.get_path()
	else:
		snapshot["vcam_active_path"] = ""
	
	var current_cam = get_viewport().get_camera()
	if current_cam:
		snapshot["current_camera_path"] = current_cam.get_path()
	else:
		snapshot["current_camera_path"] = ""
	
	return snapshot

func restore_snapshot(data: Dictionary) -> void:
	current_control_mode = int(data.get("current_control_mode", ControlMode.FREE))
	var lb = data.get("latched_camera_basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	latched_camera_basis = Basis(
		Vector3(lb[0], lb[1], lb[2]),
		Vector3(lb[3], lb[4], lb[5]),
		Vector3(lb[6], lb[7], lb[8])
	)
	latched_control_mode = int(data.get("latched_control_mode", ControlMode.FREE))
	latch_active = data.get("latch_active", false)
	_current_state = int(data.get("camera_mode_state", CameraModeState.FREE_ACTIVE))
	
	var rig_path = data.get("active_rig_path", "")
	if rig_path != "":
		var rig = get_node(rig_path)
		if rig:
			active_rig = rig
			var cam = active_rig.get_camera()
			if cam:
				cam.current = true
	else:
		active_rig = null
	
	var vcam_path = data.get("vcam_active_path", "")
	if vcam_path != "":
		var vcam = get_node(vcam_path)
		if vcam:
			_vcam_active_camera = vcam
			_find_or_create_vcam_brain()
	else:
		_vcam_active_camera = null
	
	var cam_path = data.get("current_camera_path", "")
	if cam_path != "":
		var cam = get_node(cam_path)
		if cam and cam is Camera:
			cam.current = true

func reset():
	# Reset FSM/request state introduced in PR65.
	_active_requests.clear()
	_active_payload = {}
	_request_counter = 0
	_current_state = CameraModeState.FREE_ACTIVE
	_input_state = InputState.INPUT_DIRECT
	_latch_timer = 0.0

	if active_rig:
		# Stop any active transition immediately
		_cancel_dynamic_transition("reset_active_rig")
		_cancel_plugin_transition()

		# Ensure player camera is active and sync properties if we were transitioning
		var player_cam = _find_player_camera()
		if player_cam:
			player_cam.current = true
			# If the player controller has the synchronization method, call it
			var controller = player_cam.get_parent().get_parent().get_parent().get_parent().get_parent() # Camera <- SpringArm <- Pitch <- Yaw <- CameraRig <- Player
			if not (controller and controller.has_method("sync_camera_to_rig")):
				# Fallback if hierarchy changes
				controller = player_cam.get_tree().get_nodes_in_group("player")[0] if player_cam.get_tree().get_nodes_in_group("player").size() > 0 else null
			
			if controller and controller.has_method("sync_camera_to_rig"):
				controller.call("sync_camera_to_rig")

		deactivate_rig()
	
	# Reset VCamera state
	if _vcam_active_camera and is_instance_valid(_vcam_active_camera):
		_vcam_active_camera.enabled = false
		_vcam_active_camera.priority = 0
	_vcam_active_camera = null

	# Defensive cleanup: clear any lingering virtual camera priorities/enabled flags.
	for vcam in get_tree().get_nodes_in_group("vcamera"):
		if not is_instance_valid(vcam):
			continue
		if "enabled" in vcam:
			vcam.enabled = false
		if "priority" in vcam:
			vcam.priority = 0
	
	if _vcam_brain and is_instance_valid(_vcam_brain):
		_vcam_brain.current = false
	
	active_rig = null
	current_control_mode = ControlMode.FREE
	latched_camera_basis = Basis.IDENTITY
	latched_control_mode = ControlMode.FREE
	latch_active = false
	stop_camera_shake()
	_cancel_dynamic_transition("reset")
	_cancel_plugin_transition()
	
	var player_cam = _find_player_camera()
	if player_cam:
		player_cam.current = true
