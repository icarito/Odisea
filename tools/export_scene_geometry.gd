tool
extends SceneTree

# tools/export_scene_geometry.gd
# Exports scene geometry, props, zones, and rotators to JSON for the dashboard.

var scene_path: String = ""
var resolution: float = 2.0
var include_props: bool = true
var output_dir: String = "exported_scenes/"
var scene_seed: int = 42

func _init():
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--scene" and i + 1 < args.size():
			scene_path = args[i+1]
		elif args[i] == "--res" and i + 1 < args.size():
			resolution = float(args[i+1])
		elif args[i] == "--output" and i + 1 < args.size():
			output_dir = args[i+1]
		elif args[i] == "--seed" and i + 1 < args.size():
			scene_seed = int(args[i+1])
		elif args[i] == "--no-props":
			include_props = false

	if scene_path == "":
		_print_usage()
		quit()
		return

	_run_export()
	quit()

func _print_usage():
	print("Usage: godot -s tools/export_scene_geometry.gd --scene <path> [options]")
	print("Options:")
	print("  --res <float>      Sampling resolution (default: 2.0)")
	print("  --output <dir>     Output directory (default: exported_scenes/)")
	print("  --no-props         Exclude props from export")
	print("  --seed <int>       Seed for procedural scenes (default: 42)")

func _run_export():
	print("Exporting scene: ", scene_path)
	var scene_resource = load(scene_path)
	if not scene_resource:
		printerr("Error: Could not load scene at ", scene_path)
		return

	var root = scene_resource.instance()
	if not root:
		printerr("Error: Could not instance scene")
		return

	# If it's a procedural scene like ScaffoldOrbit, we might need special handling
	# but for now we follow the scope (static scenes).

	var data = {
		"scene": scene_path.get_file().get_basename(),
		"version": 1,
		"bounds": {"min": [0,0,0], "max": [0,0,0]},
		"points": [],
		"zones": [],
		"props": [],
		"metadata": {
			"generated_at": _get_timestamp(),
			"point_count": 0,
			"zone_count": 0,
			"prop_count": 0
		}
	}

	var min_bound = Vector3(INF, INF, INF)
	var max_bound = Vector3(-INF, -INF, -INF)

	_process_node(root, root, data, min_bound, max_bound)

	if data.points.size() > 0:
		data.bounds.min = [min_bound.x, min_bound.y, min_bound.z]
		data.bounds.max = [max_bound.x, max_bound.y, max_bound.z]

	data.metadata.point_count = data.points.size()
	data.metadata.zone_count = data.zones.size()
	data.metadata.prop_count = data.props.size()

	_save_json(data)
	root.free()

func _process_node(node: Node, root: Node, data: Dictionary, min_b: Vector3, max_b: Vector3):
	if not node: return

	# 1. Geometry Sampling
	if node is MeshInstance:
		_sample_mesh_instance(node, data.points, min_b, max_b)
	elif node is CSGShape:
		_sample_csg_shape(node, data.points, min_b, max_b)

	# 2. Zones
	if node.get_class() == "BaseZoneV2" or _is_subclass_of(node, "BaseZoneV2"):
		_export_zone(node, data.zones)
	elif node.has_meta("zone_type"): # Fallback for nodes tagged as zones
		_export_zone(node, data.zones)

	# 3. Props
	if include_props:
		if _is_prop(node):
			_export_prop(node, data.props)

	# 4. Rotators
	if node.get_class() == "CylinderRotator" or node.get_script() and node.get_script().resource_path.ends_with("CylinderRotator.gd"):
		_export_rotator(node, data.props)

	for child in node.get_children():
		_process_node(child, root, data, min_b, max_b)

func _is_prop(node: Node) -> bool:
	if node.is_in_group("interactable") or node.is_in_group("prop") or node.is_in_group("hazard"):
		return true

	var script = node.get_script()
	if script:
		var path = script.resource_path
		if "LeakEmitter" in path or "Lever" in path or "PipeValve" in path or "PushableBox" in path or "PedestalButton" in path:
			return true

	return false

func _is_subclass_of(node: Node, class_name: String) -> bool:
	var script = node.get_script()
	while script:
		if script.get_instance_base_type() == class_name:
			return true
		# In Godot 3, checking script inheritance is a bit manual
		var base_script = script.get_base_script()
		if base_script and base_script.resource_path.contains(class_name):
			return true
		script = base_script
	return false

