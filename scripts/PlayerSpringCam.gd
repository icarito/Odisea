extends Spatial

# Autoloads disabled for naive version

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


export(float, 0.1, 5.0, 0.1) var yaw_sensitivity := 1.0
export(float, 0.1, 5.0, 0.1) var pitch_sensitivity := 1.0
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
var input_state = null
var _yaw_initialized := false
var _is_mouse_look_active := false

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

	# MouseCapture disabled for naive version

	_update_mouse_look_active()
	# If replay is already active when this node enters tree, go passive immediately
	var started_in_playback := false
	if input_state and input_state.mode == input_state.Mode.PLAYBACK:
		started_in_playback = true
	
	# Sensitivities not adjusted for naive version
	var _game_globals = null
	# NOTE: do not forcibly override exported sensitivities here - recorded deltas
	# already contain the expected magnitude. Changing the exported values at
	# runtime made playback almost immobile. Keep exported defaults.

func _on_capture_changed(_is_captured: bool):
	_update_mouse_look_active()

func _on_replay_mode_changed(_new_mode: int):
	_update_mouse_look_active()

func _update_mouse_look_active():
	# For naive version without autoloads, always allow mouse look
	_is_mouse_look_active = true

func process_camera_rotation(_motion: Vector2):
	"""Procesa el movimiento del mouse/touch para rotar la cámara desde InputState."""
	# Asegurar que la cámara procese input durante playback aún si el estado local
	# de captura de ratón no está activo (puede ser refrescado por ReplayManager).
	var _is_playback = input_state and input_state.mode == input_state.Mode.PLAYBACK
	var gg = null  # Autoloads disabled
	if not _is_mouse_look_active and not _is_playback:
		if gg and gg.replay_debug_mode:
			print("[PlayerSpringCam][process_camera_rotation] SKIP: _is_mouse_look_active=false, not playback")
		return
	if gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][process_camera_rotation] ENTER: is_playback=", _is_playback, " _is_mouse_look_active=", _is_mouse_look_active, " _motion=", _motion)

	# Prefer explicit motion provided by caller (ReplayPlayback)
	var motion = _motion if (_motion and _motion is Vector2) else Vector2.ZERO
	var motion_from_param = motion != Vector2.ZERO
	gg = null
	# Debug disabled for naive version

	# Decide whether to ignore smoothing during playback to avoid double-interpolation jitter
	var replay_manager = get_node_or_null("/root/ReplayManager")
	is_playback = false  # No input_state, assume live
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


func _apply_rotation(motion: Vector2, _delta: float, ignore_smoothing: bool) -> void:
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
	var scaled_motion = motion * 0.001
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
	var is_playback_mode = false  # No input_state
	if is_playback_mode:
		var cam_cur = false
		if cam:
			if "current" in cam:
				cam_cur = cam.current
			elif cam.has_method("is_current"):
				cam_cur = cam.is_current()
		if false:
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
	# Restore camera orientation for deterministic replay (applies also en playback)
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


