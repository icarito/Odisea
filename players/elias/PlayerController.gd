extends KinematicBody

# Placeholder: controlador de Elías basado en PlayerTemplate
# Nota: Se moverá lógica avanzada y referencias de animación conforme al refactor

export (NodePath) var PlayerAnimationTree 
export onready var animation_tree = get_node(PlayerAnimationTree)
onready var playback = animation_tree.get("parameters/playback")

export (NodePath) var PlayerCharacterMesh
export onready var player_mesh = get_node(PlayerCharacterMesh)

export var gravity = 9.8
export var jump_force = 9
export var walk_speed = 1.3
export var run_speed = 5.5
export var dash_power = 12

# Velocidad externa aplicada por plataformas/conveyors
var platform_velocity := Vector3.ZERO
var platform_is_static_surface := false
export var snap_len := 0.5
var snap_enabled := true
export var debug_movement := false
var _debug_accum := 0.0
var last_platform_velocity := Vector3.ZERO
var airborne_inherited := Vector3.ZERO
var was_on_floor := false
export var max_platform_up_follow := 5.0
export var inherit_vertical_platform_jump := true
var just_jumped := false

var roll_node_name = "Roll"
var idle_node_name = "Idle"
var walk_node_name = "Walk"
var run_node_name = "Run"
var jump_node_name = "Jump"
var attack1_node_name = "Attack1"
var attack2_node_name = "Attack2"
var bigattack_node_name = "BigAttack"

var is_attacking = false
var is_rolling = false
var is_walking = false
var is_running = false

var direction = Vector3()
var horizontal_velocity = Vector3()
var aim_turn = 0.0
var movement = Vector3()
var vertical_velocity = Vector3()
var movement_speed = 0
var angular_acceleration = 10
var acceleration = 15
onready var ground_ray: RayCast = $GroundRay
export (NodePath) var FakeShadowPath := NodePath("$Pilot/FakeShadow")
onready var fake_shadow: MeshInstance = get_node_or_null(FakeShadowPath)

# Override local de gravedad desde zonas (WindZone)
var local_gravity_override := Vector3.ZERO

func set_gravity_override(g: Vector3) -> void:
	local_gravity_override = g

func clear_gravity_override() -> void:
	local_gravity_override = Vector3.ZERO

func _ready():
	direction = Vector3.BACK.rotated(Vector3.UP, $Camroot/h.global_transform.basis.get_euler().y)
	# Resolver sombra si no se pudo en onready
	if not is_instance_valid(fake_shadow) and FakeShadowPath != NodePath(""):
		fake_shadow = get_node_or_null(FakeShadowPath)

# Interfaz pública para que plataformas/conveyors transfieran velocidad
func set_external_velocity(v: Vector3) -> void:
	platform_velocity = v
	# Si la fuente establece explícitamente si es superficie estática, respetar; si no, mantener valor previo.

func set_external_source_is_static(is_static: bool) -> void:
	platform_is_static_surface = is_static

func _input(event):
	if event is InputEventMouseMotion:
		aim_turn = -event.relative.x * 0.015
	if event is InputEventJoypadMotion:
		aim_turn = -event.relative.x * 0.015
	if event.is_action_pressed("aim"):
		direction = $Camroot/h.global_transform.basis.z

func roll():
	if Input.is_action_just_pressed("roll"):
		if !roll_node_name in playback.get_current_node() and !jump_node_name in playback.get_current_node() and !bigattack_node_name in playback.get_current_node():
			playback.start(roll_node_name)
			horizontal_velocity = direction * dash_power

func attack1():
	if (idle_node_name in playback.get_current_node() or walk_node_name in playback.get_current_node()) and is_on_floor():
		if Input.is_action_just_pressed("attack"):
			if (is_attacking == false):
				playback.travel(attack1_node_name)

func attack2():
	if attack1_node_name in playback.get_current_node():
		if Input.is_action_just_pressed("attack"):
			playback.travel(attack2_node_name)

func attack3():
	if attack1_node_name in playback.get_current_node():
		if Input.is_action_just_pressed("attack"):
			pass

