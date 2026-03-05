tool
extends Spatial

# TestScenePropZoo.gd
# Automatically finds props in core_v2/props (recursively) and displays them in a grid.
# Each prop is given a lever to test its 'active' state.
# Props with starts_active=true will have their lever start in the active position.

const PROPS_DIR = "res://core_v2/props/"
const EXHIBIT_SCENE = preload("res://core_v2/tests/Exhibit.tscn")

export(float) var grid_spacing := 12.0
export(int) var columns := 5
export(bool) var snap_to_floor := true
export(bool) var sort_by_last_modified := true
export(bool) var newest_first := true
export(bool) var lazy_load_props := true
export(int, 1, 64) var props_per_frame := 4
export(bool) var exclude_player_actors_from_lazy_load := true
export(bool) var run_in_editor := false
export(bool) var preload_props_in_editor := false
export(bool) var lazy_create_exhibits := true
export(bool) var editor_refresh_now := false setget _set_editor_refresh_now

onready var exhibits_root = $Exhibits
var _pending_prop_loads := []

func _ready():
	if Engine.editor_hint:
		if preload_props_in_editor:
			_preload_all_props_for_editor()
		if run_in_editor:
			_scan_and_populate()
		return

	print("TestScenePropZoo: Starting initialization...")
	_scan_and_populate()
	print("TestScenePropZoo: Initialization complete.")

func _scan_and_populate():
	var prop_entries = _collect_prop_entries()
	_pending_prop_loads.clear()
	set_process(false)
	_clear_exhibits()
	print("TestScenePropZoo: Found %d props." % prop_entries.size())

	for i in range(prop_entries.size()):
		var relative_path = String(prop_entries[i]["relative_path"])
		var camera_sensitive = bool(prop_entries[i].get("camera_sensitive", false))
		var load_now = (not lazy_load_props) or (exclude_player_actors_from_lazy_load and camera_sensitive)
		if load_now:
			var exhibit = _create_exhibit_shell(relative_path, i)
			_populate_exhibit_prop(exhibit, relative_path)
		else:
			if lazy_create_exhibits:
				_pending_prop_loads.append({
					"index": i,
					"relative_path": relative_path,
				})
			else:
				var exhibit = _create_exhibit_shell(relative_path, i)
				_pending_prop_loads.append({
					"exhibit": exhibit,
					"index": i,
					"relative_path": relative_path,
				})

	if lazy_load_props and not _pending_prop_loads.empty():
		set_process(true)
		print("TestScenePropZoo: Lazy loading queue started (%d props, %d per frame)." % [_pending_prop_loads.size(), props_per_frame])

func _process(_delta):
	if _pending_prop_loads.empty():
		set_process(false)
		return

	var batch_size = max(1, props_per_frame)
	for _i in range(batch_size):
		if _pending_prop_loads.empty():
			break
		var entry = _pending_prop_loads.pop_front()
		var exhibit = entry.get("exhibit", null)
		var index = int(entry.get("index", 0))
		var relative_path = String(entry.get("relative_path", ""))
		if (not exhibit or not is_instance_valid(exhibit)) and lazy_create_exhibits:
			exhibit = _create_exhibit_shell(relative_path, index)
		if not exhibit or not is_instance_valid(exhibit):
			continue
		_populate_exhibit_prop(exhibit, relative_path)

	if _pending_prop_loads.empty():
		set_process(false)
		print("TestScenePropZoo: Lazy loading queue finished.")

func _set_editor_refresh_now(value: bool) -> void:
	editor_refresh_now = false
	if not Engine.editor_hint or not value:
		return
	if preload_props_in_editor:
		_preload_all_props_for_editor()
	if run_in_editor:
		_scan_and_populate()

func _collect_prop_entries() -> Array:
	var prop_entries = []
	_scan_dir_recursive(PROPS_DIR, prop_entries)

	if sort_by_last_modified:
		prop_entries.sort_custom(self, "_sort_props_by_modified")
	else:
		prop_entries.sort_custom(self, "_sort_props_alpha")

	return prop_entries

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
			var relative_path = full_path.replace(PROPS_DIR, "")
			var mtime = _get_file_mtime(full_path)
			results.append({
				"relative_path": relative_path,
				"modified_time": int(mtime),
				"camera_sensitive": _is_camera_sensitive_prop(full_path, relative_path),
			})
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _is_camera_sensitive_prop(full_path: String, relative_path: String) -> bool:
	var rel = relative_path.to_lower()
	if rel.find("pilot") != -1 or rel.find("programmer") != -1 or rel.find("player") != -1:
		return true

	var file = File.new()
	if file.open(full_path, File.READ) != OK:
		return false
	var text = file.get_as_text()
	file.close()
	return text.find("res://core_v2/actors/Pilot_v2.tscn") != -1 \
		or text.find("res://core_v2/actors/Programmer_v2.tscn") != -1 \
		or text.find("groups=[\"player\"") != -1

func _sort_props_alpha(a: Dictionary, b: Dictionary) -> bool:
	return String(a["relative_path"]) < String(b["relative_path"])

func _sort_props_by_modified(a: Dictionary, b: Dictionary) -> bool:
	var a_time = int(a.get("modified_time", 0))
	var b_time = int(b.get("modified_time", 0))
	if a_time == b_time:
		return String(a["relative_path"]) < String(b["relative_path"])
	return a_time > b_time if newest_first else a_time < b_time

func _get_file_mtime(path: String) -> int:
	var f = File.new()
	var mtime = f.get_modified_time(path)
	return int(mtime)

func _clear_exhibits() -> void:
	if not exhibits_root:
		return
	_pending_prop_loads.clear()
	set_process(false)
	for child in exhibits_root.get_children():
		exhibits_root.remove_child(child)
		child.free()

func _preload_all_props_for_editor() -> void:
	if not Engine.editor_hint:
		return
	var prop_entries = _collect_prop_entries()
	for entry in prop_entries:
		load(PROPS_DIR + String(entry["relative_path"]))
	print("TestScenePropZoo: Preloaded %d prop scenes for editor cache." % prop_entries.size())

func _create_exhibit_shell(relative_path: String, index: int) -> Node:
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

	return exhibit

func _populate_exhibit_prop(exhibit: Node, relative_path: String) -> void:
	if not exhibit or not is_instance_valid(exhibit):
		return
	
	# Load and Instance Prop
	var prop_path = PROPS_DIR + relative_path
	var prop_res = load(prop_path)
	if not prop_res:
		printerr("TestScenePropZoo: Failed to load prop: %s" % prop_path)
		return

	var prop = prop_res.instance()
	var anchor = exhibit.get_node("PropAnchor")
	if not anchor:
		printerr("TestScenePropZoo: Exhibit without PropAnchor: %s" % relative_path)
		return
	anchor.add_child(prop)
	var display_name = relative_path.get_file().get_basename()
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
