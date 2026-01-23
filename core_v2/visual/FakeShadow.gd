extends MeshInstance

# FakeShadow.gd (Grid Topology)
# Generates a dynamic "blanket" shadow mesh using a grid of raycasts.
# Drapes over obstacles and "tears" at steep cliffs to avoid walls.

export(Texture) var shadow_texture: Texture
export(float) var radius: float = 1.0 # Actual World Radius of the shadow blob
export(float, 0.0, 1.0) var hardness: float = 0.5 # Edge softness
export(int) var grid_resolution: int = 20 # NxN rays (Increased for better detail)
export(float) var max_distance: float = 6.0
export(float, 0.0, 1.0) var base_opacity: float = 1.0
export(float) var skirt_limit: float = 5.0 # Max height for skirts before we stop drawing them (avoid giant walls)
export(float) var vertical_offset: float = 0.02
export(float) var snap_amount: float = 0.1 # World Grid Size (10cm matches your 0.2m floors)
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
			# Match the Player GroundRay mask (bits 1-20 or just all)
			r.collision_mask = 2147483647 # Scan EVERYTHING
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
			# Raise ray origin by 1.0m to handle cases where parent origin is floor-level or clipping
			r.transform.origin = Vector3(local_x, 1.0, local_z)
			r.cast_to = Vector3(0, -max_distance - 1.0, 0)
			r.force_raycast_update()
			ray_idx += 1

	_generate_mesh()

