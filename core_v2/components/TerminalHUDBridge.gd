extends Spatial
class_name TerminalHUDBridge

# TerminalHUDBridge.gd - Bridge between TerminalUI and HelmetHUDV2
# Extracted from HoloTerminalV2 for cleaner architecture and reusability.

signal hud_attached()
signal hud_detached()

export(bool) var attach_to_active_camera := false
export(bool) var hud_attach_as_child := false
export(float) var hud_attach_transition_time := 0.35
export(NodePath) var hud_attach_target_path := NodePath("ScreenContainer/ScreenMesh")
export(float) var hud_screen_x := 0.5
export(float) var hud_screen_y := 0.7
export(float) var hud_screen_depth := 0.35
export(float) var hud_screen_scale := 0.45
export(float) var hud_interaction_radius := 3.0
export(bool) var hud_auto_close_out_of_range := true
export(bool) var hud_ui_bridge_requires_focus := true
export(bool) var hud_ui_bridge_use_system_mouse := true
export(float) var hud_background_alpha := 0.15
export(float) var hud_background_emission := 3.0
export(bool) var hud_focus_on_activate := true
export(Vector3) var hud_local_offset := Vector3.ZERO
export(Vector3) var hud_local_rotation_deg := Vector3(0, 180, 0)

var _terminal: Node = null
var _hud_attach_target: Spatial = null
var _hud_anchor_camera: Camera = null
var _hud_original_parent: Node = null
var _hud_original_owner: Node = null
var _hud_original_global_transform := Transform.IDENTITY
var _hud_original_local_transform := Transform.IDENTITY
var _hud_original_parent_is_spatial := false
var _hud_attached := false
var _hud_warned_missing_camera := false
var _hud_attachment_suspended := false
var _hud_transition_active := false
var _hud_transition_t := 0.0
var _hud_transition_from_origin := Vector3.ZERO
var _hud_transition_to_origin := Vector3.ZERO
var _hud_transition_target_basis := Basis.IDENTITY
var _hud_last_particle_dir := Vector3.ZERO

func _ready():
	pass

func initialize(terminal: Node) -> void:
	_terminal = terminal
	
	if not String(hud_attach_target_path).empty():
		var attach_target = terminal.get_node_or_null(hud_attach_target_path)
		if attach_target and attach_target is Spatial:
			_hud_attach_target = attach_target as Spatial
	
	if _hud_attach_target == null:
		var default_target = terminal.get_node_or_null("ScreenContainer/ScreenMesh")
		if default_target and default_target is Spatial:
			_hud_attach_target = default_target as Spatial

func attach_hud() -> void:
	if not attach_to_active_camera:
		return
	
	var active_camera = _resolve_active_camera()
	if not active_camera:
		if not _hud_warned_missing_camera:
			push_warning("[TerminalHUDBridge] Could not attach HUD: active camera not found.")
			_hud_warned_missing_camera = true
		return
	
	_hud_warned_missing_camera = false
	_attach_to_camera(active_camera, true)
	emit_signal("hud_attached")

func detach_hud() -> void:
	if not _hud_attached:
		return

	_reset_hud_particles()
	var attach_target = _get_hud_attach_target()
	if attach_target == null:
		return

	var original_parent = _hud_original_parent
	if original_parent and is_instance_valid(original_parent):
		var parent = attach_target.get_parent()
		if parent:
			parent.remove_child(attach_target)
		original_parent.add_child(attach_target)
		attach_target.owner = _hud_original_owner
		if _hud_original_parent_is_spatial:
			attach_target.transform = _hud_original_local_transform
		else:
			attach_target.global_transform = _hud_original_global_transform

	_hud_anchor_camera = null
	_hud_attached = false
	_hud_transition_active = false
	_hud_transition_t = 0.0
	_hud_original_parent = null
	_hud_original_owner = null
	_hud_original_global_transform = Transform.IDENTITY
	_hud_original_local_transform = Transform.IDENTITY
	_hud_original_parent_is_spatial = false
	emit_signal("hud_detached")

func is_hud_attached() -> bool:
	return _hud_attached

func set_suspended(suspended: bool) -> void:
	_hud_attachment_suspended = suspended
	if suspended:
		_hud_transition_active = false
		_hud_transition_t = 0.0

