tool
extends Path
class_name CinematicPathRig

# CinematicPathRig.gd - Rig cinemático que sigue un Path para secuencias de "filmación"
# Incluye Camera, PathFollow y AnimationPlayer pre-configurados.

# --- CONFIGURACIÓN GENERAL ---
export(float, 0.1, 60.0) var duration := 5.0 setget set_duration
export(bool) var loop := false
export(bool) var auto_play := false
export(bool) var look_ahead := true  # La cámara mira hacia adelante del path

# --- SEGUIMIENTO DE JUGADOR ---
export(bool) var track_player := false  # La cámara siempre mira al jugador
export(bool) var follow_player_on_path := false  # La cámara se mueve a lo largo del path para estar cerca del jugador
export(float, 0.1, 20.0) var follow_speed := 5.0  # Velocidad de seguimiento suave
export(Vector3) var player_offset := Vector3(0, 1.5, 0)  # Offset para apuntar (altura del pecho)

# --- CONFIGURACIÓN DE CÁMARA ---
export(float, 10.0, 120.0) var fov := 70.0 setget set_fov
export(float, 0.01, 10.0) var near := 0.1
export(float, 100.0, 10000.0) var far := 1000.0

# --- TRANSICIÓN ---
export(float, 0.0, 5.0) var transition_time := 0.5

# --- PREVIEW EN EDITOR ---
export(float, 0.0, 1.0) var preview_position := 0.0 setget set_preview_position

# Referencias internas
var path_follow: PathFollow = null
var camera: Camera = null
var anim_player: AnimationPlayer = null
var _player_node: Spatial = null
var _target_offset := 0.0  # Offset objetivo para seguimiento suave

# Estado de transición (similar a SideScrollLogicV2)
var _is_active := false
var _transition_alpha := 0.0
var _source_transform: Transform = Transform()
var _source_fov: float = 70.0
var _player_camera: Camera = null
var _transition_camera: Camera = null  # Cámara temporal para transiciones

func _ready():
	if not is_in_group("cinematic_rigs"):
		add_to_group("cinematic_rigs")
	
	_ensure_nodes()
	_setup_animation()
	
	if not Engine.editor_hint:
		set_physics_process(track_player or follow_player_on_path)
	
	if auto_play and not Engine.editor_hint:
		play()

func _physics_process(delta):
	if Engine.editor_hint:
		return
	
	# Si no estamos activos y la transición terminó, no hacer nada
	if not _is_active and _transition_alpha <= 0:
		return
	
	# Actualizar transición alpha
	_step_transition(delta)
	
	var s_alpha = _get_smooth_alpha()
	var in_transition = s_alpha > 0 and s_alpha < 1.0 and _player_camera and is_instance_valid(_player_camera)
	
	# Buscar jugador si no lo tenemos
	if not _player_node or not is_instance_valid(_player_node):
		_find_player()
		if not _player_node:
			return
	
	# Seguir al jugador a lo largo del path
	if follow_player_on_path and curve and path_follow:
		var player_pos = _player_node.global_transform.origin
		# Convertir posición global del jugador a local del Path
		var local_pos = global_transform.affine_inverse().xform(player_pos)
		# Encontrar el offset más cercano en la curva
		var closest_offset = curve.get_closest_offset(local_pos)
		var curve_length = curve.get_baked_length()
		if curve_length > 0:
			_target_offset = closest_offset / curve_length
			# Interpolar suavemente hacia el objetivo
			path_follow.unit_offset = lerp(path_follow.unit_offset, _target_offset, follow_speed * delta)
	
	# Manejar transición de cámara
	if in_transition:
		# Durante la transición, usar una cámara de transición separada
		_apply_transition_camera(s_alpha)
	elif _is_active and camera:
		# Transición completa - usar cámara del path directamente
		camera.current = true
		
		# La cámara está como hija de PathFollow, su posición local debe ser 0
		# pero su rotación puede cambiar si track_player está activo
		camera.transform.origin = Vector3.ZERO
		
		# Hacer que la cámara mire al jugador (después de posicionarla)
		if track_player:
			var target_pos = _player_node.global_transform.origin + player_offset
			camera.look_at(target_pos, Vector3.UP)

