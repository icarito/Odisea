extends MeshInstance

# FakeShadow.gd (Grid Topology)
# Generates a dynamic "blanket" shadow mesh using a grid of raycasts.
# Drapes over obstacles and "tears" at steep cliffs to avoid walls.

export(Texture) var shadow_texture: Texture
export(float) var radius: float = 0.35 # Actual World Radius of the shadow blob
export(float, 0.0, 1.0) var hardness: float = 0.5 # Edge softness
export(String, "cheap", "grid") var shadow_mode: String = "cheap"
export(int) var grid_resolution: int = 20 # NxN rays (Increased for better detail)
export(float) var max_distance: float = 6.0
export(float, 0.0, 1.0) var base_opacity: float = 1.0
# Sólo para la BlobShadow real: el caster es una esfera y su sombra mide
# exactamente su radio. Tentador agrandarlo para igualar el óvalo ancho de la
# sombra legacy, pero el occluder es un VOLUMEN y oscurece todo lo que tapa,
# incluida la malla del propio actor: con 2.2 (r=1.1 para el piloto) la esfera
# envolvía el cuerpo hasta el pecho y lo auto-sombreaba. A 1.0 llega a la
# rodilla: sombra de piso, con las piernas apenas oscurecidas (deseable).
# Mismo arreglo que el demo_advanced del fork (godot-box3d 8c61288).
export(float) var blob_radius_scale: float = 1.0
export(float) var skirt_limit: float = 5.0 # Max height for skirts before we stop drawing them (avoid giant walls)
export(float) var vertical_offset: float = 0.02
export(float) var snap_amount: float = 0.1 # World Grid Size (10cm matches your 0.2m floors)
export(float) var smooth_speed: float = 10.0 # Lerp speed
export(int, 1, 8) var update_every_n_frames: int = 3
# Ajuste del look en cheap mode (quad plano): uv_scale >1 achica el blobl, opacity <1
# lo aclara. Valores elegidos para parecerse a lo que daba la grilla en el handheld.
export(float, 0.5, 3.0) var cheap_uv_scale: float = 1.55
export(float, 0.1, 1.0) var cheap_opacity: float = 0.55
export(float) var movement_epsilon: float = 0.02
export(float) var rotation_epsilon_deg: float = 1.0
export(bool) var anchor_to_root_body: bool = true
export(Vector3) var anchor_offset: Vector3 = Vector3(0, 0, 0)
# Include Entorno (1), NPC-Friendly (3, legacy), and Prop (7) so moving platforms/elevators receive the shadow.
export(int) var ground_collision_mask: int = 69

var _rays: Array = [] # Legacy: ya sin nodos RayCast de grilla (FD-290); queda vacío
# FD-290: la grilla ya no son 64 nodos RayCast con force_raycast_update por celda; es una
# pasada de intersect_ray sobre offsets precomputados. Resultados por celda:
var _ray_offsets := PoolVector3Array()
var _offset_step := -1.0
var _hit_points := PoolVector3Array()
var _hit_flags := PoolIntArray()
var _last_heights := PoolRealArray()
var _last_flags := PoolIntArray()
var _exclude_list: Array = []
var _mesh_needs_rebuild := true
var _mesh_tool: SurfaceTool
var _actor_excluded = false
var _disable_runtime := false
var _update_counter := 0
var _has_last_sample := false
var _last_parent_pos := Vector3.ZERO
var _last_parent_rot_y := 0.0
var _cheap_ray: RayCast = null
var _cheap_ground_y := 0.0
# Blob shadow path (godot-box3d fork). When the engine exposes BlobShadow we
# drop the generated "blanket" mesh and cast the real analytic shadow instead;
# the rest of this script (and its exports) stays untouched for stock Godot.
var _blob_mode := false
var _blob_caster: Node = null
var _blob_rig: Node = null

