tool
extends Spatial

# PropStage.gd
# Specialized environment for validating props functionality and visuals.
# Used by OYS commands LOAD_PROP and SCREENSHOT.

onready var spawn_point = $SpawnPoint
onready var camera = $Camera


var current_prop: Node = null
var _accumulated_wait_time: float = 0.0

export(String, FILE, "*.tscn") var dev_prop_path setget _set_dev_prop_path
export(bool) var dev_take_screenshots setget _set_dev_take_screenshots
export(bool) var dev_snap_to_floor = true
export(int) var dev_tween_interval = 20

func _ready():
	# Allow manual camera placement in the scene if desired.
	# Only force current if it exists.
	if camera:
		camera.make_current()

	
	# If prop path set (Editor or Runtime), load it
	if dev_prop_path != "" and current_prop == null:
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
		_run_validation_oys()
		# Reset toggle after starting (or let it stay, but usually buttons reset)
		dev_take_screenshots = false

func _run_validation_oys():
	print("[PropStage] Starting OYS Validation...")
	if dev_prop_path == "" and current_prop == null:
		printerr("[PropStage] No prop to validate.")
		return

	# Determine prop path (resolve from current_prop if strict OYS path needed?)
	# The OYS script uses $sys_env_prop_path.
	var prop_path = dev_prop_path
	if prop_path == "" and current_prop:
		prop_path = current_prop.filename
	
	if prop_path == "":
		printerr("[PropStage] Cannot determine prop path.")
		return
		
	var interpreter_script = load("res://core_v2/systems/OYS_Interpreter.gd")
	if not interpreter_script:
		printerr("[PropStage] Could not load OYS_Interpreter.gd")
		return
		
	var interpreter = interpreter_script.new(self)
	# interpreter.host_node = self # Handling in _init now
	interpreter.variables["$sys_env_prop_path"] = prop_path
	
	# Load validator script
	var f = File.new()
	var script_path = "res://core_v2/tests/prop_validator.oys"
	if f.open(script_path, File.READ) != OK:
		printerr("[PropStage] Could not load validator script: ", script_path)
		return
		
	var content = f.get_as_text()
	f.close()
	
	interpreter.parse(content)
	interpreter.run() # Async run

# Hook called by OYSInterpreter SCREENSHOT command
func take_oys_screenshot(label: String, prop_named_prefix: String) -> String:
	yield (get_tree(), "idle_frame") # Ensure sync
	
	print("[PropStage] Capturing clean screenshot: ", label)
	
	# Create temporary viewport for deterministic capture
	var vp = Viewport.new()
	vp.size = Vector2(1280, 720)
	vp.own_world = true
	vp.transparent_bg = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	# We must add VP to tree to render
	add_child(vp)
	
	# Clone Scene Content (Environment, Lights, Platform)
	for c in get_children():
		if c == vp: continue # Skip the viewport itself
		if c.name == "Camera": continue # Handled separately
		if c.name == "SpawnPoint": continue # Handled separately
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
		cam.near = $Camera.near
		cam.far = $Camera.far
	else:
		cam.transform = Transform(Basis(), Vector3(0, 2.0, 4.5))
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	vp.add_child(cam)
	
	# Add Current Prop Clone
	# We clone the *current state* of the prop
	if current_prop:
		var p_copy = current_prop.duplicate()
		vp.add_child(p_copy)
		# Ensure transform matches if it's not at origin?
		# PropStage logic places prop at SpawnPoint.
		# If we duplicate, it keeps transform relative to parent?
		# current_prop parent is SpawnPoint. p_copy parent is Viewport.
		# We need to apply SpawnPoint transform + prop transform?
		# SpawnPoint is usually at (0,0,0).
		
		if p_copy is Spatial:
			# Apply global transform of original to copy
			p_copy.global_transform = current_prop.global_transform
	
	# Wait for render
	yield (VisualServer, "frame_post_draw")
	yield (VisualServer, "frame_post_draw")
	
	var tex = vp.get_texture()
	var img = tex.get_data()
	img.flip_y()
	
	var dir = Directory.new()
	var base_dir = "res://test_output/props/"
	if not dir.dir_exists(base_dir):
		dir.make_dir_recursive(base_dir)
	
	# Use prop_named_prefix passed from OYS (resolved from prop.name)
	var path = base_dir + "%s_%s.png" % [prop_named_prefix, label]
	img.save_png(path)
	print("[PropStage] Saved: ", path)
	
	# Cleanup
	vp.queue_free()
	
	return path

	
func unload_prop():
	if not spawn_point:
		return
	for c in spawn_point.get_children():
		spawn_point.remove_child(c)
		c.queue_free()
	current_prop = null
	_accumulated_wait_time = 0.0

func load_prop(path: String) -> void:
	unload_prop() # Ensure clean slate
	
	if not spawn_point:
		printerr("[PropStage] SpawnPoint node missing!")
		return
	
	_accumulated_wait_time = 0.0

	# Clear existing props (redundant but safe)
	for c in spawn_point.get_children():
		spawn_point.remove_child(c)
		c.queue_free()
	
	# yield (get_tree(), "physics_frame") # Wait for cleanup
	
	var scene = load(path)
	if not scene:
		printerr("[PropStage] Failed to load scene: ", path)
		return
		
	var instance = scene.instance()
	spawn_point.add_child(instance)
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