func rollattack():
	if roll_node_name in playback.get_current_node():
		if Input.is_action_just_pressed("attack"):
			playback.travel(bigattack_node_name)

func bigattack():
	if run_node_name in playback.get_current_node():
		if Input.is_action_just_pressed("attack"):
			horizontal_velocity = direction * dash_power
			playback.travel(bigattack_node_name)

func _physics_process(delta):
	rollattack()
	bigattack()
	attack1()
	attack2()
	roll()

	var on_floor = is_on_floor()
	var h_rot = $Camroot/h.global_transform.basis.get_euler().y

	movement_speed = 0
	angular_acceleration = 10
	acceleration = 15

	# Gravedad efectiva: usar override si existe
	var effective_gravity_vector := local_gravity_override if (local_gravity_override.length() > 0.01) else (Vector3.DOWN * gravity)
	var effective_gravity_mag := effective_gravity_vector.length()
	var effective_gravity_dir := effective_gravity_vector.normalized() if (effective_gravity_mag > 0.01) else Vector3.DOWN

	if not is_on_floor():
		vertical_velocity += effective_gravity_vector * 2 * delta
	else:
		# Si la gravedad efectiva apunta hacia arriba (levanta), despegar del suelo
		if effective_gravity_dir.dot(Vector3.UP) < -0.5:
			vertical_velocity = Vector3.ZERO
			# Deshabilitar snap mientras estemos bajo efecto de viento ascendente
			snap_enabled = false
		else:
			vertical_velocity = -get_floor_normal() * min(effective_gravity_mag, gravity) / 3

	if (attack1_node_name in playback.get_current_node()) or (attack2_node_name in playback.get_current_node()) or (bigattack_node_name in playback.get_current_node()):
		is_attacking = true
	else:
		is_attacking = false

	if bigattack_node_name in playback.get_current_node():
		acceleration = 3

	if roll_node_name in playback.get_current_node():
		is_rolling = true
		acceleration = 2
		angular_acceleration = 2
	else:
		is_rolling = false

	if Input.is_action_just_pressed("jump") and ((is_attacking != true) and (is_rolling != true)) and is_on_floor():
		# Capturamos velocidad actual de plataforma justo en el momento del salto (antes de posible decaimiento)
		var pv := platform_velocity
		# Fuerza de salto base
		vertical_velocity = Vector3.UP * jump_force
		# Opcional: añadir componente vertical de la plataforma si está moviéndose hacia arriba
		if inherit_vertical_platform_jump and pv.y > 0.0:
			vertical_velocity.y += min(pv.y, max_platform_up_follow)
		# Al saltar, no usamos snap este frame
		snap_enabled = false
		# Heredar inercia horizontal de la plataforma (X,Z) para conservar momentum relativo
		airborne_inherited = Vector3(pv.x, 0, pv.z)
		# Aplicar inmediatamente para que el primer frame en aire no pierda empuje
		horizontal_velocity += airborne_inherited
		# Marcar frame de salto para evitar que seguimiento vertical de plataforma lo anule
		just_jumped = true

	var has_input := (Input.is_action_pressed("forward") ||  Input.is_action_pressed("backward") ||  Input.is_action_pressed("left") ||  Input.is_action_pressed("right"))
	if has_input:
		direction = Vector3(Input.get_action_strength("left") - Input.get_action_strength("right"),
					0,
					Input.get_action_strength("forward") - Input.get_action_strength("backward"))
		direction = direction.rotated(Vector3.UP, h_rot).normalized()
		is_walking = true

		if (Input.is_action_pressed("sprint")) and (is_walking == true):
			movement_speed = run_speed
			is_running = true
		else:
			movement_speed = walk_speed
			is_running = false
	else:
		is_walking = false
		is_running = false

	if Input.is_action_pressed("aim"):
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, $Camroot/h.rotation.y, delta * angular_acceleration)
	else:
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, atan2(direction.x, direction.z) - rotation.y, delta * angular_acceleration)

	if ((is_attacking == true) or (is_rolling == true)):
		horizontal_velocity = horizontal_velocity.linear_interpolate(direction.normalized() * .01 , acceleration * delta)
	else:
		horizontal_velocity = horizontal_velocity.linear_interpolate(direction.normalized() * movement_speed, acceleration * delta)

	# Fricción fuerte: si no hay input y estamos en suelo, eliminar residual para evitar "conveyor" doble
	if not has_input and is_on_floor() and not is_attacking and not is_rolling:
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, 60.0 * delta)

	# Decaimiento de la velocidad de plataforma cuando no se actualiza
	platform_velocity = platform_velocity.linear_interpolate(Vector3.ZERO, 6.0 * delta)

	# Capturar velocidad de plataforma SOLO mientras estamos en suelo para heredar al saltar / caer
	if is_on_floor():
		last_platform_velocity = platform_velocity
		airborne_inherited = Vector3.ZERO
		# Ajuste vertical: seguir plataforma si sube para evitar empuje por colisión
		if platform_velocity.y > 0.0 and not just_jumped:
			vertical_velocity.y = min(platform_velocity.y, max_platform_up_follow)
	else:
		# Primera frame en aire: hereda última velocidad de plataforma
		if was_on_floor:
			airborne_inherited = last_platform_velocity

	# Combinar velocidad propia con la transferida por la plataforma
	# En suelo: sumar componente horizontal de platform_velocity (requerido para conveyors)
	# En aire: usar la última velocidad capturada para conservar inercia
	var effective_platform_velocity := (Vector3(platform_velocity.x, 0, platform_velocity.z) if (is_on_floor() and platform_is_static_surface) else airborne_inherited)
	var combined_horizontal = horizontal_velocity + effective_platform_velocity
	movement.z = combined_horizontal.z + vertical_velocity.z
	movement.x = combined_horizontal.x + vertical_velocity.x
	movement.y = vertical_velocity.y

	# Snap al suelo para estabilidad en plataformas
	var snap_vec := Vector3.ZERO
	if is_on_floor() and snap_enabled:
		snap_vec = Vector3.DOWN * snap_len
	else:
		snap_vec = Vector3.ZERO
		# Rehabilitar snap cuando volvamos a tocar suelo
		if is_on_floor():
			snap_enabled = true

	move_and_slide_with_snap(movement, snap_vec, Vector3.UP, false)
	was_on_floor = is_on_floor()
	# Resetear bandera tras aplicar movimiento (un solo frame de protección)
	just_jumped = false

	# Debug periódicamente
	if debug_movement:
		_debug_accum += delta
		if _debug_accum >= 0.5:
			_debug_accum = 0.0
			print("[Player] hv=", horizontal_velocity, " pv=", platform_velocity, " eff_pv=", effective_platform_velocity,
				" airborne_inherited=", airborne_inherited, " combined=", combined_horizontal,
				" has_input=", has_input, " on_floor=", on_floor, " friction_applied=",
				(not has_input and on_floor and not is_attacking and not is_rolling), " snap_vec=", snap_vec)

	# --- Sombra falsa ---
	if not is_instance_valid(fake_shadow):
		fake_shadow = get_node_or_null(FakeShadowPath)
	if is_instance_valid(fake_shadow):
		if ground_ray.is_colliding():
			var hit = ground_ray.get_collision_point()
			var dist = global_transform.origin.y - hit.y
			fake_shadow.global_transform.origin = Vector3(hit.x, hit.y + 0.01, hit.z)
			var s = clamp(0.6 + dist * 0.4, 0.5, 2.0)
			fake_shadow.scale = Vector3(s, 1.0, s)
			var mat = fake_shadow.get_surface_material(0)
			if mat:
				var alpha = clamp(1.0 - dist * 0.4, 0.2, 0.9)
				mat.albedo_color.a = alpha
			fake_shadow.visible = true
		else:
			fake_shadow.visible = false

	animation_tree["parameters/conditions/IsOnFloor"] = on_floor
	animation_tree["parameters/conditions/IsInAir"] = !on_floor
	animation_tree["parameters/conditions/IsWalking"] = is_walking
	animation_tree["parameters/conditions/IsNotWalking"] = !is_walking
	animation_tree["parameters/conditions/IsRunning"] = is_running
	animation_tree["parameters/conditions/IsNotRunning"] = !is_running
