tool
extends Spatial

export(Color) var spark_color: Color = Color(1.0, 0.8, 0.2) setget set_spark_color
export(float, 0.0, 3.0) var brightness: float = 1.0 setget set_brightness
export(float) var emission_rate: float = 10.0
export(bool) var emitting: bool = true setget set_emitting

var particles: CPUParticles
var material: SpatialMaterial
var gradient: Gradient

func _enter_tree():
	particles = get_node_or_null("CPUParticles")
	if particles and particles.mesh:
		material = particles.mesh.surface_get_material(0)
	if particles and particles.color_ramp:
		var ramp = particles.color_ramp
		if ramp is GradientTexture:
			gradient = ramp.gradient
		elif ramp is Gradient:
			gradient = ramp
	_update_in_editor()

func _ready():
	if not Engine.editor_hint:
		particles = get_node_or_null("CPUParticles")
		if particles and particles.mesh:
			material = particles.mesh.surface_get_material(0)
		if particles and particles.color_ramp:
			var ramp = particles.color_ramp
			if ramp is GradientTexture:
				gradient = ramp.gradient
			elif ramp is Gradient:
				gradient = ramp
		update_color()
		update_emission()

func _update_in_editor():
	if Engine.editor_hint:
		update_color()
		if particles:
			particles.emitting = emitting

func update_color():
	var r: float = min(spark_color.r * brightness, 1.0)
	var g: float = min(spark_color.g * brightness, 1.0)
	var b: float = min(spark_color.b * brightness, 1.0)
	
	if particles:
		particles.color = Color(r, g, b, 1.0)
		
		if gradient:
			gradient.set_color(0, Color(min(r + 0.1, 1.0), min(g + 0.1, 1.0), min(b + 0.1, 1.0), 1.0))
			gradient.set_color(1, Color(r, g, b, 0.9))
			gradient.set_color(2, Color(r * 0.6, g * 0.6, b * 0.3, 0.6))
			gradient.set_color(3, Color(r * 0.3, g * 0.15, b * 0.05, 0.0))
	
	if material:
		material.emission = Color(r, g, b, 1.0)
		material.emission_energy = 3.0
		material.albedo_color = Color(r, g, b, 0.9)

func set_spark_color(color: Color):
	spark_color = color
	_update_in_editor()

func set_brightness(value: float):
	brightness = value
	_update_in_editor()

func set_emitting(value: bool):
	emitting = value
	_update_in_editor()

func update_emission():
	if particles:
		particles.emitting = emitting
