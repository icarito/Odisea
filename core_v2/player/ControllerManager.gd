extends Node
class_name ControllerManager

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const ZeroGCameraRigScene = preload("res://core_v2/camera/ZeroGCameraRig.tscn")

signal controller_changed(mode)

enum Mode {
	STANDARD_1G,
	ZERO_GRAVITY
}

export(Mode) var initial_mode := Mode.STANDARD_1G
export(bool) var auto_switch_from_gravity_world := true
export(float) var camera_transition_duration := 0.25

var current_mode: int = -1
var current_gravity_mode: int = GravityModes.Mode.STANDARD_1G
var standard_controller = null
var zero_gravity_controller = null
var _standard_camera_rig: Spatial = null
var _zero_g_camera_rig: Spatial = null
var _last_standard_camera_distance := 4.0
var _last_standard_camera_fov := 75.0

func _ready() -> void:
	var root = get_parent()
	if not root is KinematicBody:
		push_error("ControllerManager must be a child of a KinematicBody")
		return
	
	standard_controller = root # PlayerControllerV2 is the root script itself
	
	# Find ZeroGravityController if it exists, otherwise we'll switch gracefully
	zero_gravity_controller = root.get_node_or_null("ZeroGravityController")
	_cache_camera_rigs(root as KinematicBody)
	
	# Connect to all existing zero gravity zones
	var zones = get_tree().get_nodes_in_group("zero_gravity_zones")
	for zone in zones:
		if not zone.is_connected("gravity_zone_changed", self, "_on_gravity_zone_changed"):
			zone.connect("gravity_zone_changed", self, "_on_gravity_zone_changed")
	
	# Delayed switch to ensure everything is ready, without overriding a zone/manual switch.
	call_deferred("_switch_to_initial_mode_if_unset")

func _on_gravity_zone_changed(body: Node, mode: int) -> void:
	if body == get_parent():
		set_gravity_mode(mode)

func _physics_process(_delta: float) -> void:
	if auto_switch_from_gravity_world:
		sync_to_gravity_world()

func sync_to_gravity_world() -> void:
	if not has_node("/root/GravityWorld"):
		return
	var root = get_parent()
	if not root is Spatial:
		return
	var gravity_world = get_node("/root/GravityWorld")
	if not gravity_world or not gravity_world.has_method("get_gravity_mode_at"):
		return
	current_gravity_mode = int(gravity_world.get_gravity_mode_at((root as Spatial).global_transform.origin))
	var target_controller_mode: int = get_controller_mode_for_gravity_mode(current_gravity_mode)
	if target_controller_mode != current_mode:
		switch_to(target_controller_mode)

func get_controller_mode_for_gravity_mode(gravity_mode: int) -> int:
	if gravity_mode == GravityModes.Mode.ZERO_G:
		return Mode.ZERO_GRAVITY
	return Mode.STANDARD_1G

func set_gravity_mode(gravity_mode: int) -> void:
	current_gravity_mode = gravity_mode
	switch_to(get_controller_mode_for_gravity_mode(gravity_mode))

