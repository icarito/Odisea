extends Node

class_name AnnaInterface

# Configuration
const PROTOCOL_VERSION = "anna.v1"
const SENSOR_RAY_COUNT = 32 # Legacy/Visual
const RL_SENSOR_RAY_COUNT = 8 # RL PoC
const SENSOR_RANGE = 20.0
const PROXIMITY_RADIUS = 10.0
const BUFFER_MAX_ENTRIES = 50
const MAX_LOOK_DELTA = 250.0
const MAX_ONCE_IDS = 256

# RL Config
const RL_TARGET_GROUP = "anna_target"
const RL_MAX_VELOCITY = 20.0
const RL_REWARD_SUCCESS = 100.0
const RL_REWARD_FAILURE = -100.0
const RL_REWARD_TIME_PENALTY = -0.1
const RL_PROGRESS_SCALE = 12.0
const RL_SUCCESS_DIST = 2.0
const RL_SPEED_REWARD_SCALE = 0.012 # Keep locomotion incentive without collapsing to always-forward.
const RL_SPRINT_REWARD_SCALE = 0.05 # Stronger bonus when explicit sprint action is used.
const RL_SPRINT_TARGET_SPEED = 7.0 # Target horizontal speed to make sprint behavior preferable.
const RL_SPEED_TARGET_REWARD_SCALE = 0.05 # Reward approaching sprint target speed.
const RL_SPRINT_ACTION_BONUS = 0.05 # Flat bonus for selecting sprint in favorable conditions.
const RL_NO_SPRINT_WHEN_ALIGNED_PENALTY = 0.03 # Discourage jogging when aligned and path is clear.
const RL_LOW_SPEED_WHEN_ALIGNED_PENALTY_SCALE = 0.01 # Penalize staying slow in sprint-friendly context.
const RL_JUMP_ACTION_PENALTY = 0.01 # Small baseline cost; keeps jump purposeful.
const RL_JUMP_REPEAT_PENALTY = 0.03 # Stronger penalty for repeated jump spam.
const RL_AIRBORNE_PENALTY = 0.0 # Do not punish being airborne; jumping is useful in obstacle courses.
const RL_HEIGHT_REWARD_SCALE = 0.04 # Reward gaining height to clear obstacles.
const RL_HEIGHT_REWARD_CAP = 2.5
const RL_OBSTACLE_AHEAD_DIST = 1.6
const RL_OBSTACLE_JUMP_BONUS = 0.22 # Strong bonus for jumping when obstacle is ahead.
const RL_BAD_JUMP_PENALTY = 0.12 # Penalize jumping when no nearby frontal obstacle.
const RL_OBSTACLE_NO_EVASION_PENALTY = 0.08 # Penalize pushing head-on into nearby obstacles without jump/strafe.
const RL_STRAFE_WHEN_MISALIGNED_REWARD_SCALE = 0.08 # Encourage strafe corrections when target is off-center.
const RL_STRAFE_OBSTACLE_REWARD_SCALE = 0.06 # Encourage strafe around nearby frontal obstacles.
const RL_STRAFE_IDLE_PENALTY = 0.015 # Discourage needless strafe when already aligned.
const RL_APPROACH_SPEED_REWARD_SCALE = 0.06 # Reward world velocity projected toward target direction.
const RL_TANGENTIAL_SPEED_PENALTY_SCALE = 0.09 # Penalize circling/orbiting around target.
const RL_NEAR_TARGET_ORBIT_PENALTY_SCALE = 0.20 # Stronger tangential penalty when already close.
const RL_NEAR_TARGET_RADIUS = 5.0
const RL_ALIGNMENT_REWARD_SCALE = 0.04 # Shaping reward for facing target.
const RL_PROXIMITY_REWARD_SCALE = 0.02 # Smooth bonus for getting closer even before success radius.
const RL_PROXIMITY_REFERENCE_DIST = 20.0
const RL_ANGLE_PROGRESS_SCALE = 1.8 # Reward reducing absolute angle-to-target.
const RL_LOOK_USAGE_REWARD_SCALE = 0.01 # Encourage camera movement when misaligned.
const RL_ANGLE_ABS_PENALTY_SCALE = 0.10 # Penalize staying off-target.
const RL_AIM_STABILITY_BONUS_SCALE = 0.06 # Bonus when consistently aimed at target.
const RL_FORWARD_MISALIGN_PENALTY_SCALE = 0.16 # Penalize fast movement while not aiming at target.
const RL_ALIGNED_SPEED_REWARD_SCALE = 0.05 # Reward forward speed only when aligned.
const RL_UNALIGNED_SPEED_PENALTY_SCALE = 0.08 # Penalize rushing with poor aim.
const RL_NO_CORRECTION_PENALTY = 0.06 # Penalize not using look while drifting off-target.
const RL_STEER_WHEN_MISALIGNED_REWARD_SCALE = 0.04 # Small reward for actively steering when off-target.
const RL_STEER_CORRECTION_BONUS_SCALE = 1.2 # Extra bonus when steering reduces angle-to-target.
const RL_ACTION_SWITCH_PENALTY_SCALE = 0.01 # Penalize abrupt action category changes, but allow course correction.
const RL_MOVE_DELTA_PENALTY_SCALE = 0.025 # Penalize sudden move vector changes.
const RL_LOOK_DELTA_PENALTY_SCALE = 0.02 # Penalize sudden camera delta changes.
const RL_VELOCITY_JERK_PENALTY_SCALE = 0.05 # Penalize abrupt horizontal speed direction/amount changes.
const RL_LOOK_FLIP_PENALTY = 0.22 # Penalize fast left-right camera flip-flop.
const RL_MOVE_FLIP_PENALTY = 0.07 # Penalize abrupt forward/back direction reversals.
const RL_COMMIT_FORWARD_REWARD_SCALE = 0.06 # Reward sustained aligned forward progress.
const RL_STALL_PENALTY = 0.03 # Penalize stalling when far from target.
const RL_LOOK_WHEN_ALIGNED_PENALTY = 0.08 # Penalize unnecessary camera movement when already aimed.
const RL_SAME_ACTION_STREAK_PENALTY = 0.02 # Penalize repeating same action while not improving.
const RL_BAD_STREAK_DIST_EPS = 0.01
const RL_BAD_STREAK_ANGLE_EPS = 0.005
const RL_LOOK_DELTA_X = 10.0
const RL_LOOK_DELTA_Y = 2.0
const RL_LOOK_ALIGN_DEADZONE = 0.03 # Keep correcting, but don't jitter around perfect alignment.
const RL_LOOK_MIN_CORRECTION = 4.0 # Strong minimum yaw correction when clearly misaligned.
const RL_MOVE_ALIGN_GATE = 0.10 # Begin throttling forward when heading is clearly wrong.
const RL_MOVE_MIN_THROTTLE = 0.18 # Keep some forward motion while correcting to avoid freezing episodes.
const RL_COLLISION_PENALTY_THRESHOLD = 0.6 # If ray < 0.6m ~ collision
const RL_FLOOR_NORMAL_Y_THRESHOLD = 0.6 # Upward-facing collisions are treated as floor/support.
const RL_HAZARD_CONTACT_GRACE_FRAMES = 35 # Tolerate brief wall brushes in dense geometry.
const RL_WALL_CONTACT_PENALTY = 0.03 # Stronger shaping penalty for sustained wall contact.
const RL_STUCK_WALL_FAIL_FRAMES = 150 # Fail if clearly stuck against walls for too long.
const RL_STUCK_MIN_HSPEED = 0.12
const RL_STUCK_MIN_PROGRESS_SPEED = 0.05
const RL_STUCK_EXTRA_PENALTY_SCALE = 0.01 # Progressive punishment while stuck.
const RL_STUCK_EXTRA_PENALTY_CAP = 0.35
const RL_STUCK_RECOVERY_WALL_FRAMES = 18 # After this, force jump/backoff/strafe recovery.
const RL_STUCK_NO_RECOVERY_PENALTY = 0.08
const RL_STUCK_RECOVERY_REWARD = 0.05
const RL_STUCK_RECOVERY_BACKOFF = 0.85
const RL_STUCK_RECOVERY_STRAFE = 0.70
const RL_STUCK_RECOVERY_JUMP_PERIOD = 10
const RL_SMART_JUMP_AHEAD_DIST = 1.85 # Jump is only useful when obstacle is close ahead.
const RL_SMART_JUMP_MIN_COOLDOWN = 8 # Avoid hop-spam between consecutive frames.
const RL_SMART_JUMP_ALLOW_STUCK_FRAMES = 12 # If stuck, allow more aggressive jump recovery.
const RL_INTERACT_RANGE = 3.25
const RL_INTERACT_FORWARD_DOT_MIN = 0.15
const RL_INTERACT_CONTEXT_REWARD = 0.18
const RL_INTERACT_SPAM_PENALTY = 0.04
const RL_INTERACT_REPEAT_PENALTY = 0.05
const RL_INTERACT_COOLDOWN_FRAMES = 8
const RL_FALL_DISTANCE = 3.5 # Episode fails if player falls this much below episode start height.

