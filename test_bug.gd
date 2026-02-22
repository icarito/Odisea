extends SceneTree

func _init():
    var prop_scene = load("res://core_v2/props/ElevatorProp.tscn")
    var prop = prop_scene.instance()
    var root = Spatial.new()
    root.add_child(prop)
    
    var btn = prop.get_node("Platform/Button_Internal")
    var ctrl = prop
    
    # We must add it to a tree to use process, but SceneTree root works?
    # Actually wait, let's just call _on_floor_request directly for testing
    
    print("Testing controller requests:")
    ctrl._ready()
    
    print("Requesting Next Floor")
    ctrl._on_floor_request(-1)
    
    print("Target floor: ", ctrl.target_floor, " Moving: ", ctrl.is_moving)
    print("Simulating arrival at floor 1...")
    ctrl._on_arrived(5.0)
    
    print("After arrival, Current floor: ", ctrl.current_floor)
    
    # Wait some time? Actually, yield will just suspend the function and the script finishes.
    # We can invoke _process_queue manually instead. Or skip the timer for test.
    print("Requesting Next Floor AGAIN")
    ctrl._on_floor_request(-1)
    
    print("Second Target floor: ", ctrl.target_floor, " Moving: ", ctrl.is_moving)
    quit()