func _apply_transition_camera(alpha: float):
	"""Aplica la transición usando una cámara temporal sin afectar la cámara del path."""
	if not _transition_camera:
		_transition_camera = Camera.new()
		_transition_camera.name = "TransitionCamera"
		add_child(_transition_camera)
	
	# Calcular posición objetivo (donde está la cámara del path según el PathFollow)
	var target_transform = path_follow.global_transform if path_follow else global_transform
	var target_fov = fov
	
	# Interpolar desde la posición origen hacia el objetivo
	var interp_transform = _source_transform.interpolate_with(target_transform, alpha)
	var interp_fov = lerp(_source_fov, target_fov, alpha)
	
	_transition_camera.global_transform = interp_transform
	_transition_camera.fov = interp_fov
	_transition_camera.current = true

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
		# Limpiar cámara de transición
		if _transition_camera:
			_transition_camera.queue_free()
			_transition_camera = null
		
		if _player_camera and is_instance_valid(_player_camera):
			print("[CinematicPathRig] Restaurando cámara del jugador: ", _player_camera.get_path())
			_player_camera.current = true
		else:
			# Buscar la cámara del jugador si no la tenemos
			var player_cam = _find_player_camera()
			if player_cam:
				print("[CinematicPathRig] Buscando y restaurando cámara: ", player_cam.get_path())
				player_cam.current = true
		_player_camera = null
		set_physics_process(false)  # Ya no necesitamos procesar

func _get_smooth_alpha() -> float:
	"""Cubic easing (smoothstep): 3t^2 - 2t^3"""
	return _transition_alpha * _transition_alpha * (3.0 - 2.0 * _transition_alpha)