export(bool) var allow_human_heuristic_override := true
export(NodePath) var ai_controller_path := NodePath("")
export(bool) var allow_command_injection := true
export(bool) var allow_oys_integration := true
export(bool) var allow_olcs_integration := true
export(NodePath) var olcs_manager_path := NodePath("")
export(int) var olcs_snapshot_limit := 32

# State
var _raycast_root: Spatial
var _rl_raycast_root: Spatial
var _rays := []
var _rl_rays := []
var _accepted_once_ids := {}

# RL State
var _last_dist_to_target := -1.0
var _episode_start_time := 0
var _episode_start_height := 2.0
var _hazard_contact_frames := 0
var _killzone_triggered := false
var _last_action_jump := false
var _last_action_sprint := false
var _last_action_look_x := 0.0
var _last_action_look_y := 0.0
var _last_action_interact := false
var _last_abs_angle_to_target := -1.0
var _last_move_cmd := Vector2.ZERO
var _last_look_cmd := Vector2.ZERO
var _last_action_idx := -1
var _last_action_change_cost := 0.0
var _last_local_hvel := Vector2.ZERO
var _has_last_local_hvel := false
var _jump_streak := 0
var _interact_streak := 0
var _misaligned_run_streak := 0
var _same_action_streak := 0
var _last_angle_to_target := 0.0
var _has_last_angle_to_target := false
var _wall_stuck_frames := 0
var _jump_cooldown_frames := 0
var _interact_cooldown_frames := 0

func _ready():
	_setup_sensors()
	_setup_rl_sensors()
	_bind_killzones()
	var tree = get_tree()
	if tree and not tree.is_connected("node_added", self, "_on_tree_node_added"):
		tree.connect("node_added", self, "_on_tree_node_added")

func _exit_tree():
	var tree = get_tree()
	if tree and tree.is_connected("node_added", self, "_on_tree_node_added"):
		tree.disconnect("node_added", self, "_on_tree_node_added")

func _on_tree_node_added(node: Node) -> void:
	_try_bind_killzone(node)

func _bind_killzones() -> void:
	if not is_inside_tree():
		return
	var zones = get_tree().get_nodes_in_group("KillZoneV2")
	for zone in zones:
		_try_bind_killzone(zone)

