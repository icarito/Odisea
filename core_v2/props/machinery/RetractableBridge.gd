tool
extends Spatial
class_name RetractableBridge

signal extended()
signal retracted()
signal extend_progress(ratio)
signal retract_progress(ratio)

export(String, "left", "right") var side: String = "left" setget set_side
export(float) var arm_length: float = 4.0 setget set_arm_length
export(Vector2) var pivot_offset: Vector2 = Vector2.ZERO setget set_pivot_offset
export(int) var extend_steps: int = 30
export(int) var retract_steps: int = 20

var _is_extended: bool = false
var _is_moving: bool = false
var _target_extended: bool = false
var _current_step: int = 0
var _step_timer: float = 0.0
# 30 steps at 60fps = ~0.5s total duration.
var _step_duration: float = 1.0 / 60.0

onready var _base: StaticBody = get_node_or_null("Base")
onready var _arm: KinematicBody = get_node_or_null("Base/Arm")
onready var _platform: KinematicBody = get_node_or_null("Base/Arm/Platform")

func _ready():
	add_to_group("replay_sync")
	_update_layout()
	if not Engine.editor_hint:
		set_physics_process(true)

func _physics_process(delta: float):
	if Engine.editor_hint:
		return

	if _is_moving:
		_step_timer += delta
		if _step_timer >= _step_duration:
			_step_timer = 0.0
			_execute_step()

func _execute_step():
	_current_step += 1
	var total_steps = extend_steps if _target_extended else retract_steps
	var ratio = float(_current_step) / float(total_steps)

	if _target_extended:
		# Extension: Arm rotates 0->90, Platform slides 0->arm_length in parallel
		_update_transforms(ratio)
		emit_signal("extend_progress", ratio)
		if _current_step >= extend_steps:
			_is_moving = false
			_is_extended = true
			emit_signal("extended")
	else:
		# Retraction: Platform retracts first, then arm.
		# Prompt says: "Al llamar a retract(), se invierte: primero la plataforma se repliega completamente, luego el brazo vuelve a 0 grados."
		# This means it's NOT parallel for retraction.
		# Total retraction steps will be split.
		var half_steps = total_steps / 2
		if _current_step <= half_steps:
			# Phase 1: Platform retracts
			var p_ratio = 1.0 - (float(_current_step) / float(half_steps))
			_update_platform(p_ratio)
		else:
			# Phase 2: Arm rotates back
			var a_ratio = 1.0 - (float(_current_step - half_steps) / float(total_steps - half_steps))
			_update_arm(a_ratio)

		emit_signal("retract_progress", ratio)
		if _current_step >= total_steps:
			_is_moving = false
			_is_extended = false
			emit_signal("retracted")

func _update_transforms(ratio: float):
	_update_arm(ratio)
	_update_platform(ratio)

func _update_arm(ratio: float):
	if not _arm: return
	var angle = deg2rad(ratio * 90.0)
	# Side affects axis direction.
	# If side is left, pivot on left, rotates down/out.
	# User: "Z positivo para left, Z negativo para right"
	var z_sign = 1.0 if side == "left" else -1.0
	_arm.rotation.z = angle * z_sign

func _update_platform(ratio: float):
	if not _platform: return
	# Platform slides along the arm. Assume arm X axis is the extension direction.
	_platform.transform.origin.x = ratio * arm_length

func extend():
	if _is_extended or (_is_moving and _target_extended):
		return
	_target_extended = true
	_is_moving = true
	_current_step = 0
	# Reactive: execute first step immediately
	_step_timer = 0.0
	_execute_step()

func retract():
	if not _is_extended or (_is_moving and not _target_extended):
		return
	_target_extended = false
	_is_moving = true
	_current_step = 0
	# Reactive: execute first step immediately
	_step_timer = 0.0
	_execute_step()

func set_side(v):
	side = v
	if Engine.editor_hint: _update_layout()

func set_arm_length(v):
	arm_length = v
	if Engine.editor_hint: _update_layout()

func set_pivot_offset(v):
	pivot_offset = v
	if Engine.editor_hint: _update_layout()

