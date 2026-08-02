tool
extends Spatial
class_name ScaffoldHubRing

# One floor of a scaffold ring: N trapezoidal SteelGratePlatform decks laid out
# as a regular polygon with a hollow centre. sides == 4 degenerates into a square
# frame (the "rectangle with a hole" case); sides >= 6 reads as a round gallery.
#
# Each segment spans one polygon sector. Its deck corners are pushed onto the
# exact inner/outer polygon vertices through the per-corner width/depth offsets
# on SteelGratePlatform, the same trick RadialScatter._apply_join_line() uses for
# spiral chords — so neighbouring segments meet without a seam.

const SEGMENT_SCENE := preload("res://core_v2/props/scaffold/SteelGratePlatform.tscn")

export(int, 3, 32) var sides := 8 setget set_sides
export(float, 0.5, 60.0, 0.1) var outer_radius := 7.0 setget set_outer_radius
export(float, 0.0, 60.0, 0.1) var inner_radius := 3.0 setget set_inner_radius
export(float, 0.2, 100.0, 0.1) var platform_height := 0.2 setget set_platform_height
export(float, -200.0, 200.0, 0.1) var support_base_local_y := 0.0 setget set_support_base_local_y

export(bool) var rail_outer := true setget set_rail_outer
export(bool) var rail_inner := true setget set_rail_inner

# Angular ranges (degrees, local to this node) where the outer rail opens up so a
# walkway can dock. Same semantics as RadialScatter.blocked_angle_ranges_deg.
export(Array, Vector2) var outer_openings_deg := [] setget set_outer_openings_deg
export(Array, Vector2) var inner_openings_deg := [] setget set_inner_openings_deg
# Width of the gap punched into a rail whose segment falls inside an opening.
# 0 removes that segment's rail entirely instead of splitting it.
export(float, 0.0, 100.0, 0.1) var opening_width := 2.0 setget set_opening_width

export(float, 0.04, 2.0, 0.01) var tube_radius := 0.07 setget set_tube_radius
export(float, 0.04, 2.0, 0.01) var deck_frame_thickness := 0.10 setget set_deck_frame_thickness
export(float, 0.0, 20.0, 0.05) var rail_height := 1.1 setget set_rail_height
export(Color) var frame_color := Color(0.18, 0.19, 0.21, 1.0) setget set_frame_color
export(Color) var rail_color := Color(0.18, 0.19, 0.21, 1.0) setget set_rail_color
export(Color) var grate_color := Color(0.42, 0.46, 0.50, 1.0) setget set_grate_color
export(float, 0.15, 2.0, 0.01) var grate_brightness := 0.72 setget set_grate_brightness
export(float, -45.0, 45.0, 0.5) var grate_pattern_angle_degrees := 0.0 setget set_grate_pattern_angle_degrees

export(bool) var auto_build := true setget set_auto_build
export(bool) var collapse_to_single_mesh := true
# Regenerates scene-baked children at runtime. Keep disabled for baked rings;
# enable temporarily after changing generator parameters.
export(bool) var rebuild_baked_items := false

var _build_queued := false

func _ready() -> void:
	if Engine.editor_hint:
		_queue_build()
		return
	if get_child_count() != 0 and not rebuild_baked_items:
		return  # segments already baked into the scene
	build()

func set_sides(value: int) -> void:
	sides = clamp(value, 3, 32)
	_queue_build()

func set_outer_radius(value: float) -> void:
	outer_radius = max(value, 0.5)
	_queue_build()

func set_inner_radius(value: float) -> void:
	inner_radius = max(value, 0.0)
	_queue_build()

func set_platform_height(value: float) -> void:
	platform_height = max(value, 0.2)
	_queue_build()

func set_support_base_local_y(value: float) -> void:
	support_base_local_y = value
	_queue_build()

func set_rail_outer(value: bool) -> void:
	rail_outer = value
	_queue_build()

func set_rail_inner(value: bool) -> void:
	rail_inner = value
	_queue_build()

func set_outer_openings_deg(value: Array) -> void:
	outer_openings_deg = value
	_queue_build()

