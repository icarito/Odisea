extends SceneTree

func _init():
    print("DEBUG: Loading ElevatorProp.tscn...")
    var s = load("res://core_v2/props/ElevatorProp.tscn")
    if s:
        print("DEBUG: Instancing...")
        var i = s.instance()
        print("DEBUG: Instance created: ", i)
        print("DEBUG: Script: ", i.get_script())
        root.add_child(i)
        print("DEBUG: Added to tree.")
        # Force a frame
        print("DEBUG: Physics process...")
        i._physics_process(0.1)
        print("DEBUG: Done.")
    else:
        print("DEBUG: Failed to load.")
    quit()
