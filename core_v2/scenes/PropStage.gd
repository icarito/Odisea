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
export(bool) var dev_force_local_camera = false setget _set_dev_force_local_camera

func _ready():
    # Allow manual camera placement in the scene if desired.
    # Only force current if it exists.
    if camera:
        camera.make_current()

    if dev_force_local_camera:
        _enforce_local_camera()

    
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

func _set_dev_force_local_camera(value):
    dev_force_local_camera = value
    if value and is_inside_tree():
        _enforce_local_camera()

func _enforce_local_camera():
    if camera and not camera.current:
        camera.make_current()
    
    # Attempt to disable CinematicManager if present
    if has_node("/root/CinematicManager"):
        var cm = get_node("/root/CinematicManager")
        if cm.has_method("deactivate_rig"):
            cm.deactivate_rig()

    # Attempt to inhibit prop input modes (e.g. HoloTerminal focus)
    if current_prop and current_prop.has_method("set_input_mode_enabled"):
        current_prop.set_input_mode_enabled(false)
    elif current_prop and "is_focused" in current_prop:
        current_prop.set("is_focused", false)


func _process(_delta):
    # Continuous enforcement if enabled
    if dev_force_local_camera:
        if camera and not camera.current:
            camera.make_current()
        
        # Continuously suppress focus mode logic on current prop
        if current_prop:
            # 0. Disable capability entirely if supported
            if "allow_focus_mode" in current_prop:
                current_prop.set("allow_focus_mode", false)

            # 1. Generic input mode suppression
            if current_prop.has_method("set_input_mode_enabled"):
                current_prop.set_input_mode_enabled(false)
            
            # 2. Specific HoloTerminalV2 suppression
            var is_focused = false
            if current_prop.has_method("is_focused"):
                is_focused = current_prop.is_focused()
            elif "is_focused" in current_prop: # unlikely for method-based
                is_focused = current_prop.get("is_focused")
            elif "_is_focused" in current_prop:
                is_focused = current_prop.get("_is_focused")
                
            if is_focused:
                # Try calling clean exit first
                if current_prop.has_method("_exit_focus_mode"):
                    current_prop.call("_exit_focus_mode")
                elif current_prop.has_method("cancel_interaction"):
                    current_prop.cancel_interaction()
                else:
                    # Fallback to hard set
                    current_prop.set("_is_focused", false)
                    if current_prop.has_method("_update_ui_mode"):
                        current_prop.call("_update_ui_mode")

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
    var script_path = "res://core_v2/scripts/prop_validator.oys"
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
    var res_base = "res://test_output/props/"
    
    # Determine a robust prefix for the saved image. Prefer the OYS-provided
    # prop_named_prefix but fall back to the current_prop's filename or name so
    # the testing runner (which expects e.g. "CircuitCable_0_idle.png") finds
    # the files even if the interpreter passes an unexpected prefix.
    var prefix = prop_named_prefix
    if not prefix or prefix == "" or prefix == "prop" or prefix.begins_with("unknown"):
        if current_prop and current_prop.has_method("get") and current_prop.has_meta("filename"):
            prefix = current_prop.get_meta("filename")
        elif current_prop and "filename" in current_prop and current_prop.filename != "":
            prefix = current_prop.filename.get_file()
        elif current_prop and current_prop.name:
            prefix = current_prop.name
        else:
            prefix = "unknown"

    # Strip a common extension if present (e.g. "CircuitCable.tscn")
    if prefix.ends_with(".tscn"):
        prefix = prefix.substr(0, prefix.length() - 5)

    # Try to save using a res:// path (preferred). If that fails, fall back to
    # user://. We already ensured the underlying filesystem folder exists.
    # Prepare both the res:// and filesystem (globalized) paths
    var res_path = res_base + "%s_%s.png" % [prefix, label]
    var fs_res_base = ProjectSettings.globalize_path(res_base)
    # If globalize failed, try to derive from res:// root
    if fs_res_base == "":
        var res_root = ProjectSettings.globalize_path("res://")
        if res_root != "":
            fs_res_base = res_root.rstrip("/") + "/test_output/props/"
    
    var fs_res_path = ""
    if fs_res_base != "":
        if not fs_res_base.endswith("/"):
            fs_res_base += "/"
        fs_res_path = fs_res_base + "%s_%s.png" % [prefix, label]

    var saved_path = ""

    if fs_res_path != "":
        var err = img.save_png(fs_res_path)
        if err == OK:
            saved_path = fs_res_path
            print("[PropStage] Saved (fs res): ", fs_res_path)
        else:
            printerr("[PropStage] Failed to save to fs res path:", fs_res_path, "err=", err)

    # If saving to fs res failed, try res:// directly (Godot may accept it), then user:// as last resort
    if saved_path == "":
        var err2 = img.save_png(res_path)
        if err2 == OK:
            saved_path = res_path
            print("[PropStage] Saved (res://): ", res_path)
        else:
            printerr("[PropStage] Failed to save to res:// path:", res_path, "err=", err2, "-> trying user:// fallback")
            var user_base = "user://test_output/props/"
            var fs_user_base = ProjectSettings.globalize_path(user_base)
            if fs_user_base != "" and not dir.dir_exists(fs_user_base):
                dir.make_dir_recursive(fs_user_base)
            var user_path = user_base + "%s_%s.png" % [prefix, label]
            var err3 = img.save_png(user_path)
            if err3 == OK:
                saved_path = user_path
                print("[PropStage] Saved (user://): ", user_path)
            else:
                printerr("[PropStage] Failed to save screenshot to user:// as well: ", user_path, "err=", err3)

    # Final log: report the actual saved path (res:// preferred, user:// fallback)
    if saved_path != "":
        print("[PropStage] Final saved path: ", saved_path)
    else:
        printerr("[PropStage] No screenshot path available after save attempts.")

    # Cleanup
    vp.queue_free()

    return saved_path

    
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
    print("[PropStage] _start_interaction called, current_prop=", current_prop)
    if current_prop and current_prop.has_method("interact"):
        print("[PropStage] Calling interact on current_prop")
        current_prop.interact()
    else:
        print("[PropStage] current_prop has no interact method!")

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
