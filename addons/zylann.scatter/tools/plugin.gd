tool
extends EditorPlugin

const Scatter3D = preload("res://addons/zylann.scatter/scatter3d.gd")
const PaletteControl = preload("res://addons/zylann.scatter/tools/palette.tscn")
const Util = preload("res://addons/zylann.scatter/tools/util.gd")

const ACTION_PAINT = 0
const ACTION_ERASE = 1

var _node = null
var _pattern = null
var _mouse_pressed = false
var _mouse_button = BUTTON_LEFT
var _pending_paint_completed = false
var _mouse_position = Vector2()
var _editor_camera = null
var _collision_mask = 1
var _placed_instances = []
var _removed_instances = []
var _disable_undo = false
var _pattern_margin = 0.0
var _pattern_aabb = AABB()

var _palette = null
var _error_dialog = null

var _shift_pressed = false


var _last_paint_time = 0


static func get_icon(name):
	return load("res://addons/zylann.scatter/tools/icons/icon_" + name + ".svg")


func _enter_tree():
	print("Scatter plugin Enter tree")
	# The class is globally named but still need to register it just so the node creation dialog gets it
	# https://github.com/godotengine/godot/issues/30048
	add_custom_type("Scatter3D", "Spatial", Scatter3D, get_icon("scatter3d_node"))
	
	var base_control = get_editor_interface().get_base_control()
	
	_palette = PaletteControl.instance()
	_palette.connect("pattern_selected", self, "_on_Palette_pattern_selected")
	_palette.connect("pattern_added", self, "_on_Palette_pattern_added")
	_palette.connect("pattern_removed", self, "_on_Palette_pattern_removed")
	_palette.hide()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _palette)
	_palette.set_preview_provider(get_editor_interface().get_resource_previewer())
	_palette.call_deferred("setup_dialogs", base_control)
	
	_last_paint_time = OS.get_ticks_msec() # Initializing

	_error_dialog = AcceptDialog.new()
	_error_dialog.rect_min_size = Vector2(300, 200)
	_error_dialog.hide()
	_error_dialog.window_title = "Error"
	base_control.add_child(_error_dialog)
	

func _exit_tree():
	print("Scatter plugin Exit tree")
	edit(null)
	
	remove_custom_type("Scatter3D")
	
	_palette.queue_free()
	_palette = null
	
	_error_dialog.queue_free()
	_error_dialog = null


func handles(obj):
	return obj != null and obj is Scatter3D


func edit(obj):
	_node = obj
	if _node:
		var patterns = _node.get_patterns()
		if len(patterns) > 0:
			set_pattern(patterns[0])
		else:
			set_pattern(null)
		_palette.load_patterns(patterns)
		set_physics_process(true)
	else:
		set_physics_process(false)


func make_visible(visible):
	_palette.set_visible(visible)
	# TODO Workaround https://github.com/godotengine/godot/issues/6459
	# When the user selects another node, I want the plugin to release its references.
	if not visible:
		edit(null)


func forward_spatial_gui_input(p_camera, p_event):
	if _node == null:
		return false

	var captured_event = false
	
	if p_event is InputEventMouseButton:
		var mb = p_event
		
		if mb.button_index == BUTTON_LEFT or mb.button_index == BUTTON_RIGHT:
			if mb.pressed == false:
				_mouse_pressed = false

			# Need to check modifiers before capturing the event,
			# because they are used in navigation schemes
			if (not mb.control) and (not mb.alt): # and mb.button_index == BUTTON_LEFT:
				if mb.pressed:
					_mouse_pressed = true
					_mouse_button = mb.button_index
					_last_paint_time = 0 # paint immediately
				
				captured_event = true
				
				if not _mouse_pressed:
					# Just finished painting
					_pending_paint_completed = true
	
	elif p_event is InputEventMouseMotion:
		var mm = p_event
		_mouse_position = mm.position

	if p_event is InputEventWithModifiers:
		_shift_pressed = p_event.shift

	_editor_camera = p_camera
	return captured_event