func _handle_exclusions() -> void:
	if _actor_excluded: return
	
	var actor = owner
	if not actor and get_parent():
		var p = get_parent()
		while p:
			if p is PhysicsBody: # Catch KinematicBody, RigidBody, StaticBody
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
	
	var bias = 0.002 # Tight bias to prevent floating but allow Z-fighting safety
	var half_size = step * 0.5 # Exact size, no overlapping floor tiles (Fixes Grid Lines)
	
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
				var r_origin = r.transform.origin
				center_pos = Vector3(r_origin.x, -max_distance, r_origin.z)
				is_gap = true
				
			# 1. Draw Horizontal Tile
			# TL, TR, BR, BL relative to center
			# Note: We use the expanded half_size here
			var v_tl = center_pos + Vector3(-half_size, vertical_offset, -half_size)
			var v_tr = center_pos + Vector3(half_size, vertical_offset, -half_size)
			var v_br = center_pos + Vector3(half_size, vertical_offset, half_size)
			var v_bl = center_pos + Vector3(-half_size, vertical_offset, half_size)
			
			var c_tl = _get_vertex_color(v_tl)
			var c_tr = _get_vertex_color(v_tr)
			var c_br = _get_vertex_color(v_br)
			var c_bl = _get_vertex_color(v_bl)
			
			# If gap/miss, make alpha 0?
			if is_gap:
				var c_gap = Color(0, 0, 0, 0)
				c_tl = c_gap; c_tr = c_gap; c_br = c_gap; c_bl = c_gap;
			
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
			
			# Draw Floor (CCW Winding: TL -> BL -> BR -> TR)
			_add_quad(v_tl, v_bl, v_br, v_tr, c_tl, c_bl, c_br, c_tr, uv__tl, uv__bl, uv__br, uv__tr, Vector3.UP)
			
			# 2. Draw Vertical Skirts
			
			# Use the same bias as floor tiles
			var grid_half = step * 0.5
			
			# Right Neighbor (X+)
			if x < grid_resolution - 1:
				var idx_right = z * grid_resolution + (x + 1)
				var r_right = _rays[idx_right]
				var pos_right = _get_hit_pos(r_right)
				var dy = pos_right.y - center_pos.y
				
				if abs(dy) > 0.01 and abs(dy) < (skirt_limit + 0.1):
					# Slanted Wall Logic:
					# connect exact floor edge to biased Wall plane.
					# Edge X = center_pos.x + grid_half
					var edge_x = center_pos.x + grid_half
					
					var z_start = center_pos.z - half_size
					var z_end = center_pos.z + half_size
					
					# Extend Vertical Range slightly
					var y_bias = 0.02
					var y_my_floor = center_pos.y + vertical_offset
					var y_neighbor = pos_right.y + vertical_offset
					
					# Define Wall Top and Bottom Y
					# Note: 'Top' and 'Bottom' here refer to visual Y, not logic.
					# Let's use 'High' and 'Low'.
					
					var w_high_x # X at high Y
					var w_low_x # X at low Y
					
					# Bias Logic:
					# Drop (dy < 0): I am High. Neighbor is Low.
					# Connection is at My Edge (High). Free end is at Neighbor (Low).
					# High X = edge_x (Touch my floor).
					# Low X = edge_x + bias (Push out over neighbor).
					
					# Step (dy > 0): I am Low. Neighbor is High.
					# Connection is at Neighbor Edge (High). Free end is at Me (Low).
					# High X = edge_x (Touch neighbor floor).
					# Low X = edge_x - bias (Push in over me).
					
					if dy < 0: # Drop
						w_high_x = edge_x
						w_low_x = edge_x + bias
					else: # Step
						w_high_x = edge_x
						w_low_x = edge_x - bias
					
					# Create Quad Vertices
					# We need to map High/Low X to the correct Y levels.
					# y_my_floor, y_neighbor.
					
					var v_my_tl = Vector3(0, y_my_floor + y_bias, z_start)
					var v_my_bl = Vector3(0, y_my_floor + y_bias, z_end)
					var v_ne_tl = Vector3(0, y_neighbor - y_bias, z_start)
					var v_ne_bl = Vector3(0, y_neighbor - y_bias, z_end)
					
					# If Drop: My is Top. Neighbor is Bottom.
					# w_tl/w_bl are at My Y. w_tr/w_br are at Neighbor Y.
					# Wait, let's use explicit geometry vars.
					var v_top_l: Vector3
					var v_top_r: Vector3 # 'r' here means Z-end, not Right side
					var v_bot_l: Vector3
					var v_bot_r: Vector3
					
					if dy < 0: # My is High
						v_top_l = Vector3(w_high_x, y_my_floor + y_bias, z_start)
						v_top_r = Vector3(w_high_x, y_my_floor + y_bias, z_end)
						v_bot_l = Vector3(w_low_x, y_neighbor - y_bias, z_start)
						v_bot_r = Vector3(w_low_x, y_neighbor - y_bias, z_end)
					else: # Neighbor is High
						v_top_l = Vector3(w_high_x, y_neighbor + y_bias, z_start)
						v_top_r = Vector3(w_high_x, y_neighbor + y_bias, z_end)
						v_bot_l = Vector3(w_low_x, y_my_floor - y_bias, z_start)
						v_bot_r = Vector3(w_low_x, y_my_floor - y_bias, z_end)
					
					# Calculate colors
					var c_top_l = _get_vertex_color(v_top_l)
					var c_top_r = _get_vertex_color(v_top_r)
					var c_bot_l = _get_vertex_color(v_bot_l)
					var c_bot_r = _get_vertex_color(v_bot_r)
					
					if dy < 0: # Drop to right (Faces +X, CCW: HighFront -> HighBack -> LowBack -> LowFront)
						_add_quad(v_top_r, v_top_l, v_bot_l, v_bot_r, c_top_r, c_top_l, c_bot_l, c_bot_r, uv__br, uv__tr, uv__tr, uv__br, Vector3.RIGHT)
						
					else: # Step up to right (Faces -X, CCW: HighBack -> HighFront -> LowFront -> LowBack)
						_add_quad(v_top_l, v_top_r, v_bot_r, v_bot_l, c_top_l, c_top_r, c_bot_r, c_bot_l, uv__tr, uv__br, uv__br, uv__tr, Vector3.LEFT)

			# Bottom Neighbor (Z+)
			if z < grid_resolution - 1:
				var idx_down = (z + 1) * grid_resolution + x
				var r_down = _rays[idx_down]
				var pos_down = _get_hit_pos(r_down)
				var dy = pos_down.y - center_pos.y
				
				if abs(dy) > 0.01 and abs(dy) < (skirt_limit + 0.1):
					# Slanted Wall Logic (Z-Axis)
					# Edge Z = center_pos.z + grid_half
					var edge_z = center_pos.z + grid_half
					
					var x_start = center_pos.x - half_size
					var x_end = center_pos.x + half_size
					
					var y_bias = 0.02
					var y_my_floor = center_pos.y + vertical_offset
					var y_neighbor = pos_down.y + vertical_offset
					
					var w_high_z
					var w_low_z
					
					if dy < 0: # Drop (My is High)
						w_high_z = edge_z
						w_low_z = edge_z + bias
					else: # Step (Neighbor is High)
						w_high_z = edge_z
						w_low_z = edge_z - bias
						
					var v_top_l: Vector3
					var v_top_r: Vector3
					var v_bot_l: Vector3
					var v_bot_r: Vector3
					
					if dy < 0: # Drop (Faces +Z, Back) - My is Top
						# v_tl/v_tr at My Y. v_bl/v_br at Neighbor Y.
						v_top_l = Vector3(x_start, y_my_floor + y_bias, w_high_z)
						v_top_r = Vector3(x_end, y_my_floor + y_bias, w_high_z)
						v_bot_l = Vector3(x_start, y_neighbor - y_bias, w_low_z)
						v_bot_r = Vector3(x_end, y_neighbor - y_bias, w_low_z)
					else: # Step (Faces -Z, Forward) - Neighbor is Top
						# v_tl/v_tr at Neighbor Y. v_bl/v_br at My Y.
						v_top_l = Vector3(x_start, y_neighbor + y_bias, w_high_z)
						v_top_r = Vector3(x_end, y_neighbor + y_bias, w_high_z)
						v_bot_l = Vector3(x_start, y_my_floor - y_bias, w_low_z)
						v_bot_r = Vector3(x_end, y_my_floor - y_bias, w_low_z)
						
					var c_top_l = _get_vertex_color(v_top_l)
					var c_top_r = _get_vertex_color(v_top_r)
					var c_bot_l = _get_vertex_color(v_bot_l)
					var c_bot_r = _get_vertex_color(v_bot_r)
					
					if dy < 0: # Drop to bottom (Faces +Z)
						# Top is High. Bottom is Low.
						# Top-Left (High Left): v_top_l
						# Top-Right (High Right): v_top_r
						# Bot-Left (Low Left): v_bot_l
						# Bot-Right (Low Right): v_bot_r
						# _add_quad(TL, TR, BR, BL) relative to face looking from +Z
						# TL = v_top_r (Top Right in world, Top Left on Face)
						# TR = v_top_l (Top Left in world, Top Right on Face)
						# BR = v_bot_l
						# BL = v_bot_r
						_add_quad(v_top_r, v_top_l, v_bot_l, v_bot_r, c_top_r, c_top_l, c_bot_l, c_bot_r, uv__bl, uv__br, uv__br, uv__bl, Vector3.BACK)
						
					else: # Step up to bottom (Faces -Z)
						# Face -Z (Looking Forward)
						# Top is High (Neighbor). Bottom is Low (My).
						# TL = v_top_l
						# TR = v_top_r
						# BR = v_bot_r
						# BL = v_bot_l
						_add_quad(v_top_l, v_top_r, v_bot_r, v_bot_l, c_top_l, c_top_r, c_bot_r, c_bot_l, uv__br, uv__bl, uv__bl, uv__br, Vector3.FORWARD)

	self.mesh = _mesh_tool.commit()

