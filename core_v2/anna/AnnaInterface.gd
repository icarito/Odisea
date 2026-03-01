extends Node

class_name AnnaInterface

# Configuration
const PROTOCOL_VERSION = "anna.v1"
const SENSOR_RAY_COUNT = 32 # Legacy/Visual
const RL_SENSOR_RAY_COUNT = 8 # 8 rays + 5 scalar features = 13D obs (rays, dist, angle, vel_x, vel_z, height) (matches bridge/client contracts)
const SENSOR_RANGE = 20.0
const PROXIMITY_RADIUS = 10.0
const BUFFER_MAX_ENTRIES = 50
const MAX_LOOK_DELTA = 250.0
const MAX_ONCE_IDS = 256
const MCP_SCENE_DEPTH_LIMIT = 4
const MCP_SCENE_CHILD_LIMIT = 24
const MCP_DOC_SEARCH_PATHS = ["res://README.md", "res://TODO.md"]
const MCP_SCREENSHOT_DIR = "user://anna_mcp"
const MCP_INLINE_OYS_DIR = "user://anna_mcp/inline_oys"
const OYS_CONSOLE_SCRIPT = preload("res://core_v2/ui/retro/OYS_Console.gd")

# RL Config
const RL_TARGET_GROUP = "anna_target"
const RL_MAX_VELOCITY = 20.0
const RL_REWARD_SUCCESS = 100.0
const RL_REWARD_FAILURE = -100.0
const RL_REWARD_TIME_PENALTY = -0.1
const RL_MAX_EPISODE_STEPS = 1500
const RL_SHAPING_REWARD_CLAMP = 2.5 # Clamp only shaping terms; keep terminal rewards outside.
const RL_TIMEOUT_FAILURE_SCALE = 0.35
const RL_PROGRESS_SCALE = 12.0
const RL_SUCCESS_DIST = 2.0
const RL_AREA_SUCCESS_MAX_DIST = 6.0 # Guard stale Area overlap right after reset/teleport.
const RL_SPEED_REWARD_SCALE = 0.012 # Keep locomotion incentive without collapsing to always-forward.
const RL_SPRINT_REWARD_SCALE = 0.12 # Strong bonus when explicit sprint action is used.
const RL_SPRINT_TARGET_SPEED = 8.5 # Prefer true sprint pace over walk/jog.
const RL_SPEED_TARGET_REWARD_SCALE = 0.10 # Reward approaching sprint target speed.
const RL_SPRINT_ACTION_BONUS = 0.24 # Flat bonus for selecting sprint in favorable conditions.
const RL_NO_SPRINT_WHEN_ALIGNED_PENALTY = 0.20 # Strongly discourage jogging when aligned and path is clear.
const RL_LOW_SPEED_WHEN_ALIGNED_PENALTY_SCALE = 0.06 # Penalize staying slow in sprint-friendly context.
const RL_JUMP_ACTION_PENALTY = 0.01 # Small baseline cost; keeps jump purposeful.
const RL_JUMP_REPEAT_PENALTY = 0.03 # Stronger penalty for repeated jump spam.
const RL_AIRBORNE_PENALTY = 0.0 # Do not punish being airborne; jumping is useful in obstacle courses.
const RL_HEIGHT_REWARD_SCALE = 0.04 # Reward gaining height to clear obstacles.
const RL_HEIGHT_REWARD_CAP = 2.5
const RL_OBSTACLE_AHEAD_DIST = 1.6
const RL_OBSTACLE_JUMP_BONUS = 0.22 # Strong bonus for jumping when obstacle is ahead.
const RL_BAD_JUMP_PENALTY = 0.12 # Penalize jumping when no nearby frontal obstacle.
const RL_JUMPABLE_OBSTACLE_BONUS = 0.16 # Extra reward when jump clears a low front obstacle.
const RL_JUMPABLE_OBSTACLE_IGNORE_PENALTY = 0.10 # Penalize pushing forward into jumpable frontal obstacles without jumping.
const RL_OBSTACLE_NO_EVASION_PENALTY = 0.08 # Penalize pushing head-on into nearby obstacles without jump/strafe.
const RL_FRONT_HEIGHT_SENSOR_DIST = 2.4
const RL_FRONT_HEIGHT_LOW_Y = 0.55
const RL_FRONT_HEIGHT_HIGH_Y = 1.35
const RL_FRONT_HEIGHT_CLEARANCE_MARGIN = 0.08
const RL_STRAFE_WHEN_MISALIGNED_REWARD_SCALE = 0.08 # Encourage strafe corrections when target is off-center.
const RL_STRAFE_OBSTACLE_REWARD_SCALE = 0.06 # Encourage strafe around nearby frontal obstacles.
const RL_STRAFE_IDLE_PENALTY = 0.015 # Discourage needless strafe when already aligned.
const RL_STRAFE_SIDE_CHOICE_REWARD_SCALE = 0.06 # Reward choosing the lateral side that actually opens path.
const RL_STRAFE_SIDE_WRONG_PENALTY_SCALE = 0.11 # Penalize strafe toward the tighter/wrong side in narrow passages.
const RL_APPROACH_SPEED_REWARD_SCALE = 0.06 # Reward world velocity projected toward target direction.
const RL_TANGENTIAL_SPEED_PENALTY_SCALE = 0.09 # Penalize circling/orbiting around target.
const RL_NEAR_TARGET_ORBIT_PENALTY_SCALE = 0.34 # Stronger tangential penalty when already close.
const RL_NEAR_TARGET_RADIUS = 5.0
const RL_NEAR_TARGET_MOVING_AWAY_PENALTY_SCALE = 0.24 # Penalize increasing distance when already near target.
const RL_NEAR_TARGET_STRAFE_PENALTY_SCALE = 0.12 # Penalize lateral-only movement near target.
const RL_ORBIT_RATIO_PENALTY_SCALE = 0.16 # Penalize tangential dominance over radial approach.
const RL_ALIGNMENT_REWARD_SCALE = 0.04 # Shaping reward for facing target.
const RL_PROXIMITY_REWARD_SCALE = 0.02 # Smooth bonus for getting closer even before success radius.
const RL_PROXIMITY_REFERENCE_DIST = 20.0
const RL_NEAR_TARGET_BONUS_DIST = 4.0
const RL_NEAR_TARGET_BONUS_SCALE = 0.22 # Extra shaping when close, to offset timeout-dominated episodes.
const RL_ANGLE_PROGRESS_SCALE = 1.8 # Reward reducing absolute angle-to-target.
const RL_LOOK_USAGE_REWARD_SCALE = 0.01 # Encourage camera movement when misaligned.
const RL_ANGLE_ABS_PENALTY_SCALE = 0.10 # Penalize staying off-target.
const RL_AIM_STABILITY_BONUS_SCALE = 0.06 # Bonus when consistently aimed at target.
const RL_FORWARD_MISALIGN_PENALTY_SCALE = 0.16 # Penalize fast movement while not aiming at target.
const RL_ALIGNED_SPEED_REWARD_SCALE = 0.05 # Reward forward speed only when aligned.
const RL_UNALIGNED_SPEED_PENALTY_SCALE = 0.08 # Penalize rushing with poor aim.
const RL_MOVING_AWAY_WHEN_ALIGNED_PENALTY_SCALE = 0.22 # Penalize backing away while already aimed at target and clear path.
const RL_BACKSTEP_WHEN_ALIGNED_CLEAR_PENALTY = 0.14 # Additional penalty when explicit backward input is used in that context.
const RL_NO_CORRECTION_PENALTY = 0.06 # Penalize not using look while drifting off-target.
const RL_NO_CORRECTION_PENALTY_CAP = 0.8 # Avoid runaway penalty explosion in long misaligned streaks.
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
const RL_STEER_ONLY_IDLE_PENALTY = 0.16 # Discourage camera-only policy collapse when far from target.
const RL_SAME_ACTION_STREAK_PENALTY = 0.02 # Penalize repeating same action while not improving.
const RL_BAD_STREAK_DIST_EPS = 0.01
const RL_BAD_STREAK_ANGLE_EPS = 0.005
const RL_LOOK_DELTA_X = 10.0
const RL_LOOK_DELTA_Y = 2.0
const RL_LOOK_ALIGN_DEADZONE = 0.03 # Keep correcting, but don't jitter around perfect alignment.
const RL_LOOK_MIN_CORRECTION = 4.0 # Strong minimum yaw correction when clearly misaligned.
const RL_MOVE_ALIGN_GATE = 0.10 # Begin throttling forward when heading is clearly wrong.
const RL_MOVE_MIN_THROTTLE = 0.18 # Keep some forward motion while correcting to avoid freezing episodes.
const RL_SPRINT_DISABLE_THROTTLE = 0.35 # Only disable sprint when heavy throttle reduction is needed.
const RL_AUTO_SPRINT_ANGLE_MAX = 0.22 # Auto-enable sprint while reasonably aligned and far from target.
const RL_AUTO_SPRINT_OBSTACLE_CLEAR_FACTOR = 1.25
const RL_AUTO_SPRINT_MIN_DIST_FACTOR = 1.8
const RL_ORBIT_CONTROL_DIST = 6.5 # When inside this range, prioritize correction over speed.
const RL_ORBIT_CONTROL_ANGLE = 0.18 # Misalignment threshold for anti-orbit control.
const RL_ORBIT_FORWARD_THROTTLE = 0.35 # Reduce forward commit near target while misaligned.
const RL_ORBIT_STRAFE_THROTTLE = 0.45 # Reduce strafe orbiting near target while misaligned.
const RL_COLLISION_PENALTY_THRESHOLD = 0.6 # If ray < 0.6m ~ collision
const RL_FLOOR_NORMAL_Y_THRESHOLD = 0.6 # Upward-facing collisions are treated as floor/support.
const RL_HAZARD_CONTACT_GRACE_FRAMES = 24 # Detect wall-stuck states sooner.
const RL_WALL_CONTACT_PENALTY = 0.05 # Strong shaping penalty for sustained wall contact.
const RL_STUCK_WALL_FAIL_FRAMES = 120 # Fail earlier if clearly stuck against walls.
const RL_STUCK_MIN_HSPEED = 0.12
const RL_STUCK_MIN_PROGRESS_SPEED = 0.05
const RL_STUCK_EXTRA_PENALTY_SCALE = 0.015 # Progressive punishment while stuck.
const RL_STUCK_EXTRA_PENALTY_CAP = 0.5
const RL_STUCK_RECOVERY_WALL_FRAMES = 12 # Trigger recovery sooner when hugging walls.
const RL_STUCK_NO_RECOVERY_PENALTY = 0.18
const RL_STUCK_RECOVERY_REWARD = 0.08
const RL_STUCK_RECOVERY_BACKOFF = 1.0
const RL_STUCK_RECOVERY_STRAFE = 0.95
const RL_STUCK_RECOVERY_JUMP_PERIOD = 7
const RL_HAZARD_EVASION_REWARD = 0.05 # Reward trying strafe/back/jump while in wall contact.
const RL_HAZARD_FORWARD_PRESS_PENALTY = 0.12 # Penalize insisting on forward into wall contact.
const RL_WALL_ESCAPE_PROGRESS_REWARD_SCALE = 0.12 # Reward increasing frontal clearance while in hazard.
const RL_WALL_ESCAPE_REGRESS_PENALTY_SCALE = 0.06 # Penalize reducing frontal clearance while in hazard.
const RL_SMART_JUMP_AHEAD_DIST = 1.85 # Jump is only useful when obstacle is close ahead.
const RL_SMART_JUMP_MIN_COOLDOWN = 8 # Avoid hop-spam between consecutive frames.
const RL_SMART_JUMP_ALLOW_STUCK_FRAMES = 12 # If stuck, allow more aggressive jump recovery.
const RL_SMART_JUMP_TARGET_ABOVE_Y = 1.2 # If target is this much higher, allow jump-assist even without frontal obstacle.
const RL_SMART_JUMP_TARGET_ABOVE_DIST = 9.0 # Jump-assist only when horizontally close enough to upper target.
const RL_SMART_JUMP_MAX_STEER_ANGLE = 0.45 # Require approximate heading before vertical jump-assist.
const RL_INTERACT_RANGE = 3.25
const RL_INTERACT_FORWARD_DOT_MIN = 0.15
const RL_INTERACT_CONTEXT_REWARD = 0.32
const RL_INTERACT_SPAM_PENALTY = 0.04
const RL_INTERACT_REPEAT_PENALTY = 0.05
const RL_INTERACT_COOLDOWN_FRAMES = 8
const RL_MISSED_INTERACT_PENALTY = 0.14 # Penalize pressing forward into a nearby interactable obstacle without interacting.
const RL_INTERACT_AUTO_RANGE = 3.6 # Slightly wider than manual range to assist door usage.
const RL_INTERACT_AUTO_FRONT_BLOCK_DIST = 2.0
const RL_INTERACT_STUCK_TRIGGER_FRAMES = 10
const RL_INTERACT_OPEN_PROGRESS_REWARD_SCALE = 0.10
const RL_INTERACT_APPROACH_REWARD_SCALE = 0.22 # Reward moving toward a closed interactable that blocks route.
const RL_INTERACT_ROUTE_ALIGN_REWARD_SCALE = 0.08 # Reward looking toward door candidate when it is relevant.
const RL_INTERACT_FORWARD_IGNORE_PENALTY = 0.06 # Penalize forcing forward into closed interactable route blocker.
const RL_OPEN_DOOR_PASSAGE_STRAFE_PENALTY_SCALE = 0.14 # Penalize zigzag strafe when door is already open and passable.
const RL_OPEN_DOOR_PASSAGE_FORWARD_BONUS = 0.10 # Reward committing forward through open doorway.
const RL_ROUTE_INTERACT_FRONT_FACTOR = 1.4 # Door-subgoal trigger expands front-block test beyond auto-interact threshold.
const RL_ROUTE_PROGRESS_WEIGHT = 0.25 # When door subgoal is active, de-prioritize direct target progress.
const RL_ROUTE_GOAL_SWITCH_BONUS = 0.06 # Small bonus to keep policy committed to door objective once detected.
const RL_DOOR_INTERACT_BIAS = 1.0 # >1 prioritizes door interaction over jump when a closed door blocks frontal route.
const RL_POST_DOOR_FORWARD_COMMIT_BONUS = 0.12 # Once door is opened, reward committing forward toward target.
const RL_POST_DOOR_BACKSTEP_PENALTY = 0.22 # Penalize backing away after door has been opened.
const RL_POST_DOOR_MOVE_AWAY_PENALTY_SCALE = 0.18 # Penalize increasing target distance after door open.
const RL_REQUIRE_INTERACTABLE_OPEN_FOR_SUCCESS = false # Optional hard-gate: reaching target only succeeds after opening an interactable.
const RL_SUCCESS_INTERACTABLE_PROGRESS = 0.9 # Treat interactable as "opened" above this target_progress.
const RL_BYPASS_SUCCESS_PENALTY_SCALE = 0.6 # Portion of failure reward used when bypassing the required interactable gate.
const RL_START_FAILURE_GRACE_STEPS = 10 # Ignore hard failure conditions during first steps after reset to avoid spawn jitter false negatives.
const RL_FALL_DISTANCE = 3.5 # Episode fails if player falls this much below episode start height.
const RL_SPAWN_ZONE_GROUP = "anna_rl_spawn_zone"
const RL_TARGET_ZONE_GROUP = "anna_rl_target_zone"
const RL_SPAWN_POINT_GROUP = "anna_rl_spawn_point"
const RL_TARGET_POINT_GROUP = "anna_rl_target_point"
const RL_SPAWN_SAMPLE_TRIES = 24
const RL_TARGET_SAMPLE_TRIES = 28
const RL_FLOOR_SNAP_UP = 4.0
const RL_FLOOR_SNAP_DOWN = 16.0
const RL_FLOOR_SNAP_CLEARANCE = 0.32
const RL_TARGET_MIN_SEPARATION = 4.0
const RL_SHAPING_PROFILE_BALANCED = "balanced"
const RL_SHAPING_PROFILE_STABLE = "stable"
const RL_SHAPING_PROFILE_FAST = "fast"
const RL_SCENE_HOOK_BEFORE_RESET = "anna_rl_before_episode_reset"
const RL_SCENE_HOOK_CHOOSE_EPISODE = "anna_rl_choose_episode"

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
var _episode_step_count := 0
var _rl_time_penalty := RL_REWARD_TIME_PENALTY
var _rl_max_episode_steps := RL_MAX_EPISODE_STEPS
var _rl_base_max_episode_steps := RL_MAX_EPISODE_STEPS
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
var _last_front_ray_dist := -1.0
var _last_route_interact_dist := -1.0
var _last_route_interact_progress := -1.0
var _cached_player: Node = null
var _cached_target: Spatial = null