func _physics_process(delta):
	if _editor_camera == null:
		return
	if not is_instance_valid(_editor_camera):
		_editor_camera = null
		return
	if _node == null:
		return
	if _pattern == null:
		return
		
	var ray_origin = _editor_camera.project_ray_origin(_mouse_position)
	var ray_dir = _editor_camera.project_ray_normal(_mouse_position)
	var ray_distance = _editor_camera.far
	
	var action = null
	match _mouse_button:
		BUTTON_LEFT:
			action = ACTION_PAINT
		BUTTON_RIGHT:
			action = ACTION_ERASE
	
	if _mouse_pressed:
		if action == ACTION_PAINT:
			var space_state = get_viewport().world.direct_space_state
			var hit = space_state.intersect_ray(ray_origin, ray_origin + ray_dir * ray_distance, [], _collision_mask)
			
			if not hit.empty():
				var hit_instance_root
				# Collider can be null if the hit is on something that has no associated node
				if hit.collider != null:
					hit_instance_root = Util.get_instance_root(hit.collider)
				
				# Allow painting on anything, including other Scatter3D instances (for stacking)
				# if hit.collider == null or not (hit_instance_root.get_parent() is Scatter3D):
				if true:
					var pos = hit.position
					var now = OS.get_ticks_msec()
					
					# Not accurate, you might still paint stuff too close to others,
					# but should be good enough and cheap
					var too_close = false
					
					if now - _last_paint_time < _palette.get_paint_interval() * 1000.0:
						too_close = true

					# Helper for stacking
					var stacking = false
					if _shift_pressed and len(_placed_instances) > 0:
						# If shift is pressed, we try to stack on top of the last placed instance
						# if the mouse is somewhat close (or just assume intent).
						# Actually, if we just use the last instance position, we can build a tower easily.
						var last_instance = _placed_instances[-1]
						var last_pos = last_instance.global_transform.origin
						
						# Simple check: if ray passes near the last instance?
						# Or just force stacking if we are in paint mode.
						# Let's enforce stacking if the mouse ray is close to the last instance in 2D or 3D?
						# For simplicity, if Shift is held, we snap to the previous instance's top.
						
						# Calculate top position
						# We assume the last instance has the same AABB as standard pattern (approx)
						# Height of the object
						var height = _pattern_aabb.size.y
						if height < 0.1: height = 1.0
						
						# Apply spacing modifier to vertical spacing
						height *= _palette.get_spacing_modifier()
						
						# New position is directly above
						var new_pos = last_pos + Vector3(0, height, 0)
						
						# We update 'pos' to this new position
						pos = new_pos
						stacking = true
						
						# When stacking, we ignore 'too_close' because we are deliberately close
						# But we still respect time interval
						
					if not too_close and not stacking and len(_placed_instances) != 0:
						var last_placed_transform = _placed_instances[-1].global_transform
						# Ensure _pattern_margin is at least something reasonable
						var margin = _pattern_margin
						if margin < 0.5: margin = 1.0
						
						if last_placed_transform.origin.distance_to(pos) < margin * _palette.get_spacing_modifier():
							too_close = true
					
					if not too_close:
						var instance = _pattern.instance()
						instance.translation = pos
						
						if stacking:
							# Align with the instance below
							instance.rotation = _placed_instances[-1].rotation
						else:
							instance.rotate_y(rand_range(-PI, PI))
							
						_node.add_child(instance)
						instance.owner = get_editor_interface().get_edited_scene_root()
						_placed_instances.append(instance)
						_last_paint_time = now
	
		elif action == ACTION_ERASE:
			var time_before = OS.get_ticks_usec()
			var hits = VisualServer.instances_cull_ray(ray_origin, ray_dir, _node.get_world().scenario)

			if len(hits) > 0:
				var instance = null
				for hit_object_id in hits:
					var hit = instance_from_id(hit_object_id)
					if hit is Spatial:
						instance = get_scatter_child_instance(hit, _node)
						if instance != null:
							break
				
				#print("Hits: ", len(hits), ", instance: ", instance)
				if instance != null:
					assert(instance.get_parent() == _node)
					instance.get_parent().remove_child(instance)
					_removed_instances.append(instance)

	if _pending_paint_completed:
		if action == ACTION_PAINT:
			# TODO This will creep memory until the scene is closed...
			# Because in Godot, undo/redo of node creation/deletion is done by NOT deleting them.
			# To stay in line with this, I have to do the same...
			var ur = get_undo_redo()
			ur.create_action("Paint scenes")
			for instance in _placed_instances:
				# This is what allows nodes to be freed
				ur.add_do_reference(instance)
			_disable_undo = true
			ur.add_do_method(self, "_redo_paint", _node.get_path(), _placed_instances.duplicate(false))
			ur.add_undo_method(self, "_undo_paint", _node.get_path(), _placed_instances.duplicate(false))
			ur.commit_action()
			_disable_undo = false
			_placed_instances.clear()
			
		elif action == ACTION_ERASE:
			var ur = get_undo_redo()
			ur.create_action("Erase painted scenes")
			for instance in _removed_instances:
				ur.add_undo_reference(instance)
			_disable_undo = true
			ur.add_do_method(self, "_redo_erase", _node.get_path(), _removed_instances.duplicate(false))
			ur.add_undo_method(self, "_undo_erase", _node.get_path(), _removed_instances.duplicate(false))
			ur.commit_action()
			_disable_undo = false
			_removed_instances.clear()
		
		_pending_paint_completed = false

