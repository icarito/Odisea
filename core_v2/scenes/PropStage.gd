tool
extends Spatial

# PropStage.gd
# Specialized environment for validating props functionality and visuals.
# Used by OYS commands LOAD_PROP and SCREENSHOT.

onready var prop_anchor = $PropAnchor
onready var camera = $Camera


var current_prop: Node = null
var _accumulated_wait_time: float = 0.0

export(String, FILE, "*.tscn") var dev_prop_path setget _set_dev_prop_path
export(bool) var dev_take_screenshots setget _set_dev_take_screenshots
export(bool) var dev_snap_to_floor = true
export(int) var dev_tween_interval = 20

func _ready():
	if camera:
		camera.transform.origin = Vector3(0, 2.5, 4.0)
		camera.look_at(Vector3(0, 2.0, 0), Vector3.UP)
		camera.make_current()

	
	# If running in editor and prop path set, load it
	if Engine.editor_hint and dev_prop_path != "" and current_prop == null:
		load_prop(dev_prop_path)
		
	# Ensure environment is set up for neutral lighting
	pass

func _set_dev_prop_path(value):
	dev_prop_path = value
	if Engine.editor_hint and is_inside_tree():
		if value != "":
			load_prop(value)
		else:
			unload_prop()

func _set_dev_take_screenshots(value):
	dev_take_screenshots = value
	if value and is_inside_tree():
		_dev_take_screenshots_sequence()

func _dev_take_screenshots_sequence():
	if not current_prop:
		printerr("[PropStage] No prop loaded!")
		dev_take_screenshots = false
		return

	print("[PropStage] Starting editor screenshot sequence...")
	
	# Create temporary viewport for deterministic capture
	var vp = Viewport.new()
	vp.size = Vector2(1280, 720)
	vp.own_world = true
	vp.transparent_bg = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(vp)
	
	# Clone Scene Content (Environment, Lights, Platform)
	for c in get_children():
		if c == vp: continue # Skip the viewport itself
		if c.name == "Camera": continue # Handled separately
		if c.name == "PropAnchor": continue # Handled separately
		if c is Viewport: continue
		
		# We want VisualInstances (Meshes, Lights), WorldEnvironment
		if c is WorldEnvironment or c is VisualInstance or c is Light:
			var dup = c.duplicate()
			vp.add_child(dup)
			
	# Add Camera
	var cam = Camera.new()
	if $Camera:
		cam.transform = $Camera.transform
		cam.projection = $Camera.projection
		cam.size = $Camera.size
		cam.fov = $Camera.fov
	else:
		cam.transform = Transform(Basis(), Vector3(0, 2.0, 4.5))
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	vp.add_child(cam)
	
	# Add Prop Copy
	var prop_name = "Prop"
	var p_copy = null
	
	if dev_prop_path != "":
		p_copy = load(dev_prop_path).instance()
		prop_name = dev_prop_path.get_file().get_basename()
	elif current_prop:
		# Try duplicating existing
		p_copy = current_prop.duplicate()
		prop_name = current_prop.name
	
	if not p_copy:
		printerr("[PropStage] Could not create prop copy.")
		vp.queue_free()
		dev_take_screenshots = false
		return
		
	# Center it
	if p_copy is Spatial:
		p_copy.transform = Transform.IDENTITY
		# PropAnchor logic: PropAnchor is at 0, 0.5, 0 usually.
		# But here we put it directly in VP.
		# If PropAnchor existed, we should match its offset?
		# PropAnchor y=0.5.
		# Physical placement
		if dev_snap_to_floor:
			var offset = _get_bottom_offset(p_copy)
			p_copy.transform.origin = Vector3(0, offset, 0)
		else:
			# Default legacy offset
			p_copy.transform.origin = Vector3(0, 0.5, 0)
		
	vp.add_child(p_copy)
	
	var states = {
		"0.0_start": 0.0,
		"0.5_mid": 0.5,
		"1.0_end": 1.0
	}
	
	var dir = Directory.new()
	var base_dir = "res://test_output/props/"
	if not dir.dir_exists(base_dir):
		dir.make_dir_recursive(base_dir)
	
	# Allow nodes to ready
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	
	for label in states.keys():
		var progress = states[label]
		# 1. Update State
		if "anim_progress" in p_copy:
			p_copy.anim_progress = progress
			
		if "is_active" in p_copy:
			# If we want to simulate activation
			if progress > 0.0:
				p_copy.is_active = true
			else:
				p_copy.is_active = false
			
		if p_copy.has_method("_update_visuals"):
			p_copy._update_visuals()
			
		# 2. Wait for physics/animation
		# If state is > 0.0, we probably want to see some elapsed time effect?
		if progress > 0.0:
			for _i in range(dev_tween_interval):
				yield (get_tree(), "idle_frame")
			
		yield (VisualServer, "frame_post_draw")
		yield (VisualServer, "frame_post_draw")
		
		# 3. Capture
		var tex = vp.get_texture()
		var img = tex.get_data()
		
		img.flip_y()
		var path = base_dir + "%s_%s.png" % [prop_name, label]
		img.save_png(path)
		print("[PropStage] Saved: ", path)
	
	print("[PropStage] Screenshot sequence finished.")
	
	# Cleanup
	p_copy.queue_free()
	vp.queue_free()
	dev_take_screenshots = false

	
