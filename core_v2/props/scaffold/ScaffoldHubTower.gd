tool
extends Spatial
class_name ScaffoldHubTower

# Stacks N ScaffoldHubRing floors into a "cake" with a hollow core.
#
# Radial walkways and the maintenance elevator dock against the outer face.
# Per-floor angles are authored as flat arrays so they stay editable from the
# inspector in Godot 3.6, which has no typed-array export.

const RING_SCENE := preload("res://core_v2/props/scaffold/ScaffoldHubRing.tscn")

export(int, 1, 24) var floor_count := 6 setget set_floor_count
export(float, 0.5, 40.0, 0.1) var floor_height := 4.5 setget set_floor_height
export(float, -100.0, 100.0, 0.1) var base_y := 0.0 setget set_base_y

export(int, 3, 32) var sides := 8 setget set_sides
export(float, 0.5, 60.0, 0.1) var outer_radius := 13.0 setget set_outer_radius
export(float, 0.0, 60.0, 0.1) var inner_radius := 9.0 setget set_inner_radius
export(float, 0.2, 20.0, 0.1) var deck_thickness := 0.2 setget set_deck_thickness

# One entry per floor. Empty or short arrays simply leave the remaining floors
# without that opening. The legacy names mean walkway and elevator angles;
# both currently open only the outer rail.
export(Array, float) var inner_opening_angles_deg := [] setget set_inner_opening_angles_deg
export(Array, float) var outer_opening_angles_deg := [] setget set_outer_opening_angles_deg
export(float, 0.0, 100.0, 0.1) var opening_width := 2.0 setget set_opening_width
# Angular half-width used to turn a single authored angle into a range. Only has
# to be wide enough to land inside the target sector.
export(float, 0.1, 45.0, 0.1) var opening_angle_margin := 1.0 setget set_opening_angle_margin

export(bool) var rail_outer := true setget set_rail_outer
export(bool) var rail_inner := true setget set_rail_inner
# Legs reach down from the first floor to this local Y. Upper floors always land
# on the floor below.
export(float, -200.0, 200.0, 0.1) var ground_y := 0.0 setget set_ground_y

export(bool) var auto_build := true setget set_auto_build
export(bool) var rebuild_baked_items := false

var _build_queued := false

func _ready() -> void:
	if Engine.editor_hint:
		_queue_build()
		return
	if get_child_count() != 0 and not rebuild_baked_items:
		return  # floors already baked into the scene
	build()

func set_floor_count(value: int) -> void:
	floor_count = clamp(value, 1, 24)
	_queue_build()

func set_floor_height(value: float) -> void:
	floor_height = max(value, 0.5)
	_queue_build()

func set_base_y(value: float) -> void:
	base_y = value
	_queue_build()

func set_sides(value: int) -> void:
	sides = clamp(value, 3, 32)
	_queue_build()

func set_outer_radius(value: float) -> void:
	outer_radius = max(value, 0.5)
	_queue_build()

func set_inner_radius(value: float) -> void:
	inner_radius = max(value, 0.0)
	_queue_build()

func set_deck_thickness(value: float) -> void:
	deck_thickness = max(value, 0.2)
	_queue_build()

func set_inner_opening_angles_deg(value: Array) -> void:
	inner_opening_angles_deg = value
	_queue_build()

func set_outer_opening_angles_deg(value: Array) -> void:
	outer_opening_angles_deg = value
	_queue_build()

func set_opening_width(value: float) -> void:
	opening_width = max(value, 0.0)
	_queue_build()

func set_opening_angle_margin(value: float) -> void:
	opening_angle_margin = max(value, 0.1)
	_queue_build()

func set_rail_outer(value: bool) -> void:
	rail_outer = value
	_queue_build()

func set_rail_inner(value: bool) -> void:
	rail_inner = value
	_queue_build()

func set_ground_y(value: float) -> void:
	ground_y = value
	_queue_build()

func set_auto_build(value: bool) -> void:
	auto_build = value
	if auto_build:
		_queue_build()

func _queue_build() -> void:
	if not auto_build or not is_inside_tree():
		return
	if _build_queued:
		return
	_build_queued = true
	call_deferred("build")

func build() -> void:
	_build_queued = false
	_clear_children()
	var scene_owner := _get_scene_owner()

	for i in range(floor_count):
		var deck_y: float = base_y + floor_height * float(i)
		var stop := Position3D.new()
		stop.name = "ElevatorStop_%d" % i
		add_child(stop)
		var stop_xform := stop.transform
		stop_xform.origin = Vector3(0.0, deck_y, 0.0)
		stop.transform = stop_xform
		if scene_owner:
			stop.owner = scene_owner

		# Ground level already has its own floor; only upper levels need hubs.
		if i == 0:
			continue

		var ring: Spatial = RING_SCENE.instance() as Spatial
		if not ring:
			push_warning("ScaffoldHubTower: ring scene root must extend Spatial.")
			return
		ring.name = "Floor_%d" % i
		# Assign before add_child so the ring's own deferred build sees the final
		# values and runs exactly once.
		ring.sides = sides
		ring.outer_radius = outer_radius
		ring.inner_radius = inner_radius
		ring.platform_height = deck_thickness
		ring.opening_width = opening_width
		ring.rail_outer = rail_outer
		ring.rail_inner = rail_inner
		ring.inner_openings_deg = []
		ring.outer_openings_deg = _walkway_ranges_for_floor(i) + _range_for_floor(outer_opening_angles_deg, i)
		# Every generated upper ring stands on the level below it.
		ring.support_base_local_y = -floor_height
		ring.auto_build = true

		add_child(ring)
		var xform := ring.transform
		xform.origin = Vector3(0.0, deck_y, 0.0)
		ring.transform = xform
		if scene_owner:
			ring.owner = scene_owner

func _range_for_floor(angles: Array, index: int) -> Array:
	if index < 0 or index >= angles.size():
		return []
	var angle: float = float(angles[index])
	return [ Vector2(angle - opening_angle_margin, angle + opening_angle_margin) ]

func _walkway_ranges_for_floor(index: int) -> Array:
	if index == 0:
		return [Vector2(-1.0, 1.0), Vector2(89.0, 91.0), Vector2(179.0, 181.0), Vector2(269.0, 271.0)]
	return _range_for_floor(inner_opening_angles_deg, index)

# World-space position of a floor's deck, for aligning walkways and elevators.
func get_floor_y(index: int) -> float:
	return base_y + floor_height * float(index)

func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

func _get_scene_owner() -> Node:
	if owner:
		return owner
	if Engine.editor_hint and get_tree():
		return get_tree().edited_scene_root
	return null
