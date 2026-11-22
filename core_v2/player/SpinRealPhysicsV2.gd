extends Node
const SpinFrameScript = preload("res://core_v2/systems/SpinFrame.gd")
enum Landing { NORMAL, SLIDE, TUMBLE }
const GROUND_PROBE_DISTANCE := 0.1
const EPS := 0.000001
export(float) var spin_omega := 0.0
export(float) var coriolis_ground_factor := 0.3
export(float) var spin_capsule_align_rate_rad_s := 6.0
export(float) var spin_v_safe := 12.0
export(float) var spin_v_slide := 26.0
export(float) var spin_tumble_recovery_sec := 1.8
export(float) var spin_slide_decel := 14.0
export(float) var spin_thruster_dv_max := 18.0
export(float) var spin_snap := 0.25
var spin_thruster_dv_remaining := 0.0
var _up: Vector3 = Vector3.UP
var _external_accel: Vector3 = Vector3.ZERO
var _thruster_delta_v: Vector3 = Vector3.ZERO
var _tumble_timer := 0.0
var _slide_active := false
var _was_grounded := false
var _air_landed := false
func _init() -> void:
	if spin_omega <= 0.0: spin_omega = SpinFrameScript.omega_for()
	spin_thruster_dv_remaining = spin_thruster_dv_max
func update_up(position: Vector3) -> Vector3:
	# SpinFrame conserva el último _up si |r_perp| < r_eps (zona del eje).
	_up = SpinFrameScript.up(position, _up)
	return _up
func add_spin_external_accel(accel: Vector3) -> void:
	_external_accel += accel
# Delta-v limitado por presupuesto finito.
func apply_spin_thruster(dir: Vector3, dt: float) -> float:
	if dt <= 0.0 or dir.length_squared() <= EPS or spin_thruster_dv_remaining <= 0.0: return 0.0
	var dv: float = min(spin_thruster_dv_remaining, spin_thruster_dv_max * dt)
	_thruster_delta_v += dir.normalized() * dv
	spin_thruster_dv_remaining = max(0.0, spin_thruster_dv_remaining - dv)
	return dv
# Rotación mínima para alinear el eje Y del basis a `up`, con tasa angular máxima
# fija. El caso antiparalelo elige un eje perpendicular determinista.
func align_capsule_basis(current: Basis, up: Vector3, dt: float) -> Basis:
	var target_up: Vector3 = up.normalized() if up.length_squared() > EPS else Vector3.UP
	var local_y: Vector3 = current.y.normalized()
	if local_y.length_squared() <= EPS: return current
	var angle: float = acos(clamp(local_y.dot(target_up), -1.0, 1.0))
	if angle <= 0.000001: return current
	angle = min(angle, max(0.0, spin_capsule_align_rate_rad_s * dt))
	var axis: Vector3 = local_y.cross(target_up)
	if axis.length_squared() <= EPS:
		axis = current.z if current.z.length_squared() > EPS else current.x
		if axis.length_squared() <= EPS: axis = Vector3.RIGHT
	return (Basis(axis.normalized(), angle) * current).orthonormalized()
func ground_acceleration(position: Vector3, velocity: Vector3) -> Vector3:
	return SpinFrameScript.a_centrif(position, spin_omega) \
		+ SpinFrameScript.a_coriolis(velocity, spin_omega) * coriolis_ground_factor
func air_step(position: Vector3, velocity: Vector3, dt: float, extra_accel: Vector3 = Vector3.ZERO) -> Dictionary:
	return SpinFrameScript.step_free_flight(position, velocity, spin_omega, dt, extra_accel)
func classify_landing(impact_speed: float) -> int:
	var speed: float = abs(impact_speed)
	if speed < spin_v_safe: return Landing.NORMAL
	return Landing.SLIDE if speed < spin_v_slide else Landing.TUMBLE
# Conserva la tangencial, anula la normal y frena el plano.
func slide_velocity(velocity: Vector3, up: Vector3, dt: float) -> Vector3:
	var up_dir: Vector3 = up.normalized() if up.length_squared() > EPS else Vector3.UP
	var planar: Vector3 = velocity - up_dir * velocity.dot(up_dir)
	var speed: float = planar.length()
	if speed <= 0.0001: return Vector3.ZERO
	return planar.normalized() * max(0.0, speed - spin_slide_decel * dt)
func handle_landing(controller, impact_speed: float) -> int:
	var kind: int = classify_landing(impact_speed)
	_slide_active = kind == Landing.SLIDE
	if kind == Landing.TUMBLE:
		_slide_active = false
		_tumble_timer = spin_tumble_recovery_sec
		if controller != null and controller.has_method("begin_ragdoll") \
				and not bool(controller.get("is_ragdoll")):
			controller.begin_ragdoll()
	return kind
# Devuelve true el tick en que termina la recuperación del tumble.
func tick_tumble_recovery(dt: float, controller) -> bool:
	if _tumble_timer <= 0.0: return false
	_tumble_timer = max(0.0, _tumble_timer - dt)
	if _tumble_timer > 0.0: return false
	if controller != null and controller.has_method("end_ragdoll") \
			and bool(controller.get("is_ragdoll")):
		controller.end_ragdoll()
	_was_grounded = true
	return true