# Spawn config (overrideable via env vars for scene-specific safe positions)
var _rl_spawn_pos := Vector3(0.0, 2.0, 0.0)
var _rl_spawn_alt_pos := Vector3(0.0, 2.0, 0.0)
var _rl_spawn_alt_enabled := false
var _rl_spawn_alt_prob := 0.0
var _rl_spawn_random_yaw := true
var _rl_target_radius_min := 5.0
var _rl_target_radius_max := 20.0
var _rl_target_fixed_y := 1.0
var _rl_spawn_bounds_enabled := false
var _rl_target_bounds_enabled := false
var _rl_spawn_bounds_min := Vector3.ZERO
var _rl_spawn_bounds_max := Vector3.ZERO
var _rl_target_bounds_min := Vector3.ZERO
var _rl_target_bounds_max := Vector3.ZERO
var _rl_spawn_sample_tries := RL_SPAWN_SAMPLE_TRIES
var _rl_target_sample_tries := RL_TARGET_SAMPLE_TRIES
var _rl_target_min_separation := RL_TARGET_MIN_SEPARATION
var _rl_spawn_zone_nodes := []
var _rl_target_zone_nodes := []
var _rl_spawn_point_nodes := []
var _rl_target_point_nodes := []
var _rl_smart_jump_ahead_dist := RL_SMART_JUMP_AHEAD_DIST
var _rl_smart_jump_target_above_y := RL_SMART_JUMP_TARGET_ABOVE_Y
var _rl_smart_jump_target_above_dist := RL_SMART_JUMP_TARGET_ABOVE_DIST
var _rl_smart_jump_max_steer_angle := RL_SMART_JUMP_MAX_STEER_ANGLE
var _rl_front_height_sensor_dist := RL_FRONT_HEIGHT_SENSOR_DIST
var _rl_front_height_low_y := RL_FRONT_HEIGHT_LOW_Y
var _rl_front_height_high_y := RL_FRONT_HEIGHT_HIGH_Y
var _rl_legacy_fast_mode := false
var _rl_hazard_contact_grace_frames := RL_HAZARD_CONTACT_GRACE_FRAMES
var _rl_wall_contact_penalty := RL_WALL_CONTACT_PENALTY
var _rl_stuck_wall_fail_frames := RL_STUCK_WALL_FAIL_FRAMES
var _rl_stuck_extra_penalty_scale := RL_STUCK_EXTRA_PENALTY_SCALE
var _rl_stuck_extra_penalty_cap := RL_STUCK_EXTRA_PENALTY_CAP
var _rl_stuck_no_recovery_penalty := RL_STUCK_NO_RECOVERY_PENALTY
var _rl_hazard_forward_press_penalty := RL_HAZARD_FORWARD_PRESS_PENALTY
var _rl_shaping_profile := RL_SHAPING_PROFILE_BALANCED
var _rl_timeout_failure_scale := RL_TIMEOUT_FAILURE_SCALE
var _rl_shaping_reward_clamp := RL_SHAPING_REWARD_CLAMP
var _rl_progress_reward_scale := 1.0
var _rl_alignment_reward_scale := 1.0
var _rl_speed_reward_scale := 1.0
var _rl_penalty_scale := 1.0
var _rl_orbit_penalty_scale := 1.0
var _rl_wall_penalty_scale := 1.0
var _rl_jump_penalty_scale := 1.0
var _rl_strafe_reward_scale := 1.0
var _rl_strafe_penalty_scale := 1.0
var _rl_action_change_penalty_scale := 1.0
var _rl_stuck_recovery_strafe := RL_STUCK_RECOVERY_STRAFE
var _rl_stuck_recovery_backoff := RL_STUCK_RECOVERY_BACKOFF
var _rl_stuck_recovery_jump_period := RL_STUCK_RECOVERY_JUMP_PERIOD
var _rl_stuck_recovery_wall_frames := RL_STUCK_RECOVERY_WALL_FRAMES
var _rl_early_wall_recovery_hazard_frames := 6
var _rl_early_wall_recovery_front_dist := RL_OBSTACLE_AHEAD_DIST
var _rl_recovery_strafe_side := 0.0
var _rl_recovery_strafe_side_bias := 0.0
var _rl_recovery_side_clear_margin := 0.35
var _rl_recovery_fallback_side := 1.0
var _rl_jump_hold_input_frames := 2
var _rl_jump_hold_frames := 0
var _rl_assisted_steering := true
var _rl_action0_backstep_enabled := false
var _rl_action0_backstep_speed := 0.8
var _rl_sprint_on_jump_actions := false
var _rl_sprint_on_strafe_actions := false
var _rl_sprint_on_jump_strafe_actions := false
var _rl_strafe_forward_assist := 0.0
var _rl_jump_strafe_forward_assist := 0.0
var _rl_strafe_commit_frames := 7
var _rl_strafe_commit_remaining := 0
var _rl_strafe_commit_side := 0.0
var _rl_backstep_evasion_reward := 0.12
var _rl_sprint_strafe_clear_penalty := 0.18
var _rl_look_delta_x := RL_LOOK_DELTA_X
var _rl_look_min_correction := RL_LOOK_MIN_CORRECTION
var _rl_door_interact_bias := RL_DOOR_INTERACT_BIAS
var _rl_require_interactable_open_for_success := RL_REQUIRE_INTERACTABLE_OPEN_FOR_SUCCESS
var _rl_success_interactable_progress := RL_SUCCESS_INTERACTABLE_PROGRESS
var _rl_bypass_success_penalty_scale := RL_BYPASS_SUCCESS_PENALTY_SCALE
var _rl_episode_require_interactable_open_for_success := false
var _rl_episode_interactable_opened := false
var _rl_start_failure_grace_steps := RL_START_FAILURE_GRACE_STEPS
var _rl_last_episode_override := {}
var _rl_scene_controller_cache: Node = null
var _rl_debug_short_done := false

func _ready():
	_rl_legacy_fast_mode = OS.get_environment("ANNA_RL_LEGACY_FAST_MODE").to_lower() in ["1", "true", "yes", "on"]
	var rl_max_steps_env = OS.get_environment("ANNA_RL_MAX_STEPS")
	if rl_max_steps_env.is_valid_integer():
		_rl_max_episode_steps = max(100, int(rl_max_steps_env))
	_rl_base_max_episode_steps = _rl_max_episode_steps
	var rl_time_penalty_env = OS.get_environment("ANNA_RL_TIME_PENALTY")
	if rl_time_penalty_env.is_valid_float():
		_rl_time_penalty = float(rl_time_penalty_env)
	# Spawn position override (useful for scene-specific safe floor positions)
	var sx = OS.get_environment("ANNA_RL_SPAWN_X")
	var sy = OS.get_environment("ANNA_RL_SPAWN_Y")
	var sz = OS.get_environment("ANNA_RL_SPAWN_Z")
	if sx.is_valid_float(): _rl_spawn_pos.x = float(sx)
	if sy.is_valid_float(): _rl_spawn_pos.y = float(sy)
	if sz.is_valid_float(): _rl_spawn_pos.z = float(sz)
	var sax = OS.get_environment("ANNA_RL_SPAWN_ALT_X")
	var say = OS.get_environment("ANNA_RL_SPAWN_ALT_Y")
	var saz = OS.get_environment("ANNA_RL_SPAWN_ALT_Z")
	var spawn_alt_prob = OS.get_environment("ANNA_RL_SPAWN_ALT_PROB")
	_rl_spawn_alt_pos = _rl_spawn_pos
	if sax.is_valid_float() or say.is_valid_float() or saz.is_valid_float():
		if sax.is_valid_float(): _rl_spawn_alt_pos.x = float(sax)
		if say.is_valid_float(): _rl_spawn_alt_pos.y = float(say)
		if saz.is_valid_float(): _rl_spawn_alt_pos.z = float(saz)
		_rl_spawn_alt_enabled = true
	if spawn_alt_prob.is_valid_float():
		_rl_spawn_alt_prob = clamp(float(spawn_alt_prob), 0.0, 1.0)
		if _rl_spawn_alt_prob > 0.0:
			_rl_spawn_alt_enabled = true
	# Target placement radius override (smaller = easier episodes)
	var tr_min = OS.get_environment("ANNA_RL_TARGET_RADIUS_MIN")
	var tr_max = OS.get_environment("ANNA_RL_TARGET_RADIUS_MAX")
	var tr_y = OS.get_environment("ANNA_RL_TARGET_Y")
	var spawn_random_yaw_env = OS.get_environment("ANNA_RL_SPAWN_RANDOM_YAW")
	var spawn_bounds_env = OS.get_environment("ANNA_RL_SPAWN_BOUNDS")
	var target_bounds_env = OS.get_environment("ANNA_RL_TARGET_BOUNDS")
	var spawn_tries_env = OS.get_environment("ANNA_RL_SPAWN_SAMPLE_TRIES")
	var target_tries_env = OS.get_environment("ANNA_RL_TARGET_SAMPLE_TRIES")
	var target_min_separation_env = OS.get_environment("ANNA_RL_TARGET_MIN_SEPARATION")
	var shaping_profile_env = OS.get_environment("ANNA_RL_SHAPING_PROFILE")
	if tr_min.is_valid_float(): _rl_target_radius_min = max(1.0, float(tr_min))
	if tr_max.is_valid_float(): _rl_target_radius_max = max(_rl_target_radius_min + 1.0, float(tr_max))
	if tr_y.is_valid_float(): _rl_target_fixed_y = float(tr_y)
	if spawn_random_yaw_env != "":
		_rl_spawn_random_yaw = spawn_random_yaw_env.to_lower() in ["1", "true", "yes", "on"]
	_apply_rl_bounds_from_env(spawn_bounds_env, true)
	_apply_rl_bounds_from_env(target_bounds_env, false)
	if spawn_tries_env.is_valid_integer():
		_rl_spawn_sample_tries = int(clamp(int(spawn_tries_env), 4, 160))
	if target_tries_env.is_valid_integer():
		_rl_target_sample_tries = int(clamp(int(target_tries_env), 4, 220))
	if target_min_separation_env.is_valid_float():
		_rl_target_min_separation = clamp(float(target_min_separation_env), 0.5, 30.0)
	var jump_ahead_env = OS.get_environment("ANNA_RL_JUMP_AHEAD_DIST")
	var jump_above_y_env = OS.get_environment("ANNA_RL_JUMP_TARGET_ABOVE_Y")
	var jump_above_dist_env = OS.get_environment("ANNA_RL_JUMP_TARGET_ABOVE_DIST")
	var jump_max_steer_env = OS.get_environment("ANNA_RL_JUMP_MAX_STEER_ANGLE")
	var jump_front_height_dist_env = OS.get_environment("ANNA_RL_FRONT_HEIGHT_SENSOR_DIST")
	var jump_front_height_low_y_env = OS.get_environment("ANNA_RL_FRONT_HEIGHT_LOW_Y")
	var jump_front_height_high_y_env = OS.get_environment("ANNA_RL_FRONT_HEIGHT_HIGH_Y")
	var wall_contact_penalty_env = OS.get_environment("ANNA_RL_WALL_CONTACT_PENALTY")
	var stuck_fail_frames_env = OS.get_environment("ANNA_RL_STUCK_WALL_FAIL_FRAMES")
	var stuck_extra_scale_env = OS.get_environment("ANNA_RL_STUCK_EXTRA_PENALTY_SCALE")
	var stuck_extra_cap_env = OS.get_environment("ANNA_RL_STUCK_EXTRA_PENALTY_CAP")
	var stuck_no_recovery_env = OS.get_environment("ANNA_RL_STUCK_NO_RECOVERY_PENALTY")
	var hazard_forward_press_env = OS.get_environment("ANNA_RL_HAZARD_FORWARD_PRESS_PENALTY")
	var hazard_grace_frames_env = OS.get_environment("ANNA_RL_HAZARD_CONTACT_GRACE_FRAMES")
	var jump_penalty_scale_env = OS.get_environment("ANNA_RL_JUMP_PENALTY_SCALE")
	var strafe_reward_scale_env = OS.get_environment("ANNA_RL_STRAFE_REWARD_SCALE")
	var strafe_penalty_scale_env = OS.get_environment("ANNA_RL_STRAFE_PENALTY_SCALE")
	var action_change_penalty_scale_env = OS.get_environment("ANNA_RL_ACTION_CHANGE_PENALTY_SCALE")
	var stuck_recovery_strafe_env = OS.get_environment("ANNA_RL_STUCK_RECOVERY_STRAFE")
	var stuck_recovery_backoff_env = OS.get_environment("ANNA_RL_STUCK_RECOVERY_BACKOFF")
	var stuck_recovery_jump_period_env = OS.get_environment("ANNA_RL_STUCK_RECOVERY_JUMP_PERIOD")
	var stuck_recovery_wall_frames_env = OS.get_environment("ANNA_RL_STUCK_RECOVERY_WALL_FRAMES")
	var early_wall_recovery_hazard_frames_env = OS.get_environment("ANNA_RL_EARLY_WALL_RECOVERY_HAZARD_FRAMES")
	var early_wall_recovery_front_dist_env = OS.get_environment("ANNA_RL_EARLY_WALL_RECOVERY_FRONT_DIST")
	var recovery_strafe_side_env = OS.get_environment("ANNA_RL_RECOVERY_STRAFE_SIDE")
	var recovery_side_clear_margin_env = OS.get_environment("ANNA_RL_RECOVERY_SIDE_CLEAR_MARGIN")
	var jump_hold_frames_env = OS.get_environment("ANNA_RL_JUMP_HOLD_FRAMES")
	var assisted_steering_env = OS.get_environment("ANNA_RL_ASSISTED_STEERING")
	var look_delta_x_env = OS.get_environment("ANNA_RL_LOOK_DELTA_X")
	var look_min_correction_env = OS.get_environment("ANNA_RL_LOOK_MIN_CORRECTION")
	var action0_backstep_env = OS.get_environment("ANNA_RL_ACTION0_BACKSTEP")
	var action0_backstep_speed_env = OS.get_environment("ANNA_RL_ACTION0_BACKSTEP_SPEED")
	var sprint_on_jump_env = OS.get_environment("ANNA_RL_SPRINT_ON_JUMP")
	var sprint_on_strafe_env = OS.get_environment("ANNA_RL_SPRINT_ON_STRAFE")
	var sprint_on_jump_strafe_env = OS.get_environment("ANNA_RL_SPRINT_ON_JUMP_STRAFE")
	var strafe_forward_assist_env = OS.get_environment("ANNA_RL_STRAFE_FORWARD_ASSIST")
	var strafe_commit_frames_env = OS.get_environment("ANNA_RL_STRAFE_COMMIT_FRAMES")
	var jump_strafe_forward_assist_env = OS.get_environment("ANNA_RL_JUMP_STRAFE_FORWARD_ASSIST")
	var backstep_evasion_reward_env = OS.get_environment("ANNA_RL_BACKSTEP_EVASION_REWARD")
	var sprint_strafe_clear_penalty_env = OS.get_environment("ANNA_RL_SPRINT_STRAFE_CLEAR_PENALTY")
	var door_interact_bias_env = OS.get_environment("ANNA_RL_DOOR_INTERACT_BIAS")
	var require_interactable_open_success_env = OS.get_environment("ANNA_RL_REQUIRE_INTERACTABLE_OPEN_FOR_SUCCESS")
	var success_interactable_progress_env = OS.get_environment("ANNA_RL_SUCCESS_INTERACTABLE_PROGRESS")
	var bypass_success_penalty_scale_env = OS.get_environment("ANNA_RL_BYPASS_SUCCESS_PENALTY_SCALE")
	var start_failure_grace_steps_env = OS.get_environment("ANNA_RL_START_FAILURE_GRACE_STEPS")
	var debug_short_done_env = OS.get_environment("ANNA_RL_DEBUG_SHORT_DONE")
	if jump_ahead_env.is_valid_float():
		_rl_smart_jump_ahead_dist = clamp(float(jump_ahead_env), 0.8, 4.0)
	if jump_above_y_env.is_valid_float():
		_rl_smart_jump_target_above_y = clamp(float(jump_above_y_env), 0.4, 4.0)
	if jump_above_dist_env.is_valid_float():
		_rl_smart_jump_target_above_dist = clamp(float(jump_above_dist_env), 2.0, 25.0)
	if jump_max_steer_env.is_valid_float():
		_rl_smart_jump_max_steer_angle = clamp(float(jump_max_steer_env), 0.08, 1.0)
	if jump_front_height_dist_env.is_valid_float():
		_rl_front_height_sensor_dist = clamp(float(jump_front_height_dist_env), 0.5, 6.0)
	if jump_front_height_low_y_env.is_valid_float():
		_rl_front_height_low_y = clamp(float(jump_front_height_low_y_env), 0.15, 1.6)
	if jump_front_height_high_y_env.is_valid_float():
		_rl_front_height_high_y = clamp(float(jump_front_height_high_y_env), _rl_front_height_low_y + 0.1, 2.4)
	if wall_contact_penalty_env.is_valid_float():
		_rl_wall_contact_penalty = clamp(float(wall_contact_penalty_env), 0.0, 1.5)
	if stuck_fail_frames_env.is_valid_integer():
		_rl_stuck_wall_fail_frames = int(clamp(int(stuck_fail_frames_env), 20, 2000))
	if stuck_extra_scale_env.is_valid_float():
		_rl_stuck_extra_penalty_scale = clamp(float(stuck_extra_scale_env), 0.0, 0.2)
	if stuck_extra_cap_env.is_valid_float():
		_rl_stuck_extra_penalty_cap = clamp(float(stuck_extra_cap_env), 0.0, 2.0)
	if stuck_no_recovery_env.is_valid_float():
		_rl_stuck_no_recovery_penalty = clamp(float(stuck_no_recovery_env), 0.0, 2.0)
	if hazard_forward_press_env.is_valid_float():
		_rl_hazard_forward_press_penalty = clamp(float(hazard_forward_press_env), 0.0, 2.0)
	if hazard_grace_frames_env.is_valid_integer():
		_rl_hazard_contact_grace_frames = int(clamp(int(hazard_grace_frames_env), 0, 400))
	if jump_penalty_scale_env.is_valid_float():
		_rl_jump_penalty_scale = clamp(float(jump_penalty_scale_env), 0.2, 4.0)
	if strafe_reward_scale_env.is_valid_float():
		_rl_strafe_reward_scale = clamp(float(strafe_reward_scale_env), 0.2, 4.0)
	if strafe_penalty_scale_env.is_valid_float():
		_rl_strafe_penalty_scale = clamp(float(strafe_penalty_scale_env), 0.0, 3.0)
	if action_change_penalty_scale_env.is_valid_float():
		_rl_action_change_penalty_scale = clamp(float(action_change_penalty_scale_env), 0.0, 3.0)
	if stuck_recovery_strafe_env.is_valid_float():
		_rl_stuck_recovery_strafe = clamp(float(stuck_recovery_strafe_env), 0.1, 1.5)
	if stuck_recovery_backoff_env.is_valid_float():
		_rl_stuck_recovery_backoff = clamp(float(stuck_recovery_backoff_env), -1.0, 1.5)
	if stuck_recovery_jump_period_env.is_valid_integer():
		_rl_stuck_recovery_jump_period = int(clamp(int(stuck_recovery_jump_period_env), 0, 120))
	if stuck_recovery_wall_frames_env.is_valid_integer():
		_rl_stuck_recovery_wall_frames = int(clamp(int(stuck_recovery_wall_frames_env), 2, 120))
	if early_wall_recovery_hazard_frames_env.is_valid_integer():
		_rl_early_wall_recovery_hazard_frames = int(clamp(int(early_wall_recovery_hazard_frames_env), 1, 120))
	if early_wall_recovery_front_dist_env.is_valid_float():
		_rl_early_wall_recovery_front_dist = clamp(float(early_wall_recovery_front_dist_env), 0.4, 4.0)
	if recovery_strafe_side_env.is_valid_float():
		_rl_recovery_strafe_side_bias = clamp(float(recovery_strafe_side_env), -1.0, 1.0)
		if abs(_rl_recovery_strafe_side_bias) < 0.1:
			_rl_recovery_strafe_side_bias = 0.0
		else:
			_rl_recovery_strafe_side_bias = sign(_rl_recovery_strafe_side_bias)
	if recovery_side_clear_margin_env.is_valid_float():
		_rl_recovery_side_clear_margin = clamp(float(recovery_side_clear_margin_env), 0.05, 3.0)
	if jump_hold_frames_env.is_valid_integer():
		_rl_jump_hold_input_frames = int(clamp(int(jump_hold_frames_env), 0, 12))
	if assisted_steering_env != "":
		_rl_assisted_steering = assisted_steering_env.to_lower() in ["1", "true", "yes", "on"]
	if look_delta_x_env.is_valid_float():
		_rl_look_delta_x = clamp(float(look_delta_x_env), 2.0, 40.0)
	if look_min_correction_env.is_valid_float():
		_rl_look_min_correction = clamp(float(look_min_correction_env), 0.5, 20.0)
	if action0_backstep_env != "":
		_rl_action0_backstep_enabled = action0_backstep_env.to_lower() in ["1", "true", "yes", "on"]
	if action0_backstep_speed_env.is_valid_float():
		_rl_action0_backstep_speed = clamp(float(action0_backstep_speed_env), 0.1, 1.0)
	if sprint_on_jump_env != "":
		_rl_sprint_on_jump_actions = sprint_on_jump_env.to_lower() in ["1", "true", "yes", "on"]
	if sprint_on_strafe_env != "":
		_rl_sprint_on_strafe_actions = sprint_on_strafe_env.to_lower() in ["1", "true", "yes", "on"]
	if sprint_on_jump_strafe_env != "":
		_rl_sprint_on_jump_strafe_actions = sprint_on_jump_strafe_env.to_lower() in ["1", "true", "yes", "on"]
	if strafe_forward_assist_env.is_valid_float():
		_rl_strafe_forward_assist = clamp(float(strafe_forward_assist_env), 0.0, 1.0)
	if strafe_commit_frames_env.is_valid_integer():
		_rl_strafe_commit_frames = int(clamp(int(strafe_commit_frames_env), 0, 30))
	if jump_strafe_forward_assist_env.is_valid_float():
		_rl_jump_strafe_forward_assist = clamp(float(jump_strafe_forward_assist_env), 0.0, 1.0)
	if backstep_evasion_reward_env.is_valid_float():
		_rl_backstep_evasion_reward = clamp(float(backstep_evasion_reward_env), 0.0, 1.0)
	if sprint_strafe_clear_penalty_env.is_valid_float():
		_rl_sprint_strafe_clear_penalty = clamp(float(sprint_strafe_clear_penalty_env), 0.0, 1.0)
	if door_interact_bias_env.is_valid_float():
		_rl_door_interact_bias = clamp(float(door_interact_bias_env), 0.4, 3.0)
	if require_interactable_open_success_env != "":
		_rl_require_interactable_open_for_success = require_interactable_open_success_env.to_lower() in ["1", "true", "yes", "on"]
	if success_interactable_progress_env.is_valid_float():
		_rl_success_interactable_progress = clamp(float(success_interactable_progress_env), 0.1, 1.0)
	if bypass_success_penalty_scale_env.is_valid_float():
		_rl_bypass_success_penalty_scale = clamp(float(bypass_success_penalty_scale_env), 0.0, 2.0)
	if start_failure_grace_steps_env.is_valid_integer():
		_rl_start_failure_grace_steps = int(clamp(int(start_failure_grace_steps_env), 0, 180))
	if debug_short_done_env != "":
		_rl_debug_short_done = debug_short_done_env.to_lower() in ["1", "true", "yes", "on"]
	_configure_rl_shaping_profile(shaping_profile_env)
	_refresh_rl_sampling_nodes()
	print("[AnnaInterface] spawn=%s alt_enabled=%s alt_prob=%.2f alt_spawn=%s spawn_bounds=%s target_radius=[%.1f, %.1f] target_bounds=%s target_min_sep=%.2f spawn_samples=%d target_samples=%d zones[spawn=%d target=%d] points[spawn=%d target=%d] jump[ahead=%.2f,above_y=%.2f,above_d=%.2f,max_steer=%.2f,pen_scale=%.2f,hold=%d] wall[contact=%.3f stuck_scale=%.3f stuck_cap=%.3f stuck_fail=%d no_recovery=%.3f grace=%d fwd_press=%.3f recovery[frames=%d strafe=%.2f backoff=%.2f jump_period=%d early_hazard=%d early_front=%.2f side_bias=%.0f]] shaping[profile=%s clamp=%.2f timeout=%.2f progress=%.2f align=%.2f speed=%.2f penalty=%.2f orbit=%.2f wall=%.2f strafe_reward=%.2f strafe_penalty=%.2f action_change=%.2f] max_steps=%d legacy_fast=%s" % [
		_rl_spawn_pos, str(_rl_spawn_alt_enabled), _rl_spawn_alt_prob, _rl_spawn_alt_pos,
		("on" if _rl_spawn_bounds_enabled else "off"),
		_rl_target_radius_min, _rl_target_radius_max,
		("on" if _rl_target_bounds_enabled else "off"), _rl_target_min_separation, _rl_spawn_sample_tries, _rl_target_sample_tries,
		_rl_spawn_zone_nodes.size(), _rl_target_zone_nodes.size(), _rl_spawn_point_nodes.size(), _rl_target_point_nodes.size(),
		_rl_smart_jump_ahead_dist, _rl_smart_jump_target_above_y, _rl_smart_jump_target_above_dist, _rl_smart_jump_max_steer_angle, _rl_jump_penalty_scale, _rl_jump_hold_input_frames,
		_rl_wall_contact_penalty, _rl_stuck_extra_penalty_scale, _rl_stuck_extra_penalty_cap, _rl_stuck_wall_fail_frames, _rl_stuck_no_recovery_penalty, _rl_hazard_contact_grace_frames, _rl_hazard_forward_press_penalty, _rl_stuck_recovery_wall_frames, _rl_stuck_recovery_strafe, _rl_stuck_recovery_backoff, _rl_stuck_recovery_jump_period, _rl_early_wall_recovery_hazard_frames, _rl_early_wall_recovery_front_dist, _rl_recovery_strafe_side_bias,
		_rl_shaping_profile, _rl_shaping_reward_clamp, _rl_timeout_failure_scale, _rl_progress_reward_scale, _rl_alignment_reward_scale, _rl_speed_reward_scale, _rl_penalty_scale, _rl_orbit_penalty_scale, _rl_wall_penalty_scale, _rl_strafe_reward_scale, _rl_strafe_penalty_scale, _rl_action_change_penalty_scale,
		_rl_max_episode_steps, str(_rl_legacy_fast_mode)])
	print("[AnnaInterface] action_cfg backstep[action0=%s speed=%.2f evasion_reward=%.2f] sprint[jump=%s strafe=%s jump_strafe=%s] strafe_forward_assist=%.2f jump_strafe_forward_assist=%.2f strafe_commit_frames=%d recovery_side_clear_margin=%.2f sprint_strafe_clear_penalty=%.2f" % [
		str(_rl_action0_backstep_enabled), _rl_action0_backstep_speed, _rl_backstep_evasion_reward, str(_rl_sprint_on_jump_actions), str(_rl_sprint_on_strafe_actions), str(_rl_sprint_on_jump_strafe_actions), _rl_strafe_forward_assist, _rl_jump_strafe_forward_assist, _rl_strafe_commit_frames, _rl_recovery_side_clear_margin, _rl_sprint_strafe_clear_penalty
	])
	print("[AnnaInterface] look_cfg delta_x=%.2f min_correction=%.2f" % [_rl_look_delta_x, _rl_look_min_correction])
	print("[AnnaInterface] steering assisted=%s" % [str(_rl_assisted_steering)])
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