func _sample_mesh_instance(mi: MeshInstance, points: Array, min_b: Vector3, max_b: Vector3):
	var mesh = mi.mesh
	if not mesh: return

	var gt = mi.global_transform
	var faces = mesh.get_faces()

	# Very basic sampling: just vertices for now, or random points on faces if resolution is small
	# To keep JSON size manageable, we use the resolution parameter

	var seen_cells = {}

	for i in range(0, faces.size(), 3):
		var v1 = gt.xform(faces[i])
		var v2 = gt.xform(faces[i+1])
		var v3 = gt.xform(faces[i+2])

		_update_bounds(v1, min_b, max_b)
		_update_bounds(v2, min_b, max_b)
		_update_bounds(v3, min_b, max_b)

		# Sample points on the triangle based on resolution
		_sample_triangle(v1, v2, v3, resolution, points, seen_cells)

func _sample_csg_shape(csg: CSGShape, points: Array, min_b: Vector3, max_b: Vector3):
	# For CSG, we could bake to mesh, but for now let's just use the AABB or vertices if available
	# CSG doesn't easily expose vertices in Godot 3 without baking.
	# Simple fallback: sample points within its AABB if it's a CSGBox
	if csg is CSGBox:
		var gt = csg.global_transform
		var size = Vector3(csg.width, csg.height, csg.depth)
		var extents = size * 0.5
		# Sample corners
		for x in [-1, 1]:
			for y in [-1, 1]:
				for z in [-1, 1]:
					var p = gt.xform(Vector3(x * extents.x, y * extents.y, z * extents.z))
					points.append([stepify(p.x, 0.1), stepify(p.y, 0.1), stepify(p.z, 0.1)])
					_update_bounds(p, min_b, max_b)

func _sample_triangle(v1: Vector3, v2: Vector3, v3: Vector3, res: float, points: Array, seen_cells: Dictionary):
	# Grid-based downsampling to manage point count
	var center = (v1 + v2 + v3) / 3.0
	var cell_x = int(floor(center.x / res))
	var cell_y = int(floor(center.y / res))
	var cell_z = int(floor(center.z / res))
	var cell_key = str(cell_x) + "," + str(cell_y) + "," + str(cell_z)

	if not seen_cells.has(cell_key):
		seen_cells[cell_key] = true
		points.append([stepify(center.x, 0.1), stepify(center.y, 0.1), stepify(center.z, 0.1)])

func _update_bounds(p: Vector3, min_b: Vector3, max_b: Vector3):
	min_b.x = min(min_b.x, p.x)
	min_b.y = min(min_b.y, p.y)
	min_b.z = min(min_b.z, p.z)
	max_b.x = max(max_b.x, p.x)
	max_b.y = max(max_b.y, p.y)
	max_b.z = max(max_b.z, p.z)

func _export_zone(node: Node, zones: Array):
	var extents = node.get("zone_extents") if "zone_extents" in node else Vector3(1,1,1)
	var gt = node.global_transform
	zones.append({
		"name": node.name,
		"position": [gt.origin.x, gt.origin.y, gt.origin.z],
		"bounds": {
			"min": [gt.origin.x - extents.x, gt.origin.y - extents.y, gt.origin.z - extents.z],
			"max": [gt.origin.x + extents.x, gt.origin.y + extents.y, gt.origin.z + extents.z]
		},
		"type": node.get("zone_type") if "zone_type" in node else "generic"
	})

func _export_prop(node: Node, props: Array):
	var gt = node.global_transform
	var tags = []
	for g in node.get_groups():
		if g in ["interactable", "prop", "hazard"]:
			tags.append(g)

	props.append({
		"name": node.name,
		"position": [gt.origin.x, gt.origin.y, gt.origin.z],
		"type": "prop",
		"tags": tags
	})

func _export_rotator(node: Node, props: Array):
	var gt = node.global_transform
	var radius = node.get("base_radius") if "base_radius" in node else 190.0
	props.append({
		"name": node.name,
		"position": [gt.origin.x, gt.origin.y, gt.origin.z],
		"type": "rotator",
		"radius": radius,
		"tags": ["rotator"]
	})

func _get_timestamp() -> String:
	var t = OS.get_datetime()
	return "%04d-%02d-%02d" % [t.year, t.month, t.day]

func _save_json(data: Dictionary):
	var dir = Directory.new()
	if not dir.dir_exists(output_dir):
		dir.make_dir_recursive(output_dir)

	var file_name = data.scene + ".json"
	var file_path = output_dir.plus_file(file_name)
	var file = File.new()
	if file.open(file_path, File.WRITE) == OK:
		file.store_string(JSON.print(data, "  "))
		file.close()
		print("Successfully saved: ", file_path)
	else:
		printerr("Error: Could not save file: ", file_path)
