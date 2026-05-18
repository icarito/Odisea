extends Node
class_name ControllerManager

signal controller_changed(mode)

enum Mode {
	STANDARD_1G,
	ZERO_GRAVITY
}

export(Mode) var initial_mode := Mode.STANDARD_1G

var current_mode: int = -1
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

func switch_to(new_mode: int) -> void:
	print("[ControllerManager] switch_to called with: ", new_mode)
	if new_mode == current_mode:
		return
		
	var root = get_parent() as KinematicBody
	
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
