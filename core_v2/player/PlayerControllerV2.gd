extends KinematicBody

const InputProviderV2 = preload("../input/InputProviderV2.gd")
const InputDataV2 = preload("../input/InputDataV2.gd")
const PlayerJumpV2 = preload("PlayerJumpV2.gd")
const PlayerMovementV2 = preload("PlayerMovementV2.gd")
const CinematicLogicV2 = preload("CinematicLogicV2.gd")

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP

var is_replay_mode := false
var initial_transform: Transform
var _frame_counter := 0 # Contador de frames para limitar logs

# State para drift correction
var _was_touching_rigid := false
signal rigid_contact_ended() # Emitida cuando dejamos de tocar un RigidBody

# --- EXPORTED TUNING ---
export(float) var mouse_sensitivity := 0.005 setget set_mouse_sensitivity, get_mouse_sensitivity
export(float) var snap_length := 0.25
export(float) var push_force := 1.0 # Fuerza base del jugador para empujar rígidos
export(float) var min_pitch := -85.0
export(float) var max_pitch := 85.0
export(float) var interact_distance := 3.0

# Stair-stepping Configuration
export(float) var step_height := 0.4 # Max height to auto-climb (typical stair step)
export(float) var step_depth := 0.5 # How far forward to probe for steps (increased for reliability)
export var enable_step_up := true # Toggle stair-stepping
export(float) var step_grounded_grace := 0.15 # Seconds to stay "grounded" after stepping

# Stair-stepping state
var _step_grounded_timer := 0.0 # Grace period to keep grounded state for animations
var _just_stepped := false # Flag set when we step up

# Platform Transform Tracking (replaces velocity-based approach)
var _platform_collider: Spatial = null
var _platform_last_transform: Transform = Transform.IDENTITY
var _platform_velocity: Vector3 = Vector3.ZERO # Calculated from transform delta
var _was_on_platform := false

# 2.5D Mode State (Delegated to Component)
var sidescroll_logic: Node # SideScrollLogicV2
var _created_sidescroll_logic := false
var base_fov := 75.0
var _cached_cam: Camera = null
var _cached_spring_arm: SpringArm = null
var base_spring_length := 7.0 # Current world-target length (alpha-blended)
var base_spring_length_3d := 7.0 # User's 3D preference
var current_spring_length := 7.0 # Current ACTUAL length (smoothed)
var base_rig_y := 0.0
var base_collision_mask := 0
var _occlusion_mode_active := false
var active_25d_zones := [] # Stack of SideScrollZone nodes

func set_occlusion_mode(active: bool) -> void:
	_occlusion_mode_active = active

# state
var velocity := Vector3()
var yaw := 0.0
var pitch := 0.0
var yaw_deg := 0.0
var pitch_deg := 0.0
var external_input: InputDataV2 = null
var external_input_provided := false
var _forward_latch_active := false
var _forward_latch_sign := 1.0

# Direction Latch System - Evita cambios bruscos de dirección al entrar/salir de zonas
# Guarda el CONTEXTO de interpretación de input cuando cambia la cámara
var _direction_latch_active := false
var _latched_camera_basis := Basis.IDENTITY # Basis de cámara para interpretar input
var _latched_sidescroll_active := false # Si estábamos en modo sidescroll
var _latched_sidescroll_basis := Basis.IDENTITY # Basis del sidescroll para latched mode
var _latched_cinematic_mode := -1 # Modo de control cinemático (-1 = no cinematic)
var _latched_input_vec := Vector2.ZERO # Input que activó el latch (para saber cuándo liberar)
var _prev_sidescroll_active := false
var _prev_cinematic_rig = null # Referencia al rig cinemático anterior
var _cinematic_rig: Node = null # Referencia al rig cinemático actual
var _prev_camera_basis := Basis.IDENTITY # Basis de cámara del frame anterior

# Métodos de acceso para export (opcional, para Inspector)
func set_mouse_sensitivity(v):
	if v == null:
		mouse_sensitivity = 0.005
	else:
		mouse_sensitivity = v
func get_mouse_sensitivity(): return mouse_sensitivity

# --- SEÑALES ---
signal jumped
signal acrobatic_jumped
signal hit_ceiling
signal interactable_in_range(text)
signal interactable_out_of_range

const ACROBATIC_WINDOW_FRAMES := 15 # increased leniency (~250ms)
var frames_since_last_snap := ACROBATIC_WINDOW_FRAMES + 1 # Start expired
var last_input_vector := Vector3.ZERO
var is_acrobatic_ready := false

# --- INTERACTION ---
var _interact_ray: RayCast = null
var _current_interactable: Node = null

