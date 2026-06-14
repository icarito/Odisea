extends SceneTree

# test_interaction_marker_system.gd - Unit tests for Interaction Marker System

func _init() -> void:
	# Add a camera to root so unproject_position works
	var cam := Camera.new()
	root.add_child(cam)
	cam.make_current()
	cam.translation = Vector3(0, 0, 0)
	cam.look_at(Vector3(0, 0, -1), Vector3.UP)

	print("--- Running Interaction Marker System Tests ---")
	test_MarkerPriorityCulling()
	test_MarkerStateTransitions()
	test_OffScreenIndicator()
	print("--- All Tests Completed ---")
	quit()

func test_MarkerPriorityCulling() -> void:
	print("Running test_MarkerPriorityCulling...")
	var im = root.get_node("InteractionMarker")

	# Setup 5 interactables with different priorities
	var nodes := []
	for i in range(5):
		var node = Spatial.new()
		root.add_child(node)
		node.translation = Vector3(0, 0, -5)
		nodes.append(node)

		var config = MarkerConfig.new()
		config.label = "Node " + str(i)
		config.priority = i # 0, 1, 2, 3, 4
		config.interaction_range = 100.0
		im.register(node, config)

	# Mock camera and update
	im._update_markers()

	# Verify that only 3 are visible
	var visible_count = 0
	for node in nodes:
		if im._ui_nodes.has(node) and im._ui_nodes[node].visible:
			visible_count += 1

	assert_true(visible_count <= 3, "Expected max 3 visible markers, got " + str(visible_count))

	# Cleanup
	for node in nodes:
		im.unregister(node)
		node.queue_free()
	print("test_MarkerPriorityCulling passed.")

func test_MarkerStateTransitions() -> void:
	print("Running test_MarkerStateTransitions...")
	var im = root.get_node("InteractionMarker")

	var node = Spatial.new()
	root.add_child(node)
	node.translation = Vector3(0, 0, -5) # In front of camera

	var config = MarkerConfig.new()
	config.label = "Test Node"
	config.interaction_range = 10.0
	config.off_screen = true
	im.register(node, config)

	# Allow some time for debounce or just call update multiple times if needed
	# But here we can just wait or mock the 'now' in IM if we really wanted to.
	# For now, let's just bypass debounce in tests if possible or wait.

	# 1. Test ON_SCREEN (within range and in viewport)
	for i in range(10): # Trigger update multiple times to pass 150ms if delta was real, but here we manually step
		im._update_markers()
		# Manually advance 'now' in IM if it was using a variable, but it uses OS.get_ticks_msec()

	# Since we can't easily fake OS.get_ticks_msec() without modifying IM,
	# let's just wait in real time.
	OS.delay_msec(200)
	im._update_markers()

	assert_true(im._states[node].state == im.MarkerState.ON_SCREEN, "Expected ON_SCREEN, got " + str(im._states[node].state))

	# 2. Test HIDDEN (out of range)
	node.translation = Vector3(0, 0, -20)
	OS.delay_msec(200)
	im._update_markers()
	assert_true(im._states[node].state == im.MarkerState.HIDDEN, "Expected HIDDEN (out of range), got " + str(im._states[node].state))

	# 3. Test OFF_SCREEN (within range but out of viewport)
	# Move node behind camera
	node.translation = Vector3(0, 0, 5)
	OS.delay_msec(200)
	im._update_markers()
	assert_true(im._states[node].state == im.MarkerState.OFF_SCREEN, "Expected OFF_SCREEN, got " + str(im._states[node].state))

	# 4. Test LOCKED (was seen and now out of range + locked)
	# First make it seen
	node.translation = Vector3(0, 0, -5)
	OS.delay_msec(200)
	im._update_markers()

	# Now set locked and move out of range
	config.locked_text = "LOCKED"
	# Mock is_locked FuncRef
	config.is_locked = funcref(self, "mock_is_locked_true")

	node.translation = Vector3(0, 0, -20)
	OS.delay_msec(200)
	im._update_markers()
	assert_true(im._states[node].state == im.MarkerState.LOCKED, "Expected LOCKED, got " + str(im._states[node].state))

	# Cleanup
	im.unregister(node)
	node.queue_free()
	print("test_MarkerStateTransitions passed.")

func mock_is_locked_true() -> bool:
	return true

func test_OffScreenIndicator() -> void:
	print("Running test_OffScreenIndicator...")
	var im = root.get_node("InteractionMarker")

	# center is (512, 300) for 1024x600 default
	var screen_size = root.get_viewport().get_visible_rect().size
	if screen_size == Vector2.ZERO:
		screen_size = Vector2(1024, 600)
	var center = screen_size / 2.0

	var config = MarkerConfig.new()
	config.screen_margin = 10.0

	# Target to the right
	var unprojected = center + Vector2(1000, 0)
	im._off_screen_arcs.clear()
	im._add_off_screen_arc(unprojected, config)

	var arc = im._off_screen_arcs[0]
	assert_true(abs(arc.pos.x - (screen_size.x - config.screen_margin)) < 0.1, "Expected pos on right edge, got " + str(arc.pos.x))
	assert_true(abs(arc.angle) < 0.01, "Expected angle 0 for right direction")

	# Target up
	unprojected = center + Vector2(0, -1000)
	im._off_screen_arcs.clear()
	im._add_off_screen_arc(unprojected, config)

	arc = im._off_screen_arcs[0]
	assert_true(abs(arc.pos.y - config.screen_margin) < 0.1, "Expected pos on top edge, got " + str(arc.pos.y))
	assert_true(abs(arc.angle + PI/2.0) < 0.01, "Expected angle -PI/2 for up direction")

	print("test_OffScreenIndicator passed.")

func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		printerr("ASSERTION FAILED: ", msg)
		OS.exit_code = 1
