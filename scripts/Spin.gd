extends Spatial
export var speed: float = 0.7

func _process(delta):
	$PilotModel.rotate_y(speed * delta)
