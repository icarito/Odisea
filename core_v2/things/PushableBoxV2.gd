extends RigidBody

# PushableBoxV2.gd - Hybrid Deterministic Object
# Transitions between Rigid (physics) and Kinematic (resting) modes.

export(float) var settle_threshold = 0.2
export(int) var settle_frames = 15
export(bool) var debug = false

var _frames_below_threshold = 0
var _pending_snapshot = null

func _ready():
	add_to_group("replay_sync")
	# Configuración inicial: empezamos como rígido para que caiga
	mode = RigidBody.MODE_RIGID
	contact_monitor = true
	contacts_reported = 4
	
	# Conectar señal para despertar si algo nos golpea
	connect("body_entered", self, "_on_body_entered")
	
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null

func step(dt):
	if mode == RigidBody.MODE_RIGID:
		_handle_rigid_logic(dt)

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
	
	# Snap rotation to 90 degrees (PI/2)
	var euler = global_transform.basis.get_euler()
	euler.x = stepify(euler.x, PI / 2.0)
	euler.y = stepify(euler.y, PI / 2.0)
	euler.z = stepify(euler.z, PI / 2.0)
	global_transform.basis = Basis(euler)
	
	mode = RigidBody.MODE_KINEMATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_frames_below_threshold = 0

func wake_up():
	if mode == RigidBody.MODE_KINEMATIC:
		if debug:
			print("[PushableBoxV2] Wake up!")
		mode = RigidBody.MODE_RIGID
		sleeping = false
		# Dar un pequeño empujón o resetear frames para evitar re-settle inmediato
		_frames_below_threshold = 0

func _round_vec3(p_v, p_decimals):
	var multiplier = pow(10, p_decimals)
	return Vector3(
		round(p_v.x * multiplier) / multiplier,
		round(p_v.y * multiplier) / multiplier,
		round(p_v.z * multiplier) / multiplier
	)

# Interacción: Al ser golpeado por otro cuerpo
func _on_body_entered(_body):
	if mode == RigidBody.MODE_KINEMATIC:
		wake_up()

# Soporte para plataforma/conveyor o empuje directo del jugador
func set_external_velocity(vel):
	if vel.length() > 0.05:
		wake_up()
		# Si estamos en modo rígido, aplicamos un impulso proporcional
		if mode == RigidBody.MODE_RIGID:
			apply_central_impulse(vel * 0.2)

# --- Replay System (SessionManager) ---

func get_snapshot():
	var rot = global_transform.basis.get_euler()
	return {
		"pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"rot": [rot.x, rot.y, rot.z],
		"vel": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
		"ang": [angular_velocity.x, angular_velocity.y, angular_velocity.z],
		"mode": mode,
		"fbt": _frames_below_threshold
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
	
	if mode == RigidBody.MODE_RIGID:
		sleeping = false

func _physics_process(delta):
	step(delta)
