tool
extends Spatial
class_name SteelGratePlatform

const DEFAULT_FOOTSTEP_PROFILE := preload("res://core_v2/audio/footsteps/footstep_profile_scaffold_metal.tres")
const FOOTSTEP_SURFACE_SCRIPT := preload("res://core_v2/systems/footsteps/footstep_surface.gd")

export(float, 1.0, 100.0, 0.1) var platform_width := 3.0 setget set_platform_width
export(float, 1.0, 100.0, 0.1) var platform_depth := 3.0 setget set_platform_depth
# Extends each radial side of the deck independently.  This turns the plan
# into an isosceles trapezoid, useful for mitered circular walkways.
export(float, -10.0, 10.0, 0.01) var left_depth_offset := 0.0 setget set_left_depth_offset
export(float, -10.0, 10.0, 0.01) var right_depth_offset := 0.0 setget set_right_depth_offset
# Per-corner plan offsets. RadialScatter fills these for exact spiral miters;
# zero preserves the regular trapezoid defined above.
export(float, -10.0, 10.0, 0.01) var front_left_depth_offset := 0.0 setget set_front_left_depth_offset
export(float, -10.0, 10.0, 0.01) var front_right_depth_offset := 0.0 setget set_front_right_depth_offset
export(float, -10.0, 10.0, 0.01) var back_left_depth_offset := 0.0 setget set_back_left_depth_offset
export(float, -10.0, 10.0, 0.01) var back_right_depth_offset := 0.0 setget set_back_right_depth_offset
# Lateral per-corner offsets complete the arbitrary deck quad. They are used
# by radial joins to put matching support posts at one shared world point.
export(float, -10.0, 10.0, 0.01) var front_left_width_offset := 0.0 setget set_front_left_width_offset
export(float, -10.0, 10.0, 0.01) var front_right_width_offset := 0.0 setget set_front_right_width_offset
export(float, -10.0, 10.0, 0.01) var back_left_width_offset := 0.0 setget set_back_left_width_offset
export(float, -10.0, 10.0, 0.01) var back_right_width_offset := 0.0 setget set_back_right_width_offset
# Keeps frame and side-rail endpoints on the common miter plane instead of
# retracting them by one tube radius at a generated spiral joint.
export(bool) var snap_mitered_joins := false setget set_snap_mitered_joins
export(float, 0.2, 100.0, 0.1) var platform_height := 1.6 setget set_platform_height
export(float, -20.0, 20.0, 0.1) var front_height_offset := 0.0 setget set_front_height_offset
export(float, -20.0, 20.0, 0.1) var back_height_offset := 0.0 setget set_back_height_offset
export(float, -20.0, 20.0, 0.1) var left_height_offset := 0.0 setget set_left_height_offset
export(float, -20.0, 20.0, 0.1) var right_height_offset := 0.0 setget set_right_height_offset
export(float, -200.0, 200.0, 0.1) var support_base_local_y := 0.0 setget set_support_base_local_y
export(float, 0.04, 2.0, 0.01) var tube_radius := 0.07 setget set_tube_radius
export(float, 0.04, 2.0, 0.01) var deck_frame_thickness := 0.10 setget set_deck_frame_thickness
export(float, 0.05, 0.95, 0.01) var grate_alpha_threshold := 0.46 setget set_grate_alpha_threshold
export(Color) var grate_color := Color(0.42, 0.46, 0.50, 1.0) setget set_grate_color
export(float, 0.15, 2.0, 0.01) var grate_brightness := 0.72 setget set_grate_brightness
export(float, -45.0, 45.0, 0.5) var grate_pattern_angle_degrees := 0.0 setget set_grate_pattern_angle_degrees
export(float, -0.35, 0.35, 0.01) var grate_pattern_shear := 0.0 setget set_grate_pattern_shear
export(float, 1.0, 20.0, 0.1) var support_spacing := 5.0 setget set_support_spacing
export(float, 0.0, 20.0, 0.05) var rail_height := 1.1 setget set_rail_height
export(float, 0.0, 1.0, 0.05) var rail_mid_ratio := 0.5 setget set_rail_mid_ratio
export(Color) var frame_color := Color(0.18, 0.19, 0.21, 1.0) setget set_frame_color
export(Color) var rail_color := Color(0.18, 0.19, 0.21, 1.0) setget set_rail_color
export(bool) var rail_front := true setget set_rail_front
export(bool) var rail_back := true setget set_rail_back
export(bool) var rail_left := false setget set_rail_left
export(bool) var rail_right := false setget set_rail_right
export(bool) var rail_infill_enabled := true setget set_rail_infill_enabled
export(float, 0.0, 100.0, 0.1) var rail_front_opening_width := 0.0 setget set_rail_front_opening_width
export(float, 0.0, 100.0, 0.1) var rail_back_opening_width := 0.0 setget set_rail_back_opening_width
export(float, 0.0, 100.0, 0.1) var rail_left_opening_width := 0.0 setget set_rail_left_opening_width
export(float, 0.0, 100.0, 0.1) var rail_right_opening_width := 0.0 setget set_rail_right_opening_width
export(float, 0.0, 1.0, 0.01) var rail_front_opening_gravity := 0.5 setget set_rail_front_opening_gravity
export(float, 0.0, 1.0, 0.01) var rail_back_opening_gravity := 0.5 setget set_rail_back_opening_gravity
export(float, 0.0, 1.0, 0.01) var rail_left_opening_gravity := 0.5 setget set_rail_left_opening_gravity
export(float, 0.0, 1.0, 0.01) var rail_right_opening_gravity := 0.5 setget set_rail_right_opening_gravity
export(Resource) var footstep_profile: Resource = DEFAULT_FOOTSTEP_PROFILE setget set_footstep_profile