func set_inner_openings_deg(value: Array) -> void:
	inner_openings_deg = value
	_queue_build()

func set_opening_width(value: float) -> void:
	opening_width = max(value, 0.0)
	_queue_build()

func set_tube_radius(value: float) -> void:
	tube_radius = value
	_queue_build()

func set_deck_frame_thickness(value: float) -> void:
	deck_frame_thickness = value
	_queue_build()

func set_rail_height(value: float) -> void:
	rail_height = value
	_queue_build()

func set_frame_color(value: Color) -> void:
	frame_color = value
	_queue_build()

func set_rail_color(value: Color) -> void:
	rail_color = value
	_queue_build()

func set_grate_color(value: Color) -> void:
	grate_color = value
	_queue_build()

func set_grate_brightness(value: float) -> void:
	grate_brightness = value
	_queue_build()

func set_grate_pattern_angle_degrees(value: float) -> void:
	grate_pattern_angle_degrees = value
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
	if outer_radius <= inner_radius + 0.05:
		push_warning("ScaffoldHubRing: outer_radius must exceed inner_radius.")
		return
	_build_compact_ring()

func _build_compact_ring() -> void:
	var deck_tool := SurfaceTool.new()
	deck_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var frame_tool := SurfaceTool.new()
	frame_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sector: float = TAU / float(sides)
	var corner_scale: float = 1.0 / cos(sector * 0.5)
	var outer_corner: float = outer_radius * corner_scale
	var inner_corner: float = inner_radius * corner_scale
	var deck_top: float = platform_height
	var deck_bottom: float = max(0.0, platform_height - deck_frame_thickness)

	for index in range(sides):
		var a0: float = sector * float(index)
		var a1: float = sector * float(index + 1)
		var inner_a := Vector3(cos(a0) * inner_corner, deck_top, sin(a0) * inner_corner)
		var inner_b := Vector3(cos(a1) * inner_corner, deck_top, sin(a1) * inner_corner)
		var outer_a := Vector3(cos(a0) * outer_corner, deck_top, sin(a0) * outer_corner)
		var outer_b := Vector3(cos(a1) * outer_corner, deck_top, sin(a1) * outer_corner)
		_add_prism(deck_tool, inner_a, inner_b, outer_b, outer_a, deck_top - deck_bottom)

		var mid_angle: float = (a0 + a1) * 0.5
		if rail_inner:
			_add_rail_edge(frame_tool, inner_a, inner_b, _sector_opening(mid_angle, sector, inner_openings_deg))
		if rail_outer:
			_add_rail_edge(frame_tool, outer_a, outer_b, _sector_opening(mid_angle, sector, outer_openings_deg))
		_add_beam(frame_tool, Vector3(outer_a.x, support_base_local_y, outer_a.z), outer_a, tube_radius * 2.0)

	deck_tool.generate_normals()
	frame_tool.generate_normals()
	var mesh := ArrayMesh.new()
	deck_tool.set_material(_compact_material(grate_color, grate_brightness))
	deck_tool.commit(mesh)
	frame_tool.set_material(_compact_material(frame_color, 1.0))
	frame_tool.commit(mesh)

	var visual := MeshInstance.new()
	visual.name = "CombinedMesh"
	visual.layers = 64
	visual.mesh = mesh
	add_child(visual)
	var body := StaticBody.new()
	body.name = "StaticBody"
	body.collision_layer = 64
	body.collision_mask = 255
	add_child(body)
	var collision := CollisionShape.new()
	collision.name = "CombinedCollision"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	var scene_owner := _get_scene_owner()
	if scene_owner:
		visual.owner = scene_owner
		body.owner = scene_owner
		collision.owner = scene_owner

func _add_prism(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, thickness: float) -> void:
	var down := Vector3.DOWN * thickness
	_add_quad(surface_tool, a, d, c, b)
	_add_quad(surface_tool, a + down, b + down, c + down, d + down)
	_add_quad(surface_tool, a, b, b + down, a + down)
	_add_quad(surface_tool, b, c, c + down, b + down)
	_add_quad(surface_tool, c, d, d + down, c + down)
	_add_quad(surface_tool, d, a, a + down, d + down)

