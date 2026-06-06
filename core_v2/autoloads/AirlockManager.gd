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

	# Do NOT reparent the airlock — it causes cyclic resource references and
	# re-triggers transitions in the destination scene. The destination scene
	# has its own airlock that SessionManager opens via open_exit_door().
	_airlock_held = null

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
		# Pause physics so the player doesn't accumulate airborne time during scene load.
		player.set_physics_process(false)
		var animator := _find_animator_in(player)
		if is_instance_valid(animator):
			animator.set_physics_process(false)
		_seamless_swap = false
		# Freeze the source scene's WorldRotator so it stops following the player
		# (now lifted into the airlock chamber) and does not accumulate rotation
		# that would snap in at scene swap (the [YANK]).
		var source_rotator := _find_world_rotator_in(old_scene)
		if is_instance_valid(source_rotator) and source_rotator.has_method("pause_tracking"):
			source_rotator.pause_tracking()
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

	# Airlock is no longer reparented — handled by destination scene's own airlock.

	# Place player back into the new scene BEFORE apply_spawn_and_state runs,
	# so SessionManager can find it and apply spawn/camera correctly.
	if is_instance_valid(_player_held):
		set_process(false)
		var player := _player_held
		_player_held = null
		# Remove any player already in the new scene to avoid duplicates.
		# Use free() immediately (not queue_free) so references in scene scripts
		# don't access the node after it's gone in the same frame.
		var existing := _find_player_in(scene_root)
		if is_instance_valid(existing) and existing != player:
			var existing_parent := existing.get_parent()
			if is_instance_valid(existing_parent):
				existing_parent.remove_child(existing)
			existing.free()
		# Pre-position the player at the destination airlock BEFORE add_child so
		# the first rendered frame already shows the correct position — avoids a
		# one-frame yank where the player appears at the wrong location.
		_pre_position_at_destination(player, scene_root, _params)
		remove_child(player)
		scene_root.add_child(player)
		# NOTE: tracking is NOT resumed here. The WorldRotator stays paused until the
		# player physically exits the destination airlock chamber — OdiseaExterior
		# drives resume_tracking() from the chamber zone exit. Resuming at scene swap
		# would apply the rotation accumulated during the pause as a yank on arrival.
		# Freeze AFTER add_child so _ready() doesn't stomp the value.
		var animator := _find_animator_in(player)
		if is_instance_valid(animator) and animator.has_method("freeze"):
			animator.call("freeze", 60)
		elif is_instance_valid(animator) and "_transition_freeze_frames" in animator:
			animator._transition_freeze_frames = max(animator._transition_freeze_frames, 60)
		# Re-enable physics now that the player is in the new scene.
		player.set_physics_process(true)
		if is_instance_valid(animator):
			animator.set_physics_process(true)
		if player.has_method("force_camera_current"):
			player.force_camera_current()
			player.call_deferred("force_camera_current")
		# Zero out velocity so physics doesn't continue with pre-transition momentum.
		if "velocity" in player:
			player.velocity = Vector3.ZERO
		# Activate snap frames so KinematicBody adheres to the floor without micro-bounce.
		if "_post_teleport_snap_frames" in player:
			player._post_teleport_snap_frames = 8
		# NOTE: Do NOT call snap_camera_to_current_state here — the player is still at
		# the source airlock position. SessionManager will move the player to the
		# destination and call snap_camera_to_current_state after positioning.
		if "_camera_collision_grace_left" in player:
			player._camera_collision_grace_left = max(player._camera_collision_grace_left, 0.35)
		# Signal to snap_camera_to_current_state that the camera state is
		# already correct — skip any snap that would overwrite it.
		if "_transition_airlock_placed" in player:
			player._transition_airlock_placed = true
		if _params is Dictionary:
			_params["_airlock_manager_placed"] = true

func _pre_position_at_destination(player: Node, scene_root: Node, params: Dictionary) -> void:
	if not is_instance_valid(player) or not is_instance_valid(scene_root):
		return
	if typeof(params) != TYPE_DICTIONARY:
		return
	var state_data = params.get("state_data", {})
	if typeof(state_data) != TYPE_DICTIONARY:
		return
	var relative_transform = state_data.get("airlock_relative_transform", null)
	if typeof(relative_transform) != TYPE_TRANSFORM:
		return
	var target_airlock_path := String(state_data.get("target_airlock_path", "")).strip_edges()
	if target_airlock_path == "":
		return
	var target_airlock := scene_root.get_node_or_null(NodePath(target_airlock_path))
	if not is_instance_valid(target_airlock):
		var path := NodePath(target_airlock_path)
		var name_count := path.get_name_count()
		if name_count > 0:
			target_airlock = scene_root.find_node(path.get_name(name_count - 1), true, false)
	if not is_instance_valid(target_airlock):
		return
	var body_transform: Transform = target_airlock.global_transform * relative_transform
	# Preserve the rotation from relative_transform so the SpringArm points
	# in the correct direction from frame zero.
	player.global_transform = body_transform
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	# Keep the base_spring_length_3d and current_spring_length from the source
	# chamber (AirlockZoneV2 set them to AIRLOCK_OTS_SPRING_LENGTH ~1m).
	# Resetting them to 7 would cause _update_camera_view to lerp from 7 toward
	# 7 (no movement), but the visual framing still changes from chamber-ish (1m)
	# to exterior (7m) instantly on scene swap. By preserving the OTS value, the
	# camera stays at ~1m on arrival and _update_camera_view expands it to
	# exterior defaults gradually over ~0.5s (lerp from 1 to 3.2 with weight 4).
	# Also orient the camera rig to match the destination yaw so the SpringArm
	# points in the correct direction from frame zero.
	var yaw := 0.0
	if typeof(state_data.get("camera_relative_forward", null)) == TYPE_VECTOR3:
		var fwd: Vector3 = target_airlock.global_transform.basis.xform(state_data["camera_relative_forward"])
		fwd.y = 0.0
		if fwd.length_squared() > 0.0001:
			yaw = atan2(-fwd.normalized().x, -fwd.normalized().z)
	elif state_data.has("camera_body_yaw_offset"):
		yaw = body_transform.basis.get_euler().y + float(state_data["camera_body_yaw_offset"])
	elif state_data.has("camera_yaw"):
		yaw = float(state_data["camera_yaw"])
	var pitch := float(state_data.get("camera_pitch", 0.0))
	if "yaw" in player:
		player.yaw = yaw
	if "pitch" in player:
		player.pitch = pitch
	if "camera_rig" in player and is_instance_valid(player.camera_rig):
		player.camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		player.camera_rig.force_update_transform()
	if "_camera_rig_y_initialized" in player:
		player._camera_rig_y_initialized = true

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

func _find_world_rotator_in(scene_root: Node) -> Node:
	if not is_instance_valid(scene_root):
		return null
	var rotator := scene_root.get_node_or_null("WorldRotator")
	if is_instance_valid(rotator):
		return rotator
	return scene_root.find_node("WorldRotator", true, false)


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
