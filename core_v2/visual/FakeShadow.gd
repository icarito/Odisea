extends MeshInstance

# FakeShadow.gd (Grid Topology)
# Generates a dynamic "blanket" shadow mesh using a grid of raycasts.
# Drapes over obstacles and "tears" at steep cliffs to avoid walls.

export(float) var size: float = 2.0 # Total width/length of the shadow area
export(int) var grid_resolution: int = 8 # NxN rays (e.g. 5x5 = 25 rays)
export(float) var max_distance: float = 6.0
export(float, 0.0, 1.0) var base_opacity: float = 1.0
export(float) var cliff_threshold: float = 0.5 # Max vertical difference before tearing
export(float) var vertical_offset: float = 0.05

var _rays: Array = [] # Linear array of rays
var _mesh_tool: SurfaceTool
var _actor_excluded = false

func _ready() -> void:
	_mesh_tool = SurfaceTool.new()
	
	# Load material manually
	var mat = preload("res://materials/shadow/FakeShadowShader.tres")
	material_override = mat

	# Create Ray Grid
	_create_rays()
	
	cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	set_as_toplevel(true)

func _create_rays() -> void:
	# Clean up existing if any (though usually clean on ready)
	for c in get_children():
		if c is RayCast:
			c.queue_free()
	_rays.clear()

	for z in range(grid_resolution):
		for x in range(grid_resolution):
			var r = RayCast.new()
			r.name = "Ray_%d_%d" % [x, z]
			r.enabled = true
			r.collision_mask = 1
			r.cast_to = Vector3(0, -max_distance, 0)
			add_child(r)
			_rays.append(r)

func _process(_delta: float) -> void:
	var parent = get_parent()
	if not parent: return
	
	var center_pos = parent.global_transform.origin
	global_transform.origin = center_pos
	
	_handle_exclusions()

	# Reset rotation
	global_transform.basis = Basis.IDENTITY

	# Update Ray Positions in a Grid pattern centered on player
	var start_offset = - size / 2.0
	var step = size / (grid_resolution - 1)
	
	var ray_idx = 0
	for z in range(grid_resolution):
		for x in range(grid_resolution):
			var local_x = start_offset + (x * step)
			var local_z = start_offset + (z * step)
			
			var r = _rays[ray_idx]
			r.transform.origin = Vector3(local_x, 0, local_z)
			r.force_raycast_update()
			ray_idx += 1

	_generate_mesh()

func _handle_exclusions() -> void:
	if _actor_excluded: return
	
	var actor = owner
	if not actor and get_parent():
		var p = get_parent()
		while p:
			if p is KinematicBody:
				actor = p
				break
			p = p.get_parent()
	
	if actor:
		for r in _rays:
			r.add_exception(actor)
		_actor_excluded = true

func _generate_mesh() -> void:
	# We need the hits first to decide validity
	# Store hits in a 2D accessible way or just linear indexing
	# Points array will store the geometry point for each ray
	var points = []
	var center_ray_idx = (grid_resolution * grid_resolution) / 2
	var center_hit_y = -99999.0
	
	# First pass: collect points
	for i in range(_rays.size()):
		var r = _rays[i]
		var p = Vector3.ZERO
		if r.is_colliding():
			p = to_local(r.get_collision_point())
		else:
			# Missed? Project valid height or hide?
			# If we miss, we push it far down or keep at relative 0?
			# Let's drop it to -max_distance
			var local_origin = r.transform.origin
			p = Vector3(local_origin.x, -max_distance, local_origin.z)
		
		points.append(p)
		
		# Find rough center height for basic opacity check if needed?
		if i == center_ray_idx and r.is_colliding():
			center_hit_y = p.y

	# If center is wildly invalid, maybe hide?
	# Nah, let partial shadows exist.
	
	_mesh_tool.clear()
	_mesh_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate Quads
	# Iterate grid cells (0..N-2)
	for z in range(grid_resolution - 1):
		for x in range(grid_resolution - 1):
			# Indices
			var i_tl = z * grid_resolution + x
			var i_tr = z * grid_resolution + (x + 1)
			var i_bl = (z + 1) * grid_resolution + x
			var i_br = (z + 1) * grid_resolution + (x + 1)
			
			var p_tl = points[i_tl]
			var p_tr = points[i_tr]
			var p_bl = points[i_bl]
			var p_br = points[i_br]
			
			# No Tearing: Connect everything to avoid gaps.
			# High grid resolution makes walls less noticeable.

			# Calculate opacity (distance from player feet height 0?)
			# Or distance of the point itself from origin?
			# Let's simply use a constant black, but vertex alpha based on individual point depth?
			# Or just let the Shader handle the radial fade?
			# The shader handles Radial fade. We just handle base opacity?
			# Actually, if we are far from ground, we want to fade out.
			# Let's calculate alpha per vertex based on its Y depth relative to origin (0).
			
			var c_tl = _get_vertex_color(p_tl)
			var c_tr = _get_vertex_color(p_tr)
			var c_bl = _get_vertex_color(p_bl)
			var c_br = _get_vertex_color(p_br)
			
			var uv_tl = _get_uv(x, z)
			var uv_tr = _get_uv(x + 1, z)
			var uv_bl = _get_uv(x, z + 1)
			var uv_br = _get_uv(x + 1, z + 1)
			
			# Triangle 1: TL-TR-BL
			_mesh_tool.add_color(c_tl); _mesh_tool.add_uv(uv_tl); _mesh_tool.add_vertex(p_tl + Vector3(0, vertical_offset, 0))
			_mesh_tool.add_color(c_tr); _mesh_tool.add_uv(uv_tr); _mesh_tool.add_vertex(p_tr + Vector3(0, vertical_offset, 0))
			_mesh_tool.add_color(c_bl); _mesh_tool.add_uv(uv_bl); _mesh_tool.add_vertex(p_bl + Vector3(0, vertical_offset, 0))

			# Triangle 2: TR-BR-BL
			_mesh_tool.add_color(c_tr); _mesh_tool.add_uv(uv_tr); _mesh_tool.add_vertex(p_tr + Vector3(0, vertical_offset, 0))
			_mesh_tool.add_color(c_br); _mesh_tool.add_uv(uv_br); _mesh_tool.add_vertex(p_br + Vector3(0, vertical_offset, 0))
			_mesh_tool.add_color(c_bl); _mesh_tool.add_uv(uv_bl); _mesh_tool.add_vertex(p_bl + Vector3(0, vertical_offset, 0))

	self.mesh = _mesh_tool.commit()

func _get_vertex_color(p: Vector3) -> Color:
	# p.y is local y (distance from player feet level)
	var dist = abs(p.y)
	var alpha = clamp(1.0 - (dist / max_distance), 0.0, base_opacity)
	return Color(0, 0, 0, alpha)

func _get_uv(x: int, z: int) -> Vector2:
	return Vector2(float(x) / (grid_resolution - 1), float(z) / (grid_resolution - 1))