func switch_to(new_mode: int) -> void:
	if new_mode == current_mode:
		return
	if new_mode < 0:
		return
	if new_mode != Mode.STANDARD_1G and new_mode != Mode.ZERO_GRAVITY:
		push_error("[ControllerManager] Invalid controller mode: %s" % str(new_mode))
		return
		
	var root = get_parent() as KinematicBody
	if root == null:
		return
	var exiting_zero_to_standard: bool = current_mode == Mode.ZERO_GRAVITY and new_mode == Mode.STANDARD_1G
	var transition_from_cam: Camera = _find_camera(root.camera_rig) if "camera_rig" in root else null
	var zero_g_zoom_state: Dictionary = _get_zero_g_zoom_state()
	var use_camera_transition: bool = _can_transition_from(transition_from_cam)
	
	# 1. Disable current controller
	if current_mode == Mode.STANDARD_1G:
		_capture_standard_camera_state(root)
		if standard_controller:
			# Release legacy crouch if needed
			if "is_crouching" in standard_controller:
				standard_controller.is_crouching = false
	elif current_mode == Mode.ZERO_GRAVITY:
		pass
			
	# 2. Transfer velocity if possible (to maintain momentum)
	var transfer_velocity := Vector3.ZERO
	var transfer_yaw := 0.0
	var transfer_pitch := 0.0
	
	if current_mode == Mode.STANDARD_1G:
		if standard_controller:
			transfer_velocity = standard_controller.get("velocity") if "velocity" in standard_controller else Vector3.ZERO
			transfer_yaw = standard_controller.get("yaw") if "yaw" in standard_controller else 0.0
			transfer_pitch = standard_controller.get("pitch") if "pitch" in standard_controller else 0.0
	elif current_mode == Mode.ZERO_GRAVITY:
		if zero_gravity_controller:
			transfer_velocity = zero_gravity_controller.get("velocity") if "velocity" in zero_gravity_controller else Vector3.ZERO
			transfer_yaw = zero_gravity_controller.get("yaw") if "yaw" in zero_gravity_controller else 0.0
			transfer_pitch = zero_gravity_controller.get("pitch") if "pitch" in zero_gravity_controller else 0.0
			if exiting_zero_to_standard and zero_gravity_controller.has_method("get_standard_exit_orientation"):
				var exit_orientation: Dictionary = zero_gravity_controller.get_standard_exit_orientation()
				transfer_yaw = float(exit_orientation.get("yaw", transfer_yaw))
				transfer_pitch = float(exit_orientation.get("pitch", transfer_pitch))
			if zero_gravity_controller.has_method("reset_visual_state"):
				zero_gravity_controller.reset_visual_state()
		
	# 3. Enable new controller
	if new_mode == Mode.STANDARD_1G:
		if standard_controller:
			if "velocity" in standard_controller:
				standard_controller.velocity = transfer_velocity
			if "yaw" in standard_controller:
				standard_controller.yaw = transfer_yaw
			if "pitch" in standard_controller:
				standard_controller.pitch = transfer_pitch
		_activate_camera_rig(root, Mode.STANDARD_1G, not use_camera_transition)
		_restore_standard_zoom_state(root, zero_g_zoom_state)
				
	elif new_mode == Mode.ZERO_GRAVITY:
		if not zero_gravity_controller:
			push_error("Cannot switch to ZERO_GRAVITY: ZeroGravityController node not found.")
			return
		_activate_camera_rig(root, Mode.ZERO_GRAVITY, not use_camera_transition)
		_apply_zero_g_zoom_state(_last_standard_camera_distance, _last_standard_camera_fov)
		_align_zero_g_pivot_to_standard(root)
		
		if zero_gravity_controller.has_method("set_camera_rig"):
			zero_gravity_controller.set_camera_rig(_zero_g_camera_rig)
			
		if "velocity" in zero_gravity_controller:
			zero_gravity_controller.velocity = transfer_velocity
			
		if zero_gravity_controller.has_method("sync_state_from_rig"):
			zero_gravity_controller.sync_state_from_rig()
		else:
			if "yaw" in zero_gravity_controller:
				zero_gravity_controller.yaw = transfer_yaw
			if "pitch" in zero_gravity_controller:
				zero_gravity_controller.pitch = transfer_pitch
			
	current_mode = new_mode
	if use_camera_transition:
		_start_camera_transition(transition_from_cam, _find_camera(root.camera_rig) if "camera_rig" in root else null)
	emit_signal("controller_changed", current_mode)

func get_current_controller():
	if current_mode == Mode.ZERO_GRAVITY:
		return zero_gravity_controller
	return standard_controller

func get_snapshot() -> Dictionary:
	return {
		"controller_mode": current_mode,
		"gravity_mode": current_gravity_mode
	}