func _parse_float_tokens(raw: String) -> Array:
	var out := []
	var normalized = raw.strip_edges().replace(";", ",").replace(" ", ",")
	for token in normalized.split(",", false):
		var piece = token.strip_edges()
		if piece == "":
			continue
		if piece.is_valid_float():
			out.append(float(piece))
	return out

func _apply_rl_bounds_from_env(raw: String, for_spawn: bool) -> void:
	if raw.strip_edges() == "":
		return
	var values = _parse_float_tokens(raw)
	if values.size() != 4 and values.size() != 6:
		return
	var x_min = min(values[0], values[1])
	var x_max = max(values[0], values[1])
	var z_min = min(values[2], values[3])
	var z_max = max(values[2], values[3])
	var y_min = _rl_spawn_pos.y if for_spawn else _rl_target_fixed_y
	var y_max = y_min
	if values.size() == 6:
		y_min = min(values[4], values[5])
		y_max = max(values[4], values[5])
	var min_v = Vector3(x_min, y_min, z_min)
	var max_v = Vector3(x_max, y_max, z_max)
	if for_spawn:
		_rl_spawn_bounds_enabled = true
		_rl_spawn_bounds_min = min_v
		_rl_spawn_bounds_max = max_v
	else:
		_rl_target_bounds_enabled = true
		_rl_target_bounds_min = min_v
		_rl_target_bounds_max = max_v

func _read_env_scale(name: String, current: float, min_v: float, max_v: float) -> float:
	var raw = OS.get_environment(name)
	if raw.is_valid_float():
		return clamp(float(raw), min_v, max_v)
	return current

func _configure_rl_shaping_profile(raw_profile: String) -> void:
	var profile = raw_profile.strip_edges().to_lower()
	if profile == "":
		profile = RL_SHAPING_PROFILE_STABLE
	_rl_shaping_profile = profile
	_rl_timeout_failure_scale = RL_TIMEOUT_FAILURE_SCALE
	_rl_shaping_reward_clamp = RL_SHAPING_REWARD_CLAMP
	_rl_progress_reward_scale = 1.0
	_rl_alignment_reward_scale = 1.0
	_rl_speed_reward_scale = 1.0
	_rl_penalty_scale = 1.0
	_rl_orbit_penalty_scale = 1.0
	_rl_wall_penalty_scale = 1.0
	match profile:
		RL_SHAPING_PROFILE_STABLE:
			_rl_timeout_failure_scale = 0.24
			_rl_shaping_reward_clamp = 3.2
			_rl_progress_reward_scale = 1.18
			_rl_alignment_reward_scale = 1.16
			_rl_speed_reward_scale = 1.10
			_rl_penalty_scale = 0.78
			_rl_orbit_penalty_scale = 0.72
			_rl_wall_penalty_scale = 0.70
		RL_SHAPING_PROFILE_FAST:
			_rl_timeout_failure_scale = 0.30
			_rl_shaping_reward_clamp = 3.5
			_rl_progress_reward_scale = 1.24
			_rl_alignment_reward_scale = 1.10
			_rl_speed_reward_scale = 1.22
			_rl_penalty_scale = 0.86
			_rl_orbit_penalty_scale = 0.84
			_rl_wall_penalty_scale = 0.78
		_:
			_rl_shaping_profile = RL_SHAPING_PROFILE_BALANCED

	_rl_shaping_reward_clamp = _read_env_scale("ANNA_RL_SHAPING_REWARD_CLAMP", _rl_shaping_reward_clamp, 0.5, 12.0)
	_rl_timeout_failure_scale = _read_env_scale("ANNA_RL_TIMEOUT_FAILURE_SCALE", _rl_timeout_failure_scale, 0.0, 1.0)
	_rl_progress_reward_scale = _read_env_scale("ANNA_RL_PROGRESS_REWARD_SCALE", _rl_progress_reward_scale, 0.2, 3.0)
	_rl_alignment_reward_scale = _read_env_scale("ANNA_RL_ALIGNMENT_REWARD_SCALE", _rl_alignment_reward_scale, 0.2, 3.0)
	_rl_speed_reward_scale = _read_env_scale("ANNA_RL_SPEED_REWARD_SCALE", _rl_speed_reward_scale, 0.2, 3.0)
	_rl_penalty_scale = _read_env_scale("ANNA_RL_PENALTY_SCALE", _rl_penalty_scale, 0.2, 3.0)
	_rl_orbit_penalty_scale = _read_env_scale("ANNA_RL_ORBIT_PENALTY_SCALE", _rl_orbit_penalty_scale, 0.2, 3.0)
	_rl_wall_penalty_scale = _read_env_scale("ANNA_RL_WALL_PENALTY_SCALE", _rl_wall_penalty_scale, 0.2, 3.0)

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

func get_scene_hierarchy_resource(max_depth := MCP_SCENE_DEPTH_LIMIT, max_children := MCP_SCENE_CHILD_LIMIT) -> Dictionary:
	var tree = get_tree()
	if tree == null or tree.root == null:
		return {
			"resource": "odisea://scene/hierarchy",
			"available": false
		}
	var depth_limit = int(clamp(int(max_depth), 1, 12))
	var children_limit = int(clamp(int(max_children), 1, 128))
	return {
		"resource": "odisea://scene/hierarchy",
		"available": true,
		"depth_limit": depth_limit,
		"child_limit": children_limit,
		"tree": _build_scene_hierarchy_entry(tree.root, 0, depth_limit, children_limit)
	}

func get_simulation_telemetry_resource() -> Dictionary:
	var fps = float(Performance.get_monitor(Performance.TIME_FPS))
	var process_ms = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_ms = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var draw_calls = 0
	if Performance.get("RENDER_DRAW_CALLS") != null:
		draw_calls = int(Performance.get_monitor(Performance.RENDER_DRAW_CALLS))
	var node_count = 0
	if Performance.get("OBJECT_NODE_COUNT") != null:
		node_count = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var player = _get_player()
	var player_data = {
		"available": false
	}
	if is_instance_valid(player) and player is Spatial:
		var velocity = Vector3.ZERO
		if "velocity" in player:
			velocity = player.velocity
		player_data = {
			"available": true,
			"name": String(player.name),
			"path": String(player.get_path()),
			"position": _to_vector3_array((player as Spatial).global_transform.origin),
			"active_velocity": _to_vector3_array(velocity),
			"speed": velocity.length()
		}
	return {
		"resource": "odisea://simulation/telemetry",
		"fps": fps,
		"process_ms": process_ms,
		"physics_ms": physics_ms,
		"draw_calls": draw_calls,
		"node_count": node_count,
		"physics_frame": Engine.get_physics_frames(),
		"elias": player_data,
		"oys": _read_oys_runtime_info()
	}

