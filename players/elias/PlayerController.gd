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
onready var fake_shadow: MeshInstance = $FakeShadow

func _ready():
	direction = Vector3.BACK.rotated(Vector3.UP, $Camroot/h.global_transform.basis.get_euler().y)

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

	if not is_on_floor():
		vertical_velocity += Vector3.DOWN * gravity * 2 * delta
	else:
		vertical_velocity = -get_floor_normal() * gravity / 3

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
		vertical_velocity = Vector3.UP * jump_force

	if (Input.is_action_pressed("forward") ||  Input.is_action_pressed("backward") ||  Input.is_action_pressed("left") ||  Input.is_action_pressed("right")):
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

	movement.z = horizontal_velocity.z + vertical_velocity.z
	movement.x = horizontal_velocity.x + vertical_velocity.x
	movement.y = vertical_velocity.y
	move_and_slide(movement, Vector3.UP)

	# --- Sombra falsa ---
	if ground_ray.is_colliding():
		var hit = ground_ray.get_collision_point()
		var dist = global_transform.origin.y - hit.y
		# Posición
		fake_shadow.global_transform.origin = Vector3(hit.x, hit.y + 0.01, hit.z)
		# Escala dependiente de distancia al suelo (clamp para prototipo)
		var s = clamp(0.6 + dist * 0.4, 0.5, 2.0)
		fake_shadow.scale = Vector3(s, 1.0, s)
		# Opacidad simple: más transparente si está alto
		var mat := fake_shadow.get_surface_material(0)
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