func _try_bind_killzone(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not node.is_in_group("KillZoneV2"):
		return
	if not node.has_signal("player_killed"):
		return
	if not node.is_connected("player_killed", self, "_on_killzone_player_killed"):
		node.connect("player_killed", self, "_on_killzone_player_killed")

func _on_killzone_player_killed() -> void:
	_killzone_triggered = true

func _setup_sensors():
	if is_instance_valid(_raycast_root):
		return

	_raycast_root = Spatial.new()
	_raycast_root.name = "AnnaSensors"
	add_child(_raycast_root)

	for i in range(SENSOR_RAY_COUNT):
		var ray = RayCast.new()
		ray.enabled = true
		ray.cast_to = Vector3(0, 0, -SENSOR_RANGE)
		ray.rotation_degrees.y = (360.0 / SENSOR_RAY_COUNT) * i
		_raycast_root.add_child(ray)
		_rays.append(ray)

func _setup_rl_sensors():
	if is_instance_valid(_rl_raycast_root):
		return

	_rl_raycast_root = Spatial.new()
	_rl_raycast_root.name = "AnnaRLSensors"
	add_child(_rl_raycast_root)

	for i in range(RL_SENSOR_RAY_COUNT):
		var ray = RayCast.new()
		ray.enabled = true
		ray.cast_to = Vector3(0, 0, -SENSOR_RANGE)
		# 8 rays distributed around 360 degrees
		ray.rotation_degrees.y = (360.0 / float(RL_SENSOR_RAY_COUNT)) * i
		_rl_raycast_root.add_child(ray)
		_rl_rays.append(ray)

# --- STANDARD API ---

func get_observation() -> Dictionary:
	return {
		"proximity": _get_proximity(),
		"buffer": _get_buffer(),
		"metrics": _get_metrics(),
		"collisions": _get_collisions(),
		"olcs": _get_olcs_observation(),
		"anna": _get_anna_metadata()
	}

# --- RL API ---

func get_rl_observation() -> Dictionary:
	var player = _get_player()
	var obs_vector = []
	var reward = 0.0
	var done = false
	var dist_to_target = 0.0
	var angle_to_target = 0.0
	var to_target = Vector3.ZERO
	var forward = Vector3.ZERO
	var facing_basis = Basis.IDENTITY

	if not is_instance_valid(player) or not player is Spatial:
		# Fallback/Fail state
		for i in range(12): obs_vector.append(0.0)
		return {"obs": obs_vector, "reward": 0.0, "done": true}

	# 1. Update Sensors
	# Move sensors to player position
	_rl_raycast_root.global_transform.origin = player.global_transform.origin + Vector3(0, 1.0, 0)
	# Align sensors with player rotation (so Ray 0 is always "Forward")
	_rl_raycast_root.global_transform.basis = player.global_transform.basis

	# Rays 0-7
	var min_ray_dist = SENSOR_RANGE
	var front_ray_dist = SENSOR_RANGE
	for i in range(_rl_rays.size()):
		var ray = _rl_rays[i]
		ray.clear_exceptions()
		ray.add_exception(player)
		ray.force_raycast_update()
		var d = SENSOR_RANGE
		if ray.is_colliding():
			d = ray.global_transform.origin.distance_to(ray.get_collision_point())

		if d < min_ray_dist: min_ray_dist = d
		if i == 0 or i == 1 or i == (_rl_rays.size() - 1):
			if d < front_ray_dist:
				front_ray_dist = d

		# Normalize: 0.0 (Collision) to 1.0 (Clear)
		obs_vector.append(clamp(d / SENSOR_RANGE, 0.0, 1.0))

	# Target Info
	var target = _ensure_rl_target()
	if target:
		dist_to_target = player.global_transform.origin.distance_to(target.global_transform.origin)

		# Angle
		to_target = (target.global_transform.origin - player.global_transform.origin)
		to_target.y = 0
		to_target = to_target.normalized()
		facing_basis = _get_control_basis(player as Spatial)
		forward = -facing_basis.z
		forward.y = 0
		forward = forward.normalized()

		var angle = forward.angle_to(to_target) # Returns 0 to PI
		# Determine sign
		if forward.cross(to_target).y < 0:
			angle = -angle

		angle_to_target = angle / PI # Normalize -1 to 1
	else:
		dist_to_target = SENSOR_RANGE

	# Sensor 8: Distancia normalizada
	obs_vector.append(clamp(dist_to_target / 50.0, 0.0, 1.0))

	# Sensor 9: Angulo relativo
	obs_vector.append(angle_to_target)

	# Sensor 10, 11: Velocity (normalized)
	var vel = Vector3.ZERO
	if "velocity" in player:
		vel = player.velocity

	# Normalize relative to player orientation?
	var local_vel = player.global_transform.basis.xform_inv(vel)
	obs_vector.append(clamp(local_vel.x / RL_MAX_VELOCITY, -1.0, 1.0)) # Right/Left
	obs_vector.append(clamp(local_vel.z / RL_MAX_VELOCITY, -1.0, 1.0)) # Backward/Forward (-Z is forward)
	var on_floor_now = true
	if player.has_method("is_on_floor"):
		on_floor_now = player.is_on_floor()

	# --- REWARD CALCULATION ---

	# 1. Time Penalty
	reward += RL_REWARD_TIME_PENALTY

	# 1b. Reward speed (prefer fast locomotion over stationary/jump spam)
	var horizontal_speed = Vector2(local_vel.x, local_vel.z).length()
	var strafe_speed = abs(local_vel.x)
	reward += horizontal_speed * RL_SPEED_REWARD_SCALE
	reward += min(horizontal_speed / RL_SPRINT_TARGET_SPEED, 1.0) * RL_SPEED_TARGET_REWARD_SCALE
	if _last_action_sprint and horizontal_speed > 0.1:
		reward += horizontal_speed * RL_SPRINT_REWARD_SCALE
	if _last_action_jump:
		reward -= RL_JUMP_ACTION_PENALTY
		if _jump_streak > 1:
			reward -= float(_jump_streak - 1) * RL_JUMP_REPEAT_PENALTY
		if not on_floor_now:
			reward -= RL_JUMP_REPEAT_PENALTY
		if front_ray_dist < RL_OBSTACLE_AHEAD_DIST and vel.y > 0.05:
			reward += RL_OBSTACLE_JUMP_BONUS
		else:
			reward -= RL_BAD_JUMP_PENALTY
	elif on_floor_now and front_ray_dist < RL_OBSTACLE_AHEAD_DIST and abs(_last_move_cmd.x) < 0.1:
		reward -= RL_OBSTACLE_NO_EVASION_PENALTY
	if _last_action_interact:
		var interact_candidate = _get_front_interactable(player as Spatial)
		if is_instance_valid(interact_candidate):
			reward += RL_INTERACT_CONTEXT_REWARD
			if _interact_streak > 1:
				reward -= float(_interact_streak - 1) * RL_INTERACT_REPEAT_PENALTY
		else:
			reward -= RL_INTERACT_SPAM_PENALTY
	if not on_floor_now:
		reward -= RL_AIRBORNE_PENALTY
	var height_gain = max(0.0, player.global_transform.origin.y - _episode_start_height)
	reward += min(height_gain, RL_HEIGHT_REWARD_CAP) * RL_HEIGHT_REWARD_SCALE
	reward -= _last_action_change_cost
	var local_hvel = Vector2(local_vel.x, local_vel.z)
	if _has_last_local_hvel:
		reward -= (local_hvel - _last_local_hvel).length() * RL_VELOCITY_JERK_PENALTY_SCALE
	_last_local_hvel = local_hvel
	_has_last_local_hvel = true

	# 2. Progress
	if _last_dist_to_target >= 0.0:
		var diff = _last_dist_to_target - dist_to_target
		reward += diff * RL_PROGRESS_SCALE
	_last_dist_to_target = dist_to_target

	# 2b. Target shaping (alignment + approach speed + proximity)
	if target:
		if forward.length_squared() > 0.001 and to_target.length_squared() > 0.001:
			var align = clamp(forward.dot(to_target), -1.0, 1.0)
			reward += align * RL_ALIGNMENT_REWARD_SCALE

			var approach_speed = vel.dot(to_target)
			reward += approach_speed * RL_APPROACH_SPEED_REWARD_SCALE
			var tangential_speed = (vel - to_target * approach_speed).length()
			reward -= tangential_speed * RL_TANGENTIAL_SPEED_PENALTY_SCALE
			if dist_to_target < RL_NEAR_TARGET_RADIUS:
				var near_ratio = 1.0 - clamp(dist_to_target / RL_NEAR_TARGET_RADIUS, 0.0, 1.0)
				reward -= tangential_speed * near_ratio * RL_NEAR_TARGET_ORBIT_PENALTY_SCALE

		var proximity_ratio = clamp((RL_PROXIMITY_REFERENCE_DIST - dist_to_target) / RL_PROXIMITY_REFERENCE_DIST, 0.0, 1.0)
		reward += proximity_ratio * RL_PROXIMITY_REWARD_SCALE

		var abs_angle = abs(angle_to_target)
		reward -= abs_angle * RL_ANGLE_ABS_PENALTY_SCALE
		var alignment_focus = 1.0 - abs_angle
		reward += alignment_focus * alignment_focus * RL_AIM_STABILITY_BONUS_SCALE
		if _last_abs_angle_to_target >= 0.0:
			reward += (_last_abs_angle_to_target - abs_angle) * RL_ANGLE_PROGRESS_SCALE
			if abs(_last_action_look_x) > 0.05 and abs_angle < _last_abs_angle_to_target:
				reward += (_last_abs_angle_to_target - abs_angle) * RL_STEER_CORRECTION_BONUS_SCALE
		_last_abs_angle_to_target = abs_angle

		if abs_angle > 0.12 and abs(_last_action_look_x) > 0.01:
			reward += RL_LOOK_USAGE_REWARD_SCALE
		if abs_angle > 0.16 and abs(_last_action_look_x) > 0.05:
			reward += abs_angle * RL_STEER_WHEN_MISALIGNED_REWARD_SCALE
		if abs_angle < 0.08 and abs(_last_action_look_x) > 0.01:
			reward -= RL_LOOK_WHEN_ALIGNED_PENALTY
			if abs(_last_move_cmd.x) > 0.1 and abs_angle > 0.16:
				reward += strafe_speed * RL_STRAFE_WHEN_MISALIGNED_REWARD_SCALE
			if abs(_last_move_cmd.x) > 0.1 and front_ray_dist < RL_OBSTACLE_AHEAD_DIST:
				reward += strafe_speed * RL_STRAFE_OBSTACLE_REWARD_SCALE
			if abs(_last_move_cmd.x) > 0.1 and abs_angle < 0.08 and front_ray_dist > (RL_OBSTACLE_AHEAD_DIST * 1.2):
				reward -= RL_STRAFE_IDLE_PENALTY
			if horizontal_speed > 0.2 and abs_angle > 0.2:
				reward -= horizontal_speed * abs_angle * RL_FORWARD_MISALIGN_PENALTY_SCALE
			var forward_speed = max(0.0, vel.dot(to_target))
			var sprint_context = on_floor_now and abs_angle < 0.16 and front_ray_dist > (RL_OBSTACLE_AHEAD_DIST * 1.2) and dist_to_target > (RL_SUCCESS_DIST * 1.5)
			if sprint_context:
				if _last_action_sprint and forward_speed > 0.8:
					reward += RL_SPRINT_ACTION_BONUS
				elif forward_speed > 0.8:
					reward -= RL_NO_SPRINT_WHEN_ALIGNED_PENALTY
				var speed_gap = max(0.0, RL_SPRINT_TARGET_SPEED - forward_speed)
				reward -= speed_gap * RL_LOW_SPEED_WHEN_ALIGNED_PENALTY_SCALE
			if abs_angle < 0.2:
				reward += forward_speed * RL_ALIGNED_SPEED_REWARD_SCALE
				_misaligned_run_streak = 0
			elif forward_speed > 0.2:
				reward -= forward_speed * abs_angle * RL_UNALIGNED_SPEED_PENALTY_SCALE
				if abs(_last_action_look_x) < 0.01:
					_misaligned_run_streak += 1
					reward -= float(_misaligned_run_streak) * RL_NO_CORRECTION_PENALTY
				else:
					_misaligned_run_streak = 0
			else:
				_misaligned_run_streak = 0
			if on_floor_now and abs_angle < 0.2:
				var aligned_forward_speed = forward_speed
				reward += aligned_forward_speed * RL_COMMIT_FORWARD_REWARD_SCALE
			if dist_to_target > 4.0 and horizontal_speed < 0.2:
				reward -= RL_STALL_PENALTY
			if _last_dist_to_target >= 0.0 and (dist_to_target - _last_dist_to_target) > 0.02 and forward_speed > 0.15:
				reward -= 0.08 # Moving in a way that increases distance should be corrected quickly.

			# Anti-collapse: repeating same action while neither distance nor angle improves.
			if _same_action_streak > 6 and _last_dist_to_target >= 0.0 and _has_last_angle_to_target:
				var dist_improved = (_last_dist_to_target - dist_to_target) > RL_BAD_STREAK_DIST_EPS
				var angle_improved = (abs(_last_angle_to_target) - abs_angle) > RL_BAD_STREAK_ANGLE_EPS
				if not dist_improved and not angle_improved:
					reward -= float(_same_action_streak - 6) * RL_SAME_ACTION_STREAK_PENALTY
			_last_angle_to_target = angle_to_target
			_has_last_angle_to_target = true

	# 3. Success
	var reached_target := false
	if target:
		if dist_to_target < RL_SUCCESS_DIST:
			reached_target = true
		elif target is Area and target.overlaps_body(player):
			reached_target = true
	if reached_target:
		reward += RL_REWARD_SUCCESS
		done = true

	# 4. Failure (KillZone / Fall / Prolonged hazard contact)
	if not done and _killzone_triggered:
		reward += RL_REWARD_FAILURE
		done = true

	if not done and player.global_transform.origin.y < (_episode_start_height - RL_FALL_DISTANCE):
		reward += RL_REWARD_FAILURE
		done = true

	if not done:
		var hazard_contact := false
		if min_ray_dist < RL_COLLISION_PENALTY_THRESHOLD:
			hazard_contact = true

		if player.has_method("get_slide_count"):
			for i in range(player.get_slide_count()):
				var col = player.get_slide_collision(i)
				if col == null or not is_instance_valid(col.collider):
					continue
				if col.collider.is_in_group("anna_target"):
					continue
				if col.collider is StaticBody:
					# Ground contact is expected and should not end the episode.
					if col.normal.y >= RL_FLOOR_NORMAL_Y_THRESHOLD:
						continue
					# Ceiling contact should not end the episode either.
					if col.normal.y <= -RL_FLOOR_NORMAL_Y_THRESHOLD:
						continue
					hazard_contact = true
					break

		if hazard_contact:
			_hazard_contact_frames += 1
			reward -= RL_WALL_CONTACT_PENALTY
			if abs(_last_move_cmd.x) < 0.1 and not _last_action_jump:
				reward -= RL_OBSTACLE_NO_EVASION_PENALTY
		else:
			_hazard_contact_frames = 0
			_wall_stuck_frames = 0

		if hazard_contact and _hazard_contact_frames >= RL_HAZARD_CONTACT_GRACE_FRAMES:
			var progress_speed = 0.0
			if target and to_target.length_squared() > 0.001:
				progress_speed = vel.dot(to_target)
			if horizontal_speed < RL_STUCK_MIN_HSPEED and abs(progress_speed) < RL_STUCK_MIN_PROGRESS_SPEED:
				_wall_stuck_frames += 1
			else:
				_wall_stuck_frames = 0

		if _wall_stuck_frames > 0:
			reward -= min(RL_STUCK_EXTRA_PENALTY_CAP, float(_wall_stuck_frames) * RL_STUCK_EXTRA_PENALTY_SCALE)
			if _wall_stuck_frames >= RL_STUCK_RECOVERY_WALL_FRAMES:
				var trying_recovery := _last_move_cmd.y > 0.2 or abs(_last_move_cmd.x) > 0.2 or _last_action_jump
				if trying_recovery:
					reward += RL_STUCK_RECOVERY_REWARD
				else:
					reward -= RL_STUCK_NO_RECOVERY_PENALTY

		if _wall_stuck_frames >= RL_STUCK_WALL_FAIL_FRAMES:
			reward += RL_REWARD_FAILURE
			done = true

	return {
		"obs": obs_vector,
		"reward": reward,
		"done": done
	}

func reset_simulation() -> void:
	var player = _get_player()
	if player and player.has_method("teleport_to"):
		var t = Transform()
		t.origin = Vector3(0, 2, 0) # Start pos
		# Random rotation?
		var rand_yaw = rand_range(-PI, PI)
		t.basis = Basis(Vector3.UP, rand_yaw)
		player.teleport_to(t)
		_episode_start_height = t.origin.y

	# Reset Target
	var target = _ensure_rl_target()
	if target:
		var tx = rand_range(-20, 20)
		var tz = rand_range(-20, 20)
		while Vector2(tx, tz).length() < 5.0:
			tx = rand_range(-20, 20)
			tz = rand_range(-20, 20)
		target.transform.origin = Vector3(tx, 1.0, tz)

	# Reset internal state
	_last_dist_to_target = -1.0
	_hazard_contact_frames = 0
	_killzone_triggered = false
	_last_action_jump = false
	_last_action_sprint = false
	_last_action_interact = false
	_last_action_look_x = 0.0
	_last_action_look_y = 0.0
	_last_abs_angle_to_target = -1.0
	_last_move_cmd = Vector2.ZERO
	_last_look_cmd = Vector2.ZERO
	_last_action_idx = -1
	_last_action_change_cost = 0.0
	_last_local_hvel = Vector2.ZERO
	_has_last_local_hvel = false
	_jump_streak = 0
	_interact_streak = 0
	_misaligned_run_streak = 0
	_same_action_streak = 0
	_last_angle_to_target = 0.0
	_has_last_angle_to_target = false
	_wall_stuck_frames = 0
	_jump_cooldown_frames = 0
	_interact_cooldown_frames = 0
	# Force initial distance update
	if target and player:
		_last_dist_to_target = player.global_transform.origin.distance_to(target.global_transform.origin)
		var to_target = target.global_transform.origin - player.global_transform.origin
		to_target.y = 0.0
		if to_target.length_squared() > 0.001:
			to_target = to_target.normalized()
			var fwd_basis = _get_control_basis(player as Spatial)
			var fwd = -fwd_basis.z
			fwd.y = 0.0
			if fwd.length_squared() > 0.001:
				fwd = fwd.normalized()
				_last_abs_angle_to_target = abs(fwd.angle_to(to_target) / PI)

func apply_rl_action(action_idx: int) -> void:
	# Action Space:
	# 0=SteerOnly (+ contextual INTERACT when facing an interactable),
	# 1=Forward,
	# 2=SprintForward,
	# 3=JumpForward,
	# 4=StrafeLeft,
	# 5=StrafeRight,
	# 6=JumpStrafeLeft,
	# 7=JumpStrafeRight
	var move_vec = Vector2.ZERO
	var jump_pressed := false
	var sprint_pressed := false
	var interact_pressed := false
	var look_vec = Vector2.ZERO
	if _jump_cooldown_frames > 0:
		_jump_cooldown_frames -= 1
	if _interact_cooldown_frames > 0:
		_interact_cooldown_frames -= 1

	match action_idx:
		0:
			pass # steer-only
		1:
			move_vec.y = -1.0
		2:
			move_vec.y = -1.0
			sprint_pressed = true
		3:
			move_vec.y = -1.0
			jump_pressed = true
		4:
			move_vec.x = -1.0
		5:
			move_vec.x = 1.0
		6:
			move_vec.x = -1.0
			jump_pressed = true
		7:
			move_vec.x = 1.0
			jump_pressed = true

	# Assisted steering: force look direction toward current target bearing.
	var player = _get_player()
	var target = _ensure_rl_target()
	var steer_angle = 0.0
	var has_steer = false
	if is_instance_valid(player) and is_instance_valid(target):
		steer_angle = _get_target_angle_normalized(player as Spatial, target)
		has_steer = true

	if has_steer:
		if abs(steer_angle) < RL_LOOK_ALIGN_DEADZONE:
			look_vec.x = 0.0
		else:
			# Proportional steering toward target bearing using CameraRig orientation.
			# Positive steer_angle should rotate camera toward target.
			# PlayerControllerV2 applies yaw -= mouse_delta.x * sensitivity, so this sign is inverted.
			look_vec.x = -clamp(steer_angle * RL_LOOK_DELTA_X, -RL_LOOK_DELTA_X, RL_LOOK_DELTA_X)
			if abs(steer_angle) > 0.12 and abs(look_vec.x) < RL_LOOK_MIN_CORRECTION:
				look_vec.x = -sign(steer_angle) * RL_LOOK_MIN_CORRECTION
	else:
		look_vec.x = 0.0

	# Anti-collapse runtime gate:
	# when target bearing is off, throttle forward so controller re-aims without freezing.
	if has_steer and abs(steer_angle) > RL_MOVE_ALIGN_GATE:
		var misalign = clamp((abs(steer_angle) - RL_MOVE_ALIGN_GATE) / max(0.001, 1.0 - RL_MOVE_ALIGN_GATE), 0.0, 1.0)
		var throttle = lerp(1.0, RL_MOVE_MIN_THROTTLE, misalign)
		move_vec.y *= throttle
		if throttle < 0.55:
			sprint_pressed = false

	# Forced stuck recovery: if we are clearly wedged on walls, override action to escape.
	var forced_recovery := false
	if _wall_stuck_frames >= RL_STUCK_RECOVERY_WALL_FRAMES:
		forced_recovery = true
		var strafe_sign = 1.0 if int(_wall_stuck_frames / RL_STUCK_RECOVERY_WALL_FRAMES) % 2 == 0 else -1.0
		if has_steer and abs(steer_angle) > 0.20:
			strafe_sign = sign(steer_angle)
			if abs(strafe_sign) < 0.001:
				strafe_sign = 1.0
		move_vec.x = strafe_sign * RL_STUCK_RECOVERY_STRAFE
		move_vec.y = RL_STUCK_RECOVERY_BACKOFF
		sprint_pressed = false
		if int(_wall_stuck_frames) % RL_STUCK_RECOVERY_JUMP_PERIOD == 0:
			jump_pressed = true

	# Smart jump gating: only jump when obstacle/stuck context justifies it.
	if jump_pressed and not forced_recovery:
		var on_floor_now = true
		if player and player.has_method("is_on_floor"):
			on_floor_now = player.is_on_floor()
		var player_spatial: Spatial = player as Spatial if player is Spatial else null
		var front_obstacle_dist = _get_front_obstacle_distance(player_spatial)
		var obstacle_ahead = front_obstacle_dist < RL_SMART_JUMP_AHEAD_DIST
		var stuck_context = _wall_stuck_frames >= RL_SMART_JUMP_ALLOW_STUCK_FRAMES
		var blocked_jump = (not on_floor_now) or (_jump_cooldown_frames > 0) or (not obstacle_ahead and not stuck_context)
		if blocked_jump:
			jump_pressed = false
	if jump_pressed:
		_jump_cooldown_frames = RL_SMART_JUMP_MIN_COOLDOWN

	# Contextual interact:
	# Reuse "steer-only" action as an explicit interaction intent when near an interactable.
	# This preserves the 8-action API while enabling door usage in BaseTerrace.
	var interact_candidate = _get_front_interactable(player as Spatial if player is Spatial else null)
	if action_idx == 0 and is_instance_valid(interact_candidate):
		interact_pressed = true
	if interact_pressed and _interact_cooldown_frames > 0:
		interact_pressed = false
	if interact_pressed:
		_interact_cooldown_frames = RL_INTERACT_COOLDOWN_FRAMES

	_last_action_jump = jump_pressed
	_last_action_sprint = sprint_pressed
	_last_action_interact = interact_pressed
	_last_action_look_x = look_vec.x
	_last_action_look_y = look_vec.y
	if jump_pressed:
		_jump_streak += 1
	else:
		_jump_streak = 0
	if interact_pressed:
		_interact_streak += 1
	else:
		_interact_streak = 0

	var action_change_cost := 0.0
	if _last_action_idx >= 0:
		if _last_action_idx == action_idx:
			_same_action_streak += 1
		else:
			_same_action_streak = 0
		if _last_action_idx != action_idx:
			action_change_cost += RL_ACTION_SWITCH_PENALTY_SCALE
		action_change_cost += (_last_move_cmd - move_vec).length() * RL_MOVE_DELTA_PENALTY_SCALE
		var look_norm = Vector2(look_vec.x / max(1.0, RL_LOOK_DELTA_X), look_vec.y / max(1.0, RL_LOOK_DELTA_Y))
		var prev_look_norm = Vector2(_last_look_cmd.x / max(1.0, RL_LOOK_DELTA_X), _last_look_cmd.y / max(1.0, RL_LOOK_DELTA_Y))
		action_change_cost += (prev_look_norm - look_norm).length() * RL_LOOK_DELTA_PENALTY_SCALE
		if abs(_last_look_cmd.x) > 0.01 and abs(look_vec.x) > 0.01 and sign(_last_look_cmd.x) != sign(look_vec.x):
			action_change_cost += RL_LOOK_FLIP_PENALTY
		if abs(_last_move_cmd.y) > 0.01 and abs(move_vec.y) > 0.01 and sign(_last_move_cmd.y) != sign(move_vec.y):
			action_change_cost += RL_MOVE_FLIP_PENALTY
	else:
		_same_action_streak = 0
	_last_action_change_cost = action_change_cost
	_last_move_cmd = move_vec
	_last_look_cmd = look_vec
	_last_action_idx = action_idx

	var input_dict = {
		"move_vec": move_vec,
		"jump": jump_pressed,
		"interact": interact_pressed,
		"sprint": sprint_pressed,
		"crouch": false,
		"mouse_delta": look_vec,
		"zoom_delta": 0.0,
		"fov_override": -1.0
	}

	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.is_recording:
		sm._oys_input_override = input_dict
	else:
		if player and player.has_method("inject_input"):
			player.inject_input(input_dict)

func _get_front_obstacle_distance(player: Spatial) -> float:
	if not is_instance_valid(player):
		return SENSOR_RANGE
	if not is_instance_valid(_rl_raycast_root):
		_setup_rl_sensors()
	if not is_instance_valid(_rl_raycast_root) or _rl_rays.size() == 0:
		return SENSOR_RANGE

	_rl_raycast_root.global_transform.origin = player.global_transform.origin + Vector3(0, 1.0, 0)
	_rl_raycast_root.global_transform.basis = _get_control_basis(player)

	var front_dist = SENSOR_RANGE
	for i in range(_rl_rays.size()):
		if i != 0 and i != 1 and i != (_rl_rays.size() - 1):
			continue
		var ray = _rl_rays[i]
		ray.clear_exceptions()
		ray.add_exception(player)
		ray.force_raycast_update()
		var d = SENSOR_RANGE
		if ray.is_colliding():
			d = ray.global_transform.origin.distance_to(ray.get_collision_point())
		if d < front_dist:
			front_dist = d
	return front_dist

func _get_front_interactable(player: Spatial) -> Node:
	if not is_instance_valid(player):
		return null
	if not is_inside_tree():
		return null

	var basis = _get_control_basis(player)
	var forward = -basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return null
	forward = forward.normalized()

	var best: Node = null
	var best_dist := RL_INTERACT_RANGE + 0.001
	var candidates = get_tree().get_nodes_in_group("interactable")
	for node in candidates:
		if not is_instance_valid(node):
			continue
		if not node is Spatial:
			continue
		if "is_interactable" in node and not bool(node.is_interactable):
			continue

		var to_node = (node.global_transform.origin - player.global_transform.origin)
		to_node.y = 0.0
		var dist = to_node.length()
		if dist <= 0.001 or dist > RL_INTERACT_RANGE:
			continue
		var dir = to_node / dist
		if forward.dot(dir) < RL_INTERACT_FORWARD_DOT_MIN:
			continue
		if dist < best_dist:
			best = node
			best_dist = dist
	return best

func _get_target_angle_normalized(player: Spatial, target: Spatial) -> float:
	if not is_instance_valid(player) or not is_instance_valid(target):
		return 0.0
	var to_target = (target.global_transform.origin - player.global_transform.origin)
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	to_target = to_target.normalized()
	var facing_basis = player.global_transform.basis
	facing_basis = _get_control_basis(player)
	var forward = -facing_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0.0
	forward = forward.normalized()
	var angle = forward.angle_to(to_target)
	if forward.cross(to_target).y < 0:
		angle = -angle
	return angle / PI

func _get_control_basis(player: Spatial) -> Basis:
	var cm = get_node_or_null("/root/CinematicManager")
	if cm and cm.has_method("get_movement_basis"):
		return cm.get_movement_basis(1.0)
	if is_instance_valid(player) and player.has_method("get_camera_basis"):
		return player.get_camera_basis()
	return player.global_transform.basis if is_instance_valid(player) else Basis.IDENTITY


func _get_rl_target() -> Spatial:
	var targets = get_tree().get_nodes_in_group(RL_TARGET_GROUP)
	if targets.size() > 0:
		var t = targets[0]
		if t is Spatial: return t
	var current_scene = get_tree().current_scene if get_tree() else null
	if is_instance_valid(current_scene):
		var named = current_scene.get_node_or_null("RL_Target")
		if named and named is Spatial:
			return named
	return null

func _ensure_rl_target() -> Spatial:
	var existing = _get_rl_target()
	if is_instance_valid(existing):
		return existing
	if not is_inside_tree():
		return null
	var current_scene = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return null

	var target := Area.new()
	target.name = "AnnaAutoTarget"
	target.add_to_group(RL_TARGET_GROUP)
	var shape = CollisionShape.new()
	var sphere = SphereShape.new()
	sphere.radius = RL_SUCCESS_DIST
	shape.shape = sphere
	target.add_child(shape)
	current_scene.add_child(target)
	return target

# --- EXISTING HELPERS ---

func _get_proximity() -> Array:
	var player = _get_player()
	if not is_instance_valid(player):
		return []
	if not player is Spatial:
		return []

	var nearby = []
	var candidates = get_tree().get_nodes_in_group("interactable")
	var p_pos = player.global_transform.origin

	for node in candidates:
		if not is_instance_valid(node): continue
		if not node is Spatial: continue
		var dist = p_pos.distance_to(node.global_transform.origin)
		if dist < PROXIMITY_RADIUS:
			var node_type = String(node.filename)
			if node_type == "":
				node_type = node.get_class()
			nearby.append({
				"name": node.name,
				"type": node_type,
				"pos": [node.global_transform.origin.x, node.global_transform.origin.y, node.global_transform.origin.z],
				"dist": dist
			})
	return nearby

func _get_buffer() -> Array:
	if not is_inside_tree():
		return []
	var console = get_tree().root.get_node_or_null("OYS_Console")
	if console and console.has_method("get_logs"):
		var logs = console.get_logs()
		if typeof(logs) != TYPE_ARRAY:
			return []
		if logs.size() <= BUFFER_MAX_ENTRIES:
			return logs

		var trimmed := []
		var start = max(0, logs.size() - BUFFER_MAX_ENTRIES)
		for i in range(start, logs.size()):
			trimmed.append(logs[i])
		return trimmed
	return []

func _get_metrics() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"mem_static": OS.get_static_memory_usage(),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT)
	}