func _ready() -> void:
	var disable_env := OS.get_environment("ODISEA_DISABLE_FAKE_SHADOW").to_lower()
	_disable_runtime = disable_env in ["1", "true", "yes", "on"]
	var force_cheap_runtime := false

	# O8: el fallback "cheap" ya no se decide por arquitectura. Antes se forzaba con
	# OS.get_name()=="Linux"/"Unix" + /proc/cpuinfo conteniendo "arm", lo que ademas
	# elegia cheap en cualquier ARM (incluso desktop) y nunca en un low-end no-ARM.
	# Se gatea por el flag de tier bajo del proyecto (GLES3VendorGate.is_low_tier():
	# adapter verificado + opcion de usuario + ODISEA_FORCE_LOW_TIER). Desktop y ARM
	# sin low-end conservan el camino grid.
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate != null and gate.has_method("is_low_tier") and gate.is_low_tier():
		force_cheap_runtime = true

	# Prefer the real blob shadows when the running engine is the fork with the
	# backport; the legacy grid/cheap machinery stays for stock Godot.
	# Va ANTES del disable: el tier LOW apaga las sombras falsas (quads +
	# raycasts por prop) pero la del piloto es gameplay, y la blob es analítica
	# (sin mesh, sin raycasts), así que es la sombra más barata que hay.
	# En modo plano (unshaded) la blob analítica no se ve: los materiales FlatFake
	# saltean el pase de luz, así que el piso no la recibe. La sombra del piloto es
	# gameplay, así que ahí se usa el quad legacy (transparente sobre el piso plano);
	# el resto de los actores sigue con la blob y en tier LOW queda como estaba.
	if _blob_shadows_supported():
		if _flat_mode_active() and _is_pilot_owner():
			_disable_runtime = false
		else:
			_setup_blob_shadow()
			return

	if _disable_runtime:
		visible = false
		set_process(false)
		return

	if force_cheap_runtime:
		shadow_mode = "cheap"
		# La sombra del piloto es gameplay y en cheap mode es UN quad + UN raycast:
		# refrescar cada frame la mantiene pegada al piso (el raycast da la altura) y
		# sin escalonar. Los props conservan el intervalo alto (en LOW estan apagados).
		update_every_n_frames = 1 if _is_pilot_owner() else max(update_every_n_frames, 6)
		grid_resolution = min(grid_resolution, 8)
	elif OS.get_name() == "Android":
		# FD-290 (a): en ARM movil el modo grid baja de 8x8 a 6x6 en vez de saltar a
		# cheap. Con la pasada directa de intersect_ray y el rebuild condicionado, la
		# sombra se mantiene fiel a menos costo de fisica y de SurfaceTool.
		grid_resolution = min(grid_resolution, 6)

	# Continue with setup
	_mesh_tool = SurfaceTool.new()
	
	var mat = preload("res://materials/shadow/FakeShadowShader.tres")
	material_override = mat
	material_override.render_priority = -1
	if shadow_texture:
		material_override.set_shader_param("texture_albedo", shadow_texture)

	if shadow_mode == "grid":
		_create_rays()
	else:
		# Cheap mode: one quad + one raycast.
		var plane = PlaneMesh.new()
		plane.size = Vector2(max(0.05, radius * 2.0), max(0.05, radius * 2.0))
		mesh = plane
		_cheap_ray = RayCast.new()
		_cheap_ray.name = "CheapShadowRay"
		_cheap_ray.enabled = true
		_cheap_ray.collision_mask = ground_collision_mask
		_cheap_ray.cast_to = Vector3(0, -max_distance - 1.0, 0)
		add_child(_cheap_ray)
	
	cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	set_as_toplevel(true)

func _blob_shadows_supported() -> bool:
	# Opt-out for A/B and for forcing the legacy path on the fork.
	var off_env := OS.get_environment("ODISEA_DISABLE_BLOB_SHADOW").to_lower()
	if off_env in ["1", "true", "yes", "on"]:
		return false
	return ClassDB.class_exists("BlobShadow") and ClassDB.class_exists("BlobFocus")

# El modo plano del tier LOW (ODISEA_UNSHADED) reemplaza los materiales del mundo
# por FlatFake (unshaded): la blob shadow analítica vive en el pase de luz, así que
# no oscurece esos materiales. Con modo plano se prefiere el quad legacy.
func _flat_mode_active() -> bool:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	return gate != null and gate.has_method("is_flat_mode") and gate.is_flat_mode()

# Solo la sombra del piloto es gameplay; las de props siguen el disable del tier LOW.
# No alcanza con el grupo "player": PlayerControllerV2 lo agrega en su _ready, que corre
# DESPUES del _ready de este hijo (Godot hace _ready de hijos a padres). En ese momento el
# grupo todavia no existe y el piloto caia en blob mode, invisible con el mundo aplanado.
# Por eso tambien se detecta por la API del controller, que ya esta en el script al instanciar.
func _is_pilot_owner() -> bool:
	var node := get_parent()
	while node != null:
		if node.is_in_group("player"):
			return true
		if node.has_method("set_external_velocity") or node.has_method("get_input_provider"):
			return true
		node = node.get_parent()
	return false

func is_blob_mode() -> bool:
	return _blob_mode

