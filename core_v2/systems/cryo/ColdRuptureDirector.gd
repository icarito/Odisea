extends Spatial
class_name ColdRuptureDirector

# ColdRuptureDirector.gd - OYS Actor Director for Dome_Intro's cryo rupture sequence.
# Exposes coarse-grained actuator methods called directly by cold_rupture.oys.

export(NodePath) var leak_seeder_path: NodePath
export(NodePath) var rupture_focus_path: NodePath
export(PackedScene) var explosion_scene: PackedScene
export(float, 0.1, 8.0) var explosion_scale: float = 2.0

var consumed: bool = false
var last_explosion_pos: Vector3 = Vector3.ZERO
var _pending_leak_paths: Array = []
var _activated_leak_paths: Array = []


func _ready() -> void:
	add_to_group("replay_sync")
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("register_oys_actor"):
		sm.register_oys_actor("ColdRupture", self)


func _exit_tree() -> void:
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("unregister_oys_actor"):
		sm.unregister_oys_actor("ColdRupture")


# --- OYS ACTUATOR METHODS ---

func spawn_explosion() -> Vector3:
	if _pending_leak_paths.empty() and not consumed:
		_prepare_leaks()
		consumed = true

	var explosion_pos: Vector3 = global_transform.origin
	if not _pending_leak_paths.empty():
		var path_val = _pending_leak_paths.pop_front()
		var leak_node = _get_target_node(path_val)
		if leak_node != null:
			if leak_node.has_method("trigger_leak"):
				leak_node.call("trigger_leak")
			if leak_node is Spatial:
				explosion_pos = (leak_node as Spatial).global_transform.origin
			_activated_leak_paths.append(path_val)

	last_explosion_pos = explosion_pos
	focus_last_explosion()
	_instantiate_explosion_effect(last_explosion_pos)
	_play_explosion_sound()

	return last_explosion_pos


func _play_explosion_sound() -> void:
	# La primera explosión suena a RuptureSound (grande); las siguientes, a AftershockSound
	# (más chica). _activated_leak_paths ya cuenta explosiones reales (con fuga), así que
	# no hace falta un contador propio que se desincronice en restore_snapshot().
	var sound_node_name := "RuptureSound" if _activated_leak_paths.size() <= 1 else "AftershockSound"
	var sound = get_node_or_null(sound_node_name)
	if sound and sound.has_method("play"):
		sound.global_transform.origin = last_explosion_pos
		sound.play()


func focus_last_explosion() -> void:
	if rupture_focus_path == null or rupture_focus_path.is_empty():
		var focus_node = get_node_or_null("RuptureFocus")
		if focus_node is Spatial:
			focus_node.global_transform.origin = last_explosion_pos
		return

	var focus_target = get_node_or_null(rupture_focus_path)
	if focus_target is Spatial:
		focus_target.global_transform.origin = last_explosion_pos


func crossfade_heartbeat() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("crossfade_to_song"):
		am.crossfade_to_song("Mechanical Heartbeat.mp3", 4.0, -12.0)


# --- INTERNAL HELPERS ---

func _prepare_leaks() -> void:
	_activated_leak_paths = []
	_pending_leak_paths = []

	var seeder: Node = _get_target_node(leak_seeder_path)
	if seeder == null:
		var parent: Node = get_parent()
		seeder = parent.get_node_or_null("RandomLeakSeeder") if parent != null else null

	if seeder != null and seeder.has_method("get_active_leak_paths"):
		var selected_paths: Array = seeder.call("get_active_leak_paths")
		for path_value in selected_paths:
			_pending_leak_paths.append(NodePath(str(path_value)))


func _instantiate_explosion_effect(pos: Vector3) -> void:
	if explosion_scene == null or get_tree() == null:
		return

	var world_parent: Node = get_tree().current_scene
	if world_parent == null:
		world_parent = get_tree().root

	var explosion: Node = explosion_scene.instance()
	world_parent.add_child(explosion)

	if explosion is Spatial:
		explosion.global_transform.origin = pos
		explosion.scale = Vector3.ONE * explosion_scale

	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.9
	explosion.add_child(timer)
	timer.connect("timeout", explosion, "queue_free")
	timer.start()


func _get_target_node(path_val) -> Node:
	if path_val == null:
		return null
	var np: NodePath
	if path_val is NodePath:
		np = path_val
	elif path_val is String:
		if path_val == "":
			return null
		np = NodePath(path_val)
	else:
		return null
	if np.is_empty():
		return null

	var n = get_node_or_null(np)
	if n != null:
		return n
	var parent = get_parent()
	if parent != null:
		n = parent.get_node_or_null(np)
		if n != null:
			return n
	return null


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	var activated_str: Array = []
	for p in _activated_leak_paths:
		activated_str.append(str(p))
	var pending_str: Array = []
	for p in _pending_leak_paths:
		pending_str.append(str(p))

	return {
		"consumed": consumed,
		"last_explosion_pos": [last_explosion_pos.x, last_explosion_pos.y, last_explosion_pos.z],
		"activated_leak_paths": activated_str,
		"pending_leak_paths": pending_str
	}


func restore_snapshot(data: Dictionary) -> void:
	consumed = bool(data.get("consumed", false))

	if data.has("last_explosion_pos") and data["last_explosion_pos"] is Array and data["last_explosion_pos"].size() == 3:
		var raw_pos = data["last_explosion_pos"]
		last_explosion_pos = Vector3(float(raw_pos[0]), float(raw_pos[1]), float(raw_pos[2]))

	_activated_leak_paths = []
	if data.has("activated_leak_paths") and data["activated_leak_paths"] is Array:
		for p in data["activated_leak_paths"]:
			_activated_leak_paths.append(NodePath(str(p)))

	_pending_leak_paths = []
	if data.has("pending_leak_paths") and data["pending_leak_paths"] is Array:
		for p in data["pending_leak_paths"]:
			_pending_leak_paths.append(NodePath(str(p)))

	if consumed:
		for p in _activated_leak_paths:
			var leak_node = _get_target_node(p)
			if leak_node != null and leak_node.has_method("trigger_leak"):
				leak_node.call("trigger_leak")
		focus_last_explosion()
