
extends Spatial

export var is_playback := false # Flag para desactivar lógica de input/smoothing en modo replay

# Godot 3.6 SpringArm-based third person camera controller
# Node layout expected:
# CameraRig (Spatial with this script)
#  └── Yaw (Spatial)
#       └── Pitch (Spatial)
#            └── SpringArm (SpringArm)
#                 └── Camera (Camera)

export(NodePath) var player_path
export(NodePath) var yaw_path
export(NodePath) var pitch_path
export(NodePath) var springarm_path
export(NodePath) var camera_path

export(float, 0.1, 5.0, 0.1) var strafe_mode_timeout := 1.0
export(float, 0.0, 1.0, 0.05) var strafe_mode_influence := 1.0

export(float, 0.1, 100, 1) var yaw_sensitivity := 20
export(float, 0.1, 100, 1) var pitch_sensitivity := 20
export(float) var yaw_smooth := 12.0
export(float) var pitch_smooth := 12.0
export(float, 0.0, 90.0, 0.5) var pitch_limit_up_deg := 85.0 # límite superior para mirar arriba
export(float, 0.0, 90.0, 0.5) var pitch_limit_down_deg := 65.0 # límite inferior para mirar abajo
export(float) var cam_yaw_offset := 0.0
export(float) var base_length := 3.8
export(float) var max_length := 5.0
export(float) var zoom_speed := 3.0
export(int) var collision_mask := 6 # 2 (mundo) | 4 (plataformas móviles)
export var debug_enabled := false
export(float, 0.0, 2.0, 0.01) var debug_interval := 0.4

# Viewport cropping
export (float, 0.0, 0.49) var crop_margin_horizontal = 0.0 setget _set_crop_margin_horizontal
export (float, 0.0, 0.49) var crop_margin_vertical = 0.0 setget _set_crop_margin_vertical

var _original_fov := 70.0
var _last_debug_ms := 0
var _last_playback_debug_ms := 0

var player
var yaw
var pitch
var springarm
var cam

var target_yaw := 0.0
var target_pitch := 0.0
onready var input_state = get_node("/root/InputState")
var _yaw_initialized := false
var _is_mouse_look_active := false
var _pending_mouse_motion := Vector2.ZERO

var player_id := 1
var joypad_device := -1

func set_player_id(id: int) -> void:
	player_id = id
	if player_id == 2:
		joypad_device = 1 # Asumir que P2 usa joypad 1

func _enter_tree():
	pass

func _ready():
	process_priority = -5  # Ensure camera runs before player physics
	if player_path: player = get_node(player_path)
	if yaw_path: yaw = get_node(yaw_path)
	if pitch_path: pitch = get_node(pitch_path)
	if springarm_path: springarm = get_node(springarm_path)
	if camera_path: cam = get_node(camera_path)
	if springarm:
		springarm.spring_length = base_length
		springarm.collision_mask = collision_mask

	# Conectarse a la señal de MouseCapture para el cambio de captura del mouse
	if MouseCapture:
		MouseCapture.connect("capture_changed", self, "_on_capture_changed")

	# Conectarse a ReplayManager para cambios de modo
	if ReplayManager:
		ReplayManager.connect("mode_changed", self, "_on_replay_mode_changed")
	
	_update_mouse_look_active()
	# If replay is already active when this node enters tree, go passive immediately
	var started_in_playback := false
	if input_state and input_state.mode == input_state.Mode.PLAYBACK:
		started_in_playback = true
	elif typeof(GameGlobals) != TYPE_NIL and GameGlobals and GameGlobals.is_replaying:
		started_in_playback = true
	elif ReplayManager:
		# Evitar el uso de 'in' con objetos; comprobar de forma segura que las propiedades
		# existen comprobando que su tipo no sea NIL al acceder (autocast a null devuelve TYPE_NIL).
		if typeof(ReplayManager.mode) != TYPE_NIL and typeof(ReplayManager.ReplayMode) != TYPE_NIL:
			if ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
				started_in_playback = true
	if started_in_playback:
		set_is_playback(true)
	# Ajuste de sensibilidad en modo replay para evitar duplicar la escala de los deltas grabados
	var game_globals = GameGlobals
	# NOTE: do not forcibly override exported sensitivities here - recorded deltas
	# already contain the expected magnitude. Changing the exported values at
	# runtime made playback almost immobile. Keep exported defaults.