func _setup_blob_shadow() -> void:
	_blob_mode = true
	# El disable del tier LOW apaga la malla+raycasts, no la sombra del actor:
	# en modo blob el _process sólo mueve el caster (ODISEA_DISABLE_BLOB_SHADOW
	# sigue devolviendo el camino legacy, que sí respeta el disable).
	_disable_runtime = false
	# No generated blanket mesh: the cast is analytic.
	mesh = null
	material_override = null
	cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	set_as_toplevel(true)

	_blob_rig = _get_or_create_blob_rig()
	_blob_caster = ClassDB.instance("BlobShadow")
	_blob_caster.name = "BlobCaster"
	_blob_caster.set("type", 0) # BlobShadow.BLOB_SHADOW_SPHERE
	_blob_caster.call("set_radius", 0, max(0.05, radius * blob_radius_scale))
	add_child(_blob_caster)
	# Match the legacy look where the exports can: the rig owns the light, so
	# the first actor that creates it also tunes intensity/hardness from its
	# exports (they are the same across actors in practice).
	if _blob_rig.has_method("set_light_param"):
		_blob_rig.call("set_light_param", 2, clamp(base_opacity, 0.0, 1.0)) # INTENSITY
		_blob_rig.call("set_light_param", 0, clamp(hardness, 0.0, 1.0)) # RANGE_HARDNESS
	print("[FakeShadow] usando BlobShadow real (radius=", radius, ")")

func _get_or_create_blob_rig() -> Node:
	var tree := get_tree()
	var host: Node = tree.current_scene
	if host == null:
		host = tree.root
	# The first FakeShadow runs while the level is still setting up its
	# children, so the rig is queued deferred; remember it on the host so the
	# next actor in the same frame reuses it instead of creating a second one.
	if host.has_meta("blob_shadow_rig"):
		var pending = host.get_meta("blob_shadow_rig")
		if is_instance_valid(pending):
			return pending
	for n in tree.get_nodes_in_group("blob_shadow_rig"):
		if is_instance_valid(n):
			host.set_meta("blob_shadow_rig", n)
			return n
	var rig = load("res://core_v2/visual/BlobShadowRig.gd").new()
	rig.name = "BlobShadowRig"
	host.set_meta("blob_shadow_rig", rig)
	host.call_deferred("add_child", rig)
	return rig

func _process_blob_shadow() -> void:
	var parent = get_parent()
	if not parent:
		return
	if _blob_caster == null or not is_instance_valid(_blob_caster):
		return
	# At the base of the actor, never encompassing the mesh: the caster is a
	# volume and would otherwise self-shadow the body it belongs to.
	var center_pos = _get_anchor_center_pos(parent)
	center_pos.y += max(0.02, vertical_offset)
	_blob_caster.global_transform.origin = center_pos

func _create_rays() -> void:
	# (FD-290) Ya no se crean nodos RayCast para la grilla: los offsets se arman bajo
	# demanda en _rebuild_grid_offsets() y las consultas son intersect_ray directos.
	for c in get_children():
		if c is RayCast:
			c.queue_free()
	_rays.clear()
	_ray_offsets.resize(grid_resolution * grid_resolution)
	_rebuild_grid_offsets(_grid_step())


func _grid_step() -> float:
	return snap_amount if snap_amount > 0.001 else 0.1


func _rebuild_grid_offsets(step: float) -> void:
	_offset_step = step
	var grid_width := step * float(grid_resolution - 1)
	var start_offset := -grid_width * 0.5
	var idx := 0
	for z in range(grid_resolution):
		for x in range(grid_resolution):
			# Mismo levantamiento de 1.0 m que tenia cada RayCast: cubre origenes del
			# actor a nivel de piso o ligeramente enterrados.
			_ray_offsets[idx] = Vector3(start_offset + float(x) * step, 1.0, start_offset + float(z) * step)
			idx += 1
	_hit_points.resize(_ray_offsets.size())
	_hit_flags.resize(_ray_offsets.size())

