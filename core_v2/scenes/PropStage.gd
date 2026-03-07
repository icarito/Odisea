tool
extends Spatial

# PropStage.gd
# Specialized environment for validating props functionality and visuals.
# Used by OYS commands LOAD_PROP and SCREENSHOT.

onready var spawn_point = $SpawnPoint
onready var camera = $Camera


var current_prop: Node = null
var _accumulated_wait_time: float = 0.0
var _current_prop_path: String = ""
var _scene_cache := {}
var _instance_cache := {}
var _cache_root: Spatial = null

export(String, FILE, "*.tscn") var dev_prop_path setget _set_dev_prop_path
export(bool) var dev_take_screenshots setget _set_dev_take_screenshots
export(bool) var dev_snap_to_floor = true
export(int) var dev_tween_interval = 20
export(bool) var dev_force_local_camera = false setget _set_dev_force_local_camera
export(bool) var dev_reuse_prop_instances = true

func _ready():
    _ensure_cache_root()

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

func _exit_tree():
    _release_cached_instances()
    _scene_cache.clear()
    _cache_root = null

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
    if current_prop and not is_instance_valid(current_prop):
        current_prop = null
        return

    # Continuous enforcement if enabled
    if dev_force_local_camera:
        if camera and not camera.current:
            camera.make_current()
        
        # Continuously suppress focus mode logic on current prop
        if current_prop and is_instance_valid(current_prop):
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
        
    var interpreter = interpreter_script.new(self )
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
    yield (get_tree(), "idle_frame")
    
    print("[PropStage] Capturing clean screenshot: ", label)
    
    var vp = Viewport.new()
    vp.size = Vector2(1280, 720)
    vp.own_world = true
    vp.transparent_bg = true
    vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
    add_child(vp)
    
    for c in get_children():
        if c == vp: continue
        if c.name == "Camera": continue
        if c.name == "SpawnPoint": continue
        if c.name == "Pilot": continue
        if c is Viewport: continue
        
        if c is WorldEnvironment or c is VisualInstance or c is Light:
            var dup = c.duplicate()
            vp.add_child(dup)
            
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
    
    var prop_original_parent: Node = null
    var prop_original_transform: Transform = Transform()
    var prop_original_local_transform: Transform = Transform()
    var prop_original_parent_is_spatial := false
    var prop_was_camera_child := false
    var extra_capture_nodes: Array = []
    var pilot_original_parent: Node = null
    var pilot_original_transform: Transform = Transform()
    var pilot_node: Node = get_node_or_null("Pilot")
    
    if current_prop and is_instance_valid(current_prop):
        if current_prop.has_method("set_hud_attachment_suspended"):
            current_prop.call("set_hud_attachment_suspended", true)
        prop_original_parent = current_prop.get_parent()
        if prop_original_parent and prop_original_parent is Camera:
            prop_was_camera_child = true
        prop_original_transform = current_prop.global_transform
        if prop_original_parent and prop_original_parent is Spatial and current_prop is Spatial:
            prop_original_parent_is_spatial = true
            prop_original_local_transform = current_prop.transform
        if prop_original_parent:
            prop_original_parent.remove_child(current_prop)
        if prop_was_camera_child:
            cam.add_child(current_prop)
            if current_prop is Spatial:
                current_prop.transform = prop_original_local_transform
        else:
            vp.add_child(current_prop)

        if current_prop.has_method("get_capture_nodes"):
            var nodes = current_prop.call("get_capture_nodes")
            if typeof(nodes) == TYPE_ARRAY:
                for node in nodes:
                    if not (node is Spatial) or not is_instance_valid(node):
                        continue
                    var original_parent = node.get_parent()
                    var node_data = {
                        "node": node,
                        "parent": original_parent,
                        "global_transform": node.global_transform,
                        "local_transform": Transform.IDENTITY,
                        "parent_is_spatial": false,
                        "was_camera_child": original_parent != null and original_parent is Camera,
                    }
                    if original_parent and original_parent is Spatial:
                        node_data["parent_is_spatial"] = true
                        node_data["local_transform"] = node.transform
                    if original_parent:
                        original_parent.remove_child(node)

                    if node_data["was_camera_child"]:
                        cam.add_child(node)
                        node.transform = node_data["local_transform"]
                    else:
                        vp.add_child(node)
                        node.global_transform = node_data["global_transform"]
                    extra_capture_nodes.append(node_data)
    
    if pilot_node:
        pilot_original_parent = pilot_node.get_parent()
        pilot_original_transform = pilot_node.global_transform
        if pilot_original_parent:
            pilot_original_parent.remove_child(pilot_node)
        vp.add_child(pilot_node)
    
    yield (VisualServer, "frame_post_draw")
    yield (VisualServer, "frame_post_draw")
    
    var tex = vp.get_texture()
    var img = tex.get_data()
    img.flip_y()
    
    if current_prop and is_instance_valid(current_prop) and prop_original_parent:
        var capture_parent = current_prop.get_parent()
        if capture_parent:
            capture_parent.remove_child(current_prop)
        prop_original_parent.add_child(current_prop)
        if prop_original_parent_is_spatial and current_prop is Spatial:
            current_prop.transform = prop_original_local_transform
        else:
            current_prop.global_transform = prop_original_transform
        if current_prop.has_method("set_hud_attachment_suspended"):
            current_prop.call("set_hud_attachment_suspended", false)
    elif current_prop and is_instance_valid(current_prop) and current_prop.has_method("set_hud_attachment_suspended"):
        current_prop.call("set_hud_attachment_suspended", false)

    for node_data in extra_capture_nodes:
        var node = node_data.get("node", null)
        if not node or not is_instance_valid(node):
            continue
        var capture_parent = node.get_parent()
        if capture_parent:
            capture_parent.remove_child(node)
        var original_parent = node_data.get("parent", null)
        if original_parent and is_instance_valid(original_parent):
            original_parent.add_child(node)
            if node_data.get("parent_is_spatial", false):
                node.transform = node_data.get("local_transform", Transform.IDENTITY)
            else:
                node.global_transform = node_data.get("global_transform", Transform.IDENTITY)
    
    if pilot_node and pilot_original_parent:
        vp.remove_child(pilot_node)
        pilot_original_parent.add_child(pilot_node)
        pilot_node.global_transform = pilot_original_transform
    
    var dir = Directory.new()
    
    # Determine prefix from prop name
    var prefix = prop_named_prefix
    if not prefix or prefix == "" or prefix == "prop" or prefix.begins_with("unknown"):
        if current_prop and "filename" in current_prop and current_prop.filename != "":
            prefix = current_prop.filename.get_file()
        elif current_prop and current_prop.name:
            prefix = current_prop.name
        else:
            prefix = "unknown"
    if prefix.ends_with(".tscn"):
        prefix = prefix.substr(0, prefix.length() - 5)

    # Build filesystem path from project root
    var res_base = "res://test_output/props/"
    var fs_base = ProjectSettings.globalize_path(res_base)
    if fs_base == "":
        var res_root = ProjectSettings.globalize_path("res://")
        if res_root != "":
            fs_base = res_root.rstrip("/") + "/test_output/props/"
    
    if fs_base == "":
        printerr("[PropStage] ERROR: Cannot resolve filesystem path for screenshots")
        vp.queue_free()
        return ""

    if not fs_base.ends_with("/"):
        fs_base += "/"
    
    if not dir.dir_exists(fs_base):
        dir.make_dir_recursive(fs_base)
    
    var save_path = fs_base + "%s_%s.png" % [prefix, label]
    
    if has_node("/root/ScreenshotQueue"):
        var queue = get_node("/root/ScreenshotQueue")
        queue.enqueue_screenshot(img, save_path)
        print("[PropStage] Enqueued screenshot: ", save_path)
    else:
        var err = img.save_png(save_path)
        if err == OK:
            print("[PropStage] Saved (fs res): ", save_path)
            print("[PropStage] Final saved path: ", save_path)
        else:
            printerr("[PropStage] ERROR: Failed to save screenshot to: ", save_path, " err=", err)

    # Cleanup
    vp.queue_free()

    return save_path

    
