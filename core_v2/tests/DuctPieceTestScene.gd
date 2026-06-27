tool
extends Spatial

# FD-053: Test piece generator
const DuctMazeStreamerFlat = preload("res://core_v2/systems/DuctMazeStreamerFlat.gd")

func _ready():
	# Clear existing children to avoid duplicates in tool mode
	for child in get_children():
		if child is Spatial and not (child.name == "Floor" or child.name == "Pilot" or child.name == "DirectionalLight"):
			child.queue_free()

	# In runtime, always generate. In editor, skip if already have labels.
	if Engine.editor_hint and has_node("E_Label"):
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
		# Offset: W at origin, others to the right, E furthest left
		var offset_x = (i - 2) * 10.0
		add_child(tile)
		tile.translation = Vector3(offset_x, 0, 0)

		var label = Label3D.new()
		label.name = type + "_Label"
		label.text = type
		label.translation = Vector3(offset_x, 5.0, 0)
		label.pixel_size = 0.02
		add_child(label)

	streamer.free()
