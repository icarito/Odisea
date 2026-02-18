extends SceneTree

func _init():
	print("Starting CircuitCable Physics Test...")

	# Create root node
	var root = Spatial.new()
	get_root().add_child(root)

	# Instantiate CircuitCable
	var cable_script = load("res://core_v2/systems/circuit/CircuitCable.gd")
	var cable = cable_script.new()
	root.add_child(cable)

	# Create Curve3D
	var curve = Curve3D.new()
	curve.add_point(Vector3(0, 10, 0)) # Start high
	curve.add_point(Vector3(5, 10, 0)) # End high

	print("Initializing cable from curve...")
	cable.init_from_curve(curve)

	# Verify particles
	# Access private var via weakref or just assuming script logic
	# Since it's GDScript, we can access _particles if we are in same project
	var particles = cable.get("_particles")
	if not particles or particles.empty():
		print("FAILURE: No particles created.")
		quit(1)
		return

	print("Particles created: ", particles.size())

	var mid_idx = particles.size() / 2
	var p_mid = particles[mid_idx]
	var initial_y = p_mid.pos.y
	print("Middle particle initial Y: ", initial_y)

	# Simulate physics manually
	print("Simulating 60 frames...")
	for i in range(60):
		# Manually call _physics_process to ensure it runs even if engine loop is not ticking
		cable._physics_process(0.016)

	var final_y = p_mid.pos.y
	print("Middle particle final Y: ", final_y)

	# Verify gravity
	if final_y < initial_y - 0.1: # Expect significant drop
		print("SUCCESS: Gravity applied (y decreased).")
	else:
		print("FAILURE: Gravity not applied or too weak. Delta: ", final_y - initial_y)
		quit(1)
		return

	# Verify Mesh Generation
	var mesh_inst = cable.get("_mesh_instance")
	if mesh_inst and mesh_inst.mesh:
		print("SUCCESS: Mesh generated.")
		var surface_count = mesh_inst.mesh.get_surface_count()
		print("Mesh surface count: ", surface_count)
		if surface_count > 0:
			pass
		else:
			print("FAILURE: Mesh has no surfaces.")
			quit(1)
			return
	else:
		print("FAILURE: MeshInstance not found or mesh is null.")
		quit(1)
		return

	print("Test Passed.")
	quit(0)