func get_olcs_logic_state_resource() -> Dictionary:
	var snapshot = _get_olcs_observation()
	var grouped = _extract_logic_state_groups(snapshot)
	return {
		"resource": "odisea://olcs/logic-state",
		"available": bool(snapshot.get("available", false)),
		"levers": grouped.get("levers", []),
		"doors": grouped.get("doors", []),
		"gates": grouped.get("gates", []),
		"node_count": int(snapshot.get("nodes", []).size())
	}

func inspect_node(node_path: String) -> Dictionary:
	var node = _find_node_from_path(node_path)
	if node == null:
		return {
			"ok": false,
			"error": "node_not_found",
			"node_path": node_path
		}

	var out = {
		"ok": true,
		"name": String(node.name),
		"type": String(node.get_class()),
		"path": String(node.get_path()),
		"export_vars": _extract_export_vars(node)
	}
	if node is Spatial:
		out["position"] = _to_vector3_array((node as Spatial).global_transform.origin)
	if "velocity" in node:
		out["velocity"] = _to_json_compatible(node.get("velocity"))
	return out

func execute_oys(script_command: String) -> Dictionary:
	if not allow_oys_integration:
		return {
			"ok": false,
			"error": "oys_integration_disabled"
		}
	var cmd = script_command.strip_edges()
	if cmd == "":
		return {
			"ok": false,
			"error": "empty_command"
		}
	var console = _resolve_console()
	if console == null or not console.has_method("enqueue_command"):
		return {
			"ok": false,
			"error": "oys_console_not_found"
		}
	return _enqueue_inline_oys(console, cmd)

func _enqueue_inline_oys(console: Node, cmd: String) -> Dictionary:
	var dir = Directory.new()
	if not dir.dir_exists(MCP_INLINE_OYS_DIR):
		var mk_err = dir.make_dir_recursive(MCP_INLINE_OYS_DIR)
		if mk_err != OK:
			return {
				"ok": false,
				"error": "inline_oys_mkdir_failed",
				"code": mk_err
			}

	var frame_id = int(Engine.get_physics_frames())
	var ticks = int(OS.get_ticks_msec())
	var rel_path = "%s/mcp_inline_%06d_%06d.oys" % [MCP_INLINE_OYS_DIR, frame_id, ticks % 1000000]
	var file = File.new()
	var open_err = file.open(rel_path, File.WRITE)
	if open_err != OK:
		return {
			"ok": false,
			"error": "inline_oys_write_failed",
			"code": open_err,
			"path": rel_path
		}
	file.store_line("# generated by anna execute_oys")
	file.store_line(cmd)
	file.close()

	var run_cmd = "run %s" % rel_path
	console.enqueue_command(run_cmd)
	return {
		"ok": true,
		"queued_command": run_cmd,
		"source_command": cmd,
		"script_path": rel_path
	}

func capture_vision(options := {}) -> Dictionary:
	var opts = options if typeof(options) == TYPE_DICTIONARY else {}
	var include_base64 = bool(opts.get("include_base64", false))
	var label = str(opts.get("label", "mcp")).strip_edges()
	if label == "":
		label = "mcp"
	label = label.replace("/", "_").replace("\\", "_").replace(" ", "_")

	if not is_inside_tree() or get_tree().root == null:
		return {"ok": false, "error": "tree_unavailable"}

	var dir = Directory.new()
	if not dir.dir_exists(MCP_SCREENSHOT_DIR):
		var dir_err = dir.make_dir_recursive(MCP_SCREENSHOT_DIR)
		if dir_err != OK:
			return {"ok": false, "error": "mkdir_failed", "code": dir_err}

	var scene_name = "scene"
	if is_instance_valid(get_tree().current_scene):
		scene_name = String(get_tree().current_scene.name).to_lower()
	var frame_id = int(Engine.get_physics_frames())
	var rel_path = "%s/%s_%s_%06d.png" % [MCP_SCREENSHOT_DIR, scene_name, label, frame_id]

	var tex = get_tree().root.get_texture()
	if tex == null:
		return {"ok": false, "error": "viewport_texture_unavailable"}
	var img = tex.get_data()
	if img == null:
		return {"ok": false, "error": "viewport_image_unavailable"}
	img.flip_y()
	var err = img.save_png(rel_path)
	if err != OK:
		return {"ok": false, "error": "save_png_failed", "code": err}

	var result = {
		"ok": true,
		"path": rel_path,
		"absolute_path": ProjectSettings.globalize_path(rel_path)
	}

	if include_base64:
		var f = File.new()
		if f.open(rel_path, File.READ) == OK:
			var bytes = f.get_buffer(f.get_len())
			f.close()
			result["base64"] = Marshalls.raw_to_base64(bytes)
		else:
			result["base64_error"] = "read_failed"

	return result

func query_codex_docs(topic: String, max_matches := 20) -> Dictionary:
	var clean_topic = topic.strip_edges()
	if clean_topic == "":
		return {
			"ok": false,
			"topic": topic,
			"matches": []
		}

	var lower_topic = clean_topic.to_lower()
	var max_hits = max(1, int(max_matches))
	var tokens := []
	for part in lower_topic.split(" ", false):
		var token = part.strip_edges()
		if token.length() >= 2:
			tokens.append(token)

	var matches := []
	var scanned_files := 0
	for path in MCP_DOC_SEARCH_PATHS:
		var file = File.new()
		if file.open(path, File.READ) != OK:
			continue
		scanned_files += 1
		var line_number := 0
		while not file.eof_reached() and matches.size() < max_hits:
			var line = file.get_line()
			line_number += 1
			var lower_line = line.to_lower()
			var matched = lower_line.find(lower_topic) != -1
			if not matched and tokens.size() > 1:
				matched = true
				for token in tokens:
					if lower_line.find(token) == -1:
						matched = false
						break
			if not matched:
				continue
			var snippet = line.strip_edges()
			if snippet.length() > 240:
				snippet = snippet.substr(0, 240)
			matches.append({
				"path": path,
				"line": line_number,
				"text": snippet
			})
		file.close()
		if matches.size() >= max_hits:
			break

	return {
		"ok": matches.size() > 0,
		"topic": clean_topic,
		"scanned_files": scanned_files,
		"matches": matches
	}

# --- RL API ---