func step(controller, dt: float, input) -> void:
	if controller == null or dt <= 0.0 or _tumble_timer > 0.0:
		return
	var position: Vector3 = controller.global_transform.origin
	var up: Vector3 = update_up(position)
	var incoming_velocity: Vector3 = controller.velocity
	controller.global_transform.basis = align_capsule_basis(controller.global_transform.basis, up, dt)
	var move_input: Vector2 = input.move_vec if input != null else Vector2.ZERO
	var jump_pressed: bool = input != null and input.jump
	var jump_logic = controller.get("jump_logic")
	var grounded: bool = _probe_ground(controller)
	if grounded:
		_apply_planar_input(controller, dt, input, move_input, up)
		if jump_logic != null:
			jump_logic.reset_on_floor()
	elif jump_logic != null:
		jump_logic.on_air_tick(dt)
	if jump_logic != null and jump_pressed and not bool(controller.get("_jump_was_pressed")):
		jump_logic.buffer_jump()
	var jumped: bool = grounded and jump_logic != null and jump_logic.can_jump(true)
	if jumped:
		# Salto: fija la componente sobre `up` y sale por aire en este mismo tick
		# (move_and_slide_with_snap anularia el impulso contra el piso).
		controller.velocity += up * (jump_logic.jump_force - controller.velocity.dot(up))
		jump_logic.consume_jump()
		_slide_active = false
		_was_grounded = false
	var external: Vector3 = _external_accel
	var thruster: Vector3 = _thruster_delta_v
	_external_accel = Vector3.ZERO
	_thruster_delta_v = Vector3.ZERO
	if grounded and not jumped:
		_step_grounded(controller, dt, incoming_velocity, external, thruster, up)
	else:
		_step_airborne(controller, dt, external, thruster, up)
	var grounded_now: bool = false
	if not jumped:
		grounded_now = _probe_ground(controller) or bool(controller.is_on_floor())
		if grounded_now:
			spin_thruster_dv_remaining = spin_thruster_dv_max
	_was_grounded = grounded_now or (not jumped and _air_landed)
	_air_landed = false
	controller.set("_jump_was_pressed", jump_pressed)
func _apply_planar_input(controller, dt: float, input, move_input: Vector2, up: Vector3) -> void:
	var movement_logic = controller.get("movement_logic")
	if movement_logic == null or not is_instance_valid(movement_logic): return
	var world_dir := Vector3.ZERO
	if move_input.length_squared() > 0.0001 and controller.has_method("_get_move_direction"):
		world_dir = controller._get_move_direction(move_input)
		world_dir -= up * world_dir.dot(up)
	var basis := Basis.IDENTITY
	var logic_move: Vector2 = move_input
	if world_dir.length() > 0.01:
		var b_z: Vector3 = -world_dir.normalized()
		basis = Basis(up.cross(b_z), up, b_z)
		logic_move = Vector2(0.0, -world_dir.length())
	var sprint: bool = input.sprint if input != null else false
	var crouch: bool = input.crouch if input != null else false
	movement_logic.process_movement(dt, logic_move, basis, sprint, true, crouch, up)
	var h_vel: Vector3 = movement_logic.get_horizontal_velocity()
	controller.velocity = (h_vel - up * h_vel.dot(up)) + up * controller.velocity.dot(up)
func _step_grounded(controller, dt: float, incoming_velocity: Vector3, external: Vector3, thruster: Vector3, up: Vector3) -> void:
	controller.velocity += ground_acceleration(controller.global_transform.origin, controller.velocity) * dt
	controller.velocity += external * dt + thruster
	if _slide_active:
		controller.velocity = slide_velocity(controller.velocity, up, dt)
		if controller.velocity.length() < 0.2:
			_slide_active = false
	if not _was_grounded:
		var kind: int = handle_landing(controller, max(0.0, -incoming_velocity.dot(up)))
		if kind == Landing.TUMBLE: return
		if _slide_active:
			controller.velocity = slide_velocity(controller.velocity, up, dt)
	controller.velocity = controller.move_and_slide_with_snap(
		controller.velocity, -up * spin_snap, up, true, 4, deg2rad(45), false)
	if controller.has_method("_update_floor_info"):
		controller._update_floor_info()
func _step_airborne(controller, dt: float, external: Vector3, thruster: Vector3, up: Vector3) -> void:
	var position: Vector3 = controller.global_transform.origin
	var state: Dictionary = SpinFrameScript.step_free_flight(
		position, controller.velocity + thruster, spin_omega, dt, external)
	var target_vel: Vector3 = state["velocity"]
	var delta: Vector3 = state["position"] - position
	var impact_speed: float = max(0.0, -controller.velocity.dot(up))
	var collision = controller.move_and_collide(delta) if delta.length_squared() > EPS else null
	if collision == null:
		controller.velocity = target_vel
		return
	if collision.normal.dot(up) > 0.5:
		_air_landed = true
		var kind: int = handle_landing(controller, impact_speed)
		if kind == Landing.TUMBLE:
			controller.velocity = Vector3.ZERO; return
		controller.velocity = target_vel.slide(collision.normal)
		controller.velocity -= up * controller.velocity.dot(up)
		if kind == Landing.SLIDE:
			controller.velocity = slide_velocity(controller.velocity, up, dt)
		return
	controller.velocity = target_vel.slide(collision.normal)
func _probe_ground(controller) -> bool:
	if _was_grounded and controller.is_on_floor(): return true
	if not controller.is_inside_tree() or not controller.has_method("get_world"): return false
	var world = controller.get_world()
	if world == null or world.direct_space_state == null: return false
	var from: Vector3 = controller.global_transform.origin + _up * 0.05
	var distance: float = 0.8 if _was_grounded else GROUND_PROBE_DISTANCE
	var hit: Dictionary = world.direct_space_state.intersect_ray(
		from, from - _up * distance, [controller], controller.collision_mask)
	return not hit.empty() and hit.normal.dot(_up) > 0.5
