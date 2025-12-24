extends GdUnitTestSuite

const TEST_REPLAY_PATH = "res://tests/fixtures/reference.json"
const FIXED_DELTA = 1.0 / 60.0

func before():
	# ensure replay data exists
	var data = ReplayUtils.load_json(TEST_REPLAY_PATH)
	assert_that(data).is_not_null()

func test_frame_perfect_sync():
	var data = ReplayUtils.load_json(TEST_REPLAY_PATH)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		fail("Replay data missing or not a Dictionary: " + TEST_REPLAY_PATH)
		return

	# spawn player scene (adjust path if your project differs)
	var player_scene = load("res://players/elias/Pilot.tscn")
	assert_that(player_scene).is_not_null()
	var player = player_scene.instance()
	add_child(player)

	# Apply initial player pos and camera state from initials
	var initial_states = data.get("initial_states", null)
	if initial_states != null and typeof(initial_states) == TYPE_DICTIONARY:
		if initial_states.has("player"):
			var p = initial_states.get("player")
			if p and typeof(p) == TYPE_DICTIONARY and p.has("player_position"):
				player.global_transform.origin = ReplayUtils.dict_to_vector3(p.get("player_position"))
			if p and typeof(p) == TYPE_DICTIONARY and p.has("rotation"):
				player.rotation = ReplayUtils.dict_to_vector3(p.get("rotation"))
		if initial_states.has("camera"):
			var cam_state = initial_states.get("camera")
			if player.has_node("CameraRig") and player.get_node("CameraRig").has_method("set_replay_state"):
				player.get_node("CameraRig").set_replay_state(cam_state)

	# Run a short critical loop of frames, applying camera update BEFORE player physics
	var frames = data.get("frames", [])
	for i in range(min(10, frames.size())):
		var frame = frames[i]
		# Ensure mouse delta is provided in a dictionary {x,y}
		var md = frame.get("mouse_delta", {"x": 0, "y": 0})
		var md_vec = Vector2(FixedPoint.from_fixed(md.get("x",0)), FixedPoint.from_fixed(md.get("y",0))) if md is Dictionary else (md if md is Vector2 else Vector2.ZERO)

		# Step A: Rotate camera first (force immediate)
		var cam = null
		if player.has_node("CameraRig"):
			cam = player.get_node("CameraRig")
		elif get_tree().get_current_scene() and get_tree().get_current_scene().has_node("CameraRig"):
			cam = get_tree().get_current_scene().get_node("CameraRig")
		if cam and cam.has_method("force_rotate_for_playback"):
			cam.force_rotate_for_playback(md_vec)
			if cam.has_method("force_update_transform"):
				cam.force_update_transform()
			elif cam.has_method("update_camera_transform"):
				cam.update_camera_transform()

		# Step B: Inject inputs and run player physics
		if player.has_node("PlayerInput"):
			player.get_node("PlayerInput").inject_input(frame.inputs)
		player._physics_process(FIXED_DELTA)

		# Step C: Compare position against expected if present
		if frame.has("expected_pos"):
			var expected = ReplayUtils.dict_to_vector3(frame.expected_pos)
			assert_vector3(player.global_transform.origin).is_equal_approx(expected, Vector3(0.001, 0.001, 0.001))

func after():
	# free all players
	for c in get_children():
		if c and is_instance_valid(c) and c.name == "Pilot":
			c.free()
