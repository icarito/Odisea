tool
extends Spatial

export(Color) var hologram_color: Color = Color(0.0, 1.0, 0.5) setget set_hologram_color
export(float, 0.0, 10.0) var scanline_speed: float = 2.0 setget set_scanline_speed
export(float, 1.0, 50.0) var scanline_density: float = 20.0 setget set_scanline_density
export(float, 0.0, 20.0) var flicker_speed: float = 5.0 setget set_flicker_speed
export(float, 0.0, 1.0) var base_alpha: float = 0.7 setget set_base_alpha
export(bool) var active: bool = true setget set_active

onready var mesh_instance: MeshInstance = $HologramMesh
onready var omni_light: OmniLight = $OmniLight
onready var material: ShaderMaterial

func _ready():
	if mesh_instance and mesh_instance.material_override is ShaderMaterial:
		material = mesh_instance.material_override
		update_material()
	
	if omni_light:
		omni_light.light_color = hologram_color

func update_material():
	if material:
		material.set_shader_param("hologram_color", hologram_color)
		material.set_shader_param("scanline_speed", scanline_speed)
		material.set_shader_param("scanline_density", scanline_density)
		material.set_shader_param("flicker_speed", flicker_speed)
		material.set_shader_param("alpha", base_alpha if active else 0.0)

func set_hologram_color(color: Color):
	hologram_color = color
	update_material()
	if omni_light:
		omni_light.light_color = color

func set_scanline_speed(value: float):
	scanline_speed = value
	update_material()

func set_scanline_density(value: float):
	scanline_density = value
	update_material()

func set_flicker_speed(value: float):
	flicker_speed = value
	update_material()

func set_base_alpha(value: float):
	base_alpha = value
	update_material()

func set_active(value: bool):
	active = value
	update_material()
	if omni_light:
		omni_light.visible = active