func _get_collisions() -> Array:
	if not is_instance_valid(_raycast_root):
		_setup_sensors()

	var player = _get_player()
	if not is_instance_valid(player):
		# Return max range if no player
		var fallback = []
		for i in range(SENSOR_RAY_COUNT): fallback.append(SENSOR_RANGE)
		return fallback
	if not player is Spatial:
		var fallback = []
		for i in range(SENSOR_RAY_COUNT): fallback.append(SENSOR_RANGE)
		return fallback

	# Teleport sensor to player eye level
	_raycast_root.global_transform.origin = player.global_transform.origin + Vector3(0, 1.0, 0)

	# Force update to get immediate results
	for ray in _rays:
		ray.clear_exceptions()
		ray.add_exception(player)
		ray.force_raycast_update()

	var data = []
	for ray in _rays:
		if ray.is_colliding():
			var col_point = ray.get_collision_point()
			var dist = ray.global_transform.origin.distance_to(col_point)
			data.append(dist)
		else:
			data.append(SENSOR_RANGE)
	return data

func apply_action(action: Dictionary):
	# print("[AnnaInterface] Applying action: ", action.keys())
	var sm = get_node_or_null("/root/SessionManager")
	# If no SessionManager, try direct injection (for minimal test scenes)

	# Movement
	var has_input = action.has("move") or action.has("look") or action.has("jump") or action.has("interact") or action.has("sprint") or action.has("crouch")
	if has_input:
		var move_data = action.get("move", [0.0, 0.0]) # [x, y]
		var jump = action.get("jump", false)
		var interact = action.get("interact", false)
		var sprint = action.get("sprint", false)
		var crouch = action.get("crouch", false)

		# Ensure types
		var vx = 0.0
		var vy = 0.0
		if typeof(move_data) == TYPE_ARRAY and move_data.size() >= 2:
			vx = float(move_data[0])
			vy = float(move_data[1])
		vx = clamp(vx, -1.0, 1.0)
		vy = clamp(vy, -1.0, 1.0)

		# Look / Rotation
		var look_data = action.get("look", [0.0, 0.0])
		var lx = 0.0
		var ly = 0.0
		if typeof(look_data) == TYPE_ARRAY and look_data.size() >= 2:
			lx = float(look_data[0])
			ly = float(look_data[1])
		lx = clamp(lx, -MAX_LOOK_DELTA, MAX_LOOK_DELTA)
		ly = clamp(ly, -MAX_LOOK_DELTA, MAX_LOOK_DELTA)

		var move_vec = Vector2(vx, vy)
		if _is_human_heuristic_active():
			var human_move = _read_human_move_axis()
			if human_move.length_squared() > 0.0001:
				move_vec = human_move

		var input_dict = {
			"move_vec": move_vec,
			"jump": bool(jump),
			"interact": bool(interact),
			"sprint": bool(sprint),
			"crouch": bool(crouch),
			"mouse_delta": Vector2(lx, ly),
			"zoom_delta": 0.0,
			"fov_override": -1.0
		}

		if sm and sm.is_recording:
			sm._oys_input_override = input_dict
		else:
			var player = _get_player()
			if is_instance_valid(player) and player.has_method("inject_input"):
				player.inject_input(input_dict)

	# Command Injection
	if action.has("command") and allow_command_injection:
		var cmd = str(action["command"])
		var console = _resolve_console()
		if console and console.has_method("enqueue_command"):
			console.enqueue_command(cmd)

	# Structured OYS integration for ANNA clients
	if action.has("oys"):
		_apply_oys_action(action["oys"])

	# OLCS/OCLS alias accepted to avoid client-side naming mismatch
	if action.has("olcs"):
		_apply_olcs_action(action["olcs"])
	elif action.has("ocls"):
		_apply_olcs_action(action["ocls"])

