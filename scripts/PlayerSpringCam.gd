extends Spatial

# Importar FixedVec3 para conversión de punto fijo
const FixedVec3 = preload("res://scripts/utils/FVec3.gd")

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

var yaw_angle_fixed: int = 0
var pitch_angle_fixed: int = 0
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

var target_yaw_fixed: int = 0
var target_pitch_fixed: int = 0
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

   # Añadir al grupo para replay
   if not is_in_group("camera_rig_group"):
	   add_to_group("camera_rig_group")

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
	var has_touchscreen = OS.has_touchscreen_ui_hint()
	_is_mouse_look_active = is_captured or is_playback or has_touchscreen

func _get_mouse_motion() -> Vector2:
	var is_playback = ReplayManager and ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK
	
	if not is_playback:
		# Live or Recording mode
		if player_id == 1 and _is_mouse_look_active:
			return input_state.get_mouse_delta()
		else:
			return Vector2.ZERO

	# Playback mode
	match ReplayManager.current_camera_mode:
		ReplayManager.CameraMode.FREE_LOOK:
			# In playback, but with free camera. Use live user input.
			return input_state.get_live_mouse_delta()
		ReplayManager.CameraMode.FOLLOW_REPLAY:
			# Following the replay, use the injected (recorded) mouse delta.
			return input_state.get_mouse_delta()
	
	return Vector2.ZERO

func _physics_process(delta):
	# --- ROBUST YAW INITIALIZATION ---
	if not _yaw_initialized and is_instance_valid(player):
		var initial_offset = 0 
		target_yaw_fixed = FixedPoint.to_fixed(initial_offset)
		if is_instance_valid(yaw):
			yaw.rotation.y = initial_offset
		_yaw_initialized = true
	# ---------------------------------
		
	var motion = _get_mouse_motion()
	
	# 2. Aplicar rotación si hay movimiento
	if motion.length_squared() > 0.0:
		var scaled_motion = motion / 1000.0
		target_yaw_fixed -= FixedPoint.to_fixed(scaled_motion.x * yaw_sensitivity)
		target_pitch_fixed += FixedPoint.to_fixed(scaled_motion.y * pitch_sensitivity)
		
		# Limitar pitch
		var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
		var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
		var target_pitch = FixedPoint.from_fixed(target_pitch_fixed)
		target_pitch = clamp(target_pitch, -lim_down, lim_up)
		target_pitch_fixed = FixedPoint.to_fixed(target_pitch)

		var is_playback = ReplayManager and ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK
		if not is_playback:
			# Activar strafing si hay movimiento del mouse en modo 'live'
			input_state.is_strafing_mode_active = true
			# El timer es manejado en PlayerController

	# Smooth yaw/pitch solo si NO estamos en modo replay
	var is_playback = ReplayManager and ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK
	if not is_playback:
		if yaw:
			var target_yaw = FixedPoint.from_fixed(target_yaw_fixed)
			var y = yaw.rotation.y
			y += (target_yaw - y) * min(1.0, yaw_smooth * delta)
			yaw.rotation.y = y
		if pitch:
			var target_pitch = FixedPoint.from_fixed(target_pitch_fixed)
			var p = pitch.rotation.x
			p += (target_pitch - p) * min(1.0, pitch_smooth * delta)
			pitch.rotation.x = p
	else:
		# En modo replay, forzar valores exactos
		if yaw:
			yaw.rotation.y = FixedPoint.from_fixed(target_yaw_fixed)
		if pitch:
			pitch.rotation.x = FixedPoint.from_fixed(target_pitch_fixed)
	
	# Dynamic zoom based on player horizontal speed
	if player and springarm:
		var hv := Vector3.ZERO
		if player.has_method("get_horizontal_velocity"):
			hv = player.get_horizontal_velocity()
		elif player and ("horizontal_velocity_fixed" in player):
			var hv_fixed = player.get("horizontal_velocity_fixed")
			hv = FixedVec3.to_vec3(hv_fixed) if hv_fixed != null else Vector3.ZERO
		else:
			var hv_val = player.get("horizontal_velocity") if player else null
			hv = hv_val if hv_val != null else Vector3.ZERO
		var speed := hv.length()
		var target_len = lerp(base_length, max_length, clamp(speed / 8.0, 0.0, 1.0))
		springarm.spring_length = lerp(springarm.spring_length, target_len, min(1.0, zoom_speed * delta))

	# --- Conditional Input Consumption ---
	is_playback = ReplayManager and ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK
	if is_playback and ReplayManager.current_camera_mode == ReplayManager.CameraMode.FOLLOW_REPLAY:
		# This script just used the replayed pitch value. Clean it so it's not used elsewhere.
		input_state.clean_mouse_delta_y()