const PROP_LAYER := 64
const PROP_VISUAL_LAYER := 64
const CYLINDER_SEGMENTS := 12
const JOINT_SCALE := 1.35
const GRATE_REPEAT_PER_METER := 1.35
const GRATE_OVERLAP_WITH_FRAME := 0.35
const GRATE_RECESS := 0.015

var _visual_root: Spatial = null
var _body: StaticBody = null
var _footstep_surface: Spatial = null
var _frame_material: SpatialMaterial = null
var _rail_material: SpatialMaterial = null
var _grate_material: Material = null
var _fence_material: Material = null

# Shared meshes — reused across all tubes of the same type to reduce draw calls.
# Keyed by (radius, length) for cylinders and radius for spheres/caps.
var _cylinder_mesh_cache: Dictionary = {}
var _sphere_mesh_cache: Dictionary = {}


func _ready():
	_ensure_structure()
	_rebuild()

func set_platform_width(value: float) -> void:
	platform_width = value
	_queue_rebuild()

func set_platform_depth(value: float) -> void:
	platform_depth = value
	_queue_rebuild()

func set_left_depth_offset(value: float) -> void:
	left_depth_offset = value
	_queue_rebuild()

func set_right_depth_offset(value: float) -> void:
	right_depth_offset = value
	_queue_rebuild()

func set_front_left_depth_offset(value: float) -> void:
	front_left_depth_offset = value
	_queue_rebuild()

func set_front_right_depth_offset(value: float) -> void:
	front_right_depth_offset = value
	_queue_rebuild()

func set_back_left_depth_offset(value: float) -> void:
	back_left_depth_offset = value
	_queue_rebuild()

func set_back_right_depth_offset(value: float) -> void:
	back_right_depth_offset = value
	_queue_rebuild()

func set_snap_mitered_joins(value: bool) -> void:
	snap_mitered_joins = value
	_queue_rebuild()

func set_front_left_width_offset(value: float) -> void:
	front_left_width_offset = value
	_queue_rebuild()

func set_front_right_width_offset(value: float) -> void:
	front_right_width_offset = value
	_queue_rebuild()

func set_back_left_width_offset(value: float) -> void:
	back_left_width_offset = value
	_queue_rebuild()

func set_back_right_width_offset(value: float) -> void:
	back_right_width_offset = value
	_queue_rebuild()

func set_platform_height(value: float) -> void:
	platform_height = value
	_queue_rebuild()

func set_front_height_offset(value: float) -> void:
	front_height_offset = value
	_queue_rebuild()

func set_back_height_offset(value: float) -> void:
	back_height_offset = value
	_queue_rebuild()

func set_left_height_offset(value: float) -> void:
	left_height_offset = value
	_queue_rebuild()

func set_right_height_offset(value: float) -> void:
	right_height_offset = value
	_queue_rebuild()

func set_support_base_local_y(value: float) -> void:
	support_base_local_y = value
	_queue_rebuild()

func set_tube_radius(value: float) -> void:
	tube_radius = value
	_queue_rebuild()

func set_deck_frame_thickness(value: float) -> void:
	deck_frame_thickness = value
	_queue_rebuild()

func set_grate_alpha_threshold(value: float) -> void:
	grate_alpha_threshold = value
	_queue_rebuild()

func set_grate_color(value: Color) -> void:
	grate_color = value
	_queue_rebuild()

func set_grate_brightness(value: float) -> void:
	grate_brightness = value
	_queue_rebuild()

func set_grate_pattern_angle_degrees(value: float) -> void:
	grate_pattern_angle_degrees = value
	_queue_rebuild()

func set_grate_pattern_shear(value: float) -> void:
	grate_pattern_shear = value
	_queue_rebuild()

func set_support_spacing(value: float) -> void:
	support_spacing = value
	_queue_rebuild()

func set_rail_height(value: float) -> void:
	rail_height = value
	_queue_rebuild()

func set_rail_mid_ratio(value: float) -> void:
	rail_mid_ratio = value
	_queue_rebuild()