func _update_layout():
	_base = get_node_or_null("Base")
	_arm = get_node_or_null("Base/Arm")
	_platform = get_node_or_null("Base/Arm/Platform")

	if not _base or not _arm or not _platform:
		return

	# Calculate pivot from edge of base
	# Assuming Base is a cube at origin with some size.
	# Let's assume base size is (2, 1, 2) for reference, but we should probably
	# use the Mesh size if available, or just define it.
	var base_mesh = _base.get_node_or_null("MeshInstance")
	var base_half_width = 1.0
	if base_mesh and base_mesh.mesh is CubeMesh:
		base_half_width = base_mesh.mesh.size.x / 2.0

	var pivot_x = -base_half_width if side == "left" else base_half_width
	_arm.transform.origin = Vector3(pivot_x + pivot_offset.x, 0, pivot_offset.y)

	# Update visual scales and offsets based on arm_length
	var arm_mesh = _arm.get_node_or_null("MeshInstance")
	var arm_col = _arm.get_node_or_null("CollisionShape")
	if arm_mesh and arm_mesh.mesh is CubeMesh:
		# Only duplicate if we are at runtime or if we haven't made it local yet
		if not Engine.editor_hint or not arm_mesh.mesh.resource_local_to_scene:
			arm_mesh.mesh = arm_mesh.mesh.duplicate()
			if Engine.editor_hint: arm_mesh.mesh.resource_local_to_scene = true
		arm_mesh.mesh.size.x = arm_length
		arm_mesh.transform.origin.x = arm_length / 2.0
	if arm_col and arm_col.shape is BoxShape:
		if not Engine.editor_hint or not arm_col.shape.resource_local_to_scene:
			arm_col.shape = arm_col.shape.duplicate()
			if Engine.editor_hint: arm_col.shape.resource_local_to_scene = true
		arm_col.shape.extents.x = arm_length / 2.0
		arm_col.transform.origin.x = arm_length / 2.0

	var plat_mesh = _platform.get_node_or_null("MeshInstance")
	var plat_col = _platform.get_node_or_null("CollisionShape")
	if plat_mesh and plat_mesh.mesh is CubeMesh:
		if not Engine.editor_hint or not plat_mesh.mesh.resource_local_to_scene:
			plat_mesh.mesh = plat_mesh.mesh.duplicate()
			if Engine.editor_hint: plat_mesh.mesh.resource_local_to_scene = true
		plat_mesh.mesh.size.x = arm_length
		plat_mesh.transform.origin.x = arm_length / 2.0
	if plat_col and plat_col.shape is BoxShape:
		if not Engine.editor_hint or not plat_col.shape.resource_local_to_scene:
			plat_col.shape = plat_col.shape.duplicate()
			if Engine.editor_hint: plat_col.shape.resource_local_to_scene = true
		plat_col.shape.extents.x = arm_length / 2.0
		plat_col.transform.origin.x = arm_length / 2.0

	if not _is_moving:
		_update_transforms(1.0 if _is_extended else 0.0)

func interact():
	if _is_extended: retract()
	else: extend()

# --- SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"target_extended": _target_extended,
		"is_extended": _is_extended,
		"is_moving": _is_moving,
		"current_step": _current_step,
		"step_timer": _step_timer
	}

func restore_snapshot(data: Dictionary):
	_target_extended = data.get("target_extended", false)
	_is_extended = data.get("is_extended", false)
	_is_moving = data.get("is_moving", false)
	_current_step = data.get("current_step", 0)
	_step_timer = data.get("step_timer", 0.0)

	_update_layout()

	# Explicitly update visuals based on current state
	if not _is_moving:
		_update_transforms(1.0 if _is_extended else 0.0)
	else:
		# If moving, we need to manually call the appropriate update logic
		# for the current step to restore visuals mid-animation.
		var total_steps = extend_steps if _target_extended else retract_steps
		var ratio = float(_current_step) / float(total_steps)
		if _target_extended:
			_update_transforms(ratio)
		else:
			var half_steps = total_steps / 2
			if _current_step <= half_steps:
				var p_ratio = 1.0 - (float(_current_step) / float(half_steps))
				_update_platform(p_ratio)
				_update_arm(1.0) # Arm should be fully extended during platform retraction
			else:
				var a_ratio = 1.0 - (float(_current_step - half_steps) / float(total_steps - half_steps))
				_update_arm(a_ratio)
				_update_platform(0.0) # Platform should be retracted during arm rotation
