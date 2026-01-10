extends Area

export(Vector3) var push_velocity := Vector3(2, 0, 0) setget set_push_velocity
export(bool) var require_on_floor := false
export(float) var rigid_force_multiplier := 8.0
export(bool) var debug := false
export(Color) var stripe_dark_color = Color(0.18, 0.18, 0.18, 1.0)
export(Color) var stripe_light_color = Color(0.32, 0.32, 0.30, 1.0)
export(float) var stripe_emission = 0.04
export(float) var stripe_tiling = 4.0
export(float) var stripe_fill = 0.35

var _bodies := []
var _pending_snapshot = null
var _snapshot_applied := false

func _ready():
	add_to_group("replay_sync")
	var mat = _ensure_unique_material()
	if mat and mat is ShaderMaterial:
		_update_shader_params(mat)
		if debug:
			print("[Conveyor] Shader params updated dir=", Vector2(push_velocity.x, push_velocity.z), " speed=", push_velocity.length())
	# Aplicar snapshot pendiente (restore puede haberse llamado antes de _ready)
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null


func _ensure_unique_material() -> Material:
	if not has_node("Belt"):
		return null
	var mesh_instance = $Belt
	var mat = mesh_instance.material_override
	if not mat and mesh_instance.mesh:
		var mesh_mat = mesh_instance.mesh.surface_get_material(0)
		if mesh_mat:
			mat = mesh_mat.duplicate()
			mesh_instance.material_override = mat
	return mat

func _update_shader_params(mat: ShaderMaterial) -> void:
	if not mat:
		return
	var d = Vector2(push_velocity.x, push_velocity.z)
	if d.length() > 0.001:
		d = d.normalized()
	# The shader requires direction in UV space. Assuming U=X, V=Z mapping.
	# The user reports the texture is rotated 90 degrees compared to motion.
	# d is motion direction in XZ.
	# To fix 90 degree rotation, we rotate d by 90 degrees in UV space.
	# Vector2(d.y, -d.x) is -90 deg rotation. Vector2(-d.y, d.x) is +90 deg.
	var d_uv = Vector2(-d.y, d.x)
	# Negate because shader phase is 'dot(uv, d) + t'. Effective motion is opposite to d if +t.
	# We want motion ALONG d.
	# User reported direction is INVERSED. So we should NOT negate?
	# Or maybe the shader logic implies something else.
	# Let's try positive d_uv.
	mat.set_shader_param("dir", d_uv)
	
	# Calcular largo para ajustar velocidad visual
	# speed (shader) = (V_world / L_world) * tiling
	# Reduced multiplier slightly to match physics movement more accurately
	var length = _get_conveyor_length()
	var visible_speed = (push_velocity.length() / max(length, 0.001)) * stripe_tiling * 0.9
	
	mat.set_shader_param("speed", max(visible_speed, 0.0))
	mat.set_shader_param("color_a", stripe_dark_color)
	mat.set_shader_param("color_b", stripe_light_color)
	mat.set_shader_param("emission", stripe_emission)
	mat.set_shader_param("tiling", stripe_tiling)
	mat.set_shader_param("fill", stripe_fill)

func set_push_velocity(v: Vector3) -> void:
	push_velocity = v
	var mat = _ensure_unique_material()
	if mat and mat is ShaderMaterial:
		_update_shader_params(mat)


func _get_conveyor_length() -> float:
	var col = get_node_or_null("CollisionShape")
	if col and col.shape is BoxShape:
		var size = col.shape.extents * 2.0
		var dir = push_velocity.normalized()
		# Proyectar tamaño en la dirección del flujo. 
		# (Funciona bien para flujos alineados a ejes, aceptable para diagonales en cajas)
		return abs(dir.x * size.x) + abs(dir.y * size.y) + abs(dir.z * size.z)
	return 1.0


func get_snapshot() -> Dictionary:
	return {
		"pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"push_velocity": [push_velocity.x, push_velocity.y, push_velocity.z],
		"stripe_dark_color": [stripe_dark_color.r, stripe_dark_color.g, stripe_dark_color.b, stripe_dark_color.a],
		"stripe_light_color": [stripe_light_color.r, stripe_light_color.g, stripe_light_color.b, stripe_light_color.a],
		"stripe_emission": stripe_emission,
		"stripe_tiling": stripe_tiling,
		"stripe_fill": stripe_fill
	}


func _apply_snapshot(data: Dictionary) -> void:
	# Aplicar configuración determinística desde snapshot
	if data.has("push_velocity"):
		var pv = data["push_velocity"]
		push_velocity = Vector3(pv[0], pv[1], pv[2])
	if data.has("pos"):
		var p = data["pos"]
		global_transform.origin = Vector3(p[0], p[1], p[2])
	if data.has("stripe_dark_color"):
		var sd = data["stripe_dark_color"]
		stripe_dark_color = Color(sd[0], sd[1], sd[2], sd[3])
	if data.has("stripe_light_color"):
		var sl = data["stripe_light_color"]
		stripe_light_color = Color(sl[0], sl[1], sl[2], sl[3])
	if data.has("stripe_emission"):
		stripe_emission = data["stripe_emission"]
	if data.has("stripe_tiling"):
		stripe_tiling = data["stripe_tiling"]
	if data.has("stripe_fill"):
		stripe_fill = data["stripe_fill"]
	# Actualizar shader si existe
	var mat = _ensure_unique_material()
	if mat and mat is ShaderMaterial:
		_update_shader_params(mat)


func restore_snapshot(data: Dictionary) -> void:
	# Guardar si aún no estamos en el árbol
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_apply_snapshot(data)


func step(_dt: float) -> void:
	# Usar get_overlapping_bodies para determinismo (stateless per frame)
	_bodies = get_overlapping_bodies()
	
	var basis := global_transform.basis.orthonormalized()
	var world_push = basis.xform(push_velocity)
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if require_on_floor and body.has_method("is_on_floor") and not body.is_on_floor():
			continue
		
		# Aplicar velocidad externa y marcar como NO estática
		if body.has_method("set_external_velocity"):
			body.set_external_velocity(world_push)
			if body.has_method("set_external_source_is_static"):
				body.set_external_source_is_static(false)
			if debug:
				print("[Conveyor] push to:", body.get_name() if body.has_method("get_name") else body, " vel:", world_push)
		elif body is RigidBody:
			body.add_central_force(world_push * rigid_force_multiplier)
			if debug:
				print("[Conveyor] add_central_force ->", world_push * rigid_force_multiplier, " for:", body)

func _physics_process(delta):
	step(delta)