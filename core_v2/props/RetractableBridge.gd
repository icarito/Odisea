extends InteractableBaseV2
class_name RetractableBridge
tool

# RetractableBridge.gd - Mechanical bridge with two-phase animation.
# Inherits from InteractableBaseV2 for deterministic animation state.

export(bool) var starts_extended := false setget set_starts_extended
export(float) var extend_duration := 1.5 setget set_extend_duration
export(float, 2.0, 30.0) var bridge_length := 8.0 setget set_bridge_length
export(float, 2.0, 10.0) var bridge_width := 3.0 setget set_bridge_width

# Alias for compatibility with Batch 3 spec
var extended: bool setget set_extended, get_extended

onready var _arm_front: Spatial = get_node_or_null("ArmFront")
onready var _arm_back: Spatial = get_node_or_null("ArmBack")
onready var _platform: Spatial = get_node_or_null("Platform")
onready var _deck_mesh_node: MeshInstance = get_node_or_null("Platform/DeckMesh")
onready var _collision_node: CollisionShape = get_node_or_null("Platform/StaticBody/CollisionShape")
onready var _rail_left: MeshInstance = get_node_or_null("RailLeft")
onready var _rail_right: MeshInstance = get_node_or_null("RailRight")

func _ready():
	# Sync initial settings
	anim_duration = extend_duration
	starts_active = starts_extended
	._ready()
	_rebuild()

func set_starts_extended(v: bool):
	starts_extended = v
	starts_active = v

func set_extend_duration(v: float):
	extend_duration = v
	anim_duration = v

func set_extended(v: bool):
	set_active(v)

func get_extended() -> bool:
	return is_active

func set_bridge_length(v: float):
	bridge_length = v
	_rebuild()

func set_bridge_width(v: float):
	bridge_width = v
	_rebuild()

func _rebuild():
	if not is_inside_tree(): return

	var half_l = bridge_length * 0.5
	var half_w = bridge_width * 0.5

	# Arms at the ends, transverse
	if _arm_front: _arm_front.translation = Vector3(0, 0, -half_l)
	if _arm_back: _arm_back.translation = Vector3(0, 0, half_l)

	if _arm_front and _arm_front.has_node("ArmMesh"):
		var am = _arm_front.get_node("ArmMesh") as MeshInstance
		if am.mesh is CylinderMesh:
			if not am.mesh.resource_local_to_scene:
				am.mesh = am.mesh.duplicate()
			(am.mesh as CylinderMesh).height = bridge_width
		am.translation = Vector3(0, half_w, 0)
		am.rotation_degrees = Vector3(0, 0, 90)

	if _arm_back and _arm_back.has_node("ArmMesh"):
		var am = _arm_back.get_node("ArmMesh") as MeshInstance
		if am.mesh is CylinderMesh:
			if not am.mesh.resource_local_to_scene:
				am.mesh = am.mesh.duplicate()
			(am.mesh as CylinderMesh).height = bridge_width
		am.translation = Vector3(0, half_w, 0)
		am.rotation_degrees = Vector3(0, 0, 90)

	if _deck_mesh_node and _deck_mesh_node.mesh is CubeMesh:
		if not _deck_mesh_node.mesh.resource_local_to_scene:
			_deck_mesh_node.mesh = _deck_mesh_node.mesh.duplicate()
		(_deck_mesh_node.mesh as CubeMesh).size = Vector3(bridge_width, 0.2, bridge_length)

	if _collision_node and _collision_node.shape is BoxShape:
		if not _collision_node.shape.resource_local_to_scene:
			_collision_node.shape = _collision_node.shape.duplicate()
		(_collision_node.shape as BoxShape).extents = Vector3(half_w, 0.1, half_l)

	if _rail_left:
		_rail_left.translation = Vector3(-half_w, 0.1, 0)
		if _rail_left.mesh is CubeMesh:
			if not _rail_left.mesh.resource_local_to_scene:
				_rail_left.mesh = _rail_left.mesh.duplicate()
			(_rail_left.mesh as CubeMesh).size = Vector3(0.1, 0.1, bridge_length)
	if _rail_right:
		_rail_right.translation = Vector3(half_w, 0.1, 0)
		if _rail_right.mesh is CubeMesh:
			if not _rail_right.mesh.resource_local_to_scene:
				_rail_right.mesh = _rail_right.mesh.duplicate()
			(_rail_right.mesh as CubeMesh).size = Vector3(0.1, 0.1, bridge_length)

	_update_visuals()

func _update_visuals():
	if not _arm_front or not _platform: return

	# Phase 1: Arms (0.0 - 0.4)
	var t_arms = clamp(anim_progress / 0.4, 0.0, 1.0)
	var eased_arms = _ease_out(t_arms)
	var arm_rot_offset = lerp(0.0, 90.0, eased_arms)

	_arm_front.rotation_degrees.z = -arm_rot_offset
	_arm_back.rotation_degrees.z = arm_rot_offset

	# Phase 2: Platform (0.4 - 1.0)
	var t_platform = clamp((anim_progress - 0.4) / 0.6, 0.0, 1.0)
	var eased_platform = _ease_in_out(t_platform)

	_platform.translation.z = lerp(-bridge_length, 0.0, eased_platform)
	_platform.visible = (anim_progress > 0.35)

	if _collision_node:
		_collision_node.disabled = anim_progress < 0.95

func toggle():
	interact()

func extend():
	set_active(true)

func retract():
	set_active(false)

func _on_animation_completed():
	._on_animation_completed()
	if anim_progress >= 1.0:
		emit_signal("bridge_extended")
	elif anim_progress <= 0.0:
		emit_signal("bridge_retracted")

signal bridge_extended()
signal bridge_retracted()