func _on_capture_changed(is_captured: bool):
	_update_mouse_look_active()

func _on_replay_mode_changed(new_mode: int):
	_update_mouse_look_active()

func _update_mouse_look_active():
	var is_captured = MouseCapture.is_captured if MouseCapture else false
	var is_playback = input_state and input_state.mode == input_state.Mode.PLAYBACK
	# During playback, always allow mouse-look so recorded deltas are applied.
	if is_playback:
		_is_mouse_look_active = true # 2. Asegurarse de que _is_mouse_look_active sea true en playback
	else:
		_is_mouse_look_active = is_captured

func process_camera_rotation(_motion: Vector2):
	"""Procesa el movimiento del mouse/touch para rotar la cámara desde InputState."""
	# Asegurar que la cámara procese input durante playback aún si el estado local
	# de captura de ratón no está activo (puede ser refrescado por ReplayManager).
	var is_playback = input_state and input_state.mode == input_state.Mode.PLAYBACK
	var gg = GameGlobals if GameGlobals else get_node_or_null("/root/GameGlobals")
	if not _is_mouse_look_active and not is_playback:
		if gg and gg.replay_debug_mode:
			print("[PlayerSpringCam][process_camera_rotation] SKIP: _is_mouse_look_active=false, not playback")
		return
	if gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][process_camera_rotation] ENTER: is_playback=", is_playback, " _is_mouse_look_active=", _is_mouse_look_active, " _motion=", _motion)

	# Prefer explicit motion provided by caller (ReplayPlayback), fallback a InputState
	var motion = Vector2.ZERO
	var motion_from_param := false
	if _motion and _motion is Vector2 and _motion.length_squared() > 0:
		motion = _motion
		motion_from_param = true
	else:
		# Prefer any locally-captured pending mouse motion (from this camera's _input)
		if _pending_mouse_motion.length_squared() > 0:
			motion = _pending_mouse_motion
			_pending_mouse_motion = Vector2.ZERO
		else:
			motion = input_state.peek_mouse_motion() if input_state and input_state.has_method("peek_mouse_motion") else input_state.get_mouse_delta()
	gg = GameGlobals if GameGlobals else get_node_or_null("/root/GameGlobals")
	if gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][process_camera_rotation] called. mode=", input_state.mode, " _is_mouse_look_active=", _is_mouse_look_active, " param_motion=", _motion, " input_mouse_delta=", motion)

	# Decide whether to ignore smoothing during playback to avoid double-interpolation jitter
	var replay_manager = get_node_or_null("/root/ReplayManager")
	is_playback = input_state and input_state.mode == input_state.Mode.PLAYBACK
	# If we're in playback mode, apply rotation instantly and update transforms
	if is_playback:
		# Apply rotation immediately without smoothing and force transforms to match recording
		_apply_rotation(motion, 0.0, true)
		# Ensure transforms are snapped exactly
		if yaw:
			yaw.rotation.y = target_yaw
		if pitch:
			pitch.rotation.x = target_pitch
		update_camera_transform()
		# Notify InputState if motion was external
		if motion_from_param and input_state and input_state.has_method("notify_mouse_motion"):
			input_state.notify_mouse_motion(motion)
		return
	var ignore_smoothing = false
	if is_playback and replay_manager and not replay_manager.is_camera_free_look_active:
		ignore_smoothing = true

	if motion is Vector2 and motion.length_squared() > 0:
		if gg and gg.replay_debug_mode:
			print("[PlayerSpringCam][process_camera_rotation] ignore_smoothing=", ignore_smoothing, " motion=", motion)
		_apply_rotation(motion, 0.0, ignore_smoothing)
		# If the rotation was driven by an external caller (not from InputState),
		# notify the InputState so it can update strafing state and recording.
		if motion_from_param and input_state and input_state.has_method("notify_mouse_motion"):
			input_state.notify_mouse_motion(motion)
	elif gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][process_camera_rotation] motion vacío o no Vector2: ", motion)