func apply_external_yaw_delta(delta_yaw: float) -> void:
	if yaw:
		var delta_yaw_fixed = FixedPoint.to_fixed(delta_yaw)
		target_yaw_fixed += delta_yaw_fixed
		yaw.rotation.y = FixedPoint.from_fixed(target_yaw_fixed)

# Alinear yaw de cámara al yaw del cuerpo con offset configurable
func sync_to_body_yaw(body_yaw: float, offset: float) -> void:
	if yaw:
		var y := body_yaw + offset
		yaw.rotation.y = y
		target_yaw_fixed = FixedPoint.to_fixed(y)
	if pitch:
		pitch.rotation.x = 0.0
		target_pitch_fixed = 0

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

# Replay state methods
func get_replay_state() -> Dictionary:
	return {
		"yaw": FixedPoint.from_fixed(target_yaw_fixed),
		"pitch": FixedPoint.from_fixed(target_pitch_fixed),
		"spring_length": springarm.spring_length if springarm else base_length
	}

func set_replay_state(state: Dictionary) -> void:
	# Restaurar yaw y pitch iniciales para alineación perfecta en playback
	if state.has("yaw") and yaw:
		yaw.rotation.y = state["yaw"]
		target_yaw_fixed = FixedPoint.to_fixed(state["yaw"])
	if state.has("pitch") and pitch:
		pitch.rotation.x = state["pitch"]
		target_pitch_fixed = FixedPoint.to_fixed(state["pitch"])
	if state.has("spring_length") and springarm:
		springarm.spring_length = state["spring_length"]

## --- REPLAY: Aplicar rotación de input grabado ---
func apply_replay_rotation(mouse_delta: Vector2) -> void:
	if mouse_delta == null:
		return
	var pitch_change = mouse_delta.y * pitch_sensitivity / 1000.0
	var pitch_change_fixed = FixedPoint.to_fixed(pitch_change)
	target_pitch_fixed += pitch_change_fixed
	# Limitar pitch
	var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
	var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
	var target_pitch = FixedPoint.from_fixed(target_pitch_fixed)
	target_pitch = clamp(target_pitch, -lim_down, lim_up)
	target_pitch_fixed = FixedPoint.to_fixed(target_pitch)
	if pitch:
		pitch.rotation.x = target_pitch

## Permite que el sistema de replay inyecte rotación de cámara (yaw/pitch) desde mouse_delta grabado
func process_camera_rotation(mouse_delta: Vector2) -> void:
	# Simula el efecto del mouse grabado sobre la cámara durante el replay
	if mouse_delta == null:
		return
	# Yaw (horizontal)
	var yaw_change = -mouse_delta.x * yaw_sensitivity / 1000.0
	var yaw_change_fixed = FixedPoint.to_fixed(yaw_change)
	target_yaw_fixed += yaw_change_fixed
	if yaw:
		yaw.rotation.y = FixedPoint.from_fixed(target_yaw_fixed)
	# Pitch (vertical)
	var pitch_change = mouse_delta.y * pitch_sensitivity / 1000.0
	var pitch_change_fixed = FixedPoint.to_fixed(pitch_change)
	target_pitch_fixed += pitch_change_fixed
	# Limitar pitch
	var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
	var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
	var target_pitch = FixedPoint.from_fixed(target_pitch_fixed)
	target_pitch = clamp(target_pitch, -lim_down, lim_up)
	target_pitch_fixed = FixedPoint.to_fixed(target_pitch)
	if pitch:
		pitch.rotation.x = target_pitch