func set_frame_color(value: Color) -> void:
	frame_color = value
	_queue_rebuild()

func set_rail_color(value: Color) -> void:
	rail_color = value
	_queue_rebuild()

func set_rail_front(value: bool) -> void:
	rail_front = value
	_queue_rebuild()

func set_rail_back(value: bool) -> void:
	rail_back = value
	_queue_rebuild()

func set_rail_left(value: bool) -> void:
	rail_left = value
	_queue_rebuild()

func set_rail_right(value: bool) -> void:
	rail_right = value
	_queue_rebuild()

func set_rail_infill_enabled(value: bool) -> void:
	rail_infill_enabled = value
	_queue_rebuild()

func set_rail_front_opening_width(value: float) -> void:
	rail_front_opening_width = value
	_queue_rebuild()

func set_rail_back_opening_width(value: float) -> void:
	rail_back_opening_width = value
	_queue_rebuild()

func set_rail_left_opening_width(value: float) -> void:
	rail_left_opening_width = value
	_queue_rebuild()

func set_rail_right_opening_width(value: float) -> void:
	rail_right_opening_width = value
	_queue_rebuild()

func set_rail_front_opening_gravity(value: float) -> void:
	rail_front_opening_gravity = value
	_queue_rebuild()

func set_rail_back_opening_gravity(value: float) -> void:
	rail_back_opening_gravity = value
	_queue_rebuild()

func set_rail_left_opening_gravity(value: float) -> void:
	rail_left_opening_gravity = value
	_queue_rebuild()

func set_rail_right_opening_gravity(value: float) -> void:
	rail_right_opening_gravity = value
	_queue_rebuild()

func set_footstep_profile(value: Resource) -> void:
	footstep_profile = value
	_sync_footstep_surface()

func _queue_rebuild() -> void:
	if is_inside_tree():
		_rebuild()

func _ensure_structure() -> void:
	_visual_root = get_node_or_null("VisualRoot")
	if not _visual_root:
		_visual_root = Spatial.new()
		_visual_root.name = "VisualRoot"
		add_child(_visual_root)

	_body = get_node_or_null("StaticBody")
	if not _body:
		_body = StaticBody.new()
		_body.name = "StaticBody"
		_body.collision_layer = PROP_LAYER
		_body.collision_mask = 255
		add_child(_body)

	_sync_footstep_surface()

func _rebuild() -> void:
	if not _visual_root or not _body:
		return

	_sync_footstep_surface()
	_clear_children(_visual_root)
	_clear_body_collisions()
	_cylinder_mesh_cache.clear()
	_sphere_mesh_cache.clear()
	_build_materials()

	var half_w = platform_width * 0.5
	var deck_t = max(deck_frame_thickness, tube_radius * 1.2)

	_add_deck_collision(half_w, deck_t)
	_add_grate_deck()

	var join_inset: float = 0.0 if snap_mitered_joins else tube_radius
	var front_left_top := _deck_point(-half_w + tube_radius, -1.0, join_inset)
	var front_right_top := _deck_point(half_w - tube_radius, -1.0, join_inset)
	var back_left_top := _deck_point(-half_w + tube_radius, 1.0, join_inset)
	var back_right_top := _deck_point(half_w - tube_radius, 1.0, join_inset)
	front_left_top.y -= tube_radius
	front_right_top.y -= tube_radius
	back_left_top.y -= tube_radius
	back_right_top.y -= tube_radius

	_add_tube_between("Leg_FL", Vector3(front_left_top.x, support_base_local_y, front_left_top.z), front_left_top, _frame_material)
	_add_tube_between("Leg_FR", Vector3(front_right_top.x, support_base_local_y, front_right_top.z), front_right_top, _frame_material)
	_add_tube_between("Leg_BL", Vector3(back_left_top.x, support_base_local_y, back_left_top.z), back_left_top, _frame_material)
	_add_tube_between("Leg_BR", Vector3(back_right_top.x, support_base_local_y, back_right_top.z), back_right_top, _frame_material)
	_add_leg_collision("LegCollision_FL", Vector3(front_left_top.x, support_base_local_y, front_left_top.z), front_left_top)
	_add_leg_collision("LegCollision_FR", Vector3(front_right_top.x, support_base_local_y, front_right_top.z), front_right_top)
	_add_leg_collision("LegCollision_BL", Vector3(back_left_top.x, support_base_local_y, back_left_top.z), back_left_top)
	_add_leg_collision("LegCollision_BR", Vector3(back_right_top.x, support_base_local_y, back_right_top.z), back_right_top)

	_add_tube_between("BeamFront", front_left_top, front_right_top, _frame_material)
	_add_tube_between("BeamBack", back_left_top, back_right_top, _frame_material)
	_add_tube_between("BeamLeft", front_left_top, back_left_top, _frame_material)
	_add_tube_between("BeamRight", front_right_top, back_right_top, _frame_material)
	_add_intermediate_leg_supports(front_left_top, front_right_top, back_left_top, back_right_top)
	_add_joint_cap("FrameJoint_FL", front_left_top, _frame_material)
	_add_joint_cap("FrameJoint_FR", front_right_top, _frame_material)
	_add_joint_cap("FrameJoint_BL", back_left_top, _frame_material)
	_add_joint_cap("FrameJoint_BR", back_right_top, _frame_material)

	_build_side_rail("Front", rail_front, true, -platform_depth * 0.5 + tube_radius, rail_front_opening_width, rail_front_opening_gravity)
	_build_side_rail("Back", rail_back, true, platform_depth * 0.5 - tube_radius, rail_back_opening_width, rail_back_opening_gravity)
	_build_side_rail("Left", rail_left, false, -half_w + tube_radius, rail_left_opening_width, rail_left_opening_gravity)
	_build_side_rail("Right", rail_right, false, half_w - tube_radius, rail_right_opening_width, rail_right_opening_gravity)