func _apply_rotation(motion: Vector2, delta: float, ignore_smoothing: bool) -> void:
	# 2. Eliminación de la "Física de Cámara"
	# En modo is_playback, la cámara debe ser puramente matemática.
	# Si es replay, no hagas cálculos de sensibilidad ni sumas.
	if is_playback:
		# En modo replay, target_yaw y target_pitch son establecidos directamente
		# por set_replay_state. Esta función solo debe asegurarse de que se apliquen.
		yaw.rotation.y = target_yaw
		pitch.rotation.x = target_pitch
		return
	# Centraliza la lógica de aplicación de rotación para poder ignorar el smoothing
	var gg = GameGlobals if GameGlobals else get_node_or_null("/root/GameGlobals")
	if not (motion is Vector2) or motion.length_squared() == 0:
		if gg and gg.replay_debug_mode:
			print("[PlayerSpringCam][_apply_rotation] NO ROT: motion vacío o no Vector2: ", motion)
		return
	if gg and gg.replay_debug_mode:
		# Durante el replay, el delta es fijo y la sensibilidad debe ser consistente.
		# La división por 1000 es un artefacto de cómo se manejaba el input del ratón.
		# Si el mouse_delta grabado ya tiene la escala correcta, esta división puede ser
		# la causa de que el movimiento sea casi nulo.
		# Para el replay, usaremos el valor más directamente.
		if is_playback:
			var scaled_motion = motion * 0.01
		print("[PlayerSpringCam][_apply_rotation] APLICANDO: motion=", motion, " ignore_smoothing=", ignore_smoothing)
	var scaled_motion = motion / 1000.0
	if gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][_apply_rotation] scaled_motion=", scaled_motion, " ignore_smoothing=", ignore_smoothing, " yaw_sens=", yaw_sensitivity, " pitch_sens=", pitch_sensitivity)
	target_yaw -= scaled_motion.x * yaw_sensitivity
	target_pitch += scaled_motion.y * pitch_sensitivity
	var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
	var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
	target_pitch = clamp(target_pitch, -lim_down, lim_up)
	# 3. Si es playback, la rotación debe ser un set directo, sin lerp.
	if is_playback or ignore_smoothing:
		if yaw:
			yaw.rotation.y = target_yaw # Asignación directa
		if pitch:
			pitch.rotation.x = target_pitch # Asignación directa

	# Durante playback siempre imprimir estado para diagnóstico (no depender de debug_enabled)
	var is_playback_mode = input_state and input_state.mode == input_state.Mode.PLAYBACK
	if is_playback_mode:
		var cam_cur = false
		if cam:
			if "current" in cam:
				cam_cur = cam.current
			elif cam.has_method("is_current"):
				cam_cur = cam.is_current()
		print("[PlayerSpringCam][_apply_rotation][PLAYBACK] POST_APPLY yaw=", (yaw.rotation.y if yaw else "nil"), " pitch=", (pitch.rotation.x if pitch else "nil"), " cam_current=", cam_cur)

func force_rotate_for_playback(motion: Vector2):
	"""
	Llamado directamente por ReplayPlayback para garantizar la rotación instantánea
	sin pasar por la lógica de _physics_process.
	"""
	_apply_rotation(motion, 0.0, true)