func _get_player() -> Node:
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.player:
		return sm.player
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func _get_anna_metadata() -> Dictionary:
	var sm = get_node_or_null("/root/SessionManager")
	return {
		"protocol": PROTOCOL_VERSION,
		"physics_frame": Engine.get_physics_frames(),
		"recording": bool(sm and sm.is_recording),
		"heuristic_human": _is_human_heuristic_active(),
		"integrations": {
			"oys": allow_oys_integration,
			"olcs": allow_olcs_integration
		}
	}

func _resolve_ai_controller() -> Node:
	if not is_inside_tree():
		return null

	if String(ai_controller_path) != "":
		var configured = get_node_or_null(ai_controller_path)
		if configured:
			return configured

	var current_scene = get_tree().current_scene
	if is_instance_valid(current_scene):
		var named = current_scene.get_node_or_null("AIController")
		if named:
			return named

	var group_nodes = get_tree().get_nodes_in_group("ai_controller")
	for node in group_nodes:
		if is_instance_valid(node):
			return node
	return null

func _is_human_heuristic_active() -> bool:
	if not allow_human_heuristic_override:
		return false
	var controller = _resolve_ai_controller()
	if controller == null:
		return false
	var heuristic = str(controller.get("heuristic")).to_lower()
	return heuristic == "human"

