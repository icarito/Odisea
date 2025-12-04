extends Spatial
export var speed: float = 0.7

func _ready():
	$PilotModel/AnimationPlayer.play("Swim_Idle_Loop")

func _process(delta):
	$PilotModel.rotate_y(speed * delta)
