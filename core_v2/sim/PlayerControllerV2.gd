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
export(float) var min_pitch := -85.0
export(float) var max_pitch := 85.0
export(float) var interact_distance := 3.0

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

# state
var velocity := Vector3()
var yaw := 0.0
var pitch := 0.0
var _forward_latch_active := false
var _forward_latch_sign := 1.0

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
	return camera_rig.transform.basis if camera_rig else DEFAULT_BASIS

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
	sidescroll_logic.step(dt) # Actualizar alpha al inicio para gating
	var alpha = sidescroll_logic.transition_alpha
	var in_transition = alpha > 0.0 and alpha < 1.0
	
	# 0.5. Interaction System
	_process_interaction(input)
	
	# Removed input lockout during transition to preserve momentum and intent

	# velocity.y and rotation state
	if is_on_floor() and velocity.y < 0:
		velocity.y = 0
		if is_instance_valid(jump_logic):
			jump_logic.set_internal_velocity(0.0)

	# --- ROTATION, PAN & ZOOM ---
	
	if not sidescroll_logic.is_active:
		# Update tank mode state in component
		movement_logic.update_tank_mode(dt, input.mouse_delta, input.move_vec, input.jump, input.sprint)

		# Update rotations if mouse is captured OR in replay mode (where mouse_delta comes from recorded data)
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or is_replay_mode:
			yaw -= input.mouse_delta.x * mouse_sensitivity
			pitch -= input.mouse_delta.y * mouse_sensitivity
		
		# If in tank mode, A/D (input.move_vec.x) also rotates the camera
		yaw += movement_logic.get_tank_yaw_delta(dt, input.move_vec)

		# Limitamos el Pitch para no dar una voltereta
		pitch = clamp(pitch, deg2rad(min_pitch), deg2rad(max_pitch))
	else:
		# En modo 2.5D el mouse hace "Lazy Pan"
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or is_replay_mode:
			sidescroll_logic.apply_pan(input.mouse_delta)
	
	# ZOOM (Spring Length)
	if abs(input.zoom_delta) > 0.01:
		if sidescroll_logic.is_active:
			# Update 2.5D specific target
			sidescroll_logic.target_spring_length = clamp(
				sidescroll_logic.target_spring_length + input.zoom_delta,
				sidescroll_logic.spring_min,
				sidescroll_logic.spring_max
			)
		else:
			# Update 3D preference
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
		# REGLA DE ORO: En 2.5D NO puede haber Tank Turn, o el jugador se queda "atrapado" 
		# al intentar moverse lateralmente si estaba quieto.
		movement_logic.is_tank_turn_mode = false
	
	# Forward Latch Release Check
	if input.move_vec.y >= -0.1: # Released "Forward"
		_forward_latch_active = false
		
	var basis = get_camera_basis()
	var move_vec = input.move_vec
	
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
	
	if _forward_latch_active:
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
		
	elif sidescroll_logic.is_active and not in_transition:
		# STRICT 2.5D: Use target basis + constraints
		basis = sidescroll_logic.get_target_basis()
		move_vec = sidescroll_logic.get_constrained_input(move_vec)
		move_vec.y = 0
		
		if abs(move_vec.x) > 0.1:
			sidescroll_logic.update_facing(move_vec.x)
	
	movement_logic.process_movement(dt, move_vec, basis, input.sprint, is_on_floor())
	
	# Override visual direction in 2.5D based on camera facing state
	# Only apply this strictly when fully in 2.5D mode
	if sidescroll_logic.is_active and not in_transition and not _forward_latch_active:
		movement_logic.wish_direction = basis.x * sidescroll_logic.facing_sign

	var h_vel = movement_logic.get_horizontal_velocity()

	velocity.x = h_vel.x
	velocity.z = h_vel.z

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
				sidescroll_logic.pan_offset.x += push_val * jump_logic.acrobatic_camera_push
		
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

	# 5. Movimiento Final y Animación
	# El snap solo aplica cuando no estamos saltando (velocity.y <= 0)
	# infinite_inertia = false para que los RigidBodies no sean atravesados ni ignorados por la masa
	var snap_vec = Vector3.DOWN * snap_length if velocity.y <= 0 else Vector3.ZERO
	velocity = move_and_slide_with_snap(velocity, snap_vec, UP, true, 4, deg2rad(45), false)
	
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

func _physics_process(_delta):
	if external_input_provided or is_replay_mode:
		if external_input_provided:
			external_input_provided = false
		return

	# Update Input Provider config from Logic component (allows runtime tuning)
	if is_instance_valid(movement_logic) and input_provider:
		input_provider.move_response_curve = movement_logic.move_response_curve
		input_provider.camera_response_curve = movement_logic.camera_response_curve

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

func enter_25d_mode(axis: int, value: float, invert: bool = false, target_dist: float = 0.0):
	_check_forward_latch(axis)
	sidescroll_logic.enter_mode(axis, value, invert)
	if target_dist > 0.1:
		sidescroll_logic.target_spring_length = target_dist

func exit_25d_mode():
	# Al salir, "soltamos" el ángulo actual: actualizamos yaw/pitch para que coincidan con la vista actual
	if is_instance_valid(camera_rig):
		var b = camera_rig.transform.basis
		# Extraer Euler del basis actual para que la cámara no salte al orbital anterior
		var euler = b.get_euler()
		yaw = euler.y
		pitch = euler.x
	
	_forward_latch_active = false
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
			# SMOOTH ZOOM: Transition between 3D preference and 2.5D target
			var target_len = lerp(base_spring_length_3d, sidescroll_logic.target_spring_length, alpha)
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
