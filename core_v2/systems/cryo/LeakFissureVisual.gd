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

# Preload explicito en vez de depender del class_name global: en export, el compilador de
# bytecode puede resolver el cache de clases globales en un orden distinto al del editor, y
# referenciar CoolantLeak.State sin esta dependencia declarada puede dejar un .gdc invalido
# para ESTE script en el PCK exportado (mismo sintoma que en CoolantSystemStatusUI.gd: build
# nightly 402, "Loader poll failed" al cargar Dome_Intro.tscn).
const CoolantLeak = preload("res://core_v2/systems/cryo/CoolantLeak.gd")

export(bool) var enabled: bool = true setget set_enabled
export(NodePath) var leak_path: NodePath
export(NodePath) var patch_point_path: NodePath
export(NodePath) var pipe_run_path: NodePath
export(float, 0.1, 2.0) var fissure_radius: float = 0.35
export(Vector3) var spray_direction: Vector3 = Vector3.UP setget set_spray_direction

# Volumen del audio de fuga a intensidad 0 y a intensidad 1 (heredado de FrostEmitter).
const SOUND_DB_MIN := -12.0
const SOUND_DB_MAX := 10.0

var _leak: Object = null
var _patch_point: Object = null
var _pipe_run: Object = null

# Intensidad de grieta efectivamente aplicada. Es estado del nodo a proposito: el binario
# headless de CI usa el rasterizer dummy, donde los ShaderMaterial no guardan parametros y
# get_shader_param() devuelve null, asi que el material no sirve para verificar la decision
# del componente (mismo criterio que test_ice_level.gd).
var _fissure_intensity: float = 0.0

# Decision de emision efectivamente aplicada, mismo motivo que _fissure_intensity. Bajo el
# rasterizer dummy, releer CPUParticles.emitting inmediatamente despues de asignarlo puede
# devolver un valor obsoleto/racoso -- visto en CI y reproducido local con el binario headless
# real (Godot_v3.6.2-stable_linux_headless.64): la misma corrida imprimia mist.emitting=True
# un statement antes de que el assert leyera False para el mismo nodo, sin ningun yield ni
# codigo async entre medio. Es una condicion de carrera del motor bajo ese rasterizer, no un
# bug de logica: la decision que este componente tomo es la fuente de verdad fiable.
var _spray_emitting_decision: bool = false
var _mist_emitting_decision: bool = false

onready var _spray_particles: CPUParticles = get_node_or_null("SprayParticles")
onready var _mist_particles: CPUParticles = get_node_or_null("MistParticles")
onready var _sound: AudioStreamPlayer3D = get_node_or_null("FissureSound")
onready var _gloo_mesh: MeshInstance = get_node_or_null("GlooMesh")

# Presupuesto movil del vapor: 26 quads de ~1.5 m de niebla cubren ~una pantalla
# entera de fillrate por fisura en el Redmi Note 9 Pro (medido: el evento de ruptura
# baja el frame de ~16 ms a ~40 ms). Menos particulas y quads mas chicos mantienen
# la lectura de la pluma a la distancia con la mitad del overdraw.
var _mist_amount_mobile := 14
var _mist_scale_cap_mobile := 0.75

func _is_mobile_profile() -> bool:
	if OS.get_environment("ODISEA_FORCE_MOBILE_PROFILE") in ["1", "true", "yes", "on"]:
		return true
	return OS.get_name() in ["Android", "iOS"]


var _references_resolved := false


func _ready() -> void:
	add_to_group("replay_sync")
	_apply_spray_direction()
	_resolve_references()
	if _mist_particles != null and _is_mobile_profile():
		_mist_particles.amount = _mist_amount_mobile
	_update_visuals()
	# PERF: en Dome_Intro hay ~24 fisuras de autoria y solo 2-3 activas por partida — el
	# resto se queda en HEALTHY toda la partida. _sync_physics_process() decide si sigue
	# tickeando (referencias sin resolver aun, o _leak fuera de HEALTHY) o se duerme hasta
	# que _leak.state_changed la despierte.
	_sync_physics_process()


# Igual que CoolantFlowAdapter/LeakPatchPoint: re-resolver hasta lograrlo, no solo en
# _ready(). add_child() dispara _ready() sincronicamente, y setear los NodePath despues de
# add_child() (patron comun al cablear en la escena, y el que usa el propio harness de
# tests) dejaba _leak/_patch_point/_pipe_run en null para siempre si esto solo corria una
# vez. _sync_physics_process() mantiene el tick prendido mientras falte resolver algo.
func _resolve_references() -> void:
	if _references_resolved:
		return
	if leak_path != null and not leak_path.is_empty():
		_leak = get_node_or_null(leak_path)
	if patch_point_path != null and not patch_point_path.is_empty():
		_patch_point = get_node_or_null(patch_point_path)
	if pipe_run_path != null and not pipe_run_path.is_empty():
		_pipe_run = get_node_or_null(pipe_run_path)

	var leak_ok: bool = _leak != null or leak_path == null or leak_path.is_empty()
	var patch_ok: bool = _patch_point != null or patch_point_path == null or patch_point_path.is_empty()
	var pipe_ok: bool = _pipe_run != null or pipe_run_path == null or pipe_run_path.is_empty()
	if leak_ok and patch_ok and pipe_ok:
		_references_resolved = true
		if _leak != null and _leak.has_signal("state_changed") and not _leak.is_connected("state_changed", self, "_on_leak_state_changed"):
			_leak.connect("state_changed", self, "_on_leak_state_changed")


