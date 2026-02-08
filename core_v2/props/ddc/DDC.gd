extends InteractableBaseV2
class_name DDC

# DDC.gd - Drone Defense Component V2
# Implements a deterministic FSM for enemy drones.

# --- EXPORTED CONFIG ---
export(float) var scan_range := 15.0
export(float) var scan_angle := 60.0
export(float) var detection_speed := 2.0 # Seconds to transition from Suspicion to Alert
export(bool) var lethal := true
export(Color) var patrol_color := Color.cyan
export(Color) var suspicion_color := Color.yellow
export(Color) var alert_color := Color.red
export(float) var patrol_scan_speed := 1.0
export(float) var suspicion_scan_speed := 3.0

# --- FSM STATES ---
enum State {
	OFFLINE,
	PATROL,
	SUSPICION,
	ALERT
}

signal state_changed(new_state)

# --- STATE VARIABLES (Snapshotted) ---
var current_state: int = State.PATROL
var state_time: float = 0.0 # Time spent in current state
var detection_progress: float = 0.0 # 0.0 to 1.0 (Suspicion -> Alert)
var scan_phase: float = 0.0 # Accumulated phase for sin() scanning
var last_known_target_pos: Vector3 = Vector3.ZERO
var target_lock_strength: float = 0.0 # 0.0 = Scanning, 1.0 = Locked on target

# --- INTERNAL REFERENCES ---
var _head: Spatial
var _raycast: RayCast
var _laser_geo: ImmediateGeometry
var _light: OmniLight
var _impact_marker: Spatial

func _ready():
	._ready() # Call parent _ready

	_head = get_node_or_null("Head")
	if _head:
		_raycast = _head.get_node_or_null("RayCast")
		_laser_geo = _head.get_node_or_null("LaserBeam")
		_light = _head.get_node_or_null("WarningLight")
		_impact_marker = _head.get_node_or_null("ImpactMarker")

	if not starts_active:
		set_state(State.OFFLINE)
	else:
		set_state(State.PATROL)

	_update_visuals()

# --- DETERMINISTIC LOGIC ---
func step(dt: float) -> void:
	if not is_active and current_state != State.OFFLINE:
		set_state(State.OFFLINE)

	if current_state == State.OFFLINE:
		return

	state_time += dt

	match current_state:
		State.PATROL:
			_process_patrol(dt)
		State.SUSPICION:
			_process_suspicion(dt)
		State.ALERT:
			_process_alert(dt)

	_update_visuals()

func _process_patrol(dt: float):
	scan_phase += dt * patrol_scan_speed
	target_lock_strength = move_toward(target_lock_strength, 0.0, dt * 2.0)

	var scan_offset = sin(scan_phase) * (scan_angle / 2.0)
	# Assuming forward is -Z, scan around Y axis
	# We set rotation relative to parent (DDC body)
	var desired_rot = Vector3(0, deg2rad(scan_offset), 0)
	if _head:
		_head.rotation.y = desired_rot.y

	if _check_for_player():
		set_state(State.SUSPICION)

func _process_suspicion(dt: float):
	scan_phase += dt * suspicion_scan_speed

	# Widen scan slightly or focus? Spec says "Escaneo rápido enfocado en el punto de interés"
	# For simplicity, we just scan faster around the last known direction or center for now.
	# Ideally we'd rotate the whole DDC body to face the target, but let's stick to head rotation.

	var scan_offset = sin(scan_phase) * (scan_angle / 4.0) # Narrower scan
	var desired_rot = Vector3(0, deg2rad(scan_offset), 0)

	# Look at last known pos?
	if last_known_target_pos != Vector3.ZERO and _head:
		var local_target = to_local(last_known_target_pos)
		var angle_to_target = atan2(local_target.x, -local_target.z) # Angle relative to forward (-Z)
		desired_rot.y = angle_to_target + deg2rad(scan_offset)

	if _head:
		_head.rotation.y = desired_rot.y

	if _check_for_player():
		detection_progress += dt / detection_speed
		if detection_progress >= 1.0:
			set_state(State.ALERT)
	else:
		detection_progress -= dt # Cool down
		if detection_progress <= 0.0:
			set_state(State.PATROL)

func _process_alert(dt: float):
	target_lock_strength = move_toward(target_lock_strength, 1.0, dt * 5.0)

	if _check_for_player():
		# Maintain lock
		if _head:
			_head.look_at(last_known_target_pos, Vector3.UP)
			# Full 3D tracking enabled
	else:
		# Lost target, go back to suspicion or patrol after a delay?
		# For now, stick to Alert but maybe timeout?
		state_time += dt
		if state_time > 5.0: # Lost for 5 seconds
			set_state(State.PATROL)

