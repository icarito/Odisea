extends GdUnitTestSuite

const InteractionMarker = preload("res://core_v2/components/ui/InteractionMarker.gd")
const MarkerConfig = preload("res://core_v2/components/shared/MarkerConfig.gd")

func test_marker_priority_culling() -> void:
	var marker_scene = load("res://core_v2/components/ui/InteractionMarker.tscn")
	var marker_system = auto_free(marker_scene.instance())
	add_child(marker_system)

	# Create a dummy camera so _process doesn't return early
	var camera = auto_free(Camera.new())
	add_child(camera)
	camera.make_current()

	# Register 5 markers with different priorities
	for i in range(5):
		var spatial = auto_free(Spatial.new())
		add_child(spatial)
		spatial.translation = Vector3(0, 0, -2) # In front of camera

		var config = MarkerConfig.new()
		config.label = "Marker %d" % i
		config.priority = 5 - i # Priority 5, 4, 3, 2, 1
		config.interaction_range = 10.0

		marker_system.register(spatial, config)

	# Advance time to bypass debounce (0.15s)
	marker_system._process(0.2)

	# Verify that only 3 markers are active in UI
	var active_ui = marker_system.get("_active_ui")
	assert_int(active_ui.size()).is_equal(3)

	# Verify they are the ones with highest priority (lowest values: 1, 2, 3)
	# Marker 4 has priority 1, Marker 3 has priority 2, Marker 2 has priority 3
	var labels = []
	for ui in active_ui:
		labels.append(ui.get_node("VBox/Label").text)

	assert_array(labels).contains(["Marker 4", "Marker 3", "Marker 2"])

func test_marker_state_transitions() -> void:
	var marker_scene = load("res://core_v2/components/ui/InteractionMarker.tscn")
	var marker_system = auto_free(marker_scene.instance())
	add_child(marker_system)

	var camera = auto_free(Camera.new())
	add_child(camera)
	camera.make_current()

	var spatial = auto_free(Spatial.new())
	add_child(spatial)

	var config = MarkerConfig.new()
	config.label = "Test"
	config.interaction_range = 5.0
	config.off_screen = true

	marker_system.register(spatial, config)

	# Start with a known state
	spatial.translation = Vector3(0, 0, -2)
	marker_system._process(0.1)
	marker_system._process(0.1)
	var entry = marker_system.get("_entries")[0]
	assert_int(entry.state).is_equal(1) # State.ON_SCREEN

	# Case 1: Out of range -> HIDDEN
	spatial.translation = Vector3(0, 0, 10)
	marker_system._process(0.1) # Debounce start
	marker_system._process(0.1) # 0.2 total
	assert_int(entry.state).is_equal(0) # State.HIDDEN

	# Case 2: In range, in viewport -> ON_SCREEN
	spatial.translation = Vector3(0, 0, -2)
	marker_system._process(0.1)
	marker_system._process(0.1)
	assert_int(entry.state).is_equal(1) # State.ON_SCREEN

	# Case 3: In range, out of viewport -> OFF_SCREEN
	# Move far to the side but stay within interaction_range (5.0)
	spatial.translation = Vector3(4, 0, 0)
	marker_system._process(0.1)
	marker_system._process(0.1)
	assert_int(entry.state).is_equal(2) # State.OFF_SCREEN

func test_off_screen_arc_direction() -> void:
	var marker_scene = load("res://core_v2/components/ui/InteractionMarker.tscn")
	var marker_system = auto_free(marker_scene.instance())
	add_child(marker_system)

	var camera = auto_free(Camera.new())
	add_child(camera)
	camera.make_current()

	var spatial = auto_free(Spatial.new())
	add_child(spatial)
	spatial.translation = Vector3(10, 0, -2) # To the right

	var config = MarkerConfig.new()
	config.interaction_range = 20.0
	config.off_screen = true

	marker_system.register(spatial, config)
	marker_system._process(0.2)

	var arc_data = marker_system.get("_arc_draw_data")
	assert_int(arc_data.size()).is_equal(1)

	# Verify that the screen position of the off-screen object is to the right of the center
	var vs = get_viewport().size
	assert_bool(arc_data[0].pos.x > vs.x / 2.0).is_true()


func test_get_targets_in_range() -> void:
	var marker_scene = load("res://core_v2/components/ui/InteractionMarker.tscn")
	var marker_system = auto_free(marker_scene.instance())
	add_child(marker_system)

	var camera = auto_free(Camera.new())
	add_child(camera)
	camera.make_current()
	camera.translation = Vector3(0, 0, 0)

	# Register 3 objects at distances 3, 6, 9
	for i in range(3):
		var spatial = auto_free(Spatial.new())
		add_child(spatial)
		spatial.translation = Vector3(0, 0, -(3 + i * 3))

		var config = MarkerConfig.new()
		config.label = "Target %d" % i
		config.interaction_range = 20.0

		marker_system.register(spatial, config)

	var origin = Vector3(0, 0, 0)
	var results = marker_system.get_targets_in_range(origin, 5.0)
	assert_int(results.size()).is_equal(2) # Only distances 3 and 6


func test_get_named_target() -> void:
	var marker_scene = load("res://core_v2/components/ui/InteractionMarker.tscn")
	var marker_system = auto_free(marker_scene.instance())
	add_child(marker_system)

	var spatial = auto_free(Spatial.new())
	add_child(spatial)
	var config = MarkerConfig.new()
	config.label = "Consola OD-02"
	marker_system.register(spatial, config)

	var found = marker_system.get_named_target("Consola OD-02")
	assert_object(found).is_equal(spatial)

	var not_found = marker_system.get_named_target("No existe")
	assert_object(not_found).is_null()


func test_get_targets_respects_priority_order() -> void:
	var marker_scene = load("res://core_v2/components/ui/InteractionMarker.tscn")
	var marker_system = auto_free(marker_scene.instance())
	add_child(marker_system)

	var camera = auto_free(Camera.new())
	add_child(camera)
	camera.make_current()
	camera.translation = Vector3(0, 0, 0)

	var priorities = [5, 1, 3]
	var labels = []
	for p in priorities:
		var spatial = auto_free(Spatial.new())
		add_child(spatial)
		spatial.translation = Vector3(0, 0, -5)

		var config = MarkerConfig.new()
		config.label = "P%d" % p
		config.priority = p
		config.interaction_range = 20.0
		labels.append(config.label)

		marker_system.register(spatial, config)

	var origin = Vector3(0, 0, 0)
	var results = marker_system.get_targets_in_range(origin, 10.0)
	assert_int(results.size()).is_equal(3)

	# Priorities should be returned sorted: 1, 3, 5
	assert_str(results[0].config.label).is_equal("P1")
	assert_str(results[1].config.label).is_equal("P3")
	assert_str(results[2].config.label).is_equal("P5")