func _build_materials() -> void:
	# Frame tubes: match LOD InfiniteScaffoldField look — metallic pipe feel.
	_frame_material = SpatialMaterial.new()
	_frame_material.albedo_color = frame_color
	_frame_material.metallic = 0.80
	_frame_material.roughness = 0.55
	_frame_material.metallic_specular = 0.5
	_frame_material.rim_enabled = true
	_frame_material.rim = 0.4
	_frame_material.rim_tint = 0.3

	_rail_material = SpatialMaterial.new()
	_rail_material.albedo_color = rail_color
	_rail_material.metallic = 0.78
	_rail_material.roughness = 0.58
	_rail_material.metallic_specular = 0.5
	_rail_material.rim_enabled = true
	_rail_material.rim = 0.4
	_rail_material.rim_tint = 0.3

	# Grate: alpha scissor requires flags_transparent = true in Godot 3.
	# Keep metallic/roughness from the base material (steel-looking), only
	# override color tint and the scissor threshold.
	_grate_material = load("res://textures/trenchbroom/steel_grate_platform.tres").duplicate(true)
	if _grate_material is SpatialMaterial:
		var g := _grate_material as SpatialMaterial
		g.flags_transparent = true
		g.params_use_alpha_scissor = true
		g.params_alpha_scissor_threshold = grate_alpha_threshold
		g.params_cull_mode = SpatialMaterial.CULL_DISABLED
		g.albedo_color = Color(
			clamp(grate_color.r * grate_brightness, 0.0, 1.0),
			clamp(grate_color.g * grate_brightness, 0.0, 1.0),
			clamp(grate_color.b * grate_brightness, 0.0, 1.0),
			grate_color.a
		)
		# Let the base .tres metallic/roughness values through — they give the
		# steel look. Only clamp to avoid going fully mirror-like.
		g.metallic = clamp(g.metallic, 0.3, 0.9)
		g.roughness = clamp(g.roughness, 0.35, 0.75)

	_fence_material = load("res://textures/trenchbroom/metal_fence_panel.tres").duplicate(true)
	if not _fence_material:
		_fence_material = _rail_material.duplicate()

func _sync_footstep_surface() -> void:
	if not _body:
		return

	_footstep_surface = _body.get_node_or_null("FootstepSurface")
	if not _footstep_surface:
		_footstep_surface = Spatial.new()
		_footstep_surface.name = "FootstepSurface"
		_footstep_surface.set_script(FOOTSTEP_SURFACE_SCRIPT)
		_body.add_child(_footstep_surface)

	_footstep_surface.set("footstep_profile", footstep_profile)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _clear_body_collisions() -> void:
	for child in _body.get_children():
		if child is CollisionShape:
			child.queue_free()