func get_rl_observation() -> Dictionary:
	var player = _get_player()
	var obs_vector = []
	var reward = 0.0
	var done = false
	var done_reason = "running"
	var dist_to_target = 0.0
	var angle_to_target = 0.0
	var to_target = Vector3.ZERO
	var forward = Vector3.ZERO
	var facing_basis = Basis.IDENTITY
	var route_subgoal_active = false

	if not is_instance_valid(player) or not player is Spatial:
		# Fallback/Fail state
		for i in range(12): obs_vector.append(0.0)
		return {"obs": obs_vector, "reward": 0.0, "done": true, "done_reason": "invalid_player"}
	if _rl_legacy_fast_mode:
		return _get_rl_observation_legacy_fast(player as Spatial)

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
	var front_height_profile = _get_front_height_profile(player as Spatial)
	var jumpable_front = bool(front_height_profile.get("jumpable", false))
	var jumpable_front_score = float(front_height_profile.get("score", 0.0))

	# Target Info
	var target = _ensure_rl_target()
	var route_target: Spatial = null
	if target:
		route_target = _get_route_interactable(player as Spatial, target, front_ray_dist) as Spatial
		var aim_target: Spatial = target
		if is_instance_valid(route_target):
			aim_target = route_target
			route_subgoal_active = true
		dist_to_target = player.global_transform.origin.distance_to(target.global_transform.origin)

		# Angle
		to_target = (aim_target.global_transform.origin - player.global_transform.origin)
		to_target.y = 0
		to_target = to_target.normalized()
		facing_basis = _get_control_basis(player as Spatial)
		forward = - facing_basis.z
		forward.y = 0
		forward = forward.normalized()

		var angle = forward.angle_to(to_target) # Returns 0 to PI
		# Determine sign
		if forward.cross(to_target).y < 0:
			angle = - angle

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
	var control_basis = _get_control_basis(player as Spatial)
	var control_forward = - control_basis.z
	control_forward.y = 0.0
	if control_forward.length_squared() < 0.0001:
		control_forward = - player.global_transform.basis.z
		control_forward.y = 0.0
	if control_forward.length_squared() > 0.0001:
		control_forward = control_forward.normalized()
	var control_right = control_basis.x
	control_right.y = 0.0
	if control_right.length_squared() > 0.0001:
		control_right = control_right.normalized()

	# --- REWARD CALCULATION ---
	var terminal_reward = 0.0
	var prev_dist_to_target = _last_dist_to_target

	# 1. Time Penalty
	_episode_step_count += 1
	reward += _rl_time_penalty * _rl_penalty_scale

	# 1b. Reward speed (prefer fast locomotion over stationary/jump spam)
	var horizontal_speed = Vector2(local_vel.x, local_vel.z).length()
	var strafe_speed = abs(local_vel.x)
	reward += horizontal_speed * RL_SPEED_REWARD_SCALE * _rl_speed_reward_scale
	reward += min(horizontal_speed / RL_SPRINT_TARGET_SPEED, 1.0) * RL_SPEED_TARGET_REWARD_SCALE * _rl_speed_reward_scale
	if _last_action_idx == 0 and horizontal_speed < 0.2 and dist_to_target > (RL_SUCCESS_DIST * 1.5):
		var steer_only_context_clear = front_ray_dist > (RL_OBSTACLE_AHEAD_DIST * 1.1) and _hazard_contact_frames <= 1 and _wall_stuck_frames <= 1
		if steer_only_context_clear:
			var steer_only_penalty = RL_STEER_ONLY_IDLE_PENALTY
			if abs(angle_to_target) > 0.22 and abs(_last_action_look_x) > 0.04:
				steer_only_penalty *= 0.4 # Allow short camera correction bursts, but not full episodes of no movement.
			reward -= steer_only_penalty * _rl_penalty_scale
	if _last_action_sprint and horizontal_speed > 0.1:
		reward += horizontal_speed * RL_SPRINT_REWARD_SCALE * _rl_speed_reward_scale
	if _last_action_jump:
		reward -= RL_JUMP_ACTION_PENALTY * _rl_penalty_scale * _rl_jump_penalty_scale
		if _jump_streak > 1:
			reward -= float(_jump_streak - 1) * RL_JUMP_REPEAT_PENALTY * _rl_penalty_scale * _rl_jump_penalty_scale
		if not on_floor_now:
			reward -= RL_JUMP_REPEAT_PENALTY * _rl_penalty_scale * _rl_jump_penalty_scale
		if jumpable_front and vel.y > 0.05:
			reward += (RL_OBSTACLE_JUMP_BONUS + (RL_JUMPABLE_OBSTACLE_BONUS * jumpable_front_score)) * _rl_progress_reward_scale
		elif front_ray_dist < RL_OBSTACLE_AHEAD_DIST and vel.y > 0.05:
			reward += RL_OBSTACLE_JUMP_BONUS * _rl_progress_reward_scale
		else:
			reward -= RL_BAD_JUMP_PENALTY * _rl_penalty_scale * _rl_jump_penalty_scale
	elif on_floor_now and jumpable_front and _last_move_cmd.y < -0.25 and not _last_action_jump:
		var jump_ignore_scale = 1.0
		if abs(_last_move_cmd.x) > 0.1:
			# Strafing while pushing into a jumpable front obstacle should still encourage jump decisions.
			jump_ignore_scale = 0.7
		reward -= RL_JUMPABLE_OBSTACLE_IGNORE_PENALTY * jump_ignore_scale * _rl_penalty_scale
	elif on_floor_now and front_ray_dist < RL_OBSTACLE_AHEAD_DIST and abs(_last_move_cmd.x) < 0.45:
		reward -= RL_OBSTACLE_NO_EVASION_PENALTY * _rl_penalty_scale
	var interact_candidate_now = _get_front_interactable(player as Spatial)
	if is_instance_valid(interact_candidate_now):
		var door_interact_bias = max(0.4, _rl_door_interact_bias)
		var door_focus_range = RL_INTERACT_AUTO_RANGE * (1.0 + max(0.0, door_interact_bias - 1.0) * 0.25)
		var interact_dist = player.global_transform.origin.distance_to((interact_candidate_now as Spatial).global_transform.origin) if interact_candidate_now is Spatial else RL_INTERACT_RANGE
		var blocked_by_interactable = front_ray_dist < RL_INTERACT_AUTO_FRONT_BLOCK_DIST and interact_dist <= door_focus_range
		if blocked_by_interactable and _last_move_cmd.y < -0.35 and not _last_action_interact:
			reward -= RL_MISSED_INTERACT_PENALTY * _rl_penalty_scale
		var candidate_is_open = false
		var candidate_progress = 0.0
		if "is_active" in interact_candidate_now:
			candidate_is_open = bool(interact_candidate_now.is_active)
		if "target_progress" in interact_candidate_now:
			candidate_progress = float(interact_candidate_now.target_progress)
		var interact_closed = (not candidate_is_open) and candidate_progress < 0.9
		if interact_closed:
			if interact_dist <= door_focus_range:
				if _last_route_interact_dist >= 0.0:
					reward += (_last_route_interact_dist - interact_dist) * RL_INTERACT_APPROACH_REWARD_SCALE * _rl_progress_reward_scale
				var to_interact = (interact_candidate_now.global_transform.origin - player.global_transform.origin)
				to_interact.y = 0.0
				if forward.length_squared() > 0.001 and to_interact.length_squared() > 0.001:
					reward += max(0.0, forward.dot(to_interact.normalized())) * RL_INTERACT_ROUTE_ALIGN_REWARD_SCALE * _rl_alignment_reward_scale
				if _last_move_cmd.y < -0.45 and not _last_action_interact:
					reward -= RL_INTERACT_FORWARD_IGNORE_PENALTY * _rl_penalty_scale
				if door_interact_bias > 1.01 and _last_action_jump and _last_move_cmd.y < -0.25:
					reward -= RL_MISSED_INTERACT_PENALTY * _rl_penalty_scale * door_interact_bias
				if door_interact_bias > 1.01 and _last_action_interact:
					reward += RL_INTERACT_CONTEXT_REWARD * 0.4 * _rl_alignment_reward_scale * door_interact_bias
			if _last_route_interact_progress >= 0.0:
				reward += max(0.0, candidate_progress - _last_route_interact_progress) * RL_INTERACT_OPEN_PROGRESS_REWARD_SCALE * _rl_progress_reward_scale
		else:
			var open_passage_focus = interact_dist <= (door_focus_range * 1.15) and abs(angle_to_target) < 0.3
			if open_passage_focus:
				if _last_move_cmd.y < -0.3:
					reward += RL_OPEN_DOOR_PASSAGE_FORWARD_BONUS * _rl_progress_reward_scale
				elif _last_move_cmd.y > 0.1:
					reward -= RL_POST_DOOR_BACKSTEP_PENALTY * _rl_penalty_scale
				if abs(_last_move_cmd.x) > 0.1 and front_ray_dist > (RL_INTERACT_AUTO_FRONT_BLOCK_DIST * 0.9):
					reward -= strafe_speed * RL_OPEN_DOOR_PASSAGE_STRAFE_PENALTY_SCALE * _rl_penalty_scale * _rl_strafe_penalty_scale
				if prev_dist_to_target >= 0.0 and (dist_to_target - prev_dist_to_target) > 0.01:
					reward -= RL_POST_DOOR_MOVE_AWAY_PENALTY_SCALE * _rl_penalty_scale
			_last_route_interact_dist = interact_dist
			_last_route_interact_progress = candidate_progress
	else:
		_last_route_interact_dist = -1.0
		_last_route_interact_progress = -1.0
	if _last_action_interact:
		if is_instance_valid(interact_candidate_now):
			reward += RL_INTERACT_CONTEXT_REWARD * _rl_alignment_reward_scale
			if "target_progress" in interact_candidate_now:
				reward += float(interact_candidate_now.target_progress) * RL_INTERACT_OPEN_PROGRESS_REWARD_SCALE * _rl_progress_reward_scale
			if _interact_streak > 1:
				reward -= float(_interact_streak - 1) * RL_INTERACT_REPEAT_PENALTY * _rl_penalty_scale
		else:
			reward -= RL_INTERACT_SPAM_PENALTY * _rl_penalty_scale
	if _rl_episode_require_interactable_open_for_success and not _rl_episode_interactable_opened:
		_rl_episode_interactable_opened = _any_interactable_opened_for_success()
	if not on_floor_now:
		reward -= RL_AIRBORNE_PENALTY * _rl_penalty_scale
	var height_gain = max(0.0, player.global_transform.origin.y - _episode_start_height)
	reward += min(height_gain, RL_HEIGHT_REWARD_CAP) * RL_HEIGHT_REWARD_SCALE * _rl_progress_reward_scale
	reward -= _last_action_change_cost * _rl_penalty_scale * _rl_action_change_penalty_scale
	var local_hvel = Vector2(local_vel.x, local_vel.z)
	if _has_last_local_hvel:
		reward -= (local_hvel - _last_local_hvel).length() * RL_VELOCITY_JERK_PENALTY_SCALE * _rl_penalty_scale
	_last_local_hvel = local_hvel
	_has_last_local_hvel = true

	# 2. Progress
	if prev_dist_to_target >= 0.0:
		var diff = prev_dist_to_target - dist_to_target
		if route_subgoal_active:
			reward += max(0.0, diff) * RL_PROGRESS_SCALE * RL_ROUTE_PROGRESS_WEIGHT * _rl_progress_reward_scale
		else:
			reward += diff * RL_PROGRESS_SCALE * _rl_progress_reward_scale

	# 2b. Target shaping (alignment + approach speed + proximity)
	if target:
		if route_subgoal_active:
			reward += RL_ROUTE_GOAL_SWITCH_BONUS * _rl_progress_reward_scale
		if forward.length_squared() > 0.001 and to_target.length_squared() > 0.001:
			var align = clamp(forward.dot(to_target), -1.0, 1.0)
			reward += align * RL_ALIGNMENT_REWARD_SCALE * _rl_alignment_reward_scale

			var approach_speed = vel.dot(to_target)
			reward += approach_speed * RL_APPROACH_SPEED_REWARD_SCALE * _rl_progress_reward_scale
			var tangential_speed = (vel - to_target * approach_speed).length()
			reward -= tangential_speed * RL_TANGENTIAL_SPEED_PENALTY_SCALE * _rl_orbit_penalty_scale * _rl_penalty_scale
			if dist_to_target < RL_NEAR_TARGET_RADIUS:
				var near_ratio = 1.0 - clamp(dist_to_target / RL_NEAR_TARGET_RADIUS, 0.0, 1.0)
				reward -= tangential_speed * near_ratio * RL_NEAR_TARGET_ORBIT_PENALTY_SCALE * _rl_orbit_penalty_scale * _rl_penalty_scale
				if approach_speed < 0.0:
					reward += approach_speed * near_ratio * RL_NEAR_TARGET_MOVING_AWAY_PENALTY_SCALE * _rl_orbit_penalty_scale * _rl_penalty_scale
				var orbit_ratio = tangential_speed / max(0.2, abs(approach_speed) + 0.2)
				if orbit_ratio > 1.0:
					reward -= (orbit_ratio - 1.0) * near_ratio * RL_ORBIT_RATIO_PENALTY_SCALE * _rl_orbit_penalty_scale * _rl_penalty_scale

			var proximity_ratio = clamp((RL_PROXIMITY_REFERENCE_DIST - dist_to_target) / RL_PROXIMITY_REFERENCE_DIST, 0.0, 1.0)
			reward += proximity_ratio * RL_PROXIMITY_REWARD_SCALE * _rl_progress_reward_scale
			if dist_to_target < RL_NEAR_TARGET_BONUS_DIST:
				var near_target_ratio = 1.0 - clamp(dist_to_target / RL_NEAR_TARGET_BONUS_DIST, 0.0, 1.0)
				reward += near_target_ratio * RL_NEAR_TARGET_BONUS_SCALE * _rl_progress_reward_scale

		var abs_angle = abs(angle_to_target)
		reward -= abs_angle * RL_ANGLE_ABS_PENALTY_SCALE * _rl_penalty_scale
		var alignment_focus = 1.0 - abs_angle
		reward += alignment_focus * alignment_focus * RL_AIM_STABILITY_BONUS_SCALE * _rl_alignment_reward_scale
		if _last_abs_angle_to_target >= 0.0:
			reward += (_last_abs_angle_to_target - abs_angle) * RL_ANGLE_PROGRESS_SCALE * _rl_alignment_reward_scale
			if abs(_last_action_look_x) > 0.05 and abs_angle < _last_abs_angle_to_target:
				reward += (_last_abs_angle_to_target - abs_angle) * RL_STEER_CORRECTION_BONUS_SCALE * _rl_alignment_reward_scale
		_last_abs_angle_to_target = abs_angle

		if abs_angle > 0.12 and abs(_last_action_look_x) > 0.01:
			reward += RL_LOOK_USAGE_REWARD_SCALE * _rl_alignment_reward_scale
		if abs_angle > 0.16 and abs(_last_action_look_x) > 0.05:
			reward += abs_angle * RL_STEER_WHEN_MISALIGNED_REWARD_SCALE * _rl_alignment_reward_scale
		if abs_angle < 0.08 and abs(_last_action_look_x) > 0.01:
			reward -= RL_LOOK_WHEN_ALIGNED_PENALTY * _rl_penalty_scale
		if abs(_last_move_cmd.x) > 0.1 and abs_angle > 0.16:
			reward += strafe_speed * RL_STRAFE_WHEN_MISALIGNED_REWARD_SCALE * _rl_alignment_reward_scale * _rl_strafe_reward_scale
		if abs(_last_move_cmd.x) > 0.1 and front_ray_dist < RL_OBSTACLE_AHEAD_DIST:
			reward += strafe_speed * RL_STRAFE_OBSTACLE_REWARD_SCALE * _rl_progress_reward_scale * _rl_strafe_reward_scale
		if abs(_last_move_cmd.x) > 0.1 and front_ray_dist < (RL_OBSTACLE_AHEAD_DIST * 1.25):
			var preferred_strafe_side = 0.0
			var side_margin = max(0.12, _rl_recovery_side_clear_margin * 0.7)
			var lateral_clearance = _get_lateral_clearance(player as Spatial)
			var left_clear = float(lateral_clearance.get("left", SENSOR_RANGE))
			var right_clear = float(lateral_clearance.get("right", SENSOR_RANGE))
			var clear_delta = right_clear - left_clear
			if abs(clear_delta) > side_margin:
				preferred_strafe_side = 1.0 if clear_delta > 0.0 else -1.0
			elif abs(angle_to_target) > 0.16:
				preferred_strafe_side = - sign(angle_to_target)
			if abs(preferred_strafe_side) > 0.1:
				if sign(_last_move_cmd.x) == preferred_strafe_side:
					reward += strafe_speed * RL_STRAFE_SIDE_CHOICE_REWARD_SCALE * _rl_progress_reward_scale * _rl_strafe_reward_scale
				else:
					var wrong_side_scale = RL_STRAFE_SIDE_WRONG_PENALTY_SCALE
					if route_subgoal_active and not _rl_episode_interactable_opened:
						wrong_side_scale *= 1.35
					reward -= strafe_speed * wrong_side_scale * _rl_penalty_scale * _rl_strafe_penalty_scale
		if abs(_last_move_cmd.x) > 0.1 and abs_angle < 0.08 and front_ray_dist > (RL_OBSTACLE_AHEAD_DIST * 1.2):
			reward -= RL_STRAFE_IDLE_PENALTY * _rl_penalty_scale * _rl_strafe_penalty_scale
		if route_subgoal_active and (not _rl_episode_interactable_opened) and abs(_last_move_cmd.x) > 0.1 and abs_angle < 0.22 and front_ray_dist > (RL_INTERACT_AUTO_FRONT_BLOCK_DIST * 1.15):
			# Prevent overcommitting to lateral drift when the door route sub-goal is active.
			reward -= (RL_STRAFE_IDLE_PENALTY * 1.8) * _rl_penalty_scale * _rl_strafe_penalty_scale
		if _last_action_sprint and abs(_last_move_cmd.x) > 0.1 and abs_angle < 0.12 and front_ray_dist > (RL_OBSTACLE_AHEAD_DIST * 1.35):
			reward -= _rl_sprint_strafe_clear_penalty * _rl_penalty_scale * _rl_strafe_penalty_scale
		if abs(_last_move_cmd.x) > 0.1 and dist_to_target < RL_NEAR_TARGET_RADIUS and abs_angle < 0.25:
			var near_strafe_ratio = 1.0 - clamp(dist_to_target / RL_NEAR_TARGET_RADIUS, 0.0, 1.0)
			reward -= strafe_speed * near_strafe_ratio * RL_NEAR_TARGET_STRAFE_PENALTY_SCALE * _rl_orbit_penalty_scale * _rl_penalty_scale * _rl_strafe_penalty_scale
		if horizontal_speed > 0.2 and abs_angle > 0.2:
			reward -= horizontal_speed * abs_angle * RL_FORWARD_MISALIGN_PENALTY_SCALE * _rl_penalty_scale

		var forward_speed = max(0.0, vel.dot(to_target))
		var signed_approach_speed = vel.dot(to_target)
		var moving_away_speed = max(0.0, -signed_approach_speed)
		if abs_angle < 0.2 and moving_away_speed > 0.1:
			var clear_escape_path = front_ray_dist > (RL_OBSTACLE_AHEAD_DIST * 1.2)
			var hazard_context = (_hazard_contact_frames >= _rl_hazard_contact_grace_frames) or (_wall_stuck_frames > 0)
			if clear_escape_path and not hazard_context:
				reward -= moving_away_speed * RL_MOVING_AWAY_WHEN_ALIGNED_PENALTY_SCALE * _rl_penalty_scale
				if _last_move_cmd.y > 0.2:
					reward -= RL_BACKSTEP_WHEN_ALIGNED_CLEAR_PENALTY * _rl_penalty_scale
		var sprint_context = on_floor_now and abs_angle < 0.16 and front_ray_dist > (RL_OBSTACLE_AHEAD_DIST * 1.2) and dist_to_target > (RL_SUCCESS_DIST * 1.5)
		if sprint_context:
			if _last_action_sprint and forward_speed > 0.8:
				reward += RL_SPRINT_ACTION_BONUS * _rl_speed_reward_scale
			elif _last_move_cmd.y < -0.7 and forward_speed > 0.2:
				reward -= RL_NO_SPRINT_WHEN_ALIGNED_PENALTY * _rl_penalty_scale
			var speed_gap = max(0.0, RL_SPRINT_TARGET_SPEED - forward_speed)
			reward -= speed_gap * RL_LOW_SPEED_WHEN_ALIGNED_PENALTY_SCALE * _rl_penalty_scale

		if abs_angle < 0.2:
			reward += forward_speed * RL_ALIGNED_SPEED_REWARD_SCALE * _rl_speed_reward_scale
			_misaligned_run_streak = 0
		elif forward_speed > 0.2:
			reward -= forward_speed * abs_angle * RL_UNALIGNED_SPEED_PENALTY_SCALE * _rl_penalty_scale
			if abs(_last_action_look_x) < 0.01:
				_misaligned_run_streak += 1
				reward -= min(float(_misaligned_run_streak) * RL_NO_CORRECTION_PENALTY, RL_NO_CORRECTION_PENALTY_CAP) * _rl_penalty_scale
			else:
				_misaligned_run_streak = 0
		else:
			_misaligned_run_streak = 0

		if on_floor_now and abs_angle < 0.2:
			var aligned_forward_speed = forward_speed
			reward += aligned_forward_speed * RL_COMMIT_FORWARD_REWARD_SCALE * _rl_speed_reward_scale
		if dist_to_target > 4.0 and horizontal_speed < 0.2:
			reward -= RL_STALL_PENALTY * _rl_penalty_scale
		if (not route_subgoal_active) and prev_dist_to_target >= 0.0 and (dist_to_target - prev_dist_to_target) > 0.02 and forward_speed > 0.15:
			reward -= 0.08 * _rl_penalty_scale # Moving in a way that increases distance should be corrected quickly.

		# Anti-collapse: repeating same action while neither distance nor angle improves.
		if _same_action_streak > 6 and prev_dist_to_target >= 0.0 and _has_last_angle_to_target:
			var dist_improved = (prev_dist_to_target - dist_to_target) > RL_BAD_STREAK_DIST_EPS
			var angle_improved = (abs(_last_angle_to_target) - abs_angle) > RL_BAD_STREAK_ANGLE_EPS
			if not dist_improved and not angle_improved:
				reward -= float(_same_action_streak - 6) * RL_SAME_ACTION_STREAK_PENALTY * _rl_penalty_scale
			_last_angle_to_target = angle_to_target
			_has_last_angle_to_target = true

	# 3. Success
	var reached_target := false
	if target:
		if dist_to_target < RL_SUCCESS_DIST:
			reached_target = true
		elif target is Area:
			# Area overlap can remain stale for 1-2 frames after reset teleports.
			# Only trust overlap when we are physically near the target.
			var overlap_dist_guard = max(RL_SUCCESS_DIST * 2.0, RL_AREA_SUCCESS_MAX_DIST)
			if dist_to_target <= overlap_dist_guard and target.overlaps_body(player):
				reached_target = true
	if reached_target:
		if _rl_episode_require_interactable_open_for_success and not _rl_episode_interactable_opened:
			reward -= RL_MISSED_INTERACT_PENALTY * _rl_penalty_scale * max(1.0, _rl_door_interact_bias)
			terminal_reward += RL_REWARD_FAILURE * _rl_bypass_success_penalty_scale
			done = true
			done_reason = "bypass_interactable"
		else:
			terminal_reward += RL_REWARD_SUCCESS
			done = true
			done_reason = "success"

	# 4. Failure (KillZone / Fall / Prolonged hazard contact)
	if not done and _episode_step_count >= _rl_max_episode_steps:
		terminal_reward += RL_REWARD_FAILURE * _rl_timeout_failure_scale
		done = true
		done_reason = "timeout"

	var in_start_failure_grace = _episode_step_count <= _rl_start_failure_grace_steps
	if not done and not in_start_failure_grace and _killzone_triggered:
		terminal_reward += RL_REWARD_FAILURE
		done = true
		done_reason = "killzone"

	if not done and not in_start_failure_grace and player.global_transform.origin.y < (_episode_start_height - RL_FALL_DISTANCE):
		terminal_reward += RL_REWARD_FAILURE
		done = true
		done_reason = "fall"

	if not done:
		var hazard_contact := false
		if front_ray_dist < RL_COLLISION_PENALTY_THRESHOLD:
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
					var normal_h = Vector3(col.normal.x, 0.0, col.normal.z)
					var frontal_block := false
					var pressing_surface := false
					if normal_h.length_squared() > 0.0001:
						normal_h = normal_h.normalized()
						if control_forward.length_squared() > 0.0001:
							frontal_block = control_forward.dot(normal_h) < -0.25
						var desired_world = (control_right * _last_move_cmd.x) + (control_forward * (-_last_move_cmd.y))
						desired_world.y = 0.0
						if desired_world.length_squared() > 0.01:
							pressing_surface = desired_world.normalized().dot(normal_h) < -0.2
					if frontal_block or pressing_surface:
						hazard_contact = true
						break

			if hazard_contact:
				_hazard_contact_frames += 1
				reward -= _rl_wall_contact_penalty * _rl_wall_penalty_scale * _rl_penalty_scale
				var trying_evasion_now := abs(_last_move_cmd.x) > 0.2 or _last_move_cmd.y > 0.2 or _last_action_jump
				if trying_evasion_now:
					reward += RL_HAZARD_EVASION_REWARD * _rl_progress_reward_scale
					if _last_move_cmd.y > 0.2:
						reward += _rl_backstep_evasion_reward * _rl_progress_reward_scale
				elif _last_move_cmd.y < -0.25:
					reward -= _rl_hazard_forward_press_penalty * _rl_wall_penalty_scale * _rl_penalty_scale
			if _last_front_ray_dist >= 0.0:
				var clear_delta = front_ray_dist - _last_front_ray_dist
				if clear_delta > 0.0:
					reward += clear_delta * RL_WALL_ESCAPE_PROGRESS_REWARD_SCALE * _rl_wall_penalty_scale
				else:
					reward += clear_delta * RL_WALL_ESCAPE_REGRESS_PENALTY_SCALE * _rl_wall_penalty_scale
			if abs(_last_move_cmd.x) < 0.1 and not _last_action_jump:
				reward -= RL_OBSTACLE_NO_EVASION_PENALTY * _rl_penalty_scale
		else:
			_hazard_contact_frames = 0
			_wall_stuck_frames = 0
			_rl_recovery_strafe_side = 0.0
		_last_front_ray_dist = front_ray_dist

		if hazard_contact and _hazard_contact_frames >= _rl_hazard_contact_grace_frames:
			var progress_speed = 0.0
			if target and to_target.length_squared() > 0.001:
				progress_speed = vel.dot(to_target)
			if horizontal_speed < RL_STUCK_MIN_HSPEED and abs(progress_speed) < RL_STUCK_MIN_PROGRESS_SPEED:
				_wall_stuck_frames += 1
			else:
				_wall_stuck_frames = 0

		if _wall_stuck_frames > 0:
			reward -= min(_rl_stuck_extra_penalty_cap, float(_wall_stuck_frames) * _rl_stuck_extra_penalty_scale) * _rl_wall_penalty_scale * _rl_penalty_scale
			if _wall_stuck_frames >= RL_STUCK_RECOVERY_WALL_FRAMES:
				var trying_recovery := _last_move_cmd.y > 0.2 or abs(_last_move_cmd.x) > 0.2 or _last_action_jump
				if trying_recovery:
					reward += RL_STUCK_RECOVERY_REWARD * _rl_progress_reward_scale
				else:
					reward -= _rl_stuck_no_recovery_penalty * _rl_wall_penalty_scale * _rl_penalty_scale

			if _wall_stuck_frames >= _rl_stuck_wall_fail_frames and not in_start_failure_grace:
				terminal_reward += RL_REWARD_FAILURE
				done = true
				done_reason = "wall_stuck"

	# Keep distance bookkeeping at the end so intermediate checks use previous-step value.
	_last_dist_to_target = dist_to_target
	var shaping_reward = clamp(reward, -_rl_shaping_reward_clamp, _rl_shaping_reward_clamp)
	var final_reward = shaping_reward + terminal_reward
	if done and _rl_debug_short_done and _episode_step_count <= 5:
		print("[AnnaInterface][short_done] step=%d reason=%s dist=%.3f front=%.3f kill=%s opened=%s act=%d move=(%.2f,%.2f)" % [
			_episode_step_count, done_reason, dist_to_target, front_ray_dist, str(_killzone_triggered), str(_rl_episode_interactable_opened), _last_action_idx, _last_move_cmd.x, _last_move_cmd.y
		])
	return {
		"obs": obs_vector,
		"reward": final_reward,
		"done": done,
		"done_reason": done_reason
	}

