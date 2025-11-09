extends Node
## Controla los parámetros del Shader de la nota para que esté quieta en el suelo
## y se mueva (bend + flutter) solo cuando se está cargando o en vuelo.

@export var mesh_instance_path: NodePath = NodePath("../MeshInstance3D")
@export var carryable_component_path: NodePath = NodePath("../CarryableComponent")
@export var readable_component_path: NodePath = NodePath("../ReadableComponent")
@export var glow_light_path: NodePath = NodePath("../NotaGlow")
@export var glow_particles_path: NodePath = NodePath("../GlowParticles")
@export var bend_strength_idle: float = 0.0
@export var bend_strength_active: float = 0.85
@export var wave_amp_idle: float = 0.002
@export var wave_amp_active: float = 0.01
@export var wave_freq_active: float = 14.0
@export var wave_speed_active: float = 2.0
@export var raise_factor: float = 1.0
@export var velocity_flutter_threshold: float = 0.2 ## Si la velocidad lineal supera esto, activar efecto en vuelo

var mesh_instance: MeshInstance3D
var carryable_component
var readable_component
var glow_light: OmniLight3D
var glow_particles: GPUParticles3D
var rigid_body: RigidBody3D
var shader_material: ShaderMaterial
var is_carried: bool = false
var has_been_read: bool = false

func _ready():
	mesh_instance = get_node(mesh_instance_path) as MeshInstance3D
	carryable_component = get_node(carryable_component_path)
	readable_component = get_node(readable_component_path)
	glow_light = get_node(glow_light_path) as OmniLight3D
	glow_particles = get_node(glow_particles_path) as GPUParticles3D
	rigid_body = get_parent() as RigidBody3D
	if mesh_instance and mesh_instance.material_override and mesh_instance.material_override is ShaderMaterial:
		shader_material = mesh_instance.material_override
	elif mesh_instance and mesh_instance.get_active_material(0) is ShaderMaterial:
		shader_material = mesh_instance.get_active_material(0)
	else:
		# Intentar obtener el material directamente desde la malla (PrimitiveMesh: .material)
		if mesh_instance and mesh_instance.mesh and "material" in mesh_instance.mesh:
			var mesh_mat = mesh_instance.mesh.material
			if mesh_mat is ShaderMaterial:
				shader_material = mesh_mat
				# Opcional: fijarlo como override para asegurar control por instancia
				mesh_instance.material_override = shader_material
			else:
				push_warning("NoteFXController: El material de la malla no es ShaderMaterial.")
				return
		else:
			push_warning("NoteFXController: No se encontró ShaderMaterial en la malla de la nota.")
			return
	# Intentar conectar señal de carry si existe
	if carryable_component and carryable_component.has_signal("carry_state_changed"):
		carryable_component.carry_state_changed.connect(_on_carry_state_changed)
	# Conectar señal de lectura
	if readable_component and readable_component.has_signal("readable_closed"):
		readable_component.readable_closed.connect(_on_note_read)
	_update_idle()

func _physics_process(_delta):
	if not shader_material:
		return
	# Si está en mano, asegurar estado activo
	if is_carried:
		_update_active()
	else:
		# Detectar si está "volando" (velocidad suficiente y no tocando piso)
		var speed = rigid_body.linear_velocity.length()
		var on_floor = _approx_on_floor()
		if speed > velocity_flutter_threshold and not on_floor:
			_update_active()
		else:
			_update_idle()

func _on_carry_state_changed(carrying: bool):
	is_carried = carrying
	if carrying:
		_update_active()
	else:
		_update_idle()

func _on_note_read():
	has_been_read = true
	if glow_light:
		glow_light.visible = false
	if glow_particles:
		glow_particles.emitting = false

func _update_idle():
	_set_shader_param("bend_strength", bend_strength_idle)
	_set_shader_param("wave_amp", wave_amp_idle)
	# Mantener wave_freq y speed bajos para evitar actividad; wave_amp=0 basta
	_set_shader_param("wave_freq", wave_freq_active)
	_set_shader_param("wave_speed", wave_speed_active)

func _update_active():
	_set_shader_param("bend_strength", bend_strength_active)
	_set_shader_param("wave_amp", wave_amp_active)
	_set_shader_param("wave_freq", wave_freq_active)
	_set_shader_param("wave_speed", wave_speed_active)

func _set_shader_param(param: String, value):
	if shader_material:
		shader_material.set_shader_parameter(param, value)

func _approx_on_floor() -> bool:
	# Chequeo simple: si la velocidad vertical es casi cero y Y global de la nota está cerca de la plataforma.
	# Se podría mejorar con un raycast corto hacia abajo.
	var vy = rigid_body.linear_velocity.y
	if abs(vy) < 0.05:
		# Ajuste según altura de plataforma (0.25 offset usado en escena)
		if rigid_body.global_position.y <= 0.26:
			return true
	return false
