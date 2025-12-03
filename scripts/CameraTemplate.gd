extends Spatial

# Allows to select the player mesh from the inspector
export (NodePath) var PlayerCharacterMesh

var camrot_h = 0
var camrot_v = 0
export var cam_v_max = 75 # -75 recommended
export var cam_v_min = -55 # -55 recommended
export var joystick_sensitivity = 20
var h_sensitivity = .1
var v_sensitivity = .1
var rot_speed_multiplier = .15 #reduce this to make the rotation radius larger
var h_acceleration = 10
var v_acceleration = 10
var joyview = Vector2()

# Zoom dinámico por velocidad (ignora external_velocity por defecto)
export(float, 0.0, 15.0, 0.1) var base_distance := 0.0
export(float, 0.5, 15.0, 0.1) var max_distance := 7.0
export(float, 0.0, 2.0, 0.01) var speed_zoom_gain := 0.35
export(float, 0.0, 20.0, 0.1) var zoom_lerp_speed := 6.0
export(bool) var ignore_external_velocity := true
export(bool) var include_vertical_speed := true
export(float, 0.0, 3.0, 0.1) var vertical_speed_gain := 1.0

# Intro cinematográfica desde un origen opcional
export(bool) var use_cinematic_origin := true
export(float, 0.0, 10.0, 0.1) var spawn_intro_duration := 1.5
export(NodePath) var cinematic_origin_path

onready var _cam: Camera = $h/v/Camera
var _current_distance := 0.0
var _intro_active := false
var _intro_t := 0.0
var _intro_start := Transform()
var _intro_end := Transform()

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	$h/v/Camera.add_exception(get_parent())
	# Asegurar máscaras de colisión de la cámara (solo entorno estático capa 2)
	if _cam and _cam.has_method("set"):
		if "collision_mask" in _cam:
			_cam.collision_mask = 1 << 1
		if "clip_to_areas" in _cam:
			_cam.clip_to_areas = false
	# Inicializar distancia base a partir de la posición local de la cámara si no está configurada
	if _cam:
		if base_distance <= 0.0:
			base_distance = -_cam.translation.z
		_current_distance = base_distance
		var t := _cam.translation
		t.z = -_current_distance
		_cam.translation = t
	# Configurar intro cinematográfica si procede
	if use_cinematic_origin and spawn_intro_duration > 0.0 and _cam:
		var origin_node: Spatial = null
		if cinematic_origin_path and String(cinematic_origin_path) != "":
			if has_node(cinematic_origin_path):
				origin_node = get_node(cinematic_origin_path)
		if origin_node == null:
			var scene := get_tree().get_current_scene()
			if scene:
				origin_node = scene.find_node("CinematicOrigin", true, false)
		if origin_node:
			_intro_active = true
			_intro_t = 0.0
			_intro_start = origin_node.global_transform
			_intro_end = _cam.global_transform
			_cam.global_transform = _intro_start
	
func _input(event):
	if event is InputEventMouseMotion:
		$control_stay_delay.start()
		camrot_h += -event.relative.x * h_sensitivity
		camrot_v += event.relative.y * v_sensitivity
		
func _joystick_input():
	if (Input.is_action_pressed("lookup") ||  Input.is_action_pressed("lookdown") ||  Input.is_action_pressed("lookleft") ||  Input.is_action_pressed("lookright")):
		$control_stay_delay.start()
		joyview.x = Input.get_action_strength("lookright") - Input.get_action_strength("lookleft")
		joyview.y = Input.get_action_strength("lookup") - Input.get_action_strength("lookdown")
		camrot_h += joyview.x * joystick_sensitivity * h_sensitivity
		camrot_v += joyview.y * joystick_sensitivity * v_sensitivity 
		#$h.rotation_degrees.y = lerp($h.rotation_degrees.y, camrot_h, delta * h_acceleration)
		
func _physics_process(delta):
	# JoyPad Controls
	_joystick_input()
	
	# Intro cinematográfica: interpolar cámara y pausar lógica normal hasta terminar
	if _intro_active and _cam:
		_intro_t += delta
		var d := max(spawn_intro_duration, 0.0001)
		var a := clamp(_intro_t / d, 0.0, 1.0)
		# Suavizado smoothstep
		var s := a * a * (3.0 - 2.0 * a)
		_cam.global_transform = _intro_start.interpolate_with(_intro_end, s)
		if a >= 1.0:
			_intro_active = false
			_cam.global_transform = _intro_end
		return

	camrot_v = clamp(camrot_v, cam_v_min, cam_v_max)
	
	var mesh_front = get_node(PlayerCharacterMesh).global_transform.basis.z
	var player := get_parent()
	var horiz_speed := 0.0
	if player and "horizontal_velocity" in player:
		horiz_speed = player.horizontal_velocity.length()
	var auto_rotate_speed =  (PI - mesh_front.angle_to($h.global_transform.basis.z)) * horiz_speed * rot_speed_multiplier
	
	if $control_stay_delay.is_stopped():
		# FOLLOW CAMERA solo cuando el jugador está prácticamente quieto para evitar curvatura de dirección
		if horiz_speed < 0.2:
			$h.rotation.y = lerp_angle($h.rotation.y, get_node(PlayerCharacterMesh).global_transform.basis.get_euler().y, delta * auto_rotate_speed)
			camrot_h = $h.rotation_degrees.y
		else:
			# Mantener la orientación actual; no auto-seguir durante movimiento
			camrot_h = $h.rotation_degrees.y
	else:
		#MOUSE CAMERA
		$h.rotation_degrees.y = lerp($h.rotation_degrees.y, camrot_h, delta * h_acceleration)
	
	# Usamos lerp_angle también para la rotación vertical por consistencia y seguridad.
	$h/v.rotation.x = lerp_angle($h/v.rotation.x, deg2rad(camrot_v), delta * v_acceleration)
	
	# --- Zoom dinámico por velocidad ---
	if _cam:
		var hv := Vector3.ZERO
		var pv2 := Vector3.ZERO
		# Tomamos solo la velocidad propia del jugador (sin external/platform) por defecto
		if player:
			hv = player.horizontal_velocity
			if not ignore_external_velocity:
				var pv = player.platform_velocity
				pv2 = Vector3(pv.x, 0, pv.z)
		horiz_speed = (hv + pv2).length()
		var eff_speed := horiz_speed
		if include_vertical_speed and player:
			var vy := 0.0
			if "vertical_velocity" in player:
				vy = player.vertical_velocity.y
			eff_speed = sqrt(horiz_speed * horiz_speed + (vertical_speed_gain * vy) * (vertical_speed_gain * vy))
		var desired := clamp(base_distance + eff_speed * speed_zoom_gain, base_distance, max_distance)
		_current_distance = lerp(_current_distance, desired, clamp(zoom_lerp_speed * delta, 0.0, 1.0))
		var ct := _cam.translation
		ct.z = -_current_distance
		_cam.translation = ct
	
