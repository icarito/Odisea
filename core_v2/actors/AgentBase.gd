extends KinematicBody
# class_name AgentBase - REPLACED BY EXPLICIT RESOURCE PATHS FOR HEADLESS GODOT 3

# AgentBase.gd
# Generic base class for NPC agents with state management and deterministic replay support.

# --- ENUMS ---
enum State {
	IDLE,
	FOLLOW_PATH,
	FOLLOW_TARGET,
	RETURN_HOME,
	ALERT,
	SEARCH,
	MOVE_TO,
	PATROL # Added PATROL to AgentBase for FD-242
}

# --- EXPORTED CONFIGURATION ---
export(float) var max_speed := 15.0
export(float) var acceleration := 20.0
export(float) var braking_distance := 2.5

# --- SIGNALS ---
signal state_changed(new_state)
signal goal_reached
signal obstacle_detected(normal, distance)

# --- STATE VARIABLES (Snapshotted) ---
var current_state = State.IDLE setget set_state
var velocity := Vector3.ZERO
var target_position := Vector3.ZERO
var command_index := 0 # Current step in script/mission queue

# Internal state for path following
var _current_path_node: Path = null
var _path_offset := 0.0

# Follow Target state
var _follow_target: Node = null
var _follow_distance := 3.0

# Deterministic input buffer from agents
var _intended_velocity := Vector3.ZERO
var _has_intended_velocity := false
var _canonical_velocity := Vector3.ZERO # Velocity snapshot before move_and_slide()

var _perf_monitor = null

func _init():
	add_to_group("replay_sync")
	add_to_group("agent")

func _ready():
	# Register with Performance Monitor
	if Engine.has_singleton("PerformanceMonitor") or has_node("/root/PerformanceMonitor"):
		_perf_monitor = get_node("/root/PerformanceMonitor")
		if _perf_monitor and _perf_monitor.has_method("register_monitored_node"):
			_perf_monitor.register_monitored_node(self)

func set_state(new_state):
	if current_state == new_state:
		return
	current_state = new_state
	_on_state_changed(current_state)
	emit_signal("state_changed", current_state)

func _on_state_changed(_new_state):
	# Virtual method for subclasses
	pass

# --- CORE API ---

func move_to(position: Vector3) -> void:
	set_physics_process(true)
	target_position = position
	_has_intended_velocity = false
	self.current_state = State.MOVE_TO

func follow_path(path_nodepath: NodePath) -> void:
	var node = get_node_or_null(path_nodepath)
	if node and node is Path:
		set_physics_process(true)
		_current_path_node = node
		_path_offset = 0.0
		_has_intended_velocity = false
		self.current_state = State.FOLLOW_PATH
	else:
		printerr("[%s] Invalid path node: %s" % [name, path_nodepath])

func follow_target(target: Node, distance: float = 3.0) -> void:
	if not target or not is_instance_valid(target):
		printerr("[%s] follow_target: Invalid target" % name)
		return
	set_physics_process(true)
	_follow_target = target
	_follow_distance = distance
	_has_intended_velocity = false
	self.current_state = State.FOLLOW_TARGET

func stop() -> void:
	self.current_state = State.IDLE
	_has_intended_velocity = false
	velocity = Vector3.ZERO
	target_position = Vector3.ZERO
	_follow_target = null

func set_velocity(vector: Vector3) -> void:
	set_physics_process(true)
	_intended_velocity = vector
	_has_intended_velocity = true
	# Manual velocity override usually implies active control
	self.current_state = State.IDLE 

# --- PHYSICS / DETERMINISM ---

func _physics_process(delta: float) -> void:
	step(delta)

func step(dt: float) -> void:
	if _perf_monitor and _perf_monitor.has_method("measure_start"):
		_perf_monitor.measure_start(self, "step")

	var wish_velocity := Vector3.ZERO
	
	if _has_intended_velocity:
		wish_velocity = _intended_velocity
	else:
		wish_velocity = _calculate_wish_velocity(dt)

	# Acceleration / Deceleration
	var current_vel = velocity
	var lerp_weight = clamp(acceleration * dt * 0.1, 0.05, 1.0)
	current_vel = current_vel.linear_interpolate(wish_velocity, lerp_weight)
	
	velocity = current_vel

	if _perf_monitor and _perf_monitor.has_method("measure_end"):
		_perf_monitor.measure_end(self, "step")

	_canonical_velocity = velocity

	_apply_movement_and_rotation(dt)

	# PERF: Disable physics process when drone is idle
	if current_state == State.IDLE and not _has_intended_velocity and velocity.length_squared() < 0.001:
		velocity = Vector3.ZERO
		set_physics_process(false)

