extends MeshInstance

# FakeShadow.gd (Grid Topology)
# Generates a dynamic "blanket" shadow mesh using a grid of raycasts.
# Drapes over obstacles and "tears" at steep cliffs to avoid walls.

export(Texture) var shadow_texture: Texture
export(float) var radius: float = 1.0 # Actual World Radius of the shadow blob
export(float, 0.0, 1.0) var hardness: float = 0.5 # Edge softness
export(int) var grid_resolution: int = 12 # NxN rays
export(float) var max_distance: float = 6.0
export(float, 0.0, 1.0) var base_opacity: float = 1.0
export(float) var skirt_limit: float = 2.0 # Max height for skirts before we stop drawing them (avoid giant walls)
export(float) var vertical_offset: float = 0.02
export(float) var snap_amount: float = 0.25 # World Grid Size
export(float) var smooth_speed: float = 10.0 # Lerp speed

var _rays: Array = [] # Linear array of rays
var _mesh_tool: SurfaceTool
var _actor_excluded = false

func _ready() -> void:
	_mesh_tool = SurfaceTool.new()
	
	var mat = preload("res://materials/shadow/FakeShadowShader.tres")
	material_override = mat
	material_override.render_priority = -1
	if shadow_texture:
		material_override.set_shader_param("texture_albedo", shadow_texture)

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
	
	# Snap Position for Pixel Art / Stability
	# We MUST snap the mesh to the grid to avoid "swimming" geometry.
	if snap_amount > 0.0:
		var snapped_pos = center_pos.snapped(Vector3(snap_amount, snap_amount, snap_amount))
		global_transform.origin = snapped_pos
		
		# UV Sliding Technique:
		# The mesh is snapped, but we want the shadow blob to follow the player smoothly.
		# We calculate the difference and shift the UVs.
		var diff = center_pos - snapped_pos
		# Map world diff to UV space. 
		# If UV scale is based on grid_width radius...
		# Actually, simpler: Pass world offset to shader and let shader handle it?
		# Or pre-calculate UV offset here.
		# Let's pass Vector2 offset (x, z).
		
		if material_override:
			# We need to scale this offset by the same factor used for UVs
			# Grid width in world units:
			var step = snap_amount
			if step <= 0.001: step = 0.1
			var grid_width = step * (grid_resolution - 1)
			
			# UV is 0..1 over grid_width.
			# So 1 unit world move = 1.0/grid_width UV move.
			var uv_off = Vector2(diff.x, diff.z) / grid_width
			
			# We need to subtract this offset because if player moves RIGHT (+X),
			# the texture needs to move RIGHT. 
			# In UV space, moving texture right means modifying UVs... how?
			# uv = UV - offset. 
			material_override.set_shader_param("uv_offset", uv_off)
	else:
		global_transform.origin = center_pos
		
	_handle_exclusions()

	# Reset rotation (Mesh stays axis aligned)
	global_transform.basis = Basis.IDENTITY

	# Update Ray Positions
	# Perfect Pixel Alignment:
	# Force the grid step to match the snap_amount (or a multiple)
	# This ensures vertices always land on the "world grid", avoiding diagonal artifacts/beating.
	
	var step = snap_amount
	if step <= 0.001: step = 0.1 # Fallback
	
	# Calculate effective size based on resolution and step
	# We want the shadow to cover roughly 'radius' * 2
	# But rigidly constrained to grid.
	# Actually, let's keep 'resolution' fixed and 'step' fixed.
	# size is derived.
	
	var grid_width = step * (grid_resolution - 1)
	var start_offset = - grid_width / 2.0
	
	# Update Shader Params
	if material_override:
		# UV Scale logic:
		# Mesh width is 'grid_width'. UV covers 0..1.
		# We want shadow circle to have world diameter = radius * 2.
		# Fraction of mesh covered = (radius * 2) / grid_width.
		# UV Scale factor (inverse) = 1.0 / Fraction = grid_width / (radius * 2).
		# Check div by zero
		if radius < 0.01: radius = 0.01
		var scale = grid_width / (radius * 2.0)
		
		material_override.set_shader_param("uv_scale", scale)
		material_override.set_shader_param("hardness", hardness)
		
		# Rotation Logic
		if parent:
			var rot_y = parent.global_transform.basis.get_euler().y
			# We might need to invert it depending on setup.
			material_override.set_shader_param("texture_rotation", -rot_y)
	
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
	# Voxel/Manhattan Meshing Strategy
	# Treat each ray hit as the center of a flat horizontal tile.
	# Connect adjacent tiles with vertical "skirts" to form a solid step-mesh.
	# This ensures 0 diagonal slopes, perfect for pixel-art/voxel worlds.
	_mesh_tool.clear()
	_mesh_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var step = snap_amount
	if step <= 0.001: step = 0.1
	var half_size = step * 0.5
	
	# To make UVs work, we need to know the total grid bounds
	# grid_resolution is N. Loop 0..N-1.
	
	for z in range(grid_resolution):
		for x in range(grid_resolution):
			var idx = z * grid_resolution + x
			var r = _rays[idx]
			
			var center_pos = Vector3.ZERO
			var is_gap = false
			
			if r.is_colliding():
				center_pos = to_local(r.get_collision_point())
			else:
				# Miss - Push down to max distance
				# Or mark as gap? If we mark as gap, we might want to skip drawing
				# But let's draw at bottom to be safe/consistent
				var r_origin = r.transform.origin
				center_pos = Vector3(r_origin.x, -max_distance, r_origin.z)
				is_gap = true # Maybe fade it out?
				
			# 1. Draw Horizontal Tile
			# TL, TR, BR, BL relative to center
			var v_tl = center_pos + Vector3(-half_size, vertical_offset, -half_size)
			var v_tr = center_pos + Vector3(half_size, vertical_offset, -half_size)
			var v_br = center_pos + Vector3(half_size, vertical_offset, half_size)
			var v_bl = center_pos + Vector3(-half_size, vertical_offset, half_size)
			
			var c = _get_vertex_color(center_pos)
			# If gap/miss, make alpha 0?
			if is_gap: c.a = 0.0
			
	# 2. Per-Vertex UVs for Smooth Gradients
			# We need UVs for TL, TR, BR, BL based on their world position relative to grid
			# To keep it simple, we interpolate from the 0..1 range
			
			var u_l = float(x) / (grid_resolution - 1)
			var u_r = float(x + 1) / (grid_resolution - 1)
			var v_t = float(z) / (grid_resolution - 1)
			var v_b = float(z + 1) / (grid_resolution - 1)
			
			# If we are at the last index, u_r / v_b usually don't matter for the *loop* 
			# but this loop goes to grid_resolution.
			# Actually, we loop x in range(grid_resolution). 
			# This implies we draw tiles centered on rays? 
			# My prev logic: "Treat each ray hit as center of tile".
			# So UV for center is x/res. 
			# UV for TL is (x - 0.5)/res?
			
			# Let's retain "Center of Tile" logic but calculate corners.
			# UV Scale is 1.0/res.
			var uv_step = 1.0 / (grid_resolution - 1)
			var half_uv = uv_step * 0.5
			
			var u_center = float(x) / (grid_resolution - 1)
			var v_center = float(z) / (grid_resolution - 1)
			
			var uv__tl = Vector2(u_center - half_uv, v_center - half_uv)
			var uv__tr = Vector2(u_center + half_uv, v_center - half_uv)
			var uv__br = Vector2(u_center + half_uv, v_center + half_uv)
			var uv__bl = Vector2(u_center - half_uv, v_center + half_uv)
			
			# Draw Floor
			_add_quad(v_tl, v_tr, v_br, v_bl, c, uv__tl, uv__tr, uv__br, uv__bl)
			
			# 2. Draw Vertical Skirts
			# Right Neighbor
			if x < grid_resolution - 1:
				var idx_right = z * grid_resolution + (x + 1)
				var r_right = _rays[idx_right]
				var pos_right = _get_hit_pos(r_right)
				var dy = pos_right.y - center_pos.y
				
				if abs(dy) > 0.01 and abs(dy) < (skirt_limit + 0.1):
					var bias = 0.01 # Push wall out slightly to avoid Z-fighting
					var wall_x = center_pos.x + half_size + bias
					var z_start = center_pos.z - half_size
					var z_end = center_pos.z + half_size
					
					var w_tl = Vector3(wall_x, center_pos.y + vertical_offset, z_start)
					var w_bl = Vector3(wall_x, center_pos.y + vertical_offset, z_end)
					var w_tr = Vector3(wall_x, pos_right.y + vertical_offset, z_start)
					var w_br = Vector3(wall_x, pos_right.y + vertical_offset, z_end)
					
					# Vertical Projection: Bottom vertices use same UVs as Top vertices
					# Skirt is on Right side of tile. UVs are TR and BR.
					# Top Edge: TR->BR. Bottom Edge: TR->BR.
					_add_quad(w_tl, w_tr, w_br, w_bl, c, uv__tr, uv__tr, uv__br, uv__br)

			# Bottom Neighbor
			if z < grid_resolution - 1:
				var idx_down = (z + 1) * grid_resolution + x
				var r_down = _rays[idx_down]
				var pos_down = _get_hit_pos(r_down)
				var dy = pos_down.y - center_pos.y
				
				if abs(dy) > 0.01 and abs(dy) < (skirt_limit + 0.1):
					var bias = 0.01 # Push wall out slightly to avoid Z-fighting
					var wall_z = center_pos.z + half_size + bias
					var x_start = center_pos.x - half_size
					var x_end = center_pos.x + half_size
					
					var w_tl = Vector3(x_start, center_pos.y + vertical_offset, wall_z)
					var w_tr = Vector3(x_end, center_pos.y + vertical_offset, wall_z)
					var w_bl = Vector3(x_start, pos_down.y + vertical_offset, wall_z)
					var w_br = Vector3(x_end, pos_down.y + vertical_offset, wall_z)
					
					# Vertical Projection: Bottom used Top UVs
					# Skirt is on Bottom side. UVs are BL and BR.
					_add_quad(w_tl, w_tr, w_br, w_bl, c, uv__bl, uv__br, uv__br, uv__bl)

	self.mesh = _mesh_tool.commit()

