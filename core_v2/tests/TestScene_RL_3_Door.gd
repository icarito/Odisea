extends Spatial

# Stage 3 (door curriculum): inspired by BaseTerrace flow
# - Spawn starts in a small chamber
# - A sliding door blocks the only easy exit
# - Target is forced to the far side so INTERACT becomes useful

const RL_SPAWN_POS = Vector3(5.0, 2.5, 15.0)
const RL_TARGET_FIXED = Vector3(5.0, 1.0, -6.0)
const RL_TARGET_JITTER_X = 3.5
const RL_TARGET_JITTER_Z = 3.0

var _anna_interface: Node = null
var _is_rl := false
var _last_episode_seen := -1

func _ready() -> void:
	_is_rl = OS.get_environment("ANNA_RL_MODE") in ["1", "true", "True"]
	if not _is_rl:
		return
	call_deferred("_configure_rl")
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if not _is_rl or not is_instance_valid(_anna_interface):
		return
	if "_episode_step_count" in _anna_interface and int(_anna_interface._episode_step_count) <= 1:
		var episode_now = int(_anna_interface._episode_start_time)
		if episode_now != _last_episode_seen:
			_last_episode_seen = episode_now
			_reset_gate_state()
		_enforce_target_far_zone()

func _configure_rl() -> void:
	_anna_interface = _find_anna_interface(self)
	if not is_instance_valid(_anna_interface):
		return

	# Respect explicit env overrides; otherwise keep scene-safe defaults.
	var sx = OS.get_environment("ANNA_RL_SPAWN_X")
	var sy = OS.get_environment("ANNA_RL_SPAWN_Y")
	var sz = OS.get_environment("ANNA_RL_SPAWN_Z")
	if not sx.is_valid_float() and not sy.is_valid_float() and not sz.is_valid_float():
		_anna_interface._rl_spawn_pos = RL_SPAWN_POS
	_anna_interface._rl_spawn_random_yaw = false

	if not OS.get_environment("ANNA_RL_TARGET_Y").is_valid_float():
		_anna_interface._rl_target_fixed_y = 1.0

	_enforce_target_far_zone()

func _enforce_target_far_zone() -> void:
	var target = get_node_or_null("RL_Target")
	if not is_instance_valid(target):
		return
	if not is_instance_valid(_anna_interface):
		return

	var p = RL_TARGET_FIXED
	p.x += rand_range(-RL_TARGET_JITTER_X, RL_TARGET_JITTER_X)
	p.z += rand_range(-RL_TARGET_JITTER_Z, RL_TARGET_JITTER_Z)
	p.y = float(_anna_interface._rl_target_fixed_y)
	target.global_transform.origin = p

func _reset_gate_state() -> void:
	var gate = get_node_or_null("GateDoor")
	if not is_instance_valid(gate):
		return
	# Deterministic reset: each RL episode starts with closed gate.
	if "is_used" in gate:
		gate.is_used = false
	if "target_progress" in gate:
		gate.target_progress = 0.0
	if "anim_progress" in gate:
		gate.anim_progress = 0.0
	if gate.has_method("set_active"):
		gate.set_active(false, true)

func _find_anna_interface(root: Node) -> Node:
	for child in root.get_children():
		if child is AnnaInterface:
			return child
		var found = _find_anna_interface(child)
		if found:
			return found
	return null
