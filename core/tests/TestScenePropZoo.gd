extends Spatial

# TestScenePropZoo.gd
# Automatically finds props in core/props (recursively) and displays them in a grid.
# Each prop is given a lever to test its 'active' state.
# Props with starts_active=true will have their lever start in the active position.

const PROPS_DIR = "res://core/props/"
const EXHIBIT_SCENE = preload("res://core/tests/Exhibit.tscn")

export(float) var grid_spacing := 12.0
export(int) var columns := 5
export(bool) var snap_to_floor := true

onready var exhibits_root = $Exhibits

func _ready():
	print("TestScenePropZoo: Starting initialization...")
	_scan_and_populate()
	print("TestScenePropZoo: Initialization complete.")

func _scan_and_populate():
	var prop_files = []
	_scan_dir_recursive(PROPS_DIR, prop_files)
	
	prop_files.sort()
	print("TestScenePropZoo: Found %d props." % prop_files.size())
	
	for i in range(prop_files.size()):
		_create_exhibit(prop_files[i], i)

func _scan_dir_recursive(path: String, results: Array):
	var dir = Directory.new()
	if dir.open(path) != OK:
		printerr("TestScenePropZoo: Could not open directory: %s" % path)
		return
	
	dir.list_dir_begin(true)
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path + file_name
		if dir.current_is_dir():
			# Recurse into subdirectory
			_scan_dir_recursive(full_path + "/", results)
		elif file_name.ends_with(".tscn") and not "Base" in file_name:
			# Store relative path from PROPS_DIR
			results.append(full_path.replace(PROPS_DIR, ""))
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _create_exhibit(relative_path: String, index: int):
	var exhibit = EXHIBIT_SCENE.instance()
	exhibits_root.add_child(exhibit)
	
	# Layout
	# warning-ignore:INTEGER_DIVISION
	var row = index / columns
	var col = index % columns
	exhibit.translation = Vector3(col * grid_spacing, 0, row * grid_spacing)
	
	# Display name: just the filename without extension
	var display_name = relative_path.get_file().get_basename()
	
	# Setup Label
	var label = exhibit.get_node("Floor/Label")
	if label:
		label.text = display_name
		if "pixel_size" in label:
			label.pixel_size = 0.02
		else:
			label.scale = Vector3(2, 2, 2)
	
	# Load and Instance Prop
	var prop_path = PROPS_DIR + relative_path
	var prop_res = load(prop_path)
	if not prop_res:
		printerr("TestScenePropZoo: Failed to load prop: %s" % prop_path)
		return

	var prop = prop_res.instance()
	var anchor = exhibit.get_node("PropAnchor")
	anchor.add_child(prop)
	print("TestScenePropZoo: Added exhibit for %s" % display_name)
	
	if snap_to_floor and prop is Spatial:
		prop.transform.origin = Vector3.ZERO
		var shift = - _calculate_combined_aabb(prop).position.y
		prop.transform.origin = Vector3(0, shift, 0)
	
	# Wire Lever
	var lever_node = exhibit.get_node("Floor/Lever")
	var control_lever = null

	if lever_node:
		if lever_node.has_signal("activated"):
			control_lever = lever_node
		else:
			var child = lever_node.find_node("RotatingLever", true, false)
			if child and child.has_signal("activated"):
				control_lever = child

	if control_lever:
		var target = null
		var method = ""
		var type = ""
		
		# 1. Check Root
		if prop.has_method("set_active"):
			target = prop
			method = "set_active"
			type = "bool"
		elif prop.has_method("interact"):
			target = prop
			method = "interact"
			type = "void"
		elif prop.has_method("_on_interact"):
			target = prop
			method = "_on_interact"
			type = "void"
		else:
			# 2. Recursive Search for "Primary" Interactable
			var children = []
			_find_interactables_recursive(prop, children)
			if not children.empty():
				target = children[0]
				if target.has_method("set_active"):
					method = "set_active"
					type = "bool"
				elif target.has_method("interact"):
					method = "interact"
					type = "void"
		
		if target:
			print("TestScenePropZoo: Wired %s to %s.%s via %s" % [display_name, target.name, method, control_lever.name])
			if type == "bool":
				control_lever.connect("activated", target, method, [true])
				control_lever.connect("deactivated", target, method, [false])
				
				if target.has_signal("activated") and target.has_signal("deactivated"):
					target.connect("activated", control_lever, "set_active", [true])
					target.connect("deactivated", control_lever, "set_active", [false])
					print("TestScenePropZoo: Wired Bidirectional Sync for %s" % display_name)
				
				# If prop starts_active, sync lever to match
				if "starts_active" in target and target.starts_active:
					control_lever.call_deferred("set_active", true, true)
					print("TestScenePropZoo: Lever starts active for %s" % display_name)
				elif "is_active" in target and target.is_active:
					control_lever.call_deferred("set_active", true, true)
					print("TestScenePropZoo: Lever starts active for %s" % display_name)
					
			else:
				control_lever.connect("interaction_completed", target, method, [])
		else:
			printerr("TestScenePropZoo: Prop %s has no known interaction method (scanned children too)" % display_name)

	else:
		printerr("TestScenePropZoo: Could not find interactable lever component in Exhibit.")

func _find_interactables_recursive(node: Node, result: Array):
	for child in node.get_children():
		if child.has_method("set_active") or child.has_method("interact"):
			result.append(child)
		_find_interactables_recursive(child, result)

# --- Snap Helpers (Ported from PropStage) ---

func _get_bottom_offset(node: Spatial) -> float:
	var aabb = _calculate_combined_aabb(node)
	if aabb.size.y == 0:
		return 0.0
	return -aabb.position.y

func _calculate_combined_aabb(node: Spatial, depth: int = 0) -> AABB:
	var total_aabb = AABB()
	var found = false
	
	if node is MeshInstance and node.get_mesh():
		total_aabb = node.get_mesh().get_aabb()
		found = true
	elif node is CSGBox:
		total_aabb = AABB(Vector3(-node.width / 2, -node.height / 2, -node.depth / 2), Vector3(node.width, node.height, node.depth))
		found = true
	elif node is CSGCylinder:
		total_aabb = AABB(Vector3(-node.radius, -node.height / 2, -node.radius), Vector3(node.radius * 2, node.height, node.radius * 2))
		found = true

	for child in node.get_children():
		if child is Spatial:
			if child is Camera or child is Area or child is CollisionShape or child is Light:
				continue
			if child.has_method("get_curve"):
				continue
			if not child.visible:
				continue
			if child.scale.is_equal_approx(Vector3.ZERO):
				continue
				
			var child_aabb = _calculate_combined_aabb(child, depth + 1)
			if child_aabb.size != Vector3.ZERO:
				var local_aabb = child.transform.xform(child_aabb)
				
				if not found:
					total_aabb = local_aabb
					found = true
				else:
					total_aabb = total_aabb.merge(local_aabb)
	
	return total_aabb