func unload_prop():
    if current_prop and is_instance_valid(current_prop):
        if current_prop.has_method("set_hud_attachment_suspended"):
            current_prop.call("set_hud_attachment_suspended", true)
        if dev_reuse_prop_instances and _current_prop_path != "":
            _move_prop_to_cache(current_prop)
        else:
            _free_prop_instance(current_prop)

    if spawn_point:
        for c in spawn_point.get_children():
            if is_instance_valid(c):
                if dev_reuse_prop_instances and _is_cached_instance(c):
                    _move_prop_to_cache(c)
                else:
                    _free_prop_instance(c)

    current_prop = null
    _current_prop_path = ""
    _accumulated_wait_time = 0.0

func load_prop(path: String) -> void:
    if path == "":
        unload_prop()
        return

    if not spawn_point:
        printerr("[PropStage] SpawnPoint node missing!")
        return

    if current_prop and is_instance_valid(current_prop) and _current_prop_path == path and current_prop.get_parent() == spawn_point:
        _configure_prop_instance(current_prop)
        return

    unload_prop()
    
    _accumulated_wait_time = 0.0
    
    var instance = _get_or_instance_prop(path)
    if not instance:
        printerr("[PropStage] Failed to load scene: ", path)
        return

    var old_parent = instance.get_parent()
    if old_parent:
        old_parent.remove_child(instance)

    spawn_point.add_child(instance)
    current_prop = instance
    _current_prop_path = path

    if current_prop.has_method("set_hud_attachment_suspended"):
        current_prop.call("set_hud_attachment_suspended", false)

    _configure_prop_instance(instance)

