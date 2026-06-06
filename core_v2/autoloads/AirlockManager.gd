extends Node

# AirlockManager — FD-053
#
# Keeps the player node and AirlockChamber alive across scene transitions by
# reparenting them to this autoload (which lives under /root and is never freed).
#
# Flow:
#   1. AirlockZoneV2 calls notify_transition() just before goto_scene().
#      We connect to SceneManager.pre_scene_swap so we can lift the player out
#      of the old scene before it is queue_free()d.
#   2. On pre_scene_swap: reparent player (+ active chamber) to self.
#      The player stays in the scene tree under /root/AirlockManager — physics,
#      get_tree(), autoload lookups all continue to work.
#   3. SceneManager destroys old scene, loads new scene, emits scene_ready.
#   4. On scene_ready: reparent player + chamber into the new scene root.
#      SessionManager.apply_scene_transition_state() then finds the player
#      normally and applies spawn / camera state.

signal exterior_paused()
signal exterior_resumed()

var _pending_transition := false
var _seamless_swap := false  # true while SceneManager should use add-before-free order
var _player_held: Node = null
var _airlock_held: Node = null

var _exterior_scene: Node = null
var _exterior_paused := false


func _ready() -> void:
	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager:
		scene_manager.connect("pre_scene_swap", self, "_on_pre_scene_swap")
		scene_manager.connect("pre_spawn_state", self, "_on_pre_spawn_state")
	set_process(false)


func _process(_delta: float) -> void:
	# While holding the player, keep its camera current every frame so the
	# viewport never goes black during the scene swap.
	if is_instance_valid(_player_held) and _player_held.has_method("force_camera_current"):
		_player_held.force_camera_current()
	else:
		set_process(false)


# Called by AirlockZoneV2 just before it calls SceneManager.goto_scene().
func notify_transition(target_scene: String) -> void:
	_pending_transition = true
	_seamless_swap = true

	var going_to_interior := not _is_exterior_scene(target_scene)

	if going_to_interior:
		# Remember the exterior before it gets destroyed
		var current_scene = get_tree().current_scene
		if is_instance_valid(current_scene) and _is_exterior_scene(current_scene.filename):
			_exterior_scene = current_scene


func _on_pre_scene_swap(old_scene: Node, _new_scene: Node, _params: Dictionary) -> void:
	if not _pending_transition:
		return
	_pending_transition = false

	var active_airlock := _find_active_airlock_in(old_scene)
	if is_instance_valid(active_airlock):
		var airlock_parent := active_airlock.get_parent()
		if is_instance_valid(airlock_parent):
			airlock_parent.remove_child(active_airlock)
		add_child(active_airlock)
		_airlock_held = active_airlock

	# Lift player out of old scene so queue_free() doesn't destroy it
	var player := _find_player_in(old_scene)
	if is_instance_valid(player):
		# Reparent: add to self FIRST so the camera is never momentarily out of the tree.
		# Godot allows a node to have only one parent — remove_child must come first,
		# but we assert camera current immediately after to cover the one-frame gap.
		var old_parent := player.get_parent()
		if is_instance_valid(old_parent):
			old_parent.remove_child(player)
		add_child(player)
		_player_held = player
		_seamless_swap = false
		# Re-assert camera immediately and deferred (covers both the current frame and
		# the next, since Godot clears camera.current during _notification(ENTER_TREE)).
		if player.has_method("force_camera_current"):
			player.force_camera_current()
			player.call_deferred("force_camera_current")
		set_process(true)