func reset_simulation() -> void:
	var player = _get_player()
	_reset_interactables_for_episode()
	_rl_max_episode_steps = _rl_base_max_episode_steps
	_call_rl_scene_before_reset_hook()
	_refresh_rl_sampling_nodes()
	var target = _ensure_rl_target()
	var spawn_origin := _sample_rl_spawn_position(player)
	var target_origin := _sample_rl_target_position(spawn_origin, player, target)
	var has_yaw_override := false
	var yaw_override := 0.0
	var episode_override = _get_rl_scene_episode_override()
	_rl_last_episode_override = {}
	var episode_requires_interactable_open = _rl_require_interactable_open_for_success
	if typeof(episode_override) == TYPE_DICTIONARY:
		_rl_last_episode_override = episode_override.duplicate(true)
		var spawn_pick = _variant_to_vector3(episode_override.get("spawn", null))
		if bool(spawn_pick.get("ok", false)):
			spawn_origin = spawn_pick.get("value", spawn_origin)
		var target_pick = _variant_to_vector3(episode_override.get("target", null))
		if bool(target_pick.get("ok", false)):
			target_origin = target_pick.get("value", target_origin)
		var yaw_value = episode_override.get("yaw", null)
		if yaw_value != null and (typeof(yaw_value) == TYPE_REAL or typeof(yaw_value) == TYPE_INT):
			has_yaw_override = true
			yaw_override = float(yaw_value)
		var max_steps_value = episode_override.get("max_steps", null)
		if max_steps_value != null and typeof(max_steps_value) in [TYPE_INT, TYPE_REAL]:
			_rl_max_episode_steps = max(100, int(max_steps_value))
		var door_required_value = episode_override.get("door_required", null)
		if door_required_value != null and typeof(door_required_value) == TYPE_BOOL:
			episode_requires_interactable_open = episode_requires_interactable_open and bool(door_required_value)
	if player and player.has_method("teleport_to"):
		var t = Transform()
		t.origin = spawn_origin
		var rand_yaw = yaw_override if has_yaw_override else (rand_range(-PI, PI) if _rl_spawn_random_yaw else 0.0)
		t.basis = Basis(Vector3.UP, rand_yaw)
		player.teleport_to(t)
		_episode_start_height = t.origin.y

	# Reset Target
	if target:
		target.global_transform.origin = target_origin

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
	_rl_recovery_strafe_side = 0.0
	_rl_recovery_fallback_side = - _rl_recovery_fallback_side
	if abs(_rl_recovery_fallback_side) < 0.001:
		_rl_recovery_fallback_side = 1.0
	_rl_jump_hold_frames = 0
	_rl_strafe_commit_remaining = 0
	_rl_strafe_commit_side = 0.0
	_jump_cooldown_frames = 0
	_interact_cooldown_frames = 0
	_last_front_ray_dist = -1.0
	_last_route_interact_dist = -1.0
	_last_route_interact_progress = -1.0
	_rl_episode_require_interactable_open_for_success = episode_requires_interactable_open
	_rl_episode_interactable_opened = (not _rl_episode_require_interactable_open_for_success) or _any_interactable_opened_for_success()
	_episode_step_count = 0
	_episode_start_time = OS.get_unix_time()
	# Force initial distance update
	if target and player:
		_last_dist_to_target = player.global_transform.origin.distance_to(target.global_transform.origin)
		var to_target = target.global_transform.origin - player.global_transform.origin
		to_target.y = 0.0
		if to_target.length_squared() > 0.001:
			to_target = to_target.normalized()
			var fwd_basis = _get_control_basis(player as Spatial)
			var fwd = - fwd_basis.z
			fwd.y = 0.0
			if fwd.length_squared() > 0.001:
				fwd = fwd.normalized()
				_last_abs_angle_to_target = abs(fwd.angle_to(to_target) / PI)

func _get_rl_scene_controller() -> Node:
	if _is_rl_scene_hook_node(_rl_scene_controller_cache):
		return _rl_scene_controller_cache
	var node: Node = self
	while is_instance_valid(node):
		if _is_rl_scene_hook_node(node):
			_rl_scene_controller_cache = node
			return node
		node = node.get_parent()
	if not is_inside_tree():
		return null
	var tree = get_tree()
	if tree == null:
		return null
	var scene = tree.current_scene
	if _is_rl_scene_hook_node(scene):
		_rl_scene_controller_cache = scene
		return scene
	var nested = _search_rl_scene_hook_in_subtree(scene, 128)
	if is_instance_valid(nested):
		_rl_scene_controller_cache = nested
		return nested
	return scene

func _is_rl_scene_hook_node(node: Node) -> bool:
	return is_instance_valid(node) and (
		node.has_method(RL_SCENE_HOOK_BEFORE_RESET) or
		node.has_method(RL_SCENE_HOOK_CHOOSE_EPISODE)
	)

func _search_rl_scene_hook_in_subtree(root: Node, node_limit: int = 128) -> Node:
	if not is_instance_valid(root):
		return null
	var stack = [root]
	var visited = 0
	while stack.size() > 0 and visited < node_limit:
		var current = stack.pop_back()
		visited += 1
		if _is_rl_scene_hook_node(current):
			return current
		for i in range(current.get_child_count()):
			var child = current.get_child(i)
			if is_instance_valid(child):
				stack.push_back(child)
	return null

func _call_rl_scene_before_reset_hook() -> void:
	var scene = _get_rl_scene_controller()
	if not is_instance_valid(scene):
		return
	if scene.has_method(RL_SCENE_HOOK_BEFORE_RESET):
		scene.call(RL_SCENE_HOOK_BEFORE_RESET, self)

func _get_rl_scene_episode_override() -> Dictionary:
	var scene = _get_rl_scene_controller()
	if not is_instance_valid(scene):
		return {}
	if not scene.has_method(RL_SCENE_HOOK_CHOOSE_EPISODE):
		return {}
	var raw = scene.call(RL_SCENE_HOOK_CHOOSE_EPISODE, self)
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	return {}

func _variant_to_vector3(value) -> Dictionary:
	if value is Vector3:
		return {"ok": true, "value": value}
	if typeof(value) == TYPE_ARRAY:
		var arr = value
		if arr.size() >= 3:
			return {
				"ok": true,
				"value": Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
			}
	if typeof(value) == TYPE_DICTIONARY:
		var d = value
		if d.has("x") and d.has("y") and d.has("z"):
			return {
				"ok": true,
				"value": Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
			}
	return {"ok": false}

func _refresh_rl_sampling_nodes() -> void:
	_rl_spawn_zone_nodes = []
	_rl_target_zone_nodes = []
	_rl_spawn_point_nodes = []
	_rl_target_point_nodes = []
	if not is_inside_tree():
		return
	var tree = get_tree()
	if not tree:
		return
	for node in tree.get_nodes_in_group(RL_SPAWN_ZONE_GROUP):
		if is_instance_valid(node) and node is Spatial:
			_rl_spawn_zone_nodes.append(node)
	for node in tree.get_nodes_in_group(RL_TARGET_ZONE_GROUP):
		if is_instance_valid(node) and node is Spatial:
			_rl_target_zone_nodes.append(node)
	for node in tree.get_nodes_in_group(RL_SPAWN_POINT_GROUP):
		if is_instance_valid(node) and node is Spatial:
			_rl_spawn_point_nodes.append(node)
	for node in tree.get_nodes_in_group(RL_TARGET_POINT_GROUP):
		if is_instance_valid(node) and node is Spatial:
			_rl_target_point_nodes.append(node)

func _get_zone_extents(zone: Node) -> Vector3:
	if not is_instance_valid(zone):
		return Vector3.ZERO
	if "extents" in zone:
		return zone.extents
	if "size" in zone:
		return zone.size * 0.5
	return Vector3.ZERO

func _get_zone_weight(zone: Node) -> float:
	if not is_instance_valid(zone):
		return 1.0
	if "weight" in zone:
		return max(0.01, float(zone.weight))
	return 1.0

func _pick_weighted_zone(nodes: Array) -> Spatial:
	if nodes.empty():
		return null
	var total_weight = 0.0
	for node in nodes:
		total_weight += _get_zone_weight(node)
	if total_weight <= 0.0:
		return nodes[randi() % nodes.size()] as Spatial
	var roll = randf() * total_weight
	for node in nodes:
		roll -= _get_zone_weight(node)
		if roll <= 0.0:
			return node as Spatial
	return nodes[nodes.size() - 1] as Spatial

func _sample_zone_position(zone: Spatial, player: Node, default_y: float) -> Vector3:
	if not is_instance_valid(zone):
		return Vector3(0.0, default_y, 0.0)
	var extents = _get_zone_extents(zone)
	var center = zone.global_transform.origin
	var y_min = center.y
	var y_max = center.y
	var use_node_y_as_floor = true
	if "use_node_y_as_floor" in zone:
		use_node_y_as_floor = bool(zone.use_node_y_as_floor)
	if "floor_y" in zone:
		y_min = float(zone.floor_y)
		y_max = float(zone.floor_y)
	elif extents.y > 0.01 and not use_node_y_as_floor:
		y_min = center.y - extents.y
		y_max = center.y + extents.y
	var p = Vector3(
		rand_range(center.x - extents.x, center.x + extents.x),
		rand_range(y_min, y_max),
		rand_range(center.z - extents.z, center.z + extents.z)
	)
	if "y_jitter" in zone:
		p.y += rand_range(-abs(float(zone.y_jitter)), abs(float(zone.y_jitter)))
	return _snap_position_to_floor(p, player)

func _sample_bounds_position(min_v: Vector3, max_v: Vector3, player: Node, default_y: float) -> Vector3:
	var p = Vector3(
		rand_range(min_v.x, max_v.x),
		rand_range(min_v.y, max_v.y),
		rand_range(min_v.z, max_v.z)
	)
	if abs(max_v.y - min_v.y) < 0.001:
		p.y = default_y
	return _snap_position_to_floor(p, player)

func _snap_position_to_floor(point: Vector3, player: Node) -> Vector3:
	var viewport = get_viewport()
	if viewport == null or viewport.world == null:
		return point
	var from = point + Vector3.UP * RL_FLOOR_SNAP_UP
	var to = point - Vector3.UP * RL_FLOOR_SNAP_DOWN
	var exclude := []
	if is_instance_valid(player):
		exclude.append(player)
	var hit = viewport.world.direct_space_state.intersect_ray(from, to, exclude, 0x7FFFFFFF, true, false)
	if typeof(hit) == TYPE_DICTIONARY and hit.has("position"):
		var p = hit["position"]
		if p is Vector3:
			return p + Vector3.UP * RL_FLOOR_SNAP_CLEARANCE
	return point

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var d = a - b
	d.y = 0.0
	return d.length()

func _sample_rl_spawn_position(player: Node) -> Vector3:
	if _rl_spawn_point_nodes.size() > 0:
		for _i in range(_rl_spawn_sample_tries):
			var node = _rl_spawn_point_nodes[randi() % _rl_spawn_point_nodes.size()]
			if is_instance_valid(node) and node is Spatial:
				return _snap_position_to_floor((node as Spatial).global_transform.origin, player)
	if _rl_spawn_zone_nodes.size() > 0:
		for _i in range(_rl_spawn_sample_tries):
			var zone = _pick_weighted_zone(_rl_spawn_zone_nodes)
			if is_instance_valid(zone):
				return _sample_zone_position(zone, player, _rl_spawn_pos.y)
	if _rl_spawn_bounds_enabled:
		for _i in range(_rl_spawn_sample_tries):
			return _sample_bounds_position(_rl_spawn_bounds_min, _rl_spawn_bounds_max, player, _rl_spawn_pos.y)
	var spawn_origin = _rl_spawn_pos
	if _rl_spawn_alt_enabled and _rl_spawn_alt_prob > 0.0 and randf() < _rl_spawn_alt_prob:
		spawn_origin = _rl_spawn_alt_pos
	return _snap_position_to_floor(spawn_origin, player)

func _target_distance_ok(spawn_origin: Vector3, target_origin: Vector3) -> bool:
	return _horizontal_distance(spawn_origin, target_origin) >= _rl_target_min_separation

func _sample_rl_target_position(spawn_origin: Vector3, player: Node, _target: Spatial) -> Vector3:
	if _rl_target_point_nodes.size() > 0:
		for _i in range(_rl_target_sample_tries):
			var node = _rl_target_point_nodes[randi() % _rl_target_point_nodes.size()]
			if not is_instance_valid(node) or not node is Spatial:
				continue
			var p = _snap_position_to_floor((node as Spatial).global_transform.origin, player)
			if _target_distance_ok(spawn_origin, p):
				return p
	if _rl_target_zone_nodes.size() > 0:
		for _i in range(_rl_target_sample_tries):
			var zone = _pick_weighted_zone(_rl_target_zone_nodes)
			if not is_instance_valid(zone):
				continue
			var p = _sample_zone_position(zone, player, _rl_target_fixed_y)
			if _target_distance_ok(spawn_origin, p):
				return p
	if _rl_target_bounds_enabled:
		for _i in range(_rl_target_sample_tries):
			var p = _sample_bounds_position(_rl_target_bounds_min, _rl_target_bounds_max, player, _rl_target_fixed_y)
			if _target_distance_ok(spawn_origin, p):
				return p
	for _i in range(_rl_target_sample_tries):
		var angle = rand_range(0.0, 2.0 * PI)
		var dist = rand_range(_rl_target_radius_min, _rl_target_radius_max)
		var tx = spawn_origin.x + cos(angle) * dist
		var tz = spawn_origin.z + sin(angle) * dist
		var p = _snap_position_to_floor(Vector3(tx, _rl_target_fixed_y, tz), player)
		if _target_distance_ok(spawn_origin, p):
			return p
	return _snap_position_to_floor(Vector3(spawn_origin.x, _rl_target_fixed_y, spawn_origin.z + _rl_target_radius_min), player)

func _reset_interactables_for_episode() -> void:
	if not is_inside_tree():
		return
	var nodes = get_tree().get_nodes_in_group("interactable")
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if "is_used" in node:
			node.is_used = false
		if "target_progress" in node:
			node.target_progress = 0.0
		if "anim_progress" in node:
			node.anim_progress = 0.0
		if node.has_method("set_active"):
			var starts_active = false
			if "starts_active" in node:
				starts_active = bool(node.starts_active)
			node.set_active(starts_active, true)

