extends Spatial

# TestScenePropZoo.gd
# Automatically finds props in core_v2/props and displays them in a grid.
# Each prop is given a lever to test its 'active' state.

const PROPS_DIR = "res://core_v2/props/"
const EXHIBIT_SCENE = preload("res://core_v2/tests/Exhibit.tscn")

export(float) var grid_spacing := 12.0
export(int) var columns := 5
export(bool) var snap_to_floor := true

onready var exhibits_root = $Exhibits

func _ready():
	print("TestScenePropZoo: Starting initialization...")
	_scan_and_populate()
	print("TestScenePropZoo: Initialization complete.")

func _scan_and_populate():
	var dir = Directory.new()
	if dir.open(PROPS_DIR) != OK:
		printerr("TestScenePropZoo: Could not open directory: %s" % PROPS_DIR)
		return

	dir.list_dir_begin(true) # Skip navigational and hidden
	var file_name = dir.get_next()
	var prop_files = []

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tscn"):
			# Filter out base classes or temporary files if needed
			if not "Base" in file_name:
				prop_files.append(file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	prop_files.sort() # Alphabetical order
	print("TestScenePropZoo: Found %d props." % prop_files.size())
	
	for i in range(prop_files.size()):
		_create_exhibit(prop_files[i], i)

func _create_exhibit(filename: String, index: int):
	var exhibit = EXHIBIT_SCENE.instance()
	exhibits_root.add_child(exhibit)
	
	# Layout
	var row = index / columns
	var col = index % columns
	exhibit.translation = Vector3(col * grid_spacing, 0, row * grid_spacing)
	
	# Setup Label
	var label = exhibit.get_node("Label")
	if label:
		# Remove extension and path, just keep the name
		label.text = filename.get_basename()
		# Enlarge font 2x
		# Label3D in Godot 3.x uses pixel_size for scaling or requires a Font resource resource.
		# Simplest way to "enlarge" is to double pixel_size (which makes it smaller in world space usually?)
		# No, pixel_size is "size of one pixel in meters". Larger pixel_size = larger text.
		# Default is 0.01. Let's try 0.02.
		# OR we can just scale the node.
		# Let's try scaling pixel_size if available, or just scale.
		if "pixel_size" in label:
			label.pixel_size = 0.02 # Double default
		else:
			label.scale = Vector3(2, 2, 2)
	
	# Load and Instance Prop
	var prop_path = PROPS_DIR + filename
	var prop_res = load(prop_path)
	if not prop_res:
		printerr("TestScenePropZoo: Failed to load prop: %s" % prop_path)
		return

	var prop = prop_res.instance()
	var anchor = exhibit.get_node("PropAnchor")
	anchor.add_child(prop)
	print("TestScenePropZoo: Added exhibit for %s" % filename)
	
	if snap_to_floor and prop is Spatial:
		# Reset position relative to anchor first
		prop.transform.origin = Vector3.ZERO
		var offset = _get_bottom_offset(prop)
		# PropAnchor is usually at Y=0.1 or so.
		# If we want the BOTTOM of the prop to be at Y=0 relative to anchor?
		# Or relative to the floor mesh?
		# Exhibit floor is at 0. PropAnchor is at 0.1.
		# If we want the prop to sit ON the floor (Y=0.1), we need its bottom to be at 0 local.
		# _get_bottom_offset returns the Y shift needed to put the bottom at Y=0.
		# Let's see how PropStage did it:
		# offset = 0.1 - aabb.position.y (calculates shift to put bottom at 0.1)
		# instance.transform.origin = Vector3(0, offset, 0)
		
		# Here, PropAnchor is child of Exhibit.
		# If PropAnchor is at (0, 0.1, 0), then local (0,0,0) is at world Y=0.1 (floor surface).
		# We want prop's bottom to be at local Y=0.
		# AABB.position.y is the bottom relative to origin.
		# Shift = -AABB.position.y
		var shift = - _calculate_combined_aabb(prop).position.y
		prop.transform.origin = Vector3(0, shift, 0)
	
	# Wire Lever
	var lever_node = exhibit.get_node("Lever")
	var control_lever = null # The actual Interactable part of the Exhibit's lever
	
	if lever_node:
		# Find the control lever interactable
		if lever_node.has_signal("activated"):
			control_lever = lever_node
		else:
			var child = lever_node.find_node("RotatingLever", true, false)
			if child and child.has_signal("activated"):
				control_lever = child

	if control_lever:
		# Find the target method on the Prop (Root or Children)
		var target = null
		var method = ""
		var type = "" # "bool" or "void"
		
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
			# We prefer "set_active" providers
			var children = []
			_find_interactables_recursive(prop, children)
			if not children.empty():
				# Heuristic: Pick the first or one named "RotatingLever", "SlidingDoor" etc.
				target = children[0]
				if target.has_method("set_active"):
					method = "set_active"
					type = "bool"
				elif target.has_method("interact"):
					method = "interact"
					type = "void"
		
		if target:
			print("TestScenePropZoo: Wired %s to %s.%s via %s" % [filename, target.name, method, control_lever.name])
			if type == "bool":
				# Lever -> Prop
				control_lever.connect("activated", target, method, [true])
				control_lever.connect("deactivated", target, method, [false])
				
				# Prop -> Lever (Bidirectional Sync)
				# If the prop itself is a switch (like Lever.tscn or PressurePlate), it might change state externally.
				# We want the Exhibit's lever to reflect this.
				if target.has_signal("activated") and target.has_signal("deactivated"):
					# Avoid value loops via checks in InteractableBase or just by nature of signal emission
					# InteractableBaseV2 only emits if state actually changes.
					target.connect("activated", control_lever, "set_active", [true])
					target.connect("deactivated", control_lever, "set_active", [false])
					print("TestScenePropZoo: Wired Bidirectional Sync for %s" % filename)
					
			else:
				control_lever.connect("interaction_completed", target, method, [])
		else:
			printerr("TestScenePropZoo: Prop %s has no known interaction method (scanned children too)" % filename)

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
	# We want the bottom of the AABB to be at Y=0
	return -aabb.position.y

func _calculate_combined_aabb(node: Spatial, depth: int = 0) -> AABB:
	var total_aabb = AABB()
	var found = false
	
	# Start with self if has mesh
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
			# Ignore non-visual-structural nodes to prevent bad bounds
			if child is Camera or child is Area or child is CollisionShape or child is Light:
				continue
			if child.has_method("get_curve"): # Curve3D/Path
				continue
			
			# Ignore invisible or zero-scaled nodes (like collapsed holograms)
			if not child.visible:
				continue
			if child.scale.is_equal_approx(Vector3.ZERO):
				continue
				
			var child_aabb = _calculate_combined_aabb(child, depth + 1)
			if child_aabb.size != Vector3.ZERO:
				# Transform child AABB to this node's space
				var local_aabb = child.transform.xform(child_aabb)
				
				if not found:
					total_aabb = local_aabb
					found = true
				else:
					total_aabb = total_aabb.merge(local_aabb)
	
	return total_aabb
