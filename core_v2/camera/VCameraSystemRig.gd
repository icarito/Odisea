extends Spatial
class_name VCameraSystemRig

export(float, 0.05, 2.0) var rebind_interval := 0.25
export(bool) var bind_follow_target := false
export(bool) var bind_lookat_target := true
export(bool) var log_bind_debug := true

var _player: Spatial = null
var _rebind_elapsed := 0.0
var _targets_bound := false

func _ready():
	yield(get_tree(), "idle_frame")
	_try_bind_targets()

func _physics_process(delta: float) -> void:
	if _targets_bound and is_instance_valid(_player):
		return
	_rebind_elapsed += max(0.0, delta)
	if _rebind_elapsed < rebind_interval:
		return
	_rebind_elapsed = 0.0
	_try_bind_targets()

func _try_bind_targets() -> void:
	_player = _find_player()
	if not is_instance_valid(_player):
		_targets_bound = false
		return

	var player_path := _player.get_path()

	for vcam in $VCameras.get_children():
		if vcam is Spatial and not vcam.has_meta("scene_vcam_transform"):
			vcam.set_meta("scene_vcam_transform", (vcam as Spatial).global_transform)

		var follow = vcam.get_node_or_null("Follow")
		if follow and "target_path" in follow and not vcam.has_meta("scene_follow_target_path"):
			vcam.set_meta("scene_follow_target_path", follow.target_path)
		if follow and "target" in follow:
			if bind_follow_target:
				follow.target = _player
			else:
				follow.target = null

		var look_at = vcam.get_node_or_null("LookAt")
		if look_at and "look_at_target" in look_at and not vcam.has_meta("scene_look_at_target"):
			vcam.set_meta("scene_look_at_target", look_at.look_at_target)
		if look_at and "look_at_target" in look_at:
			if bind_lookat_target:
				look_at.look_at_target = player_path
				if vcam is Spatial:
					var look_offset: Vector3 = look_at.look_at_offset if "look_at_offset" in look_at else Vector3.ZERO
					(vcam as Spatial).look_at(_player.global_transform.origin + look_offset, Vector3.UP)
			else:
				look_at.look_at_target = NodePath("")

		if log_bind_debug and vcam is Spatial:
			var p: Vector3 = (vcam as Spatial).global_transform.origin
			print("[VCameraSystemRig] Bound %s pos=(%.2f, %.2f, %.2f) follow=%s lookat=%s player=(%.2f, %.2f, %.2f)" % [
				vcam.name,
				p.x, p.y, p.z,
				str(bind_follow_target),
				str(bind_lookat_target),
				_player.global_transform.origin.x,
				_player.global_transform.origin.y,
				_player.global_transform.origin.z
			])

	_targets_bound = true

func _find_player() -> Spatial:
	var players = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if candidate is Spatial and is_instance_valid(candidate):
			return candidate as Spatial
	return null
