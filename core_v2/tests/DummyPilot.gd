tool
extends KinematicBody

# Dummy Pilot for Tests
var is_replay_mode := false
var velocity := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0

var input_provider = null
var external_input = null
var external_input_provided := false

func step(dt: float, input_data = null) -> void:
	pass

func restore_snapshot(data: Dictionary) -> void:
	if "transform" in data:
		global_transform = str2var(data["transform"])

func get_full_snapshot() -> Dictionary:
	return {
		"transform": var2str(global_transform)
	}

func full_reset():
	pass

func teleport_to(t: Transform):
	global_transform = t