func _build_side_rail(side_name: String, enabled: bool, is_front_back: bool, fixed_axis: float, opening_width: float, opening_gravity: float) -> void:
	if not enabled or rail_height <= 0.01:
		return
	# Side rails must use the same mitered endpoints as the deck/frame, even
	# when an authored opening splits them into two segments.
	if not is_front_back:
		_build_mitered_side_rail(side_name, fixed_axis, opening_width, opening_gravity)
		return

	var half_depth = _deck_half_depth_at_x(fixed_axis)
	var min_axis = - platform_width * 0.5 if is_front_back else -half_depth
	var max_axis = platform_width * 0.5 if is_front_back else half_depth
	var start_margin = tube_radius
	var end_margin = tube_radius
	var span_start = min_axis + start_margin
	var span_end = max_axis - end_margin
	var full_span = span_end - span_start
	if full_span <= tube_radius:
		return

	var clamped_width = clamp(opening_width, 0.0, max(full_span - tube_radius * 2.0, 0.0))
	if clamped_width <= 0.01:
		_build_side_segment(side_name, is_front_back, fixed_axis, span_start, span_end)
		return

	var gravity = clamp(opening_gravity, 0.0, 1.0)
	var opening_center = lerp(span_start + clamped_width * 0.5, span_end - clamped_width * 0.5, gravity)
	var opening_start = opening_center - clamped_width * 0.5
	var opening_end = opening_center + clamped_width * 0.5

	_build_side_segment(side_name + "A", is_front_back, fixed_axis, span_start, opening_start)
	_build_side_segment(side_name + "B", is_front_back, fixed_axis, opening_end, span_end)

	if is_front_back:
		var gate_left_y := _deck_top_y_at(opening_start, fixed_axis)
		var gate_right_y := _deck_top_y_at(opening_end, fixed_axis)
		_add_tube_between("%sGatePostL" % side_name, Vector3(opening_start, gate_left_y, fixed_axis), Vector3(opening_start, gate_left_y + rail_height, fixed_axis), _rail_material)
		_add_tube_between("%sGatePostR" % side_name, Vector3(opening_end, gate_right_y, fixed_axis), Vector3(opening_end, gate_right_y + rail_height, fixed_axis), _rail_material)
	else:
		var gate_front_y := _deck_top_y_at(fixed_axis, opening_start)
		var gate_back_y := _deck_top_y_at(fixed_axis, opening_end)
		_add_tube_between("%sGatePostF" % side_name, Vector3(fixed_axis, gate_front_y, opening_start), Vector3(fixed_axis, gate_front_y + rail_height, opening_start), _rail_material)
		_add_tube_between("%sGatePostB" % side_name, Vector3(fixed_axis, gate_back_y, opening_end), Vector3(fixed_axis, gate_back_y + rail_height, opening_end), _rail_material)

func _build_side_segment(side_name: String, is_front_back: bool, fixed_axis: float, axis_start: float, axis_end: float) -> void:
	if axis_end - axis_start <= tube_radius:
		return

	var bottom_a: Vector3
	var bottom_b: Vector3
	if is_front_back:
		bottom_a = Vector3(axis_start, _deck_top_y_at(axis_start, fixed_axis), fixed_axis)
		bottom_b = Vector3(axis_end, _deck_top_y_at(axis_end, fixed_axis), fixed_axis)
	else:
		bottom_a = Vector3(fixed_axis, _deck_top_y_at(fixed_axis, axis_start), axis_start)
		bottom_b = Vector3(fixed_axis, _deck_top_y_at(fixed_axis, axis_end), axis_end)

	var top_a = bottom_a + Vector3.UP * rail_height
	var top_b = bottom_b + Vector3.UP * rail_height
	var mid_a = bottom_a + Vector3.UP * (rail_height * clamp(rail_mid_ratio, 0.0, 1.0))
	var mid_b = bottom_b + Vector3.UP * (rail_height * clamp(rail_mid_ratio, 0.0, 1.0))

	_add_tube_between("%sRailTop" % side_name, top_a, top_b, _rail_material)
	_add_tube_between("%sRailMid" % side_name, mid_a, mid_b, _rail_material)
	_add_tube_between("%sRailPostA" % side_name, bottom_a, top_a, _rail_material)
	_add_tube_between("%sRailPostB" % side_name, bottom_b, top_b, _rail_material)
	_add_intermediate_rail_posts(side_name, bottom_a, bottom_b)
	_add_joint_cap("%sCapTopA" % side_name, top_a, _rail_material)
	_add_joint_cap("%sCapTopB" % side_name, top_b, _rail_material)
	_add_joint_cap("%sCapMidA" % side_name, mid_a, _rail_material)
	_add_joint_cap("%sCapMidB" % side_name, mid_b, _rail_material)

	if rail_infill_enabled:
		var center = (bottom_a + bottom_b) * 0.5 + Vector3.UP * (rail_height * 0.5)
		var span = bottom_b.distance_to(bottom_a)
		if is_front_back:
			_add_vertical_panel("%sRailMesh" % side_name, Vector2(span, rail_height), center, Vector3(-90, 0, 0))
		else:
			_add_vertical_panel("%sRailMesh" % side_name, Vector2(span, rail_height), center, Vector3(-90, 90, 0))

	_add_rail_collision("%sRailCollision" % side_name, bottom_a, bottom_b, top_a, top_b)

func _build_mitered_side_rail(side_name: String, x: float, opening_width: float, opening_gravity: float) -> void:
	var join_inset: float = 0.0 if snap_mitered_joins else tube_radius
	var bottom_a = _deck_point(x, -1.0, join_inset)
	var bottom_b = _deck_point(x, 1.0, join_inset)
	var span: float = bottom_a.distance_to(bottom_b)
	var opening: float = clamp(opening_width, 0.0, max(span - tube_radius * 2.0, 0.0))
	if opening <= 0.01:
		_build_mitered_side_segment(side_name, bottom_a, bottom_b)
		return
	var opening_center: float = lerp(opening * 0.5, span - opening * 0.5, clamp(opening_gravity, 0.0, 1.0))
	var dir: Vector3 = (bottom_b - bottom_a).normalized()
	_build_mitered_side_segment(side_name + "A", bottom_a, bottom_a + dir * (opening_center - opening * 0.5))
	_build_mitered_side_segment(side_name + "B", bottom_a + dir * (opening_center + opening * 0.5), bottom_b)