func _get_hit_pos(r: RayCast) -> Vector3:
	if r.is_colliding():
		return to_local(r.get_collision_point())
	
	var ro = r.transform.origin
	return Vector3(ro.x, -max_distance, ro.z)


func _add_quad(v1, v2, v3, v4, c1, c2, c3, c4, uv1, uv2, uv3, uv4, normal: Vector3):
	_mesh_tool.add_normal(normal); _mesh_tool.add_color(c1); _mesh_tool.add_uv(uv1); _mesh_tool.add_vertex(v1)
	_mesh_tool.add_normal(normal); _mesh_tool.add_color(c2); _mesh_tool.add_uv(uv2); _mesh_tool.add_vertex(v2)
	_mesh_tool.add_normal(normal); _mesh_tool.add_color(c3); _mesh_tool.add_uv(uv3); _mesh_tool.add_vertex(v3)
	
	_mesh_tool.add_normal(normal); _mesh_tool.add_color(c1); _mesh_tool.add_uv(uv1); _mesh_tool.add_vertex(v1)
	_mesh_tool.add_normal(normal); _mesh_tool.add_color(c3); _mesh_tool.add_uv(uv3); _mesh_tool.add_vertex(v3)
	_mesh_tool.add_normal(normal); _mesh_tool.add_color(c4); _mesh_tool.add_uv(uv4); _mesh_tool.add_vertex(v4)

func _get_vertex_color(p: Vector3) -> Color:
	# p.y is local y (distance from player feet level)
	var dist = abs(p.y)
	var alpha = clamp(1.0 - (dist / max_distance), 0.0, base_opacity)
	return Color(0, 0, 0, alpha)

func _get_uv(x: int, z: int) -> Vector2:
	# UVs span 0..1 across the grid
	return Vector2(float(x) / (grid_resolution - 1), float(z) / (grid_resolution - 1))
