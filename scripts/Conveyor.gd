extends Area

export(Vector3) var push_velocity := Vector3(2, 0, 0)
export(bool) var require_on_floor := true
export(Color) var stripe_dark_color = Color(0.07, 0.07, 0.07, 1.0)
export(Color) var stripe_light_color = Color(0.55, 0.52, 0.38, 1.0)
export(float) var stripe_emission = 0.08
export(float) var stripe_tiling = 5.0
export(float) var stripe_fill = 0.45

var _bodies := []

func _ready():
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	# Ajustar shader del mesh para reflejar dirección/velocidad
	if has_node("Mesh"):
		var mesh = $Mesh
		if mesh and mesh.material and mesh.material is ShaderMaterial:
			_update_shader_params(mesh.material)

func _update_shader_params(mat: ShaderMaterial) -> void:
	if not mat:
		return
	var d = Vector2(push_velocity.x, push_velocity.z)
	# Corrige orientación: rota 90° para alinear el flujo visual con la dirección real
	d = Vector2(d.y, -d.x)
	if d.length() > 0.001:
		d = d.normalized()
	mat.set_shader_param("dir", d)
	mat.set_shader_param("speed", max(push_velocity.length(), 0.0) * 0.4)
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

func _on_body_exited(body):
	if body in _bodies:
		_bodies.erase(body)
	if is_instance_valid(body) and body.has_method("set_external_velocity"):
		body.set_external_velocity(Vector3.ZERO)

func _physics_process(_delta):
	var world_push = global_transform.basis.xform(push_velocity)
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if require_on_floor and body.has_method("is_on_floor") and not body.is_on_floor():
			continue
		if body.has_method("set_external_velocity"):
			body.set_external_velocity(world_push)
		elif body is RigidBody:
			body.add_central_force(world_push)
