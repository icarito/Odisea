extends KinematicBody

const InputProviderV2 = preload("../input/InputProviderV2.gd")
const PlayerJumpV2 = preload("PlayerJumpV2.gd")
const PlayerMovementV2 = preload("PlayerMovementV2.gd")

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP

var is_replay_mode := false


# State para drift correction
var _was_touching_rigid := false
signal rigid_contact_ended() # Emitida cuando dejamos de tocar un RigidBody

# --- EXPORTED TUNING ---
export(float) var mouse_sensitivity := 0.005 setget set_mouse_sensitivity, get_mouse_sensitivity
export(float) var snap_length := 0.5
export(float) var push_force := 1.0 # Fuerza base del jugador para empujar rígidos

# 2.5D Mode State (Delegated to Component)
var sidescroll_logic: Node # SideScrollLogicV2
var _created_sidescroll_logic := false
var base_fov := 75.0
var _cached_cam: Camera = null
var _cached_spring_arm: SpringArm = null
var base_spring_length := 7.0
var current_spring_length := 7.0
var base_rig_y := 0.0
var base_collision_mask := 0

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
		base_collision_mask = _cached_spring_arm.collision_mask
	
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
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if input_provider:
				input_provider.mouse_delta_accum += event.relative
	
	if event.is_action_pressed("zoom_in"):
		if input_provider:
			input_provider.zoom_delta_accum -= 1.0 # Una unidad de zoom por click
	elif event.is_action_pressed("zoom_out"):
		if input_provider:
			input_provider.zoom_delta_accum += 1.0

func step(dt: float, input: InputDataV2) -> void:
	# 0. State Update
	# velocity.y and rotation state
	if is_on_floor() and velocity.y < 0:
		velocity.y = 0

	# --- ROTATION, PAN & ZOOM ---
	
	if not sidescroll_logic.is_active:
		# Update tank mode state in component
		movement_logic.update_tank_mode(dt, input.mouse_delta, input.move_vec, input.jump, input.sprint)

		# Update rotations if mouse is captured
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			yaw -= input.mouse_delta.x * mouse_sensitivity
			pitch -= input.mouse_delta.y * mouse_sensitivity
		
		# If in tank mode, A/D (input.move_vec.x) also rotates the camera
		yaw += movement_logic.get_tank_yaw_delta(dt, input.move_vec)

		# Limitamos el Pitch para no dar una voltereta (aprox -85 a 85 grados)
		pitch = clamp(pitch, deg2rad(-85), deg2rad(85))
	else:
		# En modo 2.5D el mouse hace "Lazy Pan"
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			sidescroll_logic.apply_pan(input.mouse_delta)
	
	# ZOOM (Spring Length)
	if abs(input.zoom_delta) > 0.01:
		if sidescroll_logic.is_active:
			base_spring_length = clamp(base_spring_length + input.zoom_delta, sidescroll_logic.spring_min, sidescroll_logic.spring_max)
			sidescroll_logic.target_spring_length = base_spring_length
		else:
			base_spring_length = clamp(base_spring_length + input.zoom_delta, 2.0, 20.0)

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
		
		# Update camera facing from movement
		if abs(move_vec.x) > 0.1:
			sidescroll_logic.update_facing(move_vec.x)
	
	movement_logic.process_movement(dt, move_vec, basis, input.sprint, is_on_floor())
	
	# Override visual direction in 2.5D based on camera facing state
	if sidescroll_logic.is_active:
		movement_logic.wish_direction = basis.x * sidescroll_logic.facing_sign

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
	# infinite_inertia = false para que los RigidBodies no sean atravesados ni ignorados por la masa
	var snap_vec = Vector3.DOWN * snap_length if velocity.y <= 0 else Vector3.ZERO
	velocity = move_and_slide_with_snap(velocity, snap_vec, UP, true, 4, deg2rad(45), false)
	
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
	# Al salir, "soltamos" el ángulo actual: actualizamos yaw/pitch para que coincidan con la vista actual
	if is_instance_valid(camera_rig):
		var b = camera_rig.transform.basis
		# Extraer Euler del basis actual para que la cámara no salte al orbital anterior
		var euler = b.get_euler()
		yaw = euler.y
		pitch = euler.x
	
	sidescroll_logic.exit_mode()

func _step_camera_logic(_dt: float):
	if not camera_rig: return
	
	var alpha = sidescroll_logic.transition_alpha
	
	if alpha > 0:
		# Disable collision in 2.5D to avoid "zoom resets" or camera snapping
		if _cached_spring_arm:
			_cached_spring_arm.collision_mask = 0
		
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
			# SMOOTH ZOOM
			var target_len = lerp(base_spring_length, sidescroll_logic.target_spring_length, alpha)
			current_spring_length = lerp(current_spring_length, target_len, sidescroll_logic.zoom_smoothing * _dt)
			_cached_spring_arm.spring_length = current_spring_length
			
			# PERSPECTIVE SCALING:
			# Si hacemos zoom-in (spring_length pequeño), el deadzone debe ser menor para que no se salga de pantalla.
			# Usamos un ratio basado en la distancia actual vs la distancia base.
			var zoom_factor = current_spring_length / 7.0 # 7.0 es la distancia de referencia
			sidescroll_logic.deadzone_x = clamp(1.5 * zoom_factor, 0.2, 4.0)
	else:
		# Modo 3D estándar
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		camera_rig.transform.origin = Vector3(0, base_rig_y, 0)
		
		# Restore collisions
		if _cached_spring_arm:
			_cached_spring_arm.collision_mask = base_collision_mask
			# Smooth zoom even in 3D
			current_spring_length = lerp(current_spring_length, base_spring_length, sidescroll_logic.zoom_smoothing * _dt)
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