func _read_human_move_axis() -> Vector2:
	var human_move = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	)
	human_move.x = clamp(human_move.x, -1.0, 1.0)
	human_move.y = clamp(human_move.y, -1.0, 1.0)
	return human_move

func _resolve_console() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("OYS_Console")

func _should_process_once(payload: Dictionary, domain: String) -> bool:
	if not payload.has("once_id"):
		return true
	var key = "%s:%s" % [domain, str(payload["once_id"])]
	if _accepted_once_ids.has(key):
		return false
	if _accepted_once_ids.size() >= MAX_ONCE_IDS:
		_accepted_once_ids.clear()
	_accepted_once_ids[key] = true
	return true

func _apply_oys_action(payload) -> void:
	if not allow_oys_integration:
		return
	var console = _resolve_console()
	if console == null or not console.has_method("enqueue_command"):
		return

	if typeof(payload) == TYPE_STRING:
		console.enqueue_command(str(payload))
		return
	if typeof(payload) != TYPE_DICTIONARY:
		return
	if not _should_process_once(payload, "oys"):
		return

	if payload.has("command"):
		console.enqueue_command(str(payload["command"]))

	if payload.has("run"):
		var run_path = str(payload["run"]).strip_edges()
		if run_path != "":
			console.enqueue_command("run %s" % run_path)

	if payload.has("exec"):
		var cfg_path = str(payload["exec"]).strip_edges()
		if cfg_path != "":
			console.enqueue_command("exec %s" % cfg_path)

