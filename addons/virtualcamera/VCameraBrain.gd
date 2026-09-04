tool
extends Camera

class_name VCameraBrain, "res://addons/virtualcamera/VCameraBrain.svg"

export var target_group : String = "vcamera"
var last_active_vcamera : VCamera = null
var transition_time : float = 0.0
var transition_start_transform : Transform
var transition_start_fov : float
var transition_start_near : float
var transition_start_far : float

# Cache del perfilador: buscar el autoload por path en cada tick cuesta, y ese costo
# alcanza para que un replay pierda pasos de fisica y derive. Se resuelve una vez.
var _pm_perfil = null
var _pm_perfil_buscado := false

func get_highest_priority_vcamera() -> VCamera:
	var cam = last_active_vcamera if last_active_vcamera and last_active_vcamera.enabled else null
	var highest_priority = 0 if cam == null else cam.priority
	var vcams = get_tree().get_nodes_in_group(self.target_group)
	for vcam in vcams:
		if vcam is VCamera and vcam.enabled and (cam == null or vcam.priority > highest_priority):
			cam = vcam
			highest_priority = vcam.priority
	return cam

func begin_transition(vcam : VCamera):
	transition_start_transform = global_transform
	transition_start_fov = fov
	transition_start_near = near
	transition_start_far = far
	# Always start blending from 0 so both first-entry and camera-to-camera transitions interpolate.
	transition_time = 0.0
	last_active_vcamera = vcam

func process_transition(vcam : VCamera):
	if vcam.transition_time <= 0.0:
		snap_transition(vcam)
		return
	var t = transition_time / vcam.transition_time
	t = ease(t, vcam.transition_ease)
	global_transform = transition_start_transform.interpolate_with(vcam.global_transform, t)
	fov = lerp(transition_start_fov, vcam.fov, t)
	near = lerp(transition_start_near, vcam.near, t)
	far = lerp(transition_start_far, vcam.far, t)

func snap_transition(vcam : VCamera):
	transition_time = vcam.transition_time
	global_transform = vcam.global_transform
	fov = vcam.fov
	near = vcam.near
	far = vcam.far

func _physics_process(delta : float):
	# Envoltorio de perfilado (ver PerformanceMonitor.perfil_corrida_iniciar): el cuerpo
	# puede tener varios return, asi que se mide desde afuera y no por dentro.
	if not _pm_perfil_buscado:
		_pm_perfil_buscado = true
		_pm_perfil = get_node_or_null("/root/PerformanceMonitor")
	if _pm_perfil != null and _pm_perfil._perfil_corrida_on:
		_pm_perfil.perfil_inicio("VCameraBrain")
		_paso_fisica(delta)
		_pm_perfil.perfil_fin("VCameraBrain")
		return
	_paso_fisica(delta)

func _paso_fisica(delta : float):
	var vcam = get_highest_priority_vcamera()
	if vcam == null:
		return
	if not is_instance_valid(last_active_vcamera):
		last_active_vcamera = null
	if last_active_vcamera != vcam:
		begin_transition(vcam)
	transition_time = min(transition_time + delta, vcam.transition_time)
	if transition_time < vcam.transition_time:
		process_transition(vcam)
	else:
		snap_transition(vcam)
