extends BaseZoneV2
class_name ProximityTriggerV2
tool

# ProximityTriggerV2.gd - Automatic Trigger for Interactables
# Activates target when player enters, deactivates when player leaves (with optional delay).

export(NodePath) var target_path
export(float) var exit_delay := 0.5

var _target: Node = null
var _exit_timer := 0.0
var _pending_exit := false

func _ready():
	._ready()
	if target_path:
		_target = get_node_or_null(target_path)

	# Enable physics process for the delay timer
	set_physics_process(true)

func _on_zone_entered(body: Node):
	if _target and _target.has_method("set_active"):
		# Cancel any pending exit
		_pending_exit = false
		_exit_timer = 0.0

		# Activate immediately
		_target.set_active(true)

func _on_zone_exited(body: Node):
	# Check if any players remain in the zone
	var players_remaining = 0
	for b_id in _bodies_in_zone:
		var b = _bodies_in_zone[b_id]
		if b and is_instance_valid(b) and b.is_in_group("player"):
			players_remaining += 1

	if players_remaining == 0:
		if exit_delay > 0:
			_pending_exit = true
			_exit_timer = exit_delay
		else:
			if _target and _target.has_method("set_active"):
				_target.set_active(false)

func _physics_process(delta):
	if Engine.editor_hint:
		return

	if _pending_exit:
		_exit_timer -= delta
		if _exit_timer <= 0:
			_pending_exit = false

			# Check one last time if anyone is inside (race condition check)
			var players_remaining = 0
			for b_id in _bodies_in_zone:
				var b = _bodies_in_zone[b_id]
				if b and is_instance_valid(b) and b.is_in_group("player"):
					players_remaining += 1

			if players_remaining == 0:
				if _target and _target.has_method("set_active"):
					_target.set_active(false)
