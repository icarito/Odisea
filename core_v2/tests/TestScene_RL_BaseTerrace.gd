extends Spatial

# Curated safe spawn/target positions for BaseTerrace RL training.
# The open terrace floor is roughly at y=2.04, centered around x=5, z=15.
# We override spawn pos and target radius via env vars in train_anna_cuda_big.py,
# but this script also forces strip of heavy nodes that would slow down RL.

const RL_SPAWN_POS = Vector3(5.0, 2.5, 15.0) # Open terrace, clear floor
const RL_TARGET_Y = 2.0 # Floor level

func _enter_tree() -> void:
	_disable_qodot_for_rl()
	_strip_heavy_runtime_nodes()
	call_deferred("_strip_heavy_runtime_nodes")

func _ready() -> void:
	_disable_qodot_for_rl()
	call_deferred("_strip_heavy_runtime_nodes")
	# Override AnnaInterface spawn/target config if running in RL mode.
	var is_rl = OS.get_environment("ANNA_RL_MODE") in ["1", "true", "True"]
	if is_rl:
		call_deferred("_configure_rl_spawn")

func _disable_qodot_for_rl() -> void:
	var is_rl = OS.get_environment("ANNA_RL_MODE").to_lower() in ["1", "true", "yes", "on"]
	if not is_rl:
		return
	var disable_qodot = OS.get_environment("ANNA_RL_DISABLE_QODOT").to_lower()
	if disable_qodot != "" and not (disable_qodot in ["1", "true", "yes", "on"]):
		return

	var qodot_node = get_node_or_null("Terrace/Building/QodotMap")
	if not is_instance_valid(qodot_node):
		return

	# BaseTerrace already stores the generated geometry/colliders in-scene.
	# In RL we don't need editor-time Qodot behavior.
	if "auto_build" in qodot_node:
		qodot_node.auto_build = false
	qodot_node.set_process(false)
	qodot_node.set_physics_process(false)
	qodot_node.set_process_input(false)
	qodot_node.set_process_unhandled_input(false)

func _configure_rl_spawn() -> void:
	# Find the AnnaInterface node and set its spawn/target config for BaseTerrace.
	# Only override if the user hasn't set explicit env vars already.
	var interface = _find_anna_interface(self)
	if not is_instance_valid(interface):
		return

	# Spawn pos: use env override if set, else use the scene-specific safe pos.
	var sx = OS.get_environment("ANNA_RL_SPAWN_X")
	var sy = OS.get_environment("ANNA_RL_SPAWN_Y")
	var sz = OS.get_environment("ANNA_RL_SPAWN_Z")
	if not sx.is_valid_float() and not sy.is_valid_float() and not sz.is_valid_float():
		interface._rl_spawn_pos = RL_SPAWN_POS
		print("[TestScene_RL_BaseTerrace] RL spawn overridden to %s" % RL_SPAWN_POS)

	# Target Y: use env override if set, else use scene floor height.
	var tr_y = OS.get_environment("ANNA_RL_TARGET_Y")
	if not tr_y.is_valid_float():
		interface._rl_target_fixed_y = RL_TARGET_Y

func _find_anna_interface(root: Node) -> Node:
	for child in root.get_children():
		if child is AnnaInterface:
			return child
		var found = _find_anna_interface(child)
		if found:
			return found
	return null

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
		_soft_disable_node(node)

func _disable_nodes_named(root: Node, target_name: String) -> void:
	if not root:
		return
	for child in root.get_children():
		if child.name == target_name:
			_soft_disable_node(child)
		_disable_nodes_named(child, target_name)

func _disable_group(group_name: String) -> void:
	var tree = get_tree()
	if not tree:
		return
	var nodes = tree.get_nodes_in_group(group_name)
	for node in nodes:
		if is_instance_valid(node):
			_soft_disable_node(node)

func _soft_disable_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	if node is Area:
		(node as Area).monitoring = false
		(node as Area).monitorable = false
	if node is AnimationPlayer:
		(node as AnimationPlayer).stop()
	if node is Spatial:
		(node as Spatial).visible = false
	for child in node.get_children():
		_soft_disable_node(child)