func _add_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		surface_tool.add_vertex(point)

func _add_rail_edge(surface_tool: SurfaceTool, start: Vector3, end: Vector3, opening: Vector2) -> void:
	var spans := [Vector2(0.0, 1.0)]
	if opening.x > 0.5 and opening_width > 0.01:
		var edge_length: float = start.distance_to(end)
		var half_gap: float = min(opening_width / max(edge_length, 0.001) * 0.5, 0.49)
		spans = [Vector2(0.0, max(0.0, opening.y - half_gap)), Vector2(min(1.0, opening.y + half_gap), 1.0)]
	elif opening.x > 0.5:
		return
	for span in spans:
		if span.y - span.x <= 0.01:
			continue
		var a: Vector3 = start.linear_interpolate(end, span.x)
		var b: Vector3 = start.linear_interpolate(end, span.y)
		for height_ratio in [0.0, 0.5, 1.0]:
			_add_beam(surface_tool, a + Vector3.UP * rail_height * height_ratio, b + Vector3.UP * rail_height * height_ratio, tube_radius * 2.0)
		_add_beam(surface_tool, a, a + Vector3.UP * rail_height, tube_radius * 2.0)
		_add_beam(surface_tool, b, b + Vector3.UP * rail_height, tube_radius * 2.0)

