extends KinematicBody

const InputProviderV2 = preload("../input/InputProviderV2.gd")
const PlayerJumpV2 = preload("PlayerJumpV2.gd")
const PlayerMovementV2 = preload("PlayerMovementV2.gd")

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP

var is_replay_mode := false


# --- EXPORTED TUNING ---
export(float) var mouse_sensitivity := 0.005 setget set_mouse_sensitivity, get_mouse_sensitivity
export(float) var snap_length := 0.5

# 2.5D Mode State (Delegated to Component)
var sidescroll_logic: Node # SideScrollLogicV2
var _created_sidescroll_logic := false
var base_fov := 75.0
var _cached_cam: Camera = null
var _cached_spring_arm: SpringArm = null
var base_spring_length := 7.0
var base_rig_y := 0.0

# state
var velocity := Vector3()
var yaw := 0.0
var pitch := 0.0

# Métodos de acceso para export (opcional, para Inspector)
func set_mouse_sensitivity(v):
	if v == null:
		mouse_sensitivity = 0.005
	else:
		mouse_sensitivity = v
func get_mouse_sensitivity(): return mouse_sensitivity

# --- SEÑALES ---
signal jumped

## --- SNAPSHOT SERIALIZACIÓN ---
func get_full_snapshot() -> Dictionary:
	var snapshot = {
		"position": [self.global_transform.origin.x, self.global_transform.origin.y, self.global_transform.origin.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"yaw": yaw,
		"pitch": pitch,
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
			jump_logic._is_jumping = jump_state.get("is_jumping", false)
	
	# APLICACIÓN: Unificamos la lógica de rotación con la de step() para garantizar determinismo.
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

# Nodos (Asegúrate de que los nombres coincidan con tu escena)
onready var camera_rig = $CameraRig
onready var animator = $Visual/Pivot

var input_provider
var external_input_provided := false

var jump_logic: PlayerJumpV2
var movement_logic: PlayerMovementV2
var _created_jump_logic := false
var _created_movement_logic := false

const SideScrollLogicV2 = preload("SideScrollLogicV2.gd")

func set_external_velocity(v: Vector3) -> void:
	"""API para plataformas móviles: establece velocidad externa."""
	if is_instance_valid(movement_logic):
		movement_logic.set_external_velocity(v)

func set_external_source_is_static(is_static: bool) -> void:
	if is_instance_valid(movement_logic):
		movement_logic.set_external_source_is_static(is_static)

func _ready():
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
	
	_cached_cam = _find_camera(camera_rig)
	if _cached_cam:
		base_fov = _cached_cam.fov
	
	_cached_spring_arm = _find_spring_arm(camera_rig)
	if _cached_spring_arm:
		base_spring_length = _cached_spring_arm.spring_length
	
	if camera_rig:
		base_rig_y = camera_rig.transform.origin.y

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
	return camera_rig.transform.basis if camera_rig else DEFAULT_BASIS

func _input(event):
	# La única responsabilidad en _input es acumular el delta del mouse
	# para que el InputProvider lo consuma en el frame de física.
	if event is InputEventMouseMotion:
		if input_provider:
			input_provider.mouse_delta_accum += event.relative

func step(dt: float, input: InputDataV2) -> void:
	# 0. State Update
	# velocity.y and rotation state
	if is_on_floor() and velocity.y < 0:
		velocity.y = 0

	# --- ROTATION & TANK MODE ---
	# Acumulamos los ángulos solo si NO estamos en modo 2.5D
	if not sidescroll_logic.is_active:
		# Update tank mode state in component
		movement_logic.update_tank_mode(dt, input.mouse_delta, input.move_vec, input.jump, input.sprint)

		# Update rotations
		# mouse_delta always rotates the camera rig
		yaw -= input.mouse_delta.x * mouse_sensitivity
		pitch -= input.mouse_delta.y * mouse_sensitivity
		
		# If in tank mode, A/D (input.move_vec.x) also rotates the camera
		yaw += movement_logic.get_tank_yaw_delta(dt, input.move_vec)

		# Limitamos el Pitch para no dar una voltereta (aprox -85 a 85 grados)
		pitch = clamp(pitch, deg2rad(-85), deg2rad(85))

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
	# En modo 2.5D usamos la base objetivo final para que el movimiento sea estable
	# e independiente de la transición de la cámara.
	var basis = get_camera_basis()
	var move_vec = input.move_vec
	
	sidescroll_logic.step(dt) # Actualizar alpha de transición
	
	if sidescroll_logic.is_active:
		basis = sidescroll_logic.get_target_basis()
		move_vec = sidescroll_logic.get_constrained_input(move_vec)
		# En modo 2.5D, move_vec.x es el movimiento lateral (A/D) y move_vec.y es la profundidad (W/S).
		# Siempre bloqueamos la profundidad para mantenernos en el plano.
		move_vec.y = 0
		
		# Ya no aplicamos inversiones manuales. 
		# PlayerMovementV2 usa basis.x (screen right), que se orienta automáticamente 
		# según la cámara, manejando tanto el eje bloqueado como la inversión (invert_side).
	
	movement_logic.process_movement(dt, move_vec, basis, input.sprint, is_on_floor())
	var h_vel = movement_logic.get_horizontal_velocity()

	velocity.x = h_vel.x
	velocity.z = h_vel.z

	# 3. Aplicar Salto o Gravedad (Delegado al componente)
	var old_vy = velocity.y
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

	# 5. Movimiento Final y Animación
	# El snap solo aplica cuando no estamos saltando (velocity.y <= 0)
	# Usar Vector3.DOWN fijo para determinismo (no get_floor_normal())
	var snap_vec = Vector3.DOWN * snap_length if velocity.y <= 0 else Vector3.ZERO
	velocity = move_and_slide_with_snap(velocity, snap_vec, UP, true)
	
	if animator:
		# Si la fuente externa NO es estática (ej: cinta transportadora, plataforma móvil),
		# restamos esa velocidad para que el animador "vea" solo el movimiento relativo del jugador.
		var anim_vel = velocity
		if not movement_logic.external_source_is_static:
			anim_vel = velocity - movement_logic.external_velocity
		animator.step_animator(dt, anim_vel)
		
	# Resetear asunción por defecto para el próximo frame
	movement_logic.external_source_is_static = true

func _physics_process(_delta):
	if external_input_provided or is_replay_mode:
		if external_input_provided:
			external_input_provided = false
		return

	var input = input_provider.get_input()
	step(FIXED_DT, input)

func get_wish_direction() -> Vector3:
	"""
	Devuelve la dirección de movimiento deseada por el jugador, en coordenadas globales.
	Es usada por el animador para orientar el modelo visual.
	"""
	return movement_logic.wish_direction

# --- 2.5D API ---

func enter_25d_mode(axis: int, value: float, invert: bool = false):
	sidescroll_logic.enter_mode(axis, value, invert)

func exit_25d_mode():
	sidescroll_logic.exit_mode()

func _step_camera_logic(_dt: float):
	if not camera_rig: return
	
	var alpha = sidescroll_logic.transition_alpha
	
	if alpha > 0:
		# 1. Rotación (Basis)
		var orbital_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var target_basis = sidescroll_logic.get_target_basis()
		var q_from = orbital_basis.get_rotation_quat()
		var q_to = target_basis.get_rotation_quat()
		camera_rig.transform.basis = Basis(q_from.slerp(q_to, alpha))
		
		# 2. Posición (Deadzone + Smoothing + Transición)
		# Calculamos el lagging center (global)
		var lag_pos = sidescroll_logic.calculate_camera_pos(global_transform.origin, _dt)
		
		# Posición 3D "natural" (donde estaría el rig si fuera un child normal)
		var pos_3d = global_transform.origin + Vector3(0, base_rig_y, 0)
		
		# Posición 2.5D "ideal" (basada en el lag_pos + altura base + offset Y adicional)
		var pos_25d = lag_pos + Vector3(0, base_rig_y + sidescroll_logic.target_y_offset, 0)
		
		# Interpolamos globalmente para que la transición sea suave
		camera_rig.global_transform.origin = pos_3d.linear_interpolate(pos_25d, alpha)
		
		# 3. Otros parámetros (FOV, Spring Length)
		if _cached_cam:
			_cached_cam.fov = lerp(base_fov, sidescroll_logic.target_fov, alpha)
		
		if _cached_spring_arm:
			_cached_spring_arm.spring_length = lerp(base_spring_length, sidescroll_logic.target_spring_length, alpha)
	else:
		# Modo 3D estándar
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		# Volver a la posición local relativa al player
		camera_rig.transform.origin = Vector3(0, base_rig_y, 0)
		
		if _cached_cam:
			_cached_cam.fov = base_fov
		if _cached_spring_arm:
			_cached_spring_arm.spring_length = base_spring_length

func _exit_tree() -> void:
	# Si el controlador creó los componentes dinámicamente, liberarlos explícitamente
	if _created_jump_logic and jump_logic and jump_logic.is_inside_tree():
		jump_logic.queue_free()

	if _created_movement_logic and movement_logic and movement_logic.is_inside_tree():
		movement_logic.queue_free()

	if _created_sidescroll_logic and sidescroll_logic and sidescroll_logic.is_inside_tree():
		sidescroll_logic.queue_free()
