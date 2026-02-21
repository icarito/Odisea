extends Spatial
class_name VCameraSystemRig

func _ready():
	yield(get_tree(), "idle_frame")
	_setup_follow_targets()

func _setup_follow_targets():
	var players = get_tree().get_nodes_in_group("player")
	if players.empty():
		push_warning("[VCameraSystem] No player found in group 'player'")
		return
	
	var player = players[0]
	
	for vcam in $VCameras.get_children():
		var follow = vcam.get_node_or_null("Follow")
		if follow and "follow_target" in follow:
			follow.follow_target = player.get_path()
		
		var look_at = vcam.get_node_or_null("LookAt")
		if look_at and "look_at_target" in look_at:
			look_at.look_at_target = player.get_path()