## --- SNAPSHOT SERIALIZACIÓN ---
func get_full_snapshot() -> Dictionary:
	var snapshot = {
		"position": [self.global_transform.origin.x, self.global_transform.origin.y, self.global_transform.origin.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"yaw": yaw,
		"pitch": pitch,
		"base_spring_length_3d": base_spring_length_3d,
		"movement_state": movement_logic.get_full_snapshot() if is_instance_valid(movement_logic) else {},
		"ss_logic": sidescroll_logic.get_full_snapshot() if is_instance_valid(sidescroll_logic) else {}
	}
	# Incluir estado del jump logic si existe
	if is_instance_valid(jump_logic):
		snapshot["jump_state"] = {
			"coyote_timer": jump_logic.coyote_timer,
			"jump_buffer_timer": jump_logic.jump_buffer_timer,
			"is_jumping": jump_logic._is_jumping
		}
	
	# Acrobatic Backflip state
	snapshot["acrobatic_state"] = {
		"frames_since_last_snap": frames_since_last_snap,
		"last_input_vector": [last_input_vector.x, last_input_vector.y, last_input_vector.z],
		"is_acrobatic_ready": is_acrobatic_ready
	}
	
	snapshot["fwd_latch_active"] = _forward_latch_active
	snapshot["fwd_latch_sign"] = _forward_latch_sign
	
	# Platform tracking state (store node path for deterministic restore)
	if _platform_collider and is_instance_valid(_platform_collider):
		snapshot["platform_path"] = _platform_collider.get_path()
		snapshot["platform_last_transform"] = {
			"origin": [_platform_last_transform.origin.x, _platform_last_transform.origin.y, _platform_last_transform.origin.z],
			"basis_x": [_platform_last_transform.basis.x.x, _platform_last_transform.basis.x.y, _platform_last_transform.basis.x.z],
			"basis_y": [_platform_last_transform.basis.y.x, _platform_last_transform.basis.y.y, _platform_last_transform.basis.y.z],
			"basis_z": [_platform_last_transform.basis.z.x, _platform_last_transform.basis.z.y, _platform_last_transform.basis.z.z]
		}
	else:
		snapshot["platform_path"] = ""
	snapshot["platform_velocity"] = [_platform_velocity.x, _platform_velocity.y, _platform_velocity.z]
	snapshot["was_on_platform"] = _was_on_platform
	
	# Stair-stepping state
	snapshot["step_grounded_timer"] = _step_grounded_timer
	snapshot["just_stepped"] = _just_stepped
	
	# Direction Latch state (para evitar cambios bruscos de dirección)
	snapshot["direction_latch_active"] = _direction_latch_active
	snapshot["latched_camera_basis"] = {
		"x": [_latched_camera_basis.x.x, _latched_camera_basis.x.y, _latched_camera_basis.x.z],
		"y": [_latched_camera_basis.y.x, _latched_camera_basis.y.y, _latched_camera_basis.y.z],
		"z": [_latched_camera_basis.z.x, _latched_camera_basis.z.y, _latched_camera_basis.z.z]
	}
	snapshot["latched_sidescroll_active"] = _latched_sidescroll_active
	snapshot["latched_sidescroll_basis"] = {
		"x": [_latched_sidescroll_basis.x.x, _latched_sidescroll_basis.x.y, _latched_sidescroll_basis.x.z],
		"y": [_latched_sidescroll_basis.y.x, _latched_sidescroll_basis.y.y, _latched_sidescroll_basis.y.z],
		"z": [_latched_sidescroll_basis.z.x, _latched_sidescroll_basis.z.y, _latched_sidescroll_basis.z.z]
	}
	snapshot["latched_cinematic_mode"] = _latched_cinematic_mode
	snapshot["latched_input_vec"] = [_latched_input_vec.x, _latched_input_vec.y]
	snapshot["prev_sidescroll_active"] = _prev_sidescroll_active
	snapshot["prev_camera_basis"] = {
		"x": [_prev_camera_basis.x.x, _prev_camera_basis.x.y, _prev_camera_basis.x.z],
		"y": [_prev_camera_basis.y.x, _prev_camera_basis.y.y, _prev_camera_basis.y.z],
		"z": [_prev_camera_basis.z.x, _prev_camera_basis.z.y, _prev_camera_basis.z.z]
	}
	if _prev_cinematic_rig and is_instance_valid(_prev_cinematic_rig):
		snapshot["prev_cinematic_rig_path"] = _prev_cinematic_rig.get_path()
	else:
		snapshot["prev_cinematic_rig_path"] = ""
	
	if _cinematic_rig and is_instance_valid(_cinematic_rig):
		snapshot["cinematic_rig_path"] = _cinematic_rig.get_path()
	else:
		snapshot["cinematic_rig_path"] = ""
	
	return snapshot

func restore_snapshot(data: Dictionary) -> void:
	if data.has("position"):
		var pos = data["position"]
		if typeof(pos) == TYPE_ARRAY:
			pos = Vector3(pos[0], pos[1], pos[2])
		var t = self.global_transform
		t.origin = pos
		self.global_transform = t
	if data.has("velocity"):
		var vel = data["velocity"]
		if typeof(vel) == TYPE_ARRAY:
			vel = Vector3(vel[0], vel[1], vel[2])
		velocity = vel
	else:
		velocity = Vector3.ZERO
	yaw = data.get("yaw", 0.0)
	pitch = data.get("pitch", 0.0)
	yaw_deg = rad2deg(yaw)
	pitch_deg = rad2deg(pitch)
	base_spring_length_3d = data.get("base_spring_length_3d", base_spring_length_3d)
	
	if data.has("movement_state") and is_instance_valid(movement_logic):
		movement_logic.restore_snapshot(data["movement_state"])
	
	if data.has("ss_logic") and is_instance_valid(sidescroll_logic):
		sidescroll_logic.restore_snapshot(data["ss_logic"])
	
	# Restaurar estado del jump logic si existe
	if data.has("jump_state"):
		var jump_state = data["jump_state"]
		if is_instance_valid(jump_logic):
			jump_logic.coyote_timer = jump_state.get("coyote_timer", 0.0)
			jump_logic.jump_buffer_timer = jump_state.get("jump_buffer_timer", 0.0)
			jump_logic.internal_velocity = jump_state.get("internal_velocity", 0.0)
			jump_logic._is_jumping = jump_state.get("is_jumping", false)
	
	_forward_latch_active = data.get("fwd_latch_active", false)
	_forward_latch_sign = data.get("fwd_latch_sign", 1.0)
	
	# Restore platform tracking state
	var platform_path = data.get("platform_path", "")
	if platform_path != "" and has_node(platform_path):
		_platform_collider = get_node(platform_path)
		var pt = data.get("platform_last_transform", {})
		if pt.has("origin"):
			var o = pt["origin"]
			var bx = pt.get("basis_x", [1, 0, 0])
			var by = pt.get("basis_y", [0, 1, 0])
			var bz = pt.get("basis_z", [0, 0, 1])
			_platform_last_transform = Transform(
				Basis(Vector3(bx[0], bx[1], bx[2]), Vector3(by[0], by[1], by[2]), Vector3(bz[0], bz[1], bz[2])),
				Vector3(o[0], o[1], o[2])
			)
	else:
		_platform_collider = null
		_platform_last_transform = Transform.IDENTITY
	var pv = data.get("platform_velocity", [0, 0, 0])
	_platform_velocity = Vector3(pv[0], pv[1], pv[2])
	_was_on_platform = data.get("was_on_platform", false)
	
	# Restore stair-stepping state
	_step_grounded_timer = data.get("step_grounded_timer", 0.0)
	_just_stepped = data.get("just_stepped", false)
	
	# Restore direction latch state
	_direction_latch_active = data.get("direction_latch_active", false)
	_prev_sidescroll_active = data.get("prev_sidescroll_active", false)
	_latched_sidescroll_active = data.get("latched_sidescroll_active", false)
	_latched_cinematic_mode = data.get("latched_cinematic_mode", -1)
	
	# Restore latched_camera_basis
	if data.has("latched_camera_basis"):
		var lcb = data["latched_camera_basis"]
		_latched_camera_basis = Basis(
			Vector3(lcb["x"][0], lcb["x"][1], lcb["x"][2]),
			Vector3(lcb["y"][0], lcb["y"][1], lcb["y"][2]),
			Vector3(lcb["z"][0], lcb["z"][1], lcb["z"][2])
		)
	else:
		_latched_camera_basis = Basis.IDENTITY
	
	# Restore latched_sidescroll_basis
	if data.has("latched_sidescroll_basis"):
		var lsb = data["latched_sidescroll_basis"]
		_latched_sidescroll_basis = Basis(
			Vector3(lsb["x"][0], lsb["x"][1], lsb["x"][2]),
			Vector3(lsb["y"][0], lsb["y"][1], lsb["y"][2]),
			Vector3(lsb["z"][0], lsb["z"][1], lsb["z"][2])
		)
	else:
		_latched_sidescroll_basis = Basis.IDENTITY
	
	# Restore latched_input_vec
	if data.has("latched_input_vec"):
		var liv = data["latched_input_vec"]
		_latched_input_vec = Vector2(liv[0], liv[1])
	else:
		_latched_input_vec = Vector2.ZERO
	
	# Restore prev_camera_basis
	if data.has("prev_camera_basis"):
		var pcb = data["prev_camera_basis"]
		_prev_camera_basis = Basis(
			Vector3(pcb["x"][0], pcb["x"][1], pcb["x"][2]),
			Vector3(pcb["y"][0], pcb["y"][1], pcb["y"][2]),
			Vector3(pcb["z"][0], pcb["z"][1], pcb["z"][2])
		)
	else:
		_prev_camera_basis = Basis.IDENTITY
	
	# Restore prev_cinematic_rig
	var prev_rig_path = data.get("prev_cinematic_rig_path", "")
	if prev_rig_path != "":
		_prev_cinematic_rig = get_node(prev_rig_path)
	else:
		_prev_cinematic_rig = null
	
	# Restore cinematic_rig
	var rig_path = data.get("cinematic_rig_path", "")
	if rig_path != "":
		_cinematic_rig = get_node(rig_path)
	else:
		_cinematic_rig = null
	
	# Restore acrobatic state
	if data.has("acrobatic_state"):
		var acro = data["acrobatic_state"]
		frames_since_last_snap = acro.get("frames_since_last_snap", ACROBATIC_WINDOW_FRAMES + 1)
		var liv = acro.get("last_input_vector", [0, 0, 0])
		last_input_vector = Vector3(liv[0], liv[1], liv[2])
		is_acrobatic_ready = acro.get("is_acrobatic_ready", false)
	
	# APLICACIÓN: Unificamos la lógica de rotación con la de step() para garantizar determinismo.
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

func full_reset() -> void:
	"""Limpieza profunda de estado para determinismo absoluto en tests."""
	velocity = Vector3.ZERO
	frames_since_last_snap = ACROBATIC_WINDOW_FRAMES + 1
	last_input_vector = Vector3.ZERO
	is_acrobatic_ready = false
	_forward_latch_active = false
	_forward_latch_sign = 1.0
	
	# Reset direction latch
	_direction_latch_active = false
	_latched_camera_basis = Basis.IDENTITY
	_latched_sidescroll_active = false
	_latched_sidescroll_basis = Basis.IDENTITY
	_latched_cinematic_mode = -1
	_latched_input_vec = Vector2.ZERO
	_prev_sidescroll_active = false
	_prev_cinematic_rig = null
	_prev_camera_basis = Basis.IDENTITY
	
	# Reset platform tracking
	_platform_collider = null
	_platform_last_transform = Transform.IDENTITY
	_platform_velocity = Vector3.ZERO
	_was_on_platform = false
	
	# Reset stair-stepping state
	_step_grounded_timer = 0.0
	_just_stepped = false
	
	yaw = 0.0
	pitch = 0.0
	yaw_deg = 0.0
	pitch_deg = 0.0
	rotation = Vector3.ZERO
	
	if is_instance_valid(movement_logic):
		movement_logic.horizontal_velocity = Vector3.ZERO
		movement_logic.wish_direction = Vector3.ZERO
		movement_logic.external_velocity = Vector3.ZERO
		movement_logic.camera_input_timer = 0.0
		movement_logic.current_turn_time = 0.0
		
	if is_instance_valid(jump_logic):
		jump_logic.internal_velocity = 0.0
		jump_logic.coyote_timer = 0.0
		jump_logic.jump_buffer_timer = 0.0
		jump_logic._is_jumping = false
		jump_logic._jump_time_tracker = 0.0
	
	if is_instance_valid(sidescroll_logic):
		sidescroll_logic.manual_yaw = 0.0
		sidescroll_logic.manual_pitch = 0.0

# Nodos (Asegúrate de que los nombres coincidan con tu escena)
onready var camera_rig = $CameraRig
onready var animator = $Visual/Pivot


# Input reconnection and camera input lock
var input_provider
var camera_input_locked := false

# Llama esto para bloquear/desbloquear input de cámara (mouse) durante transiciones
func set_camera_input_locked(locked: bool):
	camera_input_locked = locked
	if input_provider:
		input_provider.hardware_input_enabled = not locked

func ensure_input_provider():
	if not input_provider or not is_instance_valid(input_provider):
		input_provider = InputProviderV2.new()

var jump_logic: PlayerJumpV2
var movement_logic: PlayerMovementV2
var cinematic_logic: CinematicLogicV2
var _created_jump_logic := false
var _created_movement_logic := false
var _created_cinematic_logic := false

const SideScrollLogicV2 = preload("SideScrollLogicV2.gd")

func set_external_velocity(v: Vector3) -> void:
	"""API para plataformas móviles: establece velocidad externa."""
	if is_instance_valid(movement_logic):
		movement_logic.set_external_velocity(v)

func set_external_source_is_static(is_static: bool) -> void:
	if is_instance_valid(movement_logic):
		movement_logic.set_external_source_is_static(is_static)

func reconnect_input_provider():
	if not input_provider:
		ensure_input_provider()

func _ready():
	initial_transform = global_transform
	add_to_group("player")
	input_provider = InputProviderV2.new()

	# Usar componentes existentes en la escena si están presentes, para evitar duplicados
	if has_node("Logic/Jump"):
		jump_logic = get_node("Logic/Jump")
		_created_jump_logic = false
	else:
		jump_logic = PlayerJumpV2.new()
		_created_jump_logic = true
		jump_logic.name = "Jump"
		if has_node("Logic"):
			get_node("Logic").add_child(jump_logic)
		else:
			add_child(jump_logic)

	if has_node("Logic/Movement"):
		movement_logic = get_node("Logic/Movement")
		_created_movement_logic = false
	else:
		movement_logic = PlayerMovementV2.new()
		_created_movement_logic = true
		movement_logic.name = "Movement"
		if has_node("Logic"):
			get_node("Logic").add_child(movement_logic)
		else:
			add_child(movement_logic)
	
	if has_node("Logic/SideScroll"):
		sidescroll_logic = get_node("Logic/SideScroll")
		_created_sidescroll_logic = false
	else:
		sidescroll_logic = SideScrollLogicV2.new()
		_created_sidescroll_logic = true
		sidescroll_logic.name = "SideScroll"
		if has_node("Logic"):
			get_node("Logic").add_child(sidescroll_logic)
		else:
			add_child(sidescroll_logic)
	
	if has_node("Logic/Cinematic"):
		cinematic_logic = get_node("Logic/Cinematic")
		_created_cinematic_logic = false
	else:
		cinematic_logic = CinematicLogicV2.new()
		_created_cinematic_logic = true
		cinematic_logic.name = "Cinematic"
		if has_node("Logic"):
			get_node("Logic").add_child(cinematic_logic)
		else:
			add_child(cinematic_logic)

	_cached_cam = _find_camera(camera_rig)
	if _cached_cam:
		base_fov = _cached_cam.fov
	
	_cached_spring_arm = _find_spring_arm(camera_rig)
	if _cached_spring_arm:
		base_spring_length = _cached_spring_arm.spring_length
		base_collision_mask = _cached_spring_arm.collision_mask
	
	if camera_rig:
		base_rig_y = camera_rig.transform.origin.y
		# Inicializar la basis de cámara anterior para el direction latch
		_prev_camera_basis = camera_rig.global_transform.basis
	
	# Setup interaction area attached to visual
	_setup_interact_area()

const DEFAULT_BASIS = Basis.IDENTITY

func _find_camera(node: Node) -> Camera:
	if node is Camera:
		return node as Camera
	for i in range(node.get_child_count()):
		var cam = _find_camera(node.get_child(i))
		if cam:
			return cam
	return null

func _find_spring_arm(node: Node) -> SpringArm:
	if node is SpringArm:
		return node as SpringArm
	for i in range(node.get_child_count()):
		var arm = _find_spring_arm(node.get_child(i))
		if arm:
			return arm
	return null

func get_camera_basis() -> Basis:
	return camera_rig.global_transform.basis if camera_rig else DEFAULT_BASIS

func _get_move_direction(input_vector: Vector2, control_mode: int) -> Vector3:
	"""Calcula la dirección de movimiento basada en el modo de control cinemático."""
	var camera = get_viewport().get_camera()
	if not camera:
		# For headless tests or no camera, assume forward is +Z
		if input_vector.y > 0:
			return Vector3(0, 0, 1)
		elif input_vector.y < 0:
			return Vector3(0, 0, -1)
		elif input_vector.x > 0:
			return Vector3(1, 0, 0)
		elif input_vector.x < 0:
			return Vector3(-1, 0, 0)
		return Vector3.ZERO
	
	match control_mode:
		CinematicManager.ControlMode.FREE:
			# Movimiento relativo a la cámara (estándar)
			var forward = camera.global_transform.basis.z
			var right = camera.global_transform.basis.x
			forward.y = 0
			right.y = 0
			return (-right.normalized() * input_vector.x + forward.normalized() * input_vector.y)
		
		CinematicManager.ControlMode.LOCKED_VIEW:
			# "Arriba" en el stick siempre es "Hacia el fondo" de la cámara
			var forward = - camera.global_transform.basis.z
			var right = camera.global_transform.basis.x
			forward.y = 0
			right.y = 0
			return (-right.normalized() * input_vector.x + forward.normalized() * input_vector.y)
		
		CinematicManager.ControlMode.FIXED_AXIS:
			# Ignora la rotación de la cámara, usa ejes globales
			return Vector3(-input_vector.x, 0, -input_vector.y)
		
		CinematicManager.ControlMode.SIDESCROLL:
			# Restringe movimiento a un plano (X o Z según la orientación de la cámara)
			var cam_right = camera.global_transform.basis.x
			if abs(cam_right.x) > abs(cam_right.z):
				# Movimiento a lo largo del eje global X
				var sign_x = sign(cam_right.x)
				return Vector3(-input_vector.x * sign_x, 0, 0)
			else:
				# Movimiento a lo largo del eje global Z
				var sign_z = sign(cam_right.z)
				return Vector3(0, 0, -input_vector.x * sign_z)
		
		_:
			return Vector3.ZERO

var _interact_area: Area = null

func _setup_interact_area():
	"""Find or create the interaction area attached to the visual model."""
	if _interact_area:
		return
	
	# Try to find existing area in animator (Visual/Pivot)
	if animator and animator.has_node("InteractArea"):
		_interact_area = animator.get_node("InteractArea")
		return
		
	# Fallback: Create procedurally if not found (for robustness)
	_interact_area = Area.new()
	_interact_area.name = "InteractArea"
	_interact_area.monitorable = false
	_interact_area.monitoring = true
	_interact_area.collision_mask = 1 # Match interactable layer
	
	var shape = CollisionShape.new()
	var box = BoxShape.new()
	# Box suitable for "in front of pilot"
	# extend Z by interact_distance/2, and offset center by interact_distance/2
	box.extents = Vector3(0.5, 1.0, interact_distance / 2.0)
	shape.shape = box
	# Offset forward (assuming -Z is forward for the model)
	shape.transform.origin = Vector3(0, 1.0, -interact_distance / 2.0)
	
	_interact_area.add_child(shape)
	
	# Attach to animator (Visual/Pivot) so it rotates with the character
	if animator:
		animator.add_child(_interact_area)
	else:
		add_child(_interact_area)

func _process_interaction(input: InputDataV2):
	"""Check for interactables in range using Area and handle interaction input."""
	if not _interact_area:
		return
	
	var bodies = _interact_area.get_overlapping_bodies()
	var best_target = null
	var min_dist = 999.0
	
	for body in bodies:
		if is_instance_valid(body) and body.is_in_group("interactable"):
			var dist = global_transform.origin.distance_squared_to(body.global_transform.origin)
			if dist < min_dist:
				min_dist = dist
				best_target = body
				
	if best_target:
		# New interactable in range
		if _current_interactable != best_target:
			_current_interactable = best_target
			print("Interactable in range (Area): ", best_target.name)
			var text = best_target.interaction_text if best_target.get("interaction_text") else "Interact"
			emit_signal("interactable_in_range", text)
			
			# Auto-activate if auto_interact_once is enabled and hasn't been auto-triggered yet
			if best_target.get("auto_interact_once") and not best_target.get("_auto_triggered"):
				if best_target.has_method("set_active"):
					print("Auto-activating interactable: ", best_target.name)
					best_target.set_active(true)
					best_target._auto_triggered = true
		
		# Handle interaction
		if input.interact:
			print("Interact pressed on ", best_target.name)
			if best_target.has_method("interact"):
				best_target.interact()
	else:
		_clear_interactable()

func _clear_interactable():
	"""Clear current interactable and emit signal."""
	if _current_interactable != null:
		_current_interactable = null
		emit_signal("interactable_out_of_range")

func _input(event):
	if is_replay_mode:
		return

	# Si el input de cámara está bloqueado, no acumular mouse/zoom
	if camera_input_locked:
		return

	# La única responsabilidad en _input es acumular el delta del mouse
	# para que el InputProvider lo consuma en el frame de física.
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if input_provider:
				input_provider.mouse_delta_accum += event.relative

	if event.is_action_pressed("zoom_in"):
		if input_provider:
			input_provider.zoom_delta_accum -= 1.0 # Una unidad de zoom por click
	elif event.is_action_pressed("zoom_out"):
		if input_provider:
			input_provider.zoom_delta_accum += 1.0

func inject_input(data: Dictionary) -> void:
	if data == null:
		return
	var input = InputDataV2.new()
	input.from_dict(data)
	# Ensure external input is stored for the next _physics_process
	# or for manual step calls.
	external_input = input
	external_input_provided = true

	# If physics process is disabled (replay mode), we must step manually
	if not is_physics_processing():
		step(FIXED_DT, input)

func step(dt: float, input: InputDataV2) -> void:
	if input == null:
		return  # End of replay, no more input
	
	# --- CONFIGURATION SYNC ---
	# Update Input Provider config from Logic component (allows runtime tuning)
	if is_instance_valid(movement_logic) and input_provider:
		input_provider.move_response_curve = movement_logic.move_response_curve
		input_provider.camera_response_curve = movement_logic.camera_response_curve

	# Bloquea input de cámara si está lockeado
	if camera_input_locked and input_provider:
		input_provider.hardware_input_enabled = false

	# 0. State Update
	sidescroll_logic.step(dt) # Actualizar alpha al inicio para gating
	var alpha = sidescroll_logic.transition_alpha
	var in_transition = alpha > 0.0 and alpha < 1.0

	# 0.5. Interaction System
	_process_interaction(input)
	
	# Removed input lockout during transition to preserve momentum and intent

	# velocity.y and rotation state
	if is_on_floor() and velocity.y < 0:
		# Only reset if we are not moving upwards due to slope alignment
		if movement_logic.get_horizontal_velocity().y <= 0:
			velocity.y = 0
			if is_instance_valid(jump_logic):
				jump_logic.set_internal_velocity(0.0)

	# --- ROTATION, PAN & ZOOM ---
	if not sidescroll_logic.is_active:
		if input and input.mouse_delta:
			movement_logic.update_tank_mode(dt, input.mouse_delta, input.move_vec, input.jump, input.sprint)

			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or is_replay_mode:
				yaw -= input.mouse_delta.x * mouse_sensitivity
				pitch -= input.mouse_delta.y * mouse_sensitivity

			# If in tank mode, A/D (input.move_vec.x) also rotates the camera
			yaw += movement_logic.get_tank_yaw_delta(dt, input.move_vec)

			yaw_deg = rad2deg(yaw)
			pitch_deg = rad2deg(pitch)
		# Removed unnecessary error print for zero mouse_delta during OYS override

		# Limitamos el Pitch para no dar una voltereta
		pitch = clamp(pitch, deg2rad(min_pitch), deg2rad(max_pitch))
	else:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or is_replay_mode:
			sidescroll_logic.apply_pan(input.mouse_delta)

	# ZOOM (Spring Length)
	if abs(input.zoom_delta) > 0.01:
		if sidescroll_logic.is_active:
			sidescroll_logic.target_spring_length = clamp(
				sidescroll_logic.target_spring_length + input.zoom_delta,
				sidescroll_logic.spring_min,
				sidescroll_logic.spring_max
			)
		else:
			base_spring_length_3d = clamp(base_spring_length_3d + input.zoom_delta, 2.0, 20.0)

	# APLICACIÓN:
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

	# 1. Actualizar timers de los componentes
	if is_on_floor():
		jump_logic.reset_on_floor()
	else:
		jump_logic.on_air_tick(dt)

	if input.jump:
		jump_logic.buffer_jump()

	# 2. Delegar movimiento horizontal
	if sidescroll_logic.is_active:
		movement_logic.is_tank_turn_mode = false

	# Forward Latch Release Check
	if input.move_vec.y >= -0.1: # Released "Forward"
		_forward_latch_active = false

	# Assign cinematic rig based on zones
	_cinematic_rig = null
	for zone in get_tree().get_nodes_in_group("CinematicCameraZoneV2"):
		var zone_node = zone as CinematicCameraZoneV2
		if zone_node and zone_node.is_body_in_zone(self):
			_cinematic_rig = zone_node._rig_node
			break

	# --- DIRECTION LATCH SYSTEM ---
	# Detectar cambios de contexto de cámara (entrada/salida de zonas)
	var active_rig = _cinematic_rig
	var context_changed := false

	# Detectar cambio en modo sidescroll
	if sidescroll_logic.is_active != _prev_sidescroll_active:
		context_changed = true

	# Detectar cambio en rig cinemático
	if active_rig != _prev_cinematic_rig:
		context_changed = true

	# ¿Es entrada o salida?
	var entering = (sidescroll_logic.is_active and not _prev_sidescroll_active) or (active_rig != null and _prev_cinematic_rig == null)
	var exiting = (not sidescroll_logic.is_active and _prev_sidescroll_active) or (active_rig == null and _prev_cinematic_rig != null)

	# Si hay input activo y cambió el contexto, activar el latch según flags
	var has_movement_input = input.move_vec.length() > 0.1
	if context_changed and has_movement_input and not _direction_latch_active:
		var zone_latch_on_enter := true # Por defecto true, la zona puede override
		var zone_latch_on_exit := true # Por defecto true, la zona puede override
		# Consultar zona activa para sidescroll
		#if sidescroll_logic.is_active:
		#	if "latch_on_enter" in sidescroll_logic.zone:
		#		zone_latch_on_enter = sidescroll_logic.zone.latch_on_enter
		#	if "latch_on_exit" in sidescroll_logic.zone:
		#		zone_latch_on_exit = sidescroll_logic.zone.latch_on_exit
		
		# Para cinematic, buscar la zona que activó el rig
		var cinematic_zone = null
		if active_rig != null:
			# print("DEBUG: Active rig: ", active_rig.get_path())
			for zone in get_tree().get_nodes_in_group("CinematicCameraZoneV2"):
				var zone_rig = zone.get_node_or_null(zone.cinematic_rig_path)
				# print("DEBUG: Checking zone: ", zone.name, " with rig path: ", zone.cinematic_rig_path)
				
				if zone_rig == active_rig:
					cinematic_zone = zone
					# print("DEBUG: Match found: ", zone.name)
					break
		if cinematic_zone != null and cinematic_zone is Node:
			if "latch_on_enter" in cinematic_zone:
				zone_latch_on_enter = cinematic_zone.latch_on_enter
				# print("DEBUG: Zone found. latch_on_enter override: ", zone_latch_on_enter)
			if "latch_on_exit" in cinematic_zone:
				zone_latch_on_exit = cinematic_zone.latch_on_exit
		else:
			# print("DEBUG: No cinematic zone found for rig. Using default latch=true")
			pass
			
		# Si la zona activa define latch, usar esos flags
		if (zone_latch_on_enter and entering) or (zone_latch_on_exit and exiting):
			# Guardar el contexto ANTERIOR (capturado en el frame anterior)
			_latched_camera_basis = _prev_camera_basis
			_latched_sidescroll_active = _prev_sidescroll_active
			if _latched_sidescroll_active:
				_latched_sidescroll_basis = sidescroll_logic.get_target_basis()
			if _prev_cinematic_rig:
				_latched_cinematic_mode = CinematicManager.get_control_mode()
			else:
				_latched_cinematic_mode = -1
			# Guardar qué teclas activaron el latch
			_latched_input_vec = input.move_vec
			_direction_latch_active = true
			# print("DEBUG: LATCH ACTIVATED! Enter=", entering, " Exit=", exiting)

	# Activate/deactivate rig if changed
	if _cinematic_rig != _prev_cinematic_rig:
		if _cinematic_rig:
			CinematicManager.activate_rig_direct(_cinematic_rig)
		else:
			CinematicManager.deactivate_rig()

	# Actualizar las referencias "prev" para el próximo frame
	_prev_sidescroll_active = sidescroll_logic.is_active
	_prev_cinematic_rig = _cinematic_rig
	_prev_camera_basis = get_camera_basis() # Guardar basis actual para el próximo frame
	
	# Liberar el latch cuando las teclas ORIGINALES se suelten
	# Comparamos el signo de cada eje: si la tecla original ya no está activa, liberar
	if _direction_latch_active:
		var should_release := false
		# Si X estaba activo al entrar y ya no lo está (o cambió de signo)
		if abs(_latched_input_vec.x) > 0.1:
			if abs(input.move_vec.x) < 0.1 or sign(input.move_vec.x) != sign(_latched_input_vec.x):
				should_release = true
		# Si Y estaba activo al entrar y ya no lo está (o cambió de signo)
		if abs(_latched_input_vec.y) > 0.1:
			if abs(input.move_vec.y) < 0.1 or sign(input.move_vec.y) != sign(_latched_input_vec.y):
				should_release = true
		
		if should_release:
			_direction_latch_active = false
			_latched_camera_basis = Basis.IDENTITY
			_latched_sidescroll_active = false
			_latched_sidescroll_basis = Basis.IDENTITY
			_latched_cinematic_mode = -1
			_latched_input_vec = Vector2.ZERO
		
	var basis = get_camera_basis()
	var move_vec = input.move_vec
	
	# --- DIRECTION LATCH APPLICATION ---
	# Si el latch está activo, interpretar TODO el input usando el contexto ANTERIOR guardado
	if _direction_latch_active:
		if _latched_sidescroll_active:
			# Usar el modo sidescroll anterior con TODAS sus restricciones
			basis = _latched_sidescroll_basis
			# Aplicar las mismas restricciones que aplicaría sidescroll
			# En sidescroll, solo permitimos movimiento lateral (X del input)
			if not sidescroll_logic.allow_depth:
				move_vec = Vector2(input.move_vec.x, 0)
		elif _latched_cinematic_mode >= 0:
			# Usar el modo cinemático anterior para TODAS las teclas
			var world_dir = _get_move_direction(input.move_vec, _latched_cinematic_mode)
			if world_dir.length() > 0.01:
				basis = Basis.IDENTITY
				move_vec = Vector2(0, world_dir.length())
				var h_dir = Vector3(world_dir.x, 0, world_dir.z).normalized()
				if h_dir.length() > 0.01:
					basis = Basis(Vector3.UP.cross(h_dir), Vector3.UP, h_dir)
			else:
				move_vec = Vector2.ZERO
		else:
			# Usar la basis de cámara anterior (modo 3D normal)
			# Transformar el input a world space usando la basis anterior
			var forward = _latched_camera_basis.z
			var right = _latched_camera_basis.x
			forward.y = 0
			right.y = 0
			var world_dir = (right.normalized() * input.move_vec.x + forward.normalized() * input.move_vec.y)
			move_vec = Vector2(0, world_dir.length())
			if world_dir.length() > 0.01:
				basis = Basis(Vector3.UP.cross(world_dir.normalized()), Vector3.UP, world_dir.normalized())
			else:
				basis = _latched_camera_basis
	# --- CINEMATIC CONTROL MODE ---
	elif active_rig:
		var mode = CinematicManager.get_control_mode()
		var world_dir = _get_move_direction(input.move_vec, mode)
		
		# Transform world_dir back to basis-relative move_vec for process_movement
		if world_dir.length() > 0.01:
			# We use a fixed basis and put all magnitude in move_vec.y (forward)
			basis = Basis.IDENTITY
			move_vec = Vector2(0, world_dir.length())
			# We calculate the horizontal direction
			var h_dir = Vector3(world_dir.x, 0, world_dir.z).normalized()
			if h_dir.length() > 0.01:
				basis = Basis(Vector3.UP.cross(h_dir), Vector3.UP, h_dir)
		else:
			move_vec = Vector2.ZERO

	# --- ACROBATIC SNAP DETECTION (Frame-based for determinism) ---
	# Uses input.move_vec directly to capture raw intent before processing
	var current_input_3d = Vector3(input.move_vec.x, 0, input.move_vec.y).normalized()
	if current_input_3d.length() > 0.1 and last_input_vector.length() > 0.1:
		var dot_product = current_input_3d.dot(last_input_vector)
		if dot_product < -0.6: # Detección de giro 180°
			if is_acrobatic_ready:
				# Si ya estábamos listos y giramos OTRA VEZ (Double Snap), cancelamos.
				# Esto evita el backflip "al revés" cuando rectificas la dirección muy rápido.
				is_acrobatic_ready = false
				frames_since_last_snap = ACROBATIC_WINDOW_FRAMES + 1
			else:
				# Primer snap detectado
				frames_since_last_snap = 0
				is_acrobatic_ready = true
	
	# Manage acrobatic window counter
	frames_since_last_snap += 1
	if frames_since_last_snap > ACROBATIC_WINDOW_FRAMES and is_acrobatic_ready:
		is_acrobatic_ready = false
	
	if current_input_3d.length() > 0.1:
		last_input_vector = current_input_3d
	
	if _forward_latch_active and not sidescroll_logic.allow_depth:
		# FORWARD LATCH: Force controls to follow strict 2.5D path
		basis = sidescroll_logic.get_target_basis()
		
		# Calculate input direction relative to the target basis
		var target_right = basis.x
		var world_dir = Vector3.ZERO
		
		# Assuming Axis 2 is Z Lock (Move X), Axis 1 is X Lock (Move Z)
		# NOTE: This dependence on 'sidescroll_logic.lock_axis' assumes enter_mode set it correctly.
		if sidescroll_logic.lock_axis == 2: world_dir.x = _forward_latch_sign
		elif sidescroll_logic.lock_axis == 1: world_dir.z = _forward_latch_sign
		
		# Project world direction onto screen right to get input sign
		var input_x = sign(world_dir.dot(target_right))
		if abs(input_x) == 0: input_x = 1.0 # Fallback
		
		move_vec = Vector2(input_x, 0.0)
		
		# FORCE FACING UPDATE based on the latch direction
		sidescroll_logic.update_facing(input_x, dt)
		
	elif sidescroll_logic.is_active and not in_transition:
		# STRICT 2.5D: Use target basis + constraints
		basis = sidescroll_logic.get_target_basis()
		move_vec = sidescroll_logic.get_constrained_input(move_vec)
		
		# Determine actual move direction (could be different from input if restricted)
		if abs(move_vec.x) > 0.1:
			sidescroll_logic.update_facing(move_vec.x, dt)
			
		# [NEW] Apply Local Camera Rotation (Yaw/Pitch) for Look-Ahead and Tilt
		if _cached_cam:
			var target_rot = sidescroll_logic.get_cam_rotation()
			# Smoothly blend local rotation to avoid snapping on entry/exit or rapid changes
			_cached_cam.rotation = _cached_cam.rotation.linear_interpolate(target_rot, 10.0 * dt)
			
	elif _cached_cam and not sidescroll_logic.is_active:
		# Standard 3D: Ensure local camera rotation is reset (identity)
		# The SpringArm handles the orbit, the camera should face forward (0,0,0) locally.
		var current_rot = _cached_cam.rotation
		if current_rot.length_squared() > 0.001:
			_cached_cam.rotation = current_rot.linear_interpolate(Vector3.ZERO, 10.0 * dt)
	
	movement_logic.process_movement(dt, move_vec, basis, input.sprint, is_on_floor())
	
	# Override visual direction in 2.5D based on camera facing state
	# Only apply this strictly when fully in 2.5D mode and NOT in depth-movement mode
	if sidescroll_logic.is_active and not in_transition and not _forward_latch_active and not sidescroll_logic.allow_depth:
		movement_logic.wish_direction = basis.x * sidescroll_logic.facing_sign

	var h_vel = movement_logic.get_horizontal_velocity()

	velocity.x = h_vel.x
	velocity.z = h_vel.z

	# If on floor, preserve aligned Y component from movement logic
	# (Prevents speed loss on slopes)
	if is_on_floor():
		velocity.y = h_vel.y

	# 3. Aplicar Salto o Gravedad (Delegado al componente)
	var old_vy = velocity.y
	
	# --- ACROBATIC JUMP CHECK (before normal jump) ---
	if is_acrobatic_ready and is_on_floor() and jump_logic.jump_buffer_timer > 0:
		var force = jump_logic.acrobatic_jump_force
		velocity.y = force
		
		# 1. FRENADO EN SECO: Eliminamos la inercia actual para justificar el cambio de dirección
		# Multiplicamos por acrobatic_brake_factor (usualmente 0.0 para frenado instantáneo)
		velocity.x *= jump_logic.acrobatic_brake_factor
		velocity.z *= jump_logic.acrobatic_brake_factor
		
		# 2. IMPULSO HACIA ATRÁS: Usamos el vector de intención actual.
		if last_input_vector.length() > 0.1:
			var move_dir = last_input_vector.normalized()
			# Kick: Base impulse + boost.
			velocity.x += move_dir.x * jump_logic.acrobatic_backward_impulse
			velocity.z += move_dir.z * jump_logic.acrobatic_backward_impulse
			
			# Camera Visual Impact
			if is_instance_valid(sidescroll_logic) and sidescroll_logic.is_active:
				var push_val = 0.0
				if sidescroll_logic.lock_axis == 2: push_val = move_dir.x
				elif sidescroll_logic.lock_axis == 1: push_val = move_dir.z
				sidescroll_logic.manual_yaw += push_val * jump_logic.acrobatic_camera_push
		
		jump_logic.consume_jump()
		jump_logic.set_internal_velocity(force)
		is_acrobatic_ready = false
		emit_signal("acrobatic_jumped")
	else:
		# Note: We pass velocity.y just in case, but JumpV2 now uses its internal state
		velocity.y = jump_logic.step(dt, input.jump, velocity.y, is_on_floor())
		
		# Emitir señal si se inició un salto en este frame
		if velocity.y == jump_logic.jump_force and old_vy != jump_logic.jump_force:
			emit_signal("jumped")

	# --- 2.5D AXIS CONSTRAINT ---
	sidescroll_logic.apply_spatial_constraints(self)

	# --- CAMERA TRANSITION ---
	_step_camera_logic(dt)

	# 4. Aplicar velocidad externa (plataformas móviles y conveyors)
	# Solo aplicamos cuando:
	# - NO estamos en el suelo (plataformas móviles usan physics interno de Godot)
	# - O la fuente es NO estática (conveyors empujan activamente)
	var external_vel = Vector3.ZERO
	if not is_on_floor() or not movement_logic.external_source_is_static:
		external_vel = movement_logic.integrate_external_velocity(dt)
	velocity += external_vel

	# --- STAIR GROUNDED GRACE TIMER ---
	if _step_grounded_timer > 0:
		_step_grounded_timer -= dt
	_just_stepped = false

	# 5. Movimiento Final y Animación
	# El snap solo aplica cuando no estamos saltando (velocity.y <= 0)
	# infinite_inertia = false para que los RigidBodies no sean atravesados ni ignorados por la masa
	var snap_vec = Vector3.DOWN * snap_length if (velocity.y <= 0 and not input.jump) else Vector3.ZERO
	
	# --- STAIR-STEPPING (before move_and_slide) ---
	# Use wish_direction (player intent) not velocity (which might be blocked by the step)
	if enable_step_up and is_on_floor() and velocity.y <= 0:
		var step_motion = movement_logic.wish_direction if movement_logic.wish_direction.length() > 0.1 else velocity
		var step_result = _try_step_up(step_motion)
		if step_result.stepped:
			global_transform.origin = step_result.position
			_just_stepped = true
			_step_grounded_timer = step_grounded_grace # Reset grace timer
	
	velocity = move_and_slide_with_snap(velocity, snap_vec, UP, true, 4, deg2rad(45), false)
	
	# --- FLOOR INFO UPDATE (for slope alignment) ---
	_update_floor_info()
	
	# --- PLATFORM TRANSFORM TRACKING ---
	_update_platform_tracking(dt)
	
	# --- CEILING COLLISION ---
	if is_on_ceiling() and velocity.y > 0:
		velocity.y = 0
		if is_instance_valid(jump_logic):
			jump_logic.set_internal_velocity(0.0)
		emit_signal("hit_ceiling")

	# 6. Empuje Manual de Objetos (RigidBodies)
	# Como desactivamos infinite_inertia, aplicamos el impulso manualmente basado en masa
	var touched_rigid = false
	for i in get_slide_count():
		var collision = get_slide_collision(i)
		var body = collision.collider
		if is_instance_valid(body) and body is RigidBody:
			touched_rigid = true
			if body.mode == RigidBody.MODE_RIGID:
				# Solo empujamos si el choque es mayormente horizontal
				if abs(collision.normal.y) < 0.5:
					# Aplicamos impulso central: Fuerza * -Normal * dt
					# Dividimos por la masa para que los objetos pesados se muevan menos
					# (Godot apply_impulse ya tiene en cuenta la masa, pero nosotros limitamos la fuerza)
					var impulse = - collision.normal * push_force * dt
					body.apply_central_impulse(impulse)
	
	# 7. Drift Correction: detectar cuando dejamos de tocar RigidBodies
	# Emitir señal para que SessionManager guarde un checkpoint de posición
	if _was_touching_rigid and not touched_rigid:
		emit_signal("rigid_contact_ended")
	_was_touching_rigid = touched_rigid
					
	if animator:
		# Si la fuente externa NO es estática (ej: cinta transportadora, plataforma móvil),
		# restamos esa velocidad para que el animador "vea" solo el movimiento relativo del jugador.
		var anim_vel = velocity
		if not movement_logic.external_source_is_static:
			anim_vel = velocity - movement_logic.external_velocity
		animator.step_animator(dt, anim_vel)
		
	# Resetear asunción por defecto para el próximo frame
	movement_logic.external_source_is_static = true

# =============================================================================
# SLOPE & PLATFORM HELPERS (inspired by Terrestrial Characters)
# =============================================================================

func _update_floor_info() -> void:
	"""Update floor normal for slope alignment in PlayerMovementV2."""
	if not is_on_floor():
		movement_logic.set_floor_normal(Vector3.UP)
		return
	
	# Find the floor collision (normal pointing mostly upward)
	for i in get_slide_count():
		var collision = get_slide_collision(i)
		if collision.normal.y > 0.7: # Floor-like surface
			movement_logic.set_floor_normal(collision.normal)
			return
	
	movement_logic.set_floor_normal(Vector3.UP)

func is_effectively_grounded() -> bool:
	"""Returns true if player is on floor OR within the stair-stepping grace period.
	Use this for animations to avoid flickering during stair climbing."""
	return is_on_floor() or _step_grounded_timer > 0

func _update_platform_tracking(dt: float) -> void:
	"""Track moving platforms for velocity inheritance when jumping off.
	
	NOTE: We do NOT apply position deltas here because move_and_slide already
	handles carrying the player with moving floors via collision response.
	We only track the platform's velocity so we can inherit it when jumping."""
	
	var new_platform: Spatial = null
	
	# Find current floor platform
	if is_on_floor():
		for i in get_slide_count():
			var collision = get_slide_collision(i)
			if collision.normal.y > 0.7: # Floor-like surface
				var collider = collision.collider
				if collider is Spatial and not collider is StaticBody:
					new_platform = collider
					break
	
	# Platform changed or left
	if new_platform != _platform_collider:
		if _platform_collider != null and new_platform == null:
			# Just stepped OFF a moving platform - inherit its velocity
			if _platform_velocity.length() > 0.1:
				velocity += _platform_velocity
		
		_platform_collider = new_platform
		if new_platform:
			_platform_last_transform = new_platform.global_transform
		_was_on_platform = new_platform != null
	
	# Track current platform velocity (for inheritance when jumping)
	# Do NOT move the player - move_and_slide already does that via collision
	if _platform_collider != null and is_instance_valid(_platform_collider):
		var current_transform = _platform_collider.global_transform
		
		# Calculate platform velocity from transform delta
		var old_local_pos = _platform_last_transform.affine_inverse().xform(global_transform.origin)
		var new_global_pos = current_transform.xform(old_local_pos)
		var delta_pos = new_global_pos - global_transform.origin
		
		# Store velocity for inheritance (do NOT apply delta_pos - that causes double movement!)
		_platform_velocity = delta_pos / dt if dt > 0 else Vector3.ZERO
		_platform_last_transform = current_transform
	else:
		_platform_velocity = Vector3.ZERO

# =============================================================================
# STAIR-STEPPING HELPER
# =============================================================================

func _try_step_up(motion: Vector3) -> Dictionary:
	"""Attempt to step up a small obstacle (stair step).
	Returns { stepped: bool, position: Vector3 }
	
	Algorithm:
	1. Cast forward to detect obstacle at foot level
	2. If obstacle found, check if we have headroom to step up
	3. Cast down from elevated position to find the step surface
	4. If valid floor found within step_height, return the stepped-up position
	"""
	var result = {"stepped": false, "position": global_transform.origin}
	
	if motion.length_squared() < 0.0001:
		return result
	
	# Get horizontal direction of movement
	var horizontal_motion = Vector3(motion.x, 0, motion.z)
	if horizontal_motion.length_squared() < 0.0001:
		return result
	
	var move_dir = horizontal_motion.normalized()
	var origin = global_transform.origin
	
	# Use a fixed probe distance, not dependent on current speed
	# This ensures stair detection works at any walking speed
	var probe_distance = step_depth
	
	# Step 1: Check if there's a wall/obstacle at foot level
	var foot_collision = move_and_collide(move_dir * probe_distance, true, true, true)
	if foot_collision == null:
		# No obstacle, no need to step
		return result
	
	# Check if this is a wall (not a floor) - we want vertical-ish surfaces
	if foot_collision.normal.y > 0.7:
		# It's a slope, not a step
		return result
	
	# Step 2: Check clearance at step height (head room)
	var head_collision = move_and_collide(Vector3.UP * step_height, true, true, true)
	if head_collision != null:
		# Not enough head room
		return result
	
	# Step 3: Move up and try to move forward at step height
	var step_up_pos = origin + Vector3.UP * step_height
	var old_pos = global_transform.origin
	global_transform.origin = step_up_pos
	
	# Try to move forward at the elevated position
	var _forward_collision = move_and_collide(move_dir * probe_distance, true, true, true)
	
	# Step 4: Cast down to find the step surface
	var down_collision = move_and_collide(Vector3.DOWN * (step_height + 0.1), true, true, true)
	
	# Restore position for now
	global_transform.origin = old_pos
	
	if down_collision != null:
		# Check if we found a valid floor
		if down_collision.normal.y > 0.7:
			var step_surface_y = step_up_pos.y - down_collision.travel.length() + 0.02
			var height_gain = step_surface_y - origin.y
			
			# Only step if we're actually going UP and within step_height
			# Lowered minimum threshold from 0.02 to 0.01 for smoother steps
			if height_gain > 0.01 and height_gain <= step_height:
				result.stepped = true
				result.position = Vector3(origin.x, step_surface_y, origin.z)
	
	return result

func _physics_process(_delta):
	# If we are in replay mode, SessionManager is responsible for calling step()
	if is_replay_mode:
		return

	if external_input_provided and external_input:
		external_input_provided = false
		var input = external_input
		step(FIXED_DT, input)
	else:
		var input = input_provider.get_input()
		step(FIXED_DT, input)

func get_wish_direction() -> Vector3:
	"""
	Devuelve la dirección de movimiento deseada por el jugador, en coordenadas globales.
	Es usada por el animador para orientar el modelo visual.
	"""
	return movement_logic.wish_direction

# --- 2.5D API ---

func _check_forward_latch(axis: int):
	# Determine projected velocity on the FREE axis
	var projected_vel = 0.0
	if axis == 2: # Lock Z, Move X
		projected_vel = velocity.x
	elif axis == 1: # Lock X, Move Z
		projected_vel = velocity.z
	
	# Use Input directly to avoid double get_input() call which clears mouse deltas
	var forward_pressed = Input.is_action_pressed("move_forward")
	
	# If moving or facing significantly and holding Forward
	if forward_pressed:
		if abs(projected_vel) > 0.1:
			_forward_latch_active = true
			_forward_latch_sign = sign(projected_vel)
		else:
			# Fallback: Se basa en hacia dónde mira el personaje
			var facing = - global_transform.basis.z
			var free_axis_facing = facing.x if axis == 2 else facing.z
			if abs(free_axis_facing) > 0.1:
				_forward_latch_active = true
				_forward_latch_sign = sign(free_axis_facing)
	else:
		_forward_latch_active = false

func enter_25d_mode(zone_ref: Node, axis: int, value: float, invert: bool = false, target_dist: float = 0.0, _depth_allowed: bool = false):
	if not active_25d_zones.has(zone_ref):
		active_25d_zones.push_back(zone_ref)
	
	_check_forward_latch(axis)
	
	var current_pos_val = global_transform.origin.z if axis == 2 else global_transform.origin.x
	
	# Determine if ANY active zone allows depth movement
	var effective_depth = false
	for zone in active_25d_zones:
		if zone.get("allow_depth_movement"):
			effective_depth = true
			break
			
	sidescroll_logic.enter_mode(axis, value, invert, current_pos_val, effective_depth)
	if target_dist > 0.1:
		sidescroll_logic.target_spring_length = target_dist

func exit_25d_mode(zone_ref: Node):
	active_25d_zones.erase(zone_ref)
	
	if active_25d_zones.empty():
		# No more zones, exit 2.5D mode
		_forward_latch_active = false
		sidescroll_logic.exit_mode()
	else:
		# Fallback to the previous zone in the stack
		var prev_zone = active_25d_zones.back()
		# Re-trigger enter_mode with previous zone's parameters to transition smoothly
		var coord = prev_zone.global_transform.origin.z if prev_zone.lock_axis == 0 else prev_zone.global_transform.origin.x
		var axis_int = 2 if prev_zone.lock_axis == 0 else 1
		var current_pos_val = global_transform.origin.z if axis_int == 2 else global_transform.origin.x
		
		# Determine if ANY remaining active zone allows depth movement
		var effective_depth = false
		for zone in active_25d_zones:
			if zone.get("allow_depth_movement"):
				effective_depth = true
				break
		
		sidescroll_logic.enter_mode(axis_int, coord, prev_zone.invert_side, current_pos_val, effective_depth)
		if prev_zone.target_distance > 0.1:
			sidescroll_logic.target_spring_length = prev_zone.target_distance

	# If exiting all zones, release the angle
	if active_25d_zones.empty() and is_instance_valid(camera_rig):
		var b = camera_rig.transform.basis
		var euler = b.get_euler()
		yaw = euler.y
		pitch = euler.x
		yaw_deg = rad2deg(yaw)
		pitch_deg = rad2deg(pitch)

func _step_camera_logic(_dt: float):
	if not camera_rig: return
	
	var alpha = sidescroll_logic.transition_alpha
	var s_alpha = sidescroll_logic.get_smooth_alpha()
	
	if alpha > 0:
		# Disable collision in 2.5D to avoid "zoom resets" or camera snapping
		if _cached_spring_arm:
			_cached_spring_arm.collision_mask = 0
		
		# 1. Rotación (Basis)
		var orbital_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var target_basis = sidescroll_logic.get_target_basis()
		var q_from = orbital_basis.get_rotation_quat()
		var q_to = target_basis.get_rotation_quat()
		camera_rig.transform.basis = Basis(q_from.slerp(q_to, s_alpha))
		
		# 2. Posición (Deadzone + Smoothing + Transición)
		# Calculamos el lagging center (global)
		var lag_pos = sidescroll_logic.calculate_camera_pos(global_transform.origin, _dt)
		
		# Posición 3D "natural" (donde estaría el rig si fuera un child normal)
		var pos_3d = global_transform.origin + Vector3(0, base_rig_y, 0)
		
		# Posición 2.5D "ideal" (basada en el lag_pos + altura base + offset Y adicional)
		var pos_25d = lag_pos + Vector3(0, base_rig_y + sidescroll_logic.current_target_y_offset, 0)
		
		# Interpolamos globalmente para que la transición sea suave
		camera_rig.global_transform.origin = pos_3d.linear_interpolate(pos_25d, s_alpha)
		
		# 3. Otros parámetros (FOV, Spring Length)
		if _cached_cam:
			_cached_cam.fov = lerp(base_fov, sidescroll_logic.current_target_fov, s_alpha)
		
		if _cached_spring_arm:
			# Smooth zoom: transition between 3D and 2.5D target spring length
			var ss_target = sidescroll_logic.current_target_spring_length
			
			# Add depth zoom offset for smooth transitions in depth-motion areas
			var depth_zoom = sidescroll_logic.get_depth_zoom_offset(global_transform.origin)
			ss_target += depth_zoom
			
			var target_len = lerp(base_spring_length_3d, ss_target, s_alpha)
			
			current_spring_length = target_len
			_cached_spring_arm.spring_length = current_spring_length
	else:
		# Modo 3D estándar
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.transform.origin = Vector3(0, base_rig_y, 0)
		
		# Restore collisions
		if _cached_spring_arm:
			if _occlusion_mode_active:
				_cached_spring_arm.collision_mask = 0
			else:
				_cached_spring_arm.collision_mask = base_collision_mask
			
			# Smooth zoom even in 3D, returning to the stored 3D preference
			current_spring_length = lerp(current_spring_length, base_spring_length_3d, sidescroll_logic.zoom_smoothing * _dt)
			_cached_spring_arm.spring_length = current_spring_length
		
		if _cached_cam:
			_cached_cam.fov = base_fov

func _exit_tree() -> void:
	# Si el controlador creó los componentes dinámicamente, liberarlos explícitamente
	if _created_jump_logic and jump_logic and jump_logic.is_inside_tree():
		jump_logic.queue_free()

	if _created_movement_logic and movement_logic and movement_logic.is_inside_tree():
		movement_logic.queue_free()

	if _created_sidescroll_logic and sidescroll_logic and sidescroll_logic.is_inside_tree():
		sidescroll_logic.queue_free()

	if _created_cinematic_logic and cinematic_logic and cinematic_logic.is_inside_tree():
		cinematic_logic.queue_free()

# Teletransporte seguro (para checkpoints, killzones, etc)
func teleport_to(target_transform: Transform) -> void:
	global_transform = target_transform
	velocity = Vector3.ZERO
	ensure_input_provider()
	set_camera_input_locked(false)
	# Resetear cualquier input residual si aplica
	if input_provider != null:
		if input_provider.has_method("clear_buffer"):
			input_provider.clear_buffer()
	# Sincronizar cámara si existe
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig:
		cam_rig.global_transform = target_transform
