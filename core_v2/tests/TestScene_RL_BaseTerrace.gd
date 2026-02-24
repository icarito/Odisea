extends Spatial

func _enter_tree() -> void:
	_strip_heavy_runtime_nodes()
	call_deferred("_strip_heavy_runtime_nodes")

func _ready() -> void:
	call_deferred("_strip_heavy_runtime_nodes")

func _strip_heavy_runtime_nodes() -> void:
	# RL wrapper: remove heavy intro/cinematic systems from BaseTerrace instance.
	_disable_node("Terrace/OYSComponent")
	_disable_node("Terrace/CameraZone")
	_disable_node("Terrace/CameraZone2")
	_disable_node("Terrace/OcclusionZone")
	_disable_node("Terrace/VCameraSystem")
	_disable_node("Terrace/VCameraBrain")
	_disable_node("Terrace/ShaderWarmupTrigger")
	_disable_nodes_named(self, "ShaderWarmupTrigger")
	_disable_group("CameraZoneV2")
	_disable_group("OcclusionZoneV2")

func _disable_node(path: String) -> void:
	var node = get_node_or_null(path)
	if node:
		node.queue_free()

func _disable_nodes_named(root: Node, target_name: String) -> void:
	if not root:
		return
	for child in root.get_children():
		if child.name == target_name:
			child.queue_free()
		_disable_nodes_named(child, target_name)

func _disable_group(group_name: String) -> void:
	var tree = get_tree()
	if not tree:
		return
	var nodes = tree.get_nodes_in_group(group_name)
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
