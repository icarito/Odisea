extends Node
class_name ControllerManager

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")

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
var _last_standard_camera_distance := 4.0
var _last_standard_camera_fov := 75.0

func _ready() -> void:
	var root = get_parent()
	if not root is KinematicBody:
		push_error("ControllerManager must be a child of a KinematicBody")
		return

	standard_controller = root
	zero_gravity_controller = root.get_node_or_null("ZeroGravityController")
	_standard_camera_rig = root.get_node_or_null("CameraRig") as Spatial

	var zones = get_tree().get_nodes_in_group("zero_gravity_zones")
	for zone in zones:
		if not zone.is_connected("gravity_zone_changed", self, "_on_gravity_zone_changed"):
			zone.connect("gravity_zone_changed", self, "_on_gravity_zone_changed")

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

	if _standard_camera_rig == null or not is_instance_valid(_standard_camera_rig):
		_standard_camera_rig = root.get_node_or_null("CameraRig") as Spatial

	var exiting_zero_to_standard: bool = current_mode == Mode.ZERO_GRAVITY and new_mode == Mode.STANDARD_1G
	var transition_from_cam: Camera = _find_camera(_standard_camera_rig)
	var _use_camera_transition: bool = _can_transition_from(transition_from_cam)

	# 1. Capture state leaving current mode
	if current_mode == Mode.STANDARD_1G:
		_capture_standard_camera_state(root)
		if standard_controller and "is_crouching" in standard_controller:
			standard_controller.is_crouching = false
	elif current_mode == Mode.ZERO_GRAVITY:
		pass

	# 2. Transfer velocity / orientation
	var transfer_velocity := Vector3.ZERO
	var transfer_yaw := 0.0
	var transfer_pitch := 0.0

	if current_mode == Mode.STANDARD_1G and standard_controller:
		transfer_velocity = standard_controller.get("velocity") if "velocity" in standard_controller else Vector3.ZERO
		transfer_yaw      = standard_controller.get("yaw")      if "yaw"      in standard_controller else 0.0
		transfer_pitch    = standard_controller.get("pitch")    if "pitch"    in standard_controller else 0.0
	elif current_mode == Mode.ZERO_GRAVITY and zero_gravity_controller:
		transfer_velocity = zero_gravity_controller.get("velocity") if "velocity" in zero_gravity_controller else Vector3.ZERO
		transfer_yaw      = zero_gravity_controller.get("yaw")      if "yaw"      in zero_gravity_controller else 0.0
		transfer_pitch    = zero_gravity_controller.get("pitch")    if "pitch"    in zero_gravity_controller else 0.0
		if exiting_zero_to_standard and zero_gravity_controller.has_method("get_standard_exit_orientation"):
			var exit_orientation: Dictionary = zero_gravity_controller.get_standard_exit_orientation()
			transfer_yaw   = float(exit_orientation.get("yaw",   transfer_yaw))
			transfer_pitch = float(exit_orientation.get("pitch", transfer_pitch))
		if zero_gravity_controller.has_method("reset_visual_state"):
			zero_gravity_controller.reset_visual_state()

	# 3. Enable new controller — standard CameraRig stays active in both modes
	if new_mode == Mode.STANDARD_1G:
		if standard_controller:
			if "velocity" in standard_controller: standard_controller.velocity = transfer_velocity
			if "yaw"      in standard_controller: standard_controller.yaw      = transfer_yaw
			if "pitch"    in standard_controller: standard_controller.pitch    = transfer_pitch
			if exiting_zero_to_standard:
				if "movement_logic" in standard_controller and is_instance_valid(standard_controller.movement_logic):
					standard_controller.movement_logic.horizontal_velocity = Vector3(transfer_velocity.x, 0.0, transfer_velocity.z)
				if "jump_logic" in standard_controller and is_instance_valid(standard_controller.jump_logic):
					standard_controller.jump_logic.set_internal_velocity(transfer_velocity.y)
		_restore_standard_rig(root)
		_restore_standard_zoom_state(root)

	elif new_mode == Mode.ZERO_GRAVITY:
		if not zero_gravity_controller:
			push_error("Cannot switch to ZERO_GRAVITY: ZeroGravityController node not found.")
			return
		if zero_gravity_controller.has_method("set_camera_rig"):
			zero_gravity_controller.set_camera_rig(_standard_camera_rig)
		if "velocity" in zero_gravity_controller:
			zero_gravity_controller.velocity = transfer_velocity

	current_mode = new_mode
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

func _capture_standard_camera_state(root: KinematicBody) -> void:
	var cam: Camera = _find_camera(_standard_camera_rig)
	if cam:
		_last_standard_camera_fov = cam.fov
	var arm = root._find_spring_arm(_standard_camera_rig) if root.has_method("_find_spring_arm") and _standard_camera_rig else null
	if arm:
		var current_len = arm.get("current_length")
		var spring_len  = arm.get("spring_length")
		if current_len != null:
			_last_standard_camera_distance = float(current_len)
		elif spring_len != null:
			_last_standard_camera_distance = float(spring_len)
	elif "current_spring_length" in root:
		_last_standard_camera_distance = float(root.current_spring_length)

func _restore_standard_rig(root: KinematicBody) -> void:
	if not is_instance_valid(_standard_camera_rig):
		return
	_standard_camera_rig.visible = true
	var cam := _find_camera(_standard_camera_rig)
	if cam:
		cam.current = true
	if "camera_rig" in root:
		root.camera_rig = _standard_camera_rig
	if "_cached_cam" in root:
		root._cached_cam = cam
	if "_cached_spring_arm" in root:
		root._cached_spring_arm = root._find_spring_arm(_standard_camera_rig) if root.has_method("_find_spring_arm") else null
	if "base_rig_y" in root:
		_standard_camera_rig.transform.origin.y = root.base_rig_y
	var prefix: Basis = root.get("camera_basis_prefix") if "camera_basis_prefix" in root else Basis.IDENTITY
	_standard_camera_rig.transform.basis = prefix * Basis(Vector3.UP, root.yaw) * Basis(Vector3.RIGHT, root.pitch)
	if _standard_camera_rig.is_inside_tree():
		_standard_camera_rig.force_update_transform()

func _restore_standard_zoom_state(root: KinematicBody) -> void:
	var distance := _last_standard_camera_distance
	var fov      := _last_standard_camera_fov
	if "base_spring_length_3d" in root: root.base_spring_length_3d = distance
	if "current_spring_length"  in root: root.current_spring_length  = distance
	if "base_fov"               in root: root.base_fov               = fov
	var arm = root._find_spring_arm(_standard_camera_rig) if root.has_method("_find_spring_arm") and _standard_camera_rig else null
	if arm:
		if "spring_length"  in arm: arm.spring_length  = distance
		if "target_length"  in arm: arm.target_length  = distance
		if "current_length" in arm: arm.current_length = distance
	var cam: Camera = _find_camera(_standard_camera_rig)
	if cam:
		cam.fov = fov

func _can_transition_from(from_cam: Camera) -> bool:
	if not is_inside_tree():
		return false
	return (
		camera_transition_duration > 0.0
		and is_instance_valid(from_cam)
		and from_cam.is_inside_tree()
		and get_node_or_null("/root/CameraTransition") != null
	)

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
