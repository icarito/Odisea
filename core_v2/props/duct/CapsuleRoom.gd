extends Spatial

# CapsuleRoom.gd - Controls port visibility and collision for the capsule junction

signal port_state_changed(dir, is_open)

onready var port_nodes = {
	0: get_node_or_null("Ports/PortN"),
	1: get_node_or_null("Ports/PortE"),
	2: get_node_or_null("Ports/PortS"),
	3: get_node_or_null("Ports/PortW")
}

func _ready():
	_setup_exit_airlock()

func setup(connections: Array, rotation: int) -> void:
	# connections is an array of bools [N, E, S, W]
	# rotation is usually 0, 90, 180, 270 (or 0-3 index)

	var rot_steps = int(rotation / 90) % 4

	for i in range(4):
		# Map world direction i to local port direction
		var local_dir = (i - rot_steps + 4) % 4

		if i < connections.size() and connections[i]:
			open_port(local_dir)
		else:
			close_port(local_dir)

func open_port(local_dir: int) -> void:
	if port_nodes.has(local_dir) and port_nodes[local_dir]:
		port_nodes[local_dir].visible = false
		emit_signal("port_state_changed", local_dir, true)

func close_port(local_dir: int) -> void:
	if port_nodes.has(local_dir) and port_nodes[local_dir]:
		port_nodes[local_dir].visible = true
		emit_signal("port_state_changed", local_dir, false)

func _setup_exit_airlock() -> void:
	var iris = get_node_or_null("Interior/ExitAirlockIris")
	if not iris:
		return
	_move_static_bodies_to_prop_layer(iris)
	var mechanism = iris.get_node_or_null("IrisMechanism")
	if not mechanism:
		return
	if "interaction_text" in mechanism:
		mechanism.interaction_text = "Operar esclusa"
	if "starts_active" in mechanism:
		mechanism.starts_active = true
	if mechanism.has_method("set_active"):
		mechanism.set_active(true, true)
	_ensure_iris_interaction_area(mechanism)

func _move_static_bodies_to_prop_layer(node: Node) -> void:
	if node is StaticBody:
		if (node.collision_layer & 1) != 0:
			node.collision_layer = 1 << 6
	elif node is CSGCombiner:
		if (node.collision_layer & 1) != 0:
			node.collision_layer = 1 << 6
	for child in node.get_children():
		_move_static_bodies_to_prop_layer(child)

func _ensure_iris_interaction_area(mechanism: Spatial) -> void:
	if mechanism.has_node("InteractionArea"):
		return
	var area := Area.new()
	area.name = "InteractionArea"
	area.collision_layer = 16
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false
	var shape := CollisionShape.new()
	var sphere := SphereShape.new()
	sphere.radius = 1.6
	shape.shape = sphere
	area.add_child(shape)
	mechanism.add_child(area)