func _on_leak_state_changed(_new_state = null) -> void:
	_update_visuals()
	_sync_physics_process()


# HEALTHY es el unico estado de CoolantLeak sin timer ni intensidad que evolucionar por si
# solo (mismo criterio que el gate de CoolantLeak._set_state()) — mientras dure, no hace
# falta re-evaluar visuales cada frame; state_changed la despierta cuando cambia.
func _sync_physics_process() -> void:
	if not _references_resolved:
		set_physics_process(true)
		return
	var leak_active: bool = _leak != null and is_instance_valid(_leak) and int(_leak.get_state()) != 0 # State.HEALTHY
	set_physics_process(leak_active)


func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	_resolve_references()
	_update_visuals()
	if _references_resolved:
		_sync_physics_process()


func set_enabled(value: bool) -> void:
	enabled = value
	_update_visuals()


func set_spray_direction(value: Vector3) -> void:
	if value.length_squared() <= 0.000001:
		return
	spray_direction = value.normalized()
	_apply_spray_direction()


func _apply_spray_direction() -> void:
	if spray_direction.length_squared() <= 0.000001:
		spray_direction = Vector3.UP
	var direction: Vector3 = spray_direction.normalized()
	if _spray_particles:
		_spray_particles.direction = direction
	if _mist_particles:
		_mist_particles.direction = direction


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
				_apply_pipe_fissure_uniforms(0.25)

			CoolantLeak.State.LEAKING:
				# Fuga activa: el chorro corre a un régimen fijo (amount/velocity viven en
				# la escena, constantes) — variarlos con la intensidad cada frame es lo que
				# reiniciaba el sistema de partículas todo el tiempo y se leía como "sin vida
				# propia". La intensidad solo modula la grieta del caño, no las partículas.
				_set_particles_emitting(true, true)
				_apply_pipe_fissure_uniforms(leak_intensity)

			CoolantLeak.State.SEALED, CoolantLeak.State.DEPRESSURIZED:
				# SEALED = reparado de verdad; DEPRESSURIZED = la valvula corto el caudal
				# pero el cano sigue roto. Los dos disipan, asi que se dibujan igual: lo
				# que se ve es que deja de escupir, no que quedo sano. El mist se queda
				# activo mientras dura la disipación — set_intensity() (más abajo) es lo
				# que lo va achicando gradualmente; cortarlo acá con set_active(false)
				# lo apagaba de golpe en vez de dejarlo encoger con la intensidad real.
				if leak_intensity > 0.05:
					_set_particles_emitting(true, true)
					_apply_pipe_fissure_uniforms(leak_intensity)
				else:
					_set_particles_emitting(false, false)
					_clear_pipe_fissure_uniforms()

	# Volumen del vapor proporcional a la intensidad real de la fuga, tapada o no —
	# 0 cuando está parchada, la misma curva que ya gobierna la grieta del caño.
	var intensity: float = 0.0 if is_patched else clamp(leak_intensity, 0.0, 1.0)
	if _sound != null:
		_sound.unit_db = lerp(SOUND_DB_MIN, SOUND_DB_MAX, intensity)
	# La pluma se achica con la fuga en vez de cortar de golpe (misma curva que gobierna
	# la grieta del cano). Escalar el nodo escala emision y quads a la vez. En movil el
	# techo de escala ademas recorta el quad base (overdraw, ver _ready).
	if _mist_particles != null:
		var s: float = max(0.05, intensity)
		if _is_mobile_profile():
			s = min(s, _mist_scale_cap_mobile)
		_mist_particles.scale = Vector3(s, s, s)


func _set_particles_emitting(spray_active: bool, mist_active: bool) -> void:
	_spray_emitting_decision = spray_active
	_mist_emitting_decision = mist_active
	if _spray_particles != null:
		_spray_particles.emitting = spray_active
	if _mist_particles != null and _mist_particles.emitting != mist_active:
		_mist_particles.emitting = mist_active
	# El audio ambiente sigue a la pluma. Solo se toca en el flanco: reasignar playing
	# cada tick reiniciaba el loop y se oia como un chasquido.
	if _sound != null and _sound.playing != mist_active:
		if mist_active:
			_sound.play()
		else:
			_sound.stop()


func get_fissure_intensity() -> float:
	return _fissure_intensity


func is_spray_emitting() -> bool:
	return _spray_emitting_decision


func is_mist_emitting() -> bool:
	return _mist_emitting_decision


func _apply_pipe_fissure_uniforms(intensity: float) -> void:
	_fissure_intensity = intensity
	if _pipe_run == null:
		return
	var mat = _pipe_run.get("_material")
	if mat == null:
		return

	# En coordenadas de mundo: el shader compara contra world_pos, que no depende de como
	# este rotada la malla respecto del nodo de la corrida. Pasarlo en espacio del PipeRun
	# ponia el centro a metros del cano (mesh rotado 90 grados) y la grieta no aparecia.
	mat.set_shader_param("fissure_center", global_transform.origin)
	mat.set_shader_param("fissure_radius", fissure_radius)
	mat.set_shader_param("fissure_intensity", intensity)


func _clear_pipe_fissure_uniforms() -> void:
	_fissure_intensity = 0.0
	if _pipe_run == null:
		return
	var mat = _pipe_run.get("_material")
	if mat == null:
		return
	mat.set_shader_param("fissure_intensity", 0.0)


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"fissure_intensity": _fissure_intensity
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("enabled"):
		enabled = bool(data["enabled"])
	if data.has("fissure_intensity"):
		_fissure_intensity = float(data["fissure_intensity"])
	_update_visuals()
