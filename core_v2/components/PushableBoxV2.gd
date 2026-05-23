extends RigidBody
class_name PushableBoxV2
tool

# PushableBoxV2.gd - Hybrid Deterministic Object
# Transitions between Rigid (physics) and Kinematic (resting) modes.

export(float) var settle_threshold = 0.2
export(int) var settle_frames = 15
export(bool) var debug = false
export(Vector3) var size = Vector3(2, 2, 2) setget set_size
export(float) var impact_min_speed = 1.4
export(float) var impact_cooldown = 0.12
export(float) var external_velocity_gain = 12.0
export(float) var external_force_max_accel = 16.0

# Configuración de Snap
export(bool) var snap_rotation = true
export(float) var rotation_snap_degrees = 90.0
export(float) var settle_lerp_speed = 10.0
export(int) var wake_check_interval_frames = 3
export(bool) var wake_on_body_exit = false
export(float, 0.0, 1.0) var support_contact_min_up_dot = 0.35

var _frames_below_threshold = 0
var _pending_snapshot = null
var _target_basis = null
var _impact_cooldown_left = 0.0
var _impact_sound_index = 0
var _impact_players = []
var _sfx_drag = null
var _perf_monitor = null
var _wake_check_frame_countdown = 0
var _support_normal := Vector3.UP
var _has_support_contact := false

func _init():
	add_to_group("pushable")
	add_to_group("replay_sync")

func _ready():
	# Configuración inicial: empezamos como rígido para que caiga
	mode = RigidBody.MODE_RIGID
	contact_monitor = true
	contacts_reported = 4
	
	_update_size()
	_setup_impact_players()
	
	# Conectar señal para despertar si algo nos golpea
	connect("body_entered", self, "_on_body_entered")
	
	_sfx_drag = get_node_or_null("SFX Drag")
	
	# WakeArea para detectar presencia del jugador/otros y despertar
	var wake_area = get_node_or_null("WakeArea")
	if wake_area:
		wake_area.connect("body_entered", self, "_on_body_entered")
		wake_area.connect("body_exited", self, "_on_body_exited")
	
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null

	# Register with Performance Monitor
	if Engine.has_singleton("PerformanceMonitor") or has_node("/root/PerformanceMonitor"):
		_perf_monitor = get_node("/root/PerformanceMonitor")
		if _perf_monitor and _perf_monitor.has_method("register_monitored_node"):
			_perf_monitor.register_monitored_node(self)

func step(dt):
	if _perf_monitor and _perf_monitor.has_method("measure_start"):
		_perf_monitor.measure_start(self, "step")

	if mode == RigidBody.MODE_RIGID:
		_handle_rigid_logic(dt)
	elif mode == RigidBody.MODE_KINEMATIC:
		# Throttle expensive overlap scans when box is sleeping/kinematic.
		if _wake_check_frame_countdown <= 0:
			_refresh_support_contact_probe()
			_check_kinematic_wakeup()
			_wake_check_frame_countdown = max(0, wake_check_interval_frames - 1)
		else:
			_wake_check_frame_countdown -= 1
		if _target_basis != null:
			_handle_smooth_rotation(dt)

	if _perf_monitor and _perf_monitor.has_method("measure_end"):
		_perf_monitor.measure_end(self, "step")

func _handle_smooth_rotation(dt):
	var current_q = global_transform.basis.get_rotation_quat()
	var target_q = _target_basis.get_rotation_quat()
	
	if current_q.dot(target_q) > 0.9999: # Muy cerca
		global_transform.basis = _target_basis
		_target_basis = null
		return
		
	var lerp_val = 10.0
	if settle_lerp_speed != null:
		lerp_val = settle_lerp_speed
		
	var next_q = current_q.slerp(target_q, lerp_val * dt)
	global_transform.basis = Basis(next_q)

func _handle_rigid_logic(_dt):
	var vel = linear_velocity.length()
	var ang = angular_velocity.length()
	
	if _sfx_drag:
		# print("[PushableBoxV2] Rigid Logic. Vel: ", vel)
		# Play drag sound if moving fast enough and on the ground (approx)
		# We use a simple check; for more accuracy we could check collision normals
		if vel > 0.1:
			if not _sfx_drag.playing:
				_sfx_drag.play_sfx()
		else:
			if _sfx_drag.playing:
				_sfx_drag.stop_sfx()

	if vel < settle_threshold and ang < (settle_threshold * 2.0):
		_frames_below_threshold += 1
		if _frames_below_threshold >= settle_frames:
			_settle()
	else:
		_frames_below_threshold = 0

