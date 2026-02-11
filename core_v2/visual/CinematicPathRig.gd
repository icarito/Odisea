tool
extends Path
class_name CinematicPathRig

# CinematicPathRig.gd - Rig cinemático que sigue un Path para secuencias de "filmación"
# Incluye Camera, PathFollow y AnimationPlayer pre-configurados.

# --- CONFIGURACIÓN GENERAL ---
export(float, 0.1, 60.0) var duration := 5.0 setget set_duration
export(bool) var loop := false
export(bool) var auto_play := false
export(bool) var look_ahead := true # La cámara mira hacia adelante del path

# --- SEGUIMIENTO DE JUGADOR ---
export(bool) var track_player := false # La cámara siempre mira al jugador
export(bool) var follow_player_on_path := false # La cámara se mueve a lo largo del path para estar cerca del jugador
export(float, 0.1, 20.0) var follow_speed := 5.0 # Velocidad de seguimiento suave
export(Vector3) var player_offset := Vector3(0, 1.5, 0) # Offset para apuntar (altura del pecho)

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
var _target_offset := 0.0 # Offset objetivo para seguimiento suave

# Estado activo
var _is_active := false
var _last_deactivate_time := 0.0 # Para cooldown anti-jitter
const REACTIVATION_COOLDOWN := 0.2 # Segundos antes de poder reactivar

func _init():
	if not is_in_group("cinematic_rigs"):
		add_to_group("cinematic_rigs")
	if not is_in_group("replay_sync"):
		add_to_group("replay_sync")

func _ready():
	_ensure_nodes()
	_setup_animation()
	
	if not Engine.editor_hint:
		set_physics_process(track_player or follow_player_on_path)
	
	if auto_play and not Engine.editor_hint:
		play()

# --- ACTUALIZACIÓN ---
func _physics_process(delta):
	if Engine.editor_hint:
		return
	
	# Si no estamos activos, no hacer nada
	if not _is_active:
		return
	
	# Actualizar lógica del rig (seguimiento de path y cámara)
	_update_rig(delta)

func _update_rig(delta: float):
	"""Actualiza la posición del path follow y la orientación de la cámara."""
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
			# Si delta es 0 (llamada forzada), aplicamos inmediatamente
			if delta <= 0.00001:
				path_follow.unit_offset = _target_offset
			else:
				# Interpolar suavemente hacia el objetivo
				path_follow.unit_offset = lerp(path_follow.unit_offset, _target_offset, follow_speed * delta)
	
	# Actualizar orientación de la cámara
	if camera:
		# La cámara está como hija de PathFollow, su posición local debe ser 0
		camera.transform.origin = Vector3.ZERO
		
		# Hacer que la cámara mire al jugador (si track_player está activo)
		if track_player and _player_node:
			var target_pos = _player_node.global_transform.origin + player_offset
			camera.look_at(target_pos, Vector3.UP)

# NOTA: Las funciones de transición interna fueron ELIMINADAS.
# CinematicManager ahora maneja TODAS las transiciones.
# _apply_transition_camera, _step_transition, _get_smooth_alpha ya no existen.

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
func activate(make_current: bool = true):
	"""Activa el rig. CinematicManager maneja todas las transiciones."""
	var was_active = _is_active
	
	# Cooldown anti-jitter (solo en cold start)
	if not was_active:
		var current_time = OS.get_ticks_msec() / 1000.0
		if current_time - _last_deactivate_time < REACTIVATION_COOLDOWN:
			return
	
	_is_active = true
	
	# Forzar actualización inmediata de posición y rotación (SNAP)
	# Usamos snap_to_target en lugar de _update_rig(0) porque _update_rig podría usar lerp
	if not was_active:
		snap_to_target()
	
	# Si se solicita, hacer la cámara current
	if make_current and camera:
		camera.current = true
	
	# Activar physics_process para seguimiento continuo
	set_physics_process(true)
	
	if auto_play:
		play()

func snap_to_target():
	"""Force immediate update of rig position to player target"""
	if not _player_node:
		_find_player()
	
	if _player_node and curve and path_follow:
		var player_pos = _player_node.global_transform.origin
		var local_pos = global_transform.affine_inverse().xform(player_pos)
		var closest_offset = curve.get_closest_offset(local_pos)
		
		# Set directly without lerp
		path_follow.unit_offset = closest_offset / curve.get_baked_length()
		
		# Force update transform
		path_follow.force_update_transform()
		if camera:
			if track_player:
				camera.look_at(player_pos + player_offset, Vector3.UP)
			camera.force_update_transform()

func deactivate(restore_camera: bool = true):
	"""Desactiva el rig."""
	if not _is_active:
		return
	
	_is_active = false
	_last_deactivate_time = OS.get_ticks_msec() / 1000.0
	stop()
	
	if restore_camera:
		# Restaurar cámara del jugador
		var player_cam = _find_player_camera()
		if player_cam and player_cam.is_inside_tree():
			player_cam.current = true
	
	set_physics_process(false)


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

func get_snapshot() -> Dictionary:
	var snapshot = {
		"is_active": _is_active,
		"target_offset": _target_offset,
		"last_deactivate_time": _last_deactivate_time,
	}
	if path_follow:
		snapshot["unit_offset"] = path_follow.unit_offset
	if anim_player:
		if anim_player.is_playing():
			snapshot["current_animation"] = anim_player.current_animation
			snapshot["playback_position"] = anim_player.current_animation_position
		else:
			snapshot["current_animation"] = ""
			snapshot["playback_position"] = 0.0
	return snapshot

func restore_snapshot(data: Dictionary) -> void:
	_is_active = data.get("is_active", false)
	_target_offset = data.get("target_offset", 0.0)
	_last_deactivate_time = data.get("last_deactivate_time", 0.0)
	if path_follow:
		path_follow.unit_offset = data.get("unit_offset", 0.0)
	if anim_player:
		var anim = data.get("current_animation", "")
		if anim != "":
			anim_player.current_animation = anim
			anim_player.seek(data.get("playback_position", 0.0))
		else:
			anim_player.stop()
