extends SceneTree

func _init():
	print("Starting Anna Interface Test Stub...")

	var anna_interface = load("res://core_v2/anna/AnnaInterface.gd").new()
	if not anna_interface:
		printerr("Failed to instantiate AnnaInterface")
		quit(1)
		return

	print("AnnaInterface instantiated.")

	# Verify method existence
	if not anna_interface.has_method("get_observation"):
		printerr("Method get_observation missing")
		quit(1)
		return

	if not anna_interface.has_method("apply_action"):
		printerr("Method apply_action missing")
		quit(1)
		return

	# Try to call get_observation (might return empty/defaults if not in tree)
	# We mock the environment by just calling it.
	# Note: AnnaInterface expects to be in tree for some things, so we wrap in try/catch equivalent if possible?
	# GDScript has no try/catch.
	# However, _get_player uses get_node_or_null("/root/SessionManager"). If it returns null, it handles it.
	# _setup_sensors calls add_child. This fails if AnnaInterface is not added to a parent or if we are strict.
	# Actually, add_child on a Node not in tree is fine, it just adds to internal list.

	anna_interface._ready() # Simulate ready

	var obs = anna_interface.get_observation()
	print("Observation structure keys: ", obs.keys())

	print("Anna Interface Test Stub Passed (Static Analysis equivalent).")
	quit(0)