func unload_prop():
	if not prop_anchor:
		return
	for c in prop_anchor.get_children():
		prop_anchor.remove_child(c)
		c.queue_free()
	current_prop = null
	_accumulated_wait_time = 0.0

func load_prop(path: String) -> void:
	unload_prop() # Ensure clean slate
	
	if not prop_anchor:
		printerr("[PropStage] PropAnchor node missing!")
		return
	
	_accumulated_wait_time = 0.0

	# Clear existing props (redundant but safe)
	for c in prop_anchor.get_children():
		prop_anchor.remove_child(c)
		c.queue_free()
	
	# yield (get_tree(), "physics_frame") # Wait for cleanup
	
	var scene = load(path)
	if not scene:
		printerr("[PropStage] Failed to load scene: ", path)
		return
		
	var instance = scene.instance()
	prop_anchor.add_child(instance)
	current_prop = instance
	
	# Center and reset
	if instance is Spatial:
		instance.transform = Transform.IDENTITY
		if dev_snap_to_floor:
			var offset = _get_bottom_offset(instance)
			instance.transform.origin = Vector3(0, offset, 0)
		else:
			instance.transform.origin = Vector3(0, 0.5, 0)
	
	# Reset state just in case
	if instance.has_method("restore_snapshot"):
		instance.restore_snapshot({
			"active": false,
			"used": false,
			"auto_triggered": false,
			"progress": 0.0,
			"target": 0.0
		})
	elif instance.has_method("set_active"):
		instance.set_active(false, true)

# --- Validation Helpers ---

func wait_visual_midpoint():
	var duration = 1.0
	if current_prop and "anim_duration" in current_prop:
		duration = current_prop.anim_duration
	
	# For Cubic Ease Out: 50% visual progress is at ~20.6% time
	# Formula: t = 1 - cbrt(1 - visual_target)
	# Target 0.5 -> t = 1 - cbrt(0.5) = 1 - 0.7937 = 0.2063
	var wait_t = duration * 0.21
	
	_accumulated_wait_time += wait_t
	return yield (get_tree().create_timer(wait_t), "timeout")

func wait_anim_completion():
	var duration = 1.0
	if current_prop and "anim_duration" in current_prop:
		duration = current_prop.anim_duration
		
	var remaining = duration - _accumulated_wait_time
	if remaining < 0:
		remaining = 0.0
	
	# Add a tiny buffer to ensure physics frame completion
	remaining += 0.1
	
	_accumulated_wait_time = 0.0 # Reset
	return yield (get_tree().create_timer(remaining), "timeout")

func _handle_set_command(inst: Dictionary) -> void:
	var var_name = inst.get("var", "")
	var value_str = str(inst.get("value", ""))
	
	if not current_prop:
		return

	# Type inference and setting
	if var_name in current_prop:
		# DEBUG PRINT
		print("[PropStage] Setting ", var_name, " to ", value_str, " on ", current_prop.name)
		
		var current_val = current_prop.get(var_name)
		var val_to_set = value_str
		
		if typeof(current_val) == TYPE_REAL:
			val_to_set = value_str.to_float()
		elif typeof(current_val) == TYPE_INT:
			val_to_set = value_str.to_int()
		elif typeof(current_val) == TYPE_BOOL:
			val_to_set = (value_str.to_lower() == "true")
			
		current_prop.set(var_name, val_to_set)

func _start_interaction():
	if current_prop and current_prop.has_method("interact"):
		current_prop.interact()

# --- Internal Screenshot Helpers ---

func _get_bottom_offset(node: Spatial) -> float:
	var aabb = _calculate_combined_aabb(node)
	if aabb.size.y == 0:
		return 0.5 # Fallback
	# The platform top is at Y=0.1 (height 0.2 centered at 0)
	# current position is 0. we want result bottom = 0.1
	# aabb.position.y is the relative bottom.
	# new_origin.y + aabb.position.y = 0.1
	return 0.1 - aabb.position.y

func _calculate_combined_aabb(node: Spatial) -> AABB:
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
			var child_aabb = _calculate_combined_aabb(child)
			if child_aabb.size != Vector3.ZERO:
				# Transform child AABB to this node's space
				var local_aabb = child.transform.xform(child_aabb)
				if not found:
					total_aabb = local_aabb
					found = true
				else:
					total_aabb = total_aabb.merge(local_aabb)
	
	return total_aabb