func _calculate_wish_velocity(dt: float) -> Vector3:
	match current_state:
		State.FOLLOW_TARGET:
			return _logic_follow_target(dt)
		State.FOLLOW_PATH:
			return _logic_follow_path(dt)
		State.RETURN_HOME:
			return _logic_move_to(target_position, dt)
		State.MOVE_TO:
			return _logic_move_to(target_position, dt)
		State.PATROL:
			return _logic_move_to(target_position, dt)
	return Vector3.ZERO

func _logic_follow_target(_dt: float) -> Vector3:
	if not _follow_target or not is_instance_valid(_follow_target):
		self.current_state = State.IDLE
		return Vector3.ZERO
		
	var target_pos = _follow_target.global_transform.origin
	var my_pos = global_transform.origin
	var to_target = target_pos - my_pos
	var dist = to_target.length()
	
	if dist > _follow_distance + 0.5:
		var desired_speed = max_speed
		if dist < braking_distance + _follow_distance:
			desired_speed = max_speed * ((dist - _follow_distance) / braking_distance)
		return to_target.normalized() * max(desired_speed, 0.5)
	elif dist < _follow_distance - 0.5:
		return - to_target.normalized() * max_speed * 0.3
	
	return Vector3.ZERO

func _logic_follow_path(dt: float) -> Vector3:
	if not _current_path_node:
		self.current_state = State.IDLE
		return Vector3.ZERO
		
	var curve = _current_path_node.curve
	var path_length = curve.get_baked_length()
	var look_ahead = 1.0
	var target_offset = _path_offset + look_ahead
	var arrived := false
	
	if target_offset > path_length:
		target_offset = path_length
		if _path_offset >= path_length - 0.1:
			arrived = true

	var target_pos_world = _current_path_node.to_global(curve.interpolate_baked(target_offset))
	var to_target = target_pos_world - global_transform.origin

	if to_target.length() > 0.1:
		_path_offset += velocity.length() * dt
		return to_target.normalized() * max_speed
	else:
		if arrived:
			self.current_state = State.IDLE
			emit_signal("goal_reached")
	return Vector3.ZERO

func _logic_move_to(pos: Vector3, _dt: float) -> Vector3:
	var to_target = pos - global_transform.origin
	var dist = to_target.length()

	if dist < 0.2:
		target_position = Vector3.ZERO
		self.current_state = State.IDLE
		emit_signal("goal_reached")
		return Vector3.ZERO
	else:
		var desired_speed = max_speed
		if dist < braking_distance:
			desired_speed = max_speed * (dist / braking_distance)
		return to_target.normalized() * desired_speed

func _apply_movement_and_rotation(_dt: float) -> void:
	if velocity.length() > 0.001:
		velocity = move_and_slide(velocity, Vector3.UP)

		for i in range(get_slide_count()):
			var collision = get_slide_collision(i)
			if collision.collider is StaticBody or collision.collider is CSGShape:
				emit_signal("obstacle_detected", collision.normal, global_transform.origin.distance_to(collision.position))

		var horiz_vel = Vector3(velocity.x, 0, velocity.z)
		if horiz_vel.length() > 0.1:
			var target_look = global_transform.origin + horiz_vel.normalized()
			if not target_look.is_equal_approx(global_transform.origin):
				look_at(target_look, Vector3.UP)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"tf_origin": var2str(global_transform.origin),
		"tf_basis": var2str(global_transform.basis),
		"velocity": var2str(velocity),
		"target_pos": var2str(target_position),
		"state": current_state,
		"cmd_idx": command_index,
		"has_intent": _has_intended_velocity,
		"intent_vel": var2str(_intended_velocity),
		"path_off": _path_offset,
		"follow_dist": _follow_distance
	}

func restore_snapshot(data: Dictionary) -> void:
	set_physics_process(true)

	if data.has("tf_origin"):
		var o = str2var(data["tf_origin"])
		var b = str2var(data["tf_basis"])
		global_transform = Transform(b, o)

	velocity = str2var(data.get("velocity", "Vector3(0,0,0)"))
	target_position = str2var(data.get("target_pos", "Vector3(0,0,0)"))
	current_state = int(data.get("state", State.IDLE))
	command_index = data.get("cmd_idx", 0)

	_has_intended_velocity = data.get("has_intent", false)
	_intended_velocity = str2var(data.get("intent_vel", "Vector3(0,0,0)"))

	_path_offset = data.get("path_off", 0.0)
	_follow_distance = data.get("follow_dist", 3.0)