func apply_rl_action(action_idx: int) -> void:
	# Action Space:
	# 0=SteerOnly,
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
	var jump_hold_active := _rl_jump_hold_frames > 0
	if _rl_jump_hold_frames > 0:
		_rl_jump_hold_frames -= 1
	if _jump_cooldown_frames > 0:
		_jump_cooldown_frames -= 1
	if _interact_cooldown_frames > 0:
		_interact_cooldown_frames -= 1
	if _rl_strafe_commit_remaining > 0:
		_rl_strafe_commit_remaining -= 1
	if _rl_legacy_fast_mode:
		_apply_rl_action_legacy_fast(action_idx)
		return

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

	# Strafe commit gate:
	# keep the chosen lateral side for a few frames to avoid left-right jitter.
	if abs(move_vec.x) > 0.1 and _rl_strafe_commit_frames > 0:
		var requested_side = sign(move_vec.x)
		if abs(_rl_strafe_commit_side) < 0.001:
			_rl_strafe_commit_side = requested_side
			_rl_strafe_commit_remaining = _rl_strafe_commit_frames
		elif _rl_strafe_commit_remaining > 0 and requested_side != _rl_strafe_commit_side:
			move_vec.x = _rl_strafe_commit_side * abs(move_vec.x)
		else:
			if requested_side != _rl_strafe_commit_side:
				_rl_strafe_commit_side = requested_side
			_rl_strafe_commit_remaining = _rl_strafe_commit_frames
	elif _rl_strafe_commit_remaining <= 0:
		_rl_strafe_commit_side = 0.0

	# Allow diagonal strafe+forward without increasing action space size.
	if not jump_pressed and abs(move_vec.x) > 0.1 and _rl_strafe_forward_assist > 0.0:
		move_vec.y = min(move_vec.y, -_rl_strafe_forward_assist)

	if jump_pressed and abs(move_vec.x) > 0.1 and _rl_jump_strafe_forward_assist > 0.0:
		move_vec.y = min(move_vec.y, -_rl_jump_strafe_forward_assist)
	if jump_pressed and not sprint_pressed:
		if abs(move_vec.x) > 0.1:
			if _rl_sprint_on_jump_strafe_actions:
				sprint_pressed = true
		elif _rl_sprint_on_jump_actions:
			sprint_pressed = true
	elif abs(move_vec.x) > 0.1 and _rl_sprint_on_strafe_actions:
		sprint_pressed = true

	# Assisted steering: force look direction toward current objective bearing.
	var player = _get_player()
	var target = _ensure_rl_target()
	var route_target: Spatial = null
	var steer_angle = 0.0
	var has_steer = false
	var vertical_jump_context := false
	if _rl_assisted_steering and is_instance_valid(player) and is_instance_valid(target):
		route_target = _get_route_interactable(player as Spatial, target, _get_front_obstacle_distance(player as Spatial)) as Spatial
		var steer_target: Spatial = target
		if is_instance_valid(route_target):
			steer_target = route_target
		steer_angle = _get_target_angle_normalized(player as Spatial, steer_target)
		has_steer = true
		var to_target_3d = target.global_transform.origin - player.global_transform.origin
		var target_delta_y = to_target_3d.y
		to_target_3d.y = 0.0
		var horizontal_dist = to_target_3d.length()
		var heading_ok = (not has_steer) or abs(steer_angle) <= _rl_smart_jump_max_steer_angle
		if target_delta_y > _rl_smart_jump_target_above_y and horizontal_dist <= _rl_smart_jump_target_above_dist:
			if heading_ok and (move_vec.y < -0.15 or abs(move_vec.x) > 0.2):
				vertical_jump_context = true

		if _rl_assisted_steering and has_steer:
			if abs(steer_angle) < RL_LOOK_ALIGN_DEADZONE:
				look_vec.x = 0.0
			else:
				# Proportional steering toward target bearing using CameraRig orientation.
				# Positive steer_angle should rotate camera toward target.
				# PlayerControllerV2 applies yaw -= mouse_delta.x * sensitivity, so this sign is inverted.
				look_vec.x = - clamp(steer_angle * _rl_look_delta_x, -_rl_look_delta_x, _rl_look_delta_x)
				if abs(steer_angle) > 0.12 and abs(look_vec.x) < _rl_look_min_correction:
					look_vec.x = - sign(steer_angle) * _rl_look_min_correction
	else:
		look_vec.x = 0.0

	# After opening required door-like interactable, bias motion to keep advancing
	# instead of backing off or orbiting near the doorway.
	if _rl_episode_require_interactable_open_for_success and _rl_episode_interactable_opened and is_instance_valid(player) and is_instance_valid(target):
		var post_door_dist = player.global_transform.origin.distance_to(target.global_transform.origin)
		if post_door_dist > (RL_SUCCESS_DIST * 1.1):
			if has_steer and abs(steer_angle) < 0.35 and move_vec.y > 0.05:
				move_vec.y = 0.0
			if has_steer and abs(steer_angle) < 0.22 and move_vec.y < -0.2:
				sprint_pressed = true
			if has_steer and abs(steer_angle) < 0.12 and abs(move_vec.x) > 0.55:
				move_vec.x *= 0.65

	# Anti-collapse runtime gate:
	# when target bearing is off, throttle forward so controller re-aims without freezing.
	if _rl_assisted_steering and has_steer and abs(steer_angle) > RL_MOVE_ALIGN_GATE:
		var misalign = clamp((abs(steer_angle) - RL_MOVE_ALIGN_GATE) / max(0.001, 1.0 - RL_MOVE_ALIGN_GATE), 0.0, 1.0)
		var throttle = lerp(1.0, RL_MOVE_MIN_THROTTLE, misalign)
		move_vec.y *= throttle
		if throttle < RL_SPRINT_DISABLE_THROTTLE:
			sprint_pressed = false

	# Anti-orbit control near target:
	# when close and misaligned, throttle forward/strafe so policy commits to re-aiming.
	if _rl_assisted_steering and is_instance_valid(player) and is_instance_valid(target):
		var dist_now = player.global_transform.origin.distance_to(target.global_transform.origin)
		if dist_now < RL_ORBIT_CONTROL_DIST and abs(steer_angle) > RL_ORBIT_CONTROL_ANGLE:
			if move_vec.y < 0.0:
				move_vec.y *= RL_ORBIT_FORWARD_THROTTLE
			move_vec.x *= RL_ORBIT_STRAFE_THROTTLE
			sprint_pressed = false

	# Sprint assist: if policy keeps choosing plain forward while aligned and unobstructed,
	# upgrade to sprint so locomotion does not collapse into walking.
	if not sprint_pressed and move_vec.y < -0.6 and has_steer and abs(steer_angle) < RL_AUTO_SPRINT_ANGLE_MAX:
		var on_floor_auto = true
		if player and player.has_method("is_on_floor"):
			on_floor_auto = player.is_on_floor()
		if on_floor_auto:
			var player_spatial_auto: Spatial = player as Spatial if player is Spatial else null
			var front_clear = _get_front_obstacle_distance(player_spatial_auto) > (RL_OBSTACLE_AHEAD_DIST * RL_AUTO_SPRINT_OBSTACLE_CLEAR_FACTOR)
			var far_target_auto = true
			if is_instance_valid(player) and is_instance_valid(target):
				far_target_auto = player.global_transform.origin.distance_to(target.global_transform.origin) > (RL_SUCCESS_DIST * RL_AUTO_SPRINT_MIN_DIST_FACTOR)
			if front_clear and far_target_auto:
				sprint_pressed = true

	var player_spatial_for_recovery: Spatial = player as Spatial if player is Spatial else null
	var front_obstacle_for_recovery = _get_front_obstacle_distance(player_spatial_for_recovery)
	if abs(move_vec.x) > 0.1 and front_obstacle_for_recovery < (RL_OBSTACLE_AHEAD_DIST * 1.25) and is_instance_valid(player_spatial_for_recovery):
		var preferred_side_assist = 0.0
		var side_margin_assist = max(0.12, _rl_recovery_side_clear_margin * 0.65)
		var lateral_clearance_assist = _get_lateral_clearance(player_spatial_for_recovery)
		var left_clear_assist = float(lateral_clearance_assist.get("left", SENSOR_RANGE))
		var right_clear_assist = float(lateral_clearance_assist.get("right", SENSOR_RANGE))
		var clear_delta_assist = right_clear_assist - left_clear_assist
		if abs(clear_delta_assist) > side_margin_assist:
			preferred_side_assist = 1.0 if clear_delta_assist > 0.0 else -1.0
		elif has_steer and abs(steer_angle) > 0.2:
			preferred_side_assist = - sign(steer_angle)
		if abs(preferred_side_assist) > 0.1 and sign(move_vec.x) != preferred_side_assist:
			move_vec.x = preferred_side_assist * abs(move_vec.x)
			_rl_strafe_commit_side = preferred_side_assist
			_rl_strafe_commit_remaining = max(_rl_strafe_commit_remaining, 3)
	if action_idx == 0 and _rl_action0_backstep_enabled:
		var backstep_context = front_obstacle_for_recovery < (RL_OBSTACLE_AHEAD_DIST * 1.1) or _hazard_contact_frames > 0 or _wall_stuck_frames > 0
		if backstep_context:
			move_vec.y = _rl_action0_backstep_speed
	var early_recovery = _hazard_contact_frames >= _rl_early_wall_recovery_hazard_frames and front_obstacle_for_recovery < _rl_early_wall_recovery_front_dist and move_vec.y < -0.25 and abs(move_vec.x) < 0.35 and not vertical_jump_context

	# Forced stuck recovery: if we are clearly wedged on walls, override action to escape.
	var forced_recovery := false
	if _wall_stuck_frames >= _rl_stuck_recovery_wall_frames or early_recovery:
		forced_recovery = true
		var strafe_sign = _rl_recovery_strafe_side
		if abs(strafe_sign) < 0.001:
			strafe_sign = _pick_recovery_strafe_side(player_spatial_for_recovery, has_steer, steer_angle, move_vec.x)
			if abs(strafe_sign) < 0.001:
				strafe_sign = _rl_recovery_fallback_side
		_rl_recovery_strafe_side = strafe_sign
		move_vec.x = strafe_sign * _rl_stuck_recovery_strafe
		move_vec.y = _rl_stuck_recovery_backoff
		sprint_pressed = false
		_rl_strafe_commit_side = strafe_sign
		_rl_strafe_commit_remaining = max(_rl_strafe_commit_remaining, _rl_strafe_commit_frames)
		if _rl_stuck_recovery_jump_period > 0 and _wall_stuck_frames > 0 and int(_wall_stuck_frames) % _rl_stuck_recovery_jump_period == 0:
			jump_pressed = true

	# Vertical jump-assist:
	# If target is above and nearby, help the policy by injecting jump from non-jump actions.
	if not jump_pressed and not forced_recovery and vertical_jump_context:
		var on_floor_for_assist = true
		if player and player.has_method("is_on_floor"):
			on_floor_for_assist = player.is_on_floor()
		if on_floor_for_assist and _jump_cooldown_frames <= 0:
			jump_pressed = true
			sprint_pressed = false

	if not jump_pressed and jump_hold_active and not forced_recovery:
		jump_pressed = true

	# Smart jump gating: only jump when obstacle/stuck context justifies it.
	if jump_pressed and not forced_recovery:
		var on_floor_now = true
		if player and player.has_method("is_on_floor"):
			on_floor_now = player.is_on_floor()
		var player_spatial: Spatial = player as Spatial if player is Spatial else null
		var front_obstacle_dist = _get_front_obstacle_distance(player_spatial)
		var front_height_profile = _get_front_height_profile(player_spatial)
		var jumpable_front = bool(front_height_profile.get("jumpable", false))
		var obstacle_ahead = (front_obstacle_dist < _rl_smart_jump_ahead_dist) or jumpable_front
		var stuck_context = _wall_stuck_frames >= RL_SMART_JUMP_ALLOW_STUCK_FRAMES
		var blocked_jump = (not on_floor_now and not jump_hold_active) or ((_jump_cooldown_frames > 0) and not jump_hold_active) or (not obstacle_ahead and not stuck_context and not vertical_jump_context and not jump_hold_active)
		if blocked_jump:
			jump_pressed = false
	if jump_pressed:
		if not jump_hold_active:
			_jump_cooldown_frames = RL_SMART_JUMP_MIN_COOLDOWN
			_rl_jump_hold_frames = max(0, int(_rl_jump_hold_input_frames))

	# Contextual interact:
	# Reuse "steer-only" action as explicit interaction, and auto-assist when a door-like
	# interactable blocks frontal motion so the policy does not get stuck pushing.
	var player_spatial_for_interact: Spatial = player as Spatial if player is Spatial else null
	var interact_candidate = _get_front_interactable(player_spatial_for_interact)
	if is_instance_valid(interact_candidate):
		var door_interact_bias = max(0.4, _rl_door_interact_bias)
		var door_focus_range = RL_INTERACT_AUTO_RANGE * (1.0 + max(0.0, door_interact_bias - 1.0) * 0.25)
		var door_focus_front = RL_INTERACT_AUTO_FRONT_BLOCK_DIST * (1.0 + max(0.0, door_interact_bias - 1.0) * 0.25)
		if _rl_episode_require_interactable_open_for_success and not _rl_episode_interactable_opened:
			door_focus_range = max(door_focus_range, RL_INTERACT_AUTO_RANGE * 1.45)
			door_focus_front = max(door_focus_front, RL_INTERACT_AUTO_FRONT_BLOCK_DIST * 1.55)
		var door_forward_trigger = -0.55 + max(0.0, door_interact_bias - 1.0) * 0.15
		door_forward_trigger = clamp(door_forward_trigger, -0.75, -0.25)
		var interact_dist = RL_INTERACT_AUTO_RANGE
		if interact_candidate is Spatial and is_instance_valid(player_spatial_for_interact):
			interact_dist = player_spatial_for_interact.global_transform.origin.distance_to((interact_candidate as Spatial).global_transform.origin)
		var front_obstacle_for_interact = _get_front_obstacle_distance(player_spatial_for_interact)
		var candidate_is_open := false
		var candidate_progress := 0.0
		if "is_active" in interact_candidate:
			candidate_is_open = bool(interact_candidate.is_active)
		if "target_progress" in interact_candidate:
			candidate_progress = float(interact_candidate.target_progress)
		var should_open_interactable = not candidate_is_open and candidate_progress < 0.9
		var open_passage_focus = (not should_open_interactable) and interact_dist <= (door_focus_range * 1.2) and has_steer and abs(steer_angle) < 0.32
		if open_passage_focus:
			# Door is open and centered enough: commit forward through opening, avoid zigzag.
			move_vec.y = min(move_vec.y, -0.9)
			jump_pressed = false
			if abs(move_vec.x) > 0.35:
				move_vec.x *= 0.35
			if abs(move_vec.x) > 0.1 and abs(steer_angle) > 0.06:
				var desired_side_through = - sign(steer_angle)
				if abs(desired_side_through) > 0.1 and sign(move_vec.x) != desired_side_through:
					move_vec.x = desired_side_through * min(abs(move_vec.x), 0.45)
			if abs(steer_angle) < 0.18:
				sprint_pressed = true
		if door_interact_bias > 1.01 and should_open_interactable and move_vec.y < -0.2 and front_obstacle_for_interact < door_focus_front and interact_dist <= door_focus_range:
			# Door-focused shaping mode: avoid "jumping through" closed door encounters.
			jump_pressed = false
		var auto_interact = false
		if action_idx == 0 and should_open_interactable and front_obstacle_for_interact < door_focus_front and interact_dist <= door_focus_range:
			auto_interact = true
		elif should_open_interactable and move_vec.y < door_forward_trigger and front_obstacle_for_interact < door_focus_front and interact_dist <= door_focus_range:
			auto_interact = true
		elif should_open_interactable and _wall_stuck_frames >= RL_INTERACT_STUCK_TRIGGER_FRAMES and interact_dist <= door_focus_range:
			auto_interact = true
		elif should_open_interactable and move_vec.y < -0.75 and interact_dist <= 2.6:
			# Forward commit near a closed door-like interactable: assist with an interact pulse.
			auto_interact = true
		elif _rl_episode_require_interactable_open_for_success and not _rl_episode_interactable_opened and should_open_interactable and interact_dist <= door_focus_range and front_obstacle_for_interact < (door_focus_front * 1.1):
			# In strict door-required episodes, fire interact aggressively once we're in front.
			auto_interact = true
		if auto_interact:
			interact_pressed = true
			if front_obstacle_for_interact < door_focus_front:
				move_vec.y = min(move_vec.y, 0.0)
				sprint_pressed = false
				jump_pressed = false
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
		var look_norm = Vector2(look_vec.x / max(1.0, _rl_look_delta_x), look_vec.y / max(1.0, RL_LOOK_DELTA_Y))
		var prev_look_norm = Vector2(_last_look_cmd.x / max(1.0, _rl_look_delta_x), _last_look_cmd.y / max(1.0, RL_LOOK_DELTA_Y))
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
		"fov_override": - 1.0
	}

	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.is_recording:
		sm._oys_input_override = input_dict
	else:
		if player and player.has_method("inject_input"):
			player.inject_input(input_dict)

