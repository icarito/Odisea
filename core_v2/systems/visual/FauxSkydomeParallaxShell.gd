extends Spatial
class_name FauxSkydomeParallaxShell

# FD-041: FauxSkydomeParallaxShell
# Fondo visual barato que simula profundidad de nave y espiral
# mediante shader de parallax de 3 capas.

export(float) var radius := 3500.0
export(float) var height := 6000.0
export(int, 8, 128) var radial_segments := 48
export(Texture) var hull_texture: Texture
export(Texture) var grid_texture: Texture
export(Texture) var lights_texture: Texture
export(Vector2) var uv_scale := Vector2(12.0, 4.0)
export(bool) var use_procedural_fallbacks := true
export(float, 0.0, 8.0) var brightness := 1.35
export(float, 0.0, 4.0) var parallax_strength := 1.0
export(int, "Composite", "Hull", "Grid", "Lights", "UV") var debug_mode := 0

var _mesh_instance: MeshInstance
var _material: ShaderMaterial

func _ready():
	_setup_mesh()
	_update_material()

func _setup_mesh():
	_mesh_instance = MeshInstance.new()
	_mesh_instance.name = "ShellMesh"
	
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.rings = 1
	mesh.radial_segments = radial_segments
	
	_mesh_instance.mesh = mesh
	_mesh_instance.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = max(radius, height)
	add_child(_mesh_instance)


func _update_material():
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/faux_skydome_parallax.shader")
	_material.set_shader_param("hull_tex", _resolve_texture(hull_texture, "hull"))
	_material.set_shader_param("grid_tex", _resolve_texture(grid_texture, "grid"))
	_material.set_shader_param("lights_tex", _resolve_texture(lights_texture, "lights"))
	_material.set_shader_param("uv_scale", uv_scale)
	_material.set_shader_param("brightness", brightness)
	_material.set_shader_param("parallax_strength", parallax_strength)
	_material.set_shader_param("debug_mode", debug_mode)
	_mesh_instance.material_override = _material


func set_debug_mode(value: int) -> void:
	debug_mode = clamp(value, 0, 4)
	if _material:
		_material.set_shader_param("debug_mode", debug_mode)


func set_debug_brightness(value: float) -> void:
	brightness = max(0.0, value)
	if _material:
		_material.set_shader_param("brightness", brightness)


func _resolve_texture(texture: Texture, fallback_kind: String) -> Texture:
	if texture:
		return texture
	if not use_procedural_fallbacks:
		return null
	match fallback_kind:
		"hull":
			return _make_hull_texture()
		"grid":
			return _make_grid_texture()
		"lights":
			return _make_lights_texture()
	return null


func _make_hull_texture() -> Texture:
	var image := Image.new()
	image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in range(128):
		for x in range(128):
			var panel := 0.11 if ((x / 32 + y / 32) % 2 == 0) else 0.075
			var seam := x % 32 == 0 or y % 32 == 0
			var color := Color(panel, panel + 0.015, panel + 0.035, 1.0)
			if seam:
				color = Color(0.025, 0.035, 0.045, 1.0)
			image.set_pixel(x, y, color)
	image.unlock()
	return _texture_from_image(image)


func _make_grid_texture() -> Texture:
	var image := Image.new()
	image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in range(128):
		for x in range(128):
			var major := x % 32 == 0 or y % 32 == 0
			var minor := x % 16 == 0 or y % 16 == 0
			var alpha := 0.0
			if major:
				alpha = 0.65
			elif minor:
				alpha = 0.22
			image.set_pixel(x, y, Color(0.25, 0.85, 0.95, alpha))
	image.unlock()
	return _texture_from_image(image)


func _make_lights_texture() -> Texture:
	var image := Image.new()
	image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in range(128):
		for x in range(128):
			var alpha := 0.0
			var local_x := x % 32
			var local_y := y % 32
			if local_x >= 14 and local_x <= 17 and local_y >= 14 and local_y <= 17:
				alpha = 0.85
			elif local_x >= 13 and local_x <= 18 and local_y >= 13 and local_y <= 18:
				alpha = 0.28
			image.set_pixel(x, y, Color(1.0, 0.36, 0.12, alpha))
	image.unlock()
	return _texture_from_image(image)


func _texture_from_image(image: Image) -> Texture:
	var texture := ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_REPEAT | Texture.FLAG_MIPMAPS)
	return texture