func _process(_delta: float) -> void:
	if _disable_runtime:
		return
	if _blob_mode:
		_process_blob_shadow()
		return
	var parent = get_parent()
	if not parent: return
	
	var center_pos = _get_anchor_center_pos(parent)
	
	# Grid mode benefits from snapping + UV slide.
	# Cheap mode skips this to reduce per-frame cost.
	if shadow_mode == "grid" and snap_amount > 0.0:
		var snapped_pos = center_pos.snapped(Vector3(snap_amount, snap_amount, snap_amount))
		global_transform.origin = snapped_pos
		var diff = center_pos - snapped_pos
		if material_override:
			var step = snap_amount
			if step <= 0.001:
				step = 0.1
			var grid_width = max(0.001, step * (grid_resolution - 1))
			var uv_off = Vector2(diff.x, diff.z) / grid_width
			material_override.set_shader_param("uv_offset", uv_off)
	else:
		global_transform.origin = center_pos
		
	_handle_exclusions()

	# Keep mesh orientation stable. In cheap mode we use PlaneMesh (already XZ).
	global_transform.basis = Basis.IDENTITY
	if shadow_mode != "grid":
		var cheap_pos = global_transform.origin
		cheap_pos.y = _cheap_ground_y if _has_last_sample else (center_pos.y - 1.0)
		global_transform.origin = cheap_pos

	var parent_rot_y = parent.global_transform.basis.get_euler().y
	var moved_sq = center_pos.distance_squared_to(_last_parent_pos)
	var rot_delta = abs(wrapf(parent_rot_y - _last_parent_rot_y, -PI, PI))
	var move_eps_sq = movement_epsilon * movement_epsilon
	var frame_interval = max(1, update_every_n_frames)
	_update_counter += 1

	var should_refresh = false
	if not _has_last_sample:
		should_refresh = true
	elif moved_sq >= move_eps_sq:
		should_refresh = true
	elif rot_delta >= deg2rad(rotation_epsilon_deg):
		should_refresh = true
	elif _update_counter >= frame_interval:
		should_refresh = true

	if not should_refresh:
		if shadow_mode != "grid":
			var keep_pos = global_transform.origin
			keep_pos.y = _cheap_ground_y if _has_last_sample else (center_pos.y - 1.0)
			global_transform.origin = keep_pos
		return

	_update_counter = 0
	_has_last_sample = true
	_last_parent_pos = center_pos
	_last_parent_rot_y = parent_rot_y

	if shadow_mode != "grid":
		_refresh_cheap_shadow(center_pos, parent_rot_y)
		return

	# Update Shader Params
	# Perfect Pixel Alignment: the grid step matches snap_amount (or fallback), so mesh
	# UVs keep landing on the world grid without diagonal artifacts.
	
	var step = snap_amount
	if step <= 0.001: step = 0.1 # Fallback
	
	# Calculate effective size based on resolution and step
	# We want the shadow to cover roughly 'radius' * 2
	# But rigidly constrained to grid.
	# Actually, let's keep 'resolution' fixed and 'step' fixed.
	# size is derived.
	
	var grid_width = step * (grid_resolution - 1)
	
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
	
	# FD-290: una sola pasada de intersect_ray sobre la grilla, sin nodos RayCast ni
	# force_raycast_update. La malla se regenera solo si alguna celda cruzo snap_amount.
	_refresh_grid_hits()
	_generate_mesh()


func _refresh_grid_hits() -> void:
	var step := _grid_step()
	if step != _offset_step or _ray_offsets.size() != grid_resolution * grid_resolution:
		_rebuild_grid_offsets(step)
	var count := _ray_offsets.size()
	var space := get_world().direct_space_state
	var drop := max_distance + 1.0
	if space == null:
		for idx in range(count):
			_hit_flags[idx] = 0
			_hit_points[idx] = global_transform.origin + _ray_offsets[idx]
	else:
		for idx in range(count):
			var from: Vector3 = global_transform.origin + _ray_offsets[idx]
			var to := Vector3(from.x, from.y - drop, from.z)
			var result: Dictionary = space.intersect_ray(from, to, _exclude_list, ground_collision_mask, true, false)
			if result.empty():
				_hit_flags[idx] = 0
				_hit_points[idx] = from
			else:
				_hit_flags[idx] = 1
				_hit_points[idx] = result.get("position", from)

	# Cache de malla (FD-290 c): si ninguna celda cambio mas que snap_amount y no cambio
	# el patron de huecos, el SurfaceTool no corre. La copia a _last_* es por elemento,
	# sin duplicar pools por refresh.
	var rebuild := true
	if _last_heights.size() == count:
		rebuild = false
		for idx in range(count):
			var valid_now := _hit_flags[idx] == 1
			if valid_now != (_last_flags[idx] == 1):
				rebuild = true
				break
			if valid_now and abs(_hit_points[idx].y - _last_heights[idx]) > snap_amount:
				rebuild = true
				break
	if _last_heights.size() != count:
		_last_heights.resize(count)
		_last_flags.resize(count)
	for idx in range(count):
		_last_flags[idx] = _hit_flags[idx]
		_last_heights[idx] = _hit_points[idx].y if _hit_flags[idx] == 1 else 0.0
	_mesh_needs_rebuild = rebuild