func _get_rl_observation_legacy_fast(player: Spatial) -> Dictionary:
	if not is_instance_valid(_rl_raycast_root):
		_setup_rl_sensors()
	if not is_instance_valid(_rl_raycast_root) or _rl_rays.size() == 0:
		var fallback := []
		for _i in range(12):
			fallback.append(0.0)
		return {"obs": fallback, "reward": 0.0, "done": true, "done_reason": "legacy_no_sensors"}
	var obs_vector := []
	var reward := _rl_time_penalty
	var done := false
	var done_reason := "running"
	var dist_to_target := SENSOR_RANGE
	var angle_to_target := 0.0
	var min_ray_dist := SENSOR_RANGE
	var front_ray_dist := SENSOR_RANGE
	_rl_raycast_root.global_transform.origin = player.global_transform.origin + Vector3(0, 1.0, 0)
	_rl_raycast_root.global_transform.basis = player.global_transform.basis
	for i in range(_rl_rays.size()):
		var ray = _rl_rays[i]
		ray.clear_exceptions()
		ray.add_exception(player)
		ray.force_raycast_update()
		var d := SENSOR_RANGE
		if ray.is_colliding():
			d = ray.global_transform.origin.distance_to(ray.get_collision_point())
		if d < min_ray_dist:
			min_ray_dist = d
		if i == 0 or i == 1 or i == (_rl_rays.size() - 1):
			if d < front_ray_dist:
				front_ray_dist = d
		obs_vector.append(clamp(d / SENSOR_RANGE, 0.0, 1.0))
	var target = _ensure_rl_target()
	if target:
		dist_to_target = player.global_transform.origin.distance_to(target.global_transform.origin)
		var to_target = (target.global_transform.origin - player.global_transform.origin)
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			to_target = to_target.normalized()
			var forward = -player.global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.0001:
				forward = forward.normalized()
				var angle = forward.angle_to(to_target)
				if forward.cross(to_target).y < 0:
					angle = -angle
				angle_to_target = angle / PI
	obs_vector.append(clamp(dist_to_target / 50.0, 0.0, 1.0))
	obs_vector.append(angle_to_target)
	var vel = Vector3.ZERO
	if "velocity" in player:
		vel = player.velocity
	var local_vel = player.global_transform.basis.xform_inv(vel)
	obs_vector.append(clamp(local_vel.x / RL_MAX_VELOCITY, -1.0, 1.0))
	obs_vector.append(clamp(local_vel.z / RL_MAX_VELOCITY, -1.0, 1.0))
	# Add height (Y position) for floor awareness in multi-floor levels
	var player_y = player.global_transform.origin.y
	# Normalize: assume floors at Y=1, Y=5, etc. Max reasonable height ~10m
	obs_vector.append(clamp(player_y / 10.0, 0.0, 1.0))
	if _last_dist_to_target >= 0.0:
		reward += (_last_dist_to_target - dist_to_target) * RL_PROGRESS_SCALE
	_last_dist_to_target = dist_to_target
	if dist_to_target < RL_SUCCESS_DIST:
		reward += RL_REWARD_SUCCESS
		done = true
		done_reason = "success"
	if not done and front_ray_dist < RL_COLLISION_PENALTY_THRESHOLD:
		reward += RL_REWARD_FAILURE
		done = true
		done_reason = "collision_front"
	elif not done and player.has_method("get_slide_count"):
		for i in range(player.get_slide_count()):
			var col = player.get_slide_collision(i)
			if col == null or not is_instance_valid(col.collider):
				continue
			if col.collider.is_in_group("anna_target"):
				continue
			if col.collider is StaticBody:
				reward += RL_REWARD_FAILURE
				done = true
				done_reason = "collision_slide"
				break
	return {
		"obs": obs_vector,
		"reward": reward,
		"done": done,
		"done_reason": done_reason
	}

func _apply_rl_action_legacy_fast(action_idx: int) -> void:
	var move_vec = Vector2.ZERO
	var jump_pressed := false
	var sprint_pressed := false
	match action_idx:
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
	var input_dict = {
		"move_vec": move_vec,
		"jump": jump_pressed,
		"interact": false,
		"sprint": sprint_pressed,
		"crouch": false,
		"mouse_delta": Vector2.ZERO,
		"zoom_delta": 0.0,
		"fov_override": -1.0
	}
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.is_recording:
		sm._oys_input_override = input_dict
	else:
		var player = _get_player()
		if player and player.has_method("inject_input"):
			player.inject_input(input_dict)
	_last_action_jump = jump_pressed
	_last_action_sprint = sprint_pressed
	_last_action_interact = false
	_last_action_look_x = 0.0
	_last_action_look_y = 0.0
	_last_action_change_cost = 0.0
	_last_move_cmd = move_vec
	_last_look_cmd = Vector2.ZERO
	_last_action_idx = action_idx

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

func _get_front_height_profile(player: Spatial) -> Dictionary:
	var default_profile = {
		"jumpable": false,
		"score": 0.0,
		"low_dist": SENSOR_RANGE,
		"high_dist": SENSOR_RANGE
	}
	if not is_instance_valid(player):
		return default_profile
	if not is_inside_tree():
		return default_profile
	var world = player.get_world()
	if world == null:
		return default_profile
	var space = world.direct_space_state
	if space == null:
		return default_profile

	var control_basis = _get_control_basis(player)
	var forward = -control_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -player.global_transform.basis.z
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return default_profile
	forward = forward.normalized()

	var probe_dist = clamp(_rl_front_height_sensor_dist, 0.5, SENSOR_RANGE)
	var low_from = player.global_transform.origin + Vector3(0.0, _rl_front_height_low_y, 0.0)
	var high_from = player.global_transform.origin + Vector3(0.0, _rl_front_height_high_y, 0.0)
	var low_to = low_from + forward * probe_dist
	var high_to = high_from + forward * probe_dist
	var exclude = [player]
	var low_hit = space.intersect_ray(low_from, low_to, exclude, 0x7FFFFFFF, true, false)
	var high_hit = space.intersect_ray(high_from, high_to, exclude, 0x7FFFFFFF, true, false)
	var low_dist = probe_dist
	var high_dist = probe_dist
	var low_blocked = not low_hit.empty()
	var high_blocked = not high_hit.empty()
	if low_blocked:
		low_dist = low_from.distance_to(low_hit.position)
	if high_blocked:
		high_dist = high_from.distance_to(high_hit.position)

	var jumpable = low_blocked and ((not high_blocked) or (high_dist > low_dist + RL_FRONT_HEIGHT_CLEARANCE_MARGIN))
	var score = 0.0
	if jumpable:
		var near_factor = 1.0 - clamp(low_dist / probe_dist, 0.0, 1.0)
		var clearance_factor = 1.0
		if high_blocked:
			clearance_factor = clamp((high_dist - low_dist) / max(0.05, probe_dist), 0.0, 1.0)
		score = clamp(near_factor * (0.6 + 0.4 * clearance_factor), 0.0, 1.0)
	return {
		"jumpable": jumpable,
		"score": score,
		"low_dist": low_dist,
		"high_dist": high_dist
	}

func _get_lateral_clearance(player: Spatial) -> Dictionary:
	if not is_instance_valid(player):
		return {"left": SENSOR_RANGE, "right": SENSOR_RANGE}
	if not is_instance_valid(_rl_raycast_root):
		_setup_rl_sensors()
	if not is_instance_valid(_rl_raycast_root) or _rl_rays.size() == 0:
		return {"left": SENSOR_RANGE, "right": SENSOR_RANGE}

	var control_basis = _get_control_basis(player)
	var right = control_basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = player.global_transform.basis.x
		right.y = 0.0
	if right.length_squared() < 0.0001:
		return {"left": SENSOR_RANGE, "right": SENSOR_RANGE}
	right = right.normalized()

	_rl_raycast_root.global_transform.origin = player.global_transform.origin + Vector3(0, 1.0, 0)
	_rl_raycast_root.global_transform.basis = control_basis

	var left_sum := 0.0
	var right_sum := 0.0
	var left_count := 0
	var right_count := 0
	for ray in _rl_rays:
		ray.clear_exceptions()
		ray.add_exception(player)
		ray.force_raycast_update()
		var d = SENSOR_RANGE
		if ray.is_colliding():
			d = ray.global_transform.origin.distance_to(ray.get_collision_point())

		var dir = ray.global_transform.basis.xform(ray.cast_to.normalized())
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		var side_dot = dir.dot(right)
		if side_dot > 0.25:
			right_sum += d
			right_count += 1
		elif side_dot < -0.25:
			left_sum += d
			left_count += 1

	var left_avg = left_sum / float(left_count) if left_count > 0 else SENSOR_RANGE
	var right_avg = right_sum / float(right_count) if right_count > 0 else SENSOR_RANGE
	return {"left": left_avg, "right": right_avg}

func _pick_recovery_strafe_side(player: Spatial, has_steer: bool, steer_angle: float, proposed_move_x: float) -> float:
	var clearance = _get_lateral_clearance(player)
	var left_clear = float(clearance.get("left", SENSOR_RANGE))
	var right_clear = float(clearance.get("right", SENSOR_RANGE))
	var clear_delta = right_clear - left_clear
	if abs(clear_delta) > _rl_recovery_side_clear_margin:
		return 1.0 if clear_delta > 0.0 else -1.0
	if has_steer and abs(steer_angle) > 0.20:
		return - sign(steer_angle)
	if abs(_rl_recovery_strafe_side_bias) > 0.001:
		return _rl_recovery_strafe_side_bias
	if abs(_last_move_cmd.x) > 0.05:
		return sign(_last_move_cmd.x)
	if abs(proposed_move_x) > 0.05:
		return sign(proposed_move_x)
	return _rl_recovery_fallback_side

func _get_front_interactable(player: Spatial) -> Node:
	if not is_instance_valid(player):
		return null
	if not is_inside_tree():
		return null

	var basis = _get_control_basis(player)
	var forward = - basis.z
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

func _is_interactable_closed(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var candidate_is_open := false
	var candidate_progress := 0.0
	if "is_active" in node:
		candidate_is_open = bool(node.is_active)
	if "target_progress" in node:
		candidate_progress = float(node.target_progress)
	return (not candidate_is_open) and candidate_progress < 0.9

func _any_interactable_opened_for_success() -> bool:
	var nodes = get_tree().get_nodes_in_group("interactable")
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var candidate_is_open := false
		var candidate_progress := 0.0
		if "is_active" in node:
			candidate_is_open = bool(node.is_active)
		if "target_progress" in node:
			candidate_progress = float(node.target_progress)
		if candidate_is_open or candidate_progress >= _rl_success_interactable_progress:
			return true
	return false

func _get_route_interactable(player: Spatial, target: Spatial, front_obstacle_dist: float) -> Node:
	if not is_instance_valid(player) or not is_instance_valid(target):
		return null
	var front_candidate = _get_front_interactable(player)
	if not is_instance_valid(front_candidate):
		return null
	if not _is_interactable_closed(front_candidate):
		return null
	var player_pos = player.global_transform.origin
	var target_dist = player_pos.distance_to(target.global_transform.origin)
	var interact_dist = player_pos.distance_to((front_candidate as Spatial).global_transform.origin) if front_candidate is Spatial else RL_INTERACT_AUTO_RANGE
	var front_blocked = front_obstacle_dist < (RL_INTERACT_AUTO_FRONT_BLOCK_DIST * RL_ROUTE_INTERACT_FRONT_FACTOR)
	var between_player_and_target = interact_dist < (target_dist + 0.5)
	if front_blocked and between_player_and_target:
		return front_candidate
	return null

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
	var forward = - facing_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0.0
	forward = forward.normalized()
	var angle = forward.angle_to(to_target)
	if forward.cross(to_target).y < 0:
		angle = - angle
	return angle / PI

func _get_control_basis(player: Spatial) -> Basis:
	var cm = get_node_or_null("/root/CinematicManager")
	if cm and cm.has_method("get_movement_basis"):
		return cm.get_movement_basis(1.0)
	if is_instance_valid(player) and player.has_method("get_camera_basis"):
		return player.get_camera_basis()
	return player.global_transform.basis if is_instance_valid(player) else Basis.IDENTITY


func _get_rl_target() -> Spatial:
	if is_instance_valid(_cached_target) and _cached_target.is_inside_tree() and not _cached_target.is_queued_for_deletion():
		return _cached_target
	var targets = get_tree().get_nodes_in_group(RL_TARGET_GROUP)
	if targets.size() > 0:
		var t = targets[0]
		if t is Spatial:
			_cached_target = t
			return _cached_target
	var current_scene = get_tree().current_scene if get_tree() else null
	if is_instance_valid(current_scene):
		var named = current_scene.get_node_or_null("RL_Target")
		if named and named is Spatial:
			_cached_target = named
			return _cached_target
	_cached_target = null
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
	_cached_target = target
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
			"fov_override": - 1.0
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
	if is_instance_valid(_cached_player) and _cached_player.is_inside_tree() and not _cached_player.is_queued_for_deletion():
		return _cached_player
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.player and is_instance_valid(sm.player) and sm.player.is_inside_tree():
		_cached_player = sm.player
		return _cached_player
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		_cached_player = players[0]
		return _cached_player
	_cached_player = null
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
	var root = get_tree().root
	if root == null:
		return null

	var console = root.get_node_or_null("OYS_Console")
	if console and console.has_method("enqueue_command"):
		return console

	var current_scene = get_tree().current_scene
	if is_instance_valid(current_scene):
		console = current_scene.find_node("OYS_Console", true, false)
		if console and console.has_method("enqueue_command"):
			return console

	# MCP fallback: if debug UI/terminal is not mounted, create a singleton console on demand
	# so execute_oys keeps working through the deterministic OYS path.
	var spawned = OYS_CONSOLE_SCRIPT.new()
	if spawned == null:
		return null
	spawned.name = "OYS_Console"
	root.add_child(spawned)
	return spawned

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

func _build_scene_hierarchy_entry(node: Node, depth: int, max_depth: int, max_children: int) -> Dictionary:
	var entry = {
		"name": String(node.name),
		"type": String(node.get_class()),
		"path": String(node.get_path())
	}

	if depth >= max_depth:
		entry["truncated"] = node.get_child_count() > 0
		return entry

	var children := []
	var omitted := 0
	for child in node.get_children():
		if not _should_include_scene_node(child):
			omitted += 1
			continue
		if children.size() >= max_children:
			omitted += 1
			continue
		children.append(_build_scene_hierarchy_entry(child, depth + 1, max_depth, max_children))

	if children.size() > 0:
		entry["children"] = children
	if omitted > 0:
		entry["omitted_children"] = omitted
	return entry

func _should_include_scene_node(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var name = String(node.name)
	if name.begins_with("_"):
		return false
	if name in ["_Timer", "_Tween"]:
		return false
	return true

func _read_oys_runtime_info() -> Dictionary:
	var info = {
		"running": false,
		"pc": -1,
		"line_raw": "",
		"line_command": ""
	}
	var sm = get_node_or_null("/root/SessionManager")
	if sm == null:
		return info
	var interpreter = sm.get("oys_interpreter")
	if interpreter == null:
		return info
	info["running"] = bool(interpreter.get("is_running"))
	var pc = int(interpreter.get("pc"))
	info["pc"] = pc
	var instructions = interpreter.get("instructions")
	if typeof(instructions) != TYPE_ARRAY or instructions.empty():
		return info
	var idx = clamp(pc - 1, 0, instructions.size() - 1)
	var inst = instructions[idx]
	if typeof(inst) == TYPE_DICTIONARY:
		info["line_raw"] = String(inst.get("raw", ""))
		info["line_command"] = String(inst.get("command", ""))
	return info

func _extract_logic_state_groups(snapshot: Dictionary) -> Dictionary:
	var grouped = {
		"levers": [],
		"doors": [],
		"gates": []
	}
	var nodes = snapshot.get("nodes", [])
	if typeof(nodes) != TYPE_ARRAY:
		return grouped

	for entry in nodes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var node_id = String(entry.get("id", ""))
		var node_type = String(entry.get("type", ""))
		var normalized = node_id.to_lower()
		var payload = {
			"id": node_id,
			"value": bool(entry.get("state", false))
		}
		if node_type == "GATE" or normalized.find("gate") != -1:
			grouped["gates"].append(payload)
		elif normalized.find("lever") != -1 or normalized.find("switch") != -1:
			grouped["levers"].append(payload)
		elif normalized.find("door") != -1:
			grouped["doors"].append(payload)
	return grouped

func _find_node_from_path(node_path: String) -> Node:
	if not is_inside_tree():
		return null
	var clean = node_path.strip_edges()
	if clean == "":
		return null
	var root = get_tree().root
	if clean == "/root":
		return root
	if clean.begins_with("/root/"):
		return root.get_node_or_null(clean.replace("/root/", ""))

	var scene = get_tree().current_scene
	if is_instance_valid(scene):
		var local = scene.get_node_or_null(clean)
		if local:
			return local

	var from_root = root.get_node_or_null(clean)
	if from_root:
		return from_root

	return root.find_node(clean, true, false)

func _extract_export_vars(node: Node) -> Dictionary:
	var out = {}
	var script = node.get_script()
	if script and script.has_method("get_script_property_list"):
		for prop in script.call("get_script_property_list"):
			if typeof(prop) != TYPE_DICTIONARY:
				continue
			var usage = int(prop.get("usage", 0))
			if usage & PROPERTY_USAGE_EDITOR == 0:
				continue
			var key = String(prop.get("name", ""))
			if key == "" or key.begins_with("_"):
				continue
			out[key] = _to_json_compatible(node.get(key))
	if out.size() > 0:
		return out

	for prop in node.get_property_list():
		var usage = int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var key = String(prop.get("name", ""))
		if key == "" or key.begins_with("_"):
			continue
		if key in ["script", "owner", "name", "filename"]:
			continue
		if key.find("/") != -1:
			continue
		out[key] = _to_json_compatible(node.get(key))
	return out

func _to_json_compatible(value):
	match typeof(value):
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_NODE_PATH:
			return String(value)
		TYPE_ARRAY:
			var arr := []
			for item in value:
				arr.append(_to_json_compatible(item))
			return arr
		TYPE_DICTIONARY:
			var out := {}
			for key in value.keys():
				out[String(key)] = _to_json_compatible(value[key])
			return out
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Node:
				return String((value as Node).get_path())
			return String(value)
		_:
			return value

func _to_vector3_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