func _build_mitered_side_segment(side_name: String, bottom_a: Vector3, bottom_b: Vector3) -> void:
	var top_a = bottom_a + Vector3.UP * rail_height
	var top_b = bottom_b + Vector3.UP * rail_height
	var mid_a = bottom_a + Vector3.UP * (rail_height * clamp(rail_mid_ratio, 0.0, 1.0))
	var mid_b = bottom_b + Vector3.UP * (rail_height * clamp(rail_mid_ratio, 0.0, 1.0))
	_add_tube_between("%sRailTop" % side_name, top_a, top_b, _rail_material)
	_add_tube_between("%sRailMid" % side_name, mid_a, mid_b, _rail_material)
	_add_tube_between("%sRailPostA" % side_name, bottom_a, top_a, _rail_material)
	_add_tube_between("%sRailPostB" % side_name, bottom_b, top_b, _rail_material)
	_add_intermediate_rail_posts(side_name, bottom_a, bottom_b)
	_add_joint_cap("%sCapTopA" % side_name, top_a, _rail_material)
	_add_joint_cap("%sCapTopB" % side_name, top_b, _rail_material)
	_add_joint_cap("%sCapMidA" % side_name, mid_a, _rail_material)
	_add_joint_cap("%sCapMidB" % side_name, mid_b, _rail_material)
	if rail_infill_enabled:
		var center = (bottom_a + bottom_b) * 0.5 + Vector3.UP * (rail_height * 0.5)
		_add_vertical_panel("%sRailMesh" % side_name, Vector2(bottom_b.distance_to(bottom_a), rail_height), center, Vector3(-90, 90, 0))
	_add_rail_collision("%sRailCollision" % side_name, bottom_a, bottom_b, top_a, top_b)

func _add_rail_collision(node_name: String, bottom_a: Vector3, bottom_b: Vector3, top_a: Vector3, top_b: Vector3) -> void:
	# A BoxShape stays axis-aligned and misses the upper end of a sloped rail.
	# Extrude the actual inclined rail panel instead, so visuals and collision agree.
	var side_normal: Vector3 = (bottom_b - bottom_a).cross(Vector3.UP).normalized()
	if side_normal.length_squared() <= 0.001:
		return
	var half_thickness: Vector3 = side_normal * tube_radius * 1.15
	var shape := ConvexPolygonShape.new()
	shape.points = PoolVector3Array([
		bottom_a - half_thickness, bottom_b - half_thickness, top_a - half_thickness, top_b - half_thickness,
		bottom_a + half_thickness, bottom_b + half_thickness, top_a + half_thickness, top_b + half_thickness
	])
	_add_collision_shape(node_name, shape, Vector3.ZERO, Basis())

func _add_deck_collision(half_w: float, deck_t: float) -> void:
	var front_left := _deck_point(-half_w, -1.0)
	var front_right := _deck_point(half_w, -1.0)
	var back_left := _deck_point(-half_w, 1.0)
	var back_right := _deck_point(half_w, 1.0)
	var shape = ConvexPolygonShape.new()
	shape.points = PoolVector3Array([
		front_left, front_right, back_left, back_right,
		front_left - Vector3.UP * deck_t, front_right - Vector3.UP * deck_t,
		back_left - Vector3.UP * deck_t, back_right - Vector3.UP * deck_t
	])
	_add_collision_shape("DeckCollision", shape, Vector3.ZERO, Basis())

func _add_leg_collision(node_name: String, bottom: Vector3, top: Vector3) -> void:
	var shape = CylinderShape.new()
	shape.radius = tube_radius * 1.15
	shape.height = bottom.distance_to(top)
	_add_collision_shape(node_name, shape, (bottom + top) * 0.5, _basis_from_y_axis((top - bottom).normalized()))

func _add_grate_deck() -> void:
	var deck = MeshInstance.new()
	deck.name = "DeckGrate"
	deck.layers = PROP_VISUAL_LAYER
	var mesh_size = Vector2(
		max(platform_width - tube_radius * 2.0, tube_radius * 2.0) + tube_radius * GRATE_OVERLAP_WITH_FRAME,
		max(platform_depth - tube_radius * 2.0, tube_radius * 2.0) + tube_radius * GRATE_OVERLAP_WITH_FRAME
	)
	var mesh = _make_grate_mesh()
	deck.mesh = mesh
	if _grate_material is SpatialMaterial:
		var mat = (_grate_material as SpatialMaterial).duplicate(true)
		mat.uv1_scale = Vector3(max(mesh_size.x * GRATE_REPEAT_PER_METER, 1.0), max(mesh_size.y * GRATE_REPEAT_PER_METER, 1.0), 1.0)
		deck.material_override = mat
	else:
		deck.material_override = _grate_material
	_visual_root.add_child(deck)

