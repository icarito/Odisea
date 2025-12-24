
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

var player_id := 1
var joypad_device := -1

func set_player_id(id: int) -> void:
	player_id = id
	if player_id == 2:
		joypad_device = 1 # Asumir que P2 usa joypad 1

func _ready():
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
	_is_mouse_look_active = is_captured or is_playback

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
	if _motion and _motion is Vector2 and _motion.length_squared() > 0:
		motion = _motion
	else:
		motion = input_state.get_mouse_delta()
	gg = GameGlobals if GameGlobals else get_node_or_null("/root/GameGlobals")
	if gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][process_camera_rotation] called. mode=", input_state.mode, " _is_mouse_look_active=", _is_mouse_look_active, " param_motion=", _motion, " input_mouse_delta=", motion)

	# Decide whether to ignore smoothing during playback to avoid double-interpolation jitter
	var replay_manager = get_node_or_null("/root/ReplayManager")
	is_playback = input_state and input_state.mode == input_state.Mode.PLAYBACK
	var ignore_smoothing = false
	if is_playback and replay_manager and not replay_manager.is_camera_free_look_active:
		ignore_smoothing = true

	if motion is Vector2 and motion.length_squared() > 0:
		if gg and gg.replay_debug_mode:
			print("[PlayerSpringCam][process_camera_rotation] ignore_smoothing=", ignore_smoothing, " motion=", motion)
		_apply_rotation(motion, 0.0, ignore_smoothing)
	elif gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][process_camera_rotation] motion vacío o no Vector2: ", motion)


func _apply_rotation(motion: Vector2, delta: float, ignore_smoothing: bool) -> void:
	# Centraliza la lógica de aplicación de rotación para poder ignorar el smoothing
	var gg = GameGlobals if GameGlobals else get_node_or_null("/root/GameGlobals")
	if not (motion is Vector2) or motion.length_squared() == 0:
		if gg and gg.replay_debug_mode:
			print("[PlayerSpringCam][_apply_rotation] NO ROT: motion vacío o no Vector2: ", motion)
		return
	if gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][_apply_rotation] APLICANDO: motion=", motion, " ignore_smoothing=", ignore_smoothing)
	var scaled_motion = motion / 1000.0
	if gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][_apply_rotation] scaled_motion=", scaled_motion, " ignore_smoothing=", ignore_smoothing, " yaw_sens=", yaw_sensitivity, " pitch_sens=", pitch_sensitivity)
	target_yaw -= scaled_motion.x * yaw_sensitivity
	target_pitch += scaled_motion.y * pitch_sensitivity
	var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
	var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
	target_pitch = clamp(target_pitch, -lim_down, lim_up)
	if ignore_smoothing:
		if yaw:
			yaw.rotation.y = target_yaw
		if pitch:
			pitch.rotation.x = target_pitch