func _refresh_cheap_shadow(center_pos: Vector3, parent_rot_y: float) -> void:
	if _cheap_ray:
		_cheap_ray.global_transform.origin = center_pos + Vector3(0, 1.0, 0)
		_cheap_ray.cast_to = Vector3(0, -max_distance - 1.0, 0)
		_cheap_ray.force_raycast_update()
		if _cheap_ray.is_colliding():
			_cheap_ground_y = _cheap_ray.get_collision_point().y + vertical_offset
		else:
			_cheap_ground_y = center_pos.y - max_distance + vertical_offset
	else:
		_cheap_ground_y = center_pos.y - max_distance + vertical_offset

	if material_override:
		material_override.set_shader_param("hardness", hardness)
		# El quad pelado (PlaneMesh, COLOR.a=1) cae en la variante mas grande y opaca
		# del shader: en grid el uv_scale salia ~0.7 y el alpha por celda era <1. Se
		# achica (uv_scale >1) y se aclara (opacity <1) para igualar el look de grid.
		material_override.set_shader_param("uv_scale", cheap_uv_scale)
		material_override.set_shader_param("opacity", cheap_opacity)
		material_override.set_shader_param("texture_rotation", -parent_rot_y)

	if mesh is PlaneMesh:
		var plane: PlaneMesh = mesh
		plane.size = Vector2(max(0.05, radius * 2.0), max(0.05, radius * 2.0))

	var p = global_transform.origin
	p.y = _cheap_ground_y
	global_transform.origin = p

func _get_anchor_center_pos(parent: Node) -> Vector3:
	# Transform INTERPOLADA: con physics_interpolation activa (lowend.cfg) el player
	# se DIBUJA interpolado entre ticks de fisica, pero global_transform devuelve la
	# posicion cruda del ultimo tick. Leer la cruda hacia que la sombra quedara hasta
	# un tick (33 ms) atras del cuerpo. `get_global_transform_interpolated()` (fork)
	# devuelve la misma que ve el render.
	var center_pos: Vector3 = _interpolated_origin(parent as Spatial)
	if anchor_to_root_body:
		var p: Node = parent
		while p:
			if p is PhysicsBody:
				center_pos = _interpolated_origin(p as Spatial)
				break
			p = p.get_parent()
	return center_pos + anchor_offset

func _interpolated_origin(node: Spatial) -> Vector3:
	if node == null:
		return Vector3.ZERO
	if node.has_method("get_global_transform_interpolated"):
		return node.get_global_transform_interpolated().origin
	return node.global_transform.origin

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
		# FD-290: la exclusion del actor viaja en el array de exclude de cada intersect_ray
		# de la grilla; el modo cheap sigue usando su RayCast nodo.
		_exclude_list.clear()
		_exclude_list.append(actor)
		if _cheap_ray:
			_cheap_ray.add_exception(actor)
		_actor_excluded = true

func _generate_mesh() -> void:
	# Cache de malla (FD-290 c): _refresh_grid_hits decide si algo cruzo snap_amount; si
	# nada cruzo, la malla anterior sigue siendo exacta y el SurfaceTool no corre.
	if not _mesh_needs_rebuild:
		return
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
			
			var center_pos = Vector3.ZERO
			var is_gap = false
			
			if _hit_flags[idx] == 1:
				center_pos = to_local(_hit_points[idx])
			else:
				# Miss - Push down to max distance
				var r_origin: Vector3 = _ray_offsets[idx]
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
			
			var _u_l = float(x) / (grid_resolution - 1)
			var _u_r = float(x + 1) / (grid_resolution - 1)
			var _v_t = float(z) / (grid_resolution - 1)
			var _v_b = float(z + 1) / (grid_resolution - 1)
			
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
				var pos_right = _get_hit_pos(idx_right)
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
					
					var _v_my_tl = Vector3(0, y_my_floor + y_bias, z_start)
					var _v_my_bl = Vector3(0, y_my_floor + y_bias, z_end)
					var _v_ne_tl = Vector3(0, y_neighbor - y_bias, z_start)
					var _v_ne_bl = Vector3(0, y_neighbor - y_bias, z_end)
					
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
				var pos_down = _get_hit_pos(idx_down)
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
	_mesh_needs_rebuild = false

func _get_hit_pos(idx: int) -> Vector3:
	if _hit_flags[idx] == 1:
		return to_local(_hit_points[idx])
	
	var off: Vector3 = _ray_offsets[idx]
	return Vector3(off.x, -max_distance, off.z)


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
