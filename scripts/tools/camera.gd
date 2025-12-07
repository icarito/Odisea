extends Node

func _input(event):
	print("hola")
	if Input.is_action_just_pressed("ui_accept"):  # Enter
		var cam = get_viewport().get_camera()
		if cam:
			print("Pos: ", cam.global_transform.origin)
			print("Rot: ", cam.global_transform.basis.get_euler())
