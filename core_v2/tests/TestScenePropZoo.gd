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
export(bool) var newest_first := true
export(bool) var run_in_editor := false
export(bool) var preload_props_in_editor := false
# Flat pagination: all props in one list, shown PAGE_SIZE at a time. Only the
# current page is instanced; turning the page frees the previous props. Props
# live in category subfolders on disk but folders no longer drive layout —
# that's reserved for a richer arrangement later.
export(int, 1, 32) var page_size := 5
export(bool) var show_perf_stats := true
export(bool) var editor_refresh_now := false setget _set_editor_refresh_now

onready var exhibits_root = $Exhibits

# Flat list of all prop entries, in the current sort order.
var _entries := []
var _current_page := 0
var _page_label: Label = null
# false = sort by modified time (newest first); true = alphabetical.
# Toggled with the T key.
var _alpha_mode := false

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
	_entries = _collect_prop_entries()
	print("TestScenePropZoo: Found %d props." % _entries.size())
	_sort_entries()
	_current_page = 0
	_show_page()

# Orders the flat entry list by the active sort mode.
func _sort_entries() -> void:
	if _alpha_mode:
		_entries.sort_custom(self, "_sort_props_alpha")
	else:
		_entries.sort_custom(self, "_sort_props_by_modified")

func _page_count() -> int:
	if _entries.empty():
		return 1
	return int(ceil(float(_entries.size()) / float(max(1, page_size))))

# Frees the previous page and instances only the current page's props, so at
# most page_size props are ever live.
func _show_page() -> void:
	_clear_exhibits()

	var pages = _page_count()
	_current_page = int(clamp(_current_page, 0, pages - 1))

	var start = _current_page * page_size
	var end = int(min(start + page_size, _entries.size()))

	var sort_name = "A-Z" if _alpha_mode else "by date"
	_update_page_label("Page %d/%d  (%s)  —  %d props" % [
		_current_page + 1, pages, sort_name, _entries.size()])
	print("TestScenePropZoo: Page %d/%d (%s), props %d-%d." % [
		_current_page + 1, pages, sort_name, start + 1, end])

	# Index is local to the page so the grid always starts at the top-left.
	var slot = 0
	for i in range(start, end):
		var relative_path = String(_entries[i]["relative_path"])
		var exhibit = _create_exhibit_shell(relative_path, slot)
		_populate_exhibit_prop(exhibit, relative_path)
		slot += 1

func next_page() -> void:
	if _current_page >= _page_count() - 1:
		return
	_current_page += 1
	_show_page()

func prev_page() -> void:
	if _current_page <= 0:
		return
	_current_page -= 1
	_show_page()

func _input(event: InputEvent) -> void:
	if Engine.editor_hint:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.scancode == KEY_PAGEDOWN:
		next_page()
		get_tree().set_input_as_handled()
	elif event.scancode == KEY_PAGEUP:
		prev_page()
		get_tree().set_input_as_handled()
	# T toggles sort: by date <-> alphabetical. Keep the first prop of the
	# current page in view so the toggle doesn't feel like it jumps away.
	elif event.scancode == KEY_T:
		_toggle_sort()
		get_tree().set_input_as_handled()

func _toggle_sort() -> void:
	# Remember which prop is at the top of the page so we can land near it.
	var anchor_path = ""
	var top = _current_page * page_size
	if top < _entries.size():
		anchor_path = String(_entries[top]["relative_path"])

	_alpha_mode = not _alpha_mode
	_sort_entries()

	# Re-center the page on the previously-top prop in the new ordering.
	_current_page = 0
	if anchor_path != "":
		for i in range(_entries.size()):
			if String(_entries[i]["relative_path"]) == anchor_path:
				_current_page = i / page_size
				break
	print("TestScenePropZoo: sort=%s" % ("A-Z" if _alpha_mode else "by date"))
	_show_page()

func _ensure_page_label() -> void:
	if _page_label and is_instance_valid(_page_label):
		return
	var layer = CanvasLayer.new()
	layer.name = "PropZooUI"
	add_child(layer)
	_page_label = Label.new()
	_page_label.name = "PageLabel"
	_page_label.set_anchors_and_margins_preset(Control.PRESET_TOP_WIDE)
	_page_label.margin_top = 8
	_page_label.margin_left = 12
	_page_label.align = Label.ALIGN_CENTER
	layer.add_child(_page_label)

func _update_page_label(text: String) -> void:
	if Engine.editor_hint:
		return
	_ensure_page_label()
	if _page_label and is_instance_valid(_page_label):
		_page_label.text = "%s     ( PgUp / PgDn: page   |   T: sort )" % text

func _set_editor_refresh_now(value: bool) -> void:
	editor_refresh_now = false
	if not Engine.editor_hint or not value:
		return
	if preload_props_in_editor:
		_preload_all_props_for_editor()
	if run_in_editor:
		_scan_and_populate()

func _collect_prop_entries() -> Array:
	# Returns the unsorted entry list; ordering is applied by _sort_entries().
	var prop_entries = []
	_scan_dir_recursive(PROPS_DIR, prop_entries)
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
			})
		file_name = dir.get_next()

	dir.list_dir_end()

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
	
	# Load and Instance Prop (timed for the per-prop perf overlay).
	var prop_path = PROPS_DIR + relative_path
	var t_start = OS.get_ticks_usec()
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
	var load_ms = (OS.get_ticks_usec() - t_start) / 1000.0
	var display_name = relative_path.get_file().get_basename()
	print("TestScenePropZoo: Added exhibit for %s" % display_name)

	if show_perf_stats:
		_annotate_perf_stats(exhibit, display_name, prop, load_ms)
	
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

# --- PER-PROP PERF OVERLAY ---

# Appends a complexity readout to the exhibit's Label3D. Godot 3.6 has no
# per-node draw-call counter, so we report the static cost drivers that matter
# in GLES2: instance time and counts of nodes / meshes / lights / particles.
func _annotate_perf_stats(exhibit: Node, display_name: String, prop: Node, load_ms: float) -> void:
	var stats = {"nodes": 0, "meshes": 0, "lights": 0, "particles": 0}
	_count_prop_complexity(prop, stats)

	var label = exhibit.get_node_or_null("Floor/Label")
	if label and "text" in label:
		label.text = "%s\n%.1fms  N:%d  M:%d  L:%d  P:%d" % [
			display_name, load_ms,
			stats["nodes"], stats["meshes"], stats["lights"], stats["particles"]
		]

func _count_prop_complexity(node: Node, stats: Dictionary) -> void:
	for child in node.get_children():
		stats["nodes"] += 1
		if child is MeshInstance:
			stats["meshes"] += 1
		elif child is Light:
			stats["lights"] += 1
		elif child is CPUParticles or child is Particles:
			stats["particles"] += 1
		_count_prop_complexity(child, stats)

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
