extends Spatial

# HoloProjectorBeamV2.gd - Haz piramidal del proyector de un terminal holografico.
# Reemplaza los CPUParticles viejos por UN solo mesh additive (core_v2/visual/volumetric_cone.shader):
# barato y sin rand, asi que no rompe el determinismo (es decorativo de todos modos).
#
# Se expone `emitting` (setget) para mantener el contrato que usaban los consumidores:
# HoloTerminalV2/TerminalHUDBridge hacian `particles.emitting = is_active`.

export(bool) var emitting := true setget set_emitting
export(Color) var color := Color(0.35, 0.95, 1.0, 0.55) setget set_color
export(float, 0.0, 1.0) var alpha_multiplier := 0.55
export(float, 0.1, 5.0) var falloff_exponent := 1.6
# 0.0 = borde duro; >0 difumina la silueta de la piramide.
export(float, 0.0, 1.0) var edge_softness := 0.4
# Altura (proyector -> pantalla). <= 0 = autocalcular contra ScreenContainer/ScreenMesh.
export(float) var beam_length := 0.0
# Radio de la base (semi-ancho del haz arriba). <= 0 = fraccion del ancho de la pantalla.
export(float) var base_radius := 0.0
export(float, 0.0, 1.0) var base_radius_screen_fraction := 0.35
export(int, 3, 24) var radial_segments := 12

var _mesh: MeshInstance = null
var _material: ShaderMaterial = null
var _pending_emitting := true

func _ready() -> void:
	_build()
	_fit()
	_apply_material()
	set_emitting(_pending_emitting if _mesh == null else emitting)

func _build() -> void:
	if _mesh != null:
		return
	var cone := CylinderMesh.new()
	# Apice (bottom_radius 0) abajo = proyector; base ancha arriba = pantalla.
	cone.bottom_radius = 0.0
	cone.top_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = radial_segments
	cone.rings = 1
	_mesh = MeshInstance.new()
	_mesh.name = "BeamMesh"
	_mesh.mesh = cone
	# El proyector es un CSGBox fino: que el haz no pelee por z-detras de el.
	_mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = preload("res://core_v2/visual/volumetric_cone.shader")
	_mesh.set_surface_material(0, _material)
	add_child(_mesh)

func _fit() -> void:
	if _mesh == null:
		return
	var length: float = float(beam_length)
	var radius: float = float(base_radius)
	if length <= 0.0 or radius <= 0.0:
		var size := _measure_screen()
		if length <= 0.0:
			length = size.y if size.y > 0.01 else 1.2
		if radius <= 0.0:
			radius = size.x * base_radius_screen_fraction if size.x > 0.01 else 0.4
	# Godot 3: CylinderMesh mide 1.0 de alto. Base (top) arriba, apice (bottom) en el origen.
	_mesh.scale = Vector3(radius, length, radius)
	_mesh.translation = Vector3(0.0, length * 0.5, 0.0)

# Busca la pantalla del terminal subiendo por los padres; devuelve (ancho, alto) del beam en
# espacio local: ancho = ancho de la pantalla, alto = distancia vertical proyector->pantalla.
func _measure_screen() -> Vector2:
	var screen := _find_screen_mesh()
	if screen == null:
		return Vector2.ZERO
	var width := 0.0
	if "width" in screen:
		width = float(screen.width)
	var top_y: float = float(screen.global_transform.origin.y - global_transform.origin.y)
	if top_y < 0.05:
		top_y = 1.2
	return Vector2(width, top_y)

func _find_screen_mesh() -> Node:
	var node := get_parent()
	while node != null:
		var mesh := node.get_node_or_null("ScreenContainer/ScreenMesh")
		if mesh != null:
			return mesh
		node = node.get_parent()
	return null

func _apply_material() -> void:
	if _material == null:
		return
	var alpha: float = float(alpha_multiplier)
	var segments: int = int(radial_segments)
	# Low tier (Mali): el haz es un transparente grande; se atenua y se simplifica.
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate != null and gate.has_method("is_low_tier") and gate.is_low_tier():
		alpha *= 0.5
		segments = 6
	if _mesh != null and _mesh.mesh is CylinderMesh:
		(_mesh.mesh as CylinderMesh).radial_segments = segments
	_material.set_shader_param("color", Color(color.r, color.g, color.b, color.a))
	_material.set_shader_param("alpha_multiplier", alpha)
	_material.set_shader_param("falloff_exponent", falloff_exponent)
	_material.set_shader_param("edge_softness", edge_softness)
	# CylinderMesh llega a UV.y = 0.5 en el lateral: 2.0 hace que el falloff llegue a 0 en la punta.
	_material.set_shader_param("uv_length_scale", 2.0)
	_material.set_shader_param("use_mask", false)

func set_emitting(value: bool) -> void:
	emitting = value
	_pending_emitting = value
	visible = value
	if _mesh != null:
		_mesh.visible = value

func set_color(value: Color) -> void:
	color = value
	if _material != null:
		_material.set_shader_param("color", Color(value.r, value.g, value.b, value.a))