func _check_for_player() -> bool:
	if not _raycast: return false

	# Ensure raycast is updated for this frame (force logic update if needed, but physics state is read-only)
	_raycast.force_raycast_update()

	if _raycast.is_colliding():
		var collider = _raycast.get_collider()
		if collider.is_in_group("player"):
			last_known_target_pos = collider.global_transform.origin
			return true
	return false

func set_state(new_state):
	var state_int = current_state

	if typeof(new_state) == TYPE_STRING:
		match new_state.to_lower():
			"offline": state_int = State.OFFLINE
			"patrol": state_int = State.PATROL
			"suspicion": state_int = State.SUSPICION
			"alert": state_int = State.ALERT
			"aggressive": state_int = State.ALERT
			_:
				printerr("[DDC] Unknown state string: ", new_state)
				return
	elif typeof(new_state) == TYPE_INT or typeof(new_state) == TYPE_REAL:
		state_int = int(new_state)

	if current_state == state_int: return

	current_state = state_int
	print("[DDC] State changed to ", current_state)
	emit_signal("state_changed", current_state)
	state_time = 0.0

	match current_state:
		State.PATROL:
			detection_progress = 0.0
			target_lock_strength = 0.0
		State.SUSPICION:
			# Start with current progress
			pass
		State.ALERT:
			detection_progress = 1.0
			target_lock_strength = 0.0 # Will ramp up
		State.OFFLINE:
			is_active = false
			detection_progress = 0.0

	# Optional: Trigger sound cue here via _update_visuals or a signal

# --- VISUALS ---
func _update_visuals() -> void:
	if not is_inside_tree(): return

	var color = patrol_color
	var energy = 1.0

	match current_state:
		State.OFFLINE:
			color = Color(0.1, 0.1, 0.1)
			energy = 0.0
		State.PATROL:
			color = patrol_color
			energy = 1.0
		State.SUSPICION:
			color = suspicion_color
			# Pulse intensity based on detection_progress?
			energy = 1.0 + (detection_progress * 2.0)
		State.ALERT:
			color = alert_color
			# Pulse rapidly
			energy = 2.0 + sin(state_time * 10.0) * 1.0

	if _light:
		_light.light_color = color
		_light.light_energy = energy

	# Update Laser Geometry
	if _laser_geo and _raycast:
		_laser_geo.clear()
		if current_state != State.OFFLINE:
			var start = Vector3.ZERO # Local to head
			var end = Vector3(0, 0, -scan_range) # Default range

			if _raycast.is_colliding():
				var collision_point = _raycast.get_collision_point()
				# Convert global collision point to local space of the head
				end = _head.to_local(collision_point)

				# Impact marker
				if _impact_marker:
					_impact_marker.visible = true
					_impact_marker.global_transform.origin = collision_point
			else:
				if _impact_marker:
					_impact_marker.visible = false

			_laser_geo.begin(Mesh.PRIMITIVE_LINES)
			_laser_geo.set_color(color)
			_laser_geo.add_vertex(start)
			_laser_geo.add_vertex(end)
			_laser_geo.end()
		else:
			if _impact_marker: _impact_marker.visible = false

# --- OYS INTERFACE ---
func set_offline(is_offline: bool):
	# OYS helper
	set_active(not is_offline)

func move_to(target_name: String):
	# Placeholder for navigation logic if DDC moves
	pass

func play_animation(anim_name: String):
	if debug: print("[DDC] play_animation requested: ", anim_name)
	var anim_player = get_node_or_null("AnimationPlayer")
	if anim_player:
		anim_player.play(anim_name)

# --- REPLAY SNAPSHOT ---
func get_snapshot() -> Dictionary:
	var data = .get_snapshot() # Parent snapshot (active state)
	data["state"] = current_state
	data["state_time"] = state_time
	data["det_prog"] = detection_progress
	data["scan_phase"] = scan_phase
	data["last_target"] = last_known_target_pos
	data["lock_str"] = target_lock_strength

	# Also save rotation as it's deterministic but good to sync
	if _head:
		data["head_rot_y"] = _head.rotation.y
		data["head_rot_x"] = _head.rotation.x

	return data

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data) # Parent restore
	current_state = int(data.get("state", State.PATROL))
	state_time = data.get("state_time", 0.0)
	detection_progress = data.get("det_prog", 0.0)
	scan_phase = data.get("scan_phase", 0.0)
	last_known_target_pos = data.get("last_target", Vector3.ZERO)
	target_lock_strength = data.get("lock_str", 0.0)

	if _head:
		_head.rotation.y = data.get("head_rot_y", 0.0)
		_head.rotation.x = data.get("head_rot_x", 0.0)

	_update_visuals()
