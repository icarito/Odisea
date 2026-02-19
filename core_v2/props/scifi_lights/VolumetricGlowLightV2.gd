tool
extends StaticBody

export(Color) var glow_color: Color = Color(1.0, 0.5, 0.0) setget set_glow_color
export(float, 0.1, 10.0) var glow_intensity: float = 3.0 setget set_glow_intensity
export(float, 0.0, 10.0) var pulse_speed: float = 1.0 setget set_pulse_speed
export(float, 0.0, 1.0) var pulse_amount: float = 0.3 setget set_pulse_amount
export(float) var light_range: float = 4.0 setget set_light_range
export(float) var light_energy: float = 2.0 setget set_light_energy

onready var mesh_instance: MeshInstance = $GlowMesh
onready var omni_light: OmniLight = $OmniLight
onready var material: ShaderMaterial

func _ready():
	if mesh_instance and mesh_instance.material_override is ShaderMaterial:
		material = mesh_instance.material_override
		_apply_shader_params()
	
	if omni_light:
		_apply_light_params()

func _apply_shader_params():
	if material:
		material.set_shader_param("glow_color", glow_color)
		material.set_shader_param("intensity", glow_intensity)
		material.set_shader_param("pulse_speed", pulse_speed)
		material.set_shader_param("pulse_amount", pulse_amount)

func _apply_light_params():
	if omni_light:
		omni_light.light_color = glow_color
		omni_light.omni_range = light_range
		omni_light.light_energy = light_energy

func set_glow_color(color: Color):
	glow_color = color
	if material:
		material.set_shader_param("glow_color", color)
	if omni_light:
		omni_light.light_color = color

func set_glow_intensity(value: float):
	glow_intensity = value
	if material:
		material.set_shader_param("intensity", value)

func set_pulse_speed(value: float):
	pulse_speed = value
	if material:
		material.set_shader_param("pulse_speed", value)

func set_pulse_amount(value: float):
	pulse_amount = value
	if material:
		material.set_shader_param("pulse_amount", value)

func set_light_range(value: float):
	light_range = value
	if omni_light:
		omni_light.omni_range = value

func set_light_energy(value: float):
	light_energy = value
	if omni_light:
		omni_light.light_energy = value
