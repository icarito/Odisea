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
	pass

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
