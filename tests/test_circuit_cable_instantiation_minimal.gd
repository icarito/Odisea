extends MainLoop

func _initialize_data():
    var cable_script = load("res://core_v2/systems/circuit/CircuitCable.gd")
    if not cable_script or not (cable_script is Script):
        print("ERROR: Unable to load or recognize CircuitCable.gd")
        OS.exit_code = 1
        return

    if cable_script.has_method("new"):
        var instance = cable_script.new()

        if instance:
            print("Success: Instantiation worked.")
            print("Instance class name:", instance.get_class())
        else:
            print("ERROR: CircuitCable.gd.new() returned null.")
    else:
        print("ERROR: CircuitCable.gd script has no .new() method.")

    OS.exit_code = 0
    return