func _get_world_up_direction() -> Vector3:
	if has_node("/root/GravityWorld"):
		var gravity_world = get_node("/root/GravityWorld")
		if gravity_world and gravity_world.has_method("get_physical_gravity"):
			var gravity: Vector3 = gravity_world.get_physical_gravity(global_transform.origin)
			if gravity.length_squared() > 0.0001:
				return -gravity.normalized()
	return Vector3.UP

func _project_vector_onto_plane(vector: Vector3, normal: Vector3) -> Vector3:
	if normal.length_squared() <= 0.0001:
		return vector
	return vector - normal * vector.dot(normal)

func _get_effective_support_normal() -> Vector3:
	return _support_normal if _has_support_contact else _get_world_up_direction()

func _refresh_support_contact_from_state(state) -> void:
	var up_dir := _get_world_up_direction()
	var best_dot: float = support_contact_min_up_dot
	var best_normal: Vector3 = up_dir
	var found: bool = false

	for i in range(state.get_contact_count()):
		var local_normal: Vector3 = state.get_contact_local_normal(i)
		if local_normal.length_squared() <= 0.0001:
			continue
		var world_normal: Vector3 = global_transform.basis.xform(local_normal).normalized()
		var up_dot: float = world_normal.dot(up_dir)
		if up_dot > best_dot:
			best_dot = up_dot
			best_normal = world_normal
			found = true

	_has_support_contact = found
	_support_normal = best_normal if found else up_dir

func _refresh_support_contact_probe() -> void:
	var up_dir := _get_world_up_direction()
	var half_height := max(0.5, _get_global_height() * 0.5)
	var from := global_transform.origin + up_dir * min(half_height, 0.6)
	var to := global_transform.origin - up_dir * (half_height + 0.8)
	var hit = get_world().direct_space_state.intersect_ray(from, to, [self])
	if hit and hit.has("normal"):
		var hit_normal = hit.normal
		if hit_normal is Vector3 and hit_normal.length_squared() > 0.0001:
			var support_normal: Vector3 = (hit_normal as Vector3).normalized()
			if support_normal.dot(up_dir) >= support_contact_min_up_dot:
				_has_support_contact = true
				_support_normal = support_normal
				return
	_has_support_contact = false
	_support_normal = up_dir

func _settle():
	if debug:
		print("[PushableBoxV2] Settling at ", global_transform.origin)
	
	# Round position to 4 decimals for determinism
	global_transform.origin = _round_vec3(global_transform.origin, 4)
	
	if snap_rotation:
		# Calculate Target Basis
		var euler = global_transform.basis.get_euler()
		var snap_rad = deg2rad(rotation_snap_degrees)
		if snap_rad > 0:
			euler.x = stepify(euler.x, snap_rad)
			euler.y = stepify(euler.y, snap_rad)
			euler.z = stepify(euler.z, snap_rad)
			
			var target_b = Basis(euler)
			var lerp_val = 10.0
			if settle_lerp_speed != null:
				lerp_val = settle_lerp_speed
				
			if lerp_val > 0:
				_target_basis = target_b
			else:
				global_transform.basis = target_b
	
	mode = RigidBody.MODE_KINEMATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_frames_below_threshold = 0
	
	if _sfx_drag and _sfx_drag.playing:
		_sfx_drag.stop_sfx()
		
	_refresh_support_contact_probe()
	_refresh_wake_area()

func wake_up():
	if mode == RigidBody.MODE_KINEMATIC:
		if debug:
			print("[PushableBoxV2] Wake up!")
		mode = RigidBody.MODE_RIGID
		sleeping = false
		_target_basis = null
		_wake_check_frame_countdown = 0
		# Dar un pequeño empujón o resetear frames para evitar re-settle inmediato
		_frames_below_threshold = 0
		_refresh_support_contact_probe()

func _round_vec3(p_v, p_decimals):
	var multiplier = pow(10, p_decimals)
	return Vector3(
		round(p_v.x * multiplier) / multiplier,
		round(p_v.y * multiplier) / multiplier,
		round(p_v.z * multiplier) / multiplier
	)

