extends MeshInstance3D

@onready var animation = $AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_area_3d_body_entered(body):
	if body is CharacterBody3D:
		animation.play("Open")


func _on_area_3d_body_exited(body):
	if body is CharacterBody3D:
		animation.play_backwards("Open")
