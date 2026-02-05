tool
extends BaseZoneV2
class_name ProximityTriggerV2

# ProximityTriggerV2.gd - Trigger that activates an interactable when player enters
# Deterministic based on player movement.

# --- EXPORTED TUNING ---
export(NodePath) var target_interactable_path
export(bool) var deactivate_on_exit := true
export(float) var exit_delay := 0.0

# --- INTERNAL STATE ---
var _target: Node = null
var _exit_timer := 0.0
var _is_player_inside := false

func _ready():
	if target_interactable_path:
		_target = get_node_or_null(target_interactable_path)

	add_to_group("replay_sync")
	._ready()

func _on_zone_entered(body: Node):
	if body.is_in_group("player"):
		_is_player_inside = true
		_exit_timer = 0.0
		if (not _target or not is_instance_valid(_target)) and target_interactable_path:
			_target = get_node_or_null(target_interactable_path)

		if _target and _target.has_method("set_active"):
			_target.set_active(true)
		else:
			printerr("[ProximityTriggerV2] ERROR: Target not found or has no set_active: ", target_interactable_path)

func _on_zone_exited(body: Node):
	if body.is_in_group("player"):
		_is_player_inside = false
		if deactivate_on_exit:
			if exit_delay <= 0:
				_deactivate_target()
			else:
				_exit_timer = exit_delay

func _deactivate_target():
	if _target and _target.has_method("set_active"):
		_target.set_active(false)

func step(dt: float):
	if _exit_timer > 0:
		_exit_timer -= dt
		if _exit_timer <= 0:
			_deactivate_target()

func _physics_process(delta):
	if not SessionManager.is_manual_mode:
		step(delta)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"exit_timer": _exit_timer,
		"player_inside": _is_player_inside
	}

func restore_snapshot(data: Dictionary):
	_exit_timer = data.get("exit_timer", 0.0)
	_is_player_inside = data.get("player_inside", false)