func set_size(p_size):
	size = p_size
	if is_inside_tree():
		_update_size()

func _update_size():
	var mesh = get_node_or_null("BoxMesh")
	if mesh and mesh is CSGBox:
		mesh.width = size.x
		mesh.height = size.y
		mesh.depth = size.z
	
	var col = get_node_or_null("CollisionShape")
	if col:
		# Asegurar que el recurso de forma sea único
		if not col.shape or col.shape.resource_local_to_scene == false:
			col.shape = col.shape.duplicate() if col.shape else BoxShape.new()
		
		# Extents are half-size
		col.shape.extents = size / 2.0
		
	_refresh_wake_area()

func _refresh_wake_area():
	var wake_col = get_node_or_null("WakeArea/WakeShape")
	if not wake_col: return
	
	if not wake_col.shape or wake_col.shape.resource_local_to_scene == false:
		wake_col.shape = wake_col.shape.duplicate() if wake_col.shape else BoxShape.new()
	
	# Base local extents
	var extents = size / 2.0
	
	# Detectar qué eje local está alineado con el UP global
	# Transformamos el Vector3.UP global al espacio local de la caja
	var local_up = global_transform.basis.xform_inv(Vector3.UP).abs()
	
	var margin_side = 0.05
	var margin_vertical = 0.05
	
	var final_extents = Vector3.ZERO
	
	# Si local_up.y es el valor preeminente, el eje Y local es el vertical global
	if local_up.y > local_up.x and local_up.y > local_up.z:
		final_extents = Vector3(extents.x + margin_side, max(0.01, extents.y + margin_vertical), extents.z + margin_side)
	# Si local_up.x es el preeminente, el eje X local es el vertical global
	elif local_up.x > local_up.y and local_up.x > local_up.z:
		final_extents = Vector3(max(0.01, extents.x + margin_vertical), extents.y + margin_side, extents.z + margin_side)
	# Si no, es el Z
	else:
		final_extents = Vector3(extents.x + margin_side, extents.y + margin_side, max(0.01, extents.z + margin_vertical))
	
	wake_col.shape.extents = final_extents

# Obtiene la altura aproximada en el eje Y global
func _get_global_height():
	var local_up = global_transform.basis.xform_inv(Vector3.UP).abs()
	if local_up.y > local_up.x and local_up.y > local_up.z:
		return size.y
	elif local_up.x > local_up.y and local_up.x > local_up.z:
		return size.x
	else:
		return size.z

# Interacción: Al ser golpeado por otro cuerpo
func _on_body_entered(body):
	_try_play_impact_sfx(body)

	if mode == RigidBody.MODE_KINEMATIC:
		if _should_wake_from_body(body):
			wake_up()

func _on_body_exited(_body):
	if not wake_on_body_exit:
		return
	if mode == RigidBody.MODE_KINEMATIC:
		if debug:
			print("[PushableBoxV2] Body exited, waking up to check gravity.")
		wake_up()

func _check_kinematic_wakeup():
	var wake_area = get_node_or_null("WakeArea")
	if not wake_area: return
	
	for body in wake_area.get_overlapping_bodies():
		if body == self: continue
		if not is_instance_valid(body): continue
		
		# 1. Detectar movimiento del jugador u otros RigidBodies
		var vel = body.get("linear_velocity")
		if vel is Vector3 and vel.length_squared() > 0.01:
			wake_up()
			return
			
		# 2. Detectar interactuables en movimiento (Puertas, etc)
		var potential_interactable = body
		# Buscamos hacia arriba en la jerarquía (StaticBody -> BladePivot -> IrisMechanism)
		for _i in range(3):
			if not potential_interactable: break
			if potential_interactable.has_method("get_snapshot") and potential_interactable.get("target_progress") != null:
				var prog = potential_interactable.get("anim_progress")
				var target = potential_interactable.get("target_progress")
				if prog != null and target != null and abs(prog - target) > 0.001:
					if debug:
						print("[PushableBoxV2] Waking up because supporting interactable %s is moving." % potential_interactable.name)
					wake_up()
					return
				break
			potential_interactable = potential_interactable.get_parent()

func _should_wake_from_body(body) -> bool:
	if body == null or body == self:
		return false
	if body is StaticBody:
		return false
	if body is RigidBody:
		return true
	if body is KinematicBody:
		return true
	if body is Node and (body as Node).is_in_group("player"):
		return true

	var vel = body.get("linear_velocity") if body is Object else null
	if vel is Vector3 and vel.length_squared() > 0.01:
		return true

	return false

