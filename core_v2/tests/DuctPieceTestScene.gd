tool
extends Spatial

# FD-053: Test piece generator
const DuctMazeStreamerFlat = preload("res://core_v2/systems/DuctMazeStreamerFlat.gd")

func _ready():
	# Clear existing children to avoid duplicates in tool mode
	for child in get_children():
		if child is Spatial and not (child.name == "Floor" or child.name == "Pilot" or child.name == "DirectionalLight"):
			child.queue_free()

	# Wait a frame for queue_free if in editor? Usually not needed for tool scripts in _ready
	# but let's be safe and just don't add if already there if we can.
	# Actually, better to just check if we already have the labels.
	if has_node("E_Label"):
		return

	var types = ["E", "W", "C", "T", "X"]
	var streamer = DuctMazeStreamerFlat.new()
	streamer.cell_size = 4.0

	for i in range(types.size()):
		var type = types[i]
		var data = {
			"variant": {
				"id": type,
				"rotation": 0,
				"connections": [true, true, true, true],
				"port_heights": [0, 0, 0, 0]
			},
			"base_height": 0.0
		}
		var tile = streamer._instantiate_tile(data)
		tile.name = type + "_Tile"
		add_child(tile)
		tile.translation = Vector3(i * 10.0, 0, 0)

		var label = Label3D.new()
		label.name = type + "_Label"
		label.text = type
		label.translation = Vector3(i * 10.0, 3.0, 0)
		label.billboard = SpatialMaterial.BILLBOARD_ENABLED
		add_child(label)

	streamer.free()
