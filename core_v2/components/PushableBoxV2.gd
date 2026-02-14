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

# Configuración de Snap
export(bool) var snap_rotation = true
export(float) var rotation_snap_degrees = 90.0
export(float) var settle_lerp_speed = 10.0

var _frames_below_threshold = 0
var _pending_snapshot = null
var _target_basis = null
var _impact_cooldown_left = 0.0
var _impact_sound_index = 0
var _impact_players = []
var _perf_monitor = null

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
	
	# WakeArea para detectar presencia del jugador/otros y despertar
	var wake_area = get_node_or_null("WakeArea")
	if wake_area:
		wake_area.connect("body_entered", self, "_on_body_entered")
	
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null

	# Register with Performance Monitor
	if Engine.has_singleton("PerformanceMonitor") or has_node("/root/PerformanceMonitor"):
		_perf_monitor = get_node("/root/PerformanceMonitor")
		if _perf_monitor: _perf_monitor.register_monitored_node(self)

func step(dt):
	if _perf_monitor: _perf_monitor.measure_start(self, "step")

	if mode == RigidBody.MODE_RIGID:
		_handle_rigid_logic(dt)
	elif mode == RigidBody.MODE_KINEMATIC and _target_basis != null:
		_handle_smooth_rotation(dt)

	if _perf_monitor: _perf_monitor.measure_end(self, "step")

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
	
	if vel < settle_threshold and ang < (settle_threshold * 2.0):
		_frames_below_threshold += 1
		if _frames_below_threshold >= settle_frames:
			_settle()
	else:
		_frames_below_threshold = 0

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
	
	_refresh_wake_area()

func wake_up():
	if mode == RigidBody.MODE_KINEMATIC:
		if debug:
			print("[PushableBoxV2] Wake up!")
		mode = RigidBody.MODE_RIGID
		sleeping = false
		_target_basis = null
		# Dar un pequeño empujón o resetear frames para evitar re-settle inmediato
		_frames_below_threshold = 0

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
	var margin_vertical = -0.1
	
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
		if is_instance_valid(body):
			# Ignorar si el cuerpo está claramente arriba (prevención de pisotón)
			var h = _get_global_height()
			if body.global_transform.origin.y > global_transform.origin.y + (h * 0.4):
				return
		wake_up()

func _setup_impact_players():
	_impact_players = [
		get_node_or_null("ImpactSfx1"),
		get_node_or_null("ImpactSfx2"),
		get_node_or_null("ImpactSfx3")
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
	
	if mode == RigidBody.MODE_RIGID:
		# Queremos que la caja alcance la velocidad 'vel' pero no la supere.
		# Usamos un controlador proporcional: Fuerza = ganancia * masa * (target_v - current_v)
		var target_v = vel
		var current_v = linear_velocity
		
		# Si el transportador es principalmente horizontal, ignoramos el eje Y
		# para no pelear contra la gravedad o saltos.
		if abs(vel.y) < 0.2:
			target_v.y = 0
			current_v.y = 0
		
		var diff = target_v - current_v
		
		# Usamos una ganancia de 20.0 para igualar la aceleración típica del jugador.
		# Esto hace que la caja se pegue a la velocidad del transportador rápidamente.
		var force = diff * mass * 20.0
		add_central_force(force)
		
		if debug and force.length() > 0.1:
			print("[PushableBoxV2] set_ext_vel: force=%s" % force)

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
	if _impact_cooldown_left > 0.0:
		_impact_cooldown_left = max(0.0, _impact_cooldown_left - delta)
	step(delta)
