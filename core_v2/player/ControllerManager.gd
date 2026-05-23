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

var current_mode: int = -1
var current_gravity_mode: int = GravityModes.Mode.STANDARD_1G
var standard_controller = null
var zero_gravity_controller = null

func _ready() -> void:
	var root = get_parent()
	if not root is KinematicBody:
		push_error("ControllerManager must be a child of a KinematicBody")
		return
	
	standard_controller = root # PlayerControllerV2 is the root script itself
	
	# Find ZeroGravityController if it exists, otherwise we'll switch gracefully
	zero_gravity_controller = root.get_node_or_null("ZeroGravityController")
	
	# Delayed switch to ensure everything is ready
	call_deferred("switch_to", initial_mode)

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
	
	# 1. Disable current controller
	if current_mode == Mode.STANDARD_1G:
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
		
	# 3. Enable new controller
	if new_mode == Mode.STANDARD_1G:
		if standard_controller:
			if "velocity" in standard_controller:
				standard_controller.velocity = transfer_velocity
			if "yaw" in standard_controller:
				standard_controller.yaw = transfer_yaw
			if "pitch" in standard_controller:
				standard_controller.pitch = transfer_pitch
				
	elif new_mode == Mode.ZERO_GRAVITY:
		if not zero_gravity_controller:
			push_error("Cannot switch to ZERO_GRAVITY: ZeroGravityController node not found.")
			return
		if "velocity" in zero_gravity_controller:
			zero_gravity_controller.velocity = transfer_velocity
		if "yaw" in zero_gravity_controller:
			zero_gravity_controller.yaw = transfer_yaw
		if "pitch" in zero_gravity_controller:
			zero_gravity_controller.pitch = transfer_pitch
			
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
