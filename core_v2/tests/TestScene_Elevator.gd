extends Spatial

func _ready():
    # Force test camera to be current, overriding PropStage or Player
    if has_node("Camera"):
        $Camera.make_current()

    pass
