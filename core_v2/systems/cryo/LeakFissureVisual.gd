extends Spatial
class_name LeakFissureVisual

# LeakFissureVisual.gd — Componente visual para la fisura de refrigerante (FD-268).
#
# Se ubica en la posición de la fisura. Lee el estado de CoolantLeak y LeakPatchPoint
# únicamente por API pública y maneja:
#   1. Los uniforms de grieta en el material de la PipeCoolantRun.
#   2. El chorro de refrigerante con CPUParticles (GLES2 safe).
#   3. El parche de gloo cuando la fisura está tapada.
#
# Pertenece al grupo 'replay_sync' para guardar/restaurar su estado de forma determinista.

export(bool) var enabled: bool = true setget set_enabled
export(NodePath) var leak_path: NodePath
export(NodePath) var patch_point_path: NodePath
export(NodePath) var pipe_run_path: NodePath
export(float, 0.1, 2.0) var fissure_radius: float = 0.35

var _leak: Object = null
var _patch_point: Object = null
var _pipe_run: Object = null

onready var _spray_particles: CPUParticles = get_node_or_null("SprayParticles")
onready var _mist_particles: CPUParticles = get_node_or_null("MistParticles")
onready var _gloo_mesh: MeshInstance = get_node_or_null("GlooMesh")


func _ready() -> void:
	add_to_group("replay_sync")

	if leak_path != null and not leak_path.is_empty():
		_leak = get_node_or_null(leak_path)
	if patch_point_path != null and not patch_point_path.is_empty():
		_patch_point = get_node_or_null(patch_point_path)
	if pipe_run_path != null and not pipe_run_path.is_empty():
		_pipe_run = get_node_or_null(pipe_run_path)

	_update_visuals()


func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	_update_visuals()


func set_enabled(value: bool) -> void:
	enabled = value
	_update_visuals()


func _update_visuals() -> void:
	if not enabled or not is_inside_tree():
		_set_particles_emitting(false, false)
		if _gloo_mesh:
			_gloo_mesh.visible = false
		_clear_pipe_fissure_uniforms()
		return

	var is_patched := false
	if _patch_point != null and _patch_point.has_method("is_patched"):
		is_patched = _patch_point.is_patched()

	var leak_state: int = 0 # State.HEALTHY = 0
	var leak_intensity := 0.0
	if _leak != null:
		if _leak.has_method("get_state"):
			leak_state = _leak.get_state()
		if _leak.has_method("get_leak_intensity"):
			leak_intensity = _leak.get_leak_intensity()

	# 1. Parche de Gloo
	if _gloo_mesh != null:
		_gloo_mesh.visible = is_patched

	# 2. Partículas y Shader de grieta
	if is_patched:
		# Si está parcheado, la grieta se tapa y el chorro se corta.
		_set_particles_emitting(false, false)
		_clear_pipe_fissure_uniforms()
	else:
		# Constantes del enum, no enteros pelados: FD-266 agrego DEPRESSURIZED a
		# CoolantLeak.State y un match sobre numeros se desalinea en silencio ante el
		# proximo estado nuevo — sin romper ningun test, mostrando el estado equivocado.
		match leak_state:
			CoolantLeak.State.HEALTHY:
				_set_particles_emitting(false, false)
				_clear_pipe_fissure_uniforms()

			CoolantLeak.State.WARNING:
				# Fase de condensación previa a la rotura: niebla leve
				_set_particles_emitting(false, true)
				if _mist_particles:
					_mist_particles.amount = 8
				_apply_pipe_fissure_uniforms(0.25)

			CoolantLeak.State.LEAKING:
				# Fuga activa con chorro a presión según la intensidad
				_set_particles_emitting(true, true)
				if _spray_particles:
					_spray_particles.amount = int(clamp(12.0 + leak_intensity * 28.0, 8.0, 40.0))
					_spray_particles.initial_velocity = 2.5 + leak_intensity * 3.5
				if _mist_particles:
					_mist_particles.amount = int(clamp(6.0 + leak_intensity * 14.0, 4.0, 20.0))
				_apply_pipe_fissure_uniforms(leak_intensity)

			CoolantLeak.State.SEALED, CoolantLeak.State.DEPRESSURIZED:
				# SEALED = reparado de verdad; DEPRESSURIZED = la valvula corto el caudal
				# pero el cano sigue roto. Los dos disipan, asi que se dibujan igual: lo
				# que se ve es que deja de escupir, no que quedo sano.
				if leak_intensity > 0.05:
					_set_particles_emitting(true, false)
					if _spray_particles:
						_spray_particles.amount = int(clamp(leak_intensity * 20.0, 4.0, 20.0))
					_apply_pipe_fissure_uniforms(leak_intensity)
				else:
					_set_particles_emitting(false, false)
					_clear_pipe_fissure_uniforms()


func _set_particles_emitting(spray_active: bool, mist_active: bool) -> void:
	if _spray_particles != null:
		_spray_particles.emitting = spray_active
	if _mist_particles != null:
		_mist_particles.emitting = mist_active


func _apply_pipe_fissure_uniforms(intensity: float) -> void:
	if _pipe_run == null:
		return
	var mat = _pipe_run.get("_material")
	if mat == null:
		return

	# Convertir posición global de la fisura a espacio local de la corrida/tramo
	var local_fissure_pos: Vector3 = _pipe_run.to_local(global_transform.origin)

	mat.set_shader_param("fissure_center", local_fissure_pos)
	mat.set_shader_param("fissure_radius", fissure_radius)
	mat.set_shader_param("fissure_intensity", intensity)


func _clear_pipe_fissure_uniforms() -> void:
	if _pipe_run == null:
		return
	var mat = _pipe_run.get("_material")
	if mat == null:
		return
	mat.set_shader_param("fissure_intensity", 0.0)


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"enabled": enabled
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("enabled"):
		enabled = bool(data["enabled"])
	_update_visuals()