func is_player_within_hud_radius() -> bool:
	if hud_interaction_radius <= 0.0:
		return true
	var player = _find_player()
	if player == null:
		return true
	if not (player is Spatial):
		return true
	var dist = _terminal.global_transform.origin.distance_to((player as Spatial).global_transform.origin) if _terminal else 0.0
	return dist <= hud_interaction_radius

func _physics_process(delta: float) -> void:
	if not attach_to_active_camera:
		return
	if not _terminal or not ("is_active" in _terminal and _terminal.is_active):
		return
	if _hud_attachment_suspended:
		return
	
	if hud_auto_close_out_of_range and not is_player_within_hud_radius():
		if _terminal and _terminal.has_method("set_active"):
			_terminal.set_active(false)
		return
	
	_sync_hud_attachment()
	_update_hud_particle_flow()

func _sync_hud_attachment() -> void:
	var active_camera = _resolve_active_camera()
	if not active_camera:
		if not _hud_warned_missing_camera:
			push_warning("[TerminalHUDBridge] HUD mode active but no camera was found.")
			_hud_warned_missing_camera = true
		return

	_hud_warned_missing_camera = false
	if active_camera != _hud_anchor_camera or not _hud_attached:
		_attach_to_camera(active_camera)
	elif not hud_attach_as_child:
		_apply_hud_world_transform(active_camera)

func _attach_to_camera(active_camera: Camera, animate := false) -> void:
	var attach_target = _get_hud_attach_target()
	if attach_target == null:
		return
	var world_before = attach_target.global_transform

	if not _hud_attached:
		_hud_original_parent = attach_target.get_parent()
		_hud_original_owner = attach_target.owner
		_hud_original_global_transform = attach_target.global_transform
		if _hud_original_parent and _hud_original_parent is Spatial:
			_hud_original_parent_is_spatial = true
			_hud_original_local_transform = attach_target.transform
		else:
			_hud_original_parent_is_spatial = false
		_hud_attached = true

	_hud_anchor_camera = active_camera
	_reset_hud_particles()
	if hud_attach_as_child:
		var parent = attach_target.get_parent()
		if parent != active_camera:
			if parent:
				parent.remove_child(attach_target)
			active_camera.add_child(attach_target)
			attach_target.owner = null
		var target_local = _build_hud_target_local_transform(active_camera)
		if animate and hud_attach_transition_time > 0.0:
			var start_local = active_camera.global_transform.affine_inverse() * world_before
			_hud_transition_from_origin = start_local.origin
			_hud_transition_to_origin = target_local.origin
			_hud_transition_target_basis = target_local.basis.orthonormalized()
			_hud_transition_t = 0.0
			_hud_transition_active = true
			attach_target.transform.basis = _hud_transition_target_basis
			attach_target.transform.origin = _hud_transition_from_origin
		else:
			_hud_transition_active = false
			attach_target.transform = target_local
	else:
		_hud_transition_active = false
		_apply_hud_world_transform(active_camera)

func _resolve_active_camera() -> Camera:
	var viewport = get_viewport()
	if viewport:
		var viewport_camera = viewport.get_camera()
		if viewport_camera:
			return viewport_camera

	var player = _find_player()
	if player:
		var player_camera = player.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera")
		if player_camera and player_camera is Camera:
			return player_camera as Camera

	var scene_root = get_tree().current_scene if get_tree() else null
	if scene_root:
		var current_camera = _find_current_camera_recursive(scene_root)
		if current_camera:
			return current_camera

	return null

func _find_current_camera_recursive(node: Node) -> Camera:
	if node is Camera and (node as Camera).current:
		return node as Camera
	for child in node.get_children():
		var current_camera = _find_current_camera_recursive(child)
		if current_camera:
			return current_camera
	return null

