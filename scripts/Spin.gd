extends Spatial
export var speed: float = 0.7

func _ready():
	var anim = $PilotModel/AnimationPlayer
	var swim_idle_anim = anim.get_animation("Swim_Idle_Loop")
	if swim_idle_anim:
		swim_idle_anim.loop = true
		anim.play("Swim_Idle_Loop")

func _process(delta):
	$PilotModel.rotate_y(speed * delta * 0.2)