func restore_snapshot(data: Dictionary) -> void:
	if data.has("gravity_mode"):
		current_gravity_mode = int(data["gravity_mode"])
	if data.has("controller_mode"):
		switch_to(int(data["controller_mode"]))

func _switch_to_initial_mode_if_unset() -> void:
	if current_mode == -1:
		switch_to(initial_mode)

func _cache_camera_rigs(root: KinematicBody) -> void:
	_standard_camera_rig = root.get_node_or_null("CameraRig") as Spatial
	_zero_g_camera_rig = root.get_node_or_null("ZeroGCameraRig") as Spatial
	if _zero_g_camera_rig == null:
		_zero_g_camera_rig = ZeroGCameraRigScene.instance() as Spatial
		_zero_g_camera_rig.name = "ZeroGCameraRig"
		root.add_child(_zero_g_camera_rig)
	_configure_zero_g_camera_rig(root)
	if _zero_g_camera_rig and _zero_g_camera_rig.has_method("set_active"):
		_zero_g_camera_rig.set_active(false)

func _configure_zero_g_camera_rig(root: KinematicBody) -> void:
	var settings = root.get_node_or_null("Logic/ZeroGravity")
	if settings and settings.has_method("configure_camera_rig"):
		settings.configure_camera_rig(_zero_g_camera_rig)

func _capture_standard_camera_state(root: KinematicBody) -> void:
	var cam: Camera = _find_camera(_standard_camera_rig)
	if cam:
		_last_standard_camera_fov = cam.fov
	var arm = root._find_spring_arm(_standard_camera_rig) if root.has_method("_find_spring_arm") and _standard_camera_rig else null
	if arm:
		var current_len = arm.get("current_length")
		var spring_len = arm.get("spring_length")
		if current_len != null:
			_last_standard_camera_distance = float(current_len)
		elif spring_len != null:
			_last_standard_camera_distance = float(spring_len)
	elif "current_spring_length" in root:
		_last_standard_camera_distance = float(root.current_spring_length)

func _get_zero_g_zoom_state() -> Dictionary:
	var cam: Camera = _find_camera(_zero_g_camera_rig)
	var distance := _last_standard_camera_distance
	var fov := _last_standard_camera_fov
	if _zero_g_camera_rig and "camera_distance" in _zero_g_camera_rig:
		distance = float(_zero_g_camera_rig.camera_distance)
	if cam:
		fov = cam.fov
	return {
		"distance": distance,
		"fov": fov
	}

func _apply_zero_g_zoom_state(distance: float, fov: float) -> void:
	if not _zero_g_camera_rig:
		return
	if _zero_g_camera_rig.has_method("set_camera_distance"):
		_zero_g_camera_rig.set_camera_distance(max(0.1, distance))
	if _zero_g_camera_rig.has_method("set_camera_fov"):
		_zero_g_camera_rig.set_camera_fov(fov)

func _align_zero_g_pivot_to_standard(root: KinematicBody) -> void:
	if not _zero_g_camera_rig:
		return
	if _standard_camera_rig and is_instance_valid(_standard_camera_rig):
		_zero_g_camera_rig.transform.origin = _standard_camera_rig.transform.origin
		if _zero_g_camera_rig.has_method("set_orientation_basis"):
			_zero_g_camera_rig.set_orientation_basis(_standard_camera_rig.transform.basis)
		else:
			_zero_g_camera_rig.transform.basis = _standard_camera_rig.transform.basis
			_zero_g_camera_rig.force_update_transform()
	elif "base_rig_y" in root:
		_zero_g_camera_rig.transform.origin = Vector3(0.0, root.base_rig_y, 0.0)
		if _zero_g_camera_rig.has_method("set_orientation_basis"):
			_zero_g_camera_rig.set_orientation_basis(Basis.IDENTITY)
		else:
			_zero_g_camera_rig.transform.basis = Basis.IDENTITY
			_zero_g_camera_rig.force_update_transform()