#func resnap_instances():
#	pass


func _redo_paint(parent_path, instances_data):
	if _disable_undo:
		return
	var parent = get_node(parent_path)
	for instance in instances_data:
		parent.add_child(instance)


func _undo_paint(parent_path, instances_data):
	if _disable_undo:
		return
	var parent = get_node(parent_path)
	for instance in instances_data:
		parent.remove_child(instance)


func _redo_erase(parent_path, instances_data):
	if _disable_undo:
		return
	var parent = get_node(parent_path)
	for instance in instances_data:
		instance.get_parent().remove_child(instance)


func _undo_erase(parent_path, instances_data):
	if _disable_undo:
		return
	var parent = get_node(parent_path)
	for instance in instances_data:
		parent.add_child(instance)


# Goes up the tree from the given node and finds the first Scatter layer,
# then return the immediate child of it from which the node is child of
static func get_scatter_child_instance(node, scatter_root):
	var parent = node
	while parent != null:
		parent = node.get_parent()
		if parent != null and parent == scatter_root:
			return node
		node = parent
	return null


func set_pattern(pattern):
	if _pattern != pattern:
		_pattern = pattern
		var temp = pattern.instance()
		# TODO This causes errors because of accessing `global_transform` outside the tree... Oo
		# See https://github.com/godotengine/godot/issues/30445
		var result = Util.get_scene_aabb(temp)
		var aabb = result.aabb
		_pattern_aabb = aabb

		# _pattern_margin = aabb.size.length() * 0.4
		# Use the longest axis as the base spacing to prevent overlap by default
		_pattern_margin = aabb.get_longest_axis_size()
		if _pattern_margin < 0.5:
			_pattern_margin = 1.0
		temp.free()
		print("Pattern margin is ", _pattern_margin)


func _on_Palette_pattern_selected(pattern_index):
	var patterns = _node.get_patterns()
	set_pattern(patterns[pattern_index])


func _on_Palette_pattern_added(path):
	if not verify_scene(path):
		return
	# TODO Duh, may not work if the file was moved or renamed... I'm tired of this
	var ur = get_undo_redo()
	ur.create_action("Add scatter pattern")
	ur.add_do_method(self, "add_pattern", path)
	ur.add_undo_method(self, "remove_pattern", path)
	ur.commit_action()


func _on_Palette_pattern_removed(path):
	var ur = get_undo_redo()
	ur.create_action("Remove scatter pattern")
	ur.add_do_method(self, "remove_pattern", path)
	ur.add_undo_method(self, "add_pattern", path)
	ur.commit_action()


func add_pattern(path):
	print("Adding pattern ", path)
	_node.add_pattern(path)
	_palette.add_pattern(path)


func remove_pattern(path):
	print("Removing pattern ", path)
	_node.remove_pattern(path)
	_palette.remove_pattern(path)


func verify_scene(fpath):
	# Check it can be loaded
	var scene = load(fpath)
	if scene == null:
		_show_error(tr("Could not load the scene. See the console for more info."))
		return false
	
	# Check it's not already in the list
	if _node.has_pattern(fpath):
		_palette.select_pattern(fpath)
		_show_error(tr("The selected scene is already in the palette"))
		return false
	
	# Check it's not the current scene itself
	if Util.is_self_or_parent_scene(fpath, _node):
		_show_error("The selected scene can't be added recursively")
		return false
	
	# Check it inherits Spatial
#	var scene_state = scene.get_state()
#	var root_type = scene_state.get_node_type(0)
	# Aaaah screw this
	var scene_instance = scene.instance()
	if not (scene_instance is Spatial):
		_show_error(tr("The selected scene is not a Spatial, it can't be painted in a 3D scene."))
		scene_instance.free()
		return false
	scene_instance.free()
	
	return true


func _show_error(msg):
	_error_dialog.dialog_text = msg
	_error_dialog.popup_centered_minsize()
