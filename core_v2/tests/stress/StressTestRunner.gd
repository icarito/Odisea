extends Node

# StressTestRunner.gd
# Helper to execute stress tests via OYS commands

const DRONE_SCENE = preload("res://core_v2/actors/CargolDroneV2.tscn")
const BOX_SCENE = preload("res://core_v2/components/PushableBoxV2.tscn")

var _active_test := ""
var _spawned_drones := []
var _spawn_timer := 0.0
var _spawn_rate := 50.0 # Per second
var _hierarchy_root: Spatial = null

func _ready():
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("register_oys_actor"):
		sm.register_oys_actor("StressTestRunner", self)
	print("[StressTestRunner] Ready. Use OYS CALL to run tests.")

func _process(delta):
	if _active_test == "spawning":
		_process_spawning_test(delta)
	elif _active_test == "hierarchy":
		if _hierarchy_root:
			_hierarchy_root.rotate_y(delta * 2.0)

# --- Test API ---

func run_saturation_test(count: int):
	_cleanup()
	print("[StressTestRunner] Starting Saturation Test with %d drones..." % count)

	for i in range(count):
		var drone = DRONE_SCENE.instance()
		add_child(drone)
		# Spread them out
		var angle = i * 0.1
		var radius = 5.0 + (i * 0.05)
		var x = cos(angle) * radius
		var z = sin(angle) * radius
		drone.translation = Vector3(x, 2.0, z)
		# Make them move around randomly?
		# Or just exist to test node overhead
		if drone.has_method("move_to"):
			drone.move_to(Vector3(-x, 2.0, -z)) # Cross the center

		_spawned_drones.append(drone)

		# Yield occasionally to prevent freeze during spawn
		if i % 50 == 0:
			yield(get_tree(), "idle_frame")

	_active_test = "saturation"
	print("[StressTestRunner] Saturation Test Running. Check PerformanceMonitor.")

func run_spawning_test():
	_cleanup()
	print("[StressTestRunner] Starting Spawning/Despawning Test...")
	_active_test = "spawning"
	_spawn_timer = 0.0

func _process_spawning_test(delta):
	_spawn_timer += delta
	var to_spawn = int(_spawn_timer * _spawn_rate)
	if to_spawn > 0:
		_spawn_timer -= (to_spawn / _spawn_rate)

		# Spawn new ones
		for i in range(to_spawn):
			var drone = DRONE_SCENE.instance()
			add_child(drone)
			drone.translation = Vector3(rand_range(-20, 20), 5, rand_range(-20, 20))
			_spawned_drones.append(drone)

		# Despawn old ones to keep count roughly constant after a while?
		# Spec says "Create and Destroy 50/sec".
		# So we should destroy roughly same amount.
		if _spawned_drones.size() > 200:
			for i in range(to_spawn):
				if _spawned_drones.empty(): break
				var d = _spawned_drones.pop_front()
				if is_instance_valid(d):
					d.queue_free()

func run_pathfinding_test(count: int):
	_cleanup()
	print("[StressTestRunner] Starting Pathfinding Test (Unreachable Goals)...")

	# Create a wall box
	var wall_container = Spatial.new()
	add_child(wall_container)
	var box = CSGBox.new()
	box.width = 10
	box.height = 5
	box.depth = 10
	box.invert_faces = true # Hollow box? No, invert makes normals inward.
	# Better: 4 walls.
	# Actually, simplest unreachable goal is just way up in the sky or inside a solid block.
	# Let's use "Goal inside a solid block".

	var obstacle = CSGBox.new()
	obstacle.use_collision = true
	obstacle.width = 5
	obstacle.height = 5
	obstacle.depth = 5
	obstacle.translation = Vector3(0, 2.5, 0)
	wall_container.add_child(obstacle)
	_spawned_drones.append(wall_container) # Track for cleanup

	for i in range(count):
		var drone = DRONE_SCENE.instance()
		add_child(drone)
		var angle = i * (TAU / count)
		var radius = 15.0
		drone.translation = Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)

		# Goal is inside the box (0, 2.5, 0)
		if drone.has_method("move_to"):
			drone.move_to(Vector3(0, 2.5, 0))

		_spawned_drones.append(drone)
		if i % 20 == 0: yield(get_tree(), "idle_frame")

	_active_test = "pathfinding"

func run_hierarchy_test(depth: int):
	_cleanup()
	print("[StressTestRunner] Starting Hierarchy Test (Depth: %d)..." % depth)

	_hierarchy_root = Spatial.new()
	add_child(_hierarchy_root)
	_spawned_drones.append(_hierarchy_root)

	var current = _hierarchy_root
	for i in range(depth):
		var next = Spatial.new()
		next.translation = Vector3(1.0, 0.1, 0)
		current.add_child(next)

		# Add some visual/logic load at each level
		var mesh = MeshInstance.new()
		mesh.mesh = CubeMesh.new() # Simple cube
		mesh.scale = Vector3(0.5, 0.5, 0.5)
		next.add_child(mesh)

		current = next

	_active_test = "hierarchy"

func run_physics_box_test(count: int):
	_cleanup()
	print("[StressTestRunner] Starting Physics Box Test (RigidBody interaction)...")

	for i in range(count):
		if BOX_SCENE == null:
			printerr("[StressTestRunner] Failed to load PushableBoxV2.tscn")
			return

		var box = BOX_SCENE.instance()
		add_child(box)
		box.translation = Vector3(rand_range(-5, 5), 5 + (i * 2.5), rand_range(-5, 5))

		_spawned_drones.append(box)
		if i % 10 == 0: yield(get_tree(), "idle_frame")

	_active_test = "physics_box"

func stop_test():
	_cleanup()
	print("[StressTestRunner] Test Stopped.")

func _cleanup():
	# Save snapshot before cleaning up
	if _active_test != "":
		var pm = get_node_or_null("/root/PerformanceMonitor")
		if pm:
			pm.save_performance_snapshot(_active_test + "_end")

	for n in _spawned_drones:
		if is_instance_valid(n):
			n.queue_free()
	_spawned_drones.clear()
	_active_test = ""
	_hierarchy_root = null