func _resolve_olcs_manager(preferred = "") -> Node:
	if not is_inside_tree():
		return null

	if String(olcs_manager_path) != "":
		var configured = get_node_or_null(olcs_manager_path)
		if configured:
			return configured

	var preferred_name = str(preferred).strip_edges()
	if preferred_name != "":
		var from_scene = null
		var current_scene = get_tree().current_scene
		if is_instance_valid(current_scene):
			from_scene = current_scene.get_node_or_null(preferred_name)
		if from_scene:
			return from_scene
		var from_root = get_tree().root.get_node_or_null(preferred_name)
		if from_root:
			return from_root

	var scene = get_tree().current_scene
	if is_instance_valid(scene):
		var named = scene.get_node_or_null("LogicCircuitManager")
		if named:
			return named

	var managers = get_tree().get_nodes_in_group("olcs_manager")
	for node in managers:
		if is_instance_valid(node):
			return node

	return null

func _get_olcs_observation() -> Dictionary:
	if not allow_olcs_integration:
		return {"available": false}

	var manager = _resolve_olcs_manager()
	if manager == null:
		return {"available": false}

	if manager.has_method("anna_get_snapshot"):
		var snapshot = manager.call("anna_get_snapshot", olcs_snapshot_limit)
		if typeof(snapshot) == TYPE_DICTIONARY:
			if not snapshot.has("available"):
				snapshot["available"] = true
			return snapshot

	return {
		"available": true,
		"manager": manager.name
	}