func _build_hud_reference_local_transform(active_camera: Camera) -> Transform:
	var depth_t = clamp(hud_screen_depth, 0.0, 1.0)
	var fov_deg = 70.0
	var aspect = 16.0 / 9.0
	var near_plane = 0.05
	if active_camera:
		fov_deg = active_camera.fov
		near_plane = active_camera.near
		var view = active_camera.get_viewport()
		if view and view.size.y > 0.0:
			aspect = view.size.x / view.size.y
	var min_distance = max(0.07, near_plane + 0.03)
	var max_distance = max(min_distance + 0.01, 0.55)
	var distance = lerp(min_distance, max_distance, depth_t)
	var half_height = tan(deg2rad(fov_deg) * 0.5) * distance
	var half_width = half_height * aspect
	var local_x = lerp(-half_width, half_width, clamp(hud_screen_x, 0.0, 1.0))
	var local_y = lerp(half_height, -half_height, clamp(hud_screen_y, 0.0, 1.0))
	var local_z = -distance
	var scale_t = clamp(hud_screen_scale, 0.0, 1.0)
	var scale_factor = lerp(0.08, 2.4, scale_t)

	var basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.RIGHT, deg2rad(hud_local_rotation_deg.x))
	basis = basis.rotated(Vector3.UP, deg2rad(hud_local_rotation_deg.y))
	basis = basis.rotated(Vector3.BACK, deg2rad(hud_local_rotation_deg.z))
	basis = basis.scaled(Vector3.ONE * scale_factor)
	return Transform(basis, Vector3(local_x, local_y, local_z) + hud_local_offset)

func _build_hud_target_local_transform(active_camera: Camera) -> Transform:
	return _build_hud_reference_local_transform(active_camera)

func _get_hud_attach_target() -> Spatial:
	if _hud_attach_target and is_instance_valid(_hud_attach_target):
		return _hud_attach_target
	return null

func _apply_hud_world_transform(active_camera: Camera) -> void:
	var attach_target = _get_hud_attach_target()
	if attach_target == null:
		return
	var target_local = _build_hud_target_local_transform(active_camera)
	attach_target.global_transform = active_camera.global_transform * target_local

func _step_hud_transition(delta: float) -> void:
	if not hud_attach_as_child:
		_hud_transition_active = false
		return
	var attach_target = _get_hud_attach_target()
	if attach_target == null:
		_hud_transition_active = false
		return
	if hud_attach_transition_time <= 0.0:
		_hud_transition_active = false
		return

	_hud_transition_t = min(1.0, _hud_transition_t + (delta / hud_attach_transition_time))
	var eased_t = 1.0 - pow(1.0 - _hud_transition_t, 3.0)
	attach_target.transform.basis = _hud_transition_target_basis
	attach_target.transform.origin = _hud_transition_from_origin.linear_interpolate(_hud_transition_to_origin, eased_t)
	if _hud_transition_t >= 1.0:
		_hud_transition_active = false

func _update_hud_particle_flow() -> void:
	if not _terminal:
		return
	var particles = _terminal.get_node_or_null("HoloParticles")
	var target = _get_hud_attach_target()
	if not particles or not target or not particles.emitting:
		return
	particles.local_coords = false
	var from = particles.global_transform.origin
	var to = target.global_transform.origin
	var flow_dir = (to - from)
	if flow_dir.length_squared() < 0.0001:
		return
	var dist = flow_dir.length()
	var flow_normal = flow_dir / dist
	particles.randomness = 0.0
	particles.lifetime_randomness = 0.0
	particles.initial_velocity_random = 0.0
	particles.spread = 0.0
	particles.radial_accel = 0.0
	particles.gravity = Vector3.ZERO
	if _hud_last_particle_dir.length_squared() > 0.0 and _hud_last_particle_dir.dot(flow_normal) < 0.99:
		if particles.has_method("restart"):
			particles.restart()
	_hud_last_particle_dir = flow_normal
	particles.direction = flow_normal
	var stop_distance = max(0.02, dist - 0.16)
	var speed = clamp(stop_distance * 12.0, 1.2, 14.0)
	particles.initial_velocity = speed
	particles.lifetime = clamp(stop_distance / speed, 0.03, 0.10)

func _reset_hud_particles() -> void:
	if not _terminal:
		return
	var particles = _terminal.get_node_or_null("HoloParticles")
	if not particles:
		return
	_hud_last_particle_dir = Vector3.ZERO
	var was_emitting = particles.emitting
	particles.emitting = false
	if particles.has_method("restart"):
		particles.restart()
	particles.emitting = was_emitting

func _find_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func get_capture_nodes() -> Array:
	var nodes := []
	var target = _get_hud_attach_target()
	if attach_to_active_camera and target and is_instance_valid(target) and target != self and target.get_parent() != self:
		nodes.append(target)
	return nodes