func _setup_impact_players():
	_impact_players = [
		get_node_or_null("ImpactSfx1"),
		get_node_or_null("ImpactSfx2"),
		get_node_or_null("ImpactSfx3"),
		get_node_or_null("ImpactSfx4")
	]

func _try_play_impact_sfx(body):
	if _impact_cooldown_left > 0.0:
		return
	if _impact_players.empty():
		return

	var other_velocity = Vector3.ZERO
	if is_instance_valid(body):
		var candidate_velocity = body.get("linear_velocity")
		if candidate_velocity is Vector3:
			other_velocity = candidate_velocity

	var relative_speed = (linear_velocity - other_velocity).length()
	if relative_speed < impact_min_speed:
		return

	var player = _impact_players[_impact_sound_index % _impact_players.size()]
	_impact_sound_index += 1
	_impact_cooldown_left = impact_cooldown
	if player and player.has_method("play"):
		player.play()

# Soporte para plataforma/conveyor o empuje directo del jugador
func set_external_velocity(vel):
	if mode == RigidBody.MODE_KINEMATIC:
		wake_up()
	else:
		_refresh_support_contact_probe()
	
	if mode == RigidBody.MODE_RIGID:
		# Queremos que la caja alcance la velocidad 'vel' pero no la supere.
		# Usamos un controlador proporcional: Fuerza = ganancia * masa * (target_v - current_v)
		var support_normal := _get_effective_support_normal()
		var target_v = vel
		var current_v = linear_velocity
		if _has_support_contact:
			target_v = _project_vector_onto_plane(target_v, support_normal)
			current_v = _project_vector_onto_plane(current_v, support_normal)
		elif abs(vel.y) < 0.2:
			# Fallback legacy para superficies planas sin contacto cacheado.
			target_v.y = 0
			current_v.y = 0
		
		var diff = target_v - current_v

		var target_accel = diff * external_velocity_gain
		if external_force_max_accel > 0.0 and target_accel.length() > external_force_max_accel:
			target_accel = target_accel.normalized() * external_force_max_accel
		var force = target_accel * mass
		add_central_force(force)
		
		if debug and force.length() > 0.1:
			print("[PushableBoxV2] set_ext_vel: force=%s" % force)

func _integrate_forces(state) -> void:
	_refresh_support_contact_from_state(state)

# --- Replay System (SessionManager) ---

func get_snapshot():
	var rot = global_transform.basis.get_euler()
	return {
		"pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"rot": [rot.x, rot.y, rot.z],
		"vel": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
		"ang": [angular_velocity.x, angular_velocity.y, angular_velocity.z],
		"mode": mode,
		"fbt": _frames_below_threshold,
		"size": [size.x, size.y, size.z],
		"snap_rot": snap_rotation,
		"snap_deg": rotation_snap_degrees
	}

func restore_snapshot(data):
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_apply_snapshot(data)

func _apply_snapshot(data):
	if data.has("mode"):
		mode = data["mode"]
	
	if data.has("pos"):
		var p = data["pos"]
		global_transform.origin = Vector3(p[0], p[1], p[2])
	
	if data.has("rot"):
		var r = data["rot"]
		global_transform.basis = Basis(Vector3(r[0], r[1], r[2]))
	
	if data.has("vel"):
		var v = data["vel"]
		linear_velocity = Vector3(v[0], v[1], v[2])
		
	if data.has("ang"):
		var a = data["ang"]
		angular_velocity = Vector3(a[0], a[1], a[2])
	
	if data.has("fbt"):
		_frames_below_threshold = data["fbt"]
	
	if data.has("size"):
		var s = data["size"]
		size = Vector3(s[0], s[1], s[2])
		_update_size()
	
	if data.has("snap_rot"):
		snap_rotation = data["snap_rot"]
	if data.has("snap_deg"):
		rotation_snap_degrees = data["snap_deg"]
	
	if mode == RigidBody.MODE_RIGID:
		sleeping = false

func _physics_process(delta):
	# print("[PushableBoxV2] physics step. Mode: ", mode)
	if _impact_cooldown_left > 0.0:
		_impact_cooldown_left = max(0.0, _impact_cooldown_left - delta)
	step(delta)
