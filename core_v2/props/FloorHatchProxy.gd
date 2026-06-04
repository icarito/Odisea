extends Spatial
tool

# Configurable hatch opening size. Adjusts the door and hole at runtime.
# Default matches FloorHatch.tscn geometry (2.8 unit square opening).
export(float) var hatch_size := 2.8 setget set_hatch_size

func set_hatch_size(v: float):
	hatch_size = max(0.5, v)
	if is_inside_tree():
		_apply_hatch_size()

func _ready():
	_apply_hatch_size()

func _apply_hatch_size():
	var door = get_node_or_null("HatchDoor")
	if door:
		door.size = Vector3(hatch_size, 0.12, hatch_size)
		door.slide_vector = Vector3(hatch_size + 0.4, 0, 0)

	var hole = get_node_or_null("Frame/Floor/Hole")
	if hole and hole is CSGBox:
		hole.width = hatch_size
		hole.depth = hatch_size

func interact():
	if has_node("ValveWheel"):
		$ValveWheel.interact()