func _make_grate_mesh() -> ArrayMesh:
	var half_w = max(platform_width * 0.5 - tube_radius, tube_radius)
	var vertices = PoolVector3Array([
		_deck_point(-half_w, -1.0, tube_radius, GRATE_RECESS),
		_deck_point(half_w, -1.0, tube_radius, GRATE_RECESS),
		_deck_point(half_w, 1.0, tube_radius, GRATE_RECESS),
		_deck_point(-half_w, 1.0, tube_radius, GRATE_RECESS)
	])
	var normal: Vector3 = (vertices[1] - vertices[0]).cross(vertices[3] - vertices[0]).normalized()
	var normals = PoolVector3Array([
		normal, normal, normal, normal
	])
	var uvs = PoolVector2Array([
		_transform_grate_uv(Vector2(0, 0)),
		_transform_grate_uv(Vector2(1, 0)),
		_transform_grate_uv(Vector2(1, 1)),
		_transform_grate_uv(Vector2(0, 1))
	])
	var indices = PoolIntArray([0, 1, 2, 0, 2, 3])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _transform_grate_uv(uv: Vector2) -> Vector2:
	var centered = uv - Vector2(0.5, 0.5)
	centered.x += centered.y * grate_pattern_shear
	var angle = deg2rad(grate_pattern_angle_degrees)
	var c = cos(angle)
	var s = sin(angle)
	return Vector2(
		centered.x * c - centered.y * s,
		centered.x * s + centered.y * c
	) + Vector2(0.5, 0.5)

func _add_intermediate_leg_supports(front_left_top: Vector3, front_right_top: Vector3, back_left_top: Vector3, back_right_top: Vector3) -> void:
	var x_positions = _intermediate_positions(-platform_width * 0.5 + tube_radius, platform_width * 0.5 - tube_radius)
	for x in x_positions:
		var front_top := _deck_point(x, -1.0, tube_radius)
		var back_top := _deck_point(x, 1.0, tube_radius)
		front_top.y -= tube_radius
		back_top.y -= tube_radius
		_add_tube_between("LegFront_%s" % str(x), Vector3(x, support_base_local_y, front_top.z), front_top, _frame_material)
		_add_tube_between("LegBack_%s" % str(x), Vector3(x, support_base_local_y, back_top.z), back_top, _frame_material)
		_add_leg_collision("LegFrontCollision_%s" % str(x), Vector3(x, support_base_local_y, front_top.z), front_top)
		_add_leg_collision("LegBackCollision_%s" % str(x), Vector3(x, support_base_local_y, back_top.z), back_top)

	var z_positions = _intermediate_positions(-platform_depth * 0.5 + tube_radius, platform_depth * 0.5 - tube_radius)
	for z in z_positions:
		var left_top = Vector3(front_left_top.x, _deck_top_y_at(front_left_top.x, z) - tube_radius, z)
		var right_top = Vector3(front_right_top.x, _deck_top_y_at(front_right_top.x, z) - tube_radius, z)
		_add_tube_between("LegLeft_%s" % str(z), Vector3(front_left_top.x, support_base_local_y, z), left_top, _frame_material)
		_add_tube_between("LegRight_%s" % str(z), Vector3(front_right_top.x, support_base_local_y, z), right_top, _frame_material)
		_add_leg_collision("LegLeftCollision_%s" % str(z), Vector3(front_left_top.x, support_base_local_y, z), left_top)
		_add_leg_collision("LegRightCollision_%s" % str(z), Vector3(front_right_top.x, support_base_local_y, z), right_top)

func _add_intermediate_rail_posts(side_name: String, bottom_a: Vector3, bottom_b: Vector3) -> void:
	var distance = bottom_a.distance_to(bottom_b)
	if distance <= support_spacing * 1.1:
		return
	var dir = (bottom_b - bottom_a).normalized()
	var count = int(floor(distance / support_spacing))
	for i in range(1, count):
		var p = bottom_a + dir * (distance * float(i) / float(count))
		_add_tube_between("%sRailPostMid_%d" % [side_name, i], p, p + Vector3.UP * rail_height, _rail_material)

func _intermediate_positions(start_axis: float, end_axis: float) -> Array:
	var positions := []
	var span = end_axis - start_axis
	if span <= support_spacing * 1.1:
		return positions
	var count = int(floor(span / support_spacing))
	for i in range(1, count):
		positions.append(lerp(start_axis, end_axis, float(i) / float(count)))
	return positions

