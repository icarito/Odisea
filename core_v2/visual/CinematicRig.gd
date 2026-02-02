tool
extends Spatial
class_name CinematicRigV2

# CinematicRig.gd - Specialized camera node for cinematic sequences
# Se registra automáticamente en el grupo "cinematic_rigs" y crea una Camera hija si falta.

export(bool) var auto_play_animation := true
export(String) var animation_name := "intro"

# Transition settings
export(float) var transition_time := 0.5 # 0.0 for cut

var camera: Camera = null
var anim_player: AnimationPlayer = null

# Estado de transición (similar a SideScrollLogicV2)
var _is_active := false
var _transition_alpha := 0.0
var _source_transform: Transform = Transform()
var _source_fov: float = 70.0
var _player_camera: Camera = null

func _ready():
	# Siempre registrarse en el grupo (útil para búsquedas legacy)
	if not is_in_group("cinematic_rigs"):
		add_to_group("cinematic_rigs")
	
	_ensure_camera()
	_find_anim_player()

func _physics_process(delta):
	if Engine.editor_hint:
		return
	
	# Actualizar transición alpha
	_step_transition(delta)
	
	# Aplicar transición de cámara
	_apply_camera_transition()

func _step_transition(delta: float):
	"""Actualiza el alpha de transición con interpolación suave."""
	var target_alpha = 1.0 if _is_active else 0.0
	if _transition_alpha != target_alpha:
		var speed = 1.0 / max(transition_time, 0.01)
		var step_val = speed * delta
		if _transition_alpha < target_alpha:
			_transition_alpha = min(_transition_alpha + step_val, target_alpha)
		else:
			_transition_alpha = max(_transition_alpha - step_val, target_alpha)
	
	# Si terminó de salir, devolver control a la cámara del jugador
	if not _is_active and _transition_alpha <= 0:
		if _player_camera and is_instance_valid(_player_camera):
			_player_camera.current = true
		_player_camera = null
		set_physics_process(false)

func _get_smooth_alpha() -> float:
	"""Cubic easing (smoothstep): 3t^2 - 2t^3"""
	return _transition_alpha * _transition_alpha * (3.0 - 2.0 * _transition_alpha)

func _apply_camera_transition():
	"""Aplica la interpolación de la cámara durante la transición."""
	if not camera or _transition_alpha <= 0:
		return
	
	var s_alpha = _get_smooth_alpha()
	
	if s_alpha < 1.0 and _player_camera and is_instance_valid(_player_camera):
		# Interpolar entre la cámara del jugador y la cinemática
		var target_transform = camera.global_transform
		var target_fov = camera.fov
		
		# Crear una transformación interpolada
		var interp_transform = _source_transform.interpolate_with(target_transform, s_alpha)
		var interp_fov = lerp(_source_fov, target_fov, s_alpha)
		
		# Aplicar a la cámara cinemática
		camera.global_transform = interp_transform
		camera.fov = interp_fov
		camera.current = true
	elif s_alpha >= 1.0:
		# Transición completa, restaurar transform original de la cámara
		camera.current = true

func _ensure_camera():
	"""Busca o crea una Camera hija automáticamente."""
	# Primero buscar en $Camera
	camera = get_node_or_null("Camera") as Camera
	if camera:
		return
	
	# Buscar cualquier Camera hija
	for child in get_children():
		if child is Camera:
			camera = child
			return
	
	# No hay cámara: crear una automáticamente
	camera = Camera.new()
	camera.name = "Camera"
	add_child(camera)
	if Engine.editor_hint:
		camera.owner = get_tree().edited_scene_root

func _find_anim_player():
	"""Busca un AnimationPlayer hijo."""
	anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player:
		return
	
	for child in get_children():
		if child is AnimationPlayer:
			anim_player = child
			return

func activate(force_current: bool = true):
	if not camera:
		_ensure_camera()
	
	_is_active = true
	
	# Capturar estado de la cámara actual para transición suave
	_player_camera = get_viewport().get_camera()
	if _player_camera and _player_camera != camera:
		_source_transform = _player_camera.global_transform
		_source_fov = _player_camera.fov
	else:
		_source_transform = camera.global_transform
		_source_fov = camera.fov
	
	# Iniciar transición
	if transition_time > 0.01:
		_transition_alpha = 0.0
		camera.current = true  # Tomar control pero interpolar
	elif force_current:
		_transition_alpha = 1.0
		camera.current = true
	
	# Activar physics_process para transición
	set_physics_process(true)

	if anim_player and auto_play_animation and animation_name != "":
		if anim_player.has_animation(animation_name):
			anim_player.play(animation_name)

func deactivate():
	_is_active = false
	if anim_player:
		anim_player.stop()
	# La transición de salida se maneja en _step_transition()

func get_camera() -> Camera:
	if not camera:
		_ensure_camera()
	return camera