func _restore_standard_zoom_state(root: KinematicBody, zero_g_zoom_state: Dictionary) -> void:
	var distance: float = float(zero_g_zoom_state.get("distance", _last_standard_camera_distance))
	var fov: float = float(zero_g_zoom_state.get("fov", _last_standard_camera_fov))
	if "base_spring_length_3d" in root:
		root.base_spring_length_3d = distance
	if "current_spring_length" in root:
		root.current_spring_length = distance
	if "base_fov" in root:
		root.base_fov = fov
	var arm = root._find_spring_arm(_standard_camera_rig) if root.has_method("_find_spring_arm") and _standard_camera_rig else null
	if arm:
		if "spring_length" in arm:
			arm.spring_length = distance
		if "target_length" in arm:
			arm.target_length = distance
		if "current_length" in arm:
			arm.current_length = distance
	var cam: Camera = _find_camera(_standard_camera_rig)
	if cam:
		cam.fov = fov

func _start_camera_transition(from_cam: Camera, to_cam: Camera) -> void:
	if camera_transition_duration <= 0.0:
		return
	if not is_instance_valid(from_cam) or not is_instance_valid(to_cam) or from_cam == to_cam:
		return
	var transition = get_node_or_null("/root/CameraTransition")
	if transition and transition.has_method("transition_camera3D"):
		transition.transition_camera3D(from_cam, to_cam, camera_transition_duration)

func _can_transition_from(from_cam: Camera) -> bool:
	return (
		camera_transition_duration > 0.0
		and is_instance_valid(from_cam)
		and get_node_or_null("/root/CameraTransition") != null
	)

func _activate_camera_rig(root: KinematicBody, mode: int, make_current: bool = true) -> void:
	if _standard_camera_rig == null or not is_instance_valid(_standard_camera_rig):
		_standard_camera_rig = root.get_node_or_null("CameraRig") as Spatial
	if _zero_g_camera_rig == null or not is_instance_valid(_zero_g_camera_rig):
		_cache_camera_rigs(root)

	var use_zero_g: bool = mode == Mode.ZERO_GRAVITY
	if _standard_camera_rig:
		_standard_camera_rig.visible = not use_zero_g
		var standard_cam: Camera = _find_camera(_standard_camera_rig)
		if standard_cam:
			standard_cam.current = make_current and not use_zero_g
	if _zero_g_camera_rig:
		_configure_zero_g_camera_rig(root)
		if _zero_g_camera_rig.has_method("set_active") and make_current:
			_zero_g_camera_rig.set_active(use_zero_g)
		else:
			_zero_g_camera_rig.visible = use_zero_g
			var zero_cam: Camera = _find_camera(_zero_g_camera_rig)
			if zero_cam:
				zero_cam.current = make_current and use_zero_g

	var active_rig: Spatial = _zero_g_camera_rig if use_zero_g else _standard_camera_rig
	if active_rig and "camera_rig" in root:
		root.camera_rig = active_rig
	if "_cached_cam" in root:
		root._cached_cam = _find_camera(active_rig)
	if "_cached_spring_arm" in root:
		root._cached_spring_arm = root._find_spring_arm(active_rig) if root.has_method("_find_spring_arm") and active_rig else null
	if not use_zero_g and active_rig:
		if "base_rig_y" in root:
			active_rig.transform.origin.y = root.base_rig_y
		active_rig.transform.basis = Basis(Vector3.UP, root.yaw) * Basis(Vector3.RIGHT, root.pitch)
		active_rig.force_update_transform()

func _find_camera(node: Node) -> Camera:
	if node == null:
		return null
	if node is Camera:
		return node as Camera
	for i in range(node.get_child_count()):
		var cam = _find_camera(node.get_child(i))
		if cam:
			return cam
	return null