func _add_vertical_panel(node_name: String, size: Vector2, pos: Vector3, rot_deg: Vector3) -> void:
	var panel = MeshInstance.new()
	panel.name = node_name
	panel.layers = PROP_VISUAL_LAYER
	var mesh = QuadMesh.new()
	mesh.size = size
	panel.mesh = mesh
	panel.translation = pos
	panel.rotation_degrees = rot_deg
	panel.material_override = _fence_material
	_visual_root.add_child(panel)

func _get_cylinder_mesh(length: float) -> CylinderMesh:
	var key = stepify(length, 0.001)
	if _cylinder_mesh_cache.has(key):
		return _cylinder_mesh_cache[key]
	var mesh = CylinderMesh.new()
	mesh.top_radius = tube_radius
	mesh.bottom_radius = tube_radius
	mesh.height = key
	mesh.radial_segments = CYLINDER_SEGMENTS
	_cylinder_mesh_cache[key] = mesh
	return mesh

func _get_sphere_mesh() -> SphereMesh:
	if _sphere_mesh_cache.has(tube_radius):
		return _sphere_mesh_cache[tube_radius]
	var mesh = SphereMesh.new()
	mesh.radius = tube_radius * JOINT_SCALE
	mesh.height = tube_radius * JOINT_SCALE * 2.0
	mesh.radial_segments = CYLINDER_SEGMENTS
	mesh.rings = 6
	_sphere_mesh_cache[tube_radius] = mesh
	return mesh

func _add_tube_between(node_name: String, start: Vector3, end: Vector3, material: Material) -> void:
	var dir = end - start
	var length = dir.length()
	if length <= 0.001:
		return

	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.layers = PROP_VISUAL_LAYER
	mesh_instance.mesh = _get_cylinder_mesh(length)
	mesh_instance.transform = Transform(_basis_from_y_axis(dir.normalized()), (start + end) * 0.5)
	mesh_instance.material_override = material
	_visual_root.add_child(mesh_instance)

func _add_joint_cap(node_name: String, pos: Vector3, material: Material) -> void:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.layers = PROP_VISUAL_LAYER
	mesh_instance.mesh = _get_sphere_mesh()
	mesh_instance.translation = pos
	mesh_instance.material_override = material
	_visual_root.add_child(mesh_instance)

func _basis_from_y_axis(y_axis: Vector3) -> Basis:
	var up = y_axis.normalized()
	var tangent = Vector3.FORWARD if abs(up.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_axis = tangent.cross(up).normalized()
	var z_axis = x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)

func _deck_top_y_at(x: float, z: float) -> float:
	var front_z = _deck_z_at_x(x, -1.0)
	var back_z = _deck_z_at_x(x, 1.0)
	var z_t: float = clamp((z - front_z) / max(back_z - front_z, 0.001), 0.0, 1.0)
	var x_t: float = clamp((x + platform_width * 0.5) / max(platform_width, 0.001), 0.0, 1.0)
	return platform_height + lerp(front_height_offset, back_height_offset, z_t) + lerp(left_height_offset, right_height_offset, x_t)

func _deck_half_depth_at_x(x: float) -> float:
	var x_t: float = clamp((x + platform_width * 0.5) / max(platform_width, 0.001), 0.0, 1.0)
	return max(tube_radius * 2.0, platform_depth * 0.5 + lerp(left_depth_offset, right_depth_offset, x_t))

func _deck_z_at_x(x: float, z_sign: float, inset: float = 0.0) -> float:
	var half_depth = _deck_half_depth_at_x(x)
	var x_t: float = clamp((x + platform_width * 0.5) / max(platform_width, 0.001), 0.0, 1.0)
	var corner_offset = lerp(front_left_depth_offset, front_right_depth_offset, x_t) if z_sign < 0.0 else lerp(back_left_depth_offset, back_right_depth_offset, x_t)
	return z_sign * max(half_depth - inset, 0.01) + corner_offset

func _deck_width_offset_at_x(x: float, z_sign: float) -> float:
	var x_t: float = clamp((x + platform_width * 0.5) / max(platform_width, 0.001), 0.0, 1.0)
	return lerp(front_left_width_offset, front_right_width_offset, x_t) if z_sign < 0.0 else lerp(back_left_width_offset, back_right_width_offset, x_t)

func _deck_point(x: float, z_sign: float, inset: float = 0.0, recess: float = 0.0) -> Vector3:
	var z = _deck_z_at_x(x, z_sign, inset)
	return Vector3(x + _deck_width_offset_at_x(x, z_sign), _deck_top_y_at(x, z) - recess, z)

func _add_collision_shape(node_name: String, shape: Shape, pos: Vector3, basis: Basis) -> void:
	var collision = CollisionShape.new()
	collision.name = node_name
	collision.shape = shape
	collision.transform = Transform(basis, pos)
	_body.add_child(collision)