func _physics_process(delta):
	# 2. Congelar la lógica de la Cámara: Si es playback, no hacer nada.
	if is_playback:
		set_physics_process(false) # Desactivarse para no consumir recursos.
		return

	# --- Lógica de input/smoothing solo si NO es playback (Modo LIVE) ---
	_update_mouse_look_active()

	var motion = Vector2.ZERO
	if _is_mouse_look_active:
		# En modo LIVE, leer el delta del mouse desde InputState.
		motion = input_state.get_mouse_delta()

	if motion.length_squared() > 0.0:
		_apply_rotation(motion, delta, false)

	# Smooth yaw/pitch (solo para modo LIVE)
	if yaw:
		yaw.rotation.y = lerp_angle(yaw.rotation.y, target_yaw, min(1.0, yaw_smooth * delta))
	if pitch:
		pitch.rotation.x = lerp(pitch.rotation.x, target_pitch, min(1.0, pitch_smooth * delta))


func set_is_playback(value: bool) -> void:
	# When entering playback, become passive: stop physics processing
	# and snap transforms to recorded targets to avoid internal smoothing.
	is_playback = value
	# 3. Limpieza de set_is_playback: Esta línea es la clave.
	# Si value es 'false' (modo Live), set_physics_process será 'true'.
	set_physics_process(not value)
	# Force mouse-look active during playback so camera accepts deltas
	if value:
		_is_mouse_look_active = true
	if value:
		if yaw:
			yaw.rotation.y = target_yaw
		if pitch:
			pitch.rotation.x = target_pitch
		# Also ensure immediate transform application
		update_camera_transform()

# Aplicar delta externo de yaw (p.ej., tank turn del jugador)
func apply_external_yaw_delta(delta_yaw: float) -> void:
	if yaw:
		yaw.rotation.y = yaw.rotation.y + delta_yaw
		# Mantener el objetivo sincronizado para que el suavizado no revierta el cambio
		target_yaw = target_yaw + delta_yaw

# Alinear yaw de cámara al yaw del cuerpo con offset configurable
func sync_to_body_yaw(body_yaw: float, offset: float) -> void:
	if yaw:
		var y := body_yaw + offset
		yaw.rotation.y = y
		target_yaw = y
	if pitch:
		pitch.rotation.x = 0.0
		target_pitch = 0.0

func _set_crop_margin_horizontal(value):
	crop_margin_horizontal = value
	if is_inside_tree():
		_update_camera_fov()

func _set_crop_margin_vertical(value):
	crop_margin_vertical = value
	if is_inside_tree():
		_update_camera_fov()

func _update_camera_fov():
	if not cam:
		return

	var v_scale = 1.0 - (2.0 * crop_margin_vertical)
	var h_scale = 1.0 - (2.0 * crop_margin_horizontal)
	
	var scale = min(v_scale, h_scale)
	
	if scale <= 0:
		return
		
	var original_fov_rad = deg2rad(_original_fov)
	var new_fov_rad = 2.0 * atan(tan(original_fov_rad / 2.0) * scale)
	cam.fov = rad2deg(new_fov_rad)

func _round(v: float) -> float:
	return round(v * 1000000.0) / 1000000.0

# Replay state methods
func get_replay_state() -> Dictionary:
	return {
		"yaw": _round(yaw.rotation.y) if yaw else 0.0,
		"pitch": _round(pitch.rotation.x) if pitch else 0.0,
		"spring_length": round((springarm.spring_length if springarm else base_length) * 1000000.0) / 1000000.0
	}

func set_replay_state(state: Dictionary) -> void:
	# Restore camera orientation for deterministic replay
	# 1. Sincronización Absoluta: Sobreescribir directamente la rotación.
	if state.has("yaw") and yaw:
		target_yaw = state["yaw"]
		yaw.rotation.y = target_yaw
	if state.has("pitch") and pitch:
		target_pitch = state["pitch"]
		pitch.rotation.x = target_pitch
	if state.has("spring_length") and springarm:
		springarm.spring_length = state["spring_length"]
	# Force immediate update to ensure transform is applied
	update_camera_transform()

func update_camera_transform() -> void:
	# Force immediate application of yaw/pitch to transforms
	if yaw:
		yaw.rotation.y = target_yaw
	if pitch:
		pitch.rotation.x = target_pitch
