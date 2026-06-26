tool
extends Spatial
class_name DuctMazeSpawner

# FD-052: DuctMazeSpawner
# Coordinates the generation of the radial duct maze.

const INNER_RADIUS = 2.0
const RING_STEP = 2.0
const ANGLE_STEP = 30.0

export(float) var inner_radius := 2.0
export(int) var sectors := 12
export(int) var rings := 6
export(int) var height_steps := 6
export(int) var room_count := 8
export(int) var extra_cycles := 2
export(int) var seed_value := -1

# Tile paths
const TILE_PATHS = {
	"E": "res://core_v2/props/duct/DuctEndCap.tscn",
	"W": "res://core_v2/props/duct/DuctRadial.tscn",
	"C": "res://core_v2/props/duct/DuctElbow.tscn",
	"T": "res://core_v2/props/duct/DuctTee.tscn",
	"X": "res://core_v2/props/duct/DuctCross.tscn",
	"S": "res://core_v2/props/duct/DuctIncline.tscn"
}
const CAPSULE_PATH = "res://core_v2/props/duct/CapsuleRoom.tscn"
const VALVE_PATH = "res://core_v2/props/duct/DuctGateValve.tscn"

# Resource cache
var _resource_cache := {}
var _arc_builder_script = load("res://core_v2/systems/DuctArcBuilder.gd")

# Exported dictionaries for manual override
export(Dictionary) var duct_tiles := {}
export(PackedScene) var capsule_scene: PackedScene

func _ready():
	if not Engine.editor_hint:
		generate()

func _get_res(path: String):
	if not _resource_cache.has(path):
		if ResourceLoader.exists(path):
			_resource_cache[path] = load(path)
		else:
			_resource_cache[path] = null
	return _resource_cache[path]

func generate() -> void:
	# Clear existing
	for child in get_children():
		child.queue_free()

	var mst_gen = ScaffoldMSTGenerator.new()
	var params = {
		"grid_width": sectors,
		"grid_depth": rings,
		"mst_max_height_steps": height_steps,
		"room_count": room_count,
		"extra_cycles": extra_cycles
	}
	mst_gen.apply_params(params)
	var grid = mst_gen.generate_grid_data(seed_value)

	for i in range(grid.size()):
		var cell = grid[i]
		if cell == null:
			continue

		var gx = i % sectors
		var gy = i / sectors
		var v = cell.variant

		# Replace junction with CapsuleRoom if condition met
		if cell.is_room and _grado(v.connections) >= 2 and v.id in ["C", "T", "X"]:
			var cap_scene = capsule_scene if capsule_scene else _get_res(CAPSULE_PATH)
			if cap_scene:
				var capsule = cap_scene.instance()
				add_child(capsule)
				capsule.transform = _grid_to_world(gx, gy, cell.base_height)
				if capsule.has_method("setup"):
					capsule.setup(v.connections, v.rotation)
				_add_overlay(capsule, gy)
				continue

		var instance: Spatial = null

		if v.id == "W" and (int(v.rotation) % 180 != 0):
			# Task 1: Procedural DuctArc
			var major_r = inner_radius + (gy + 0.5) * RING_STEP
			var mesh = _arc_builder_script.get_or_build_arc(major_r, 2.0, ANGLE_STEP)
			var mesh_instance = MeshInstance.new()
			mesh_instance.mesh = mesh
			mesh_instance.set_meta("variant_id", "W")
			mesh_instance.set_meta("rotation", v.rotation)

			# Apply material from Radial tile if possible
			var radial_res = _get_res(TILE_PATHS["W"])
			if radial_res:
				var radial_temp = radial_res.instance()
				var csg = radial_temp.get_node_or_null("CSGCombiner")
				if csg and csg.get_child_count() > 0:
					mesh_instance.material_override = csg.get_child(0).material
				radial_temp.free()

			if not mesh_instance.material_override:
				mesh_instance.material_override = _get_res("res://core_v2/props/duct/DuctHull.tres")

			# Collision: CylinderShape (radio 2.0, altura ~2.0) oriented to arc
			var sb = StaticBody.new()
			var col = CollisionShape.new()
			var shape = CylinderShape.new()
			shape.radius = 2.0
			shape.height = 2.0
			col.shape = shape
			col.rotation_degrees = Vector3(90, 0, 0)
			sb.add_child(col)
			mesh_instance.add_child(sb)

			add_child(mesh_instance)
			mesh_instance.translation = Vector3(0, cell.base_height, 0)
			mesh_instance.rotation_degrees = Vector3(0, (gx - 0.5) * ANGLE_STEP, 0)

			_add_overlay(mesh_instance, gy)
			continue

		var scene = null
		if v.id == "W":
			scene = duct_tiles.get("W", _get_res(TILE_PATHS["W"]))
		elif v.id == "S":
			scene = duct_tiles.get("S", _get_res(TILE_PATHS["S"]))
		else:
			scene = duct_tiles.get(v.id, _get_res(TILE_PATHS.get(v.id, "")))

		if scene:
			instance = scene.instance()
			add_child(instance)
			instance.transform = _grid_to_world(gx, gy, cell.base_height)
			instance.rotate_object_local(Vector3.UP, deg2rad(v.rotation))
			instance.set_meta("variant_id", v.id)
			instance.set_meta("rotation", v.rotation)
			_add_overlay(instance, gy)

	_insert_valves()
	_activate_collapse_triggers()