func _find_player_camera() -> Camera:
	"""Busca específicamente la cámara del jugador (no cualquier cámara activa)."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var player = players[0]
		# Buscar en rutas comunes para la cámara del jugador
		var cam = player.get_node_or_null("CameraRig/SpringArm/Camera") as Camera
		if cam:
			return cam
		cam = player.get_node_or_null("CameraRig/Camera") as Camera
		if cam:
			return cam
		cam = player.get_node_or_null("Camera") as Camera
		if cam:
			return cam
		# Buscar cualquier Camera descendiente
		cam = _find_camera_in_children(player)
		if cam:
			return cam
	return null

func _find_camera_in_children(node: Node) -> Camera:
	"""Busca recursivamente una Camera en los hijos del nodo."""
	for child in node.get_children():
		if child is Camera:
			return child as Camera
		var found = _find_camera_in_children(child)
		if found:
			return found
	return null

func _find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player_node = players[0] as Spatial

func _ensure_nodes():
	# PathFollow
	path_follow = get_node_or_null("PathFollow") as PathFollow
	if not path_follow:
		path_follow = PathFollow.new()
		path_follow.name = "PathFollow"
		path_follow.loop = false
		add_child(path_follow)
		if Engine.editor_hint:
			path_follow.owner = get_tree().edited_scene_root
	
	# Configurar rotation_mode basado en opciones
	_update_rotation_mode()
	
	# Camera
	camera = path_follow.get_node_or_null("Camera") as Camera
	if not camera:
		camera = Camera.new()
		camera.name = "Camera"
		camera.fov = fov
		camera.near = near
		camera.far = far
		path_follow.add_child(camera)
		if Engine.editor_hint:
			camera.owner = get_tree().edited_scene_root
	
	# AnimationPlayer
	anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		add_child(anim_player)
		if Engine.editor_hint:
			anim_player.owner = get_tree().edited_scene_root

func _update_rotation_mode():
	if not path_follow:
		return
	# Si track_player está activo, no rotamos con el path (lo hace look_at)
	if track_player:
		path_follow.rotation_mode = PathFollow.ROTATION_NONE
	elif look_ahead:
		path_follow.rotation_mode = PathFollow.ROTATION_ORIENTED
	else:
		path_follow.rotation_mode = PathFollow.ROTATION_NONE

func _setup_animation():
	if not anim_player:
		return
	
	# Crear o actualizar la animación "dolly"
	var anim: Animation
	if anim_player.has_animation("dolly"):
		anim = anim_player.get_animation("dolly")
	else:
		anim = Animation.new()
		anim_player.add_animation("dolly", anim)
	
	anim.length = duration
	anim.loop = loop
	
	# Track para unit_offset del PathFollow
	var track_idx := -1
	for i in range(anim.get_track_count()):
		if anim.track_get_path(i) == NodePath("PathFollow:unit_offset"):
			track_idx = i
			break
	
	if track_idx == -1:
		track_idx = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, NodePath("PathFollow:unit_offset"))
	
	# Limpiar keys existentes
	while anim.track_get_key_count(track_idx) > 0:
		anim.track_remove_key(track_idx, 0)
	
	# Añadir keyframes: 0 al inicio, 1 al final
	anim.track_insert_key(track_idx, 0.0, 0.0)
	anim.track_insert_key(track_idx, duration, 1.0)
	anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)

# --- SETTERS PARA EDITOR ---
func set_duration(val: float):
	duration = val
	if anim_player and anim_player.has_animation("dolly"):
		_setup_animation()

func set_fov(val: float):
	fov = val
	if camera:
		camera.fov = fov

func set_preview_position(val: float):
	preview_position = val
	if Engine.editor_hint and path_follow:
		path_follow.unit_offset = val

# --- API PÚBLICA ---
func play():
	if anim_player:
		anim_player.play("dolly")

func stop():
	if anim_player:
		anim_player.stop()

func pause():
	if anim_player:
		anim_player.stop(false)

func seek(time: float):
	if anim_player:
		anim_player.seek(time, true)

func is_playing() -> bool:
	return anim_player and anim_player.is_playing()

# --- COMPATIBILIDAD CON CinematicManager ---
func activate(force_current: bool = true):
	# Evitar activaciones repetidas
	if _is_active:
		return
	
	_is_active = true
	
	# Buscar específicamente la cámara del jugador (no usar get_viewport().get_camera() 
	# porque puede devolver una cámara de transición del CinematicManager)
	_player_camera = _find_player_camera()
	print("[CinematicPathRig] activate() - player_camera capturada: ", _player_camera.get_path() if _player_camera else "null")
	print("[CinematicPathRig] activate() - Path global_pos: ", global_transform.origin)
	print("[CinematicPathRig] activate() - Camera global_pos: ", camera.global_transform.origin if camera else "no camera")
	
	if _player_camera and _player_camera != camera:
		_source_transform = _player_camera.global_transform
		_source_fov = _player_camera.fov
	else:
		# Fallback: usar la cámara activa del viewport
		var active_cam = get_viewport().get_camera()
		if active_cam and active_cam != camera:
			_source_transform = active_cam.global_transform
			_source_fov = active_cam.fov
		else:
			_source_transform = camera.global_transform
			_source_fov = camera.fov
	
	# Iniciar transición (no hacer current inmediatamente si hay transición)
	if transition_time > 0.01:
		_transition_alpha = 0.0
		camera.current = true  # Tomar control pero interpolar
	elif force_current:
		_transition_alpha = 1.0
		camera.current = true
	
	# Activar physics_process para seguimiento y transición
	set_physics_process(true)
	
	if auto_play:
		play()

func deactivate():
	_is_active = false
	stop()
	
	# La transición de salida se maneja en _step_transition()
	# No hacemos _player_camera.current = true aquí, lo hacemos cuando alpha llega a 0

func get_camera() -> Camera:
	return camera

# --- PROCESO EN EDITOR ---
func _process(_delta):
	if Engine.editor_hint:
		# Actualizar rotation mode si cambió track_player o look_ahead
		_update_rotation_mode()
		
		# Actualizar parámetros de cámara
		if camera:
			if camera.fov != fov:
				camera.fov = fov
			if camera.near != near:
				camera.near = near
			if camera.far != far:
				camera.far = far