func _configure_prop_instance(instance: Node) -> void:
    if instance is Spatial:
        instance.transform = Transform.IDENTITY
        if dev_snap_to_floor:
            var offset = _get_bottom_offset(instance)
            instance.transform.origin = Vector3(0, offset, 0)
        else:
            instance.transform.origin = Vector3(0, 0.5, 0)
    _reset_prop_runtime_state(instance)

func _reset_prop_runtime_state(instance: Node) -> void:
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

func _get_or_instance_prop(path: String) -> Node:
    if dev_reuse_prop_instances:
        var cached = _instance_cache.get(path, null)
        if cached and is_instance_valid(cached):
            return cached
        if cached and not is_instance_valid(cached):
            _instance_cache.erase(path)

    var scene = _get_cached_scene(path)
    if not scene:
        return null

    var instance = scene.instance()
    if dev_reuse_prop_instances:
        _instance_cache[path] = instance
    return instance

func _get_cached_scene(path: String):
    var cached = _scene_cache.get(path, null)
    if cached:
        return cached
    var scene = load(path)
    if scene:
        _scene_cache[path] = scene
    return scene

func _move_prop_to_cache(prop: Node) -> void:
    if not prop or not is_instance_valid(prop):
        return
    _ensure_cache_root()
    var parent = prop.get_parent()
    if parent:
        parent.remove_child(prop)
    _cache_root.add_child(prop)
    if prop is Spatial:
        prop.transform = Transform.IDENTITY

func _free_prop_instance(prop: Node) -> void:
    if not prop or not is_instance_valid(prop):
        return
    _forget_cached_instance(prop)
    var parent = prop.get_parent()
    if parent:
        parent.remove_child(prop)
    prop.queue_free()

func _forget_cached_instance(prop: Node) -> void:
    for key in _instance_cache.keys():
        if _instance_cache[key] == prop:
            _instance_cache.erase(key)
            return

func _is_cached_instance(prop: Node) -> bool:
    for cached in _instance_cache.values():
        if cached == prop:
            return true
    return false

func _ensure_cache_root() -> void:
    if _cache_root and is_instance_valid(_cache_root):
        return
    _cache_root = get_node_or_null("_PropCache")
    if _cache_root == null:
        _cache_root = Spatial.new()
        _cache_root.name = "_PropCache"
        add_child(_cache_root)
        _cache_root.owner = null

func _release_cached_instances() -> void:
    for prop in _instance_cache.values():
        if not prop or not is_instance_valid(prop):
            continue
        var parent = prop.get_parent()
        if parent:
            parent.remove_child(prop)
        prop.queue_free()
    _instance_cache.clear()

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