func _grid_to_world(gx: int, gy: int, height: float) -> Transform:
	var r = inner_radius + (gy + 0.5) * RING_STEP
	var angle = deg2rad(gx * ANGLE_STEP)

	var pos = Vector3(r * cos(angle), height, r * sin(angle))

	# Basis: X=tangent, Y=up, Z=radial outward
	var tangent = Vector3(-sin(angle), 0, cos(angle))
	var up = Vector3.UP
	var radial = Vector3(cos(angle), 0, sin(angle))

	var basis = Basis(tangent, up, radial)
	return Transform(basis, pos)

func _grado(conn: Array) -> int:
	var count = 0
	for c in conn:
		if c: count += 1
	return count

func _add_overlay(node: Spatial, gy: int) -> void:
	# Task 4: Content Zones
	var color = Color.white
	var zone_name = "Air"

	if gy >= 4:
		color = Color.cyan # Gas
		zone_name = "Gas"
	elif gy >= 2:
		color = Color.blue # Water
		zone_name = "Water"
	else:
		color = Color.lightgray # Air
		zone_name = "Air"

	node.set_meta("zone_color", color)
	node.set_meta("zone_name", zone_name)

	# Visual overlays: Colored light
	var light = OmniLight.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 6.0
	node.add_child(light)

	# Material tint (Water/Gas)
	if zone_name != "Air":
		_apply_tint(node, color)

	# Particles for Gas
	if zone_name == "Gas":
		var particles = Particles.new()
		particles.name = "ZoneParticles_" + zone_name
		var mat = ParticlesMaterial.new()
		mat.emission_shape = ParticlesMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(1.5, 1.5, 1.5)
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 180.0
		mat.gravity = Vector3(0, 0, 0)
		mat.initial_velocity = 0.2
		mat.color = color
		particles.process_material = mat
		particles.amount = 32
		particles.lifetime = 4.0
		node.add_child(particles)

func _apply_tint(node: Node, color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance:
			for i in range(child.get_surface_material_count()):
				var mat = child.get_surface_material(i)
				if not mat:
					mat = child.mesh.surface_get_material(i) if child.mesh else null

				if mat is SpatialMaterial:
					var new_mat = mat.duplicate()
					new_mat.albedo_color = new_mat.albedo_color.linear_interpolate(color, 0.3)
					child.set_surface_material(i, new_mat)
		elif child is CSGCombiner:
			# Tinting CSG is trickier if it uses material at root
			if child.material is SpatialMaterial:
				child.material = child.material.duplicate()
				child.material.albedo_color = child.material.albedo_color.linear_interpolate(color, 0.3)
		_apply_tint(child, color)

func _insert_valves() -> void:
	# Task 2: Strategic valves
	var valve_scene = _get_res(VALVE_PATH)
	if not valve_scene: return

	var count = 0
	for child in get_children():
		var is_radial = false
		if "DuctRadial" in child.name:
			is_radial = true
		elif child.has_meta("variant_id") and child.get_meta("variant_id") == "W":
			if child.has_meta("rotation") and int(child.get_meta("rotation")) % 180 == 0:
				is_radial = true

		if is_radial:
			count += 1
			if count % 3 == 0:
				var valve = valve_scene.instance()
				child.add_child(valve)
				valve.translation = Vector3(0, 0, 0)

func _activate_collapse_triggers() -> void:
	# Task 3: Progressive collapse activation
	for child in get_children():
		if child is Spatial:
			child.set_meta("collapse_active", true)
			if child.has_method("enable_collapse"):
				child.enable_collapse()
