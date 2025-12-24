extends Spatial

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
	if not _is_mouse_look_active:
		return

	var motion = input_state.get_mouse_delta()
	if motion is Vector2 and motion.length_squared() > 0:
		var scaled_motion = motion / 10000.0
		target_yaw -= -scaled_motion.x * yaw_sensitivity
		target_pitch += scaled_motion.y * pitch_sensitivity
		var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
		var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
		target_pitch = clamp(target_pitch, -lim_down, lim_up)


func _physics_process(delta):
	# --- ROBUST YAW INITIALIZATION ---
	# On the first frame, set the camera's local yaw to PI (180 deg) to look from behind.
	# The camera rig rotates with the player, so we only need to set this local offset once.
	if not _yaw_initialized and is_instance_valid(player):
		var initial_offset = 0 
		target_yaw = initial_offset
		if is_instance_valid(yaw):
			yaw.rotation.y = initial_offset
		print("[PlayerSpringCam] First frame: Initialized camera with local yaw offset: ", rad2deg(initial_offset))
		_yaw_initialized = true
	# ---------------------------------
	# Control de rotación de cámara
	var touch_controls = get_node_or_null("/root/TouchControls")
	var touch_active = touch_controls and touch_controls.is_touch_controls_active()
	var is_playback = input_state and input_state.mode == input_state.Mode.PLAYBACK
	var is_record = input_state and input_state.mode == input_state.Mode.RECORD
	var replay_manager = get_node("/root/ReplayManager")
	
	var motion = Vector2.ZERO
	
	# 1. Adquirir 'motion' (delta de mouse/look)
	if is_playback:
		if replay_manager.is_camera_free_look_active:
			motion = input_state.get_live_mouse_delta()
		else:
			motion = input_state.get_mouse_delta()
	elif not touch_active and player_id == 1 and _is_mouse_look_active:
		# En modo 'live' o 'record', usar el mouse procesado si no hay controles touch activos.
		motion = input_state.get_live_mouse_delta()

	# 2. Aplicar rotación si hay movimiento
	if motion is Vector2 and motion.length() > 0.0:
		var scaled_motion = motion / 1000.0
		target_yaw -= scaled_motion.x * yaw_sensitivity
		target_pitch += scaled_motion.y * pitch_sensitivity
		
		# Limitar pitch
		var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
		var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
		target_pitch = clamp(target_pitch, -lim_down, lim_up)
		
		if is_playback and not replay_manager.is_camera_free_look_active:
			input_state.clean_mouse_delta_y()
		
		if is_playback:
			# Ya no se consume el input aquí. Se lee una variable limpia.
			pass
		else: # Solo en modo 'live'
			# Activar strafing si hay movimiento del mouse
			if motion.length_squared() > 0:
				input_state.is_strafing_mode_active = true
				# El timer es manejado en PlayerController

	# Para player 2, siempre usar joy
	if player_id == 2:
		# TODO: Integrar ejes de InputState si se usan para joypad
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

	if (is_record or is_playback) and motion.length_squared() > 0.01:
		var mode_str = "REC" if is_record else "PLAY"
		var pitch_deg = rad2deg(pitch.rotation.x)
		var target_pitch_deg = rad2deg(target_pitch)
		print("CAM_PITCH_DEBUG | %s | motion_y: %.2f | target_pitch: %.2f | final_pitch: %.2f" % [mode_str, motion.y, target_pitch_deg, pitch_deg])
	# Dynamic zoom based on player horizontal speed
	if player and springarm:
		var hv := Vector3.ZERO
		if player.has_method("get_horizontal_velocity"):
			hv = player.get_horizontal_velocity()
		else:
			# Fallback: if player exposes velocity as property
			hv = player.get("horizontal_velocity") if player else Vector3.ZERO
		var speed := hv.length()
		var target_len = lerp(base_length, max_length, clamp(speed / 8.0, 0.0, 1.0))
		springarm.spring_length = lerp(springarm.spring_length, target_len, min(1.0, zoom_speed * delta))

	# Debug básico de cámara (yaw/pitch/length)
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
	
	# Debug adicional para playback
	if ReplayManager and ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		var now := OS.get_ticks_msec()
		if now - _last_playback_debug_ms >= 1000:  # Cada segundo
			_last_playback_debug_ms = now
			print("Playback Cam: yaw=", yaw.rotation.y if yaw else 0, " target_yaw=", target_yaw)

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