func _physics_process(delta):
	_update_mouse_look_active()
	# --- ROBUST YAW INITIALIZATION ---
	if not _yaw_initialized and is_instance_valid(player):
		var initial_offset = 0 
		target_yaw = initial_offset
		if is_instance_valid(yaw):
			yaw.rotation.y = initial_offset
		print("[PlayerSpringCam] First frame: Initialized camera with local yaw offset: ", rad2deg(initial_offset))
		_yaw_initialized = true
	# ---------------------------------
	if is_playback:
		# En modo replay: aplicar mouse_delta grabado cada frame, sin smoothing ni input real
		if player and springarm:
			var hv := Vector3.ZERO
			if player.has_method("get_horizontal_velocity"):
				hv = player.get_horizontal_velocity()
			else:
				hv = player.get("horizontal_velocity") if player else Vector3.ZERO
			var speed := hv.length()
			var target_len = lerp(base_length, max_length, clamp(speed / 8.0, 0.0, 1.0))
			springarm.spring_length = lerp(springarm.spring_length, target_len, min(1.0, zoom_speed * delta))
		# Aplicar mouse_delta del replay
		if input_state:
			var replay_motion = input_state.get_mouse_delta()
			if replay_motion is Vector2 and replay_motion.length_squared() > 0.0:
				process_camera_rotation(replay_motion)
				# Limpiar el delta solo si no lo hace ReplayPlayback
				input_state.clean_mouse_delta_x()
				input_state.clean_mouse_delta_y()
		if debug_enabled:
			var now := OS.get_ticks_msec()
			var interval_ms := int(debug_interval * 1000.0)
			if now - _last_debug_ms >= interval_ms:
				_last_debug_ms = now
				var yv = (yaw.rotation.y if yaw else 0.0)
				var pv = (pitch.rotation.x if pitch else 0.0)
				var sl = (springarm.spring_length if springarm else 0.0)
				print("[Cam] yaw=" + String(yv).pad_decimals(3) +
					" pitch=" + String(pv).pad_decimals(3) +
					" len=" + String(sl).pad_decimals(2))
		if ReplayManager and ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
			var now := OS.get_ticks_msec()
			if now - _last_playback_debug_ms >= 1000:
				_last_playback_debug_ms = now
				print("Playback Cam: yaw=", yaw.rotation.y if yaw else 0, " target_yaw=", target_yaw)
		return
	# Lógica de input/smoothing solo si NO es playback
	var touch_controls = get_node_or_null("/root/TouchControls")
	var touch_active = touch_controls and touch_controls.is_touch_controls_active()
	var is_record = input_state and input_state.mode == input_state.Mode.RECORD
	var replay_manager = get_node("/root/ReplayManager")
	var motion = Vector2.ZERO
	if not touch_active and player_id == 1 and _is_mouse_look_active:
		motion = input_state.get_live_mouse_delta()
	var gg = GameGlobals if GameGlobals else get_node_or_null("/root/GameGlobals")
	if gg and gg.replay_debug_mode:
		print("[PlayerSpringCam][_physics_process] beginning. motion=", motion, " is_playback=", is_playback, " player_id=", player_id)
	if motion is Vector2 and motion.length() > 0.0:
		if gg and gg.replay_debug_mode:
			print("[PlayerSpringCam][_physics_process] about to _apply_rotation. raw_motion=", motion)
		_apply_rotation(motion, delta, false)
		# Activar strafing si hay movimiento del mouse
		if motion.length_squared() > 0:
			input_state.is_strafing_mode_active = true
	# Para player 2, siempre usar joy
	if player_id == 2:
		pass
	# Smooth yaw/pitch
	if yaw:
		var y = yaw.rotation.y
		y += (target_yaw - y) * min(1.0, yaw_smooth * delta)
		yaw.rotation.y = y
	if pitch:
		var p = pitch.rotation.x
		p += (target_pitch - p) * min(1.0, pitch_smooth * delta)
		pitch.rotation.x = p
	if (is_record) and motion.length_squared() > 0.01:
		var mode_str = "REC"
		var pitch_deg = rad2deg(pitch.rotation.x)
		var target_pitch_deg = rad2deg(target_pitch)
		print("CAM_PITCH_DEBUG | %s | motion_y: %.2f | target_pitch: %.2f | final_pitch: %.2f" % [mode_str, motion.y, target_pitch_deg, pitch_deg])

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
	if state.has("yaw") and yaw:
		yaw.rotation.y = state["yaw"]
		target_yaw = state["yaw"]
	if state.has("pitch") and pitch:
		pitch.rotation.x = state["pitch"]
		target_pitch = state["pitch"]
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


func set_is_playback(value: bool) -> void:
	# When entering playback, become passive: stop physics processing
	# and snap transforms to recorded targets to avoid internal smoothing.
	is_playback = value
	# Disable physics processing to prevent camera from running its own smoothing
	set_physics_process(not value)
	if value:
		if yaw:
			yaw.rotation.y = target_yaw
		if pitch:
			pitch.rotation.x = target_pitch
		# Also ensure immediate transform application
		update_camera_transform()
