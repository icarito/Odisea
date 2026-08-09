extends Node

# CheckpointManager.gd
# Autoload system to track registered and active checkpoints.

var registered_checkpoints := []
var active_checkpoint_pos: Vector3 = Vector3.ZERO
var active_checkpoint_yaw: float = 0.0
var active_checkpoint_pitch: float = 0.0
var active_elevator_snapshot: Dictionary = {}

var default_respawn_position: Vector3 = Vector3.ZERO
var default_respawn_yaw: float = 0.0
var default_respawn_pitch: float = 0.0

func _ready() -> void:
	# Cache initial player position if available as fallback spawn
	call_deferred("_cache_default_spawn")

func _cache_default_spawn() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		default_respawn_position = p.global_transform.origin
		default_respawn_yaw = p.yaw
		default_respawn_pitch = p.pitch

func register_checkpoint(console: Node) -> void:
	if not registered_checkpoints.has(console):
		registered_checkpoints.append(console)

func set_active_checkpoint(pos: Vector3, yaw: float, pitch: float) -> void:
	active_checkpoint_pos = pos
	active_checkpoint_yaw = yaw
	active_checkpoint_pitch = pitch
	active_elevator_snapshot = capture_elevator_state()

	# Deactivate other checkpoints to ensure visual consistency (only one is active)
	for cp in registered_checkpoints:
		if is_instance_valid(cp):
			var cp_pos = cp.global_transform.origin
			if cp_pos.distance_squared_to(pos) > 0.01:
				if cp.has_method("deactivate"):
					cp.deactivate()

func get_respawn_transform() -> Dictionary:
	if active_checkpoint_pos != Vector3.ZERO:
		restore_elevator_state(active_elevator_snapshot)
		return {
			"position": active_checkpoint_pos,
			"yaw": active_checkpoint_yaw,
			"pitch": active_checkpoint_pitch
		}

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		return {
			"position": p.initial_transform.origin,
			"yaw": p.yaw,
			"pitch": p.pitch
		}

	return {
		"position": default_respawn_position,
		"yaw": default_respawn_yaw,
		"pitch": default_respawn_pitch
	}

# Support auto-checkpoints triggered by room triggers or areas
func trigger_auto_checkpoint(pos: Vector3, yaw: float = 0.0, pitch: float = 0.0) -> void:
	set_active_checkpoint(pos, yaw, pitch)

func capture_elevator_state() -> Dictionary:
	var snapshot: Dictionary = {}
	for node in get_tree().get_nodes_in_group("replay_sync"):
		if is_instance_valid(node) and _is_elevator_node(node) and node.has_method("get_snapshot"):
			snapshot[String(node.get_path())] = node.get_snapshot()
	return snapshot

func restore_elevator_state(snapshot: Dictionary) -> void:
	for path in snapshot.keys():
		var node: Node = get_node_or_null(NodePath(path))
		if is_instance_valid(node) and node.has_method("restore_snapshot"):
			node.restore_snapshot(snapshot[path])

func _is_elevator_node(node: Node) -> bool:
	var script: Script = node.get_script() as Script
	if script == null:
		return false
	return script.resource_path in [
		"res://core_v2/props/ElevatorController.gd",
		"res://core_v2/components/ElevatorPlatform.gd",
		"res://core_v2/props/elevator/MaintenanceElevator.gd"
	]
