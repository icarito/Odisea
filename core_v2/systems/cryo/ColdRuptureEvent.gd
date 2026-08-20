extends Spatial
class_name ColdRuptureEvent

# ColdRuptureEvent.gd - One-shot deterministic trigger for Dome_Intro's cryo failure.
# The rupture owns gameplay state only; explosion lifetime is presentation-only.

export(NodePath) var trigger_area_path: NodePath
export(Array, NodePath) var candidate_leak_paths: Array = []
export(PackedScene) var explosion_scene: PackedScene
export(Array, Vector3) var explosion_positions: Array = []
export(Array, Vector3) var aftershock_positions: Array = []
export(float) var aftershock_delay: float = 0.65
export(NodePath) var rupture_sound_path: NodePath
export(NodePath) var aftershock_sound_path: NodePath

var consumed: bool = false
var _activated_leak_paths: Array = []
var _trigger_area: Area = null
var _aftershock_remaining: float = -1.0
var _aftershock_fired: bool = false


func _ready() -> void:
	add_to_group("replay_sync")
	_resolve_trigger_area()


func trigger() -> void:
	if consumed:
		return
	consumed = true
	_trigger_camera_shake()
	_play_sound(rupture_sound_path)
	_spawn_explosions(explosion_positions, 1.0)
	_activated_leak_paths = []
	for path_value in candidate_leak_paths:
		var leak: Node = _get_target_node(path_value)
		if leak == null or not leak.has_method("trigger_leak"):
			continue
		leak.call("trigger_leak")
		_activated_leak_paths.append(NodePath(str(path_value)))
	_aftershock_remaining = max(aftershock_delay, 0.0)
	_aftershock_fired = false


func _physics_process(delta: float) -> void:
	if not consumed or _aftershock_fired or _aftershock_remaining < 0.0:
		return
	_aftershock_remaining -= delta
	if _aftershock_remaining <= 0.0:
		_aftershock_remaining = 0.0
		_aftershock_fired = true
		_play_aftershock()


func _resolve_trigger_area() -> void:
	if trigger_area_path == null or trigger_area_path.is_empty():
		return
	_trigger_area = get_node_or_null(trigger_area_path)
	if _trigger_area != null and not _trigger_area.is_connected("body_entered", self, "_on_trigger_body_entered"):
		_trigger_area.connect("body_entered", self, "_on_trigger_body_entered")


func _on_trigger_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		trigger()


func _trigger_camera_shake() -> void:
	var cinematic_manager: Node = get_node_or_null("/root/CinematicManager")
	if cinematic_manager != null and cinematic_manager.has_method("trigger_camera_shake"):
		cinematic_manager.call("trigger_camera_shake", 1.2, 0.12, 30.0, 2.0)


func _play_aftershock() -> void:
	_play_sound(aftershock_sound_path)
	_spawn_explosions(aftershock_positions, 0.55)
	var cinematic_manager: Node = get_node_or_null("/root/CinematicManager")
	if cinematic_manager != null and cinematic_manager.has_method("trigger_camera_shake"):
		cinematic_manager.call("trigger_camera_shake", 0.45, 0.06, 20.0, 0.8)


func _play_sound(sound_path: NodePath) -> void:
	if sound_path == null or sound_path.is_empty():
		return
	var sound: Node = get_node_or_null(sound_path)
	if sound != null and sound.has_method("play"):
		sound.call("play")


func _spawn_explosions(positions: Array, scale_factor: float) -> void:
	if explosion_scene == null or get_tree() == null:
		return
	for position in positions:
		var explosion: Node = explosion_scene.instance()
		get_tree().root.add_child(explosion)
		if explosion is Spatial:
			explosion.global_transform.origin = global_transform.xform(position)
			explosion.scale = Vector3.ONE * scale_factor
		var timer: Timer = Timer.new()
		timer.one_shot = true
		timer.wait_time = 0.9
		explosion.add_child(timer)
		timer.connect("timeout", explosion, "queue_free")
		timer.start()


func _get_target_node(path_value) -> Node:
	if path_value == null:
		return null
	var target_path: NodePath
	if path_value is NodePath:
		target_path = path_value
	elif path_value is String:
		if path_value == "":
			return null
		target_path = NodePath(path_value)
	else:
		return null
	if target_path.is_empty():
		return null
	var target: Node = get_node_or_null(target_path)
	if target != null:
		return target
	var parent: Node = get_parent()
	return parent.get_node_or_null(target_path) if parent != null else null


func get_snapshot() -> Dictionary:
	var paths: Array = []
	for path_value in _activated_leak_paths:
		paths.append(str(path_value))
	return {
		"consumed": consumed,
		"activated_leak_paths": paths,
		"aftershock_remaining": _aftershock_remaining,
		"aftershock_fired": _aftershock_fired
	}


func restore_snapshot(data: Dictionary) -> void:
	consumed = bool(data.get("consumed", false))
	_aftershock_remaining = float(data.get("aftershock_remaining", -1.0))
	_aftershock_fired = bool(data.get("aftershock_fired", true))
	_activated_leak_paths = []
	if data.has("activated_leak_paths") and data["activated_leak_paths"] is Array:
		for path_value in data["activated_leak_paths"]:
			_activated_leak_paths.append(NodePath(str(path_value)))
	if consumed:
		for path_value in _activated_leak_paths:
			var leak: Node = _get_target_node(path_value)
			if leak != null and leak.has_method("trigger_leak"):
				leak.call("trigger_leak")
