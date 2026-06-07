extends SceneTree

func _init():
	print("--- FD-160 Test Runner ---")
	var scene = load("res://core_v2/tests/TestFD160_Searchlights.tscn").instance()
	root.add_child(scene)

	var searchlight = scene.get_node("SearchLightV2")
	var camera = scene.get_node("SecurityCameraV2")
	var player = scene.get_node("PlayerProxy")

	# Wait a bit
	yield(create_timer(1.0), "timeout")

	print("Testing Searchlight Sweep...")
	var initial_rot = searchlight.get_node("Head").rotation_degrees.y
	yield(create_timer(1.0), "timeout")
	var new_rot = searchlight.get_node("Head").rotation_degrees.y
	if initial_rot != new_rot:
		print("SUCCESS: Searchlight is sweeping.")
	else:
		print("FAILURE: Searchlight is static.")

	print("Testing Camera Tracking...")
	player.translation = Vector3(0, 1, -5) # Move player in front
	# Manually trigger entry for headless test if physics is flaky
	camera._on_body_entered(player)

	yield(create_timer(1.0), "timeout")
	# Check if camera head is looking towards player
	var to_player = (player.global_transform.origin - camera.get_node("Head").global_transform.origin).normalized()
	var forward = -camera.get_node("Head").global_transform.basis.z
	var dot = forward.dot(to_player)
	print("Camera forward dot player: ", dot)
	if dot > 0.8:
		print("SUCCESS: Camera is tracking player.")
	else:
		print("FAILURE: Camera not tracking player. Dot: ", dot)

	print("Test complete. Quitting in 1s...")
	yield(create_timer(1.0), "timeout")
	quit()
