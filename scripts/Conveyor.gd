extends Area

export(Vector3) var push_velocity := Vector3(2, 0, 0)
export(bool) var require_on_floor := false
export(float) var rigid_force_multiplier := 8.0
export(bool) var debug := true
export(Color) var stripe_dark_color = Color(0.18, 0.18, 0.18, 1.0)
export(Color) var stripe_light_color = Color(0.32, 0.32, 0.30, 1.0)
export(float) var stripe_emission = 0.04
export(float) var stripe_tiling = 4.0
export(float) var stripe_fill = 0.35

var _bodies := []

func _ready():
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	# Ajustar shader del mesh para reflejar dirección/velocidad
	if has_node("Mesh"):
		var mesh = $Mesh
		if mesh and mesh.material and mesh.material is ShaderMaterial:
			_update_shader_params(mesh.material)
			if debug:
				print("[Conveyor] Shader params updated dir=", Vector2(push_velocity.x, push_velocity.z), " speed=", push_velocity.length())

func _update_shader_params(mat: ShaderMaterial) -> void:
	if not mat:
		return
	var d = Vector2(push_velocity.x, push_velocity.z)
	if d.length() > 0.001:
		d = d.normalized()
	# Rotar 90° para alinear con el mapeo UV (top face X/Z)
	# e invertir para que el desplazamiento visual coincida con el empuje
	var d_uv = Vector2(d.y, -d.x)
	mat.set_shader_param("dir", -d_uv)
	# Velocidad visual igual a la magnitud del empuje
	mat.set_shader_param("speed", max(push_velocity.length(), 0.0))
	mat.set_shader_param("color_a", stripe_dark_color)
	mat.set_shader_param("color_b", stripe_light_color)
	mat.set_shader_param("emission", stripe_emission)
	mat.set_shader_param("tiling", stripe_tiling)
	mat.set_shader_param("fill", stripe_fill)

func set_push_velocity(v: Vector3) -> void:
	push_velocity = v
	if has_node("Mesh") and $Mesh.material and $Mesh.material is ShaderMaterial:
		_update_shader_params($Mesh.material)

func set_stripe_colors(dark: Color, light: Color) -> void:
	stripe_dark_color = dark
	stripe_light_color = light
	if has_node("Mesh") and $Mesh.material and $Mesh.material is ShaderMaterial:
		_update_shader_params($Mesh.material)

func _on_body_entered(body):
	if body in _bodies:
		return
	_bodies.append(body)
	if debug:
		print("[Conveyor] body_entered:", body, " total=", _bodies.size())

func _on_body_exited(body):
	if body in _bodies:
		_bodies.erase(body)
		if debug:
			print("[Conveyor] body_exited:", body, " total=", _bodies.size())
	if is_instance_valid(body) and body.has_method("set_external_velocity"):
		body.set_external_velocity(Vector3.ZERO)
		if debug:
			print("[Conveyor] reset external velocity to ZERO for:", body)

func _physics_process(_delta):
	# Usar base ortonormalizada para evitar escalamientos del transform
	var basis := global_transform.basis.orthonormalized()
	var world_push = basis.xform(push_velocity)
	var _debug_accum := 0.0
	if debug:
		_debug_accum += _delta
		if _debug_accum >= 0.25:
			print("[Conveyor] world_push=", world_push, " bodies=", _bodies.size())
			_debug_accum = 0.0
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if require_on_floor and body.has_method("is_on_floor") and not body.is_on_floor():
			continue
		if body.has_method("set_external_velocity"):
			# Similar a MovingPlatform: comunicar velocidad externa cada frame
			body.set_external_velocity(world_push)
			if debug:
				_debug_accum += _delta
				if _debug_accum >= 0.25:
					print("[Conveyor] set_external_velocity ->", world_push, " for:", body)
					_debug_accum = 0.0
		elif body is RigidBody:
			# Empuje para objetos de física. Multiplicador configurable.
			body.add_central_force(world_push * rigid_force_multiplier)
			if debug:
				_debug_accum += _delta
				if _debug_accum >= 0.25:
					print("[Conveyor] add_central_force ->", world_push * rigid_force_multiplier, " for:", body)
					_debug_accum = 0.0
		elif body is RigidBody:
			body.add_central_force(world_push)