func _on_pre_spawn_state(path: String, scene_root: Node, _params: Dictionary) -> void:
	if not is_instance_valid(scene_root):
		return

	# Update exterior reference after a reload
	if _is_exterior_scene(path):
		_exterior_scene = scene_root
		if _exterior_paused:
			_resume_exterior()

	if is_instance_valid(_airlock_held):
		var airlock := _airlock_held
		_airlock_held = null
		if airlock.get_parent() == self:
			remove_child(airlock)
		_rename_held_airlock_for_target(airlock, _params)
		scene_root.add_child(airlock)
		if _params is Dictionary:
			_params["_airlock_manager_placed"] = true

	# Place player back into the new scene BEFORE apply_spawn_and_state runs,
	# so SessionManager can find it and apply spawn/camera correctly.
	if is_instance_valid(_player_held):
		set_process(false)
		var player := _player_held
		_player_held = null
		remove_child(player)
		scene_root.add_child(player)
		if player.has_method("force_camera_current"):
			player.force_camera_current()
			player.call_deferred("force_camera_current")
		# Zero out velocity so physics doesn't continue with pre-transition momentum.
		if "velocity" in player:
			player.velocity = Vector3.ZERO
		# Activate snap frames so KinematicBody adheres to the floor without micro-bounce,
		# and so is_effectively_grounded() returns true to suppress animator state flicker.
		if "_post_teleport_snap_frames" in player:
			player._post_teleport_snap_frames = 8
		# Freeze animator state updates so scene-transition physics noise doesn't
		# trigger a mid-air animation while the player settles into the new scene.
		var animator := _find_animator_in(player)
		if is_instance_valid(animator) and "_transition_freeze_frames" in animator:
			animator._transition_freeze_frames = 8
		# Snap camera arm to the actual collision geometry in the new scene so it
		# doesn't violently retract from spring_length on the first frame.
		# Grant a brief collision grace so jitter from the freeze frames doesn't
		# cause the arm to bounce between wall and open air.
		if player.has_method("snap_camera_to_current_state"):
			player.call_deferred("snap_camera_to_current_state")
		if "_camera_collision_grace_left" in player:
			player._camera_collision_grace_left = max(player._camera_collision_grace_left, 0.35)
		if _params is Dictionary:
			_params["_airlock_manager_placed"] = true

func _find_animator_in(player: Node) -> Node:
	if not is_instance_valid(player):
		return null
	return player.find_node("PilotAnimatorV2", true, false)


func _find_player_in(scene_root: Node) -> Node:
	if not is_instance_valid(scene_root):
		return null
	# SessionManager holds the canonical player reference
	var session := get_node_or_null("/root/SessionManager")
	if session and is_instance_valid(session.player) and scene_root.is_a_parent_of(session.player):
		return session.player
	# Fallback: first group member that is a child of this scene
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and scene_root.is_a_parent_of(p):
			return p
	return scene_root.find_node("Pilot", true, false)

func _find_active_airlock_in(scene_root: Node) -> Node:
	if not is_instance_valid(scene_root):
		return null
	var pending: Array = [scene_root]
	while not pending.empty():
		var node: Node = pending.pop_front()
		if is_instance_valid(node) and node is AirlockControllerV2:
			if node.has_method("is_transition_requested") and bool(node.is_transition_requested()):
				return node
			var state = node.get("state")
			if state != null and int(state) == int(AirlockControllerV2.State.PRESSURIZING):
				return node
		for child in node.get_children():
			pending.push_back(child)
	return null

func _rename_held_airlock_for_target(airlock: Node, params: Dictionary) -> void:
	if not is_instance_valid(airlock) or typeof(params) != TYPE_DICTIONARY:
		return
	var state_data = params.get("state_data", {})
	if typeof(state_data) != TYPE_DICTIONARY:
		return
	var target_path := String(state_data.get("target_airlock_path", "")).strip_edges()
	if target_path == "":
		return
	var path := NodePath(target_path)
	var name_count := path.get_name_count()
	if name_count <= 0:
		return
	var target_name := path.get_name(name_count - 1)
	if target_name != "":
		airlock.name = target_name


# --- Exterior streaming pause/resume ---

func _pause_exterior() -> void:
	if not is_instance_valid(_exterior_scene) or _exterior_paused:
		return
	_exterior_paused = true
	if _exterior_scene.has_method("pause_streaming"):
		_exterior_scene.pause_streaming()
	else:
		_exterior_scene.set_process(false)
		_exterior_scene.set_physics_process(false)
	emit_signal("exterior_paused")


func _resume_exterior() -> void:
	if not _exterior_paused:
		return
	_exterior_paused = false
	if is_instance_valid(_exterior_scene):
		if _exterior_scene.has_method("resume_streaming"):
			_exterior_scene.resume_streaming()
		else:
			_exterior_scene.set_process(true)
			_exterior_scene.set_physics_process(true)
	emit_signal("exterior_resumed")


func _is_exterior_scene(scene_path: String) -> bool:
	return "OdiseaExterior" in scene_path