func _add_beam(surface_tool: SurfaceTool, start: Vector3, end: Vector3, width: float) -> void:
	var direction: Vector3 = end - start
	if direction.length_squared() <= 0.0001:
		return
	var y_axis: Vector3 = direction.normalized()
	var helper: Vector3 = Vector3.FORWARD if abs(y_axis.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_axis: Vector3 = helper.cross(y_axis).normalized() * width * 0.5
	var z_axis: Vector3 = x_axis.normalized().cross(y_axis).normalized() * width * 0.5
	var p0: Vector3 = start - x_axis - z_axis
	var p1: Vector3 = start + x_axis - z_axis
	var p2: Vector3 = start + x_axis + z_axis
	var p3: Vector3 = start - x_axis + z_axis
	var delta: Vector3 = direction
	_add_prism_between(surface_tool, p0, p1, p2, p3, delta)

func _add_prism_between(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, delta: Vector3) -> void:
	_add_quad(surface_tool, a, b, c, d)
	_add_quad(surface_tool, a + delta, d + delta, c + delta, b + delta)
	_add_quad(surface_tool, a, a + delta, b + delta, b)
	_add_quad(surface_tool, b, b + delta, c + delta, c)
	_add_quad(surface_tool, c, c + delta, d + delta, d)
	_add_quad(surface_tool, d, d + delta, a + delta, a)

func _compact_material(color: Color, brightness: float) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.albedo_color = Color(color.r * brightness, color.g * brightness, color.b * brightness, color.a)
	material.roughness = 0.72
	material.metallic = 0.65
	return material

# SteelGratePlatform is convenient authoring geometry but each instance expands
# into dozens of MeshInstances. Batch identical pieces while retaining the
# authored collision shapes (which are already cheap and gameplay-accurate).
func _collapse_segments() -> void:
	var groups := {}
	var ring_inverse: Transform = global_transform.affine_inverse()
	for segment in get_children():
		for mesh_instance in _mesh_descendants(segment):
			var mesh: Mesh = mesh_instance.mesh
			if not mesh:
				continue
			var category: String = _mesh_category(mesh_instance.name)
			var size: Vector3 = mesh.get_aabb().size
			var key: String = "%s|%.3f|%.3f|%.3f" % [category, size.x, size.y, size.z]
			if not groups.has(key):
				groups[key] = {
					"mesh": mesh,
					"material": mesh_instance.material_override,
					"transforms": []
				}
			groups[key]["transforms"].append(ring_inverse * mesh_instance.global_transform)

	var batch_root := Spatial.new()
	batch_root.name = "BatchedMeshes"
	add_child(batch_root)
	var scene_owner := _get_scene_owner()
	if scene_owner:
		batch_root.owner = scene_owner
	for key in groups:
		var data: Dictionary = groups[key]
		var transforms: Array = data["transforms"]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = data["mesh"]
		multimesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multimesh.set_instance_transform(index, transforms[index])
		var instance := MultiMeshInstance.new()
		instance.name = "Batch_%d" % batch_root.get_child_count()
		instance.layers = 64
		instance.multimesh = multimesh
		instance.material_override = data["material"]
		batch_root.add_child(instance)
		if scene_owner:
			instance.owner = scene_owner

	# Collision and footstep metadata stay in each segment; only their expanded
	# visual trees are removed after the MultiMeshes own the required resources.
	for segment in get_children():
		if segment == batch_root:
			continue
		var visual_root: Node = segment.get_node_or_null("VisualRoot")
		if visual_root:
			segment.remove_child(visual_root)
			visual_root.free()

func _mesh_descendants(root: Node) -> Array:
	var result := []
	var pending := [root]
	while not pending.empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance:
			result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result

func _mesh_category(node_name: String) -> String:
	if node_name == "DeckGrate":
		return "grate"
	if "Rail" in node_name or "Infill" in node_name:
		return "rail"
	return "frame"

func _add_segment(index: int, mid_angle: float, sector: float, outer_corner: float, inner_corner: float, scene_owner: Node) -> void:
	var instance := SEGMENT_SCENE.instance()
	if not (instance is Spatial):
		push_warning("ScaffoldHubRing: segment scene root must extend Spatial.")
		if instance:
			instance.free()
		return
	var seg := instance as Spatial

	# Polygon vertices bounding this sector, in ring-local space.
	var a0: float = mid_angle - sector * 0.5
	var a1: float = mid_angle + sector * 0.5
	var outer_a := Vector3(cos(a0), 0.0, sin(a0)) * outer_corner
	var outer_b := Vector3(cos(a1), 0.0, sin(a1)) * outer_corner
	var inner_a := Vector3(cos(a0), 0.0, sin(a0)) * inner_corner
	var inner_b := Vector3(cos(a1), 0.0, sin(a1)) * inner_corner

	var outer_chord: float = outer_a.distance_to(outer_b)
	var inner_chord: float = inner_a.distance_to(inner_b)
	var depth: float = outer_radius - inner_radius

	seg.name = "Segment_%d" % index
	seg.set("platform_width", max(outer_chord, inner_chord))
	seg.set("platform_depth", depth)
	seg.set("platform_height", platform_height)
	seg.set("support_base_local_y", support_base_local_y)
	seg.set("tube_radius", tube_radius)
	seg.set("deck_frame_thickness", deck_frame_thickness)
	seg.set("rail_height", rail_height)
	seg.set("frame_color", frame_color)
	seg.set("rail_color", rail_color)
	seg.set("grate_color", grate_color)
	seg.set("grate_brightness", grate_brightness)
	seg.set("grate_pattern_angle_degrees", grate_pattern_angle_degrees)
	seg.set("snap_mitered_joins", true)

	add_child(seg)
	if scene_owner:
		seg.owner = scene_owner

	# Face the ring centre: local -Z ("front") points inward, +Z ("back") outward.
	var centre: Vector3 = (outer_a + outer_b + inner_a + inner_b) * 0.25
	var seg_xform := seg.transform
	seg_xform.origin = centre
	seg.transform = seg_xform
	seg.look_at(to_global(Vector3(0.0, centre.y, 0.0)), Vector3.UP)

	_snap_corners(seg, outer_a, outer_b, inner_a, inner_b)
	_apply_rails(seg, mid_angle, sector)

# Pushes the four deck corners onto the exact polygon vertices. The deck's own
# _deck_point() already accounts for platform_width/depth, so we only write the
# delta between where a corner lands by default and where the polygon wants it.
func _snap_corners(seg: Spatial, outer_a: Vector3, outer_b: Vector3, inner_a: Vector3, inner_b: Vector3) -> void:
	var half_w: float = float(seg.get("platform_width")) * 0.5
	var depth: float = float(seg.get("platform_depth"))
	var inv: Transform = seg.global_transform.affine_inverse()

	# front == -Z == inner edge; back == +Z == outer edge.
	# left == -X, right == +X in the segment's local frame.
	for corner in [
		{ "point": inner_a, "x": -half_w, "z_sign": -1.0, "depth_prop": "front_left_depth_offset", "width_prop": "front_left_width_offset" },
		{ "point": inner_b, "x": half_w, "z_sign": -1.0, "depth_prop": "front_right_depth_offset", "width_prop": "front_right_width_offset" },
		{ "point": outer_a, "x": -half_w, "z_sign": 1.0, "depth_prop": "back_left_depth_offset", "width_prop": "back_left_width_offset" },
		{ "point": outer_b, "x": half_w, "z_sign": 1.0, "depth_prop": "back_right_depth_offset", "width_prop": "back_right_width_offset" },
	]:
		var target_local: Vector3 = inv.xform(to_global(corner["point"]))
		var base_z: float = float(corner["z_sign"]) * depth * 0.5
		seg.set(corner["depth_prop"], target_local.z - base_z)
		seg.set(corner["width_prop"], target_local.x - float(corner["x"]))

func _apply_rails(seg: Spatial, mid_angle: float, sector: float) -> void:
	# Front/back are the inner/outer faces; left/right are the shared joins with
	# the neighbouring segments and never get a rail.
	seg.set("rail_left", false)
	seg.set("rail_right", false)

	# An opening is claimed by whichever segment's sector *contains* it, not by a
	# segment whose midpoint happens to fall inside the range — a 2 m doorway is
	# far narrower than a sector, so testing the midpoint would silently drop it.
	var outer_hit: Vector2 = _sector_opening(mid_angle, sector, outer_openings_deg)
	var inner_hit: Vector2 = _sector_opening(mid_angle, sector, inner_openings_deg)
	var outer_open: bool = outer_hit.x > 0.5
	var inner_open: bool = inner_hit.x > 0.5

	# opening_width <= 0 means "drop the rail on this segment entirely".
	seg.set("rail_back", rail_outer and (not outer_open or opening_width > 0.01))
	seg.set("rail_front", rail_inner and (not inner_open or opening_width > 0.01))
	seg.set("rail_back_opening_width", opening_width if outer_open else 0.0)
	seg.set("rail_front_opening_width", opening_width if inner_open else 0.0)
	# Gravity places the gap along the rail so it lands on the requested angle
	# instead of always at the segment's midpoint.
	seg.set("rail_back_opening_gravity", outer_hit.y if outer_open else 0.5)
	seg.set("rail_front_opening_gravity", inner_hit.y if inner_open else 0.5)

# Returns (hit, gravity): whether any range overlaps this segment's sector, and
# where along the rail (0..1) the opening centre falls. Ranges wrap around 360,
# mirroring RadialScatter._is_angle_blocked().
func _sector_opening(mid_angle: float, sector: float, ranges: Array) -> Vector2:
	var half: float = rad2deg(sector) * 0.5
	var mid_deg: float = rad2deg(mid_angle)
	for range_deg in ranges:
		if not (range_deg is Vector2):
			continue
		# Work in a frame centred on this segment so wraparound is a single
		# shortest-arc reduction rather than a set of interval cases.
		var start_rel: float = _shortest_arc(range_deg.x - mid_deg)
		var end_rel: float = _shortest_arc(range_deg.y - mid_deg)
		if end_rel < start_rel:
			end_rel += 360.0
		var centre_rel: float = _shortest_arc((start_rel + end_rel) * 0.5)
		if centre_rel < -half or centre_rel > half:
			continue
		# The rail is a straight polygon edge, not a circular arc. Project the
		# radial opening onto that chord so pods and rail gaps share one ray.
		var projected: float = tan(deg2rad(centre_rel)) / max(tan(deg2rad(half)), 0.001)
		return Vector2(1.0, clamp((projected + 1.0) * 0.5, 0.0, 1.0))
	return Vector2(0.0, 0.5)

static func _shortest_arc(delta_deg: float) -> float:
	return fposmod(delta_deg + 180.0, 360.0) - 180.0

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
