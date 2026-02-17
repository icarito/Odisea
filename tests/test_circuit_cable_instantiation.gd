extends SceneTree

func _ready():
    var output_file = File.new()
    output_file.open("user://test_output.log", File.WRITE)

    output_file.store_line("Testing direct instantiation of CircuitCable.gd...")

    var circuit_cable_script = load("res://core_v2/systems/circuit/CircuitCable.gd")
    if circuit_cable_script and circuit_cable_script is Script:
        output_file.store_line("Script loaded successfully.")
        if circuit_cable_script.has_method("new"):
            var cable_instance = circuit_cable_script.new()
            if cable_instance:
                output_file.store_line("CircuitCable.gd instantiation successful.")
                output_file.store_line("Instance properties:")
                for prop in cable_instance:
                    output_file.store_line(prop + ": " + str(cable_instance.get(prop)))
            else:
                output_file.store_line("CircuitCable.gd.new() returned null.")
        else:
            output_file.store_line("CircuitCable.gd script has no .new() method.")
    else:
        output_file.store_line("Failed to load CircuitCable.gd as a Script.")

    output_file.close()
    quit()