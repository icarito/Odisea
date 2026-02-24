extends Spatial

func _enter_tree() -> void:
	# RL wrapper: remove heavy intro/cinematic systems from BaseTerrace instance.
	_disable_node("Terrace/OYSComponent")
	_disable_node("Terrace/CameraZone")
	_disable_node("Terrace/VCameraSystem")
	_disable_node("Terrace/ShaderWarmupTrigger")

func _disable_node(path: String) -> void:
	var node = get_node_or_null(path)
	if node:
		node.queue_free()
