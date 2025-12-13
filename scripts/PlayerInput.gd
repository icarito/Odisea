extends Node
class_name PlayerInput

# Abstraction layer for inputs to enable deterministic replay
export var is_replay_mode := false
var _override_inputs: Dictionary = {}
var mouse_motion := Vector2.ZERO

func get_input_frame() -> Dictionary:
	if is_replay_mode:
		return _override_inputs.duplicate(true)
	else:
		var inputs = {
			"move_vec": Input.get_vector("left", "right", "forward", "backward"),
			"jump": Input.is_action_just_pressed("jump"),
			"attack1": Input.is_action_just_pressed("attack"),
			"sprint": Input.is_action_pressed("sprint"),
			"roll": Input.is_action_pressed("roll"),
			"mouse_motion": mouse_motion
		}
		mouse_motion = Vector2.ZERO  # Reset after reading
		return inputs

func inject_input(inputs: Dictionary):
	_override_inputs = inputs