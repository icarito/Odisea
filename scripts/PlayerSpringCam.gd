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

export(float, 0.001, 1, 0.01) var yaw_sensitivity := 0.015
export(float, 0.001, 1, 0.01) var pitch_sensitivity := 0.015
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

var player
var yaw
var pitch
var springarm
var cam

var target_yaw := 0.0
var target_pitch := 0.0
var _yaw_initialized := false

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
		# In Godot 3 SpringArm uses current transform forward; leave orientation to yaw/pitch
	# Capturar el puntero para control de cámara
	if player_id == 1:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Initial yaw will be set by _physics_process on the first frame
	# Set default pitch respecting limit
	if pitch:
		var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
		var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
		target_pitch = clamp(pitch.rotation.x, -lim_down, lim_up)
	
	if cam:
		_original_fov = cam.fov
	
	if is_inside_tree():
		get_viewport().connect("size_changed", self, "_update_camera_fov")
	_update_camera_fov()


func _unhandled_input(event):
	# Toggle captura con ESC, recapturar al click
	if event is InputEventKey and event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if event is InputEventMouseButton and event.pressed and player_id == 1:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func process_camera_rotation(motion: Vector2):
	"""Procesa el movimiento del mouse para rotar la cámara."""
	if player_id == 1:
		var scaled_motion = motion / 100.0
		target_yaw -= scaled_motion.x * yaw_sensitivity
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

	if player_id == 2:
		var joy_x = Input.get_joy_axis(joypad_device, JOY_AXIS_0)
		var joy_y = Input.get_joy_axis(joypad_device, JOY_AXIS_1)
		var deadzone = 0.2
		
		if abs(joy_x) > deadzone:
			target_yaw -= joy_x * yaw_sensitivity * 1000 * delta
		if abs(joy_y) > deadzone:
			target_pitch += joy_y * pitch_sensitivity * 1000 * delta
		
		var lim_up := deg2rad(clamp(pitch_limit_up_deg, 0.0, 90.0))
		var lim_down := deg2rad(clamp(pitch_limit_down_deg, 0.0, 90.0))
		target_pitch = clamp(target_pitch, -lim_down, lim_up)

	# Smooth yaw/pitch
	if yaw:
		var y = yaw.rotation.y
		y += (target_yaw - y) * min(1.0, yaw_smooth * delta)
		yaw.rotation.y = y
	if pitch:
		var p = pitch.rotation.x
		p += (target_pitch - p) * min(1.0, pitch_smooth * delta)
		pitch.rotation.x = p
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