func _get_hit_pos(r: RayCast) -> Vector3:
	if r.is_colliding():
		return to_local(r.get_collision_point())
	
	var ro = r.transform.origin
	return Vector3(ro.x, -max_distance, ro.z)


func _add_quad(v1, v2, v3, v4, c, uv1, uv2, uv3, uv4):
	_mesh_tool.add_color(c); _mesh_tool.add_uv(uv1); _mesh_tool.add_vertex(v1)
	_mesh_tool.add_color(c); _mesh_tool.add_uv(uv2); _mesh_tool.add_vertex(v2)
	_mesh_tool.add_color(c); _mesh_tool.add_uv(uv3); _mesh_tool.add_vertex(v3)
	
	_mesh_tool.add_color(c); _mesh_tool.add_uv(uv1); _mesh_tool.add_vertex(v1)
	_mesh_tool.add_color(c); _mesh_tool.add_uv(uv3); _mesh_tool.add_vertex(v3)
	_mesh_tool.add_color(c); _mesh_tool.add_uv(uv4); _mesh_tool.add_vertex(v4)

func _get_vertex_color(p: Vector3) -> Color:
	# p.y is local y (distance from player feet level)
	var dist = abs(p.y)
	var alpha = clamp(1.0 - (dist / max_distance), 0.0, base_opacity)
	return Color(0, 0, 0, alpha)

func _get_uv(x: int, z: int) -> Vector2:
	# UVs span 0..1 across the grid
	return Vector2(float(x) / (grid_resolution - 1), float(z) / (grid_resolution - 1))