func _apply_olcs_action(payload) -> void:
	if not allow_olcs_integration:
		return
	if typeof(payload) != TYPE_DICTIONARY:
		return
	if not _should_process_once(payload, "olcs"):
		return

	var manager = _resolve_olcs_manager(payload.get("manager", ""))
	if manager == null:
		return

	if payload.has("rebuild_cables") and bool(payload["rebuild_cables"]):
		if manager.has_method("anna_rebuild_cables"):
			manager.call("anna_rebuild_cables")
		elif manager.has_method("generate_cables"):
			manager.call("generate_cables")

	if payload.has("inject"):
		var inject = payload["inject"]
		if typeof(inject) == TYPE_DICTIONARY and manager.has_method("anna_inject_input"):
			var target = str(inject.get("target", ""))
			var input_id = str(inject.get("input", ""))
			var value = bool(inject.get("value", false))
			if target != "" and input_id != "":
				manager.call("anna_inject_input", target, input_id, value)

	if payload.has("set_output"):
		var set_output = payload["set_output"]
		if typeof(set_output) == TYPE_DICTIONARY and manager.has_method("anna_set_output"):
			var source = str(set_output.get("source", ""))
			var value = bool(set_output.get("value", false))
			if source != "":
				manager.call("anna_set_output", source, value)
